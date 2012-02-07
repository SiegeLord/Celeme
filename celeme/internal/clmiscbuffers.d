/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2011 Pavel Sountsov

Celeme is free software: you can redistribute it and/or modify
it under the terms of the Lesser GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Celeme is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Celeme. If not, see <http:#www.gnu.org/licenses/>.
*/

module celeme.internal.clmiscbuffers;

import celeme.internal.frontend;
import celeme.internal.clcore;
import celeme.internal.util;

import opencl.cl;
import dutil.Disposable;

import tango.core.Traits;
import tango.text.convert.Format;
import tango.text.Util;

private struct SValueHolder(T)
{
	cstring Name;
	T DefaultValue;
}

class CMultiBuffer(T) : CDisposable
{
	this(cstring prefix, size_t n, size_t count, bool read = true, bool write = true)
	{
		assert(n == 1 || n == 2 || n == 4, "N must be 1, 2 or 4");
		
		N = n;
		Prefix = prefix;
		Count = count;
		Read = read;
		Write = write;
	}
	
	void AddValue(CCLCore core, cstring name, T default_value)
	{
		if(HaveValue(name))
			throw new Exception("'" ~ name.idup ~ "' is already present in this multi buffer");
		
		Registry[name] = Values.length;
		Values ~= SValueHolder!(T)(name, default_value);
		
		if(Buffers.length * N < Values.length)
		{
			Buffers.length = Buffers.length + 1;
			Buffers[$-1] = core.CreateBuffer!(T)(Count * N, Read, Write);
		}
	}
	
	size_t* HaveValue(cstring name)
	{
		return name in Registry;
	}
	
	T opIndexAssign(T val, cstring name)
	{
		auto idx_ptr = HaveValue(name);
		assert(idx_ptr);
		return Values[*idx_ptr].DefaultValue = val;
	}
	
	T opIndex(cstring name)
	{
		auto idx_ptr = HaveValue(name);
		assert(idx_ptr);
		return Values[*idx_ptr].DefaultValue;
	}
	
	T opIndexAssign(T val, cstring name, size_t idx)
	{
		auto idx_ptr = HaveValue(name);
		assert(idx_ptr);
		
		/* Buffer index */
		auto buf_idx = (*idx_ptr) / N;
		/* Where the thing is inside the buffer */
		auto val_idx = idx * N + (*idx_ptr) % N;
		
		return Buffers[buf_idx][val_idx] = val;
	}
	
	T opIndex(cstring name, size_t idx)
	{
		auto idx_ptr = HaveValue(name);
		assert(idx_ptr);
		
		/* Buffer index */
		auto buf_idx = (*idx_ptr) / N;
		/* Where the thing is inside the buffer */
		auto val_idx = idx * N + (*idx_ptr) % N;
		
		return Buffers[buf_idx][val_idx];
	}
	
	void Reset()
	{
		foreach(buf_idx, buf; Buffers)
		{
			auto arr = buf.MapWrite();
			scope(exit) buf.UnMap();
			
			foreach(arr_idx, ref val; arr)
			{
				/* Which value it is */
				auto idx = arr_idx % N + buf_idx * N;
				if(idx < Values.length)
					val = Values[idx].DefaultValue;
			}
		}
	}
	
	override
	void Dispose()
	{
		foreach(buf; Buffers)
			buf.Dispose();
		super.Dispose();
	}
	
	@property
	cstring ArgsCode()
	{
		char[] ret;
		foreach(buf_idx, buf; Buffers)
		{
			ret ~= Format("__global $type$$num$* _$prefix$_{0}_buf,\n", buf_idx);
		}
		
		ret = ret.substitute("$type$", T.stringof);
		ret = ret.substitute("$num$", Format("{}", N));
		ret = ret.substitute("$prefix$", Prefix);
		
		return ret;
	}
	
	@property
	cstring LoadCode()
	{
		char[] ret;
		foreach(buf_idx, buf; Buffers)
		{
			ret ~= Format("$type$$num$ _$prefix$_{0} = _$prefix$_{0}_buf[i];\n", buf_idx);
			foreach(tuple_idx; range(N))
			{
				auto val_idx = buf_idx * N + tuple_idx;
				if(val_idx < Values.length)
					ret ~= Format("$type$ {1} = _$prefix$_{0}.s{2};\n", buf_idx, Values[val_idx].Name, tuple_idx);
			}
			ret ~= "\n";
		}
		
		ret = ret.substitute("$type$", T.stringof);
		ret = ret.substitute("$num$", Format("{}", N));
		ret = ret.substitute("$prefix$", Prefix);
		
		return ret;
	}
	
	@property
	cstring SaveCode()
	{
		char[] ret;
		
		foreach(buf_idx, buf; Buffers)
		{
			ret ~= Format("_$prefix$_{0}_buf[i] = ($type$$num$)(", buf_idx);
			foreach(tuple_idx; range(N))
			{
				auto val_idx = buf_idx * N + tuple_idx;
				auto name = val_idx < Values.length ? Values[val_idx].Name : "0";
				ret ~= Format("{0}{1}", tuple_idx == 0 ? "" : ", ", name);
			}
			ret ~= ");\n";
		}
		
		ret = ret.substitute("$type$", T.stringof);
		ret = ret.substitute("$num$", Format("{}", N));
		ret = ret.substitute("$prefix$", Prefix);
		
		return ret;
	}
	
	size_t SetArgs(CCLKernel kernel, size_t start_arg)
	{
		foreach(buf; Buffers)
			kernel.SetGlobalArg(start_arg++, buf);
			
		return start_arg;
	}
	
	@property
	size_t length()
	{
		return Buffers.length;
	}
private:
	cstring Prefix;
	CCLBuffer!(T)[] Buffers;
	SValueHolder!(T)[] Values;
	size_t[char[]] Registry;
	size_t Count;
	size_t N;
	bool Read = true;
	bool Write = true;
}

class CValueBuffer(T) : CDisposable
{
	this(CValue val, CCLCore core, size_t count)
	{
		DefaultValue = val.Value;
		Buffer = core.CreateBuffer!(T)(count, true, !val.ReadOnly);
	}
	
	double opAssign(double val)
	{
		return DefaultValue = val;
	}
	
	override
	void Dispose()
	{
		Buffer.Dispose();
		super.Dispose();
	}
		
	CCLBuffer!(T) Buffer;	
	double DefaultValue;
}

class CSynGlobalBuffer(T) : CDisposable
{
	this(CValue val, CCLCore core, size_t num_syn)
	{
		DefaultValue = val.Value;
		Buffer = core.CreateBuffer!(T)(num_syn, true, !val.ReadOnly);
	}
	
	override
	void Dispose()
	{
		Buffer.Dispose();
		super.Dispose();
	}
	
	CCLBuffer!(T) Buffer;
	double DefaultValue;
}

class CEventSourceBuffer : CDisposable
{
	this(CCLCore core, int nrn_count)
	{
		FreeIdx = core.CreateBuffer!(int)(nrn_count);
		FreeIdx[] = 0;
	}
	
	override
	void Dispose()
	{
		FreeIdx.Dispose();
		super.Dispose();
	}
	
	/* Last free index */
	CCLBuffer!(int) FreeIdx;
}

class CSynapseBuffer : CDisposable
{
	this(CCLCore core, int offset, int count, int nrn_count)
	{
		FreeIdx = core.CreateBuffer!(int)(nrn_count);
		FreeIdx[] = 0;
		SlotOffset = offset;
		Count = count;
	}

	override
	void Dispose()
	{
		FreeIdx.Dispose();
		super.Dispose();
	}
	/* Last free index */
	CCLBuffer!(int) FreeIdx;
	int SlotOffset;
	int Count;
}

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

module celeme.clmiscbuffers;

import celeme.frontend;
import celeme.clcore;

import opencl.cl;

class CValueBuffer(T)
{
	this(CValue val, CCLCore core, size_t count)
	{
		DefaultValue = val.Value;
		Buffer = core.CreateBufferEx!(T)(count);
	}
	
	double opAssign(double val)
	{
		return DefaultValue = val;
	}
	
	void Release()
	{
		Buffer.Release();
	}
		
	CCLBuffer!(T) Buffer;	
	double DefaultValue;
}

class CSynGlobalBuffer(T)
{
	this(CValue val, CCLCore core, size_t num_syn)
	{
		DefaultValue = val.Value;
		Buffer = core.CreateBufferEx!(T)(num_syn);
	}
	
	void Release()
	{
		Buffer.Release();
	}
	
	CCLBuffer!(T) Buffer;
	double DefaultValue;
}

class CEventSourceBuffer
{
	this(CCLCore core, int nrn_count)
	{
		FreeIdx = core.CreateBufferEx!(int)(nrn_count);
		FreeIdx[] = 0;
	}
	
	void Release()
	{
		FreeIdx.Release();
	}
	
	/* Last free index */
	CCLBuffer!(int) FreeIdx;
}

class CSynapseBuffer
{
	this(CCLCore core, int offset, int count, int nrn_count)
	{
		FreeIdx = core.CreateBufferEx!(int)(nrn_count);
		FreeIdx[] = 0;
		SlotOffset = offset;
		Count = count;
	}
	
	void Release()
	{
		FreeIdx.Release();
	}
	/* Last free index */
	CCLBuffer!(int) FreeIdx;
	int SlotOffset;
	int Count;
}

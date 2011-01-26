/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2011 Pavel Sountsov

Celeme is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Celeme is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Celeme. If not, see <http:#www.gnu.org/licenses/>.
*/

module celeme.alignedarray;

import tango.stdc.string;
import tango.stdc.stdint;

import tango.io.Stdout;

struct SAlignedArray(T, int N)
{
	T opCatAssign(T val)
	{
		length = length + 1;
		return opIndexAssign(val, length - 1);
	}
	
	T opIndex(size_t idx)
	{
		return ptr[idx];
	}
	
	T opIndexAssign(T val, size_t idx)
	{
		return ptr[idx] = val;
	}
	
	T* ptr()
	{
		return cast(T*)(Data.ptr + Offset);
	}
	
	size_t length()
	{
		return Length;
	}
	
	int opApply(int delegate(ref T value) dg)
	{
		foreach(val; ptr[0..Length])
		{
			if(int ret = dg(val))
				return ret;
		}
		return 0;
	}
	
	void length(size_t new_length)
	{
		auto new_data_len = new_length * T.sizeof + N;
		if(new_data_len > Data.length)
		{
			/* Allocate extra for the offset */
			auto new_data = new char[](new_data_len);
			auto new_offset = N - (cast(intptr_t)new_data.ptr % N);
			
			memcpy(new_data.ptr + new_offset, ptr, Length * T.sizeof);
			
			Data.length = 0;
			Data = new_data;
			Offset = new_offset;
		}
		Length = new_length;
	}
	
	char[] Data;
	size_t Length = 0;
	size_t Offset = 0;
}

unittest
{
	/* Test an odd alignment to make sure it works */
	const N = 7;
	SAlignedArray!(double, N) arr;
	arr.length = 1;
	assert(arr.ptr !is null);
	arr[0] = 5.0;
	assert(cast(intptr_t)arr.ptr % N == 0);
	/* Check that we can size down and up, and not change the pointer */
	auto old_ptr = arr.ptr;
	arr.length = 0;
	arr.length = 1;
	assert(arr.ptr is old_ptr);
	
	/* Check the resizing that does move the memory */
	arr[0] = 5.0;
	arr.length = 2;
	assert(arr.ptr !is old_ptr);
	/* Check to see that the resize went okay */
	assert(arr[0] == 5.0);
	
	arr[1] = 6.0;
	arr.length = 3;
	assert(arr[0] == 5.0);
	assert(arr[1] == 6.0);
}

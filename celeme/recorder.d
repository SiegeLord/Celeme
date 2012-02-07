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

module celeme.recorder;

import celeme.internal.util;

import tango.io.Stdout;
import tango.stdc.stdlib;

struct SCArray(T)
{
	T[] opSlice()
	{
		return ptr[0..length];
	}
	
	T[] opSlice(size_t start, size_t end)
	{
		return ptr[start..end];
	}
	
	T opIndex(size_t idx)
	{
		return ptr[idx];
	}
	
	T opIndexAssign(T val, size_t idx)
	{
		return ptr[idx] = val;
	}
	
	@property
	size_t length()
	{
		return Length;
	}
	
	@property
	size_t length(size_t new_len)
	{
		if(new_len != Length)
		{
			ptr = cast(T*)realloc(ptr, new_len * T.sizeof);
			if(new_len)
				assert(ptr);
			
			Length = new_len;
		}
		
		return Length;
	}
	
	T* ptr;
	size_t Length;
}

unittest
{
	SCArray!(int) array;
	assert(array.length == 0);
	
	array.length = 5;
	assert(array.length == 5);
	
	array[0] = 1;
	array[4] = 2;
	assert(array[0] == 1);
	assert(array[4] == 2);
	
	array.length = 10;
	assert(array[0] == 1);
	assert(array[4] == 2);
	
	array.length = 0;
}

/**
 * This class holds the time, tags and data poins. Essentially this is a growable
 * quad of arrays.
 */
class CRecorder
{
	this(cstring name = "", bool store_neuron_id = false)
	{
		Name = name;
		StoreNeuronId = store_neuron_id;
	}
	
	~this()
	{
		Detach();
	}
	
	void Detach()
	{
		Length = 0;
		TArray.length = DataArray.length = TagArray.length = 0;
	}
	
	void AddDatapoint(double t, double data, int tag, size_t neuron_id = 0)
	{
		if(Length >= TArray.length)
		{
			TArray.length = cast(int)((Length + 1) * 1.5);
			TagArray.length = DataArray.length = TArray.length;
			if(StoreNeuronId)
				NeuronIdArray.length = TArray.length;
		}
		TArray[Length] = t;
		DataArray[Length] = data;
		TagArray[Length] = tag;
		if(StoreNeuronId)
			NeuronIdArray[Length] = neuron_id;
		Length++;
	}
	
	/**
	 * Returns the time array.
	 */
	@property
	double[] T()
	{
		return TArray[0..Length];
	}
	
	/**
	 * Returns the data array.
	 */
	@property
	double[] Data()
	{
		return DataArray[0..Length];
	}
	
	/**
	 * Returns the tag array.
	 */
	@property
	int[] Tags()
	{
		return TagArray[0..Length];
	}
	
	/**
	 * Returns the neuron id array (if any).
	 */
	@property
	size_t[] NeuronIds()
	{
		if(StoreNeuronId)
			return NeuronIdArray[0..Length];
		else
			return null;
	}
	
	SCArray!(double) TArray;
	SCArray!(int) TagArray;
	SCArray!(size_t) NeuronIdArray;
	SCArray!(double) DataArray;
	
	/**
	 * Name of this recorder, specifying what it was recording.
	 */
	cstring Name;
	
	/**
	 * The length of the recorded data
	 */
	size_t Length = 0;
	
protected:
	bool StoreNeuronId = false;
}

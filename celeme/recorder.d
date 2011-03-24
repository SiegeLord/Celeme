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

import tango.io.Stdout;

/**
 * This class holds the time, tags and data poins. Essentially this is a growable
 * triplet of arrays.
 */
class CRecorder
{
	this(char[] name = "", bool store_neuron_id = false)
	{
		Name = name;
		StoreNeuronId = false;
	}
	
	void Detach()
	{
		Length = 0;
		TArray.length = DataArray.length = TagArray.length = 0;
	}
	
	void AddDatapoint(double t, double data, int tag, int neuron_id = 0)
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
	double[] T()
	{
		return TArray[0..Length];
	}
	
	/**
	 * Returns the data array.
	 */
	double[] Data()
	{
		return DataArray[0..Length];
	}
	
	/**
	 * Returns the tag array.
	 */
	int[] Tags()
	{
		return TagArray[0..Length];
	}
	
	/**
	 * Returns the neuron id array (if any).
	 */
	int[] NeuronIds()
	{
		if(StoreNeuronId)
			return NeuronIdArray[0..Length];
		else
			return null;
	}
	
	double[] TArray;
	int[] TagArray;
	int[] NeuronIdArray;
	double[] DataArray;
	
	/**
	 * Name of this recorder, specifying what it was recording.
	 */
	char[] Name;
	
	/**
	 * The length of the recorded data
	 */
	size_t Length = 0;
	
protected:
	bool StoreNeuronId = false;
}

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

module celeme.celeme_util;

import dutil.Array;

import celeme.ineurongroup;

/**
 * A structure to hold time and data points.
 */
struct SData
{	
	void AddDatapoint(double t, double data)
	{
		if(Length >= TArray.length)
		{
			TArray.length = cast(int)((Length + 1) * 1.5);
			DataArray.length = TArray.length;
		}
		TArray[Length] = t;
		DataArray[Length] = data;
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
	
	double[] TArray;
	double[] DataArray;
	/**
	 * The length of the recorded data
	 */
	size_t Length = 0;
}

/**
 * Given a recorder it decodes and extracts the datasets in it.
 * 
 * Params:
 *     recoder = Data recorder
 * Returns:
 *     A double assosiative array of SData structures. First key is the neuron idx, second key is tag.
 */
SData[int][size_t] ExtractData(SArray!(SDataPoint) array)
{
	SData[int][size_t] ret;
	
	foreach(ii, datapoint; array[])
	{
		auto time = datapoint.T;
		auto data = datapoint.Data;
		auto tag = datapoint.Tag;
		auto neuron_id = datapoint.NeuronIdx;
		
		auto tag_array_ptr = neuron_id in ret;
		if(tag_array_ptr is null)
		{
			SData d;
			d.AddDatapoint(time, data);
			ret[neuron_id][tag] = d;
			continue;
		}
		
		auto data_ptr = tag in *tag_array_ptr;
		if(data_ptr is null)
		{
			SData d;
			d.AddDatapoint(time, data);
			(*tag_array_ptr)[tag] = d;
			continue;
		}
		
		data_ptr.AddDatapoint(time, data);
	}
	
	return ret;
}

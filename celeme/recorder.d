/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2012 Pavel Sountsov

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

import dutil.Array;

package struct SDataPoint
{
	double T;
	double Data;
	int Flags;
	size_t NeuronIdx;
}

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
	
	/**
	 * The length of the recorded data
	 */
	size_t Length = 0;
protected:
	double[] TArray;
	double[] DataArray;
}

/**
 * Stores data recorded from a single neuron group.
 */
class CRecorder
{
	/**
	 * Return a map of data sets (keyed by the neuron index) that were recorded with particular flag. Returns NULL if there are no recordings for this flag.
	 */
	SData[size_t] opIndex(int flags)
	{
		auto ptr = flags in AllData;
		return ptr is null ? null : *ptr;
	}
	
	void ParseData(SArray!(SDataPoint) datapoints)
	{
		foreach(datapoint; datapoints)
		{
			auto time = datapoint.T;
			auto data = datapoint.Data;
			auto flags = datapoint.Flags;
			auto neuron_idx = datapoint.NeuronIdx;
			
			auto data_array_ptr = flags in AllData;
			if(data_array_ptr is null)
			{
				SData d;
				d.AddDatapoint(time, data);
				AllData[flags][neuron_idx] = d;
				continue;
			}
			
			auto data_ptr = neuron_idx in *data_array_ptr;
			if(data_ptr is null)
			{
				SData d;
				d.AddDatapoint(time, data);
				(*data_array_ptr)[neuron_idx] = d;
				continue;
			}
			
			data_ptr.AddDatapoint(time, data);
		}
	}
protected:
	SData[size_t][int] AllData;
}

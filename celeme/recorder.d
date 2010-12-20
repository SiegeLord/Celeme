module celeme.recorder;

import tango.io.Stdout;

/**
 * This class holds the time and data poins. Essentially this is a growable
 * pair of arrays.
 */
class CRecorder
{
	this(char[] name = "")
	{
		Name = name;
	}
	
	void Detach()
	{
		Length = 0;
		TArray.length = DataArray.length = 0;
	}
	
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
	
	double[] TArray;
	double[] DataArray;
	
	/**
	 * Name of this recorder, specifying what it was recording.
	 */
	char[] Name;
	
	/**
	 * The length of the recorded data
	 */
	size_t Length = 0;
}

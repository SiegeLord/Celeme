module celeme.recorder;

import tango.io.Stdout;

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
	
	double[] T()
	{
		return TArray[0..Length];
	}
	
	double[] Data()
	{
		return DataArray[0..Length];
	}
	
	double[] TArray;
	double[] DataArray;
	
	char[] Name;
	size_t Length = 0;
}

module celeme.recorder;

import tango.io.Stdout;

class CRecorder
{
	this(int neuron_id, char[] name)
	{
		NeuronId = neuron_id;
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
			//Stdout(NeuronId, TArray.length).nl;
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
	
	int NeuronId;
	char[] Name;
	size_t Length = 0;
}

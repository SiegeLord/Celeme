module recorder;

class CRecorder
{
	this(int neuron_id, char[] name)
	{
		NeuronId = neuron_id;
		Name = name;
	}
	
	void Detach()
	{
		Valid = false;
	}
	
	void AddDatapoint(double t, double data)
	{
		T ~= t;
		Data ~= data;
	}
	
	double[] T;
	double[] Data;
	
	int NeuronId;
	char[] Name;
	bool Valid = true;
}

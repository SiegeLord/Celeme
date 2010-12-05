module celeme.ineurongroup;

import celeme.recorder;

interface INeuronGroup
{
	double opIndex(char[] name);
	double opIndexAssign(double val, char[] name);
	double opIndex(char[] name, int idx);
	double opIndexAssign(double val, char[] name, int idx);
	double opIndex(char[] name, int nrn_idx, int syn_idx);
	double opIndexAssign(double val, char[] name, int nrn_idx, int syn_idx);
	
	CRecorder Record(int neuron_id, char[] name);
	CRecorder RecordEvents(int neuron_id, int thresh_id);
	void StopRecording(int neuron_id);
	
	void MinDt(double min_dt);
	double MinDt();
	int Count();
}

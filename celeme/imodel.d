module celeme.imodel;

import celeme.clmodel;
import celeme.frontend;
import celeme.ineurongroup;

IModel CreateCLModel(float_t)(bool gpu = false)
{
	return new CCLModel!(float_t)(gpu);
}

interface IModel
{
	void Initialize();
	void Shutdown();
	
	void AddNeuronGroup(CNeuronType type, int number, char[] name = null, bool adaptive_dt = true);
	void Generate(bool parallel_delivery = true, bool atomic_delivery = true, bool initialize = true);
	
	INeuronGroup opIndex(char[] name);
	
	void Run(int num_timesteps);
	void ResetRun();
	void InitRun();
	void RunUntil(int num_timesteps);
	
	void SetConnection(char[] src_group, int src_nrn_id, int src_event_source, int src_slot, char[] dest_group, int dest_nrn_id, int dest_syn_type, int dest_slot);
	bool Connect(char[] src_group, int src_nrn_id, int src_event_source, char[] dest_group, int dest_nrn_id, int dest_syn_type);
	void Connect(char[] connector_name, int multiplier, char[] src_group, int[2] src_nrn_range, int src_event_source, char[] dest_group, int[2] dest_nrn_range, int dest_syn_type, double[char[]] args = null);
	
	double TimeStepSize();
	void TimeStepSize(double val);
}

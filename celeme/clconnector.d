module celeme.clconnector;

import celeme.frontend;
import celeme.util;
import celeme.clcore;
import celeme.clneurongroup;

const ConnectorTemplate = 
`
__kernel void $connector_name$_connect
	(
		$connector_args$
		$random_state_args$
		const int src_count,
		__global int* event_source_idxs,
		const int dest_count,
		__global int* dest_syn_idxs
	)
{
	int i = get_global_id(0);
	int src_id = 0;
	
	/* Choose source id */
$choose_src_code$
	/* Load random state */
$load_rand_state$
	/* Connector code */
$connector_code$
	/* Save random state */
$save_rand_state$
}
`; 

class CCLConnector(float_t)
{
	this(CNeuronGroup!(float_t) group, CConnector conn)
	{
		Group = group;
		Name = conn.Name;
		
		foreach(val; conn.Constants)
		{
			ConstantRegistry[val.Name] = Constants.length;
			
			Constants ~= val.Value;
		}
		
		CreateKernel(conn);
	}
	
	void Initialize()
	{
		
	}
	
	void CreateKernel(CConnector conn)
	{
		
	}
	
	double opIndex(char[] name)
	{
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			return Constants[*idx_ptr];
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	double opIndexAssign(double val, char[] name)
	{	
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			Constants[*idx_ptr] = val;
			if(Model.Initialized)
				SetConstant(*idx_ptr);
			return val;
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	char[] Name;
	double[] Constants;
	int[char[]] ConstantRegistry;
	
	char[] KernelCode;
	CNeuronGroup!(float_t) Group;
}

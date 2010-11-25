module celeme.integrator;

import celeme.clneurongroup;
import celeme.frontend;
import celeme.clcore;
import celeme.sourceconstructor;

class CIntegrator(float_t)
{
	this(CNeuronGroup!(float_t) group, CNeuronType type)
	{
		Group = group;
	}
	
	int SetArgs(int arg_id)
	{
		return arg_id;
	}
	
	void Reset()
	{
		
	}
	
	char[] GetLoadCode(CNeuronType type)
	{
		return "";
	}
	
	char[] GetSaveCode(CNeuronType type)
	{
		return "";
	}
	
	char[] GetArgsCode(CNeuronType type)
	{
		return "";
	}
	
	char[] GetIntegrateCode(CNeuronType type)
	{
		return "";
	}
	
	char[] GetPostThreshCode(CNeuronType type)
	{
		return "";
	}
	
	void SetDt(double dt)
	{
		
	}
	
	void Shutdown()
	{
		
	}
	
	CNeuronGroup!(float_t) Group;
}

class CAdaptiveIntegrator(float_t) : CIntegrator!(float_t)
{
	this(CNeuronGroup!(float_t) group, CNeuronType type)
	{
		super(group, type);
	}
	
	void SetTolerance(char[] state, double tolerance)
	{
		
	}
}

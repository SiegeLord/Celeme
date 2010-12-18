/* 
 * A module describing the base integrator classes. These classes
 * generate code for the kernel, taking care of the integration needs.
 */

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
	
	/*
	 * Will set the arguments of the integrator (it assumes the StepKernel is used)
	 * Returns the updated arg_id.
	 */
	int SetArgs(int arg_id)
	{
		return arg_id;
	}
	
	/*
	 * Resets whatever internal buffers are used.
	 */
	void Reset()
	{
		
	}
	
	/*
	 * Returns the load code for the kernel.
	 */
	char[] GetLoadCode(CNeuronType type)
	{
		return "";
	}
	
	/*
	 * Returns the save code for the kernel.
	 */
	char[] GetSaveCode(CNeuronType type)
	{
		return "";
	}
	
	/*
	 * Returns the args code for the kernel.
	 */
	char[] GetArgsCode(CNeuronType type)
	{
		return "";
	}
	
	/*
	 * Returns the actual integration code for the kernel.
	 */
	char[] GetIntegrateCode(CNeuronType type)
	{
		return "";
	}
	
	/*
	 * Returns the code that should be called after a threshold is reached.
	 */
	char[] GetPostThreshCode(CNeuronType type)
	{
		return "";
	}
	
	/*
	 * Sets the dt of the integrator (what this means depends on the integrator).
	 */
	void SetDt(double dt)
	{
		
	}
	
	/*
	 * Destroys any buffers associated with this integrator.
	 */
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
	
	/*
	 * Adaptive integrators have tolerances associated with states
	 */
	void SetTolerance(char[] state, double tolerance)
	{
		
	}
}

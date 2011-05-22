/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2011 Pavel Sountsov

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

/* 
 * A module describing the base integrator classes. These classes
 * generate code for the kernel, taking care of the integration needs.
 */

module celeme.internal.integrator;

import celeme.internal.iclneurongroup;
import celeme.internal.frontend;
import celeme.internal.clcore;
import celeme.internal.sourceconstructor;

class CIntegrator(float_t)
{
	this(ICLNeuronGroup group, CNeuronType type)
	{
		Group = group;
	}
	
	/*
	 * Will set the arguments of the integrator (it assumes the StepKernel is used)
	 * Returns the updated arg_id.
	 */
	int SetArgs(CCLKernel kernel, int arg_id)
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
	
	ICLNeuronGroup Group;
}

class CAdaptiveIntegrator(float_t) : CIntegrator!(float_t)
{
	this(ICLNeuronGroup group, CNeuronType type)
	{
		super(group, type);
	}
	
	/*
	 * Adaptive integrators have tolerances associated with states
	 */
	void SetTolerance(CCLKernel kernel, char[] state, double tolerance)
	{
		
	}
}

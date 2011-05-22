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
 * A simple fixed timestep Heun integrator.
 */

module celeme.internal.heun;

import celeme.internal.iclneurongroup;
import celeme.internal.frontend;
import celeme.internal.integrator;
import celeme.internal.sourceconstructor;
import celeme.internal.util;
import celeme.internal.clcore;

import opencl.cl;

import tango.io.Stdout;

class CHeun(float_t) : CIntegrator!(float_t)
{
	this(ICLNeuronGroup group, CNeuronType type)
	{
		super(group, type);
	}
	
	override
	char[] GetLoadCode(CNeuronType type)
	{
		return "_dt = _dt_const;";
	}
	
	override
	char[] GetSaveCode(CNeuronType type)
	{
		return "";
	}
	
	override
	int SetArgs(CCLKernel kernel, int arg_id)
	{
		SetDt(kernel, Group.MinDt);		
		return arg_id + 1;
	}
	
	void SetDt(CCLKernel kernel, double dt)
	{
		int parts = cast(int)(Group.TimeStepSize / dt + 0.5);
		if(parts == 0)
			parts++;

		kernel.SetGlobalArg(Group.IntegratorArgOffset, cast(float_t)(Group.TimeStepSize / parts));
	}
	
	override
	char[] GetArgsCode(CNeuronType type)
	{
		return "const $num_type$ _dt_const,";
	}
	
	override
	char[] GetIntegrateCode(CNeuronType type)
	{
		scope source = new CSourceConstructor();

		auto eval_source = type.GetEvalSource();
		
		char[] kernel_source = 
"
/* Declare temporary storage for state*/
$declare_temp_states$

/* First derivative stage */
$declare_derivs_1$

/* Second derivative stage */
$declare_derivs_2$

/* Compute the first derivatives */
$compute_derivs_1$

/* Compute the first state estimate */
$apply_derivs_1$

/* Compute the derivatives again */
$compute_derivs_2$

/* Compute the final state estimate */
$apply_derivs_2$

/* Transfer the state from the temporary storage to the real storage */
$reset_state$

/* Advance time*/
_cur_time += _dt;
".dup;
		/* Declare temp states */
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ _" ~ name ~ "_0 = " ~ name ~ ";";
		}
		source.Inject(kernel_source, "$declare_temp_states$");
		
		/* Declare derivs 1 */
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ _d" ~ name ~ "_dt_1;";
		}
		source.Inject(kernel_source, "$declare_derivs_1$");
		
		/* Declare derivs 2 */
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ _d" ~ name ~ "_dt_2;";
		}
		source.Inject(kernel_source, "$declare_derivs_2$");
		
		/* Compute derivs 1 */
		auto first_source = eval_source.dup;
		foreach(name, state; &type.AllStates)
		{
			first_source = first_source.c_substitute(name ~ "'", "_d" ~ name ~ "_dt_1");
		}
		source.AddBlock(first_source);
		source.Inject(kernel_source, "$compute_derivs_1$");
		
		/* Apply derivs 1 */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " += _dt * _d" ~ name ~ "_dt_1;";
		}
		source.Inject(kernel_source, "$apply_derivs_1$");
		
		/* Compute derivs 2 */
		auto second_source = eval_source.dup;
		foreach(name, state; &type.AllStates)
		{
			second_source = second_source.c_substitute(name ~ "'", "_d" ~ name ~ "_dt_2");
		}
		source.AddBlock(second_source);
		source.Inject(kernel_source, "$compute_derivs_2$");
		
		/* Apply derivs 2 */
		foreach(name, state; &type.AllStates)
		{
			source ~= "_" ~ name ~ "_0 += _dt / 2 * (_d" ~ name ~ "_dt_1 + _d" ~ name ~ "_dt_2);";
		}
		source.Inject(kernel_source, "$apply_derivs_2$");
		
		/* Reset state */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " = _" ~ name ~ "_0;";
		}
		source.Inject(kernel_source, "$reset_state$");
		
		return kernel_source;
	}
}

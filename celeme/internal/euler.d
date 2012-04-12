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
 * A simple fixed timestep Euler integrator.
 */

module celeme.internal.euler;

import celeme.internal.iclneurongroup;
import celeme.internal.frontend;
import celeme.internal.integrator;
import celeme.internal.sourceconstructor;
import celeme.internal.util;
import celeme.internal.clcore;

import opencl.cl;

import tango.io.Stdout;

class CEuler(float_t) : CIntegrator!(float_t)
{
	this(ICLNeuronGroup group, CNeuronType type)
	{
		super(group, type);
	}
	
	override
	cstring GetLoadCode(CNeuronType type)
	{
		return "_dt = _dt_const;";
	}
	
	override
	cstring GetSaveCode(CNeuronType type)
	{
		return "";
	}
	
	override
	size_t SetArgs(CCLKernel kernel, size_t arg_id)
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
	cstring GetArgsCode(CNeuronType type)
	{
		return "const $num_type$ _dt_const,";
	}
	
	override
	cstring GetIntegrateCode(CNeuronType type)
	{
		scope source = new CSourceConstructor();

		auto eval_source = type.GetEvalSource();
		
		char[] kernel_source = 
"
/* Derivatives */
$declare_derivs$

/* Compute the derivatives */
$compute_derivs$

/* Compute the new state */
$apply_derivs$

/* Advance time*/
_cur_time += _dt;
".dup;
		/* Declare derivs */
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ _d" ~ name ~ "_dt;";
		}
		source.Inject(kernel_source, "$declare_derivs$");
		
		/* Compute derivs */
		auto first_source = eval_source.dup;
		foreach(name, state; &type.AllStates)
		{
			first_source = first_source.c_substitute(name ~ "'", "_d" ~ name ~ "_dt");
		}
		source.AddBlock(first_source);
		source.Inject(kernel_source, "$compute_derivs$");
		
		/* Apply derivs */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " += _dt * _d" ~ name ~ "_dt;";
		}
		source.Inject(kernel_source, "$apply_derivs$");
		
		return kernel_source;
	}
}

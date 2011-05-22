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
 * An adaptive heun integrator. Absolute tolerance is used, as it is more
 * appropriate for neural models.
 */

module celeme.internal.adaptiveheun;

import celeme.internal.iclneurongroup;
import celeme.internal.frontend;
import celeme.internal.integrator;
import celeme.internal.sourceconstructor;
import celeme.internal.util;
import celeme.internal.clcore;

import opencl.cl;

import tango.io.Stdout;

class CAdaptiveHeun(float_t) : CAdaptiveIntegrator!(float_t)
{
	this(ICLNeuronGroup group, CNeuronType type)
	{
		super(group, type);
		
		/* Copy tolerances */
		foreach(name, state; &type.AllStates)
		{
			ToleranceRegistry[name] = Tolerances.length;
			Tolerances ~= state.Tolerance;
		}
		
		DtBuffer = Group.Core.CreateBuffer!(float_t)(Group.Count);
	}
	
	override
	void Reset()
	{
		DtBuffer[] = Group.MinDt;
	}
	
	override
	char[] GetLoadCode(CNeuronType type)
	{
		return 
"$num_type$ _dt_residual = 0;
_dt = _dt_buf[i];";
	}
	
	override
	char[] GetSaveCode(CNeuronType type)
	{
		return 
"if(_dt_residual > $min_dt$f)
	_dt = _dt_residual;
if(_dt > timestep)
	_dt = timestep;

_dt_buf[i] = _dt;";
	}
	
	override
	int SetArgs(CCLKernel kernel, int arg_id)
	{
		kernel.SetGlobalArg(arg_id++, DtBuffer);
		foreach(tol; Tolerances)
		{
			float_t tolerance = tol;
			kernel.SetGlobalArg(arg_id++, tolerance);
		}
		
		return arg_id;
	}
	
	override
	char[] GetArgsCode(CNeuronType type)
	{
		char[] ret = "__global $num_type$* _dt_buf,\n";
		foreach(name, state; &type.AllStates)
		{
			ret ~= "const $num_type$ _" ~ name ~ "_tol," ~ "\n";
		}
		if(ret.length)
			ret = ret[0..$-1];
		return ret;
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

/* Compute the error in this step */
$compute_error$

/* Transfer the state from the temporary storage to the real storage */
$reset_state$

/* Advance and compute the new step size*/
_cur_time += _dt;

if(_error == 0)
	_dt = timestep;
else
{
	/* Approximate the cube root using Halley's Method (error is usually between 0 and 10)*/
	$num_type$ cr = (1.0f + 2 * _error)/(2.0f + _error);
	$num_type$ cr3 = cr*cr*cr;
	cr = cr * (cr3 + 2.0f * _error)/(2.0f * cr3 + _error);
	_dt *= 0.9f / cr;
	/* _dt *= 0.9f * rootn(_error, -3.0f); */
}
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
		
		/* Compute error */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " -= _" ~ name ~ "_0;";
			source ~= "_error = max(_error, fabs(" ~ name ~ ") / _" ~ name ~ "_tol);";
		}
		source.Inject(kernel_source, "$compute_error$");
		
		/* Reset state */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " = _" ~ name ~ "_0;";
		}
		source.Inject(kernel_source, "$reset_state$");
		
		return kernel_source;
	}
	
	override
	void SetTolerance(CCLKernel kernel, char[] state, double tolerance)
	{
		assert(tolerance > 0);
		
		auto idx_ptr = state in ToleranceRegistry;
		if(idx_ptr !is null)
		{	
			Tolerances[*idx_ptr] = tolerance;
			if(Group.Initialized)
			{
				kernel.SetGlobalArg(*idx_ptr + Group.IntegratorArgOffset, cast(float_t)tolerance);
			}
		}
		else
			throw new Exception("Neuron group '" ~ Group.Name ~ "' does not have a '" ~ state ~ "' state.");
	}
	
	override
	char[] GetPostThreshCode(CNeuronType type)
	{
		return 
"/* Clamp the _dt not too overshoot the timestep */
if(_cur_time < timestep && _cur_time + _dt >= timestep)
{
	_dt_residual = _dt;
	_dt = timestep - _cur_time + 0.0001f;
	_dt_residual -= _dt;
}";
	}
	
	override
	void Shutdown()
	{
		DtBuffer.Release();
	}
	
	CCLBuffer!(float_t) DtBuffer;
	double[] Tolerances;
	int[char[]] ToleranceRegistry;
}

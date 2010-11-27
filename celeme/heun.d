module celeme.heun;

import celeme.clneurongroup;
import celeme.frontend;
import celeme.integrator;
import celeme.sourceconstructor;
import celeme.util;

import opencl.cl;

import tango.io.Stdout;

class CHeun(float_t) : CIntegrator!(float_t)
{
	this(CNeuronGroup!(float_t) group, CNeuronType type)
	{
		super(group, type);
	}
	
	override
	char[] GetLoadCode(CNeuronType type)
	{
		return "dt = dt_const;";
	}
	
	override
	char[] GetSaveCode(CNeuronType type)
	{
		return "";
	}
	
	override
	int SetArgs(int arg_id)
	{
		SetDt(Group.MinDt);		
		return arg_id + 1;
	}
	
	void SetDt(double dt)
	{
		int parts = cast(int)(Group.Model.TimeStepSize / dt + 0.5);
		if(parts == 0)
			parts++;
		
		float_t val = cast(float_t)(Group.Model.TimeStepSize / parts);
		Group.StepKernel.SetGlobalArg(Group.IntegratorArgOffset, &val);
	}
	
	override
	char[] GetArgsCode(CNeuronType type)
	{
		return "const $num_type$ dt_const,";
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
cur_time += dt;
".dup;
		/* Declare temp states */
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ " ~ name ~ "_0 = " ~ name ~ ";";
		}
		source.Inject(kernel_source, "$declare_temp_states$");
		
		/* Declare derivs 1 */
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ d" ~ name ~ "_dt_1;";
		}
		source.Inject(kernel_source, "$declare_derivs_1$");
		
		/* Declare derivs 2 */
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ d" ~ name ~ "_dt_2;";
		}
		source.Inject(kernel_source, "$declare_derivs_2$");
		
		/* Compute derivs 1 */
		auto first_source = eval_source.dup;
		foreach(name, state; &type.AllStates)
		{
			first_source = first_source.c_substitute(name ~ "'", "d" ~ name ~ "_dt_1");
		}
		source.AddBlock(first_source);
		source.Inject(kernel_source, "$compute_derivs_1$");
		
		/* Apply derivs 1 */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " += dt * d" ~ name ~ "_dt_1;";
		}
		source.Inject(kernel_source, "$apply_derivs_1$");
		
		/* Compute derivs 2 */
		auto second_source = eval_source.dup;
		foreach(name, state; &type.AllStates)
		{
			second_source = second_source.c_substitute(name ~ "'", "d" ~ name ~ "_dt_2");
		}
		source.AddBlock(second_source);
		source.Inject(kernel_source, "$compute_derivs_2$");
		
		/* Apply derivs 2 */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ "_0 += dt / 2 * (d" ~ name ~ "_dt_1 + d" ~ name ~ "_dt_2);";
		}
		source.Inject(kernel_source, "$apply_derivs_2$");
		
		/* Reset state */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " = " ~ name ~ "_0;";
		}
		source.Inject(kernel_source, "$reset_state$");
		
		return kernel_source;
	}
}

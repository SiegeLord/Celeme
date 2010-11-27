module celeme.adaptiveheun;

import celeme.clneurongroup;
import celeme.frontend;
import celeme.integrator;
import celeme.sourceconstructor;
import celeme.util;

import opencl.cl;

import tango.io.Stdout;

class CAdaptiveHeun(float_t) : CAdaptiveIntegrator!(float_t)
{
	this(CNeuronGroup!(float_t) group, CNeuronType type)
	{
		super(group, type);
		
		/* Copy tolerances */
		foreach(name, state; &type.AllStates)
		{
			ToleranceRegistry[name] = Tolerances.length;
			Tolerances ~= state.Tolerance;
		}
		
		DtBuffer = Group.Model.Core.CreateBuffer(Group.Count * Group.Model.NumSize);
	}
	
	override
	void Reset()
	{
		Group.Model.MemsetFloatBuffer(DtBuffer, Group.Count, Group.MinDt);
	}
	
	override
	char[] GetLoadCode(CNeuronType type)
	{
		return 
"$num_type$ dt_residual = 0;
dt = dt_buf[i];";
	}
	
	override
	char[] GetSaveCode(CNeuronType type)
	{
		return 
"if(dt_residual > $min_dt$f)
	dt = dt_residual;
if(dt > timestep)
	dt = timestep;

dt_buf[i] = dt;";
	}
	
	override
	int SetArgs(int arg_id)
	{
		Group.StepKernel.SetGlobalArg(arg_id++, &DtBuffer);
		foreach(tol; Tolerances)
		{
			float_t tolerance = tol;
			Group.StepKernel.SetGlobalArg(arg_id++, &tolerance);
		}
		
		return arg_id;
	}
	
	override
	char[] GetArgsCode(CNeuronType type)
	{
		char[] ret = "__global $num_type$* dt_buf,\n";
		foreach(name, state; &type.AllStates)
		{
			ret ~= "const $num_type$ " ~ name ~ "_tol," ~ "\n";
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
cur_time += dt;

if(error == 0)
	dt = timestep;
else
	dt *= 0.9f * rootn(error, -3.0f);
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
		
		/* Compute error */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " -= " ~ name ~ "_0;";
			source ~= "error = max(error, fabs(" ~ name ~ ") / " ~ name ~ "_tol);";
		}
		source.Inject(kernel_source, "$compute_error$");
		
		/* Reset state */
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " = " ~ name ~ "_0;";
		}
		source.Inject(kernel_source, "$reset_state$");
		
		return kernel_source;
	}
	
	override
	void SetTolerance(char[] state, double tolerance)
	{
		assert(tolerance > 0);
		
		auto idx_ptr = state in ToleranceRegistry;
		if(idx_ptr !is null)
		{	
			Tolerances[*idx_ptr] = tolerance;
			if(Group.Model.Initialized)
			{
				float_t val = tolerance;
				Group.StepKernel.SetGlobalArg(*idx_ptr + Group.IntegratorArgOffset, &val);
			}
		}
		else
			throw new Exception("Neuron group '" ~ Group.Name ~ "' does not have a '" ~ state ~ "' state.");
	}
	
	override
	char[] GetPostThreshCode(CNeuronType type)
	{
		return 
"/* Clamp the dt not too overshoot the timestep */
if(cur_time < timestep && cur_time + dt >= timestep)
{
	dt_residual = dt;
	dt = timestep - cur_time + 0.0001f;
	dt_residual -= dt;
}";
	}
	
	override
	void Shutdown()
	{
		clReleaseMemObject(DtBuffer);
	}
	
	cl_mem DtBuffer;
	double[] Tolerances;
	int[char[]] ToleranceRegistry;
}

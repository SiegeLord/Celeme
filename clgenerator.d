module clgenerator;

import frontend;

import tango.io.Stdout;
import tango.core.Array;

char[] StepKernelTemplate = "
__kernel void $type_name$_step
	(
$val_args$
$constant_args$
		__global $num_type$* dt_buf,
		const $num_type$ t,
		const int count
	)
{
	int i = get_global_id(0);
	if(i < count)
	{
		$num_type$ dt = dt_buf[i];
$load_vals$

		while(cur_time < timestep)
		{
			$num_type$ error = 0;
			
$declare_locals$

$declare_temp_states$

$declare_derivs_1$

$declare_derivs_2$

$compute_derivs_1$

$apply_derivs_1$

$compute_derivs_2$

$apply_derivs_2$

$compute_error$

$reset_state$
			
			cur_time += dt;
			
			dt *= 0.8f * .46415888f * rootn(error + 0.00001f, -6);
			
			if(cur_time < timestep && cur_time + dt >= timestep)
			{
				dt = timestep - cur_time + 0.0001f;
			}
		}
		
		dt_buf[i] = dt;
$save_states$
	}
}
";

void replace(ref char[] text, char[] pattern, char[] what)
{
	char[] ret;
	char[] rem = text;
	int start;
	while((start = rem.find(pattern)) != rem.length)
	{
		ret ~= rem[0..start] ~ what;
		rem = rem[start + pattern.length .. $];
	}
	ret ~= rem;
	text = ret;
}

unittest
{
	char[] a = "People like eating cows and pigs".dup;
	
	replace(a, "cows", "sheep");
	assert(a == "People like eating sheep and pigs");
	
	replace(a, "eat", "pett");
	assert(a == "People like petting sheep and pigs");
	
	replace(a, "pigs", "cats");
	assert(a == "People like petting sheep and cats");
	
	replace(a, "People", "Skeletons");
	assert(a == "Skeletons like petting sheep and cats");
	
	replace(a, "nothing", "anything");
	assert(a == "Skeletons like petting sheep and cats");
}

class CSource
{
	void Add(char[] text)
	{
		Source ~= text;
	}
	void AddLine(char[] line)
	{
		auto tabs = "\t\t\t\t\t\t\t\t\t\t";
		Source ~= tabs[0..TabLevel] ~ line ~ "\n";
	}
	
	alias AddLine opCatAssign;
	
	void EmptyLine()
	{
		Source ~= "\n";
	}
	
	void Clear()
	{
		TabLevel = 0;
		Source.length = 0;
	}
	
	void Tab(int num = 1)
	{
		TabLevel += num;
		assert(TabLevel < 10, "TabLevel has to be less than 10");
	}
	
	void DeTab(int num = 1)
	{
		TabLevel -= num;
		assert(TabLevel >= 0, "TabLevel cannot be less than 0");
	}
	
	void Retreat(int num)
	{
		assert(Source.length - num >= 0, "Can't retreat past start!");
		Source = Source[0..$-num];
	}
	
	char[] toString()
	{
		return Source;
	}
	
	int TabLevel = 0;
	char[] Source;
}

class CModel
{	
	void AddNeuronGroup(CNeuronType type, int number)
	{
		type.VerifyExternals();
		
		SNeuronGroup group;
		group.Type = type;
		group.Count = number;
		
		NeuronGroups ~= group;
	}
	
	struct SNeuronGroup
	{
		CNeuronType Type;
		int Count;
	}
	
	void Generate()
	{
		/* Generate the step function */
		auto source = new CSource;
		
		foreach(group; NeuronGroups)
		{
			auto kernel_source = StepKernelTemplate.dup;
			
			auto type = group.Type;
			
			void apply(char[] dest)
			{
				source.Retreat(1); /* Chomp the newline */
				kernel_source.replace(dest, source.toString);
				source.Clear();
			}
			
			kernel_source.replace("$type_name$", type.Name);
			
			/* Value arguments */
			source.Tab(2);
			foreach(state; &type.AllNonLocals)
			{
				source ~= "__global $num_type$* " ~ state.Name ~ "_buf,";
			}
			apply("$val_args$");
			
			/* Constant arguments */
			source.Tab(2);
			foreach(state; &type.AllConstants)
			{
				source ~= "const $num_type$* " ~ state.Name ~ ",";
			}
			apply("$constant_args$");
			
			/* Load vals */
			source.Tab(2);
			foreach(state; &type.AllNonLocals)
			{
				source ~= "$num_type$ " ~ state.Name ~ " = " ~ state.Name ~ "_buf[i];";
			}
			apply("$load_vals$");
			
			/* Declare locals */
			source.Tab(3);
			foreach(state; &type.AllLocals)
			{
				source ~= "$num_type$ " ~ state.Name ~ ";";
			}
			apply("$declare_locals$");
			
			/* Declare temp states */
			source.Tab(3);
			foreach(state; &type.AllStates)
			{
				source ~= "$num_type$ " ~ state.Name ~ "_0 = " ~ state.Name ~ ";";
			}
			apply("$declare_temp_states$");
			
			/* Declare derivs 1 */
			source.Tab(3);
			foreach(state; &type.AllStates)
			{
				source ~= "$num_type$ d" ~ state.Name ~ "_dt_1;";
			}
			apply("$declare_derivs_1$");
			
			/* Declare derivs 2 */
			source.Tab(3);
			foreach(state; &type.AllStates)
			{
				source ~= "$num_type$ d" ~ state.Name ~ "_dt_2;";
			}
			apply("$declare_derivs_2$");
			
			/* Apply derivs 1 */
			source.Tab(3);
			foreach(state; &type.AllStates)
			{
				source ~= state.Name ~ " += dt * d" ~ state.Name ~ "_dt_1;";
			}
			apply("$apply_derivs_1$");
			
			/* Apply derivs 2 */
			source.Tab(3);
			foreach(state; &type.AllStates)
			{
				source ~= state.Name ~ "_0 += dt / 2 * (d" ~ state.Name ~ "_dt_1 + d" ~ state.Name ~ "_dt_2);";
			}
			apply("$apply_derivs_2$");
			
			/* Compute error */
			source.Tab(3);
			foreach(state; &type.AllStates)
			{
				source ~= state.Name ~ " -= " ~ state.Name ~ "_0;";
				source ~= "error += " ~ state.Name ~ " * " ~ state.Name ~ ";";
			}
			apply("$compute_error$");
			
			/* Reset state */
			source.Tab(3);
			foreach(state; &type.AllStates)
			{
				source ~= state.Name ~ " = " ~ state.Name ~ "_0;";
			}
			apply("$reset_state$");
			
			/* Save states */
			source.Tab(2);
			foreach(state; &type.AllStates)
			{
				source ~= state.Name ~ "_buf[i] = " ~ state.Name ~ ";";
			}
			apply("$save_states$");
			
			kernel_source.replace("$num_type$", NumType);
			Source ~= kernel_source;
		}
		Stdout(Source).nl;
	}
	
	char[] NumType = "float";
	SNeuronGroup[] NeuronGroups;
	char[] Source;
}

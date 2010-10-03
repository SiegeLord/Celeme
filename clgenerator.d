module clgenerator;

import frontend;

import tango.io.Stdout;
import tango.core.Array;
import tango.text.Util;

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

			/* Declare local variables */
$declare_locals$

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
			
			dt *= 0.8f * .46415888f * rootn(error + 0.00001f, -6);
			
			/* Handle thresholds */
$thresholds$
			
			/* Clamp the dt not too overshoot the timestep */
			if(cur_time < timestep && cur_time + dt >= timestep)
			{
				dt = timestep - cur_time + 0.0001f;
			}
		}
		dt_buf[i] = dt;
$save_vals$
	}
}
";

char[] InitKernelTemplate = "
__kernel void $type_name$_init
	(
$val_args$
$constant_args$
		const int count
	)
{
	int i = get_global_id(0);
	if(i < count)
	{
		/* Load values */
$load_vals$
		
		/* Perform initialization */
$init_vals$
		
		/* Put them back */
$save_vals$
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
	
	void AddBlock(char[] block)
	{
		foreach(line; lines(block))
		{
			AddLine(line);
		}
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

class CNeuronGroup
{
	struct SValueBuffer
	{
		double Value;
	}
	
	this(CNeuronType type, int count)
	{
		Count = count;
		Initialize(type);
	}
	
	void Initialize(CNeuronType type)
	{
		Name = type.Name;
		
		/* Copy the non-locals and constants */
		foreach(state; &type.AllNonLocals)
		{
			ValueBufferRegistry[state.Name] = ValueBuffers.length;
			
			SValueBuffer buff;
			buff.Value = state.Value;
			
			ValueBuffers ~= buff;
		}

		foreach(state; &type.AllConstants)
		{
			ConstantRegistry[state.Name] = Constants.length;
			
			Constants ~= state.Value;
		}
		
		/* Create kernel sources */
		CreateStepKernel(type);
		CreateInitKernel(type);
	}
	
	void CreateStepKernel(CNeuronType type)
	{
		scope source = new CSource;
		
		auto kernel_source = StepKernelTemplate.dup;
		
		auto eval_source = type.GetEvalSource();
		
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
			source ~= "const $num_type$ " ~ state.Name ~ ",";
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
		
		/* Compute derivs 1 */
		auto first_source = eval_source.dup;
		foreach(state; &type.AllStates)
		{
			first_source.replace(state.Name ~ "'", "d" ~ state.Name ~ "_dt_1");
		}
		source.Tab(3);
		source.AddBlock(first_source);
		apply("$compute_derivs_1$");
		
		/* Apply derivs 1 */
		source.Tab(3);
		foreach(state; &type.AllStates)
		{
			source ~= state.Name ~ " += dt * d" ~ state.Name ~ "_dt_1;";
		}
		apply("$apply_derivs_1$");
		
		/* Compute derivs 2 */
		auto second_source = eval_source.dup;
		foreach(state; &type.AllStates)
		{
			second_source.replace(state.Name ~ "'", "d" ~ state.Name ~ "_dt_2");
		}
		source.Tab(3);
		source.AddBlock(second_source);
		apply("$compute_derivs_2$");
		
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
		
		/* Thresholds */
		source.Tab(3);
		foreach(thresh; &type.AllThresholds)
		{
			source ~= "if(" ~ thresh.State ~ " " ~ thresh.Condition ~ ")";
			source ~= "{";
			source.Tab;
			source.AddBlock(thresh.Source);
			source ~= "dt = 0.001f;";
			source.DeTab;
			source ~= "}";
		}
		apply("$thresholds$");
		
		/* Save values */
		source.Tab(2);
		foreach(state; &type.AllNonLocals)
		{
			source ~= state.Name ~ "_buf[i] = " ~ state.Name ~ ";";
		}
		apply("$save_vals$");
		
		StepKernelSource = kernel_source;
	}
	
	void CreateInitKernel(CNeuronType type)
	{
		scope source = new CSource;
		
		auto init_source = type.GetInitSource();
		
		if(init_source.length == 0)
			return;
		
		auto kernel_source = InitKernelTemplate.dup;
		
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
			source ~= "const $num_type$ " ~ state.Name ~ ",";
		}
		apply("$constant_args$");
		
		/* Load vals */
		source.Tab(2);
		foreach(state; &type.AllNonLocals)
		{
			source ~= "$num_type$ " ~ state.Name ~ " = " ~ state.Name ~ "_buf[i];";
		}
		apply("$load_vals$");
		
		/* Perform initialization */
		source.Tab(2);
		source.AddBlock(init_source);
		apply("$init_vals$");
		
		/* Save values */
		source.Tab(2);
		foreach(state; &type.AllNonLocals)
		{
			source ~= state.Name ~ "_buf[i] = " ~ state.Name ~ ";";
		}
		apply("$save_vals$");
		
		InitKernelSource = kernel_source;
	}
	
	double[] Constants;
	int[char[]] ConstantRegistry;
	
	SValueBuffer[] ValueBuffers;
	int[char[]] ValueBufferRegistry;
	
	char[] Name;
	int Count = 0;
	
	char[] StepKernelSource;
	char[] InitKernelSource;
}

class CModel
{
	void AddNeuronGroup(CNeuronType type, int number)
	{
		type.VerifyExternals();
		
		auto group = new CNeuronGroup(type, number);
		
		NeuronGroupRegistry[type.Name] = NeuronGroups.length;
		NeuronGroups ~= group;
	}
	
	void Generate()
	{
		foreach(group; NeuronGroups)
		{
			//group.Initialize();
			Source ~= group.StepKernelSource;
			Source ~= group.InitKernelSource;
		}
		Source.replace("$num_type$", NumType);
		Stdout(Source).nl;
	}
	
	char[] NumType = "float";
	CNeuronGroup[] NeuronGroups;
	int[char[]] NeuronGroupRegistry;
	char[] Source;
}

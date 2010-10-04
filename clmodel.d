module clmodel;

import frontend;
import clcore;

import opencl.cl;

import tango.io.Stdout;
import tango.core.Array;
import tango.text.Util;

char[] FloatMemsetKernelTemplate = "
__kernel void float_memset(
		__global $num_type$* buffer,
		const $num_type$ value,
		const int count
	)
{
	int i = get_global_id(0);
	if(i < count)
	{
		buffer[i] = value;
	}
}
";

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
		$num_type$ cur_time = 0;
		const $num_type$ timestep = 1;
		
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
		cl_mem Buffer;
	}
	
	this(CModel model, CNeuronType type, int count, char[] name)
	{
		Model = model;
		Count = count;
		Name = name;
		Initialize(type);
	}
	
	void Initialize(CNeuronType type)
	{
		/* Copy the non-locals and constants */
		foreach(state; &type.AllNonLocals)
		{
			ValueBufferRegistry[state.Name] = ValueBuffers.length;
			
			SValueBuffer buff;
			buff.Value = state.Value;
			buff.Buffer = Model.Core.CreateBuffer(Count * Model.NumSize);
			
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
	
	/* Call this after the kernel has been compiled, as we need the memset kernel */
	void InitializeBuffers()
	{
		foreach(buffer; ValueBuffers)
		{
			WriteToBuffer(buffer);
		}
		Model.Core.Finish();
	}
	
	void WriteToBuffer(SValueBuffer buffer)
	{
		auto kernel = Model.FloatMemsetKernel;
		
		SetGlobalArg(kernel, 0, &buffer.Buffer);
		if(Model.SinglePrecision)
		{
			float val = buffer.Value;
			SetGlobalArg(kernel, 1, &val);
		}
		else
		{
			double val = buffer.Value;
			SetGlobalArg(kernel, 1, &val);
		}
		SetGlobalArg(kernel, 2, &Count);
		
		size_t count = Count;
		auto err = clEnqueueNDRangeKernel(Model.Core.Commands, kernel, 1, null, &count, null, 0, null, null);
		assert(err == CL_SUCCESS);
	}
	
	double ReadFromBuffer(SValueBuffer buffer, int idx)
	{
		if(Model.SinglePrecision)
		{
			float val;
			clEnqueueReadBuffer(Model.Core.Commands, buffer.Buffer, CL_TRUE, float.sizeof * idx, float.sizeof, &val, 0, null, null);
			return val;
		}
		else
		{
			double val;
			clEnqueueReadBuffer(Model.Core.Commands, buffer.Buffer, CL_TRUE, double.sizeof * idx, double.sizeof, &val, 0, null, null);
			return val;
		}
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
		
		kernel_source.replace("$type_name$", Name);
		
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
		
		kernel_source.replace("$type_name$", Name);
		
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
	
	/* These two functions can be used to modify values after the model has been created.
	 */
	double opIndex(char[] name, int idx = -1)
	{
		assert(idx < Count, "idx needs to be less than Count.");
		
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			return Constants[*idx_ptr];
		}
		
		idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr !is null)
		{
			if(Model.Generated && idx > 0)
			{
				auto val = ReadFromBuffer(ValueBuffers[*idx_ptr], idx);
				Model.Core.Finish();
				return val;
			}
			else
			{
				return ValueBuffers[*idx_ptr].Value;
			}
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	double opIndexAssign(double val, char[] name)
	{
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			return Constants[*idx_ptr] = val;
		}
		
		idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr !is null)
		{
			ValueBuffers[*idx_ptr].Value = val;
			if(Model.Generated)
			{
				WriteToBuffer(ValueBuffers[*idx_ptr]);
				Model.Core.Finish();
			}
			return val;
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	void Shutdown()
	{
		foreach(buffer; ValueBuffers)
			clReleaseMemObject(buffer.Buffer);
	}
	
	double[] Constants;
	int[char[]] ConstantRegistry;
	
	SValueBuffer[] ValueBuffers;
	int[char[]] ValueBufferRegistry;
	
	char[] Name;
	int Count = 0;
	CModel Model;
	
	char[] StepKernelSource;
	char[] InitKernelSource;
}

class CModel
{
	this(CCLCore core)
	{
		Core = core;
	}
	
	void AddNeuronGroup(CNeuronType type, int number, char[] name = null)
	{
		type.VerifyExternals();
		
		if(name is null)
			name = type.Name;
			
		if((name in NeuronGroups) !is null)
			throw new Exception("A group named '" ~ name ~ "' already exists in this model.");
		
		auto group = new CNeuronGroup(this, type, number, name);
		
		NeuronGroups[type.Name] = group;
	}
	
	void Generate()
	{
		Source ~= "#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable\n";
		Source ~= FloatMemsetKernelTemplate;
		foreach(group; NeuronGroups)
		{
			Source ~= group.StepKernelSource;
			Source ~= group.InitKernelSource;
		}
		Source.replace("$num_type$", NumType);
		//Stdout(Source).nl;
		Program = Core.BuildProgram(Source);
		
		int err;
		FloatMemsetKernel = clCreateKernel(Program, "float_memset", &err);
		assert(err == CL_SUCCESS);
		
		foreach(group; NeuronGroups)
			group.InitializeBuffers();
		
		Generated = true;
	}
	
	CNeuronGroup opIndex(char[] name)
	{
		auto ret_ptr = name in NeuronGroups;
		if(ret_ptr is null)
			throw new Exception("No group named '" ~ name ~ "' exists in this model");
		return *ret_ptr;
	}
	
	char[] NumType()
	{
		if(SinglePrecision)
			return "float";
		else
			return "double";
	}
	
	size_t NumSize()
	{
		if(SinglePrecision)
			return float.sizeof;
		else
			return double.sizeof;
	}
	
	void Shutdown()
	{
		foreach(group; NeuronGroups)
			group.Shutdown();
		Generated = false;
	}
	
	cl_program Program;
	cl_kernel FloatMemsetKernel;
	
	CCLCore Core;
	bool SinglePrecision = true;
	CNeuronGroup[char[]] NeuronGroups;
	char[] Source;
	bool Generated = false;
}

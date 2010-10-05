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

char[] IntMemsetKernelTemplate = "
__kernel void int_memset(
		__global int* buffer,
		const int value,
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

const ArgOffsetStep = 5;
char[] StepKernelTemplate = "
__kernel void $type_name$_step
	(
		const $num_type$ t,
		__global $num_type$* dt_buf,
		__global int* record_flags,
		__global int* record_idx,
		__global $num_type$4* record_buffer,
$val_args$
$constant_args$
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

const ArgOffsetInit = 0;
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
		
		/* Copy the non-locals and constants from the type */
		foreach(state; &type.AllNonLocals)
		{
			ValueBufferRegistry[state.Name] = ValueBuffers.length;
			
			SValueBuffer buff;
			buff.Value = state.Value;
			buff.Buffer = Model.Core.CreateBuffer(Count * Model.NumSize);
			
			ValueBuffers ~= buff;
		}
		
		DtBuffer = Model.Core.CreateBuffer(Count * Model.NumSize);
		RecordFlagsBuffer = Model.Core.CreateBuffer(Count * int.sizeof);
		RecordBuffer = Model.Core.CreateBuffer(Count * Model.NumSize * 4);
		RecordIdxBuffer = Model.Core.CreateBuffer(int.sizeof);

		foreach(state; &type.AllConstants)
		{
			ConstantRegistry[state.Name] = Constants.length;
			
			Constants ~= state.Value;
		}
		
		/* Create kernel sources */
		CreateStepKernel(type);
		CreateInitKernel(type);
	}
	
	/* Call this after the program has been created, as we need the memset kernel
	 * and to create the local kernels*/
	void Initialize()
	{
		auto step_kernel_name = Name ~ "_step\0";
		int err;
		
		StepKernel = clCreateKernel(Model.Program, step_kernel_name.ptr, &err);
		assert(err == CL_SUCCESS);
		
		/* Set the arguments. Start at 1 to skip the t argument*/
		int arg_id = 1;
		SetGlobalArg(StepKernel, arg_id++, &DtBuffer);
		SetGlobalArg(StepKernel, arg_id++, &RecordFlagsBuffer);
		SetGlobalArg(StepKernel, arg_id++, &RecordIdxBuffer);
		SetGlobalArg(StepKernel, arg_id++, &RecordBuffer);
		foreach(buffer; ValueBuffers)
		{
			SetGlobalArg(StepKernel, arg_id++, &buffer.Buffer);
		}
		arg_id += Constants.length;
		SetGlobalArg(StepKernel, arg_id++, &Count);
		
		if(InitKernelSource.length)
		{
			auto init_kernel_name = Name ~ "_init\0";
			InitKernel = clCreateKernel(Model.Program, init_kernel_name.ptr, &err);
			assert(err == CL_SUCCESS);
			
			/* Nothing to skip, so set it at 0 */
			arg_id = 0;
			foreach(buffer; ValueBuffers)
			{
				SetGlobalArg(InitKernel, arg_id++, &buffer.Buffer);
			}
			arg_id += Constants.length;
			SetGlobalArg(InitKernel, arg_id++, &Count);
		}
		
		/* Set the constants. Here because SetConstant sets it to both kernels, so both need
		 * to be created
		 */
		foreach(ii, _; Constants)
		{
			SetConstant(ii);
		}
		
		/* Initialize the buffers */
		Model.MemsetFloatBuffer(DtBuffer, Count, 0.001f);
		Model.MemsetIntBuffer(RecordFlagsBuffer, Count, 0);
		Model.MemsetIntBuffer(RecordIdxBuffer, 1, 0);
		/* Write the default values to the global buffers*/
		foreach(buffer; ValueBuffers)
		{
			WriteToBuffer(buffer);
		}
		Model.Core.Finish();
	}
	
	void SetConstant(int idx)
	{
		if(Model.SinglePrecision)
		{
			float val = Constants[idx];
			if(InitKernelSource.length)
				SetGlobalArg(InitKernel, idx + ValueBuffers.length + ArgOffsetInit, &val);
			SetGlobalArg(StepKernel, idx + ValueBuffers.length + ArgOffsetStep, &val);
		}
		else
		{
			double val = Constants[idx];
			if(InitKernelSource.length)
				SetGlobalArg(InitKernel, idx + ValueBuffers.length + ArgOffsetInit, &val);
			SetGlobalArg(StepKernel, idx + ValueBuffers.length + ArgOffsetStep, &val);
		}
	}
	
	void WriteToBuffer(SValueBuffer buffer)
	{
		Model.MemsetFloatBuffer(buffer.Buffer, Count, buffer.Value);
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
	
	void CallInitKernel(size_t workgroup_size)
	{
		if(InitKernelSource.length)
		{
			size_t total_num = (Count / workgroup_size) * workgroup_size;
			if(total_num < Count)
				total_num += workgroup_size;
			auto err = clEnqueueNDRangeKernel(Model.Core.Commands, InitKernel, 1, null, &total_num, &workgroup_size, 0, null, null);
			assert(err == CL_SUCCESS);
		}
	}
	
	void CallStepKernel(double t, size_t workgroup_size)
	{
		size_t total_num = (Count / workgroup_size) * workgroup_size;
		if(total_num < Count)
			total_num += workgroup_size;
		
		if(Model.SinglePrecision)
		{
			float t_val = t;
			SetGlobalArg(StepKernel, 0, &t_val);
		}
		else
		{
			double t_val = t;
			SetGlobalArg(StepKernel, 0, &t_val);
		}

		auto err = clEnqueueNDRangeKernel(Model.Core.Commands, StepKernel, 1, null, &total_num, &workgroup_size, 0, null, null);
		assert(err == CL_SUCCESS);
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
			Constants[*idx_ptr] = val;
			if(Model.Generated)
				SetConstant(*idx_ptr);
			return val;
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

		clReleaseMemObject(DtBuffer);
	}
	
	CRecorder Record(int neuron_id, char[] name)
	{
		assert(neuron_id >= 0);
		assert(neuron_id < Count);
		auto idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr is null)
			throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
		
		Recorders[neuron_id] = new CRecorder();
	}
	
	CRecorder[int] Recorders;
	
	double[] Constants;
	int[char[]] ConstantRegistry;
	
	SValueBuffer[] ValueBuffers;
	int[char[]] ValueBufferRegistry;
	
	char[] Name;
	int Count = 0;
	CModel Model;
	
	char[] StepKernelSource;
	char[] InitKernelSource;
	
	cl_kernel InitKernel;
	cl_kernel StepKernel;
	
	cl_mem DtBuffer;
	cl_mem RecordFlagsBuffer;
	cl_mem RecordBuffer;
	cl_mem RecordIdxBuffer;
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
		Source ~= IntMemsetKernelTemplate;
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
		IntMemsetKernel = clCreateKernel(Program, "int_memset", &err);
		assert(err == CL_SUCCESS);
		
		foreach(group; NeuronGroups)
			group.Initialize();
		
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
	
	void Run(int tstop)
	{
		/* Transfer to an array for faster iteration */
		auto groups = NeuronGroups.values;
		
		foreach(group; groups)
			group.CallInitKernel(16);
		foreach(group; groups)
			group.CallStepKernel(0, 16);
			
		Core.Finish();
	}
	
	void Shutdown()
	{
		foreach(group; NeuronGroups)
			group.Shutdown();
		Generated = false;
	}
	
	void MemsetFloatBuffer(ref cl_mem buffer, int count, double value)
	{
		SetGlobalArg(FloatMemsetKernel, 0, &buffer);
		if(SinglePrecision)
		{
			float val = value;
			SetGlobalArg(FloatMemsetKernel, 1, &val);
		}
		else
		{
			double val = value;
			SetGlobalArg(FloatMemsetKernel, 1, &val);
		}
		SetGlobalArg(FloatMemsetKernel, 2, &count);
		size_t total_size = count;
		auto err = clEnqueueNDRangeKernel(Core.Commands, FloatMemsetKernel, 1, null, &total_size, null, 0, null, null);
		assert(err == CL_SUCCESS);
	}
	
	void SetFloat(ref cl_mem buffer, int idx, double value)
	{
		int err;
		if(SinglePrecision)
		{
			float val = value;
			err = clEnqueueWriteBuffer(Core.Commands, buffer, CL_TRUE, float.sizeof * idx, float.sizeof, &val, 0, null, null);
		}
		else
		{
			double val = value;
			err = clEnqueueWriteBuffer(Core.Commands, buffer, CL_TRUE, double.sizeof * idx, double.sizeof, &val, 0, null, null);
		}
		assert(err == CL_SUCCESS);
	}
	
	void SetInt(ref cl_mem buffer, int idx, int value)
	{
		auto err = clEnqueueWriteBuffer(Core.Commands, buffer, CL_TRUE, int.sizeof * idx, int.sizeof, &value, 0, null, null);
		assert(err == CL_SUCCESS);
	}
	
	int ReadInt(ref cl_mem buffer, int idx)
	{
		int value;
		auto err = clEnqueueReadBuffer(Core.Commands, buffer, CL_TRUE, int.sizeof * idx, int.sizeof, &value, 0, null, null);
		assert(err == CL_SUCCESS);
		return value;
	}
	
	void MemsetIntBuffer(ref cl_mem buffer, int count, int value)
	{
		SetGlobalArg(IntMemsetKernel, 0, &buffer);
		SetGlobalArg(IntMemsetKernel, 1, &value);
		SetGlobalArg(IntMemsetKernel, 2, &count);
		size_t total_size = count;
		auto err = clEnqueueNDRangeKernel(Core.Commands, IntMemsetKernel, 1, null, &total_size, null, 0, null, null);
		assert(err == CL_SUCCESS);
	}
	
	cl_program Program;
	cl_kernel FloatMemsetKernel;
	cl_kernel IntMemsetKernel;
	
	CCLCore Core;
	bool SinglePrecision = true;
	CNeuronGroup[char[]] NeuronGroups;
	char[] Source;
	bool Generated = false;
}

class CRecorder
{
	
}

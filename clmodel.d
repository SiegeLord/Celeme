module clmodel;

import clcore;
import frontend;
import clneurongroup;
import tango.text.Util;

import opencl.cl;

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
		Source ~= "#define PARALLEL_DELIVER 1\n";
		Source ~= FloatMemsetKernelTemplate;
		Source ~= IntMemsetKernelTemplate;
		foreach(group; NeuronGroups)
		{
			Source ~= group.StepKernelSource;
			Source ~= group.InitKernelSource;
			Source ~= group.DeliverKernelSource;
		}
		Source = Source.substitute("$num_type$", NumType);
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
		
		int t = 0;
		/* Initialize */
		foreach(group; groups)
		{
			group.ResetBuffers();
			group.CallInitKernel(16);
		}
		/* Run the model */
		while(t <= tstop)
		{
			foreach(group; groups)
				group.CallDeliverKernel(t, 16);
			foreach(group; groups)
				group.CallStepKernel(t, 16);
			foreach(group; groups)
				group.UpdateRecorders();
			t++;
		}
		Core.Finish();
		/* Check for errors */
		foreach(group; groups)
		{
			group.CheckErrors();
		}
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

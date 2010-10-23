module celeme.clmodel;

import celeme.clcore;
import celeme.frontend;
import celeme.clneurongroup;

import tango.text.Util;
import tango.io.Stdout;

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


class CCLModel
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
		
		auto nrn_offset = NumNeurons;
		NumNeurons += number;
		auto sink_offset = NumDestSynapses;
		NumDestSynapses += number * type.NumDestSynapses;
		
		auto group = new CNeuronGroup(this, type, number, name, sink_offset, nrn_offset);
		
		NeuronGroups[type.Name] = group;
	}
	
	void Generate(bool parallel_delivery = true)
	{
		assert(NumNeurons);
		if(NumDestSynapses)
		{
			FiredSynIdxBuffer = Core.CreateBuffer(int.sizeof * NumNeurons);
			FiredSynBuffer = Core.CreateBuffer(int.sizeof * NumDestSynapses);
		}
		
		Source ~= "#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable\n";
		if(parallel_delivery)
			Source ~= "#define PARALLEL_DELIVERY 1\n";
		else
			Source ~= "#define PARALLEL_DELIVERY 0\n";
		Source ~= FloatMemsetKernelTemplate;
		Source ~= IntMemsetKernelTemplate;
		foreach(group; NeuronGroups)
		{
			Source ~= group.StepKernelSource;
			Source ~= group.InitKernelSource;
			Source ~= group.DeliverKernelSource;
		}
		Source = Source.substitute("$num_type$", NumType);
		//Stdout(Source).nl;
		Program = Core.BuildProgram(Source);
		
		FloatMemsetKernel = new CCLKernel(&Program, "float_memset");
		IntMemsetKernel = new CCLKernel(&Program, "int_memset");
		
		/* Set it to -1, so that when the neuron step functions are called,
		 * it gets reset automatically there */
		if(NumDestSynapses)
		{
			MemsetIntBuffer(FiredSynIdxBuffer, NumNeurons, -1);
		}
		
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
	
	void Run(int tstop, int run_workgroup_size = 16, int deliver_workgroup_size = 16)
	{
		/* Transfer to an array for faster iteration */
		auto groups = NeuronGroups.values;
		
		int t = 0;
		/* Initialize */
		foreach(group; groups)
		{
			group.ResetBuffers();
			group.CallInitKernel(run_workgroup_size);
		}
		/* Run the model */
		while(t <= tstop)
		{
			/* Called first because it resets the record index to 0,
			 * so the update recorders wouldn't get anything if it was right 
			 * before it */
			foreach(group; groups)
				group.CallDeliverKernel(t, deliver_workgroup_size);
			foreach(group; groups)
				group.CallStepKernel(t, run_workgroup_size);
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
		with(FloatMemsetKernel)
		{
			SetGlobalArg(0, &buffer);
			if(SinglePrecision)
			{
				float val = value;
				SetGlobalArg(1, &val);
			}
			else
			{
				double val = value;
				SetGlobalArg(1, &val);
			}
			SetGlobalArg(2, &count);
			size_t total_size = count;
			auto err = clEnqueueNDRangeKernel(Core.Commands, Kernel, 1, null, &total_size, null, 0, null, null);
			assert(err == CL_SUCCESS);
		}
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
		with(IntMemsetKernel)
		{
			SetGlobalArg(0, &buffer);
			SetGlobalArg(1, &value);
			SetGlobalArg(2, &count);
			size_t total_size = count;
			auto err = clEnqueueNDRangeKernel(Core.Commands, Kernel, 1, null, &total_size, null, 0, null, null);
			assert(err == CL_SUCCESS);
		}
	}
	
	cl_program Program;
	CCLKernel FloatMemsetKernel;
	CCLKernel IntMemsetKernel;
	
	cl_mem FiredSynIdxBuffer;
	cl_mem FiredSynBuffer;
	
	/* Total model number of dest synapses */
	int NumDestSynapses = 0;
	int NumNeurons = 0;
	
	CCLCore Core;
	bool SinglePrecision = true;
	CNeuronGroup[char[]] NeuronGroups;
	char[] Source;
	bool Generated = false;
}

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


class CCLModel(float_t)
{
	static if(is(float_t == float))
	{
		char[] NumStr = "float";
	}
	else
	{
		static assert(0);
	}
	
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
		
		auto group = new CNeuronGroup!(float_t)(this, type, number, name, sink_offset, nrn_offset);
		
		NeuronGroups[type.Name] = group;
	}
	
	void Generate(bool parallel_delivery = true)
	{
		assert(NumNeurons);
		if(NumDestSynapses)
		{
			FiredSynIdxBuffer = Core.CreateBufferEx!(int)(NumNeurons);
			FiredSynBuffer = Core.CreateBufferEx!(int)(NumDestSynapses);
		}
		
		Source ~= "#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable\n";
		//Source ~= "#pragma OPENCL EXTENSION cl_amd_printf : enable\n";
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
		Source = Source.substitute("$num_type$", NumStr);
		//Stdout(Source).nl;
		Program = Core.BuildProgram(Source);
		
		FloatMemsetKernel = new CCLKernel(&Program, "float_memset");
		IntMemsetKernel = new CCLKernel(&Program, "int_memset");
		
		/* Set it to -1, so that when the neuron step functions are called,
		 * it gets reset automatically there */
		if(NumDestSynapses)
		{
			auto arr = FiredSynIdxBuffer.Map(CL_MAP_WRITE);
			arr[] = -1;
			FiredSynIdxBuffer.UnMap(arr);
		}
		
		foreach(group; NeuronGroups)
			group.Initialize();
		
		Generated = true;
	}
	
	CNeuronGroup!(float_t) opIndex(char[] name)
	{
		auto ret_ptr = name in NeuronGroups;
		if(ret_ptr is null)
			throw new Exception("No group named '" ~ name ~ "' exists in this model");
		return *ret_ptr;
	}
	
	size_t NumSize()
	{
		return float_t.sizeof;
	}
	
	void Run(int tstop)
	{
		ResetRun();
		InitRun();
		RunUntil(tstop);
	}
	
	void ResetRun()
	{
		T = 0;
		foreach(group; NeuronGroups)
		{
			group.ResetBuffers();
		}
	}
	
	void InitRun()
	{
		/* Initialize */
		foreach(group; NeuronGroups)
		{
			group.CallInitKernel(StepWorkgroupSize);
		}
	}
	
	void RunUntil(int tstop)
	{
		/* Transfer to an array for faster iteration */
		auto groups = NeuronGroups.values;
		
		int t = T;
		/* Run the model */
		while(t < tstop)
		{
			/* Called first because it resets the record index to 0,
			 * so the update recorders wouldn't get anything if it was right 
			 * before it */
			foreach(group; groups)
				group.CallDeliverKernel(t, DeliverWorkgroupSize);
			foreach(group; groups)
				group.CallStepKernel(t, StepWorkgroupSize);
			foreach(group; groups)
				group.UpdateRecorders(t, t == tstop - 1);
			t++;
		}
			
		T = t;

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
			
		clReleaseProgram(Program);
		
		FloatMemsetKernel.Release();
		IntMemsetKernel.Release();
		
		FiredSynBuffer.Release();
		FiredSynIdxBuffer.Release();
		
		Generated = false;
	}
	
	void MemsetFloatBuffer(ref cl_mem buffer, int count, double value)
	{
		with(FloatMemsetKernel)
		{
			SetGlobalArg(0, &buffer);
			float_t val = value;
			SetGlobalArg(1, &val);
			SetGlobalArg(2, &count);
			size_t total_size = count;
			auto err = clEnqueueNDRangeKernel(Core.Commands, Kernel, 1, null, &total_size, null, 0, null, null);
			assert(err == CL_SUCCESS);
		}
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
	
	CCLBuffer!(int) FiredSynIdxBuffer;
	CCLBuffer!(int) FiredSynBuffer;
	
	/* Total model number of dest synapses */
	int NumDestSynapses = 0;
	int NumNeurons = 0;
	
	int StepWorkgroupSize = 64;
	int DeliverWorkgroupSize = 64;
	
	int T = 0;
	
	CCLCore Core;
	CNeuronGroup!(float_t)[char[]] NeuronGroups;
	char[] Source;
	bool Generated = false;
}

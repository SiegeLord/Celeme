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
		assert(number > 0, "Need at least 1 neuron in a group");
		
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
	
	void Generate(bool parallel_delivery = true, bool atomic_delivery = true, bool initialize = true)
	{
		assert(NumNeurons);
		assert(!Generated);
		assert(!Initialized);
		
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
			
		if(atomic_delivery)
		{
			Source ~= "#define USE_ATOMIC_DELIVERY 1\n";
			Source ~= "#pragma OPENCL EXTENSION cl_khr_local_int32_base_atomics : enable\n";
		}
		else
		{
			Source ~= "#define USE_ATOMIC_DELIVERY 0\n";
		}
			
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
		
		Generated = true;
		
		if(initialize)
			Initialize();
	}
	
	void Initialize()
	{
		assert(Generated);
		assert(!Initialized);
		
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
		
		Initialized = true;
		
		foreach(group; NeuronGroups)
			group.Initialize();
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
		assert(Initialized);
		
		T = 0;
		foreach(group; NeuronGroups)
		{
			group.ResetBuffers();
		}
	}
	
	void InitRun()
	{
		assert(Initialized);
		
		/* Initialize */
		foreach(group; NeuronGroups)
		{
			group.CallInitKernel(StepWorkgroupSize);
		}
	}
	
	void RunUntil(int tstop)
	{
		assert(Initialized);
		
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
		Initialized = false;
	}
	
	void MemsetFloatBuffer(ref cl_mem buffer, int count, double value)
	{
		assert(FloatMemsetKernel);
		
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
		assert(IntMemsetKernel);
		
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
	
	/*
	 * Connect a neuron at index src_nrn_id from src_group using its src_event_source and src_slot
	 * to a neuron at index dest_nrn_id from dest_group.
	 */
	void Connect(char[] src_group, int src_nrn_id, int src_event_source, int src_slot, char[] dest_group, int dest_nrn_id, int dest_slot)
	{
		assert(Initialized);
		
		auto src = opIndex(src_group);
		auto dest = opIndex(dest_group);
		
		assert(src_nrn_id >= 0 && src_nrn_id < src.Count, "Invalid source index.");
		assert(dest_nrn_id >= 0 && dest_nrn_id < dest.Count, "Invalid source index.");
		
		assert(src_event_source >= 0 && src_event_source < src.NumEventSources, "Invalid event source index.");
		assert(src_slot >= 0 && src_slot < src.NumSrcSynapses, "Invalid event source slot index.");
		
		assert(dest_slot >= 0 && dest_slot < dest.NumDestSynapses, "Invalid event source slot index.");
		
		src.ConnectTo(src_nrn_id, src_event_source, src_slot, dest.NrnOffset + dest_nrn_id, dest_slot);
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
	
	bool Initialized = false;
	bool Generated = false;
}

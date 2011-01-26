/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2011 Pavel Sountsov

Celeme is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Celeme is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Celeme. If not, see <http:#www.gnu.org/licenses/>.
*/

module celeme.clmodel;

import celeme.clcore;
import celeme.clrand;
import celeme.frontend;
import celeme.clneurongroup;
import celeme.util;
import celeme.imodel;
import celeme.ineurongroup;

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

class CCLModel(float_t) : IModel
{
	static if(is(float_t == float))
	{
		char[] NumStr = "float";
	}
	else static if(is(float_t == double))
	{
		char[] NumStr = "double";
	}
	else
	{
		static assert(0);
	}
	
	this(bool gpu)
	{
		Core = new CCLCore(gpu);
		RandsUsed[] = false;
	}
	
	override
	void AddNeuronGroup(CNeuronType type, int number, char[] name = null, bool adaptive_dt = true)
	{
		assert(!Generated, "Can't add neuron groups to generated models");
		assert(number > 0, "Need at least 1 neuron in a group");
		
		type.VerifyExternals();
		
		if(name is null || name == "")
			name = type.Name;
			
		if((name in NeuronGroups) !is null)
			throw new Exception("A group named '" ~ name ~ "' already exists in this model.");
		
		auto nrn_offset = NumNeurons;
		NumNeurons += number;
		
		auto sink_offset = NumDestSynapses;
		NumDestSynapses += number * type.NumDestSynapses;
		
		RandsUsed[type.RandLen] = true;
		
		auto group = new CNeuronGroup!(float_t)(this, type, number, name, sink_offset, nrn_offset, adaptive_dt);
		
		NeuronGroups[type.Name] = group;
	}
	
	override
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
		else
		{
			/*
			 * Dummies for parameters
			 */
			FiredSynIdxBuffer = Core.CreateBufferEx!(int)(1);
			FiredSynBuffer = Core.CreateBufferEx!(int)(1);
		}
		
		static if(is(float_t == double))
		{
			//Source ~= "#pragma OPENCL EXTENSION cl_khr_fp64 : enable\n";
			Source ~= "#pragma OPENCL EXTENSION cl_amd_fp64 : enable\n";
		}
		
		Source ~= "#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable\n";
		Source ~= "#pragma OPENCL EXTENSION cl_amd_printf : enable\n";
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
		
		/* RNG */
		bool need_rand = false;
		foreach(have_rand; RandsUsed[1..$])
			need_rand |= have_rand;
			
		if(need_rand)
			Source ~= RandComponents;
			
		foreach(ii, have_rand; RandsUsed[1..$])
		{
			if(have_rand)
				Source ~= RandCode[ii];
		}
			
		Source ~= FloatMemsetKernelTemplate;
		Source ~= IntMemsetKernelTemplate;
		foreach(group; NeuronGroups)
		{
			Source ~= group.StepKernelSource;
			Source ~= group.InitKernelSource;
			Source ~= group.DeliverKernelSource;
			foreach(conn; group.Connectors)
				Source ~= conn.KernelCode;
		}
		Source = Source.substitute("$num_type$", NumStr);
		//Stdout(Source).nl;
		Program = Core.BuildProgram(Source);
		Generated = true;
		
		if(initialize)
			Initialize();
	}
	
	override
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
	
	override
	INeuronGroup opIndex(char[] name)
	{
		return GetGroup(name);
	}
	
	CNeuronGroup!(float_t) GetGroup(char[] name)
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
	
	override
	void Run(int num_timesteps)
	{
		ResetRun();
		InitRun();
		RunUntil(num_timesteps);
	}
	
	override
	void ResetRun()
	{
		assert(Initialized);
		
		CurStep = 0;
		foreach(group; NeuronGroups)
		{
			group.ResetBuffers();
		}
	}
	
	override
	void InitRun()
	{
		assert(Initialized);
		
		/* Initialize */
		foreach(group; NeuronGroups)
		{
			group.CallInitKernel(StepWorkgroupSize);
		}
	}
	
	override
	void RunUntil(int num_timesteps)
	{
		assert(Initialized);
		
		/* Transfer to an array for faster iteration */
		auto groups = NeuronGroups.values;
		
		int t = CurStep;
		/* Run the model */
		while(t < num_timesteps)
		{
			double time = TimeStepSize * t;
			/* Called first because it resets the record index to 0,
			 * so the update recorders wouldn't get anything if it was right 
			 * before it */
			foreach(group; groups)
				group.CallDeliverKernel(time, DeliverWorkgroupSize);
			foreach(group; groups)
				group.CallStepKernel(time, StepWorkgroupSize);
			foreach(group; groups)
				group.UpdateRecorders(t, t == num_timesteps - 1);
			t++;
		}
			
		CurStep = t;

		Core.Finish();
		/* Check for errors */
		foreach(group; groups)
		{
			group.CheckErrors();
		}
	}
	
	override
	void Shutdown()
	{
		foreach(group; NeuronGroups)
			group.Shutdown();
		
		/* TODO: Add safe releases to all of these */
		if(Initialized)
		{				
			clReleaseProgram(Program);
			
			FloatMemsetKernel.Release();
			IntMemsetKernel.Release();
			
			FiredSynBuffer.Release();
			FiredSynIdxBuffer.Release();
		}
		
		Core.Shutdown();
		
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
	override
	void SetConnection(char[] src_group, int src_nrn_id, int src_event_source, int src_slot, char[] dest_group, int dest_nrn_id, int dest_syn_type, int dest_slot)
	{
		assert(Initialized);
		
		auto src = GetGroup(src_group);
		auto dest = GetGroup(dest_group);
		
		assert(src_nrn_id >= 0 && src_nrn_id < src.Count, "Invalid source index.");
		assert(dest_nrn_id >= 0 && dest_nrn_id < dest.Count, "Invalid destination index.");
		
		assert(src_event_source >= 0 && src_event_source < src.NumEventSources, "Invalid event source index.");
		assert(src_slot >= 0 && src_slot < src.NumSrcSynapses, "Invalid event source slot index.");
		
		assert(dest_syn_type >= 0 && dest_syn_type < dest.SynapseBuffers.length, "Invalid destination synapse type.");
		assert(dest_slot >= 0 && dest_slot < dest.SynapseBuffers[dest_syn_type].Count, "Invalid destination synapse index.");
		
		src.SetConnection(src_nrn_id, src_event_source, src_slot, dest.NrnOffset + dest_nrn_id, dest.GetSynapseTypeOffset(dest_syn_type) + dest_slot);
	}
	
	override
	bool Connect(char[] src_group, int src_nrn_id, int src_event_source, char[] dest_group, int dest_nrn_id, int dest_syn_type)
	{
		assert(Initialized);
		
		auto src = GetGroup(src_group);
		auto dest = GetGroup(dest_group);
		
		assert(src_nrn_id >= 0 && src_nrn_id < src.Count, "Invalid source index.");
		assert(dest_nrn_id >= 0 && dest_nrn_id < dest.Count, "Invalid destination index.");
		
		assert(src_event_source >= 0 && src_event_source < src.NumEventSources, "Invalid event source index.");
		
		assert(dest_syn_type >= 0 && dest_syn_type < dest.SynapseBuffers.length, "Invalid destination synapse type.");
		
		auto src_slot = src.GetSrcSlot(src_nrn_id, src_event_source);
		auto dest_slot = dest.GetDestSlot(dest_nrn_id, dest_syn_type);
		
		if(src_slot < 0 || dest_slot < 0)
			return false;
		
		src.SetConnection(src_nrn_id, src_event_source, src_slot, dest.NrnOffset + dest_nrn_id, dest.GetSynapseTypeOffset(dest_syn_type) + dest_slot);
		return true;
	}
	
	override
	void ApplyConnector(char[] connector_name, int multiplier, char[] src_group, int[2] src_nrn_range, int src_event_source, char[] dest_group, int[2] dest_nrn_range, int dest_syn_type, double[char[]] args = null)
	{
		assert(Initialized);
		
		auto src = GetGroup(src_group);
		auto dest = GetGroup(dest_group);
		
		assert(multiplier > 0, "Multiplier must be positive.");
		assert(src_nrn_range[0] >= 0 && src_nrn_range[0] < src.Count, "Invalid source range.");
		assert(src_nrn_range[1] > 0 && src_nrn_range[1] <= src.Count, "Invalid source range.");
		assert(dest_nrn_range[0] >= 0 && dest_nrn_range[0] < dest.Count, "Invalid destination range.");
		assert(dest_nrn_range[1] > 0 && dest_nrn_range[1] <= dest.Count, "Invalid destination range.");
		assert(src_nrn_range[1] > src_nrn_range[0], "Invalid source range.");
		assert(dest_nrn_range[1] > dest_nrn_range[0], "Invalid source range.");
		
		src.Connect(connector_name, multiplier, src_nrn_range, src_event_source, dest, dest_nrn_range, dest_syn_type, args);
	}
	
	override
	double TimeStepSize()
	{
		return TimeStepSizeVal;
	}
	
	override
	void TimeStepSize(double val)
	{
		TimeStepSizeVal = val;
	}
	
	bool[5] RandsUsed;
	
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
	
	int CurStep = 0;
	
	double TimeStepSizeVal = 1.0;
	
	CCLCore Core;
	CNeuronGroup!(float_t)[char[]] NeuronGroups;
	char[] Source;
	
	bool Initialized = false;
	bool Generated = false;
}

/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2011 Pavel Sountsov

Celeme is free software: you can redistribute it and/or modify
it under the terms of the Lesser GNU General Public License as published by
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
import celeme.iclmodel;
import celeme.ineurongroup;

import tango.text.Util;
import tango.io.Stdout;
import tango.time.StopWatch;

version (AMDPerf)
import perf = celeme.amdperf;

import opencl.cl;

class CCLModel(float_t) : ICLModel
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
			
		auto actual_number = (number / StepWorkgroupSize) * StepWorkgroupSize;
		if(actual_number < number)
			actual_number += StepWorkgroupSize;
		number = actual_number;
		
		auto nrn_offset = NumNeurons;
		NumNeurons += number;
		
		auto sink_offset = NumDestSynapses;
		NumDestSynapses += number * type.NumDestSynapses;
		
		RandsUsed[type.RandLen] = true;
		
		auto group = new CNeuronGroup!(float_t)(this, type, number, name, sink_offset, nrn_offset, adaptive_dt);
		
		NeuronGroups[name] = group;
	}
	
	override
	void Generate(bool parallel_delivery = true, bool atomic_delivery = true, bool initialize = true)
	{
		assert(NumNeurons);
		assert(!Generated);
		assert(!Initialized);
		
		if(NumDestSynapses)
		{
			FiredSynIdxBuffer = Core.CreateBuffer!(int)(NumNeurons);
			FiredSynBuffer = Core.CreateBuffer!(int)(NumDestSynapses);
		}
		else
		{
			/*
			 * Dummies for parameters
			 */
			FiredSynIdxBuffer = Core.CreateBuffer!(int)(1);
			FiredSynBuffer = Core.CreateBuffer!(int)(1);
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
		
		Source ~= `
		
		#define record(flags, data, tag) \
		if(record_flags & (flags)) \
		{ \
			int idx = atomic_inc(&record_idx[0]); \
			if(idx >= record_buffer_size) \
			{ \
				error_buffer[i + 1] = 10; \
				record_idx[0] = record_buffer_size - 1; \
			} \
			$num_type$4 record; \
			record.s0 = cur_time + t; \
			record.s1 = (data); \
			record.s2 = tag; \
			record.s3 = i; \
			record_buffer[idx] = record; \
		} \
		
		`;
		
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
		
		/* Set it to -1, so that when the neuron step functions are called,
		 * it gets reset automatically there */
		if(NumDestSynapses)
		{
			FiredSynIdxBuffer[] = -1;
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
		
		StopWatch timer;
		double step_est = 0;
		double deliver_est = 0;
		double record_est = 0;
		double finish_est = 0;
		
		version(Perf)
		{
			double step_total = 0;
			double deliver_total = 0;
			cl_event step_event = null;
			cl_event deliver_event = null;
		}
		
		int t = CurStep;
		/* Run the model */
		while(t < num_timesteps)
		{
			double time = TimeStepSize * t;
			
			version(AMDPerf)
			{
				perf.gpa_uint32 id;
				const prof_t = 112;
				if(t == prof_t)
				{
					perf.EnableCounters(1, "Wavefronts", "FastPath", "CompletePath");
					id = perf.BeginSP();
					perf.BeginSample("Deliver");
				}
			}

			/* Call the deliver kernel.
			 * Called first because it resets the record index to 0,
			 * so the update recorders wouldn't get anything if it was right 
			 * before it */
			timer.start;
			foreach(group; groups)
			{
				cl_event* event_ptr;
				version(Perf)
				{
					event_ptr = &deliver_event;
				}
				group.CallDeliverKernel(time, event_ptr);
			}
			deliver_est += timer.stop;
			
			version(AMDPerf)
			{
				if(t == prof_t)
				{
					perf.EndSample();
					perf.BeginSample("Step");
				}
			}

			/* Call the step kernel */
			timer.start;
			foreach(group; groups)
			{
				cl_event* event_ptr;
				version(Perf)
				{
					event_ptr = &step_event;
				}
				group.CallStepKernel(time, event_ptr);
			}
			step_est += timer.stop;
			
			version(AMDPerf)
			{
				if(t == prof_t)
				{
					perf.EndSample();
					perf.EndSP();
					Stdout(perf.GetSessionData(id)).nl;
				}
			}
			
			version(Perf)
			{
				Core.Finish();
				
				double get_dur(cl_event event)
				{
					cl_ulong start, end;
					auto ret = clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_START, start.sizeof, &start, null);
					assert(err == 0, GetCLErrorString(err));
					ret = clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_END, start.sizeof, &end, null);
					assert(err == 0, GetCLErrorString(err));
					
					return cast(double)(end - start) / (1.0e9);
				}
				
				if(step_event !is null)
					step_total += get_dur(step_event);
				if(deliver_event !is null)
					deliver_total += get_dur(deliver_event);
			}
			
			timer.start;	
			foreach(group; groups)
				group.UpdateRecorders(t, t == num_timesteps - 1);
			record_est += timer.stop;

			t++;
		}

		CurStep = t;
		
		timer.start;
		Core.Finish();
		finish_est = timer.stop;
		
		version(Perf)
		{
			println("True run times:");
			println("\tStep time: {:f8}", step_total);
			println("\tDeliver time: {:f8}", deliver_total);
		}
		
		println("Estimates:");
		println("\tStep: {:f8}", step_est);
		println("\tDeliver: {:f8}", deliver_est);
		println("\tRecord: {:f8}", record_est);
		println("\tFinish: {:f8}", finish_est);
		println("\tSum: {:f8}", step_est + deliver_est + record_est + finish_est);
		
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
			
			FiredSynBuffer.Release();
			FiredSynIdxBuffer.Release();
		}
		
		Core.Shutdown();
		
		Generated = false;
		Initialized = false;
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
	int StepWorkgroupSize()
	{
		return 64;
	}
	
	override
	int DeliverWorkgroupSize()
	{
		return 64;
	}
	
	mixin(Prop!("double", "TimeStepSize", "override", "override"));
	mixin(Prop!("cl_program", "Program", "override", "private"));
	mixin(Prop!("CCLBuffer!(int)", "FiredSynIdxBuffer", "override", "private"));
	mixin(Prop!("CCLBuffer!(int)", "FiredSynBuffer", "override", "private"));
	mixin(Prop!("bool", "Initialized", "override", "private"));
	mixin(Prop!("CCLCore", "Core", "override", "private"));
	
	cl_program ProgramVal;
	
	CCLBuffer!(int) FiredSynIdxBufferVal;
	CCLBuffer!(int) FiredSynBufferVal;
	
	bool[5] RandsUsed;
	
	/* Total model number of dest synapses */
	int NumDestSynapses = 0;
	int NumNeurons = 0;
	
	int CurStep = 0;
	
	double TimeStepSizeVal = 1.0;
	
	CCLCore CoreVal;
	CNeuronGroup!(float_t)[char[]] NeuronGroups;
	char[] Source;
	
	bool InitializedVal = false;
	bool Generated = false;
}

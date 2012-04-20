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

module celeme.internal.clmodel;

import celeme.internal.clcore;
import celeme.internal.clrand;
import celeme.internal.frontend;
import celeme.internal.clneurongroup;
import celeme.internal.util;
import celeme.internal.iclmodel;
import celeme.integrator_flags;
import celeme.ineurongroup;
import celeme.platform_flags;

import opencl.cl;
import dutil.Disposable;

import tango.text.Util;
import tango.io.Stdout;
import tango.time.StopWatch;
import tango.io.device.File;

class CCLModel(float_t) : CDisposable, ICLModel
{
	static if(is(float_t == float))
	{
		enum NumStr = "float";
	}
	else static if(is(float_t == double))
	{
		enum NumStr = "double";
	}
	else
	{
		static assert(0);
	}
	
	this(EPlatformFlags flags, size_t device_idx, CNeuronType[char[]] registry = null)
	{
		Core = new CCLCore(flags, device_idx);
		RandsUsed[] = false;
		Registry = registry;
	}
	
	override
	void AddNeuronGroup(cstring type_name, size_t number, cstring name = null, EIntegratorFlags integrator_type = EIntegratorFlags.Adaptive | EIntegratorFlags.Heun, bool parallel_delivery = true)
	{
		assert(Registry !is null, "No neuron types available.");
		
		auto type_ptr = type_name in Registry;
		if(type_ptr is null)
			throw new Exception("The registry has no neuron type named '" ~ type_name.idup ~ "'.");
		
		AddNeuronGroup(*type_ptr, number, name, integrator_type, parallel_delivery);
	}
	
	override
	void AddNeuronGroup(CNeuronType type, size_t number, cstring name = null, EIntegratorFlags integrator_type = EIntegratorFlags.Adaptive | EIntegratorFlags.Heun, bool parallel_delivery = true)
	{
		assert(!Generated, "Can't add neuron groups to generated models");
		assert(number > 0, "Need at least 1 neuron in a group");
		
		type.VerifyExternals();
		
		if(name is null || name == "")
			name = type.Name;
			
		if((name in NeuronGroups) !is null)
			throw new Exception("A group named '" ~ name.idup ~ "' already exists in this model.");

		number = cast(int)Core.GetGoodNumWorkitems(cast(int)number);
		
		auto nrn_offset = NumNeurons;
		NumNeurons += number;
		
		auto sink_offset = NumDestSynapses;
		NumDestSynapses += number * type.NumDestSynapses;
		
		RandsUsed[type.RandLen] = true;
		
		auto group = new CNeuronGroup!(float_t)(this, type, number, name, sink_offset, nrn_offset, integrator_type, parallel_delivery);
		
		NeuronGroups[name] = group;
	}
	
	override
	void Generate(bool initialize = true)
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
		Source ~= "#pragma OPENCL EXTENSION cl_khr_local_int32_base_atomics : enable\n";
		if(Core.PlatformFlags & EPlatformFlags.AMD)
			Source ~= "#pragma OPENCL EXTENSION cl_amd_printf : enable\n";
		
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
		
		auto file = new File("kernel.c", File.WriteCreate);
		file.write(Source);
		file.close();
		
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
	INeuronGroup opIndex(cstring name)
	{
		return GetGroup(name);
	}
	
	CNeuronGroup!(float_t) GetGroup(cstring name)
	{
		auto ret_ptr = name in NeuronGroups;
		if(ret_ptr is null)
			throw new Exception("No group named '" ~ name.idup ~ "' exists in this model");
		return *ret_ptr;
	}
	
	size_t NumSize()
	{
		return float_t.sizeof;
	}
	
	override
	void Run(size_t num_timesteps)
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
			group.CallInitKernel();
		}
	}
	
	override
	void RunUntil(size_t num_timesteps)
	{
		assert(Initialized);
		assert(num_timesteps > 1);
		
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
		
		size_t t = CurStep;
		/* Run the model */
		while(t < num_timesteps)
		{
			double time = TimeStepSize * t;

			/* Call the deliver kernel.
			 * Called first because it resets the record index to 0,
			 * so the update recorders wouldn't get anything if it was right 
			 * before it */
			timer.start();
			foreach(group; groups)
			{
				cl_event* event_ptr;
				version(Perf)
				{
					event_ptr = &deliver_event;
				}
				group.CallDeliverKernel(time, event_ptr);
			}
			version(Perf) Core.Finish();
			deliver_est += timer.stop();

			/* Call the step kernel */
			timer.start();
			foreach(group; groups)
			{
				cl_event* event_ptr;
				version(Perf)
				{
					event_ptr = &step_event;
				}
				group.CallStepKernel(time, event_ptr);
			}
			version(Perf) Core.Finish();
			step_est += timer.stop();
			
			version(Perf)
			{
				Core.Finish();
				
				double get_dur(cl_event event)
				{
					cl_ulong start, end;
					auto ret = clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_START, start.sizeof, &start, null);
					assert(ret == 0, GetCLErrorString(ret));
					ret = clGetEventProfilingInfo(event, CL_PROFILING_COMMAND_END, start.sizeof, &end, null);
					assert(ret == 0, GetCLErrorString(ret));
					
					return cast(double)(end - start) / (1.0e9);
				}
				
				if(step_event !is null)
					step_total += get_dur(step_event);
				if(deliver_event !is null)
					deliver_total += get_dur(deliver_event);
			}
			
			timer.start();	
			foreach(group; groups)
				group.UpdateRecorders(t, t == num_timesteps - 1);
			record_est += timer.stop();

			t++;
		}

		CurStep = t;
		
		timer.start();
		Core.Finish();
		finish_est = timer.stop();
		
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
	void Dispose()
	{
		foreach(group; NeuronGroups)
			group.Dispose();
		
		/* TODO: Add safe releases to all of these */
		if(Initialized)
		{				
			clReleaseProgram(Program);
			
			FiredSynBuffer.Dispose();
			FiredSynIdxBuffer.Dispose();
		}
		
		Core.Dispose();
		
		Generated = false;
		Initialized = false;
		
		super.Dispose();
	}
	
	/*
	 * Connect a neuron at index src_nrn_id from src_group using its src_event_source and src_slot
	 * to a neuron at index dest_nrn_id from dest_group.
	 */
	override
	void SetConnection(cstring src_group, size_t src_nrn_id, size_t src_event_source, size_t src_slot, cstring dest_group, size_t dest_nrn_id, size_t dest_syn_type, size_t dest_slot)
	{
		assert(Initialized);
		
		auto src = GetGroup(src_group);
		auto dest = GetGroup(dest_group);
		
		assert(src_nrn_id < src.Count, "Invalid source index.");
		assert(dest_nrn_id < dest.Count, "Invalid destination index.");
		
		assert(src_event_source < src.NumEventSources, "Invalid event source index.");
		assert(src_slot < src.NumSrcSynapses, "Invalid event source slot index.");
		
		assert(dest_syn_type < dest.SynapseBuffers.length, "Invalid destination synapse type.");
		assert(dest_slot < dest.SynapseBuffers[dest_syn_type].Count, "Invalid destination synapse index.");
		
		src.SetConnection(src_nrn_id, src_event_source, src_slot, dest.NrnOffset + dest_nrn_id, dest.GetSynapseTypeOffset(dest_syn_type) + dest_slot);
	}
	
	override
	SSlots Connect(cstring src_group, size_t src_nrn_id, size_t src_event_source, cstring dest_group, size_t dest_nrn_id, size_t dest_syn_type)
	{
		assert(Initialized);
		
		SSlots ret;
		ret.SourceSlot = -1;
		ret.DestSlot = -1;
		
		auto src = GetGroup(src_group);
		auto dest = GetGroup(dest_group);
		
		assert(src_nrn_id < src.Count, "Invalid source index.");
		assert(dest_nrn_id < dest.Count, "Invalid destination index.");
		
		assert(src_event_source < src.NumEventSources, "Invalid event source index.");
		
		assert(dest_syn_type < dest.SynapseBuffers.length, "Invalid destination synapse type.");
		
		auto src_slot = src.GetSrcSlot(src_nrn_id, src_event_source);
		auto dest_slot = dest.GetDestSlot(dest_nrn_id, dest_syn_type);
		
		if(src_slot < 0 || dest_slot < 0)
			return ret;
		
		src.SetConnection(src_nrn_id, src_event_source, src_slot, dest.NrnOffset + dest_nrn_id, dest.GetSynapseTypeOffset(dest_syn_type) + dest_slot);
		ret.SourceSlot = src_slot;
		ret.DestSlot = dest_slot;
		return ret;
	}
	
	override
	void ApplyConnector(cstring connector_name, size_t multiplier, cstring src_group, size_t[2] src_nrn_range, size_t src_event_source, cstring dest_group, size_t[2] dest_nrn_range, size_t dest_syn_type, double[char[]] args = null)
	{
		assert(Initialized);
		
		auto src = GetGroup(src_group);
		auto dest = GetGroup(dest_group);
		
		assert(multiplier > 0, "Multiplier must be positive.");
		assert(src_nrn_range[0] < src.Count, "Invalid source range.");
		assert(src_nrn_range[1] <= src.Count, "Invalid source range.");
		assert(dest_nrn_range[0] < dest.Count, "Invalid destination range.");
		assert(dest_nrn_range[1] <= dest.Count, "Invalid destination range.");
		assert(src_nrn_range[1] > src_nrn_range[0], "Invalid source range.");
		assert(dest_nrn_range[1] > dest_nrn_range[0], "Invalid destination range.");
		
		src.Connect(connector_name, multiplier, src_nrn_range, src_event_source, dest, dest_nrn_range, dest_syn_type, args);
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
	
	size_t CurStep = 0;
	
	double TimeStepSizeVal = 1.0;
	
	CCLCore CoreVal;
	CNeuronGroup!(float_t)[char[]] NeuronGroups;
	cstring Source;
	
	bool InitializedVal = false;
	bool Generated = false;
	
	bool NeedLocalAtomicPragma = false;
	
	CNeuronType[char[]] Registry;
}

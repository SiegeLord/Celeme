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

module celeme.internal.clneurongroup;

import celeme.internal.iclneurongroup;
import celeme.internal.frontend;
import celeme.internal.clcore;
import celeme.internal.clconnector;
import celeme.internal.iclmodel;
import celeme.internal.alignedarray;
import celeme.internal.sourceconstructor;
import celeme.internal.util;
import celeme.internal.integrator;
import celeme.internal.adaptiveheun;
import celeme.internal.heun;
import celeme.internal.euler;
import celeme.internal.clrand;
import celeme.internal.clmiscbuffers;

import celeme.ineurongroup;
import celeme.integrator_flags;
import celeme.recorder;

import opencl.cl;
import dutil.Disposable;
import dutil.Array;

import tango.io.Stdout;
import tango.text.Util;
import tango.util.Convert;
import tango.text.convert.Format;
import tango.core.Array;
import tango.util.MinMax;
//import stdc = tango.stdc.stdio;

const RecordSizeArgStep = 6;
const ArgOffsetStep = 7;
const StepKernelTemplate = `
#undef record
#define record(flags, data) \
if(_record_flags & (flags)) \
{ \
	int idx = atomic_inc(&_local_record_idx); \
	if(idx >= _record_buffer_size) \
	{ \
		_error_buffer[i + 1] = $record_error$; \
		_local_record_idx = _record_buffer_size - 1; \
	} \
	$num_type$4 record; \
	record.s0 = t; \
	record.s1 = (data); \
	record.s2 = flags; \
	record.s3 = i; \
	_record_buffer[idx + _local_record_idx_start] = record; \
} \


__kernel void $type_name$_step
	(
		const $num_type$ _t,
		__global int* _error_buffer,
		__global int* _record_flags_buffer,
		__global int* _record_idx,
		__global int* _record_idx_start,
		__global $num_type$4* _record_buffer,
		const int _record_buffer_size,
$rw_val_args$
$ro_val_args$
$constant_args$
$random_state_args$
$integrator_args$
$event_source_args$
$synapse_args$
$synapse_globals$
$syn_thresh_array_arg$
		const int count
	)
{
	int i = get_global_id(0);
	int _local_id = get_local_id(0);
	int _group_id = get_group_id(0);
	
$immutables$

$syn_threshold_status$

$primary_exit_condition_init$

	$num_type$ _cur_time = 0;
	const $num_type$ timestep = $time_step$;
	int _record_flags = _record_flags_buffer[i];
	
$record_load$
	
	$num_type$ _dt;
	$num_type$ t = _t;

$integrator_load$

$load_rw_vals$

$load_ro_vals$

$load_rand_state$

$synapse_code$

$pre_step_code$

	$barrier$
		
	while($primary_exit_condition$)
	{
		bool _any_thresh = false;
		
		/* Threshold statuses */
$threshold_status$

$syn_threshold_status_init$
			
		while(!_any_thresh && _cur_time < timestep)
		{
			t = _t + _cur_time;
			/* Post-thresh integrator code */
$integrator_post_thresh_code$

			$num_type$ _error = 0;
		
			/* See where the thresholded states are before changing them (doesn't work for synapse states)*/
$threshold_pre_check$

$syn_threshold_pre_check$

			/* Declare local variables */
$declare_locals$

			/* Pre-stage code */
$pre_stage_code$

			/* Integrator code */
$integrator_code$

			/* Detect thresholds */
$detect_thresholds$

$detect_syn_thresholds$
			/* Check exit condition */
$primary_exit_condition_check$
		}
		
		/* Handle thresholds */
$thresholds$

$syn_thresholds$
	}
$integrator_save$

$save_vals$

$save_rand_state$

$record_save$
}
`;

const ArgOffsetInit = 0;
const InitKernelTemplate = `
__kernel void $type_name$_init
	(
$rw_val_args$
$ro_val_args$
$constant_args$
$event_source_args$
		const int count
	)
{
	int i = get_global_id(0);
	if(i < count)
	{
$immutables$

		/* Load values */
$load_rw_vals$

$load_ro_vals$
		
		/* Perform initialization */
$init_vals$
		
		/* Put them back */
$save_vals$
	}
}
`;

const ArgOffsetDeliver = 4;
const DeliverKernelTemplate = "
__kernel void $type_name$_deliver
	(
		const $num_type$ _t,
		__global int* _error_buffer,
		__global int* _record_idx,
		const int _record_rate,
$event_source_args$
		const uint count
	)
{
	int i = get_global_id(0);
	int _local_id = get_local_id(0);
	
	if(_local_id == 0 && _record_rate && ((int)(_t / $time_step$) % _record_rate == 0))
	{
		_record_idx[get_group_id(0)] = 0;
	}

$parallel_init$
	
	/* Max number of source synapses */
	const int num_synapses = $num_synapses$;
	(void)num_synapses;
	
$event_source_code$

$parallel_delivery_code$
}
";

enum
{
	RECORD_ERROR = 1,
	CIRC_BUFFER_ERROR = 2
}

class CNeuronGroup(float_t) : CDisposable, ICLNeuronGroup
{
	static if(is(float_t == float))
	{
		alias cl_float4 float_t4;
	}
	else static if(is(float_t == double))
	{
		alias cl_double4 float_t4;
	}
	else
	{
		static assert(0);
	}
	
	this(ICLModel model, CNeuronType type, size_t count, size_t workgroup_size, cstring name, size_t sink_offset, size_t nrn_offset, EIntegratorFlags integrator_type = EIntegratorFlags.Adaptive | EIntegratorFlags.Heun, bool parallel_delivery = true)
	{
		Model = model;
		CountVal = count;
		WorkgroupSize = workgroup_size;
		Name = name;
		NumEventSources = type.NumEventSources;
		RecordLength = type.RecordLength;
		RecordRate = type.RecordRate;
		CircBufferSize = type.CircBufferSize;
		SynOffset = sink_offset;
		NrnOffset = nrn_offset;
		NumDestSynapses = type.NumDestSynapses;
		NumSrcSynapses = type.NumSrcSynapses;
		MinDt = type.MinDt;
		Parallel = parallel_delivery;
		NeedUnMap = true;
		
		RandLen = type.RandLen;
		switch(RandLen)
		{
			case 1:
				Rand = new CCLRandImpl!(1)(Core, Count);
				break;
			case 2:
				Rand = new CCLRandImpl!(2)(Core, Count);
				break;
			case 3:
				assert(0, "Unsupported rand length");
			case 4:
				assert(0, "Unsupported rand length");
				//Rand = new CCLRandImpl!(4)(Core, Count);
			default:
		}
		
		foreach(conn; type.Connectors)
		{
			Connectors[conn.Name] = new CCLConnector!(float_t)(this, conn);
		}
		
		size_t tuple_size = (1 * float.sizeof) / float_t.sizeof;
		tuple_size = max(tuple_size, 1UL);
		
		RWValues = new CMultiBuffer!(float_t)("rwvalues", tuple_size, Count, 16, true, true, true);
		ROValues = new CMultiBuffer!(float_t)("rovalues", tuple_size, Count, 16, true, false, true);
		
		/* Copy the non-locals from the type */
		foreach(name, state; &type.AllNonLocals)
		{
			if(state.ReadOnly)
				ROValues.AddValue(Core, name, state.Value);
			else
				RWValues.AddValue(Core, name, state.Value);
		}
		
		/* Syn globals are special, so they get treated separately */
		foreach(syn_type; type.SynapseTypes)
		{
			foreach(val; &syn_type.Synapse.AllSynGlobals)
			{
				auto name = syn_type.Prefix == "" ? val.Name : syn_type.Prefix ~ "_" ~ val.Name;
				
				SynGlobalBufferRegistry[name] = SynGlobalBuffers.length;
				SynGlobalBuffers ~= new CSynGlobalBuffer!(float_t)(val, Core, Count * syn_type.NumSynapses);
				SynGlobalBuffers[$ - 1].Buffer.MapReadWrite();
			}
		}
		
		int syn_type_offset = 0;
		foreach(syn_type; type.SynapseTypes)
		{
			auto syn_buff = new CSynapseBuffer(Core, syn_type_offset, syn_type.NumSynapses, Count, true);
			SynapseBuffers = SynapseBuffers ~ syn_buff;
			
			syn_type_offset += syn_type.NumSynapses;
		}
		
		foreach(ii; range(NumEventSources))
		{
			EventSourceBuffers = EventSourceBuffers ~ new CEventSourceBuffer(Core, Count, true);
		}
		
		if(NeedSrcSynCode)
		{
			CircBufferStart = Core.CreateBuffer!(int)(NumEventSources * Count);
			CircBufferEnd = Core.CreateBuffer!(int)(NumEventSources * Count);
			CircBuffer = Core.CreateBuffer!(float_t)(CircBufferSize * NumEventSources * Count);
		}
		
		ErrorBuffer = Core.CreateBuffer!(int)(Count + 1, false, true);
		RecordFlagsBuffer = Core.CreateBuffer!(int)(Count, true, false);
		RecordBuffer = Core.CreateBuffer!(float_t4)(RecordLength, false, true);
		RecordIdxBuffer = Core.CreateBuffer!(cl_int)(Count / WorkgroupSize);
		RecordIdxBufferStart = Core.CreateBuffer!(cl_int)(Count / WorkgroupSize, true, false);
		
		Recorder = new CRecorder;
		
		if(NeedSrcSynCode)
		{
			DestSynBuffer = Core.CreateBuffer!(cl_int2)(Count * NumEventSources * NumSrcSynapses, true, true, NumSrcSynapses);
		}

		foreach(name, state; &type.AllConstants)
		{
			ConstantRegistry[name] = Constants.length;
			
			Constants ~= state.Value;
		}
		
		if(integrator_type & EIntegratorFlags.Heun)
		{
			if(integrator_type & EIntegratorFlags.Adaptive)
				Integrator = new CAdaptiveHeun!(float_t)(this, type);
			else
				Integrator = new CHeun!(float_t)(this, type);
		}
		else if(integrator_type & EIntegratorFlags.Euler)
		{
			Integrator = new CEuler!(float_t)(this, type);
		}
		else
		{
			throw new Exception("Invalid integrator type for neuron group '" ~ name.idup ~ "'.");
		}
		
		/* Create kernel sources */
		CreateStepKernel(type);
		CreateInitKernel(type);
		CreateDeliverKernel(type);
	}
	
	void UnMapBuffers()
	{
		DestSynBuffer.UnMap();
		foreach(buf; EventSourceBuffers)
			buf.FreeIdx.UnMap();
		foreach(buf; SynapseBuffers)
			buf.FreeIdx.UnMap();
		foreach(buf; SynGlobalBuffers)
			buf.Buffer.UnMap();
		RWValues.UnMapBuffers();
		ROValues.UnMapBuffers();
		NeedUnMap = false;
	}
	
	override
	void MapBuffers(const(char)[] variable)
	{
		if(variable == "")
		{
			DestSynBuffer.MapReadWrite();
			foreach(buf; EventSourceBuffers)
				buf.FreeIdx.MapReadWrite();
			foreach(buf; SynapseBuffers)
				buf.FreeIdx.MapReadWrite();
			foreach(buf; SynGlobalBuffers)
				buf.Buffer.MapReadWrite();
			RWValues.MapBuffers();
			ROValues.MapBuffers();
		}
		else
		{
			if(RWValues.HaveValue(variable))
			{
				RWValues.MapBuffers(variable);
				return;
			}
				
			if(ROValues.HaveValue(variable))
			{
				ROValues.MapBuffers(variable);
				return;
			}
			
			auto idx_ptr = variable in SynGlobalBufferRegistry;
			if(idx_ptr !is null)
			{
				SynGlobalBuffers[*idx_ptr].Buffer.MapReadWrite();
				return;
			}
			
			throw new Exception("Neuron group '" ~ Name.idup ~ "' does not have a '" ~ variable.idup ~ "' variable.");
		}
		
		NeedUnMap = true;
	}
	
	/* Call this after the program has been created, as we need the memset kernel
	 * and to create the local kernels*/
	void Initialize()
	{
		size_t arg_id;
		/* Step kernel */
		auto program = Program;
		StepKernel = Core.CreateKernel(program, Name ~ "_step");
		
		with(StepKernel)
		{
			/* Set the arguments. Start at 1 to skip the t argument*/
			arg_id = 1;
			SetGlobalArg(arg_id++, ErrorBuffer);
			SetGlobalArg(arg_id++, RecordFlagsBuffer);
			SetGlobalArg(arg_id++, RecordIdxBuffer);
			SetGlobalArg(arg_id++, RecordIdxBufferStart);
			SetGlobalArg(arg_id++, RecordBuffer);
			SetGlobalArg(arg_id++, RecordLength);
			arg_id = RWValues.SetArgs(StepKernel, arg_id);
			arg_id = ROValues.SetArgs(StepKernel, arg_id);
			arg_id += Constants.length;
			if(NeedRandArgs)
				arg_id = Rand.SetArgs(StepKernel, arg_id);
			arg_id = Integrator.SetArgs(StepKernel, arg_id);
			if(NeedSrcSynCode)
			{
				/* Set the event source args */
				SetGlobalArg(arg_id++, CircBufferStart);
				SetGlobalArg(arg_id++, CircBufferEnd);
				SetGlobalArg(arg_id++, CircBuffer);
			}
			if(NumDestSynapses)
			{
				SetGlobalArg(arg_id++, Model.FiredSynIdxBuffer);
				SetGlobalArg(arg_id++, Model.FiredSynBuffer);
				foreach(buffer; SynGlobalBuffers)
				{
					SetGlobalArg(arg_id++, buffer.Buffer);
				}
			}
			if(Parallel)
			{
				foreach(_; range(NumSynThresholds))
				{
					SetLocalArg(arg_id++, int.sizeof * WorkgroupSize);
				}
			}
			SetGlobalArg(arg_id++, cast(int)Count);
		}
		
		/* Init kernel */
		InitKernel = Core.CreateKernel(Program, Name ~ "_init");
		with(InitKernel)
		{
			/* Nothing to skip, so set it at 0 */
			arg_id = 0;
			arg_id = RWValues.SetArgs(InitKernel, arg_id);
			arg_id = ROValues.SetArgs(InitKernel, arg_id);
			arg_id += Constants.length;
			if(NeedSrcSynCode)
			{
				SetGlobalArg(arg_id++, DestSynBuffer);
			}
			SetGlobalArg(arg_id++, cast(int)Count);
		}
		
		/* Deliver kernel */
		DeliverKernel = Core.CreateKernel(Program, Name ~ "_deliver");
		
		with(DeliverKernel)
		{
			/* Set the arguments. Start at 1 to skip the t argument*/
			arg_id = 1;
			SetGlobalArg(arg_id++, ErrorBuffer);
			SetGlobalArg(arg_id++, RecordIdxBuffer);
			SetGlobalArg(arg_id++, RecordRate);
			if(NeedSrcSynCode)
			{
				/* Local fire table */
				SetLocalArg(arg_id++, int.sizeof * WorkgroupSize * NumEventSources);
				/* Set the event source args */
				SetGlobalArg(arg_id++, CircBufferStart);
				SetGlobalArg(arg_id++, CircBufferEnd);
				SetGlobalArg(arg_id++, CircBuffer);
				SetGlobalArg(arg_id++, DestSynBuffer);
				SetGlobalArg(arg_id++, Model.FiredSynIdxBuffer);
				SetGlobalArg(arg_id++, Model.FiredSynBuffer);
			}
			SetGlobalArg(arg_id++, cast(int)Count);
		}
		
		Core.Finish();
		
		RecordFlagsBuffer[] = 0;
		
		DestSynBuffer().MapReadWrite();
		DestSynBuffer()[] = cl_int2(-1, -1);
		
		foreach(conn; Connectors)
			conn.Initialize();
		
		ResetBuffers();
	}
	
	@property
	bool NeedSrcSynCode()
	{
		/* Don't need it if the type of this neuron group has no event sources. 
		 * Obviously we need src slots too */
		return NumEventSources && NumSrcSynapses;
	}
	
	void ResetBuffers()
	{
		assert(Model.Initialized);
		
		/* Set the constants. Here because SetConstant sets it to both kernels, so both need
		 * to be created
		 */
		foreach(ii, _; Constants)
		{
			SetConstant(ii);
		}
		
		Integrator.Reset();
		if(RandLen)
			Rand.Seed();
		
		/* Initialize the buffers */
		ErrorBuffer()[] = 0;
		RecordIdxBuffer[] = 0;
		SetRecordSizeAndStart();
		
		if(NeedSrcSynCode)
		{
			CircBufferStart[] = -1;
			CircBufferEnd[] = 0;
		}
		
		/* Write the default values to the global buffers*/
		RWValues.Reset();
		ROValues.Reset();
		
		foreach(buffer; SynGlobalBuffers)
		{
			buffer.Buffer[] = buffer.DefaultValue;
		}
		Core.Finish();

		NeedUnMap = true;
	}
	
	void SetConstant(size_t idx)
	{
		assert(Model.Initialized);
		
		float_t val = Constants[idx];
		InitKernel.SetGlobalArg(idx + ValArgsOffset + ArgOffsetInit, val);
		StepKernel.SetGlobalArg(idx + ValArgsOffset + ArgOffsetStep, val);
	}
	
	final void CallInitKernel(cl_event* ret_event = null)
	{
		assert(Model.Initialized);
		
		if(NeedUnMap)
			UnMapBuffers();

		InitKernel.Launch([Count], [WorkgroupSize], ret_event);
	}
	
	final void CallStepKernel(double sim_time, cl_event* ret_event = null)
	{
		assert(Model.Initialized);
		
		if(NeedUnMap)
			UnMapBuffers();

		with(StepKernel)
		{
			SetGlobalArg(0, cast(float_t)sim_time);
			Launch([Count], [WorkgroupSize], ret_event);
		}
	}
	
	final void CallDeliverKernel(double sim_time, cl_event* ret_event = null)
	{
		assert(Model.Initialized);
		
		if(NeedUnMap)
			UnMapBuffers();
		
		with(DeliverKernel)
		{
			SetGlobalArg(0, cast(float_t)sim_time);
			Launch([Count], [WorkgroupSize], ret_event);
		}
	}
	
	private void CreateStepKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto kernel_source = new CCode(StepKernelTemplate);
		
		kernel_source["$type_name$"] = Name;
		
		/* RW Value arguments */
		source.Tab(2);
		source.AddBlock(RWValues.ArgsCode);
		source.Inject(kernel_source, "$rw_val_args$");
		
		/* RO Value arguments */
		source.Tab(2);
		source.AddBlock(ROValues.ArgsCode);
		source.Inject(kernel_source, "$ro_val_args$");
		
		/* Constant arguments */
		source.Tab(2);
		foreach(name, state; &type.AllConstants)
		{
			source ~= "const $num_type$ " ~ name ~ ",";
		}
		source.Inject(kernel_source, "$constant_args$");
		
		/* Integrator arguments */
		source.Tab(2);
		source.AddBlock(Integrator.GetArgsCode(type));
		source.Inject(kernel_source, "$integrator_args$");
		
		/* Event source args */
		source.Tab(2);
		if(NeedSrcSynCode)
		{
			source ~= "__global int* _circ_buffer_start,";
			source ~= "__global int* _circ_buffer_end,";
			source ~= "__global $num_type$* _circ_buffer,";
		}
		source.Inject(kernel_source, "$event_source_args$");
		
		/* Synapse args */
		source.Tab(2);
		if(NumDestSynapses)
		{
			source ~= "__global int* _fired_syn_idx_buffer,";
			source ~= "__global int* _fired_syn_buffer,";
		}
		source.Inject(kernel_source, "$synapse_args$");
		
		/* Synapse globals */
		source.Tab(2);
		if(NumDestSynapses)
		{
			foreach(name, val; &type.AllSynGlobals)
			{
				source ~= "__global $num_type$* _" ~ name ~ "_buf,";
			}
		}
		source.Inject(kernel_source, "$synapse_globals$");
		
		/* Immutables */
		source.Tab;
		foreach(name, val; &type.AllImmutables)
		{
			source ~= "const $num_type$ " ~ name ~ " = " ~ Format("{:e6}", val.Value) ~ ";";
		}
		foreach(name; &type.MissingTolerances)
		{
			source ~= "const $num_type$ " ~ name ~ " = 0.1;";
		}
		source.Inject(kernel_source, "$immutables$");
		
		/* Record load */
		source.Tab;
		if(Parallel)
		{
			source.AddBlock(
`__local int _local_record_idx;
__local int _local_record_idx_start;
if(_local_id == 0)
{
	_local_record_idx = _record_idx[_group_id];
	_local_record_idx_start = _record_idx_start[_group_id];
}`);
		}
		else
		{
			/* Global atomics are as fast as local ones on the CPU, so use them instead.
			 */
			source.AddBlock(
`#define _local_record_idx _record_idx[_group_id]
int _local_record_idx_start = _record_idx_start[_group_id];
`);
		}
		source.Inject(kernel_source, "$record_load$");
		
		/* Integrator load */
		source.Tab;
		source.AddBlock(Integrator.GetLoadCode(type));
		source.Inject(kernel_source, "$integrator_load$");
		
		/* Load RW vals */
		source.Tab;
		source.AddBlock(RWValues.LoadCode);
		source.Inject(kernel_source, "$load_rw_vals$");
		
		/* Load RO vals */
		source.Tab;
		source.AddBlock(ROValues.LoadCode);
		source.Inject(kernel_source, "$load_ro_vals$");
		
		/* Synapse code */
		source.Tab;
		if(NumDestSynapses)
		{
			scope all_syn_code = new CCode(
`const int _syn_offset = $syn_offset$ + i * $num_dest_synapses$;
int _syn_table_end = _fired_syn_idx_buffer[i + $nrn_offset$];
if(_syn_table_end != _syn_offset)
{
	for(int _syn_table_idx = _syn_offset; _syn_table_idx < _syn_table_end; _syn_table_idx++)
	{
		int syn_i = _fired_syn_buffer[_syn_table_idx];
		
$syns_code$
	}
	
	reset_dt();
	_fired_syn_idx_buffer[i + $nrn_offset$] = _syn_offset;
}`);
			scope syns_source = new CSourceConstructor();
			syns_source.Tab(2);
			
			int syn_type_offset = 0;
			int syn_type_start = 0;
			foreach(ii, syn_type; type.SynapseTypes)
			{
				scope full_syn_code = new CCode(
`$else$
if(syn_i < $syn_type_offset$)
{
	int _g_syn_i = syn_i - $syn_type_start$ + i * $syn_type_num$;
	/* Load values */
$load_vals$
	/* Syn code */
$syn_code$
	/* Save values */
$save_vals$

}`);
				scope full_syn_source = new CSourceConstructor();
				
				syn_type_offset += syn_type.NumSynapses;

				full_syn_code["$else$"] = ii == 0 ? "" : "else";
				
				auto prefix = syn_type.Prefix;
				/* Apply the prefix to the syn code */
				auto syn_code = syn_type.Synapse.SynCode;
				if(syn_type.Prefix != "")
				{
					foreach(val; &syn_type.Synapse.AllValues)
						syn_code = syn_code.c_substitute(val.Name, prefix ~ "_" ~ val.Name);
					foreach(val; &syn_type.Synapse.AllSynGlobals)
						syn_code = syn_code.c_substitute(val.Name, prefix ~ "_" ~ val.Name);
				}
				
				/* Load values */
				full_syn_source.Tab;
				foreach(val; &syn_type.Synapse.AllSynGlobals)
				{
					auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
					if(syn_code.c_find(name) != syn_code.length)
						full_syn_source ~= Format("$num_type$ {0} = _{0}_buf[_g_syn_i];", name);
				}
				full_syn_source.Inject(full_syn_code, "$load_vals$");
				
				/* Synapse code */
				full_syn_source.Tab;
				full_syn_source.AddBlock(syn_code);
				full_syn_source.Inject(full_syn_code, "$syn_code$");
				
				/* Save values */
				full_syn_source.Tab;
				foreach(val; &syn_type.Synapse.AllSynGlobals)
				{
					if(!val.ReadOnly)
					{
						auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
						if(syn_code.c_find(name) != syn_code.length)
							full_syn_source ~= Format("_{0}_buf[_g_syn_i] = {0};", name);
					}
				}
				full_syn_source.Inject(full_syn_code, "$save_vals$");
				
				full_syn_code["$syn_type_offset$"] = syn_type_offset;
				full_syn_code["$syn_type_start$"] = syn_type_start;
				full_syn_code["$syn_type_num$"] = syn_type.NumSynapses;
				
				syns_source.AddBlock(full_syn_code);
				
				syn_type_start = syn_type_offset;
			}
			
			syns_source.Inject(all_syn_code, "$syns_code$");
			
			all_syn_code["$num_dest_synapses$"] = NumDestSynapses;
			all_syn_code["$nrn_offset$"] = NrnOffset;
			all_syn_code["$syn_offset$"] = SynOffset;
			
			source.AddBlock(all_syn_code);
		}
		source.Inject(kernel_source, "$synapse_code$");
		
		/* Pre-step code */
		source.Tab;
		source.AddBlock(type.GetPreStepSource());
		source.Inject(kernel_source, "$pre_step_code$");
		
		/* Syn threshold statuses */
		source.Tab;
		int thresh_idx = 0;
		foreach(thresh; &type.AllSynThresholds)
		{
			if(Parallel)
				source ~= Format("__local int _syn_thresh_{}_num;", thresh_idx);
			thresh_idx++;
		}
		NumSynThresholds = thresh_idx;
		if(NumSynThresholds)
		{
			if(Parallel)
				source ~= "int _local_size = get_local_size(0);";
		}
		source.Inject(kernel_source, "$syn_threshold_status$");
		
		/* Primary exit condition */
		source.Tab;
		if(NumSynThresholds && Parallel)
		{
			source.AddBlock(
`__local int _num_complete;
if(_local_id == 0)
	_num_complete = 0;
`);
		}
		source.Inject(kernel_source, "$primary_exit_condition_init$");
		
		if(NumSynThresholds && Parallel)
			kernel_source["$primary_exit_condition$"] = "_num_complete < _local_size";
		else
			kernel_source["$primary_exit_condition$"] = "_cur_time < timestep";
		
		source.Tab(3);
		if(NumSynThresholds && Parallel)
		{
			source.AddBlock(
`if(_cur_time >= timestep)
		atomic_inc(&_num_complete);`);
		}
		source.Inject(kernel_source, "$primary_exit_condition_check$");
		
		if(Parallel)
		{
			source.Tab;
			thresh_idx = 0;
			if(NumSynThresholds)
			{
				foreach(thresh; &type.AllSynThresholds)
				{
					source ~= Format("__local int* _syn_thresh_{}_arr,", thresh_idx);
					thresh_idx++;
				}
			}
		}
		source.Inject(kernel_source, "$syn_thresh_array_arg$");
		
		/* Threshold statuses (and non-parallel syn threshold statuses) */
		source.Tab(2);
		thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			source ~= Format("bool thresh_{}_state = false;", thresh_idx);
			thresh_idx++;
		}
		NumThresholds = thresh_idx;
		if(!Parallel)
		{
			thresh_idx = 0;
			foreach(syn_thresh; &type.AllSynThresholds)
			{
				source ~= Format("bool syn_thresh_{}_state = false;", thresh_idx);
				thresh_idx++;
			}
		}
		source.Inject(kernel_source, "$threshold_status$");
		
		/* Syn threshold statuses init */
		source.Tab(2);
		if(Parallel)
		{
			thresh_idx = 0;
			if(NumSynThresholds)
			{
				scope block = new CCode(
`if(_local_id == 0)
{
$thresh_set$
}
barrier(CLK_LOCAL_MEM_FENCE);`);

				scope block_source = new CSourceConstructor;
				block_source.Tab;
				foreach(thresh; &type.AllSynThresholds)
				{
					block_source ~= Format("_syn_thresh_{}_num = 0;", thresh_idx);
					thresh_idx++;
				}
				block_source.Inject(block, "$thresh_set$");
				source.AddBlock(block);
			}
		}
		source.Inject(kernel_source, "$syn_threshold_status_init$");
		
		/* Threshold pre-check */
		source.Tab(3);
		thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			source ~= Format("bool thresh_{}_pre_state = {} {};", thresh_idx, thresh.State, thresh.Condition);
			thresh_idx++;
		}
		source.Inject(kernel_source, "$threshold_pre_check$");
		
		/* Syn threshold pre-check */
		source.Tab(3);
		thresh_idx = 0;
		foreach(thresh; &type.AllSynThresholds)
		{
			source ~= Format("bool syn_thresh_{}_pre_state = {} {};", thresh_idx, thresh.State, thresh.Condition);
			thresh_idx++;
		}
		source.Inject(kernel_source, "$syn_threshold_pre_check$");
		
		/* Declare locals */
		source.Tab(3);
		foreach(name, state; &type.AllLocals)
		{
			source ~= Format("$num_type$ {};", name);
		}
		source.Inject(kernel_source, "$declare_locals$");
		
		/* Pre-stage code */
		source.Tab(3);
		source.AddBlock(type.GetPreStageSource());
		source.Inject(kernel_source, "$pre_stage_code$");
		
		/* Integrator code */
		source.Tab(3);
		source.AddBlock(Integrator.GetIntegrateCode(type));
		source.Inject(kernel_source, "$integrator_code$");
		
		/* Detect thresholds */
		source.Tab(3);
		int event_src_idx = 0;
		thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			scope block = new CCode(
`thresh_$thresh_idx$_state = !thresh_$thresh_idx$_pre_state && ($thresh_state$ $thresh_cond$);
_any_thresh |= thresh_$thresh_idx$_state;
`);
			
			block["$thresh_idx$"] = thresh_idx;
			block["$thresh_state$"] = thresh.State;
			block["$thresh_cond$"] = thresh.Condition;
			
			source.AddBlock(block);
			
			thresh_idx++;
		}
		source.Inject(kernel_source, "$detect_thresholds$");
		
		/* Detect syn thresholds */
		source.Tab(3);
		thresh_idx = 0;
		foreach(thresh; &type.AllSynThresholds)
		{
			scope block = new CCode;
			if(Parallel)
			{
				block = 
`if(!syn_thresh_$thresh_idx$_pre_state && ($thresh_state$ $thresh_cond$))
{
	_any_thresh = true;
	_syn_thresh_$thresh_idx$_arr[atomic_inc(&_syn_thresh_$thresh_idx$_num)] = i;
}
`;
			}
			else
			{
				block = 
`syn_thresh_$thresh_idx$_state = !syn_thresh_$thresh_idx$_pre_state && ($thresh_state$ $thresh_cond$);
_any_thresh |= syn_thresh_$thresh_idx$_state;
`;
			}
			
			block["$thresh_idx$"] = thresh_idx;
			block["$thresh_state$"] = thresh.State;
			block["$thresh_cond$"] = thresh.Condition;
			
			source.AddBlock(block);
			
			thresh_idx++;
		}
		source.Inject(kernel_source, "$detect_syn_thresholds$");
		
		/* Thresholds */
		source.Tab(2);
		event_src_idx = 0;
		thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			scope block = new CCode(
`if(thresh_$thresh_idx$_state)
{
$set_delay$
$thresh_source$
$reset_dt$
$event_src_code$
}
`);
			scope block_source = new CSourceConstructor;
			/* Set delay */
			block_source.Tab;
			if(thresh.IsEventSource)
				block_source ~= "$num_type$ delay = 1.0f;";
			block_source.Inject(block, "$set_delay$");
			
			/* Thresh source */
			block_source.Tab;
			block_source.AddBlock(thresh.Source);
			block_source.Inject(block, "$thresh_source$");
			
			/* Reset time */
			block_source.Tab;
			if(thresh.ResetTime)
				block_source ~= "reset_dt();";
			block_source.Inject(block, "$reset_dt$");
			
			/* Event src code */
			block_source.Tab;
			if(NeedSrcSynCode && thresh.IsEventSource)
			{
				scope src_code = new CCode(
`const int _idx_idx = $num_event_sources$ * i + $event_source_idx$;
const int _buff_start = _circ_buffer_start[_idx_idx];
const int _buff_end = _circ_buffer_end[_idx_idx];

if(_buff_start != _buff_end)
{
	const int _circ_buffer_size = $circ_buffer_size$;
	
	int _cur_idx;
	int _end_idx;
	if(_buff_start < 0) //It is empty
	{
		_circ_buffer_start[_idx_idx] = 0;
		_end_idx = 1;
		_cur_idx = 0;
	}
	else
	{
		_end_idx = (_buff_end + 1) % _circ_buffer_size;
		_cur_idx = _buff_end;
	}
	const int _buff_idx = (i * $num_event_sources$ + $event_source_idx$) * _circ_buffer_size + _cur_idx;
	_circ_buffer[_buff_idx] = t + delay;
	_circ_buffer_end[_idx_idx] = _end_idx;
}
else //It is full, error
{
	_error_buffer[i + 1] = $circ_buffer_error$ + $event_source_idx$;
	//Prevent the deliver code from delivering
	_circ_buffer_start[_idx_idx] = -1;
	_circ_buffer_end[_idx_idx] = -1;
}`);
				src_code["$circ_buffer_size$"] = CircBufferSize;
				src_code["$num_event_sources$"] = NumEventSources;
				src_code["$event_source_idx$"] = event_src_idx;
				
				block_source.AddBlock(src_code);
				
				event_src_idx++;
/* TODO: Better error reporting */
			}
			block_source.Inject(block, "$event_src_code$");
			
			block["$thresh_idx$"] = thresh_idx;
			
			source.AddBlock(block);
			
			thresh_idx++;
		}
		source.Inject(kernel_source, "$thresholds$");
		
		/* Syn thresholds */
		source.Tab(2);
		thresh_idx = 0;
		foreach(syn_type, thresh; &type.AllSynThresholdsEx)
		{
			scope block = new CCode;
			if(Parallel)
			{
				block = 
`
barrier(CLK_LOCAL_MEM_FENCE);
if(_syn_thresh_$thresh_idx$_num > 0)
{
	for(int _ii = 0; _ii < _syn_thresh_$thresh_idx$_num; _ii++)
	{
		int nrn_id = _syn_thresh_$thresh_idx$_arr[_ii];
		/* Declare locals */
$declare_locals$
		
		/* Init locals */
		if(i == nrn_id)
		{
$init_locals$			
		}
		barrier(CLK_LOCAL_MEM_FENCE);
		
		int _syn_offset = nrn_id * $num_syn$;
		for(int _g_syn_i = _syn_offset + _local_id; _g_syn_i < $num_syn$ + _syn_offset; _g_syn_i += _local_size)
		{
			/* Load syn globals */
$load_syn_globals$
			/* Thresh source */
$thresh_src$
			/* Save syn globals */
$save_syn_globals$
		}
	}
}
`;
			}
			else
			{
				block = 
`
if(syn_thresh_$thresh_idx$_state)
{
		int _syn_offset = i * $num_syn$;
		for(int _g_syn_i = _syn_offset; _g_syn_i < $num_syn$ + _syn_offset; _g_syn_i++)
		{
			/* Load syn globals */
$load_syn_globals$
			/* Thresh source */
$thresh_src$
			/* Save syn globals */
$save_syn_globals$
		}
}
`;
			}
			
			scope block_source = new CSourceConstructor;
			
			cstring thresh_src = thresh.Source.dup;
			
			if(Parallel)
			{
				char[] declare_locals;
				char[] init_locals;
				
				foreach(name, val; &type.AllNonLocals)
				{
					if(thresh_src.c_find(name) != thresh_src.length)
					{
						declare_locals ~= Format("__local $num_type$ {}_local;\n", name);
						init_locals ~= Format("{0}_local = {0};\n", name);
						thresh_src = thresh_src.c_substitute(name, name ~ "_local");
					}
				}
				
				/* Declare locals */
				block_source.Tab(2);
				block_source.AddBlock(declare_locals);
				block_source.Inject(block, "$declare_locals$");
				
				/* Init locals */
				block_source.Tab(3);
				block_source.AddBlock(init_locals);
				block_source.Inject(block, "$init_locals$");
			}
			
			/* Load syn globals */
			block_source.Tab(3);
			auto prefix = syn_type.Prefix;
			foreach(val; &syn_type.Synapse.AllSynGlobals)
			{
				auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
				if(thresh_src.c_find(name) != thresh_src.length)
				{
					block_source ~= Format("$num_type$ {0} = _{0}_buf[_g_syn_i];", name);
				}
			}
			block_source.Inject(block, "$load_syn_globals$");
			
			/* Thresh source */
			block_source.Tab(3);
			block_source.AddBlock(thresh_src);
			block_source.Inject(block, "$thresh_src$");
			
			/* Save syn globals */
			block_source.Tab(3);
			foreach(val; &syn_type.Synapse.AllSynGlobals)
			{
				if(!val.ReadOnly)
				{
					auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
					if(thresh_src.c_find(name) != thresh_src.length)
					{
						block_source ~= Format("_{0}_buf[_g_syn_i] = {0};", name);
					}
				}
			}
			block_source.Inject(block, "$save_syn_globals$");
			
			block["$num_syn$"] = syn_type.NumSynapses;
			block["$thresh_idx$"] = thresh_idx;
			
			source.AddBlock(block);
			
			thresh_idx++;
		}
		source.Inject(kernel_source, "$syn_thresholds$");
		
		/* Integrator save */
		source.Tab(3);
		source.AddBlock(Integrator.GetPostThreshCode(type));
		source.Inject(kernel_source, "$integrator_post_thresh_code$");
		
		/* Integrator save */
		source.Tab;
		source.AddBlock(Integrator.GetSaveCode(type));
		source.Inject(kernel_source, "$integrator_save$");
		
		/* Save values */
		source.Tab;
		source.AddBlock(RWValues.SaveCode);
		source.Inject(kernel_source, "$save_vals$");
		
		/* Random stuff */
		kernel_source["randn()"] = "(sqrt(-2 * log(rand() + 0.000001)) * cospi(2 * rand()))";
		NeedRandArgs = kernel_source[].containsPattern("rand()");
		if(NeedRandArgs)
		{
			if(!RandLen)
				throw new Exception("Found rand()/randn() but neuron type '" ~ type.Name.idup ~ "' does not have random_state_len > 0.");
				
			kernel_source["rand()"] = Format("rand{}(&_rand_state)", RandLen);
		}
		
		/* Load rand state */
		source.Tab;
		if(NeedRandArgs)
			source.AddBlock(Rand.GetLoadCode());
		source.Inject(kernel_source, "$load_rand_state$");
		
		/* Random state arguments */
		source.Tab;
		if(NeedRandArgs)
			source.AddBlock(Rand.GetArgsCode());
		source.Inject(kernel_source, "$random_state_args$");
		
		/* Save rand state */
		source.Tab;
		if(NeedRandArgs)
			source ~= Rand.GetSaveCode();
		source.Inject(kernel_source, "$save_rand_state$");
		
		/* Record save */
		source.Tab;
		if(Parallel)
		{
			source.AddBlock(
`
$barrier$
if(_local_id == 0)
{
	_record_idx[_group_id] = _local_record_idx;
}`);
		}
		source.Inject(kernel_source, "$record_save$");
		
		kernel_source["reset_dt()"] = FixedStep ? "" : "_dt = $min_dt$f";
		kernel_source["$min_dt$"] = MinDt;
		kernel_source["$time_step$"] = Model.TimeStepSize;
		kernel_source["$record_error$"] = RECORD_ERROR;
		kernel_source["$circ_buffer_error$"] = CIRC_BUFFER_ERROR;
		kernel_source["$barrier$"] = Parallel ? "barrier(CLK_LOCAL_MEM_FENCE);" : "";
		
		StepKernelSource = kernel_source[];
	}
	
	private void CreateDeliverKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto kernel_source = new CCode(DeliverKernelTemplate);
		
		kernel_source["$type_name$"] = Name;
		
		/* Event source args */
		source.Tab(2);
		if(NeedSrcSynCode)
		{
			source.AddBlock(
`__local int* fire_table,
__global int* _circ_buffer_start,
__global int* _circ_buffer_end,
__global $num_type$* _circ_buffer,
__global int2* _dest_syn_buffer,
__global int* _fired_syn_idx_buffer,
__global int* _fired_syn_buffer,`);
		}
		source.Inject(kernel_source, "$event_source_args$");
		
		/* Parallel init code */
		source.Tab;
		if(Parallel)
		{
			source.AddBlock(
`__local int fire_table_idx;
if(_local_id == 0)
	fire_table_idx = 0;

barrier(CLK_LOCAL_MEM_FENCE);
`);
		}
		source.Inject(kernel_source, "$parallel_init$");
		
		/* Event source code */
		source.Tab;
		int event_src_idx = 0;
		foreach(thresh; &type.AllEventSources)
		{
			if(NeedSrcSynCode)
			{
				scope src = new CCode(
`{
	int _idx_idx = $num_event_sources$ * i + $event_source_idx$;
	int _buff_start = _circ_buffer_start[_idx_idx];
	if(_buff_start >= 0) /* See if we have any spikes that we can check */
	{
		const int _circ_buffer_size = $circ_buffer_size$;
		int _buff_idx = (i * $num_event_sources$ + $event_source_idx$) * _circ_buffer_size + _buff_start;

		if(_t > _circ_buffer[_buff_idx])
		{
			int buff_end = _circ_buffer_end[_idx_idx];
			
$deliver_code$
	
			_buff_start = (_buff_start + 1) % _circ_buffer_size;
			if(_buff_start == buff_end)
			{
				_buff_start = -1;
			}
			_circ_buffer_start[_idx_idx] = _buff_start;
		}
	}
}`);
				scope src_source = new CSourceConstructor;
				
				
				/* Deliver code */
				src_source.Tab(3);
				if(Parallel)
				{
					src_source ~= "fire_table[atomic_inc(&fire_table_idx)] = $num_event_sources$ * i + $event_source_idx$;";
				}
				else
				{
					src_source.AddBlock(
`int syn_start = num_synapses * _idx_idx;
for(int syn_id = 0; syn_id < num_synapses; syn_id++)
{
	int2 dest = _dest_syn_buffer[syn_id + syn_start];
	if(dest.s0 >= 0)
	{
		/* Get the index into the global syn buffer */
		int dest_syn = atomic_inc(&_fired_syn_idx_buffer[dest.s0]);
		_fired_syn_buffer[dest_syn] = dest.s1;
	}
}`);
				}
				src_source.Inject(src, "$deliver_code$");
				
				src["$event_source_idx$"] = event_src_idx;
				
				source.AddBlock(src);

				event_src_idx++;
			}
		}
		source.Inject(kernel_source, "$event_source_code$");
		
		/* Parallel delivery */
		source.Tab;
		if(NeedSrcSynCode && Parallel)
		{
			scope src = new CCode(
`barrier(CLK_LOCAL_MEM_FENCE);

int _local_size = get_local_size(0);
int num_fired = $num_fired$;

for(int ii = 0; ii < num_fired; ii++)
{
	int syn_start = num_synapses * fire_table[ii];
	for(int syn_id = _local_id; syn_id < num_synapses; syn_id += _local_size)
	{
		int2 dest = _dest_syn_buffer[syn_id + syn_start];
		if(dest.s0 >= 0)
		{
			/* Get the index into the global syn buffer */
			int dest_syn = atomic_inc(&_fired_syn_idx_buffer[dest.s0]);
			_fired_syn_buffer[dest_syn] = dest.s1;
		}
	}
}
`);
			src["$num_fired$"] = "fire_table_idx";
			
			source.AddBlock(src);
		}
		source.Inject(kernel_source, "$parallel_delivery_code$");
		
		kernel_source["$num_event_sources$"] = NumEventSources;
		kernel_source["$circ_buffer_size$"] = CircBufferSize;
		kernel_source["$num_synapses$"] = NumSrcSynapses;
		kernel_source["$time_step$"] = Model.TimeStepSize;
		
		DeliverKernelSource = kernel_source[];
	}
	
	private void CreateInitKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto init_source = type.GetInitSource();
		
		auto kernel_source = new CCode(InitKernelTemplate);
		
		kernel_source["$type_name$"] = Name;
		
		/* RW Value arguments */
		source.Tab(2);
		source.AddBlock(RWValues.ArgsCode);
		source.Inject(kernel_source, "$rw_val_args$");
		
		/* RO Value arguments */
		source.Tab(2);
		source.AddBlock(ROValues.ArgsCode);
		source.Inject(kernel_source, "$ro_val_args$");
		
		/* Constant arguments */
		source.Tab(2);
		foreach(name, state; &type.AllConstants)
		{
			source ~= Format("const $num_type$ {},", name);
		}
		source.Inject(kernel_source, "$constant_args$");
		
		source.Tab(2);
		if(NeedSrcSynCode)
		{
			source ~= "__global int2* _dest_syn_buffer,";
		}
		source.Inject(kernel_source, "$event_source_args$");
		
		/* Immutables */
		source.Tab(2);
		foreach(name, val; &type.AllImmutables)
		{
			source ~= "const $num_type$ " ~ name ~ " = " ~ Format("{:e6}", val.Value) ~ ";";
		}
		source.Inject(kernel_source, "$immutables$");
		
		/* Load vals */
		source.Tab(2);
				/* Load RW vals */
		source.Tab;
		source.AddBlock(RWValues.LoadCode);
		source.Inject(kernel_source, "$load_rw_vals$");
		
		/* Load RO vals */
		source.Tab;
		source.AddBlock(ROValues.LoadCode);
		source.Inject(kernel_source, "$load_ro_vals$");
		source.Inject(kernel_source, "$load_vals$");
		
		/* Perform initialization */
		source.Tab(2);
		source.AddBlock(init_source);
		source.Inject(kernel_source, "$init_vals$");
		
		/* Save values */
		source.Tab(2);
		source.AddBlock(RWValues.SaveCode);
		source.Inject(kernel_source, "$save_vals$");
		
		InitKernelSource = kernel_source[];
	}
	
	@property
	bool FixedStep()
	{
		return cast(CAdaptiveIntegrator!(float_t))Integrator is null;
	}
	
	override
	double opIndex(cstring name)
	{
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			return Constants[*idx_ptr];
		}
		
		if(RWValues.HaveValue(name))
		{
			NeedUnMap = true;
			return RWValues[name];
		}
			
		if(ROValues.HaveValue(name))
		{
			NeedUnMap = true;
			return ROValues[name];
		}
		
		idx_ptr = name in SynGlobalBufferRegistry;
		if(idx_ptr !is null)
		{
			return SynGlobalBuffers[*idx_ptr].DefaultValue;
		}
		
		throw new Exception("Neuron group '" ~ Name.idup ~ "' does not have a '" ~ name.idup ~ "' variable.");
	}
	
	override
	double opIndexAssign(double val, cstring name)
	{	
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			Constants[*idx_ptr] = val;
			if(Model.Initialized)
				SetConstant(*idx_ptr);
			return val;
		}
		
		if(RWValues.HaveValue(name))
		{
			NeedUnMap = true;
			return RWValues[name] = val;
		}
			
		if(ROValues.HaveValue(name))
		{
			NeedUnMap = true;
			return ROValues[name] = val;
		}
		
		idx_ptr = name in SynGlobalBufferRegistry;
		if(idx_ptr !is null)
		{
			SynGlobalBuffers[*idx_ptr].DefaultValue = val;
			return val;
		}
		
		throw new Exception("Neuron group '" ~ Name.idup ~ "' does not have a '" ~ name.idup ~ "' variable.");
	}
	
	/* These two functions can be used to modify values after the model has been created.
	 */
	override
	double opIndex(cstring name, size_t idx)
	{
		assert(Model.Initialized, "Model needs to be Initialized before using this function.");
		assert(idx < Count, "Neuron index needs to be less than Count.");
	
		if(RWValues.HaveValue(name))
		{
			NeedUnMap = true;
			return RWValues[name, idx];
		}
			
		if(ROValues.HaveValue(name))
		{
			NeedUnMap = true;
			return ROValues[name, idx];
		}
		
		throw new Exception("Neuron group '" ~ Name.idup ~ "' does not have a '" ~ name.idup ~ "' variable.");
	}
	
	override
	double opIndexAssign(double val, cstring name, size_t idx)
	{
		assert(Model.Initialized, "Model needs to be Initialized before using this function.");
		assert(idx < Count, "Neuron index needs to be less than Count.");
		
		if(RWValues.HaveValue(name))
		{
			NeedUnMap = true;
			return RWValues[name, idx] = val;
		}
			
		if(ROValues.HaveValue(name))
		{
			NeedUnMap = true;
			return ROValues[name, idx] = val;
		}
		
		throw new Exception("Neuron group '" ~ Name.idup ~ "' does not have a '" ~ name.idup ~ "' variable.");
	}
	
	/* These two functions can be used to modify synglobals after the model has been created.
	 * syn_idx refers to the synapse index in this type (i.e. each successive type has indices starting from 0)
	 */
	override
	double opIndex(cstring name, size_t nrn_idx, size_t syn_idx)
	{
		assert(Model.Initialized, "Model needs to be Initialized before using this function.");
		assert(nrn_idx < Count, "Neuron index needs to be less than Count.");
	
		auto idx_ptr = name in SynGlobalBufferRegistry;
		if(idx_ptr !is null)
		{
			auto buffer = SynGlobalBuffers[*idx_ptr].Buffer;
			auto num_syns_per_nrn = buffer.Length / Count;
			assert(syn_idx < num_syns_per_nrn, "Synapse index needs to be less than the number of synapses for this synapse type.");
			
			auto idx = num_syns_per_nrn * nrn_idx + syn_idx;
			
			return buffer[idx];
		}
		
		throw new Exception("Neuron group '" ~ Name.idup ~ "' does not have a '" ~ name.idup ~ "' variable.");
	}
	
	override
	double opIndexAssign(double val, cstring name, size_t nrn_idx, size_t syn_idx)
	{
		assert(Model.Initialized, "Model needs to be Initialized before using this function.");
		assert(nrn_idx < Count, "Neuron index needs to be less than Count.");
		
		auto idx_ptr = name in SynGlobalBufferRegistry;
		if(idx_ptr !is null)
		{
			auto buffer = SynGlobalBuffers[*idx_ptr].Buffer;
			auto num_syns_per_nrn = buffer.Length / Count;
			assert(syn_idx < num_syns_per_nrn, "Synapse index needs to be less than the number of synapses for this synapse type.");
			
			auto idx = num_syns_per_nrn * nrn_idx + syn_idx;
			
			buffer[idx] = val;
			
			return val;
		}
		
		throw new Exception("Neuron group '" ~ Name.idup ~ "' does not have a '" ~ name.idup ~ "' variable.");
	}
	
	override
	void Dispose()
	{
		if(!Model.Initialized)
			return;
			
		RWValues.Dispose();
		ROValues.Dispose();

		/* TODO: Add safe releases to all of these */			
		foreach(buffer; SynGlobalBuffers)
			buffer.Dispose();
			
		foreach(buffer; SynapseBuffers)
			buffer.Dispose();
			
		foreach(buffer; EventSourceBuffers)
			buffer.Dispose();

		CircBufferStart.Dispose();
		CircBufferEnd.Dispose();
		CircBuffer.Dispose();
		ErrorBuffer.Dispose();
		RecordFlagsBuffer.Dispose();
		RecordBuffer.Dispose();
		RecordIdxBuffer.Dispose();
		RecordIdxBufferStart.Dispose();
		DestSynBuffer.Dispose();
		
		InitKernel.Dispose();
		StepKernel.Dispose();
		DeliverKernel.Dispose();
		
		Integrator.Dispose();
		
		foreach(conn; Connectors)
			conn.Dispose();
		
		if(RandLen)
			Rand.Dispose();

		super.Dispose();
	}
	
	void SetRecordSizeAndStart()
	{
		RecordIdxBuffer.MapWrite();
		scope(exit) RecordIdxBuffer.UnMap();
		RecordIdxBufferStart[] = 0;
		
		if(RecordingWorkgroups.length)
		{		
			auto rec_size = GroupRecordSize;
			
			StepKernel.SetGlobalArg(RecordSizeArgStep, cast(int)rec_size);
			
			foreach(ii, workgroup; RecordingWorkgroups)
				RecordIdxBufferStart[workgroup.Id] = cast(int)(ii * rec_size);
		}
	}
	
	final void UpdateRecorders(size_t timestep, bool last = false)
	{
		assert(Model.Initialized);
		
		if(CommonRecorderIds.length)
		{
			/* Do this here in hopes that it'll be done in parallel with the computation on the GPU*/
			Recorder.ParseData(DataArray);
			DataArray.Length = 0;
			
			if((RecordRate && ((timestep + 1) % RecordRate == 0)) || last)
			{
				foreach(ii, workgroup; RecordingWorkgroups)
				{
					int num_written = RecordIdxBuffer[workgroup.Id];
					assert(num_written <= GroupRecordSize);
					if(num_written)
					{
						auto start = ii * GroupRecordSize;
						
						auto output = RecordBuffer.MapRead(start, start + num_written);
						scope(exit) RecordBuffer.UnMap();

						//stdc.printf("num_written: %d/%d\n", num_written, GroupRecordSize);
						foreach(quad; output)
						{
							int id = cast(int)quad[0];
							//Stdout.formatln("{:5} {:5} {:5} {}", quad[0], quad[1], quad[2], quad[3]);
							DataArray ~= SDataPoint(quad[0], quad[1], cast(int)quad[2], cast(size_t)quad[3]);
						}
					}
				}
			}
			/* The one for the normal RecordRate triggers is done inside the deliver kernel */
			if(last)
				RecordIdxBuffer[] = 0;
		}
	}
	
	private
	@property
	size_t GroupRecordSize()
	{
		return RecordLength / RecordingWorkgroups.length;
	}
	
	override
	void Record(size_t neuron_id, int flags)
	{
		assert(Model.Initialized);
		assert(neuron_id < Count);
		
		/* Try finding a workgroup that contains this neuron */
		auto num_rec_workgroups = RecordingWorkgroups.length;
		auto workgroup = SRecordingWorkgroup(neuron_id / WorkgroupSize);
		auto workgroup_idx = RecordingWorkgroups.find(workgroup);
		
		if(workgroup_idx != RecordingWorkgroups.length)
			workgroup = RecordingWorkgroups[workgroup_idx];
		else
			RecordingWorkgroups.length = RecordingWorkgroups.length + 1;
		
		if(flags == 0)
		{
			/* Remove it */
			CommonRecorderIds.length = CommonRecorderIds.remove(neuron_id);
			
			workgroup.NeuronIds.length = workgroup.NeuronIds.remove(neuron_id);
			
			/* Remove the workgroup if it is empty */
			if(workgroup.NeuronIds.length == 0)
			{
				RecordingWorkgroups[workgroup_idx] = RecordingWorkgroups[$ - 1];
				RecordingWorkgroups.length = RecordingWorkgroups.length - 1;
			}
			else
			{
				RecordingWorkgroups[workgroup_idx] = workgroup;
			}
		}
		else
		{
			CommonRecorderIds ~= neuron_id;
			workgroup.NeuronIds ~= neuron_id;
			RecordingWorkgroups[workgroup_idx] = workgroup;
		}
		
		RecordFlagsBuffer[neuron_id] = flags;
		
		/* If the number of workgroups changed, we need to tell the kernel this */
		if(num_rec_workgroups != RecordingWorkgroups.length)
			SetRecordSizeAndStart();
	}
	
	override
	int GetRecordFlags(size_t neuron_id)
	{
		assert(Model.Initialized);
		assert(neuron_id < Count);
		
		return RecordFlagsBuffer[neuron_id];
	}
	
	override
	void ResetRecordedData()
	{
		DataArray.Length = 0;
	}
	
	void CheckErrors()
	{
		assert(Model.Initialized);
		
		auto errors = ErrorBuffer.MapRead();
		scope(exit) ErrorBuffer.UnMap();
		
		bool found_errors = false;
		if(errors[0])
		{
			Stdout.formatln("Error: {}", errors[0]);
			found_errors = true;
		}
		foreach(ii, error; errors[1..$])
		{
			found_errors |= error != 0;
			if(error == RECORD_ERROR)
			{
				Stdout.formatln("Neuron {}: Record buffer too small", ii);
				
			}
			else if(error >= CIRC_BUFFER_ERROR)
			{
				Stdout.formatln("Neuron {}: Event source {} exceeded the circular buffer capacity (spike rate too high)", ii, error - CIRC_BUFFER_ERROR);
			}
			else if(error != 0)
			{
				Stdout.formatln("Neuron {}: Unknown error code {}", ii, error);
			}
		}
		
		if(found_errors)
			throw new Exception("Found errors during model execution.");
	}
	
	private size_t GetSrcSynId(size_t src_nrn_id, size_t event_source, size_t src_slot)
	{
		assert(src_nrn_id < Count);
		assert(event_source < NumEventSources);
		assert(src_slot < NumSrcSynapses);
		
		return (src_nrn_id * NumEventSources + event_source) * NumSrcSynapses + src_slot;
	}
	
	void SetConnection(size_t src_nrn_id, size_t event_source, size_t src_slot, size_t dest_neuron_id, size_t dest_slot)
	{
		assert(Model.Initialized);
		
		auto src_syn_id = GetSrcSynId(src_nrn_id, event_source, src_slot);
		
		NeedUnMap = true;
		
		DestSynBuffer()[src_syn_id] = cl_int2(cast(int)dest_neuron_id, cast(int)dest_slot);
	}
	
	override
	int GetConnectionId(size_t src_nrn_id, size_t event_source, size_t src_slot)
	{
		assert(Model.Initialized);
		
		auto src_syn_id = GetSrcSynId(src_nrn_id, event_source, src_slot);
		
		NeedUnMap = true;
		
		return DestSynBuffer()[src_syn_id][0];
	}
	
	override
	int GetConnectionSlot(size_t src_nrn_id, size_t event_source, size_t src_slot)
	{
		assert(Model.Initialized);
		
		auto src_syn_id = GetSrcSynId(src_nrn_id, event_source, src_slot);
		
		NeedUnMap = true;
		
		return DestSynBuffer()[src_syn_id][1];
	}
	
	/*
	 * Reserves a slot in an event source, returns -1 if its full
	 */
	int GetSrcSlot(size_t src_nrn_id, size_t event_source)
	{
		assert(src_nrn_id < Count);
		assert(event_source < NumEventSources);
		
		auto idx = EventSourceBuffers[event_source].FreeIdx[src_nrn_id];
		
		if(idx >= NumSrcSynapses)
			return -1;
		
		idx++;
		
		EventSourceBuffers()[event_source].FreeIdx[src_nrn_id] = idx;
		
		return idx - 1;
	}
	
	/*
	 * Reserves a slot in a destination mechanism, returns -1 if its full
	 */
	int GetDestSlot(size_t dest_nrn_id, size_t dest_syn_type)
	{
		assert(dest_nrn_id < Count);
		assert(dest_syn_type < SynapseBuffers.length);
		
		auto idx = SynapseBuffers[dest_syn_type].FreeIdx[dest_nrn_id];
		
		if(idx >= SynapseBuffers[dest_syn_type].Count)
			return -1;
		
		idx++;
		
		SynapseBuffers()[dest_syn_type].FreeIdx[dest_nrn_id] = idx;
		
		return idx - 1;
	}
	
	size_t GetSynapseTypeOffset(size_t type)
	{
		assert(type < SynapseBuffers.length, "Invalid synapse type.");
		return SynapseBuffers[type].SlotOffset;
	}
	
	void Connect(cstring connector_name, size_t multiplier, size_t[2] src_nrn_range, size_t src_event_source, CNeuronGroup!(float_t) dest, size_t[2] dest_nrn_range, size_t dest_syn_type, double[char[]] args)
	{
		auto conn_ptr = connector_name in Connectors;
		if(conn_ptr is null)
			throw new Exception("Neuron group '" ~ Name.idup ~ "' does not have a connector named '" ~ connector_name.idup ~ "'.");
		
		auto conn = *conn_ptr;
		
		if(args !is null)
		{
			foreach(arg_name, arg_val; args)
			{
				conn[arg_name] = arg_val;
			}
		}
		
		if(NeedUnMap)
			UnMapBuffers();
		
		conn.Connect(multiplier, src_nrn_range, src_event_source, dest, dest_nrn_range, dest_syn_type);
		
		CheckErrors();
	}
	
	double MinDtVal = 0.1;
	
	override
	@property
	double MinDt()
	{
		return MinDtVal;
	}
	
	override
	@property
	void MinDt(double min_dt)
	{
		if(Model.Initialized && FixedStep)
		{
			Integrator.SetDt(min_dt);
		}
		MinDtVal = min_dt;
	}
	
	override
	@property
	int IntegratorArgOffset()
	{
		int rand_offset = 0;
		if(NeedRandArgs)
		{
			rand_offset = Rand.NumArgs;
		}
		return cast(int)(ValArgsOffset + Constants.length + ArgOffsetStep + rand_offset);
	}
	
	override
	void Seed(int seed)
	{
		if(RandLen)
			Rand.Seed(seed);
	}
	
	override
	void Seed(size_t idx, int seed)
	{
		if(RandLen)
			Rand.Seed(idx, seed);
	}
	
	@property
	size_t ValArgsOffset()
	{
		return RWValues.length + ROValues.length;
	}
	
	@property
	cl_program Program()
	{
		return Model.Program;
	}
	
	override
	@property
	CCLCore Core()
	{
		return Model.Core;
	}
	
	override
	@property
	size_t Count()
	{
		return CountVal;
	}
	
	override
	@property
	bool Initialized()
	{
		return Model.Initialized;
	}
	
	override
	@property
	double TimeStepSize()
	{
		return Model.TimeStepSize;
	}
	
	mixin(Prop!("cstring", "Name", "override", "private"));
	mixin(Prop!("size_t", "NumEventSources", "override", "private"));
	mixin(Prop!("size_t", "NumSynThresholds", "override", "private"));
	mixin(Prop!("size_t", "NumSrcSynapses", "override", "private"));
	mixin(Prop!("CEventSourceBuffer[]", "EventSourceBuffers", "override", "private"));
	mixin(Prop!("CSynapseBuffer[]", "SynapseBuffers", "override", "private"));
	mixin(Prop!("CCLBuffer!(cl_int2)", "DestSynBuffer", "override", "private"));
	mixin(Prop!("size_t", "NrnOffset", "override", "private"));
	mixin(Prop!("CCLBuffer!(int)", "ErrorBuffer", "override", "private"));
	mixin(Prop!("CCLRand", "Rand", "override", "private"));
	mixin(Prop!("size_t", "RandLen", "override", "private"));
	mixin(Prop!("CRecorder", "Recorder", "override", "private"));

	SArray!(SDataPoint) DataArray;
	CRecorder RecorderVal;
	
	/* Holds the id's where we are recording events, may have duplicates (we only care if it's empty or not though) */
	size_t[] CommonRecorderIds;
	/* Like the above, but groups them by recording group */
	struct SRecordingWorkgroup
	{
		size_t[] NeuronIds;
		size_t Id;
		
		bool opEquals(SRecordingWorkgroup other)
		{
			return other.Id == Id;
		}
		
		static SRecordingWorkgroup opCall(size_t id)
		{
			SRecordingWorkgroup ret;
			ret.Id = id;
			return ret;
		}
	}
	SRecordingWorkgroup[] RecordingWorkgroups;
	
	
	double[] Constants;
	size_t[char[]] ConstantRegistry;
	
	CMultiBuffer!(float_t) RWValues;
	CMultiBuffer!(float_t) ROValues;
	
	CSynGlobalBuffer!(float_t)[] SynGlobalBuffers;
	size_t[char[]] SynGlobalBufferRegistry;
	
	cstring NameVal;
	size_t CountVal = 0;
	ICLModel Model;
	
	cstring StepKernelSource;
	cstring InitKernelSource;
	cstring DeliverKernelSource;
	
	CCLKernel InitKernel;
	CCLKernel StepKernel;
	CCLKernel DeliverKernel;
	
	CCLBuffer!(int) CircBufferStart;
	CCLBuffer!(int) CircBufferEnd;
	CCLBuffer!(float_t) CircBuffer;
	CCLBuffer!(int) ErrorBufferVal;
	CCLBuffer!(int) RecordFlagsBuffer;
	CCLBuffer!(float_t4) RecordBuffer;
	CCLBuffer!(cl_int) RecordIdxBuffer;
	CCLBuffer!(cl_int) RecordIdxBufferStart;
	/* TODO: This is stupid. Make it so each event source has its own buffer, much much simpler that way. */
	CCLBuffer!(cl_int2) DestSynBufferVal;
	
	/* These two must be integers */
	int RecordLength;
	int RecordRate;
	size_t CircBufferSize = 20;
	size_t NumEventSourcesVal = 0;
	size_t NumThresholds = 0;
	size_t NumSynThresholdsVal = 0;
	
	size_t NumSrcSynapsesVal; /* Number of pre-synaptic slots per event source */
	size_t NumDestSynapses; /* Number of post-synaptic slots per neuron */
	
	/* The place we reset the fired syn idx to*/
	size_t SynOffset;
	/* Offset for indexing into the model global indices */
	size_t NrnOffsetVal;
	
	CSynapseBuffer[] SynapseBuffersVal;
	CEventSourceBuffer[] EventSourceBuffersVal;
	
	size_t RandLenVal = 0;
	CCLRand RandVal;
	bool NeedRandArgs = false;
	
	/* If true, need to unmap the cached buffers */
	bool NeedUnMap = false;
	
	CIntegrator!(float_t) Integrator;
	
	CCLConnector!(float_t)[char[]] Connectors;
	
	bool Parallel = true;
	
	size_t WorkgroupSize = 1;
}

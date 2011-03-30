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

module celeme.clneurongroup;

import celeme.iclneurongroup;
import celeme.frontend;
import celeme.clcore;
import celeme.clconnector;
import celeme.iclmodel;
import celeme.recorder;
import celeme.alignedarray;
import celeme.sourceconstructor;
import celeme.util;
import celeme.integrator;
import celeme.adaptiveheun;
import celeme.heun;
import celeme.clrand;
import celeme.clmiscbuffers;

import opencl.cl;

import tango.io.Stdout;
import tango.text.Util;
import tango.util.Convert;
import tango.core.Array;

const ArgOffsetStep = 6;
char[] StepKernelTemplate = `
#undef record
#define record(flags, data, tag) \
if(_record_flags & (flags)) \
{ \
	int idx = atomic_inc(&_record_idx[0]); \
	if(idx >= _record_buffer_size) \
	{ \
		_error_buffer[i + 1] = $record_error$; \
		_record_idx[0] = _record_buffer_size - 1; \
	} \
	$num_type$4 record; \
	record.s0 = t; \
	record.s1 = (data); \
	record.s2 = tag; \
	record.s3 = i; \
	_record_buffer[idx] = record; \
} \


__kernel void $type_name$_step
	(
		const $num_type$ _t,
		__global int* _error_buffer,
		__global int* _record_flags_buffer,
		__global int* _record_idx,
		__global $num_type$4* _record_buffer,
		const int _record_buffer_size,
$val_args$
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

$syn_threshold_status$

$primary_exit_condition_init$

	$num_type$ _cur_time = 0;
	const $num_type$ timestep = $time_step$;
	int _record_flags = _record_flags_buffer[i];
	
	$num_type$ _dt;
	$num_type$ t = _t;

$integrator_load$

$load_vals$

$load_rand_state$

$synapse_code$
		
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
}
`;

const ArgOffsetInit = 0;
char[] InitKernelTemplate = `
__kernel void $type_name$_init
	(
$val_args$
$constant_args$
$event_source_args$
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
`;

const ArgOffsetDeliver = 4;
const char[] DeliverKernelTemplate = "
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
	
	if(i == 0 && _record_rate && ((int)(_t / $time_step$) % _record_rate == 0))
	{
		_record_idx[0] = 0;
	}
	
#if PARALLEL_DELIVERY
	int _local_id = get_local_id(0);

#if USE_ATOMIC_DELIVERY
	__local int fire_table_idx;
	if(_local_id == 0)
		fire_table_idx = 0;
#else
	for(int ii = 0; ii < $num_event_sources$; ii++)
		fire_table[_local_id * $num_event_sources$ + ii] = -1;

	__local bool need_to_deliver;
	need_to_deliver = false;
#endif

	barrier(CLK_LOCAL_MEM_FENCE);
#endif
	
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

class CNeuronGroup(float_t) : ICLNeuronGroup
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
	
	this(ICLModel model, CNeuronType type, int count, char[] name, int sink_offset, int nrn_offset, bool adaptive_dt = true)
	{
		Model = model;
		CountVal = count;
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
				break;
			case 4:
				assert(0, "Unsupported rand length");
				//Rand = new CCLRandImpl!(4)(Core, Count);
				break;
			default:
		}
		
		foreach(conn; type.Connectors)
		{
			Connectors[conn.Name] = new CCLConnector!(float_t)(this, conn);
		}
		
		/* Copy the non-locals and constants from the type */
		foreach(name, state; &type.AllNonLocals)
		{
			ValueBufferRegistry[name] = ValueBuffers.length;
			ValueBuffers ~= new CValueBuffer!(float_t)(state, Core, Count);
		}
		
		/* Syn globals are special, so they get treated separately */
		foreach(syn_type; type.SynapseTypes)
		{
			foreach(val; &syn_type.Synapse.AllSynGlobals)
			{
				auto name = syn_type.Prefix == "" ? val.Name : syn_type.Prefix ~ "_" ~ val.Name;
				
				SynGlobalBufferRegistry[name] = SynGlobalBuffers.length;
				SynGlobalBuffers ~= new CSynGlobalBuffer!(float_t)(val, Core, Count * syn_type.NumSynapses);			
			}
		}
		
		int syn_type_offset = 0;
		foreach(syn_type; type.SynapseTypes)
		{
			auto syn_buff = new CSynapseBuffer(Core, syn_type_offset, syn_type.NumSynapses, Count);
			SynapseBuffers = SynapseBuffers ~ syn_buff;
			
			syn_type_offset += syn_type.NumSynapses;
		}
		
		foreach(ii; range(NumEventSources))
		{
			EventSourceBuffers = EventSourceBuffers ~ new CEventSourceBuffer(Core, Count);
		}
		
		if(NeedSrcSynCode)
		{
			CircBufferStart = Core.CreateBuffer!(int)(NumEventSources * Count);
			CircBufferEnd = Core.CreateBuffer!(int)(NumEventSources * Count);
			CircBuffer = Core.CreateBuffer!(float_t)(CircBufferSize * NumEventSources * Count);
		}
		
		ErrorBuffer = Core.CreateBuffer!(int)(Count + 1);
		RecordFlagsBuffer = Core.CreateBuffer!(int)(Count);
		RecordBuffer = Core.CreateBuffer!(float_t4)(RecordLength);
		RecordIdxBuffer = Core.CreateBuffer!(int)(1);
		
		if(NeedSrcSynCode)
		{
			DestSynBuffer = Core.CreateBuffer!(cl_int2)(Count * NumEventSources * NumSrcSynapses);
		}

		foreach(name, state; &type.AllConstants)
		{
			ConstantRegistry[name] = Constants.length;
			
			Constants ~= state.Value;
		}
		
		if(adaptive_dt)
			Integrator = new CAdaptiveHeun!(float_t)(this, type);
		else
			Integrator = new CHeun!(float_t)(this, type);
		
		CommonRecorder = new CRecorder(Name, true);
		
		/* Create kernel sources */
		CreateStepKernel(type);
		CreateInitKernel(type);
		CreateDeliverKernel(type);
	}
	
	/* Call this after the program has been created, as we need the memset kernel
	 * and to create the local kernels*/
	void Initialize()
	{
		int arg_id;
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
			SetGlobalArg(arg_id++, RecordBuffer);
			SetGlobalArg(arg_id++, RecordLength);
			foreach(buffer; ValueBuffers)
			{
				SetGlobalArg(arg_id++, buffer.Buffer);
			}
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
			foreach(_; range(NumSynThresholds))
			{
				SetLocalArg(arg_id++, int.sizeof * Model.StepWorkgroupSize);
			}
			SetGlobalArg(arg_id++, Count);
		}
		
		/* Init kernel */
		InitKernel = Core.CreateKernel(Program, Name ~ "_init");
		with(InitKernel)
		{
			/* Nothing to skip, so set it at 0 */
			arg_id = 0;
			foreach(buffer; ValueBuffers)
			{
				SetGlobalArg(arg_id++, buffer.Buffer);
			}
			arg_id += Constants.length;
			if(NeedSrcSynCode)
			{
				SetGlobalArg(arg_id++, DestSynBuffer);
			}
			SetGlobalArg(arg_id++, Count);
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
				SetLocalArg(arg_id++, int.sizeof * Model.DeliverWorkgroupSize * NumEventSources);
				/* Set the event source args */
				SetGlobalArg(arg_id++, CircBufferStart);
				SetGlobalArg(arg_id++, CircBufferEnd);
				SetGlobalArg(arg_id++, CircBuffer);
				SetGlobalArg(arg_id++, DestSynBuffer);
				SetGlobalArg(arg_id++, Model.FiredSynIdxBuffer);
				SetGlobalArg(arg_id++, Model.FiredSynBuffer);
			}
			SetGlobalArg(arg_id++, Count);
		}
		
		Core.Finish();
		
		RecordFlagsBuffer[] = 0;
		DestSynBuffer()[] = cl_int2(-1, -1);
		
		foreach(conn; Connectors)
			conn.Initialize;
		
		ResetBuffers();
	}
	
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
		RecordIdxBuffer[0] = 0;
		
		if(NeedSrcSynCode)
		{
			CircBufferStart[] = -1;
			CircBufferEnd[] = 0;
		}
		
		/* Write the default values to the global buffers*/
		foreach(buffer; ValueBuffers)
		{
			buffer.Buffer[] = buffer.DefaultValue;
		}
		
		foreach(buffer; SynGlobalBuffers)
		{
			buffer.Buffer[] = buffer.DefaultValue;
		}
		Core.Finish();
			
		CommonRecorder.Length = 0;
	}
	
	void SetConstant(int idx)
	{
		assert(Model.Initialized);
		
		float_t val = Constants[idx];
		InitKernel.SetGlobalArg(idx + ValueBuffers.length + ArgOffsetInit, val);
		StepKernel.SetGlobalArg(idx + ValueBuffers.length + ArgOffsetStep, val);
	}
	
	void SetTolerance(char[] state, double tolerance)
	{
		auto adaptive = cast(CAdaptiveIntegrator!(float_t))Integrator;
		if(adaptive !is null)
		{
			adaptive.SetTolerance(StepKernel, state, tolerance);
		}
		else
		{
			throw new Exception("Can only set tolerances for adaptive integrators.");
		}
	}
	
	void CallInitKernel(size_t workgroup_size, cl_event* ret_event = null)
	{
		assert(Model.Initialized);
		
		size_t total_num = (Count / workgroup_size) * workgroup_size;
		if(total_num < Count)
			total_num += workgroup_size;
		
		InitKernel.Launch([total_num], [workgroup_size], ret_event);
	}
	
	void CallStepKernel(double sim_time, cl_event* ret_event = null)
	{
		assert(Model.Initialized);

		with(StepKernel)
		{
			SetGlobalArg(0, cast(float_t)sim_time);
			Launch([Count], [Model.StepWorkgroupSize], ret_event);
		}
	}
	
	void CallDeliverKernel(double sim_time, cl_event* ret_event = null)
	{
		assert(Model.Initialized);
		
		size_t total_num = (Count / Model.DeliverWorkgroupSize) * Model.DeliverWorkgroupSize;
		if(total_num < Count)
			total_num += Model.DeliverWorkgroupSize;
		
		with(DeliverKernel)
		{
			SetGlobalArg(0, cast(float_t)sim_time);
			
			Launch([total_num], [Model.DeliverWorkgroupSize], ret_event);
		}
	}
	
	private void CreateStepKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto kernel_source = StepKernelTemplate.dup;
		
		kernel_source = kernel_source.substitute("$type_name$", Name);
		
		/* Value arguments */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "__global $num_type$* _" ~ name ~ "_buf,";
		}
		source.Inject(kernel_source, "$val_args$");
		
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
		
		/* Integrator load */
		source.Tab;
		source.AddBlock(Integrator.GetLoadCode(type));
		source.Inject(kernel_source, "$integrator_load$");
		
		/* Load vals */
		source.Tab;
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "$num_type$ " ~ name ~ " = _" ~ name ~ "_buf[i];";
		}
		source.Inject(kernel_source, "$load_vals$");
		
		/* Synapse code */
		source.Tab;
		if(NumDestSynapses)
		{
			source.AddBlock(
`
const int _syn_offset = $syn_offset$ + i * ` ~ to!(char[])(NumDestSynapses) ~ `;
int _syn_table_end = _fired_syn_idx_buffer[i + $nrn_offset$];
if(_syn_table_end != _syn_offset)
{
	for(int _syn_table_idx = _syn_offset; _syn_table_idx < _syn_table_end; _syn_table_idx++)
	{
		int syn_i = _fired_syn_buffer[_syn_table_idx];
`);
			source.Tab(2);
			int syn_type_offset = 0;
			int syn_type_start = 0;
			foreach(ii, syn_type; type.SynapseTypes)
			{
				syn_type_offset += syn_type.NumSynapses;
				char[] cond;
				if(ii != 0)
					cond ~= "else ";
				cond ~= "if(syn_i < " ~ to!(char[])(syn_type_offset) ~ ")";
				source ~= cond;
				source ~= "{";
				source.Tab();
				source ~= "int _g_syn_i = syn_i - " ~ to!(char[])(syn_type_start) ~ " + i * " ~ to!(char[])(syn_type.NumSynapses) ~ ";";
				auto prefix = syn_type.Prefix;
				
				auto syn_code = syn_type.Synapse.SynCode;
				if(syn_type.Prefix != "")
				{
					foreach(val; &syn_type.Synapse.AllValues)
					{
						syn_code = syn_code.c_substitute(val.Name, prefix ~ "_" ~ val.Name);
					}
					
					foreach(val; &syn_type.Synapse.AllSynGlobals)
					{
						syn_code = syn_code.c_substitute(val.Name, prefix ~ "_" ~ val.Name);
					}
				}
				
				foreach(val; &syn_type.Synapse.AllSynGlobals)
				{
					auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
					if(syn_code.c_find(name) != syn_code.length)
						source ~= "$num_type$ " ~ name ~ " = _" ~ name ~ "_buf[_g_syn_i];";
				}
				
				source.AddBlock(syn_code);
				
				foreach(val; &syn_type.Synapse.AllSynGlobals)
				{
					if(!val.ReadOnly)
					{
						auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
						if(syn_code.c_find(name) != syn_code.length)
							source ~= "_" ~ name ~ "_buf[_g_syn_i] = " ~ name ~ ";";
					}
				}
				
				source.DeTab;
				source ~= "}";
				
				syn_type_start = syn_type_offset;
			}
			source.DeTab;
			source ~= "}";
			if(!FixedStep)
				source ~= "_dt = $min_dt$f;";
			source ~= "_fired_syn_idx_buffer[i + $nrn_offset$] = _syn_offset;";
			source.DeTab;
			source ~= "}";
			
			source.Source = source.Source.substitute("$nrn_offset$", to!(char[])(NrnOffset));
			source.Source = source.Source.substitute("$syn_offset$", to!(char[])(SynOffset));
		}
		source.Inject(kernel_source, "$synapse_code$");
		
		/* Syn threshold statuses */
		source.Tab;
		int thresh_idx = 0;
		foreach(thresh; &type.AllSynThresholds)
		{
			source ~= "__local int _syn_thresh_" ~ to!(char[])(thresh_idx) ~ "_num;";
			thresh_idx++;
		}
		NumSynThresholds = thresh_idx;
		if(NumSynThresholds)
		{
			source ~= "int _local_id = get_local_id(0);";
			source ~= "int _local_size = get_local_size(0);";
		}
		source.Inject(kernel_source, "$syn_threshold_status$");
		
		/* Primary exit condition */
		source.Tab;
		if(NumSynThresholds)
		{
			source ~= "__local int _num_complete;";
			source ~= "if(_local_id == 0)";
			source.Tab;
			source ~= "_num_complete = 0;";
			source.DeTab;
			source ~= "barrier(CLK_LOCAL_MEM_FENCE);";
		}
		source.Inject(kernel_source, "$primary_exit_condition_init$");
		
		if(NumSynThresholds)
			kernel_source = kernel_source.substitute("$primary_exit_condition$", "_num_complete < _local_size");
		else
			kernel_source = kernel_source.substitute("$primary_exit_condition$", "_cur_time < timestep");
		
		source.Tab(3);
		if(NumSynThresholds)
		{
			source ~= "if(_cur_time >= timestep)";
			source.Tab;
			source ~= "atomic_inc(&_num_complete);";
			source.DeTab;
		}
		source.Inject(kernel_source, "$primary_exit_condition_check$");
		
		source.Tab;
		thresh_idx = 0;
		if(NumSynThresholds)
		{
			foreach(thresh; &type.AllSynThresholds)
			{
				source ~= "__local int* _syn_thresh_" ~ to!(char[])(thresh_idx) ~ "_arr,";
				thresh_idx++;
			}
		}
		source.Inject(kernel_source, "$syn_thresh_array_arg$");
		
		/* Threshold statuses */
		source.Tab(2);
		thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			source ~= "bool thresh_" ~ to!(char[])(thresh_idx) ~ "_state = false;";
			
			thresh_idx++;
		}
		NumThresholds = thresh_idx;
		source.Inject(kernel_source, "$threshold_status$");
		
		/* Syn threshold statuses init */
		source.Tab(2);
		thresh_idx = 0;
		if(NumSynThresholds)
		{
			source ~= "if(_local_id == 0)";
			source ~= "{";
			source.Tab;
			foreach(thresh; &type.AllSynThresholds)
			{
				source ~= "_syn_thresh_" ~ to!(char[])(thresh_idx) ~ "_num = 0;";
				thresh_idx++;
			}
			source.DeTab;
			source ~= "}";
			source ~= "barrier(CLK_LOCAL_MEM_FENCE);";
		}
		source.Inject(kernel_source, "$syn_threshold_status_init$");
		
		/* Threshold pre-check */
		source.Tab(3);
		thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			source ~= "bool thresh_" ~ to!(char[])(thresh_idx) ~ "_pre_state = " ~ thresh.State ~ " " ~ thresh.Condition ~ ";";
			
			thresh_idx++;
		}
		source.Inject(kernel_source, "$threshold_pre_check$");
		
		/* Syn threshold pre-check */
		source.Tab(3);
		thresh_idx = 0;
		foreach(thresh; &type.AllSynThresholds)
		{
			source ~= "bool syn_thresh_" ~ to!(char[])(thresh_idx) ~ "_pre_state = " ~ thresh.State ~ " " ~ thresh.Condition ~ ";";
			
			thresh_idx++;
		}
		source.Inject(kernel_source, "$syn_threshold_pre_check$");
		
		/* Declare locals */
		source.Tab(3);
		foreach(name, state; &type.AllLocals)
		{
			source ~= "$num_type$ " ~ name ~ ";";
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
			source ~= "thresh_$thresh_idx$_state = !thresh_$thresh_idx$_pre_state && (" ~ thresh.State ~ " " ~ thresh.Condition ~ ");";
			source ~= "_any_thresh |= thresh_$thresh_idx$_state;";
			source.Source = source.Source.substitute("$thresh_idx$", to!(char[])(thresh_idx));
			
			thresh_idx++;
		}
		source.Inject(kernel_source, "$detect_thresholds$");
		
		/* Detect syn thresholds */
		source.Tab(3);
		thresh_idx = 0;
		foreach(thresh; &type.AllSynThresholds)
		{
			source ~= "if(!syn_thresh_$thresh_idx$_pre_state && (" ~ thresh.State ~ " " ~ thresh.Condition ~ "))";
			source ~= "{";
			source.Tab;
			source ~= "_any_thresh = true;";
			source ~= "_syn_thresh_$thresh_idx$_arr[atomic_inc(&_syn_thresh_$thresh_idx$_num)] = i;";
			source.DeTab;
			source ~= "}";
			source.Source = source.Source.substitute("$thresh_idx$", to!(char[])(thresh_idx));
			
			thresh_idx++;
		}
		source.Inject(kernel_source, "$detect_syn_thresholds$");
		
		/* Thresholds */
		source.Tab(2);
		event_src_idx = 0;
		thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			source ~= "if(thresh_$thresh_idx$_state)";
			source ~= "{";
			source.Tab;
			
			if(thresh.IsEventSource)
				source ~= "$num_type$ delay = 1.0f;";
			source.AddBlock(thresh.Source);
			if(thresh.ResetTime && !FixedStep)
				source ~= "_dt = $min_dt$f;";

			source.Source = source.Source.substitute("$thresh_idx$", to!(char[])(thresh_idx));
			
			if(NeedSrcSynCode && thresh.IsEventSource)
			{
				char[] src = 
`int _idx_idx = $num_event_sources$ * i + $event_source_idx$;
int _buff_start = _circ_buffer_start[_idx_idx];

if(_buff_start != _circ_buffer_end[_idx_idx])
{
	const int _circ_buffer_size = $circ_buffer_size$;
	
	int _end_idx;
	if(_buff_start < 0) //It is empty
	{
		_circ_buffer_start[_idx_idx] = 0;
		_circ_buffer_end[_idx_idx] = 1;
		_end_idx = 1;
	}
	else
	{
		_end_idx = _circ_buffer_end[_idx_idx] = (_circ_buffer_end[_idx_idx] + 1) % _circ_buffer_size;
	}
	int _buff_idx = (i * $num_event_sources$ + $event_source_idx$) * _circ_buffer_size + _end_idx - 1;
	_circ_buffer[_buff_idx] = t + delay;
}
else //It is full, error
{
	_error_buffer[i + 1] = $circ_buffer_error$ + $event_source_idx$;
}
`.dup;
				src = src.substitute("$circ_buffer_size$", to!(char[])(CircBufferSize));
				src = src.substitute("$num_event_sources$", to!(char[])(NumEventSources));
				src = src.substitute("$event_source_idx$", to!(char[])(event_src_idx));
				
				source.AddBlock(src);
				
				event_src_idx++;
/* TODO: Better error reporting */
			}
			
			source.DeTab;
			source ~= "}";
			thresh_idx++;
		}
		source.Inject(kernel_source, "$thresholds$");
		
		/* Syn thresholds */
		source.Tab(2);
		thresh_idx = 0;
		foreach(syn_type, thresh; &type.AllSynThresholdsEx)
		{
			source ~= "barrier(CLK_LOCAL_MEM_FENCE);";
			source ~= "if(_syn_thresh_$thresh_idx$_num > 0)";
			source ~= "{";
			source.Tab;
			
			source ~= "for(int _ii = 0; _ii < _syn_thresh_$thresh_idx$_num; _ii++)";
			source ~= "{";
			source.Tab;
			source ~= "int nrn_id = _syn_thresh_$thresh_idx$_arr[_ii];";
			char[] declare_locals;
			char[] init_locals;
			char[] thresh_src = thresh.Source.dup;
			
			foreach(name, val; &type.AllNonLocals)
			{
				if(thresh_src.c_find(name) != thresh_src.length)
				{
					declare_locals ~= "__local $num_type$ " ~ name ~ "_local;\n";
					init_locals ~= name ~ "_local = " ~ name ~ ";\n";
					thresh_src = thresh_src.c_substitute(name, name ~ "_local");
				}
			}
			source.AddBlock(declare_locals);
			source ~= "if(i == nrn_id)";
			source ~= "{";
			source.Tab;
			source.AddBlock(init_locals);
			source.DeTab;
			source ~= "}";
			source ~= "barrier(CLK_LOCAL_MEM_FENCE);";
			source ~= "int _syn_offset = nrn_id * $num_syn$;";
			source ~= "for(int _g_syn_i = _syn_offset + _local_id; _g_syn_i < $num_syn$ + _syn_offset; _g_syn_i += _local_size)";
			source ~= "{";
			source.Tab;
			
			auto prefix = syn_type.Prefix;
			/* Load syn globals */
			foreach(val; &syn_type.Synapse.AllSynGlobals)
			{
				auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
				if(thresh_src.c_find(name) != thresh_src.length)
					source ~= "$num_type$ " ~ name ~ " = _" ~ name ~ "_buf[_g_syn_i];";
			}
			
			source.AddBlock(thresh_src);
			
			/* Save syn globals */
			foreach(val; &syn_type.Synapse.AllSynGlobals)
			{
				if(!val.ReadOnly)
				{
					auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
					if(thresh_src.c_find(name) != thresh_src.length)
						source ~= "_" ~ name ~ "_buf[_g_syn_i] = " ~ name ~ ";";
				}
			}
			
			source.DeTab;
			source ~= "}";
			
			source.DeTab;
			source ~= "}";
			source.DeTab;
			source ~= "}";
			
			source.Source = source.Source.substitute("$num_syn$", to!(char[])(syn_type.NumSynapses));
			source.Source = source.Source.substitute("$thresh_idx$", to!(char[])(thresh_idx));
			
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
		foreach(name, state; &type.AllNonLocals)
		{
			if(!state.ReadOnly)
				source ~= "_" ~ name ~ "_buf[i] = " ~ name ~ ";";
		}
		source.Inject(kernel_source, "$save_vals$");
		
		/* Random stuff */
		NeedRandArgs = kernel_source.containsPattern("rand()");
		if(NeedRandArgs)
		{
			if(!RandLen)
				throw new Exception("Found rand() but neuron type '" ~ type.Name ~ "' does not have random_state_len > 0.");
				
			kernel_source = kernel_source.substitute("rand()", "rand" ~ to!(char[])(RandLen) ~ "(&_rand_state)");
		}
		
		/* Load rand state */
		source.Tab;
		if(NeedRandArgs)
			source ~= Rand.GetLoadCode();
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
		
		kernel_source = kernel_source.substitute("reset_dt()", FixedStep ? "" : "_dt = $min_dt$f");
		kernel_source = kernel_source.substitute("$min_dt$", to!(char[])(MinDt));
		kernel_source = kernel_source.substitute("$time_step$", to!(char[])(Model.TimeStepSize));
		kernel_source = kernel_source.substitute("$record_error$", to!(char[])(RECORD_ERROR));
		kernel_source = kernel_source.substitute("$circ_buffer_error$", to!(char[])(CIRC_BUFFER_ERROR));
		
		StepKernelSource = kernel_source;
	}
	
	private void CreateDeliverKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto kernel_source = DeliverKernelTemplate.dup;
		
		kernel_source = kernel_source.substitute("$type_name$", Name);
		
		/* Event source args */
		source.Tab(2);
		if(NeedSrcSynCode)
		{
			source ~= "__local int* fire_table,";
			source ~= "__global int* _circ_buffer_start,";
			source ~= "__global int* _circ_buffer_end,";
			source ~= "__global $num_type$* _circ_buffer,";
			source ~= "__global int2* _dest_syn_buffer,";
			source ~= "__global int* _fired_syn_idx_buffer,";
			source ~= "__global int* _fired_syn_buffer,";
		}
		source.Inject(kernel_source, "$event_source_args$");
		
		/* Thresholds */
		source.Tab;
		int event_src_idx = 0;
		foreach(thresh; &type.AllEventSources)
		{
			if(NeedSrcSynCode)
			{
				source ~= "{";
				source.Tab;
			
				char[] src = `
int _idx_idx = $num_event_sources$ * i + $event_source_idx$;
int _buff_start = _circ_buffer_start[_idx_idx];
if(_buff_start >= 0) /* See if we have any spikes that we can check */
{
	const int _circ_buffer_size = $circ_buffer_size$;
	int _buff_idx = (i * $num_event_sources$ + $event_source_idx$) * _circ_buffer_size + _buff_start;

	if(_t > _circ_buffer[_buff_idx])
	{
		int buff_end = _circ_buffer_end[_idx_idx];
#if PARALLEL_DELIVERY
#if USE_ATOMIC_DELIVERY
		fire_table[atomic_inc(&fire_table_idx)] = $num_event_sources$ * i + $event_source_idx$;
#else
		fire_table[$num_event_sources$ * _local_id + $event_source_idx$] = $num_event_sources$ * i + $event_source_idx$;
		need_to_deliver = true;
#endif
#else
		int syn_start = num_synapses * _idx_idx;
		for(int syn_id = 0; syn_id < num_synapses; syn_id++)
		{
			int2 dest = _dest_syn_buffer[syn_id + syn_start];
			if(dest.s0 >= 0)
			{
				/* Get the index into the global syn buffer */
				int dest_syn = atomic_inc(&_fired_syn_idx_buffer[dest.s0]);
				_fired_syn_buffer[dest_syn] = dest.s1;
			}
		}
#endif
		_buff_start = (_buff_start + 1) % _circ_buffer_size;
		if(_buff_start == buff_end)
		{
			_buff_start = -1;
		}
		_circ_buffer_start[_idx_idx] = _buff_start;
	}
}
`.dup;
				src = src.substitute("$event_source_idx$", to!(char[])(event_src_idx));
				
				source.AddBlock(src);
				source.DeTab;
				source ~= "}";
				event_src_idx++;
			}
		}
		source.Inject(kernel_source, "$event_source_code$");
		
		if(NeedSrcSynCode)
		{
			char[] src = 
`
#if PARALLEL_DELIVERY
	barrier(CLK_LOCAL_MEM_FENCE);
#if !USE_ATOMIC_DELIVERY
	if(need_to_deliver)
	{
#endif
		int _local_size = get_local_size(0);
		int num_fired;
#if USE_ATOMIC_DELIVERY
		num_fired = fire_table_idx;
#else
		num_fired = _local_size * $num_event_sources$;
#endif

		for(int ii = 0; ii < num_fired; ii++)
		{
#if !USE_ATOMIC_DELIVERY
			if(fire_table[ii] < 0)
				continue;
#endif

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
#if !USE_ATOMIC_DELIVERY
	}
#endif
#endif
`.dup;
			source.AddBlock(src);
		}
		source.Inject(kernel_source, "$parallel_delivery_code$");
		
		kernel_source = kernel_source.substitute("$num_event_sources$", to!(char[])(NumEventSources));
		kernel_source = kernel_source.substitute("$circ_buffer_size$", to!(char[])(CircBufferSize));
		kernel_source = kernel_source.substitute("$num_synapses$", to!(char[])(NumSrcSynapses));
		kernel_source = kernel_source.substitute("$time_step$", to!(char[])(Model.TimeStepSize));
		
		DeliverKernelSource = kernel_source;
	}
	
	private void CreateInitKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto init_source = type.GetInitSource();
		
		auto kernel_source = InitKernelTemplate.dup;
		
		kernel_source = kernel_source.substitute("$type_name$", Name);
		
		/* Value arguments */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "__global $num_type$* _" ~ name ~ "_buf,";
		}
		source.Inject(kernel_source, "$val_args$");
		
		/* Constant arguments */
		source.Tab(2);
		foreach(name, state; &type.AllConstants)
		{
			source ~= "const $num_type$ " ~ name ~ ",";
		}
		source.Inject(kernel_source, "$constant_args$");
		
		source.Tab(2);
		if(NeedSrcSynCode)
		{
			source ~= "__global int2* _dest_syn_buffer,";
		}
		source.Inject(kernel_source, "$event_source_args$");
		
		/* Load vals */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "$num_type$ " ~ name ~ " = _" ~ name ~ "_buf[i];";
		}
		source.Inject(kernel_source, "$load_vals$");
		
		/* Perform initialization */
		source.Tab(2);
		source.AddBlock(init_source);
		source.Inject(kernel_source, "$init_vals$");
		
		/* Save values */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "_" ~ name ~ "_buf[i] = " ~ name ~ ";";
		}
		source.Inject(kernel_source, "$save_vals$");
		
		InitKernelSource = kernel_source;
	}
	
	bool FixedStep()
	{
		return cast(CAdaptiveIntegrator!(float_t))Integrator is null;
	}
	
	override
	double opIndex(char[] name)
	{
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			return Constants[*idx_ptr];
		}
		
		idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr !is null)
		{
			return ValueBuffers[*idx_ptr].DefaultValue;
		}
		
		idx_ptr = name in SynGlobalBufferRegistry;
		if(idx_ptr !is null)
		{
			return SynGlobalBuffers[*idx_ptr].DefaultValue;
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	override
	double opIndexAssign(double val, char[] name)
	{	
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			Constants[*idx_ptr] = val;
			if(Model.Initialized)
				SetConstant(*idx_ptr);
			return val;
		}
		
		idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr !is null)
		{
			ValueBuffers[*idx_ptr].DefaultValue = val;
			return val;
		}
		
		idx_ptr = name in SynGlobalBufferRegistry;
		if(idx_ptr !is null)
		{
			SynGlobalBuffers[*idx_ptr].DefaultValue = val;
			return val;
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	/* These two functions can be used to modify values after the model has been created.
	 */
	override
	double opIndex(char[] name, int idx)
	{
		assert(Model.Initialized, "Model needs to be Initialized before using this function.");
		assert(idx < Count, "Neuron index needs to be less than Count.");
		assert(idx >= 0, "Invalid neuron index.");
	
		auto idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr !is null)
		{
			return ValueBuffers[*idx_ptr].Buffer[idx];
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	override
	double opIndexAssign(double val, char[] name, int idx)
	{
		assert(Model.Initialized, "Model needs to be Initialized before using this function.");
		assert(idx < Count, "Neuron index needs to be less than Count.");
		assert(idx >= 0, "Invalid neuron index.");
		
		auto idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr !is null)
		{
			ValueBuffers[*idx_ptr].Buffer[idx] = val;
			return val;
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	/* These two functions can be used to modify synglobals after the model has been created.
	 * syn_idx refers to the synapse index in this type (i.e. each successive type has indices starting from 0)
	 */
	override
	double opIndex(char[] name, int nrn_idx, int syn_idx)
	{
		assert(Model.Initialized, "Model needs to be Initialized before using this function.");
		assert(nrn_idx < Count, "Neuron index needs to be less than Count.");
		assert(nrn_idx >= 0, "Invalid neuron index.");
		assert(syn_idx >= 0, "Invalid synapse index.");
	
		auto idx_ptr = name in SynGlobalBufferRegistry;
		if(idx_ptr !is null)
		{
			auto buffer = SynGlobalBuffers[*idx_ptr].Buffer;
			auto num_syns_per_nrn = buffer.Length / Count;
			assert(syn_idx < num_syns_per_nrn, "Synapse index needs to be less than the number of synapses for this synapse type.");
			
			auto idx = num_syns_per_nrn * nrn_idx + syn_idx;
			
			return buffer[idx];
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	override
	double opIndexAssign(double val, char[] name, int nrn_idx, int syn_idx)
	{
		assert(Model.Initialized, "Model needs to be Initialized before using this function.");
		assert(nrn_idx < Count, "Neuron index needs to be less than Count.");
		assert(nrn_idx >= 0, "Invalid neuron index.");
		assert(syn_idx >= 0, "Invalid synapse index.");
		
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
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	void Shutdown()
	{
		if(!Model.Initialized)
			return;

		/* TODO: Add safe releases to all of these */

		foreach(buffer; ValueBuffers)
			buffer.Release();
			
		foreach(buffer; SynGlobalBuffers)
			buffer.Release();
			
		foreach(buffer; SynapseBuffers)
			buffer.Release();
			
		foreach(buffer; EventSourceBuffers)
			buffer.Release();

		CircBufferStart.Release();
		CircBufferEnd.Release();
		CircBuffer.Release();
		ErrorBuffer.Release();
		RecordFlagsBuffer.Release();
		RecordBuffer.Release();
		RecordIdxBuffer.Release();
		DestSynBuffer.Release();
		
		InitKernel.Release();
		StepKernel.Release();
		DeliverKernel.Release();
		
		Integrator.Shutdown();
		
		if(RandLen)
			Rand.Shutdown();
	}
	
	void UpdateRecorders(int timestep, bool last = false)
	{
		assert(Model.Initialized);
		
		if(CommonRecorderIds.length)
		{
			if((RecordRate && ((timestep + 1) % RecordRate == 0)) || last)
			{
				int num_written = RecordIdxBuffer[0];
				if(num_written)
				{
					auto output = RecordBuffer.MapRead(0, num_written);
					scope(exit) RecordBuffer.UnMap();
					//Stdout.formatln("num_written: {} {}", num_written, output.length);
					foreach(quad; output)
					{
						int id = cast(int)quad[0];
						//Stdout.formatln("{:5} {:5} {:5} {}", quad[0], quad[1], quad[2], quad[3]);
						CommonRecorder.AddDatapoint(quad[0], quad[1], cast(int)quad[2], cast(int)quad[3]);
					}
				}
			}
			/* The one for the normal RecordRate triggers is done inside the deliver kernel */
			if(last)
				RecordIdxBuffer[0] = 0;
		}
	}
	
	override
	CRecorder Record(int neuron_id, int flags)
	{
		assert(Model.Initialized);
		assert(neuron_id >= 0);
		assert(neuron_id < Count);
		
		CommonRecorderIds ~= neuron_id;
		RecordFlagsBuffer[neuron_id] = flags;
		
		return CommonRecorder;
	}
	
	override
	void StopRecording(int neuron_id)
	{
		assert(Model.Initialized);
		assert(neuron_id >= 0);
		assert(neuron_id < Count);
		
		CommonRecorderIds.length = CommonRecorderIds.remove(neuron_id);
		
		RecordFlagsBuffer[neuron_id] = 0;
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
	
	void SetConnection(int src_nrn_id, int event_source, int src_slot, int dest_neuron_id, int dest_slot)
	{
		assert(Model.Initialized);
		
		assert(src_nrn_id >= 0 && src_nrn_id < Count);
		assert(event_source >= 0 && event_source < NumEventSources);
		assert(src_slot >= 0 && src_slot < NumSrcSynapses);
		
		int src_syn_id = (src_nrn_id * NumEventSources + event_source) * NumSrcSynapses + src_slot;
		
		DestSynBuffer()[src_syn_id] = cl_int2(dest_neuron_id, dest_slot);
	}
	
	int GetSrcSlot(int src_nrn_id, int event_source)
	{
		assert(src_nrn_id >= 0 && src_nrn_id < Count);
		assert(event_source >= 0 && event_source < NumEventSources);
		
		auto idx = EventSourceBuffers[event_source].FreeIdx[src_nrn_id];
		
		if(idx >= NumSrcSynapses)
			return -1;
		
		idx++;
		
		EventSourceBuffers()[event_source].FreeIdx[src_nrn_id] = idx;
		
		return idx - 1;
	}
	
	int GetDestSlot(int dest_nrn_id, int dest_syn_type)
	{
		assert(dest_nrn_id >= 0 && dest_nrn_id < Count);
		assert(dest_syn_type >= 0 && dest_syn_type < SynapseBuffers.length);
		
		auto idx = SynapseBuffers[dest_syn_type].FreeIdx[dest_nrn_id];
		
		if(idx >= SynapseBuffers[dest_syn_type].Count)
			return -1;
		
		idx++;
		
		SynapseBuffers()[dest_syn_type].FreeIdx[dest_nrn_id] = idx;
		
		return idx - 1;
	}
	
	int GetSynapseTypeOffset(int type)
	{
		assert(type >= 0 && type < SynapseBuffers.length, "Invalid synapse type.");
		return SynapseBuffers[type].SlotOffset;
	}
	
	void Connect(char[] connector_name, int multiplier, int[2] src_nrn_range, int src_event_source, CNeuronGroup!(float_t) dest, int[2] dest_nrn_range, int dest_syn_type, double[char[]] args)
	{
		auto conn_ptr = connector_name in Connectors;
		if(conn_ptr is null)
			throw new Exception("Neuron group '" ~ Name ~ "' does not have a connector named '" ~ connector_name ~ "'.");
		
		auto conn = *conn_ptr;
		
		if(args !is null)
		{
			foreach(arg_name, arg_val; args)
			{
				conn[arg_name] = arg_val;
			}
		}
		
		conn.Connect(multiplier, src_nrn_range, src_event_source, dest, dest_nrn_range, dest_syn_type);
		
		CheckErrors();
	}
	
	double MinDtVal = 0.1;
	
	override
	double MinDt()
	{
		return MinDtVal;
	}
	
	override
	void MinDt(double min_dt)
	{
		if(Model.Initialized && FixedStep)
		{
			Integrator.SetDt(min_dt);
		}
		MinDtVal = min_dt;
	}
	
	override
	int IntegratorArgOffset()
	{
		int rand_offset = 0;
		if(NeedRandArgs)
		{
			rand_offset = Rand.NumArgs;
		}
		return ValueBuffers.length + Constants.length + ArgOffsetStep + rand_offset;
	}
	
	override
	void Seed(int seed)
	{
		if(RandLen)
			Rand.Seed(seed);
	}
	
	cl_program Program()
	{
		return Model.Program;
	}
	
	override
	CCLCore Core()
	{
		return Model.Core;
	}
	
	override
	int Count()
	{
		return CountVal;
	}
	
	override
	bool Initialized()
	{
		return Model.Initialized;
	}
	
	override
	double TimeStepSize()
	{
		return Model.TimeStepSize;
	}
	
	mixin(Prop!("char[]", "Name", "override", "private"));
	mixin(Prop!("int", "NumEventSources", "override", "private"));
	mixin(Prop!("int", "NumSrcSynapses", "override", "private"));
	mixin(Prop!("CEventSourceBuffer[]", "EventSourceBuffers", "override", "private"));
	mixin(Prop!("CSynapseBuffer[]", "SynapseBuffers", "override", "private"));
	mixin(Prop!("CCLBuffer!(cl_int2)", "DestSynBuffer", "override", "private"));
	mixin(Prop!("int", "NrnOffset", "override", "private"));
	mixin(Prop!("CCLBuffer!(int)", "ErrorBuffer", "override", "private"));
	mixin(Prop!("CCLRand", "Rand", "override", "private"));
	mixin(Prop!("int", "RandLen", "override", "private"));

	CRecorder CommonRecorder;
	
	/* Holds the id's where we are recording events */
	int[] CommonRecorderIds;
	
	double[] Constants;
	int[char[]] ConstantRegistry;
	
	CValueBuffer!(float_t)[] ValueBuffers;
	int[char[]] ValueBufferRegistry;
	
	CSynGlobalBuffer!(float_t)[] SynGlobalBuffers;
	int[char[]] SynGlobalBufferRegistry;
	
	char[] NameVal;
	int CountVal = 0;
	ICLModel Model;
	
	char[] StepKernelSource;
	char[] InitKernelSource;
	char[] DeliverKernelSource;
	
	CCLKernel InitKernel;
	CCLKernel StepKernel;
	CCLKernel DeliverKernel;
	
	CCLBuffer!(int) CircBufferStart;
	CCLBuffer!(int) CircBufferEnd;
	CCLBuffer!(float_t) CircBuffer;
	CCLBuffer!(int) ErrorBufferVal;
	CCLBuffer!(int) RecordFlagsBuffer;
	CCLBuffer!(float_t4) RecordBuffer;
	CCLBuffer!(int) RecordIdxBuffer;
	/* TODO: This is stupid. Make it so each event source has its own buffer, much much simpler that way. */
	CCLBuffer!(cl_int2) DestSynBufferVal;
	
	int RecordLength;
	int RecordRate;
	int CircBufferSize = 20;
	int NumEventSourcesVal = 0;
	int NumThresholds = 0;
	int NumSynThresholds = 0;
	
	int NumSrcSynapsesVal; /* Number of pre-synaptic slots per event source */
	int NumDestSynapses; /* Number of post-synaptic slots per neuron */
	
	/* The place we reset the fired syn idx to*/
	int SynOffset;
	/* Offset for indexing into the model global indices */
	int NrnOffsetVal;
	
	CSynapseBuffer[] SynapseBuffersVal;
	CEventSourceBuffer[] EventSourceBuffersVal;
	
	int RandLenVal = 0;
	CCLRand RandVal;
	bool NeedRandArgs = false;
	
	CIntegrator!(float_t) Integrator;
	
	CCLConnector!(float_t)[char[]] Connectors;
}

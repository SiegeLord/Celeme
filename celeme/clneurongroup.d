module celeme.clneurongroup;

import celeme.frontend;
import celeme.clcore;
import celeme.clconnector;
import celeme.clmodel;
import celeme.recorder;
import celeme.alignedarray;
import celeme.sourceconstructor;
import celeme.util;
import celeme.integrator;
import celeme.adaptiveheun;
import celeme.heun;
import celeme.clrand;
import celeme.ineurongroup;

import opencl.cl;

import tango.io.Stdout;
import tango.text.Util;
import tango.util.Convert;
import tango.core.Array;

const ArgOffsetStep = 6;
char[] StepKernelTemplate = "
__kernel void $type_name$_step
	(
		const $num_type$ t,
		__global int* error_buffer,
		__global int* record_flags_buffer,
		__global int* record_idx,
		__global $num_type$4* record_buffer,
		const int record_buffer_size,
$val_args$
$constant_args$
$random_state_args$
$integrator_args$
$event_source_args$
$synapse_args$
$synapse_globals$
		const int count
	)
{
	int i = get_global_id(0);
	
	if(i < count)
	{
		$num_type$ cur_time = 0;
		const $num_type$ timestep = $time_step$;
		int record_flags = record_flags_buffer[i];
		
		$num_type$ dt;
$integrator_load$
$load_vals$
$load_rand_state$

$synapse_code$

		while(cur_time < timestep)
		{
			/* Record if necessary */
			if(record_flags && record_flags < $thresh_rec_offset$)
			{
				int idx = atomic_inc(&record_idx[0]);
				if(idx >= record_buffer_size)
				{
					error_buffer[i + 1] = 10;
					record_idx[0] = record_buffer_size - 1;
				}
				$num_type$4 record;
				record.s0 = i;
				record.s1 = cur_time + t;
				record.s3 = 0;
				switch(record_flags)
				{
$record_vals$
				}
				record_buffer[idx] = record;
			}
			
			$num_type$ error = 0;
			
			/* See where the thresholded states are before changing them (doesn't work for synapse states)*/
$threshold_pre_check$

			/* Declare local variables */
$declare_locals$

			/* Pre-stage code */
$pre_stage_code$

			/* Integrator code */
$integrator_code$
			
			/* Handle thresholds */
$thresholds$
			
			/* Post-thresh integrator code */
$integrator_post_thresh_code$
		}
$integrator_save$
$save_vals$
$save_rand_state$
	}
}
";

const ArgOffsetInit = 0;
char[] InitKernelTemplate = "
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
";

const ArgOffsetDeliver = 4;
const char[] DeliverKernelTemplate = "
__kernel void $type_name$_deliver
	(
		const $num_type$ t,
		__global int* error_buffer,
		__global int* record_idx,
		const int record_rate,
$event_source_args$
		const uint count
	)
{
	int i = get_global_id(0);
	
	if(i == 0 && record_rate && ((int)(t / $time_step$) % record_rate == 0))
	{
		record_idx[0] = 0;
	}
	
#if PARALLEL_DELIVERY
	int local_id = get_local_id(0);

#if USE_ATOMIC_DELIVERY
	__local int fire_table_idx;
	if(local_id == 0)
		fire_table_idx = 0;
#else
	for(int ii = 0; ii < $num_event_sources$; ii++)
		fire_table[local_id * $num_event_sources$ + ii] = -1;

	__local bool need_to_deliver;
	need_to_deliver = false;
#endif

	barrier(CLK_LOCAL_MEM_FENCE);
#endif
	
	/* Max number of source synapses */
	const int num_synapses = $num_synapses$;
	(void)num_synapses;
	
	if(i < count)
	{
$event_source_code$
	}

$parallel_delivery_code$
}
";

class CValueBuffer(T)
{
	this(CValue val, CCLCore core, size_t count)
	{
		DefaultValue = val.Value;
		Buffer = core.CreateBufferEx!(T)(count);
	}
	
	double opAssign(double val)
	{
		return DefaultValue = val;
	}
	
	void Release()
	{
		Buffer.Release();
	}
		
	CCLBuffer!(T) Buffer;	
	double DefaultValue;
}

class CSynGlobalBuffer(T)
{
	this(CValue val, CCLCore core, size_t num_syn)
	{
		DefaultValue = val.Value;
		Buffer = core.CreateBufferEx!(T)(num_syn);
	}
	
	void Release()
	{
		Buffer.Release();
	}
	
	CCLBuffer!(T) Buffer;
	double DefaultValue;
}

class CEventSourceBuffer
{
	this(CCLCore core, int nrn_count)
	{
		FreeIdx = core.CreateBufferEx!(int)(nrn_count);
		auto buff = FreeIdx.Map(CL_MAP_WRITE);
		buff[] = 0;
		FreeIdx.UnMap(buff);
	}
	
	void Release()
	{
		FreeIdx.Release();
	}
	
	/* Last free index */
	CCLBuffer!(int) FreeIdx;
}

class CSynapseBuffer
{
	this(CCLCore core, int offset, int count, int nrn_count)
	{
		FreeIdx = core.CreateBufferEx!(int)(nrn_count);
		auto buff = FreeIdx.Map(CL_MAP_WRITE);
		buff[] = 0;
		FreeIdx.UnMap(buff);
		SlotOffset = offset;
		Count = count;
	}
	
	void Release()
	{
		FreeIdx.Release();
	}
	/* Last free index */
	CCLBuffer!(int) FreeIdx;
	int SlotOffset;
	int Count;
}

class CNeuronGroup(float_t) : INeuronGroup
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
	
	this(CCLModel!(float_t) model, CNeuronType type, int count, char[] name, int sink_offset, int nrn_offset, bool adaptive_dt = true)
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
			SynapseBuffers ~= syn_buff;
			
			syn_type_offset += syn_type.NumSynapses;
		}
		
		foreach(ii; range(NumEventSources))
		{
			EventSourceBuffers ~= new CEventSourceBuffer(Core, Count);
		}
		
		if(NeedSrcSynCode)
		{
			CircBufferStart = Core.CreateBuffer(NumEventSources * Count * int.sizeof);
			CircBufferEnd = Core.CreateBuffer(NumEventSources * Count * int.sizeof);
			CircBuffer = Core.CreateBuffer(CircBufferSize * NumEventSources * Count * Model.NumSize);
		}
		
		ErrorBuffer = Core.CreateBuffer((Count + 1) * int.sizeof);
		RecordFlagsBuffer = Core.CreateBufferEx!(int)(Count);
		RecordBuffer = Core.CreateBufferEx!(float_t4)(RecordLength);
		RecordIdxBuffer = Core.CreateBufferEx!(int)(1);
		
		if(NeedSrcSynCode)
		{
			DestSynBuffer = Core.CreateBufferEx!(cl_int2)(Count * NumEventSources * NumSrcSynapses);
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
		
		EventRecorder = new CRecorder(Name ~ " events.");
		
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
		StepKernel = new CCLKernel(&Model.Program, Name ~ "_step");
		
		with(StepKernel)
		{
			/* Set the arguments. Start at 1 to skip the t argument*/
			arg_id = 1;
			SetGlobalArg(arg_id++, &ErrorBuffer);
			SetGlobalArg(arg_id++, &RecordFlagsBuffer.Buffer);
			SetGlobalArg(arg_id++, &RecordIdxBuffer.Buffer);
			SetGlobalArg(arg_id++, &RecordBuffer.Buffer);
			SetGlobalArg(arg_id++, &RecordLength);
			foreach(buffer; ValueBuffers)
			{
				SetGlobalArg(arg_id++, &buffer.Buffer.Buffer);
			}
			arg_id += Constants.length;
			if(RandLen)
				arg_id = Rand.SetArgs(StepKernel, arg_id);
			arg_id = Integrator.SetArgs(arg_id);
			if(NeedSrcSynCode)
			{
				/* Set the event source args */
				SetGlobalArg(arg_id++, &CircBufferStart);
				SetGlobalArg(arg_id++, &CircBufferEnd);
				SetGlobalArg(arg_id++, &CircBuffer);
			}
			if(NumDestSynapses)
			{
				SetGlobalArg(arg_id++, &Model.FiredSynIdxBuffer.Buffer);
				SetGlobalArg(arg_id++, &Model.FiredSynBuffer.Buffer);
				foreach(buffer; SynGlobalBuffers)
				{
					SetGlobalArg(arg_id++, &buffer.Buffer.Buffer);
				}
			}
			SetGlobalArg(arg_id++, &CountVal);
		}
		
		/* Init kernel */
		InitKernel = new CCLKernel(&Model.Program, Name ~ "_init");
		with(InitKernel)
		{
			/* Nothing to skip, so set it at 0 */
			arg_id = 0;
			foreach(buffer; ValueBuffers)
			{
				SetGlobalArg(arg_id++, &buffer.Buffer.Buffer);
			}
			arg_id += Constants.length;
			if(NeedSrcSynCode)
			{
				SetGlobalArg(arg_id++, &DestSynBuffer.Buffer);
			}
			SetGlobalArg(arg_id++, &CountVal);
		}
		
		/* Deliver kernel */
		DeliverKernel = new CCLKernel(&Model.Program, Name ~ "_deliver");
		
		with(DeliverKernel)
		{
			/* Set the arguments. Start at 1 to skip the t argument*/
			arg_id = 1;
			SetGlobalArg(arg_id++, &ErrorBuffer);
			SetGlobalArg(arg_id++, &RecordIdxBuffer.Buffer);
			SetGlobalArg(arg_id++, &RecordRate);
			if(NeedSrcSynCode)
			{
				/* Skip the fire table */
				arg_id++;
				/* Set the event source args */
				SetGlobalArg(arg_id++, &CircBufferStart);
				SetGlobalArg(arg_id++, &CircBufferEnd);
				SetGlobalArg(arg_id++, &CircBuffer);
				SetGlobalArg(arg_id++, &DestSynBuffer.Buffer);
				SetGlobalArg(arg_id++, &Model.FiredSynIdxBuffer.Buffer);
				SetGlobalArg(arg_id++, &Model.FiredSynBuffer.Buffer);
			}
			SetGlobalArg(arg_id++, &CountVal);
		}
		
		Core.Finish();
		
		Model.MemsetIntBuffer(RecordFlagsBuffer.Buffer, Count, 0);
		Model.MemsetIntBuffer(DestSynBuffer.Buffer, 2 * Count * NumSrcSynapses * NumEventSources, -1);
		
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
		Model.MemsetIntBuffer(ErrorBuffer, Count + 1, 0);
		RecordIdxBuffer.WriteOne(0, 0);
		
		if(NeedSrcSynCode)
		{
			Model.MemsetIntBuffer(CircBufferStart, Count * NumEventSources, -1);
			Model.MemsetIntBuffer(CircBufferEnd, Count * NumEventSources, 0);
		}
		
		/* Write the default values to the global buffers*/
		foreach(buffer; ValueBuffers)
		{
			auto arr = buffer.Buffer.Map(CL_MAP_WRITE);
			arr[] = buffer.DefaultValue;
			buffer.Buffer.UnMap(arr);
		}
		
		foreach(buffer; SynGlobalBuffers)
		{
			auto arr = buffer.Buffer.Map(CL_MAP_WRITE);
			arr[] = buffer.DefaultValue;
			buffer.Buffer.UnMap(arr);
		}
		Core.Finish();
		
		foreach(recorder; Recorders)
			recorder.Length = 0;
			
		EventRecorder.Length = 0;
	}
	
	void SetConstant(int idx)
	{
		assert(Model.Initialized);
		
		float_t val = Constants[idx];
		InitKernel.SetGlobalArg(idx + ValueBuffers.length + ArgOffsetInit, &val);
		StepKernel.SetGlobalArg(idx + ValueBuffers.length + ArgOffsetStep, &val);
	}
	
	void SetTolerance(char[] state, double tolerance)
	{
		auto adaptive = cast(CAdaptiveIntegrator!(float_t))Integrator;
		if(adaptive !is null)
		{
			adaptive.SetTolerance(state, tolerance);
		}
		else
		{
			throw new Exception("Can only set tolerances for adaptive integrators.");
		}
	}
	
	void CallInitKernel(size_t workgroup_size)
	{
		assert(Model.Initialized);
		
		size_t total_num = (Count / workgroup_size) * workgroup_size;
		if(total_num < Count)
			total_num += workgroup_size;
		auto err = clEnqueueNDRangeKernel(Core.Commands, InitKernel.Kernel, 1, null, &total_num, &workgroup_size, 0, null, null);
		assert(err == CL_SUCCESS);
	}
	
	void CallStepKernel(double sim_time, size_t workgroup_size)
	{
		assert(Model.Initialized);
		
		size_t total_num = (Count / workgroup_size) * workgroup_size;
		if(total_num < Count)
			total_num += workgroup_size;
		
		with(StepKernel)
		{
			float_t t_val = sim_time;
			SetGlobalArg(0, &t_val);

			auto err = clEnqueueNDRangeKernel(Core.Commands, Kernel, 1, null, &total_num, &workgroup_size, 0, null, null);
			assert(err == CL_SUCCESS);
		}
	}
	
	void CallDeliverKernel(double sim_time, size_t workgroup_size)
	{
		assert(Model.Initialized);
		
		size_t total_num = (Count / workgroup_size) * workgroup_size;
		if(total_num < Count)
			total_num += workgroup_size;
		
		with(DeliverKernel)
		{
			float_t t_val = sim_time;
			SetGlobalArg(0, &t_val);
			
			if(NeedSrcSynCode)
			{
				/* Local fire table */
				SetLocalArg(ArgOffsetDeliver, int.sizeof * workgroup_size * NumEventSources);
			}

			auto err = clEnqueueNDRangeKernel(Core.Commands, Kernel, 1, null, &total_num, &workgroup_size, 0, null, null);
			assert(err == CL_SUCCESS);
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
			source ~= "__global $num_type$* " ~ name ~ "_buf,";
		}
		source.Inject(kernel_source, "$val_args$");
		
		/* Constant arguments */
		source.Tab(2);
		foreach(name, state; &type.AllConstants)
		{
			source ~= "const $num_type$ " ~ name ~ ",";
		}
		source.Inject(kernel_source, "$constant_args$");
		
		/* Random state arguments */
		source.Tab(2);
		if(RandLen)
			source.AddBlock(Rand.GetArgsCode());
		source.Inject(kernel_source, "$random_state_args$");
		
		/* Integrator arguments */
		source.Tab(2);
		source.AddBlock(Integrator.GetArgsCode(type));
		source.Inject(kernel_source, "$integrator_args$");
		
		/* Event source args */
		source.Tab(2);
		if(NeedSrcSynCode)
		{
			source ~= "__global int* circ_buffer_start,";
			source ~= "__global int* circ_buffer_end,";
			source ~= "__global $num_type$* circ_buffer,";
		}
		source.Inject(kernel_source, "$event_source_args$");
		
		/* Synapse args */
		source.Tab(2);
		if(NumDestSynapses)
		{
			source ~= "__global int* fired_syn_idx_buffer,";
			source ~= "__global int* fired_syn_buffer,";
		}
		source.Inject(kernel_source, "$synapse_args$");
		
		/* Synapse globals */
		source.Tab(2);
		if(NumDestSynapses)
		{
			foreach(name, val; &type.AllSynGlobals)
			{
				source ~= "__global $num_type$* " ~ name ~ "_buf,";
			}
		}
		source.Inject(kernel_source, "$synapse_globals$");
		
		/* Integrator load */
		source.Tab(2);
		source.AddBlock(Integrator.GetLoadCode(type));
		source.Inject(kernel_source, "$integrator_load$");
		
		/* Load vals */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "$num_type$ " ~ name ~ " = " ~ name ~ "_buf[i];";
		}
		source.Inject(kernel_source, "$load_vals$");
		
		/* Load rand state */
		source.Tab(2);
		if(RandLen)
			source ~= Rand.GetLoadCode();
		source.Inject(kernel_source, "$load_rand_state$");
		
		/* Synapse code */
		source.Tab(2);
		if(NumDestSynapses)
		{
			source.AddBlock(
`
const int syn_offset = $syn_offset$ + i * ` ~ to!(char[])(NumDestSynapses) ~ `;
int syn_table_end = fired_syn_idx_buffer[i + $nrn_offset$];
if(syn_table_end != syn_offset)
{
	for(int syn_table_idx = syn_offset; syn_table_idx < syn_table_end; syn_table_idx++)
	{
		int syn_i = fired_syn_buffer[syn_table_idx];
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
				source ~= "int g_syn_i = syn_i - " ~ to!(char[])(syn_type_start) ~ " + i * " ~ to!(char[])(syn_type.NumSynapses) ~ ";";
				auto prefix = syn_type.Prefix;
				
				foreach(val; &syn_type.Synapse.AllSynGlobals)
				{
					auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
					source ~= "$num_type$ " ~ name ~ " = " ~ name ~ "_buf[g_syn_i];";
				}
				
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
				source.AddBlock(syn_code);
				
				foreach(val; &syn_type.Synapse.AllSynGlobals)
				{
					if(!val.ReadOnly)
					{
						auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
						source ~= name ~ "_buf[g_syn_i] = " ~ name ~ ";";
					}
				}
				
				source.DeTab();
				source ~= "}";
				
				syn_type_start = syn_type_offset;
			}
			source.DeTab;
			source ~= "}";
			if(!FixedStep)
				source ~= "dt = $min_dt$f;";
			source ~= "fired_syn_idx_buffer[i + $nrn_offset$] = syn_offset;";
			source.DeTab;
			source ~= "}";
			
			source.Source = source.Source.substitute("$nrn_offset$", to!(char[])(NrnOffset));
			source.Source = source.Source.substitute("$syn_offset$", to!(char[])(SynOffset));
			source.DeTab(2);
		}
		source.Inject(kernel_source, "$synapse_code$");
		
		/* Record vals */
		source.Tab(5);
		/* The indices are offset by 1, so that 0 can be used as a special
		 * index indicating that nothing is to be recorded*/
		int non_local_idx = 1; 
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "case " ~ to!(char[])(non_local_idx) ~ ":";
			source.Tab;
			source ~= "record.s2 = " ~ name ~ ";";
			source.DeTab;
			source ~= "break;";
			non_local_idx++;
		}
		source.Inject(kernel_source, "$record_vals$");
		
		/* Threshold pre-check */
		source.Tab(3);
		int thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			source ~= "bool thresh_" ~ to!(char[])(thresh_idx) ~ "_state = " ~ thresh.State ~ " " ~ thresh.Condition ~ ";";
			
			thresh_idx++;
		}
		NumThresholds = thresh_idx;
		source.Inject(kernel_source, "$threshold_pre_check$");
		
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
		
		/* Thresholds */
		source.Tab(3);
		int event_src_idx = 0;
		thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			source ~= "if(!thresh_$thresh_idx$_state && (" ~ thresh.State ~ " " ~ thresh.Condition ~ "))";
			source ~= "{";
			source.Tab;
			
			if(thresh.IsEventSource)
				source ~= "$num_type$ delay = 1.0f;";
			source.AddBlock(thresh.Source);
			if(thresh.ResetTime && !FixedStep)
				source ~= "dt = $min_dt$f;";
			
			source.AddBlock(
`if(record_flags >= $thresh_rec_offset$ && record_flags - $thresh_rec_offset$ == $thresh_idx$)
{
	int idx = atomic_inc(&record_idx[0]);
	if(idx >= record_buffer_size)
	{
		error_buffer[i + 1] = 10;
		record_idx[0] = record_buffer_size - 1;
	}

	$num_type$4 record;
	record.s0 = i;
	record.s1 = cur_time + t;
	record.s2 = $thresh_idx$;
	record.s3 = 1;
	record_buffer[idx] = record;
}`);
			source.Source = source.Source.substitute("$thresh_idx$", to!(char[])(thresh_idx));
			
			if(NeedSrcSynCode && thresh.IsEventSource)
			{
				char[] src = 
`int idx_idx = $num_event_sources$ * i + $event_source_idx$;
int buff_start = circ_buffer_start[idx_idx];

if(buff_start != circ_buffer_end[idx_idx])
{
	const int circ_buffer_size = $circ_buffer_size$;
	
	int end_idx;
	if(buff_start < 0) //It is empty
	{
		circ_buffer_start[idx_idx] = 0;
		circ_buffer_end[idx_idx] = 1;
		end_idx = 1;
	}
	else
	{
		end_idx = circ_buffer_end[idx_idx] = (circ_buffer_end[idx_idx] + 1) % circ_buffer_size;
	}
	int buff_idx = (i * $num_event_sources$ + $event_source_idx$) * circ_buffer_size + end_idx - 1;
	circ_buffer[buff_idx] = t + cur_time + delay;
}
else //It is full, error
{
	error_buffer[i + 1] = 100 + $event_source_idx$;
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
		
		/* Integrator save */
		source.Tab(3);
		source.AddBlock(Integrator.GetPostThreshCode(type));
		source.Inject(kernel_source, "$integrator_post_thresh_code$");
		
		
		/* Integrator save */
		source.Tab(2);
		source.AddBlock(Integrator.GetSaveCode(type));
		source.Inject(kernel_source, "$integrator_save$");
		
		/* Save values */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			if(!state.ReadOnly)
				source ~= name ~ "_buf[i] = " ~ name ~ ";";
		}
		source.Inject(kernel_source, "$save_vals$");
		
		/* Save rand state */
		source.Tab(2);
		if(RandLen)
			source ~= Rand.GetSaveCode();
		source.Inject(kernel_source, "$save_rand_state$");
		
		kernel_source = kernel_source.substitute("reset_dt()", FixedStep ? "" : "dt = $min_dt$f");
		kernel_source = kernel_source.substitute("$thresh_rec_offset$", to!(char[])(non_local_idx));
		kernel_source = kernel_source.substitute("$min_dt$", to!(char[])(MinDt));
		kernel_source = kernel_source.substitute("$time_step$", to!(char[])(Model.TimeStepSize));
		
		if(RandLen)
			kernel_source = kernel_source.substitute("rand()", "rand" ~ to!(char[])(RandLen) ~ "(&rand_state)");
		else if(kernel_source.containsPattern("rand()"))
			throw new Exception("Found rand() but neuron type '" ~ type.Name ~ "' does not have random_state_len > 0.");
		
		kernel_source = kernel_source.substitute("rand()", "rand" ~ to!(char[])(RandLen) ~ "(&rand_state)");
		
		ThreshRecordOffset = non_local_idx;
		
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
			source ~= "__global int* circ_buffer_start,";
			source ~= "__global int* circ_buffer_end,";
			source ~= "__global $num_type$* circ_buffer,";
			source ~= "__global int2* dest_syn_buffer,";
			source ~= "__global int* fired_syn_idx_buffer,";
			source ~= "__global int* fired_syn_buffer,";
		}
		source.Inject(kernel_source, "$event_source_args$");
		
		/* Thresholds */
		source.Tab(2);
		int event_src_idx = 0;
		foreach(thresh; &type.AllEventSources)
		{
			if(NeedSrcSynCode)
			{
				source ~= "{";
				source.Tab;
			
				char[] src = `
int idx_idx = $num_event_sources$ * i + $event_source_idx$;
int buff_start = circ_buffer_start[idx_idx];
if(buff_start >= 0) /* See if we have any spikes that we can check */
{
	const int circ_buffer_size = $circ_buffer_size$;
	int buff_idx = (i * $num_event_sources$ + $event_source_idx$) * circ_buffer_size + buff_start;

	if(t > circ_buffer[buff_idx])
	{
		int buff_end = circ_buffer_end[idx_idx];
#if PARALLEL_DELIVERY
#if USE_ATOMIC_DELIVERY
		fire_table[atomic_inc(&fire_table_idx)] = $num_event_sources$ * i + $event_source_idx$;
#else
		fire_table[$num_event_sources$ * local_id + $event_source_idx$] = $num_event_sources$ * i + $event_source_idx$;
		need_to_deliver = true;
#endif
#else
		int syn_start = num_synapses * idx_idx;
		for(int syn_id = 0; syn_id < num_synapses; syn_id++)
		{
			int2 dest = dest_syn_buffer[syn_id + syn_start];
			if(dest.s0 >= 0)
			{
				/* Get the index into the global syn buffer */
				int dest_syn = atomic_inc(&fired_syn_idx_buffer[dest.s0]);
				fired_syn_buffer[dest_syn] = dest.s1;
			}
		}
#endif
		buff_start = (buff_start + 1) % circ_buffer_size;
		if(buff_start == buff_end)
		{
			buff_start = -1;
		}
		circ_buffer_start[idx_idx] = buff_start;
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
		int local_size = get_local_size(0);
		int num_fired;
#if USE_ATOMIC_DELIVERY
		num_fired = fire_table_idx;
#else
		num_fired = local_size * $num_event_sources$;
#endif

		for(int ii = 0; ii < num_fired; ii++)
		{
#if !USE_ATOMIC_DELIVERY
			if(fire_table[ii] < 0)
				continue;
#endif

			int syn_start = num_synapses * fire_table[ii];
			for(int syn_id = local_id; syn_id < num_synapses; syn_id += local_size)
			{
				int2 dest = dest_syn_buffer[syn_id + syn_start];
				if(dest.s0 >= 0)
				{
					/* Get the index into the global syn buffer */
					int dest_syn = atomic_inc(&fired_syn_idx_buffer[dest.s0]);
					fired_syn_buffer[dest_syn] = dest.s1;
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
			source ~= "__global $num_type$* " ~ name ~ "_buf,";
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
			source ~= "__global int2* dest_syn_buffer,";
		}
		source.Inject(kernel_source, "$event_source_args$");
		
		/* Load vals */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "$num_type$ " ~ name ~ " = " ~ name ~ "_buf[i];";
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
			source ~= name ~ "_buf[i] = " ~ name ~ ";";
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
			return ValueBuffers[*idx_ptr].Buffer.ReadOne(idx);
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
			ValueBuffers[*idx_ptr].Buffer.WriteOne(idx, val);
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
			
			return buffer.ReadOne(idx);
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
			
			buffer.WriteOne(idx, val);
			
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

		clReleaseMemObject(CircBufferStart);
		clReleaseMemObject(CircBufferEnd);
		clReleaseMemObject(CircBuffer);
		clReleaseMemObject(ErrorBuffer);
		RecordFlagsBuffer.Release();
		RecordBuffer.Release();
		RecordIdxBuffer.Release();
		DestSynBuffer.Release();
		
		InitKernel.Release();
		StepKernel.Release();
		DeliverKernel.Release();
		
		Integrator.Shutdown();
	}
	
	void UpdateRecorders(int timestep, bool last = false)
	{
		assert(Model.Initialized);
		
		if(Recorders.length || EventRecorderIds.length)
		{
			if((RecordRate && ((timestep + 1) % RecordRate == 0)) || last)
			{
				int num_written = RecordIdxBuffer.ReadOne(0);
				if(num_written)
				{
					auto output = RecordBuffer.Map(CL_MAP_READ, 0, num_written);
					//Stdout.formatln("num_written: {} {}", num_written, output.length);
					foreach(quad; output)
					{
						int id = cast(int)quad[0];
						//Stdout.formatln("{:5} {:5} {:5} {}", quad[0], quad[1], quad[2], quad[3]);
						if(quad[3] > 0)
							EventRecorder.AddDatapoint(quad[1], id * NumThresholds + quad[2]);
						else
							Recorders[id].AddDatapoint(quad[1], quad[2]);
					}
					RecordBuffer.UnMap(output);
				}
			}
			/* The one for the normal RecordRate triggers is done inside the deliver kernel */
			if(last)
				RecordIdxBuffer.WriteOne(0, 0);
		}
	}
	
	override
	CRecorder Record(int neuron_id, char[] name)
	{
		assert(Model.Initialized);
		assert(neuron_id >= 0);
		assert(neuron_id < Count);
		
		/* TODO: This relies on states being first in the valuebuffer registry... */
		auto idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr is null)
			throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
		
		/* Offset the index by 1 */
		RecordFlagsBuffer.WriteOne(neuron_id, 1 + *idx_ptr);
		
		auto rec = new CRecorder(Name ~ "[" ~ to!(char[])(neuron_id) ~ "]." ~ name);
		Recorders[neuron_id] = rec;
		return rec;
	}
	
	override
	CRecorder RecordEvents(int neuron_id, int thresh_id)
	{
		assert(Model.Initialized);
		assert(neuron_id >= 0);
		assert(neuron_id < Count);
		assert(thresh_id >= 0);
		
		EventRecorderIds ~= neuron_id;
		/* Offset the index by 1 */
		RecordFlagsBuffer.WriteOne(neuron_id, thresh_id + ThreshRecordOffset);
		
		return EventRecorder;
	}
	
	override
	void StopRecording(int neuron_id)
	{
		assert(Model.Initialized);
		assert(neuron_id >= 0);
		assert(neuron_id < Count);
		
		auto idx_ptr = neuron_id in Recorders;
		if(idx_ptr !is null)
		{
			idx_ptr.Detach();
			Recorders.remove(neuron_id);
		}
		
		EventRecorderIds.length = EventRecorderIds.remove(neuron_id);
		
		RecordFlagsBuffer.WriteOne(neuron_id, 0);
	}
	
	void CheckErrors()
	{
		assert(Model.Initialized);
		
		auto errors = new int[](Count + 1);
		clEnqueueReadBuffer(Core.Commands, ErrorBuffer, CL_TRUE, 0, (Count + 1) * int.sizeof, errors.ptr, 0, null, null);
		
		bool found_errors = false;
		if(errors[0])
		{
			Stdout.formatln("Error: {}", errors[0]);
			found_errors = true;
		}
		foreach(ii, error; errors[1..$])
		{
			if(error)
			{
				Stdout.formatln("Error: {} : {}", ii, error);
				found_errors = true;
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
		
		DestSynBuffer.WriteOne(src_syn_id, cl_int2(dest_neuron_id, dest_slot));
		//auto arr = DestSynBuffer.Map(CL_MAP_READ);
	}
	
	int GetSrcSlot(int src_nrn_id, int event_source)
	{
		assert(src_nrn_id >= 0 && src_nrn_id < Count);
		assert(event_source >= 0 && event_source < NumEventSources);
		
		auto idx = EventSourceBuffers[event_source].FreeIdx.ReadOne(src_nrn_id);
		
		if(idx >= NumSrcSynapses)
			return -1;
		
		idx++;
		
		EventSourceBuffers[event_source].FreeIdx.WriteOne(src_nrn_id, idx);
		
		return idx - 1;
	}
	
	int GetDestSlot(int dest_nrn_id, int dest_syn_type)
	{
		assert(dest_nrn_id >= 0 && dest_nrn_id < Count);
		assert(dest_syn_type >= 0 && dest_syn_type < SynapseBuffers.length);
		
		auto idx = SynapseBuffers[dest_syn_type].FreeIdx.ReadOne(dest_nrn_id);
		
		if(idx >= SynapseBuffers[dest_syn_type].Count)
			return -1;
		
		idx++;
		
		SynapseBuffers[dest_syn_type].FreeIdx.WriteOne(dest_nrn_id, idx);
		
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
	
	int IntegratorArgOffset()
	{
		int rand_offset = 0;
		if(RandLen)
		{
			rand_offset = Rand.NumArgs;
		}
		return ValueBuffers.length + Constants.length + ArgOffsetStep + rand_offset;
	}
	
	cl_program* Program()
	{
		return &Model.Program;
	}
	
	CCLCore Core()
	{
		return Model.Core;
	}
	
	override
	int Count()
	{
		return CountVal;
	}
	
	CRecorder[int] Recorders;
	CRecorder EventRecorder;
	
	/* Holds the id's where we are recording events */
	int[] EventRecorderIds;
	
	double[] Constants;
	int[char[]] ConstantRegistry;
	
	CValueBuffer!(float_t)[] ValueBuffers;
	int[char[]] ValueBufferRegistry;
	
	CSynGlobalBuffer!(float_t)[] SynGlobalBuffers;
	int[char[]] SynGlobalBufferRegistry;
	
	char[] Name;
	int CountVal = 0;
	CCLModel!(float_t) Model;
	
	char[] StepKernelSource;
	char[] InitKernelSource;
	char[] DeliverKernelSource;
	
	CCLKernel InitKernel;
	CCLKernel StepKernel;
	CCLKernel DeliverKernel;
	
	/* TODO: Convert these to CCLBuffers */
	cl_mem CircBufferStart;
	cl_mem CircBufferEnd;
	cl_mem CircBuffer;
	cl_mem ErrorBuffer;
	CCLBuffer!(int) RecordFlagsBuffer;
	CCLBuffer!(float_t4) RecordBuffer;
	CCLBuffer!(int) RecordIdxBuffer;
	/* TODO: This is stupid. Make it so each event source has its own buffer, much much simpler that way. */
	CCLBuffer!(cl_int2) DestSynBuffer;
	
	int RecordLength;
	int RecordRate;
	int CircBufferSize = 20;
	int NumEventSources = 0;
	int NumThresholds = 0;
	
	int NumSrcSynapses; /* Number of pre-synaptic slots per event source */
	int NumDestSynapses; /* Number of post-synaptic slots per neuron */
	
	/* The place we reset the fired syn idx to*/
	int SynOffset;
	/* Offset for indexing into the model global indices */
	int NrnOffset;
	
	int ThreshRecordOffset = 0;
	
	CSynapseBuffer[] SynapseBuffers;
	CEventSourceBuffer[] EventSourceBuffers;
	
	int RandLen = 0;
	CCLRand Rand;
	
	CIntegrator!(float_t) Integrator;
	
	CCLConnector!(float_t)[char[]] Connectors;
}

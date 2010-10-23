module celeme.clneurongroup;

import celeme.frontend;
import celeme.clcore;
import celeme.clmodel;
import celeme.recorder;
import celeme.alignedarray;
import celeme.sourceconstructor;
import celeme.util;

import opencl.cl;

import tango.io.Stdout;
import tango.text.Util;
import tango.util.Convert;

const ArgOffsetStep = 6;
char[] StepKernelTemplate = "
__kernel void $type_name$_step
	(
		const $num_type$ t,
		__global $num_type$* dt_buf,
		__global int* error_buffer,
		__global int* record_flags_buffer,
		__global int* record_idx,
		__global $num_type$4* record_buffer,
$val_args$
$constant_args$
$event_source_args$
$synapse_args$
		const int count
	)
{
	int i = get_global_id(0);
	
	if(i < count)
	{
		$num_type$ cur_time = 0;
		const $num_type$ timestep = 1;
		int record_flags = record_flags_buffer[i];
		
		$num_type$ dt = dt_buf[i];
$load_vals$

$synapse_code$

		while(cur_time < timestep)
		{
			/* Record if necessary */
			if(record_flags)
			{
				int idx = atom_inc(&record_idx[0]);
				$num_type$4 record;
				record.s0 = i;
				record.s1 = cur_time + t;
				switch(record_flags)
				{
$record_vals$
				}
				record_buffer[idx] = record;
			}
			
			$num_type$ error = 0;

			/* Declare local variables */
$declare_locals$

			/* Declare temporary storage for state*/
$declare_temp_states$

			/* First derivative stage */
$declare_derivs_1$

			/* Second derivative stage */
$declare_derivs_2$

			/* Compute the first derivatives */
$compute_derivs_1$

			/* Compute the first state estimate */
$apply_derivs_1$

			/* Compute the derivatives again */
$compute_derivs_2$

			/* Compute the final state estimate */
$apply_derivs_2$

			/* Compute the error in this step */
$compute_error$

			/* Transfer the state from the temporary storage to the real storage */
$reset_state$

			/* Advance and compute the new step size*/
			cur_time += dt;
			
			dt *= 0.8f * .46415888f * rootn(error + 0.00001f, -6);
			
			/* Handle thresholds */
$thresholds$
			
			/* Clamp the dt not too overshoot the timestep */
			if(cur_time < timestep && cur_time + dt >= timestep)
			{
				dt = timestep - cur_time + 0.0001f;
			}
		}
		dt_buf[i] = dt;
$save_vals$
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

const ArgOffsetDeliver = 3;
const char[] DeliverKernelTemplate = "
__kernel void $type_name$_deliver
	(
		const float t,
		__global int* error_buffer,
		__global int* record_idx,
$event_source_args$
		const uint count
	)
{
	int i = get_global_id(0);
	
	if(i == 0)
		record_idx[0] = 0;
	
#if PARALLEL_DELIVERY
	int local_id = get_local_id(0);

	fire_table[local_id] = -1;

	__local bool need_to_deliver;
	need_to_deliver = false;
	barrier(CLK_LOCAL_MEM_FENCE);
#endif
	
	/* Max number of source synapses */
	const int num_synapses = $num_synapses$;
	
	if(i < count)
	{
$event_source_code$
	}

#if PARALLEL_DELIVERY
	barrier(CLK_LOCAL_MEM_FENCE);
	if(need_to_deliver)
	{
		int local_size = get_local_size(0);

		for(int ii = 0; ii < local_size; ii++)
		{
			if(fire_table[ii] < 0)
				continue;

			int syn_start = num_synapses * fire_table[ii];
			for(int syn_id = local_id; syn_id < num_synapses; syn_id += local_size)
			{
				int2 dest = dest_syn_buffer[syn_id + syn_start];
				if(dest.s0 >= 0)
				{
					/* Get the index into the global syn buffer */
					int dest_syn = atom_inc(&fired_syn_idx_buffer[dest.s0]);
					fired_syn_buffer[dest_syn] = dest.s1;
				}
			}
		}
	}
#endif
}
";

class CNeuronGroup
{
	struct SValueBuffer
	{
		double Value;
		cl_mem Buffer;
	}
	
	this(CCLModel model, CNeuronType type, int count, char[] name, int sink_offset, int nrn_offset)
	{
		Model = model;
		Count = count;
		Name = name;
		NumEventSources = type.NumEventSources;
		RecordLength = type.RecordLength;
		CircBufferSize = type.CircBufferSize;
		SynOffset = sink_offset;
		NrnOffset = nrn_offset;
		NumDestSynapses = type.NumDestSynapses;
		NumSrcSynapses = type.NumSrcSynapses;
		
		/* Copy the non-locals and constants from the type */
		foreach(name, state; &type.AllNonLocals)
		{
			ValueBufferRegistry[name] = ValueBuffers.length;
			
			SValueBuffer buff;
			buff.Value = state.Value;
			buff.Buffer = Model.Core.CreateBuffer(Count * Model.NumSize);
			
			ValueBuffers ~= buff;
		}
		
		if(NeedSrcSynCode)
		{
			CircBufferStart = Model.Core.CreateBuffer(NumEventSources * Count * int.sizeof);
			CircBufferEnd = Model.Core.CreateBuffer(NumEventSources * Count * int.sizeof);
			CircBuffer = Model.Core.CreateBuffer(CircBufferSize * NumEventSources * Count * Model.NumSize);
		}
		
		DtBuffer = Model.Core.CreateBuffer(Count * Model.NumSize);
		ErrorBuffer = Model.Core.CreateBuffer((Count + 1) * int.sizeof);
		RecordFlagsBuffer = Model.Core.CreateBuffer(Count * int.sizeof);
		RecordBuffer = Model.Core.CreateBuffer(RecordLength * Model.NumSize * 4);
		RecordIdxBuffer = Model.Core.CreateBuffer(int.sizeof);
		
		if(NeedSrcSynCode)
		{
			DestSynBuffer = Model.Core.CreateBuffer(Count * NumEventSources * NumSrcSynapses * 2 * int.sizeof);
		}
		
		if(Model.SinglePrecision)
		{
			FloatOutput.length = RecordLength;
		}
		else
		{
			assert(0, "Unimplemented");
		}

		foreach(name, state; &type.AllConstants)
		{
			ConstantRegistry[name] = Constants.length;
			
			Constants ~= state.Value;
		}
		
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
			SetGlobalArg(arg_id++, &DtBuffer);
			SetGlobalArg(arg_id++, &ErrorBuffer);
			SetGlobalArg(arg_id++, &RecordFlagsBuffer);
			SetGlobalArg(arg_id++, &RecordIdxBuffer);
			SetGlobalArg(arg_id++, &RecordBuffer);
			foreach(buffer; ValueBuffers)
			{
				SetGlobalArg(arg_id++, &buffer.Buffer);
			}
			arg_id += Constants.length;
			if(NeedSrcSynCode)
			{
				/* Set the event source args */
				SetGlobalArg(arg_id++, &CircBufferStart);
				SetGlobalArg(arg_id++, &CircBufferEnd);
				SetGlobalArg(arg_id++, &CircBuffer);
			}
			if(NumDestSynapses)
			{
				SetGlobalArg(arg_id++, &Model.FiredSynIdxBuffer);
				SetGlobalArg(arg_id++, &Model.FiredSynBuffer);
			}
			SetGlobalArg(arg_id++, &Count);
		}
		
		/* Init kernel */
		InitKernel = new CCLKernel(&Model.Program, Name ~ "_init");
		with(InitKernel)
		{
			/* Nothing to skip, so set it at 0 */
			arg_id = 0;
			foreach(buffer; ValueBuffers)
			{
				SetGlobalArg(arg_id++, &buffer.Buffer);
			}
			arg_id += Constants.length;
			if(NeedSrcSynCode)
			{
				SetGlobalArg(arg_id++, &DestSynBuffer);
			}
			SetGlobalArg(arg_id++, &Count);
		}
		
		/* Deliver kernel */
		DeliverKernel = new CCLKernel(&Model.Program, Name ~ "_deliver");
		
		with(DeliverKernel)
		{
			/* Set the arguments. Start at 1 to skip the t argument*/
			arg_id = 1;
			SetGlobalArg(arg_id++, &ErrorBuffer);
			SetGlobalArg(arg_id++, &RecordIdxBuffer);
			if(NeedSrcSynCode)
			{
				/* Skip the fire table */
				arg_id++;
				/* Set the event source args */
				SetGlobalArg(arg_id++, &CircBufferStart);
				SetGlobalArg(arg_id++, &CircBufferEnd);
				SetGlobalArg(arg_id++, &CircBuffer);
				SetGlobalArg(arg_id++, &DestSynBuffer);
				SetGlobalArg(arg_id++, &Model.FiredSynIdxBuffer);
				SetGlobalArg(arg_id++, &Model.FiredSynBuffer);
			}
			SetGlobalArg(arg_id++, &Count);
		}
		
		Model.Core.Finish();
		
		Model.MemsetIntBuffer(RecordFlagsBuffer, Count, 0);
		Model.MemsetIntBuffer(DestSynBuffer, 2 * Count * NumSrcSynapses * NumEventSources, -1);
		
		ResetBuffers();
	}
	
	bool NeedSrcSynCode()
	{
		/* Don't need it if the model has no synapses to receive events, or the type
		 * of this neuron group has no event sources. Obviously we need src slots too */
		return Model.NumDestSynapses && NumEventSources && NumSrcSynapses;
	}
	
	void ResetBuffers()
	{
		/* Set the constants. Here because SetConstant sets it to both kernels, so both need
		 * to be created
		 */
		foreach(ii, _; Constants)
		{
			SetConstant(ii);
		}
		
		/* Initialize the buffers */
		Model.MemsetFloatBuffer(DtBuffer, Count, 0.001f);
		Model.MemsetIntBuffer(ErrorBuffer, Count + 1, 0);
		Model.MemsetIntBuffer(RecordIdxBuffer, 1, 0);
		
		if(NeedSrcSynCode)
		{
			Model.MemsetIntBuffer(CircBufferStart, Count * NumEventSources, -1);
			Model.MemsetIntBuffer(CircBufferEnd, Count * NumEventSources, 0);
		}
		
		/* Write the default values to the global buffers*/
		foreach(buffer; ValueBuffers)
		{
			WriteToBuffer(buffer);
		}
		Model.Core.Finish();
	}
	
	void SetConstant(int idx)
	{
		if(Model.SinglePrecision)
		{
			float val = Constants[idx];
			InitKernel.SetGlobalArg(idx + ValueBuffers.length + ArgOffsetInit, &val);
			StepKernel.SetGlobalArg(idx + ValueBuffers.length + ArgOffsetStep, &val);
		}
		else
		{
			double val = Constants[idx];
			InitKernel.SetGlobalArg(idx + ValueBuffers.length + ArgOffsetInit, &val);
			StepKernel.SetGlobalArg(idx + ValueBuffers.length + ArgOffsetStep, &val);
		}
	}
	
	void WriteToBuffer(SValueBuffer buffer)
	{
		Model.MemsetFloatBuffer(buffer.Buffer, Count, buffer.Value);
	}
	
	double ReadFromBuffer(SValueBuffer buffer, int idx)
	{
		if(Model.SinglePrecision)
		{
			float val;
			clEnqueueReadBuffer(Model.Core.Commands, buffer.Buffer, CL_TRUE, float.sizeof * idx, float.sizeof, &val, 0, null, null);
			return val;
		}
		else
		{
			double val;
			clEnqueueReadBuffer(Model.Core.Commands, buffer.Buffer, CL_TRUE, double.sizeof * idx, double.sizeof, &val, 0, null, null);
			return val;
		}
	}
	
	void CallInitKernel(size_t workgroup_size)
	{
		size_t total_num = (Count / workgroup_size) * workgroup_size;
		if(total_num < Count)
			total_num += workgroup_size;
		auto err = clEnqueueNDRangeKernel(Model.Core.Commands, InitKernel.Kernel, 1, null, &total_num, &workgroup_size, 0, null, null);
		assert(err == CL_SUCCESS);
	}
	
	void CallStepKernel(double t, size_t workgroup_size)
	{
		size_t total_num = (Count / workgroup_size) * workgroup_size;
		if(total_num < Count)
			total_num += workgroup_size;
		
		with(StepKernel)
		{
			if(Model.SinglePrecision)
			{
				float t_val = t;
				SetGlobalArg(0, &t_val);
			}
			else
			{
				double t_val = t;
				SetGlobalArg(0, &t_val);
			}

			auto err = clEnqueueNDRangeKernel(Model.Core.Commands, Kernel, 1, null, &total_num, &workgroup_size, 0, null, null);
			assert(err == CL_SUCCESS);
		}
	}
	
	void CallDeliverKernel(double t, size_t workgroup_size)
	{
		size_t total_num = (Count / workgroup_size) * workgroup_size;
		if(total_num < Count)
			total_num += workgroup_size;
		
		with(DeliverKernel)
		{
			if(Model.SinglePrecision)
			{
				float t_val = t;
				SetGlobalArg(0, &t_val);
			}
			else
			{
				double t_val = t;
				SetGlobalArg(0, &t_val);
			}
			
			if(NeedSrcSynCode)
			{
				/* Local fire table */
				SetLocalArg(ArgOffsetDeliver, int.sizeof * workgroup_size * NumEventSources);
			}

			auto err = clEnqueueNDRangeKernel(Model.Core.Commands, Kernel, 1, null, &total_num, &workgroup_size, 0, null, null);
			assert(err == CL_SUCCESS);
		}
	}
	
	void CreateStepKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto kernel_source = StepKernelTemplate.dup;
		
		auto eval_source = type.GetEvalSource();
		
		void apply(char[] dest)
		{
			if(source.Source.length)
				source.Retreat(1); /* Chomp the newline */
			kernel_source = kernel_source.substitute(dest, source.toString);
			source.Clear();
		}
		
		kernel_source = kernel_source.substitute("$type_name$", Name);
		
		/* Value arguments */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "__global $num_type$* " ~ name ~ "_buf,";
		}
		apply("$val_args$");
		
		/* Constant arguments */
		source.Tab(2);
		foreach(name, state; &type.AllConstants)
		{
			source ~= "const $num_type$ " ~ name ~ ",";
		}
		apply("$constant_args$");
		
		/* Event source args */
		source.Tab(2);
		if(NeedSrcSynCode)
		{
			source ~= "__global int* circ_buffer_start,";
			source ~= "__global int* circ_buffer_end,";
			source ~= "__global $num_type$* circ_buffer,";
		}
		apply("$event_source_args$");
		
		/* Synapse args */
		source.Tab(2);
		if(NumDestSynapses)
		{
			source ~= "__global int* fired_syn_idx_buffer,";
			source ~= "__global int* fired_syn_buffer,";
		}
		apply("$synapse_args$");
		
		/* Load vals */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "$num_type$ " ~ name ~ " = " ~ name ~ "_buf[i];";
		}
		apply("$load_vals$");
		
		/* Synapse code */
		source.Tab(2);
		if(NumDestSynapses)
		{
			source.AddBlock(
"
int syn_table_end = fired_syn_idx_buffer[i + $nrn_offset$];
if(syn_table_end != $syn_offset$)
{
	for(int syn_table_idx = $syn_offset$; syn_table_idx < syn_table_end; syn_table_idx++)
	{
		int syn_i = fired_syn_buffer[syn_table_idx];
");
			source.Tab(2);
			int syn_offset = 0;
			foreach(ii, syn_type; type.SynapseTypes)
			{
				syn_offset += syn_type.NumSynapses;
				char[] cond;
				if(ii != 0)
					cond ~= "else ";
				cond ~= "if(syn_i < " ~ to!(char[])(syn_offset) ~ ")";
				source ~= cond;
				source ~= "{";
				source.Tab();
				
				auto syn_code = syn_type.Synapse.SynCode;
				auto prefix = syn_type.Prefix;
				if(syn_type.Prefix != "")
				{
					foreach(val; &syn_type.Synapse.AllValues)
					{
						syn_code = syn_code.c_substitute(val.Name, prefix ~ "_" ~ val.Name);
					}
				}
				source.AddBlock(syn_code);
				
				source.DeTab();
				source ~= "}";
			}
			source.DeTab(2);
			source.AddBlock(
"	}
	dt = 0.001f;
	fired_syn_idx_buffer[i + $nrn_offset$] = $syn_offset$;
}");
			source.Source = source.Source.substitute("$nrn_offset$", to!(char[])(NrnOffset));
			source.Source = source.Source.substitute("$syn_offset$", to!(char[])(SynOffset));
			source.DeTab(2);
		}
		apply("$synapse_code$");
		
		/* Record vals */
		source.Tab(5);
		/* The indices are offset by 1, so that 0 can be used as a special
		 * index indicating that nothing is to be recorded*/
		int idx = 1; 
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "case " ~ to!(char[])(idx) ~ ":";
			source.Tab;
			source ~= "record.s2 = " ~ name ~ ";";
			source.DeTab;
			source ~= "break;";
			idx++;
		}
		apply("$record_vals$");
		
		/* Declare locals */
		source.Tab(3);
		foreach(name, state; &type.AllLocals)
		{
			source ~= "$num_type$ " ~ name ~ ";";
		}
		apply("$declare_locals$");
		
		/* Declare temp states */
		source.Tab(3);
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ " ~ name ~ "_0 = " ~ name ~ ";";
		}
		apply("$declare_temp_states$");
		
		/* Declare derivs 1 */
		source.Tab(3);
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ d" ~ name ~ "_dt_1;";
		}
		apply("$declare_derivs_1$");
		
		/* Declare derivs 2 */
		source.Tab(3);
		foreach(name, state; &type.AllStates)
		{
			source ~= "$num_type$ d" ~ name ~ "_dt_2;";
		}
		apply("$declare_derivs_2$");
		
		/* Compute derivs 1 */
		auto first_source = eval_source.dup;
		foreach(name, state; &type.AllStates)
		{
			first_source = first_source.c_substitute(name ~ "'", "d" ~ name ~ "_dt_1");
		}
		source.Tab(3);
		source.AddBlock(first_source);
		apply("$compute_derivs_1$");
		
		/* Apply derivs 1 */
		source.Tab(3);
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " += dt * d" ~ name ~ "_dt_1;";
		}
		apply("$apply_derivs_1$");
		
		/* Compute derivs 2 */
		auto second_source = eval_source.dup;
		foreach(name, state; &type.AllStates)
		{
			second_source = second_source.c_substitute(name ~ "'", "d" ~ name ~ "_dt_2");
		}
		source.Tab(3);
		source.AddBlock(second_source);
		apply("$compute_derivs_2$");
		
		/* Apply derivs 2 */
		source.Tab(3);
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ "_0 += dt / 2 * (d" ~ name ~ "_dt_1 + d" ~ name ~ "_dt_2);";
		}
		apply("$apply_derivs_2$");
		
		/* Compute error */
		source.Tab(3);
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " -= " ~ name ~ "_0;";
			source ~= "error += " ~ name ~ " * " ~ name ~ ";";
		}
		apply("$compute_error$");
		
		/* Reset state */
		source.Tab(3);
		foreach(name, state; &type.AllStates)
		{
			source ~= name ~ " = " ~ name ~ "_0;";
		}
		apply("$reset_state$");
		
		/* Thresholds */
		source.Tab(3);
		int thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			source ~= "if(" ~ thresh.State ~ " " ~ thresh.Condition ~ ")";
			source ~= "{";
			source.Tab;
			
			if(NeedSrcSynCode && thresh.IsEventSource)
				source ~= "$num_type$ delay = " ~ to!(char[])(thresh.EventDelay) ~ ";";
			source.AddBlock(thresh.Source);
			source ~= "dt = 0.001f;";
			
			if(NeedSrcSynCode && thresh.IsEventSource)
			{
				char[] src = 
"int idx_idx = " ~ to!(char)(NumEventSources) ~ " * i + " ~ to!(char)(thresh_idx) ~ ";
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
	int buff_idx = (i * " ~ to!(char)(NumEventSources) ~ " + " ~ to!(char)(thresh_idx) ~ ") * circ_buffer_size + end_idx - 1;

	circ_buffer[buff_idx] = t + cur_time + delay;
}
else //It is full, error
{
	error_buffer[i + 1] = 6;
}
".dup;
				src = src.substitute("$circ_buffer_size$", to!(char[])(CircBufferSize));
				
				source.AddBlock(src);
				
				thresh_idx++;
/* TODO: Better error reporting */
/* TODO: Check that the darn thing works */
			}
			
			source.DeTab;
			source ~= "}";
		}
		apply("$thresholds$");
		
		/* Save values */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= name ~ "_buf[i] = " ~ name ~ ";";
		}
		apply("$save_vals$");
		
		StepKernelSource = kernel_source;
	}
	
	void CreateDeliverKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto kernel_source = DeliverKernelTemplate.dup;
		
		void apply(char[] dest)
		{
			if(source.Source.length)
				source.Retreat(1); /* Chomp the newline */
			kernel_source = kernel_source.substitute(dest, source.toString);
			source.Clear();
		}
		
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
		apply("$event_source_args$");
		
		/* Thresholds */
		source.Tab(2);
		int thresh_idx = 0;
		foreach(thresh; &type.AllThresholds)
		{
			if(Model.NumDestSynapses && thresh.IsEventSource)
			{
				source ~= "{";
				source.Tab;
			
				char[] src = "
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
		fire_table[$num_event_sources$ * local_id + $event_source_idx$] = $num_event_sources$ * i + $event_source_idx$;
		need_to_deliver = true;
#else
		int syn_start = num_synapses * idx_idx;
		for(int syn_id = 0; syn_id < num_synapses; syn_id++)
		{
			int2 dest = dest_syn_buffer[syn_id + syn_start];
			if(dest.s0 >= 0)
			{
				/* Get the index into the global syn buffer */
				int dest_syn = atom_inc(&fired_syn_idx_buffer[dest.s0]);
				
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
".dup;
				src = src.substitute("$num_event_sources$", to!(char[])(NumEventSources));
				src = src.substitute("$event_source_idx$", to!(char[])(thresh_idx));
				src = src.substitute("$circ_buffer_size$", to!(char[])(CircBufferSize));
				
				source.AddBlock(src);
				source.DeTab;
				source ~= "}";
				thresh_idx++;
			}
		}
		apply("$event_source_code$");
		
		kernel_source = kernel_source.substitute("$num_synapses$", to!(char[])(NumSrcSynapses));
		
		DeliverKernelSource = kernel_source;
	}
	
	void CreateInitKernel(CNeuronType type)
	{
		scope source = new CSourceConstructor;
		
		auto init_source = type.GetInitSource();
		
		auto kernel_source = InitKernelTemplate.dup;
		
		void apply(char[] dest)
		{
			if(source.Source.length)
				source.Retreat(1); /* Chomp the newline */
			kernel_source = kernel_source.substitute(dest, source.toString);
			source.Clear();
		}
		
		kernel_source = kernel_source.substitute("$type_name$", Name);
		
		/* Value arguments */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "__global $num_type$* " ~ name ~ "_buf,";
		}
		apply("$val_args$");
		
		/* Constant arguments */
		source.Tab(2);
		foreach(name, state; &type.AllConstants)
		{
			source ~= "const $num_type$ " ~ name ~ ",";
		}
		apply("$constant_args$");
		
		source.Tab(2);
		if(NeedSrcSynCode)
		{
			source ~= "__global int2* dest_syn_buffer,";
		}
		apply("$event_source_args$");
		
		/* Load vals */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= "$num_type$ " ~ name ~ " = " ~ name ~ "_buf[i];";
		}
		apply("$load_vals$");
		
		/* Perform initialization */
		source.Tab(2);
		source.AddBlock(init_source);
		apply("$init_vals$");
		
		/* Save values */
		source.Tab(2);
		foreach(name, state; &type.AllNonLocals)
		{
			source ~= name ~ "_buf[i] = " ~ name ~ ";";
		}
		apply("$save_vals$");
		
		InitKernelSource = kernel_source;
	}
	
	/* These two functions can be used to modify values after the model has been created.
	 */
	double opIndex(char[] name, int idx = -1)
	{
		assert(idx < Count, "idx needs to be less than Count.");
		
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			return Constants[*idx_ptr];
		}
		
		idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr !is null)
		{
			if(Model.Generated && idx > 0)
			{
				auto val = ReadFromBuffer(ValueBuffers[*idx_ptr], idx);
				Model.Core.Finish();
				return val;
			}
			else
			{
				return ValueBuffers[*idx_ptr].Value;
			}
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	double opIndexAssign(double val, char[] name)
	{
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			Constants[*idx_ptr] = val;
			if(Model.Generated)
				SetConstant(*idx_ptr);
			return val;
		}
		
		idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr !is null)
		{
			ValueBuffers[*idx_ptr].Value = val;
			if(Model.Generated)
			{
				WriteToBuffer(ValueBuffers[*idx_ptr]);
				Model.Core.Finish();
			}
			return val;
		}
		
		throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	void Shutdown()
	{
		foreach(buffer; ValueBuffers)
			clReleaseMemObject(buffer.Buffer);

		clReleaseMemObject(DtBuffer);
	}
	
	void UpdateRecorders()
	{
		if(Recorders.length)
		{
			int num_written;
			clEnqueueReadBuffer(Model.Core.Commands, RecordIdxBuffer, CL_TRUE, 0, int.sizeof, &num_written, 0, null, null);
			if(Model.SinglePrecision)
			{
				FloatOutput.length = num_written;
				clEnqueueReadBuffer(Model.Core.Commands, RecordBuffer, CL_TRUE, 0, num_written * cl_float4.sizeof, FloatOutput.ptr, 0, null, null);
				//Stdout.formatln("num_written: {}", num_written);
				foreach(quad; FloatOutput)
				{
					int id = cast(int)quad[0];
					//Stdout.formatln("{:5} {:5} {:5} {}", quad[0], quad[1], quad[2], quad[3]);
					Recorders[id].AddDatapoint(quad[1], quad[2]);
				}
			}
			else
			{
				assert(0, "Unimplemented");
			}
		}
	}
	
	CRecorder Record(int neuron_id, char[] name)
	{
		assert(neuron_id >= 0);
		assert(neuron_id < Count);
		auto idx_ptr = name in ValueBufferRegistry;
		if(idx_ptr is null)
			throw new Exception("Neuron group '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
		
		/* Offset the index by 1 */
		Model.SetInt(RecordFlagsBuffer, neuron_id, 1 + *idx_ptr);
		
		auto rec = new CRecorder(neuron_id, name);
		Recorders[neuron_id] = rec;
		return rec;
	}
	
	void StopRecording(int neuron_id)
	{
		assert(neuron_id >= 0);
		assert(neuron_id < Count);
		auto idx_ptr = neuron_id in Recorders;
		if(idx_ptr !is null)
		{
			idx_ptr.Detach();
			Recorders.remove(neuron_id);
			Model.SetInt(RecordFlagsBuffer, neuron_id, 0);
		}
	}
	
	void CheckErrors()
	{
		auto errors = new int[](Count + 1);
		clEnqueueReadBuffer(Model.Core.Commands, ErrorBuffer, CL_TRUE, 0, (Count + 1) * int.sizeof, errors.ptr, 0, null, null);
		if(errors[0])
		{
			Stdout.formatln("Error: {}", errors[0]);
		}
		foreach(ii, error; errors[1..$])
		{
			if(error)
			{
				Stdout.formatln("Error: {} : {}", ii, error);
			}
		}
	}
	
	void ConnectTo(int src_nrn_id, int event_source, int src_slot, int dest_neuron_id, int dest_slot)
	{
		assert(Model.Generated);
		assert(src_nrn_id >= 0 && src_nrn_id < Count);
		assert(event_source >= 0 && event_source < NumEventSources);
		assert(src_slot >= 0 && src_slot < NumSrcSynapses);
		
		int dest_syn_id = (src_nrn_id * NumEventSources + event_source) * NumSrcSynapses + src_slot;
		
		Model.SetInt(DestSynBuffer, dest_syn_id * 2 + 0, dest_neuron_id);
		Model.SetInt(DestSynBuffer, dest_syn_id * 2 + 1, dest_slot);
	}
	
	SAlignedArray!(cl_float4, cl_float4.sizeof) FloatOutput;
	//SAlignedArray!(cl_double4, cl_double4.sizeof) DoubleOutput;
	
	CRecorder[int] Recorders;
	
	double[] Constants;
	int[char[]] ConstantRegistry;
	
	SValueBuffer[] ValueBuffers;
	int[char[]] ValueBufferRegistry;
	
	char[] Name;
	int Count = 0;
	CCLModel Model;
	
	char[] StepKernelSource;
	char[] InitKernelSource;
	char[] DeliverKernelSource;
	
	CCLKernel InitKernel;
	CCLKernel StepKernel;
	CCLKernel DeliverKernel;
	
	cl_mem DtBuffer;
	cl_mem CircBufferStart;
	cl_mem CircBufferEnd;
	cl_mem CircBuffer;
	cl_mem ErrorBuffer;
	cl_mem RecordFlagsBuffer;
	cl_mem RecordBuffer;
	cl_mem RecordIdxBuffer;
	cl_mem DestSynBuffer;
	
	int RecordLength;
	int CircBufferSize = 20;
	int NumEventSources = 0;
	
	int NumSrcSynapses; /* Number of pre-synaptic slots per event source */
	int NumDestSynapses; /* Number of post-synaptic slots (total) */
	
	/* The place we reset the fired syn idx to*/
	int SynOffset;
	/* Offset for indexing into the model global indices */
	int NrnOffset;
}

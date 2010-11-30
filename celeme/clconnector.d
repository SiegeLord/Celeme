module celeme.clconnector;

import celeme.frontend;
import celeme.util;
import celeme.clcore;
import celeme.clneurongroup;
import celeme.sourceconstructor;

import opencl.cl;

import tango.text.Util;
import tango.util.Convert;
import tango.io.Stdout;

const ConnectorTemplate = 
`
void $connector_name$_connect_impl
	(
		int src_event_source, 
		int src_slot_max, 
		__global int* event_source_idxs, 
		int dest_slot_max,
		__global int* dest_syn_idxs,
		__global int2* dest_syn_buffer,
		__global int* error_buffer,
		int dest_nrn_offset,
		int dest_slot_offset,
		int src_nrn_id, 
		int dest_nrn_id
	)
{
	int src_slot = atomic_inc(&event_source_idxs[src_nrn_id]);
	int dest_slot = atomic_inc(&dest_syn_idxs[dest_nrn_id]);
	
	if(src_slot >= src_slot_max || dest_slot >= dest_slot_max)
	{
		error_buffer[src_nrn_id + 1] = 99;
		return;
	}
	
	int src_syn_id = (src_nrn_id * $num_event_sources$ + src_event_source) * src_slot_max + src_slot;
	
	dest_syn_buffer[src_syn_id].s0 = dest_nrn_offset + dest_nrn_id;
	dest_syn_buffer[src_syn_id].s1 = dest_slot + dest_slot_offset;
}

__kernel void $connector_name$_connect
	(
$connector_args$
$random_state_args$
		const int src_start,
		const int src_end,
		const int src_event_source,
		const int src_slot_max,
		__global int* event_source_idxs,
		const int dest_start,
		const int dest_end,
		const int dest_slot_max,
		__global int* dest_syn_idxs,
		__global int2* dest_syn_buffer,
		int dest_nrn_offset,
		int dest_slot_offset,
		__global int* error_buffer
	)
{
	int gid = get_global_id(0);
	int i = src_start + gid % (src_end - src_start);
	int cycle = gid / (src_end - src_start);

	/* Load random state */
$load_rand_state$
	/* Connector code */
$connector_code$
	/* Save random state */
$save_rand_state$
}
`; 

class CCLConnector(float_t)
{
	this(CNeuronGroup!(float_t) group, CConnector conn)
	{
		Group = group;
		Name = conn.Name;
		
		foreach(val; conn.Constants)
		{
			ConstantRegistry[val.Name] = Constants.length;
			
			Constants ~= val.Value;
		}
		
		CreateKernel(conn);
	}
	
	void Initialize()
	{
		ConnectKernel = new CCLKernel(Group.Program, Group.Name ~ "_" ~ Name ~ "_connect");
	}
	
	void CreateKernel(CConnector conn)
	{
		scope source = new CSourceConstructor;
		
		auto kernel_source = ConnectorTemplate.dup;		
		
		auto code = conn.Code.dup;
		code = code.substitute("connect(", "$connector_name$_connect_impl(src_event_source, src_slot_max, event_source_idxs, dest_slot_max, dest_syn_idxs, dest_syn_buffer, error_buffer, dest_nrn_offset, dest_slot_offset, ");
		
		if(kernel_source.containsPattern("rand()"))
		{
			if(!Group.RandLen)
				throw new Exception("Found rand() but neuron type does not have random_state_len > 0.");
			kernel_source = kernel_source.substitute("rand()", "rand" ~ to!(char[])(Group.RandLen) ~ "(&rand_state)");
			
			NeedRand = true;
		}
		
		/* Connector args */
		source.Tab(2);
		foreach(val; conn.Constants)
		{
			source ~= "const $num_type$ " ~ val.Name ~ ",";
		}
		source.Inject(kernel_source, "$connector_args$");
		
		/* Random state arguments */
		source.Tab(2);
		if(NeedRand)
			source.AddBlock(Group.Rand.GetArgsCode());
		source.Inject(kernel_source, "$random_state_args$");
		
		/* Load rand state */
		source.Tab(1);
		if(NeedRand)
			source ~= Group.Rand.GetLoadCode();
		source.Inject(kernel_source, "$load_rand_state$");
		
		/* Connector code */
		source.Tab(1);
		source.AddBlock(code);
		source.Inject(kernel_source, "$connector_code$");
		
		/* Save rand state */
		source.Tab(1);
		if(NeedRand)
			source ~= Group.Rand.GetSaveCode();
		source.Inject(kernel_source, "$save_rand_state$");
		
		kernel_source = kernel_source.substitute("$connector_name$", Group.Name ~ "_" ~ Name);
		kernel_source = kernel_source.substitute("$num_event_sources$", to!(char[])(Group.NumEventSources));
			
		KernelCode = kernel_source;
	}
	
	void Connect(int multiplier, int[2] src_nrn_range, int src_event_source, CNeuronGroup!(float_t) dest, int[2] dest_nrn_range, int dest_syn_type)
	{
		int arg_id = 0;
		
		with(ConnectKernel)
		{
			//$connector_args$
			foreach(cnst; Constants)
			{
				float_t val = cnst;
				SetGlobalArg(arg_id++, &val);
			}
			
			//$random_state_args$
			if(NeedRand)
			{
				arg_id = Group.Rand.SetArgs(ConnectKernel, arg_id);
			}
			//const int src_start,
			SetGlobalArg(arg_id++, &src_nrn_range[0]);
			//const int src_end,
			SetGlobalArg(arg_id++, &src_nrn_range[1]);
			//const int src_event_source,
			SetGlobalArg(arg_id++, &src_event_source);
			//const int src_slot_max,
			SetGlobalArg(arg_id++, &Group.NumSrcSynapses);
			//__global int* event_source_idxs,
			SetGlobalArg(arg_id++, &Group.EventSourceBuffers[src_event_source].FreeIdx.Buffer);
			//const int dest_start,
			SetGlobalArg(arg_id++, &dest_nrn_range[0]);
			//const int dest_end,
			SetGlobalArg(arg_id++, &dest_nrn_range[1]);
			//const int dest_slot_max,
			SetGlobalArg(arg_id++, &dest.SynapseBuffers[dest_syn_type].Count);
			//__global int* dest_syn_idxs,
			SetGlobalArg(arg_id++, &dest.SynapseBuffers[dest_syn_type].FreeIdx.Buffer);
			//__global int2* dest_syn_buffer,
			SetGlobalArg(arg_id++, &Group.DestSynBuffer.Buffer);
			//int dest_nrn_offset,
			SetGlobalArg(arg_id++, &dest.NrnOffset);
			//int dest_slot_offset,
			SetGlobalArg(arg_id++, &dest.SynapseBuffers[dest_syn_type].SlotOffset);
			//__global int* error_buffer
			SetGlobalArg(arg_id++, &Group.ErrorBuffer);
		}
		
		assert(src_nrn_range[1] > src_nrn_range[0]);
		assert(multiplier > 0);
		
		size_t total_num = multiplier * (src_nrn_range[1] - src_nrn_range[0]);
		
		auto err = clEnqueueNDRangeKernel(Group.Core.Commands, ConnectKernel.Kernel, 1, null, &total_num, null, 0, null, null);
		assert(err == CL_SUCCESS);
	}
	
	double opIndex(char[] name)
	{
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			return Constants[*idx_ptr];
		}
		
		throw new Exception("Connector '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	double opIndexAssign(double val, char[] name)
	{	
		auto idx_ptr = name in ConstantRegistry;
		if(idx_ptr !is null)
		{
			Constants[*idx_ptr] = val;
			return val;
		}
		
		throw new Exception("Connector '" ~ Name ~ "' does not have a '" ~ name ~ "' variable.");
	}
	
	int ArgStart()
	{
		auto ret = Constants.length;
		if(Group.RandLen)
			ret += Group.Rand.NumArgs;
		return ret;
	}
	
	void Shutdown()
	{
		ConnectKernel.Release();
	}
	
	char[] Name;
	double[] Constants;
	int[char[]] ConstantRegistry;
	bool NeedRand = false;
	
	char[] KernelCode;
	CNeuronGroup!(float_t) Group;
	
	CCLKernel ConnectKernel;
}

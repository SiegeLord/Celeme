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

module celeme.internal.clconnector;

import celeme.internal.frontend;
import celeme.internal.util;
import celeme.internal.clcore;
import celeme.internal.iclneurongroup;
import celeme.internal.sourceconstructor;

import opencl.cl;

import tango.text.Util;
import tango.util.Convert;
import tango.io.Stdout;

const ConnectorTemplate = 
`
void $connector_name$_connect_impl
	(
		int _src_event_source, 
		int* src_slot,
		int _src_slot_max,
		int _dest_slot_max,
		__global int* _dest_syn_idxs,
		__global int2* _dest_syn_buffer,
		__global int* _error_buffer,
		int _dest_nrn_offset,
		int _dest_slot_offset,
		int src_nrn_id, 
		int dest_nrn_id
	)
{
	int dest_slot = atomic_inc(&_dest_syn_idxs[dest_nrn_id]);
	
	if(*src_slot >= _src_slot_max || dest_slot >= _dest_slot_max)
	{
		_error_buffer[src_nrn_id + 1] = 99;
		return;
	}
	
	int src_syn_id = (src_nrn_id * $num_event_sources$ + _src_event_source) * _src_slot_max + *src_slot;
	
	_dest_syn_buffer[src_syn_id].s0 = _dest_nrn_offset + dest_nrn_id;
	_dest_syn_buffer[src_syn_id].s1 = dest_slot + _dest_slot_offset;
	
	(*src_slot)++;
}

__kernel void $connector_name$_connect
	(
$connector_args$
$random_state_args$
		const int num_cycles,
		const int src_start,
		const int src_end,
		const int _src_event_source,
		const int _src_slot_max,
		__global int* _event_source_idxs,
		const int dest_start,
		const int dest_end,
		const int _dest_slot_max,
		__global int* _dest_syn_idxs,
		__global int2* _dest_syn_buffer,
		int _dest_nrn_offset,
		int _dest_slot_offset,
		__global int* _error_buffer
	)
{
	int i = src_start + get_global_id(0);
	int src_slot = _event_source_idxs[i];
	
	/* Load random state */
$load_rand_state$
	for(int cycle = 0; cycle < num_cycles; cycle++)
	{
	/* Connector code */
$connector_code$
	}
	
	_event_source_idxs[i] = src_slot;
	/* Save random state */
$save_rand_state$
}
`; 

class CCLConnector(float_t)
{
	this(ICLNeuronGroup group, CConnector conn)
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
		ConnectKernel = Group.Core.CreateKernel(Group.Program, Group.Name ~ "_" ~ Name ~ "_connect");
	}
	
	void CreateKernel(CConnector conn)
	{
		scope source = new CSourceConstructor;
		
		auto kernel_source = ConnectorTemplate.dup;		
		
		auto code = conn.Code.dup;
		code = code.substitute("connect(", "$connector_name$_connect_impl(_src_event_source, &src_slot, _src_slot_max, _dest_slot_max, _dest_syn_idxs, _dest_syn_buffer, _error_buffer, _dest_nrn_offset, _dest_slot_offset, ");
		
		if(code.containsPattern("rand()"))
		{
			if(!Group.RandLen)
				throw new Exception("Found rand() but neuron group '" ~ Group.Name ~ "' does not have random_state_len > 0.");
			code = code.substitute("rand()", "rand" ~ to!(char[])(Group.RandLen) ~ "(&_rand_state)");
			
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
		source.Tab(2);
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
	
	void Connect(int num_cycles, int[2] src_nrn_range, int src_event_source, ICLNeuronGroup dest, int[2] dest_nrn_range, int dest_syn_type)
	{
		assert(src_nrn_range[1] > src_nrn_range[0]);
		assert(num_cycles > 0);
		
		int arg_id = 0;
		
		with(ConnectKernel)
		{
			//$connector_args$
			foreach(cnst; Constants)
			{
				float_t val = cnst;
				SetGlobalArg(arg_id++, val);
			}
			
			//$random_state_args$
			if(NeedRand)
			{
				arg_id = Group.Rand.SetArgs(ConnectKernel, arg_id);
			}
			//const int num_cycles,
			SetGlobalArg(arg_id++, num_cycles);
			//const int src_start,
			SetGlobalArg(arg_id++, src_nrn_range[0]);
			//const int src_end,
			SetGlobalArg(arg_id++, src_nrn_range[1]);
			//const int _src_event_source,
			SetGlobalArg(arg_id++, src_event_source);
			//const int _src_slot_max,
			auto num_src_synapses = Group.NumSrcSynapses;
			SetGlobalArg(arg_id++, num_src_synapses);
			//__global int* _event_source_idxs,
			SetGlobalArg(arg_id++, Group.EventSourceBuffers[src_event_source].FreeIdx.Buffer);
			//const int dest_start,
			SetGlobalArg(arg_id++, dest_nrn_range[0]);
			//const int dest_end,
			SetGlobalArg(arg_id++, dest_nrn_range[1]);
			//const int _dest_slot_max,
			SetGlobalArg(arg_id++, dest.SynapseBuffers[dest_syn_type].Count);
			//__global int* _dest_syn_idxs,
			SetGlobalArg(arg_id++, dest.SynapseBuffers[dest_syn_type].FreeIdx.Buffer);
			//__global int2* _dest_syn_buffer,
			SetGlobalArg(arg_id++, Group.DestSynBuffer.Buffer);
			//int _dest_nrn_offset,
			SetGlobalArg(arg_id++, dest.NrnOffset);
			//int _dest_slot_offset,
			SetGlobalArg(arg_id++, dest.SynapseBuffers[dest_syn_type].SlotOffset);
			//__global int* _error_buffer
			auto error_buffer = Group.ErrorBuffer;
			SetGlobalArg(arg_id++, error_buffer);
		}
		
		ConnectKernel.Launch([src_nrn_range[1] - src_nrn_range[0]]);
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
	ICLNeuronGroup Group;
	
	CCLKernel ConnectKernel;
}

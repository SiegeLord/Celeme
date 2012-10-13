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

/**
 * This module allows the loading of a model definition (including connectors,
 * neuron types, mechanisms and synapses) from a configuration file.
 */

module celeme.configloader;

import celeme.internal.util;
import celeme.internal.frontend;
import celeme.imodel;
import celeme.internal.clmodel;
import celeme.platform_flags;

import slconfig;

import tango.text.convert.Format;

void FillMechanism(CMechanism mech, SNode mech_node)
{
	foreach(ii; range(3))
	{
		auto stage_name = Format("stage{}", ii);
		auto stage_code = mech_node[stage_name].GetValue!(const(char)[])(null);
			//println("{}: {}", stage_name, stage_code);
		mech.SetStage(ii, cast(cstring)mech_node[stage_name]);
	}
	
	mech.InitCode = cast(cstring)mech_node.init_code;
	mech.PreStageCode = cast(cstring)mech_node.pre_stage;
	mech.PreStepCode = cast(cstring)mech_node.pre_step;
	
	foreach(node; mech_node)
	{
		switch(node.Type)
		{
			case "state":
			{
				auto val = mech.AddState(node.Name);
				if(node.IsAggregate)
					val = node["init"].GetValue(0.0);
				else
					val = node.GetValue(0.0);
				
				//println("State: {} = {}", val.Name, val.Value);
				break;
			}
			case "global":
			{
				auto val = mech.AddGlobal(node.Name);
				if(node.IsAggregate)
				{
					val = node["init"].GetValue(0.0);
					val.ReadOnly = node.read_only.GetValue(false);
				}
				else
				{
					val = node.GetValue(0.0);
				}
				
				//println("Global: {} = {} read_only: {}", val.Name, val.Value, val.ReadOnly);
				break;
			}
			case "local":
			{
				auto val = mech.AddLocal(node.Name);
				//println("Local: {}", val.Name);
				break;
			}
			case "constant":
			{
				auto val = mech.AddConstant(node.Name);
				if(node.IsAggregate)
					val = node["init"].GetValue(0.0);
				else
					val = node.GetValue(0.0);
				
				val.ReadOnly = true;
				
				//println("Constant: {} = {}", val.Name, val.Value);
				break;
			}
			case "immutable":
			{
				auto val = mech.AddImmutable(node.Name);
				if(node.IsAggregate)
					val = node["init"].GetValue(0.0);
				else
					val = node.GetValue(0.0);
				
				val.ReadOnly = true;
				
				//println("Immutable: {} = {}", val.Name, val.Value);
				break;
			}
			case "external":
			{
				mech.AddExternal(node.Name);
				//println("External: {}", node.Name);
				break;
			}
			case "threshold":
			{
				auto state = node.state.GetValue!(cstring)(null);
				if(state == "")
					throw new Exception("All thresholds need a state.");
					
				auto condition = node.condition.GetValue!(cstring)(null);
				if(condition == "")
					throw new Exception("All thresholds need a condition.");

				auto code = cast(cstring)node.code;
				
				auto is_event_source = node.event_source.GetValue(false);
				auto reset_dt = node.reset_dt.GetValue(false);
				
				mech.AddThreshold(state, condition, code, is_event_source, reset_dt);
				
				//println("Thresh: {} {} -> {} \n Events: {} Reset: {}", state, condition, code, is_event_source, reset_dt);
				break;
			}
			default:
				break;
		}
	}
}

/**
 * Load mechanisms from a root config node.
 * 
 * Returns:
 *     An associative array of mechanisms.
 * 
 * A mechanism node looks like this:
 * 
 * ---
 * mechanism MechName
 * {
 *     // Staged evaluation of the derivatives. Duplicate nodes will be combined together.
 *     stage0 = "";
 *     stage1 = "";
 *     stage2 = "";
 *     
 *     // Init code. Duplicate nodes will be combined together.
 *     init_code = "";
 *     
 *     // Code run before any integration is performed. Duplicate nodes will be combined together.
 *     pre_step = "";
 * 
 *     // Code run before an integration step (by dt) is performed. Duplicate nodes will be combined together.
 *     pre_stage = "";
 *     
 *     // States
 *     // To specify the tolerance for a state, add a global/constant/immutable value that has a _tol suffix
 *     state StateName
 *     {
 *         // Initial value
 *         init = 0;
 *     }
 *     // Alternate syntax, the init is set to the assigned value
 *     state StateName2 = 0;
 *     
 *     // Globals
 *     global GlobalName
 *     {
 *         // Initial value
 *         init = 0;
 *         // Whether the global is read only or not
 *         read_only = false;
 *     }
 *     // Alternate syntax, the init is set to the assigned value
 *     global GlobalName2 = 0;
 *     
 *     // Locals
 *     local LocalName;
 *     
 *     // Constants
 *     constant ConstantName
 *     {
 *         init = 0;
 *     }
 *     // Alternate syntax, the init is set to the assigned value
 *     constant ConstantName2 = 0;
 * 
 *     // Immutables
 *     immutable ImmutableName;
 *     
 *     // Externals
 *     external ExternName;
 *     
 *     // Thresholds
 *     threshold ThreshName
 *     {
 *         // State to track. Mandatory parameter.
 *         state SomeState;
 *         
 *         // Condition to use as threshold. Mandatory parameter.
 *         condition "> 0";
 *         
 *         // Code ran when the threshold is activated. Duplicate nodes will be combined together.
 *         code = "";
 *         
 *         // Specifies whether this is an event source or not
 *         event_source = false;
 *         
 *         // Specifies whether to reset the dt or not when the threshold is activated
 *         reset_dt = false;
 *     }
 * }
 * ---
 */
CMechanism[char[]] LoadMechanisms(SNode root)
{
	CMechanism[char[]] ret;
	
	foreach(node; root)
	{
		if(node.Type == "mechanism")
		{
			if(!node.IsAggregate)
				throw new Exception("mechanism is supposed to be an aggregate.");

			if((node.Name in ret) !is null)
				throw new Exception("Duplicate mechanism name: '" ~ node.Name.idup ~ "'.");
				
			auto mech = new CMechanism(node.Name);
			ret[node.Name.idup] = mech;
			
			FillMechanism(mech, node);
				
			//println("Mechanism: {}", node.Name);
		}
	}
	
	return ret;
}

/**
 * Load synapses from a root config node.
 * 
 * Returns:
 *     An associative array of synapses.
 * 
 * A mechanism node looks just like a mechanism node, except it has more fields:
 * 
 * ---
 * synapse SynapseName
 * {
 *     // Code to be ran when the synapse is triggered. Duplicate nodes will be combined together.
 *     syn_code = "";
 *     
 *     // Syn globals
 *     syn_global SynGlobalName
 *     {
 *         // Initial value
 *         init = 0;
 *         // Whether the syn global is read only or not
 *         read_only = false;
 *     }
 * 
 *     // Syn thresholds (ran after the normal thresholds and cannot modify non-synglobals)
 *     syn_threshold
 *     {
 *         // State to track. Mandatory parameter.
 *         state;
 *         
 *         // Condition to use as threshold. Mandatory parameter.
 *         condition;
 *         
 *         // Code ran when the threshold is activated. Duplicate nodes will be combined together.
 *         code = "";
 *     }
 *     // Alternate syntax, the init is set to the assigned value
 *     syn_global SynGlobalName2 = 0;
 * }
 * ---
 */
CSynapse[char[]] LoadSynapses(SNode root)
{
	CSynapse[char[]] ret;
	
	foreach(syn_node; root)
	{
		if(syn_node.Type == "synapse")
		{
			if(!syn_node.IsAggregate)
				throw new Exception("synapse is supposed to be an aggregate.");
			
			if((syn_node.Name in ret) !is null)
				throw new Exception("Duplicate synapse name: '" ~ syn_node.Name.idup ~ "'.");
			
			auto syn = new CSynapse(syn_node.Name);
			ret[syn_node.Name.idup] = syn;
			
			//println("Synapse: {}", syn_node.Name);
			
			FillMechanism(syn, syn_node);
			
			syn.SynCode = cast(cstring)syn_node.syn_code;
			
			foreach(node; syn_node)
			{
				switch(node.Type)
				{
					case "syn_threshold":
					{
						auto state = node.state.GetValue!(cstring)(null);
						if(state == "")
							throw new Exception("All syn thresholds need a state.");
							
						auto condition = node.condition.GetValue!(cstring)(null);
						if(condition == "")
							throw new Exception("All syn thresholds need a condition.");

						auto code = cast(cstring)node.code;
						
						syn.AddSynThreshold(state, condition, code);
						
						//println("SynThresh: {} {} -> {}", state, condition, code);
						break;
					}
					case "syn_global":
					{
						auto val = syn.AddSynGlobal(node.Name);
					
						if(node.IsAggregate)
						{
							val = node["init"].GetValue(0.0);
							val.ReadOnly = node.read_only.GetValue(false);
						}
						else
						{
							val = node.GetValue(0.0);
						}
						
						//println("SynGlobal: {} = {} read_only: {}", node.Name, val.Value, val.ReadOnly);
						break;
					}
					default:
						break;
				}
			}
		}
	}
	
	return ret;
}

/**
 * Load connectors from a root config node.
 * 
 * Returns:
 *     An associative array of connectors.
 * 
 * A connector node looks like this:
 * ---
 * connector ConnectorName
 * {
 *     // Connector code. Multiple nodes will be combined together.
 *     code = "";
 * 
 *     // Constants
 *     constant ConstantName
 *     {
 *         init = 0;
 *     }
 * }
 * ---
 */
CConnector[char[]] LoadConnectors(SNode root)
{
	CConnector[char[]] ret;
	
	foreach(conn_node; root)
	{
		if(conn_node.Type == "connector")
		{
			if(!conn_node.IsAggregate)
				throw new Exception("connector is supposed to be an aggregate.");

			if((conn_node.Name in ret) !is null)
				throw new Exception("Duplicate connector name: '" ~ conn_node.Name.idup ~ "'.");
		
			auto conn = new CConnector(conn_node.Name);
			ret[conn_node.Name.idup] = conn;
			
			//println("Connector: {}", conn_node.Name);
			
			conn.SetCode(cast(cstring)conn_node.code);
			
			//println("Code: {}", conn.Code);
			
			foreach(node; conn_node)
			{
				if(node.Type == "constant")
				{
					auto val = conn.AddConstant(node.Name);
					
					if(node.IsAggregate)
						val = node["init"].GetValue(0.0);
					else
						val = node.GetValue(0.0);
					
					//println("Constant: {} = {}", node.Name, val.Value);
				}
			}
		}
	}
	
	return ret;
}

void ApplyMechVals(CMechanism mech, SNode mech_node)
{
	void replace_value(cstring name, scope CValue delegate(cstring name) add_del, double new_value)
	{
		auto old_val = mech[name];
		mech.RemoveValue(name);
		auto new_val = add_del(name);
		old_val.dup(new_val);
		if(new_value !is double.init)
			new_val = new_value;
	}
	
	foreach(node; mech_node)
	{
		switch(node.Type)
		{
			case "global":
				replace_value(node.Name, &mech.AddGlobal, cast(double)node);
				break;
			case "constant":
				replace_value(node.Name, &mech.AddConstant, cast(double)node);
				break;
			case "immutable":
				replace_value(node.Name, &mech.AddImmutable, cast(double)node);
				break;
			default:
				try
				{
					auto new_val = cast(double)node;
					if(new_val !is double.init)
						mech[node.Name] = new_val;
				}
				catch(Exception e)
				{
					if(node.Name != "number" && node.Name != "prefix")
						throw e;
				}
				break;
		}
	}
}

/**
 * Load neuron types from a root config node.
 * 
 * Returns:
 *     An associative array of neuron types.
 * 
 * A neuron type node looks like this:
 * 
 * ---
 * neuron NeuronTypeName
 * {
 *     // Record length
 *     record_length = 0;
 *     
 *     // Record rate
 *     record_rate = 0;
 *     
 *     // Circular buffer size
 *     circ_buffer_size = 0;
 *     
 *     // Number of source synapses
 *     num_src_synapses = 0;
 *     
 *     // Length of the random state
 *     rand_state_len = 0;
 *     
 *     // Minimum dt
 *     min_dt = 0.01;
 * 
 *     // Pre-step code.  Multiple nodes will be combined together.
 *     pre_step = "";
 * 
 *     // Pre-stage code. Multiple nodes will be combined together.
 *     pre_stage = "";
 * 
 *     // Init code. Multiple nodes will be combined together.
 *     init_stage = "";
 *     
 *     // Mechanisms
 *     mechanism MechName
 *     {
 *         // Prefix to use for this mechanism
 *         prefix = "";
 *         
 *         // Initial value setting
 *         some_value = 0;
 * 
 *         // Value replacement. It is possible to change the type of a value to global, constant or immutable.
 *         // This can be useful to fix some parameters for efficiency.
 *         global some_other_value;
 * 
 *         // Can replace and change the initial value
 *         immutable some_other_value_still = 5;
 *     }
 *     
 *     // Synapses
 *     synapse SynName
 *     {
 *         // Prefix to use for this synapse
 *         prefix = "";
 *         
 *         // Number of synapses of this type to insert
 *         number = 0;
 *         
 *         // Initial value setting
 *         some_value = 0;
 *     }
 *     
 *     // Connectors
 *     connector ConnName;
 * }
 * ---
 */
CNeuronType[char[]] LoadNeuronTypes(SNode root, CMechanism[char[]] mechanisms, CSynapse[char[]] synapses, CConnector[char[]] connectors)
{
	CNeuronType[char[]] ret;
	
	foreach(nrn_node; root)
	{
		if(nrn_node.Type == "neuron")
		{
			if(!nrn_node.IsAggregate)
				throw new Exception("neuron is supposed to be an aggregate.");
			if((nrn_node.Name in ret) !is null)
				throw new Exception("Duplicate neuron type name: '" ~ nrn_node.Name.idup ~ "'.");
		
			auto nrn_type = new CNeuronType(nrn_node.Name);
			ret[nrn_node.Name.idup] = nrn_type;
			
			nrn_type.RecordLength = cast(int)nrn_node.record_length;
			nrn_type.RecordRate = cast(int)nrn_node.record_rate;
			nrn_type.CircBufferSize = cast(int)nrn_node.circ_buffer_size;
			nrn_type.NumSrcSynapses = cast(int)nrn_node.num_src_synapses;
			nrn_type.RandLen = cast(int)nrn_node.rand_state_len;
			nrn_type.MinDt = nrn_node.min_dt.GetValue(0.01);
			nrn_type.PreStageCode = cast(cstring)nrn_node.pre_stage;
			nrn_type.PreStepCode = cast(cstring)nrn_node.pre_step;
			nrn_type.InitCode = cast(cstring)nrn_node.init_code;
			
			foreach(node; nrn_node)
			{
				switch(node.Type)
				{
					case "mechanism":
					{
						auto ptr = node.Name in mechanisms;
						if(ptr is null)
							throw new Exception("No mechanism named '" ~ node.Name.idup ~ "' exists.");
						
						auto mech = (*ptr).dup;
						cstring prefix = "";
						if(node.IsAggregate)
						{
							prefix = cast(cstring)node.prefix;
							
							ApplyMechVals(mech, node);
						}
						
						nrn_type.AddMechanism(mech, prefix, true);
						break;
					}
					case "synapse":
					{
						auto ptr = node.Name in synapses;
						if(ptr is null)
							throw new Exception("No synapse named '" ~ node.Name.idup ~ "' exists.");
						
						auto syn = (*ptr).dup;

						if(!node.IsAggregate)
							throw new Exception("synapse instantiation must be an aggregate.");

						auto prefix = cast(cstring)node.prefix;
						auto number = cast(int)node.number;
							
						ApplyMechVals(syn, node);
						
						nrn_type.AddSynapse(syn, number, prefix, true);
					
						break;
					}
					case "connector":
					{
						auto ptr = node.Name in connectors;
						if(ptr is null)
							throw new Exception("No connector named '" ~ node.Name.idup ~ "' exists.");
						
						//println("Added {}", node.Name);
						
						nrn_type.AddConnector(*ptr);
						break;
					}
					default:
						break;
				}
			}
		}
	}
	
	return ret;
}

/**
 * Loads a model from a configuration file.
 * 
 * Params:
 *     file = Path to a file to load from.
 *     include_directories = Additional include directories.
 *     flags = Flags specifying which platform and type of device you wish to use. See $(SYMLINK2 celeme.platform_flags, EPlatformFlags, EPlatformFlags).
 *     device_idx = If you are forcing a specific platform you can specify what device index to use. Otherwise, first available device is uesd.
 *     double_precision = Whether or not to use double precision.
 * 
 * Returns:
 *     The loaded model.
 */
IModel LoadModel(cstring file, cstring[] include_directories, EPlatformFlags flags = EPlatformFlags.GPU, size_t device_idx = 0, bool double_precision = false)
{
	auto root = SNode();
	scope(exit) root.Destroy();
	foreach(dir; include_directories)
		root.AddSearchDirectory(dir);
	if(!root.LoadNodes(file))
		throw new Exception("Failed to load the model from '" ~ file.idup ~ "'.");

	return LoadModel(root, flags, device_idx, double_precision);
}

/**
 * Loads a model from a pre-loaded configuration node.
 * 
 * Params:
 *     node = The root node to load from.
 *     flags = Flags specifying which platform and type of device you wish to use. See $(SYMLINK2 celeme.platform_flags, EPlatformFlags, EPlatformFlags).
 *     device_idx = If you are forcing a specific platform you can specify what device index to use. Otherwise, first available device is uesd.
 *     double_precision = Whether or not to use double precision.
 * 
 * Returns:
 *     The loaded model.
 */
IModel LoadModel(SNode root, EPlatformFlags flags = EPlatformFlags.GPU, size_t device_idx = 0, bool double_precision = false)
{
	auto mechanisms = LoadMechanisms(root);
	auto synapses = LoadSynapses(root);
	auto connectors = LoadConnectors(root);
	auto types = LoadNeuronTypes(root, mechanisms, synapses, connectors);
	
	if(double_precision)
		return new CCLModel!(double)(flags, device_idx, types);
	else
		return new CCLModel!(float)(flags, device_idx, types);
}

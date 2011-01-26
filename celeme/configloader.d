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

/**
 * This module allows the loading of a model definition (including connectors,
 * neuron types, mechanisms and synapses) from a configuration file.
 */

module celeme.configloader;

import celeme.config;
import celeme.util;
import celeme.frontend;
import celeme.imodel;
import celeme.clmodel;

import tango.text.convert.Format;

void FillMechanism(CMechanism mech, CConfigEntry mech_entry)
{
	foreach(ii; range(3))
	{
		auto stage_name = Format("stage{}", ii);
		auto stage_code = mech_entry.ValueOf!(char[])(stage_name);
		if(stage_code !is null)
		{
			//println("{}: {}", stage_name, stage_code);
			mech.SetStage(ii, stage_code);
		}
	}
	
	mech.SetInitCode(mech_entry.ValueOf!(char[])("init", ""));
	mech.SetPreStage(mech_entry.ValueOf!(char[])("pre_stage", ""));
	
	foreach(val_entries; mech_entry["state"])
	{
		foreach(val_entry; val_entries[])
		{		
			auto val = mech.AddState(val_entry.Name);
			
			if(val_entry.IsSingleValue)
				val = val_entry.Value!(double)(0.0);
			else if(val_entry.IsAggregate)
			{
				val = val_entry.ValueOf!(double)("init", 0.0);
				val.Tolerance = val_entry.ValueOf!(double)("tolerance", 0.1);
			}
			
			//println("State: {} = {} @ {}", val_entry.Name, val.Value, val.Tolerance);
		}
	}
	
	foreach(val_entries; mech_entry["global"])
	{
		foreach(val_entry; val_entries[])
		{	
			auto val = mech.AddGlobal(val_entry.Name);
			
			if(val_entry.IsSingleValue)
				val = val_entry.Value!(double)(0.0);
			else if(val_entry.IsAggregate)
			{
				val = val_entry.ValueOf!(double)("init", 0.0);
				val.ReadOnly = val_entry.ValueOf!(bool)("readonly", false);
			}
			
			//println("Global: {} = {} readonly: {}", val_entry.Name, val.Value, val.ReadOnly);
		}
	}
	
	foreach(val_entries; mech_entry["local"])
	{
		foreach(val_entry; val_entries[])
		{	
			mech.AddLocal(val_entry.Name);
			//println("Local: {}", val_entry.Name);
		}
	}
	
	foreach(val_entries; mech_entry["constant"])
	{
		foreach(val_entry; val_entries[])
		{
			auto val = mech.AddConstant(val_entry.Name);
			
			if(val_entry.IsSingleValue)
				val = val_entry.Value!(double)(0.0);
			else if(val_entry.IsAggregate)
				val = val_entry.ValueOf!(double)("init", 0.0);
			
			//println("Constant: {} = {}", val_entry.Name, val.Value);
		}
	}
	
	foreach(val_entries; mech_entry["external"])
	{
		foreach(val_entry; val_entries[])
		{
			mech.AddExternal(val_entry.Name);
			
			//println("External: {}", val_entry.Name);
		}
	}

	foreach(entry; mech_entry["threshold"])
	{
		auto state = entry.ValueOf!(char[])("state", null);
		if(state is null)
			throw new Exception("All thresholds need a state.");
			
		auto condition = entry.ValueOf!(char[])("condition", null);
		if(condition is null)
			throw new Exception("All thresholds need a condition.");

		auto code = entry.ValueOf!(char[])("code", "");
		
		bool is_event_source = entry.ValueOf!(bool)("event_source", false);
		bool reset_dt = entry.ValueOf!(bool)("reset_dt", false);
		
		mech.AddThreshold(state, condition, code, is_event_source, reset_dt);
		
		//println("Thresh: {} {} -> {} \n Events: {} Reset: {}", state, condition, code, is_event_source, reset_dt);
	}
}

/**
 * Load mechanisms from a root config entry.
 * 
 * Returns:
 *     An associative array of mechanisms.
 * 
 * A mechanism entry looks like this:
 * 
 * ---
 * mechanism MechName
 * {
 *     // Staged evaluation of the derivatives
 *     stage0 = "";
 *     stage1 = "";
 *     stage2 = "";
 *     
 *     // Init code
 *     init = "";
 *     
 *     // Code run before the integration is performed
 *     pre_stage = "";
 *     
 *     // States
 *     state StateName
 *     {
 *         // Initial value
 *         init = 0;
 *         // Tolerance
 *         tolerance = 0.1
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
 *         readonly = false;
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
 *     // Externals
 *     external ExternName;
 *     
 *     // Thresholds
 *     threshold
 *     {
 *         // State to track. Mandatory parameter.
 *         state;
 *         
 *         // Condition to use as threshold. Mandatory parameter.
 *         condition;
 *         
 *         // Code ran when the threshold is activated
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
CMechanism[char[]] LoadMechanisms(CConfigEntry root)
{
	CMechanism[char[]] ret;
	
	foreach(entries; root["mechanism"])
	{
		if(!entries.IsAggregate)
			throw new Exception("mechanism is supposed to be an aggregate.");
		foreach(entry; entries[])
		{ 
			if((entry.Name in ret) !is null)
				throw new Exception("Duplicate mechanism name: '" ~ entry.Name ~ "'.");
				
			auto mech = new CMechanism(entry.Name);
			ret[entry.Name.dup] = mech;
			
			FillMechanism(mech, entry);
			
			//println("Mechanism: {}", entry.Name);
		}
	}
	
	return ret;
}

/**
 * Load synapses from a root config entry.
 * 
 * Returns:
 *     An associative array of synapses.
 * 
 * A mechanism entry looks just like a mechanism entry, except it has more fields:
 * 
 * ---
 * synapse SynapseName
 * {
 *     // Code to be ran when the synapse is triggered
 *     syn_code = "";
 *     
 *     // Syn globals
 *     syn_global SynGlobalName
 *     {
 *         // Initial value
 *         init = 0;
 *         // Whether the syn global is read only or not
 *         readonly = false;
 *     }
 *     // Alternate syntax, the init is set to the assigned value
 *     syn_global SynGlobalName2 = 0;
 * }
 * ---
 */
CSynapse[char[]] LoadSynapses(CConfigEntry root)
{
	CSynapse[char[]] ret;
	
	foreach(entries; root["synapse"])
	{
		if(!entries.IsAggregate)
			throw new Exception("synapse is supposed to be an aggregate.");
		foreach(entry; entries[])
		{
			if((entry.Name in ret) !is null)
				throw new Exception("Duplicate synapse name: '" ~ entry.Name ~ "'.");
			
			auto syn = new CSynapse(entry.Name);
			ret[entry.Name.dup] = syn;
			
			//println("Synapse: {}", entry.Name);
			
			FillMechanism(syn, entry);
			
			auto code = entry.ValueOf!(char[])("syn_code", null);
			if(code !is null)
			{
				//println("Code: {}", code);
				syn.SetSynCode(code);
			}
			
			foreach(val_entries; entry["syn_global"])
			{
				foreach(val_entry; val_entries[])
				{				
					auto val = syn.AddSynGlobal(val_entry.Name);
					
					if(val_entry.IsSingleValue)
						val = val_entry.Value!(double)(0.0);
					else if(val_entry.IsAggregate)
					{
						val = val_entry.ValueOf!(double)("init", 0.0);
						val.ReadOnly = val_entry.ValueOf!(bool)("readonly", false);
					}
					
					//println("SynGlobal: {} = {} readonly: {}", val_entry.Name, val.Value, val.ReadOnly);
				}
			}
		}
	}
	
	return ret;
}

/**
 * Load connectors from a root config entry.
 * 
 * Returns:
 *     An associative array of connectors.
 * 
 * A connector entry looks like this:
 * ---
 * connector ConnectorName
 * {
 *     // Connector code
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
CConnector[char[]] LoadConnectors(CConfigEntry root)
{
	CConnector[char[]] ret;
	
	foreach(entries; root["connector"])
	{
		if(!entries.IsAggregate)
			throw new Exception("connector is supposed to be an aggregate.");
		foreach(entry; entries[])
		{
			if((entry.Name in ret) !is null)
				throw new Exception("Duplicate connector name: '" ~ entry.Name ~ "'.");
		
			auto conn = new CConnector(entry.Name);
			ret[entry.Name.dup] = conn;
			
			//println("Connector: {}", entry.Name);
			
			conn.SetCode(entry.ValueOf!(char[])("code", ""));
			
			//println("Code: {}", conn.Code);
			
			foreach(val_entries; entry["constant"])
			{
				foreach(val_entry; val_entries[])
				{
					auto val = conn.AddConstant(val_entry.Name);
					
					if(val_entry.IsSingleValue)
						val = val_entry.Value!(double)(0.0);
					else if(val_entry.IsAggregate)
						val = val_entry.ValueOf!(double)("init", 0.0);
					
					//println("Constant: {} = {}", val_entry.Name, val.Value);
				}
			}
		}
	}
	
	return ret;
}

void ApplyMechVals(CMechanism mech, CConfigEntry mech_entry)
{
	foreach(val_entries; mech_entry["init"])
	{
		foreach(val_entry; val_entries[])
		{
			bool is_def = false;
			if(val_entry.IsSingleValue)
			{
				auto value = val_entry.Value!(double)(0.0, &is_def);
				if(!is_def)
				{
					mech[val_entry.Name] = value;
					//println("{} set to {}", val_entry.Name, value);
				}
			}
			else
			{
				auto value = val_entry.ValueOf!(double)("init", 0.0, &is_def);
				if(!is_def)
				{
					mech[val_entry.Name] = value;
				}
				value = val_entry.ValueOf!(double)("tolerance", 0.0, &is_def);
				if(!is_def)
				{
					mech[val_entry.Name].Tolerance = value;
				}
			}
		}
	}
}

/**
 * Load neuron types from a root config entry.
 * 
 * Returns:
 *     An associative array of neuron types.
 * 
 * A neuron type entry looks like this:
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
 *     // Mechanisms
 *     mechanism MechName
 *     {
 *         // Prefix to use for this mechanism
 *         prefix = "";
 *         
 *         // Initial value setting
 *         init
 *         {
 *             SomeVal
 *             {
 *                 // Initial value. If omitted, mechanism's default value is used
 *                 init;
 *                 // Tolerance (makes sense only for states). If omitted, mechanism's default value
 *                 // is used
 *                 tolerance;
 *             }
 *             // Alternate syntax, the init is set to the assigned value
 *             SomeOtherVal = 0;
 *         }
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
 *         init
 *         {
 *             SomeVal
 *             {
 *                 // Initial value. If omitted, mechanism's default value is used
 *                 init;
 *                 // Tolerance (makes sense only for states). If omitted, mechanism's default value
 *                 // is used
 *                 tolerance;
 *             }
 *             // Alternate syntax, the init is set to the assigned value
 *             SomeOtherVal = 0;
 *         }
 *     }
 *     
 *     // Connectors
 *     connector ConnName;
 * }
 * ---
 */
CNeuronType[char[]] LoadNeuronTypes(CConfigEntry root, CMechanism[char[]] mechanisms, CSynapse[char[]] synapses, CConnector[char[]] connectors)
{
	CNeuronType[char[]] ret;
	
	foreach(nrn_entries; root["neuron"])
	{
		if(!nrn_entries.IsAggregate)
			throw new Exception("neuron is supposed to be an aggregate.");
		foreach(nrn_entry; nrn_entries[])
		{
			if((nrn_entry.Name in ret) !is null)
				throw new Exception("Duplicate neuron type name: '" ~ nrn_entry.Name ~ "'.");
		
			auto nrn_type = new CNeuronType(nrn_entry.Name);
			ret[nrn_entry.Name.dup] = nrn_type;
			
			nrn_type.RecordLength = nrn_entry.ValueOf!(int)("record_length", 0);
			nrn_type.RecordRate = nrn_entry.ValueOf!(int)("record_rate", 0);
			nrn_type.CircBufferSize = nrn_entry.ValueOf!(int)("circ_buffer_size", 0);
			nrn_type.NumSrcSynapses = nrn_entry.ValueOf!(int)("num_src_synapses", 0);
			nrn_type.RandLen = nrn_entry.ValueOf!(int)("rand_state_len", 0);
			nrn_type.MinDt = nrn_entry.ValueOf!(double)("min_dt", 0.01);
			
			foreach(entries; nrn_entry["mechanism"])
			{
				foreach(entry; entries[])
				{
					auto ptr = entry.Name in mechanisms;
					if(ptr is null)
						throw new Exception("No mechanism named '" ~ entry.Name ~ "' exists.");
					
					auto mech = (*ptr).dup;
					char[] prefix = "";
					if(entry.IsAggregate)
					{
						prefix = entry.ValueOf!(char[])("prefix", "");
						
						ApplyMechVals(mech, entry);
					}
					
					nrn_type.AddMechanism(mech, prefix, true);
				}
			}
			
			foreach(entries; nrn_entry["synapse"])
			{
				foreach(entry; entries[])
				{
					auto ptr = entry.Name in synapses;
					if(ptr is null)
						throw new Exception("No synapse named '" ~ entry.Name ~ "' exists.");
					
					auto syn = (*ptr).dup;
	
					if(!entry.IsAggregate)
						throw new Exception("synapse instantiation must be an aggregate.");

					auto prefix = entry.ValueOf!(char[])("prefix", "");
					auto number = entry.ValueOf!(int)("number", 0);
						
					ApplyMechVals(syn, entry);
					
					nrn_type.AddSynapse(syn, number, prefix, true);
				}
			}
			
			foreach(entries; nrn_entry["connector"])
			{
				foreach(entry; entries[])
				{
					auto ptr = entry.Name in connectors;
					if(ptr is null)
						throw new Exception("No connector named '" ~ entry.Name ~ "' exists.");
					
					//println("Added {}", entry.Name);
					
					nrn_type.AddConnector(*ptr);
				}
			}
		}
	}
	
	return ret;
}

/**
 * Loads a model from a configuration file.
 * 
 * The configuration entry for a model looks like this:
 * 
 * ---
 * model
 * {
 *     // What floating point size to use ("float" or "double")
 *     float_type = "float";
 *     timestep_size = 1.0;
 *     
 *     // Neuron groups
 *     group NeuronTypeName
 *     {
 *         // Number of neurons
 *         number = 1;
 *         
 *         // Override the name of the group (if adding several of the same kind)
 *         // Empty name keeps the original neuron type name.
 *         name = "";
 *         
 *         // Whether or not to use the adaptive integrator for this group
 *         adaptive_dt = true;
 *     }
 * }
 * ---
 * 
 * Params:
 *     file = Path to a file to load from.
 *     gpu = Whether or not to use the GPU.
 * 
 * Returns:
 *     The loaded model.
 */
IModel LoadModel(char[] file, bool gpu = false)
{
	auto root = LoadConfig(file);
	auto mechanisms = LoadMechanisms(root);
	auto synapses = LoadSynapses(root);
	auto connectors = LoadConnectors(root);
	auto types = LoadNeuronTypes(root, mechanisms, synapses, connectors);
	
	auto model_entry = root["model", true];
	if(model_entry is null)
		throw new Exception("No 'model' node in '" ~ file ~ "'.");
	
	IModel ret;

	auto float_type = model_entry.ValueOf!(char[])("float_type", "float");
	auto timestep_size = model_entry.ValueOf!(double)("timestep_size", 1.0);
	
	if(float_type == "float")
		ret = CreateCLModel!(float)(gpu);
	//else if(float_type == "double")
	//	ret = CreateCLModel!(double)(gpu);
	else
		throw new Exception("'" ~ float_type ~ "' is not a valid floating point type.");
		
	ret.TimeStepSize = timestep_size;
	
	foreach(entries; model_entry["group"])
	{
		foreach(entry; entries[])
		{		
			auto type_ptr = entry.Name in types;
			if(type_ptr is null)
				throw new Exception("No type named '" ~ entry.Name ~ "' exists.");
			
			auto number = entry.ValueOf!(int)("number", 1);
			auto name = entry.ValueOf!(char[])("name", "");
			auto adaptive_dt = entry.ValueOf!(bool)("adaptive_dt", true);
			
			ret.AddNeuronGroup(*type_ptr, number, name, adaptive_dt);
		}
	}
	
	return ret;
}

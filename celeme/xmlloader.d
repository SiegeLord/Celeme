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

module celeme.xmlloader;
/+
import celeme.xmlutil;
import celeme.util;
import celeme.frontend;
import celeme.imodel;
import celeme.clmodel;

import tango.text.convert.Format;

CMechanism[char[]] LoadMechanisms(char[] file)
{
	auto root = GetRoot(file);
	return LoadMechanisms(root);
}

void FillMechanism(CMechanism mech, Node mech_node)
{
	foreach(ii; range(3))
	{
		auto stage_name = Format("stage{}", ii);
		auto stage_code = GetAttribute!(char[])(mech_node, stage_name);
		if(stage_code !is null)
		{
			//println("{}: {}", stage_name, stage_code);
			mech.SetStage(ii, stage_code);
		}
	}
	
	mech.SetInitCode(GetAttribute!(char[])(mech_node, "init", ""));
	mech.SetPreStage(GetAttribute!(char[])(mech_node, "pre_stage", ""));
	
	foreach(val_node; GetChildren(mech_node, "state"))
	{
		auto val_name = GetAttribute!(char[])(val_node, "name", null);
		if(val_name is null)
			throw new Exception("All states need a name.");
		
		auto val = mech.AddState(val_name);
		
		val = GetAttribute!(double)(val_node, "init", 0.0);
		val.Tolerance = GetAttribute!(double)(val_node, "tolerance", 0.1);
		
		//println("State: {} = {} @ {}", val_name, val.Value, val.Tolerance);
	}
	
	foreach(val_node; GetChildren(mech_node, "global"))
	{
		auto val_name = GetAttribute!(char[])(val_node, "name", null);
		if(val_name is null)
			throw new Exception("All globals need a name.");
		
		auto val = mech.AddGlobal(val_name);
		
		val = GetAttribute!(double)(val_node, "init", 0.0);
		val.ReadOnly = GetAttribute!(bool)(val_node, "readonly", false);
		
		//println("Global: {} = {} readonly: {}", val_name, val.Value, val.ReadOnly);
	}
	
	foreach(val_node; GetChildren(mech_node, "local"))
	{
		auto val_name = GetAttribute!(char[])(val_node, "name", null);
		if(val_name is null)
			throw new Exception("All locals need a name.");
		
		mech.AddLocal(val_name);
		
		//println("Local: {}", val_name);
	}
	
	foreach(val_node; GetChildren(mech_node, "constant"))
	{
		auto val_name = GetAttribute!(char[])(val_node, "name", null);
		if(val_name is null)
			throw new Exception("All constants need a name.");
		
		auto val = mech.AddConstant(val_name);
		val = GetAttribute!(double)(val_node, "init", 0.0);
		
		//println("Constant: {} = {}", val_name, val.Value);
	}
	
	foreach(val_node; GetChildren(mech_node, "external"))
	{
		auto val_name = GetAttribute!(char[])(val_node, "name", null);
		if(val_name is null)
			throw new Exception("All externals need a name.");
		
		mech.AddExternal(val_name);
		
		//println("External: {}", val_name);
	}
	
	foreach(thresh_node; GetChildren(mech_node, "threshold"))
	{
		auto state = GetAttribute!(char[])(thresh_node, "state", null);
		if(state is null)
			throw new Exception("All thresholds need a state.");
			
		auto condition = GetAttribute!(char[])(thresh_node, "condition", null);
		if(condition is null)
			throw new Exception("All thresholds need a condition.");

		auto code = GetAttribute!(char[])(thresh_node, "code", "");
		
		bool is_event_source = GetAttribute!(bool)(thresh_node, "event_source", false);
		bool reset_dt = GetAttribute!(bool)(thresh_node, "reset_dt", false);
		
		mech.AddThreshold(state, condition, code, is_event_source, reset_dt);
		
		//println("Thresh: {} {} -> {} \n Events: {} Reset: {}", state, condition, code, is_event_source, reset_dt);
	}
}

CMechanism[char[]] LoadMechanisms(Node root)
{
	CMechanism[char[]] ret;
	
	foreach(mech_node; GetChildren(root, "mechanism"))
	{
		auto mech_name = GetAttribute!(char[])(mech_node, "name", null);
		if(mech_name is null)
			throw new Exception("All mechanisms need a name.");
		
		auto mech_ptr = mech_name in ret;
		if(mech_ptr !is null)
			throw new Exception("Duplicate mechanism name: '" ~ mech_name ~ "'.");
		
		auto mech = new CMechanism(mech_name);
		ret[mech_name.dup] = mech;
		
		//println("Mechanism: {}", mech_name);
		
		FillMechanism(mech, mech_node);
	}
	
	return ret;
}

CSynapse[char[]] LoadSynapses(Node root)
{
	CSynapse[char[]] ret;
	
	foreach(syn_node; GetChildren(root, "synapse"))
	{
		auto syn_name = GetAttribute!(char[])(syn_node, "name", null);
		if(syn_name is null)
			throw new Exception("All synapses need a name.");
		
		auto syn_ptr = syn_name in ret;
		if(syn_ptr !is null)
			throw new Exception("Duplicate synapse name: '" ~ syn_name ~ "'.");
		
		auto syn = new CSynapse(syn_name);
		ret[syn_name.dup] = syn;
		
		//println("Synapse: {}", syn_name);
		
		FillMechanism(syn, syn_node);
		
		auto code = GetAttribute!(char[])(syn_node, "syn_code", null);
		if(code !is null)
		{
			//println("Code: {}", code);
			syn.SetSynCode(code);
		}
		
		foreach(val_node; GetChildren(syn_node, "syn_global"))
		{
			auto val_name = GetAttribute!(char[])(val_node, "name", null);
			if(val_name is null)
				throw new Exception("All synglobals need a name.");
			
			auto val = syn.AddSynGlobal(val_name);
			
			val = GetAttribute!(double)(val_node, "init", 0.0);
			val.ReadOnly = GetAttribute!(bool)(val_node, "readonly", false);
			
			//println("SynGlobal: {} = {} readonly: {}", val_name, val.Value, val.ReadOnly);
		}
	}
	
	return ret;
}

CConnector[char[]] LoadConnectors(Node root)
{
	CConnector[char[]] ret;
	
	foreach(conn_node; GetChildren(root, "connector"))
	{
		auto conn_name = GetAttribute!(char[])(conn_node, "name", null);
		if(conn_name is null)
			throw new Exception("All neuron types need a name.");
		
		auto conn_ptr = conn_name in ret;
		if(conn_ptr !is null)
			throw new Exception("Duplicate neuron type name: '" ~ conn_name ~ "'.");
		
		auto conn = new CConnector(conn_name);
		ret[conn_name.dup] = conn;
		
		//println("Connector: {}", conn_name);
		
		conn.SetCode(GetAttribute!(char[])(conn_node, "code", ""));
		
		foreach(val_node; GetChildren(conn_node, "constant"))
		{
			auto val_name = GetAttribute!(char[])(val_node, "name", null);
			if(val_name is null)
				throw new Exception("All constants need a name.");
			
			auto val = conn.AddConstant(val_name);
			val = GetAttribute!(double)(val_node, "init", 0.0);
			
			//println("Constant: {} = {}", val_name, val.Value);
		}
	}
	
	return ret;
}

void ApplyMechVals(CMechanism mech, Node mech_node)
{
	foreach(val_node; GetChildren(mech_node, "value"))
	{
		auto name = GetAttribute!(char[])(val_node, "name", null);
		if(name is null)
			throw new Exception("All values need a name.");

		bool is_def = false;
		auto value = GetAttribute!(double)(val_node, "value", 0.0, &is_def);
		if(!is_def)
		{
			mech[name] = value;
		}
		
		value = GetAttribute!(double)(val_node, "tolerance", 0.0, &is_def);
		if(!is_def)
		{
			mech[name].Tolerance = value;
		}
	}
}

CNeuronType[char[]] LoadNeuronTypes(Node root, CMechanism[char[]] mechanisms, CSynapse[char[]] synapses, CConnector[char[]] connectors)
{
	CNeuronType[char[]] ret;
	
	foreach(nrn_node; GetChildren(root, "neuron"))
	{
		auto nrn_name = GetAttribute!(char[])(nrn_node, "name", null);
		if(nrn_name is null)
			throw new Exception("All neuron types need a name.");
		
		auto nrn_ptr = nrn_name in ret;
		if(nrn_ptr !is null)
			throw new Exception("Duplicate neuron type name: '" ~ nrn_name ~ "'.");
		
		auto nrn_type = new CNeuronType(nrn_name);
		ret[nrn_name.dup] = nrn_type;
		
		nrn_type.RecordLength = GetAttribute!(int)(nrn_node, "record_length", 0);
		nrn_type.RecordRate = GetAttribute!(int)(nrn_node, "record_rate", 0);
		nrn_type.CircBufferSize = GetAttribute!(int)(nrn_node, "circ_buffer_size", 0);
		nrn_type.NumSrcSynapses = GetAttribute!(int)(nrn_node, "num_src_synapses", 0);
		nrn_type.RandLen = GetAttribute!(int)(nrn_node, "rand_state_len", 0);
		nrn_type.MinDt = GetAttribute!(double)(nrn_node, "min_dt", 0.01);
		
		foreach(mech_node; GetChildren(nrn_node, "mechanism"))
		{
			auto mech_name = GetAttribute!(char[])(mech_node, "name", null);
			if(mech_name is null)
				throw new Exception("All mechanisms need a name.");
			
			auto mech_ptr = mech_name in mechanisms;
			if(mech_ptr is null)
				throw new Exception("No mechanism named '" ~ mech_name ~ "' exists.");
			
			auto prefix = GetAttribute!(char[])(mech_node, "prefix", "");
			
			auto mech = (*mech_ptr).dup;
			
			ApplyMechVals(mech, mech_node);
			
			nrn_type.AddMechanism(mech, prefix, true);
		}
		
		foreach(syn_node; GetChildren(nrn_node, "synapse"))
		{
			auto syn_name = GetAttribute!(char[])(syn_node, "name", null);
			if(syn_name is null)
				throw new Exception("All synapses need a name.");
			
			auto syn_ptr = syn_name in synapses;
			if(syn_ptr is null)
				throw new Exception("No synapse named '" ~ syn_name ~ "' exists.");
			
			auto prefix = GetAttribute!(char[])(syn_node, "prefix", "");
			auto number = GetAttribute!(int)(syn_node, "number", 0);
			
			auto syn = (*syn_ptr).dup;
			
			ApplyMechVals(syn, syn_node);
			
			nrn_type.AddSynapse(syn, number, prefix, true);
		}
		
		foreach(conn_node; GetChildren(nrn_node, "connector"))
		{
			auto conn_name = GetAttribute!(char[])(conn_node, "name", null);
			if(conn_name is null)
				throw new Exception("All connectors need a name.");
			
			auto conn_ptr = conn_name in connectors;
			if(conn_ptr is null)
				throw new Exception("No connector named '" ~ conn_name ~ "' exists.");
			
			//println("Added {}", conn_name);
			
			nrn_type.AddConnector(*conn_ptr);
		}
	}
	
	return ret;
}

IModel LoadModel(char[] file, bool gpu = false)
{
	auto root = GetRoot(file);
	auto mechanisms = LoadMechanisms(root);
	auto connectors = LoadConnectors(root);
	auto synapses = LoadSynapses(root);
	auto types = LoadNeuronTypes(root, mechanisms, synapses, connectors);
	
	auto model_node = GetChild(root, "model");
	if(model_node is null)
		throw new Exception("No 'model' node in '" ~ file ~ "'.");
	
	IModel ret;

	auto float_type = GetAttribute!(char[])(model_node, "float_type", "float");
	auto timestep_size = GetAttribute!(double)(model_node, "timestep_size", 1.0);
	
	if(float_type == "float")
		ret = CreateCLModel!(float)(gpu);
	//else if(float_type == "double")
	//	ret = CreateCLModel!(double)(gpu);
	else
		throw new Exception("'" ~ float_type ~ "' is not a valid floating point type.");
		
	ret.TimeStepSize = timestep_size;
	
	foreach(group_node; GetChildren(model_node, "group"))
	{
		auto type_name = GetAttribute!(char[])(group_node, "type", null);
		if(type_name is null)
			throw new Exception("All groups need a type name.");
		
		auto type_ptr = type_name in types;
		if(type_ptr is null)
			throw new Exception("No type named '" ~ type_name ~ "' exists.");
		
		auto number = GetAttribute!(int)(group_node, "number", 1);
		auto name = GetAttribute!(char[])(group_node, "name", "");
		auto adaptive_dt = GetAttribute!(bool)(group_node, "adaptive_dt", true);
		
		ret.AddNeuronGroup(*type_ptr, number, name, adaptive_dt);
	}
	
	return ret;
}
+/
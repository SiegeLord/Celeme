module celeme.xmlloader;

import celeme.xmlutil;
import celeme.util;
import celeme.frontend;

import tango.text.convert.Format;

CMechanism[char[]] LoadMechanisms(char[] file)
{
	auto root = GetRoot(file);
	return LoadMechanisms(root);
}

void FillMechanism(CMechanism mech, Node mech_node)
{
	for(int ii = 0; ii < 3; ii++)
	{
		auto stage_name = Format("stage{}", ii);
		auto stage_code = GetAttribute!(char[])(mech_node, stage_name);
		if(stage_code !is null)
		{
			//println("{}: {}", stage_name, stage_code);
		}
		mech.SetStage(ii, stage_code);
	}
	
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

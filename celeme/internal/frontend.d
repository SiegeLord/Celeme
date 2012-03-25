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

module celeme.internal.frontend;

import celeme.internal.util;

import tango.core.Array;
import tango.io.Stdout;

/* A front end value, primarily stores the name and default value */
class CValue
{
	this(cstring name)
	{
		Name = name;
	}
	
	double opAssign(double val)
	{
		return Value = val;
	}
	
	@property
	CValue dup(CValue ret = null)
	{
		if(ret is null)
			ret = new CValue(Name.dup);

		ret.Name = Name.dup;
		ret.Value = Value;
		ret.ReadOnly = ReadOnly;
		
		return ret;
	}
	
	cstring Name;
	double Value = 0;
	bool ReadOnly = false;
}

bool IsValidName(cstring name)
{
	return name != "t"
	    && name != "dt"
	    && name != "count"
	    && name != "cur_time"
	    && name != "i"
	    && name != "error";
}

struct SThreshold
{
	cstring State;
	cstring Condition;
	cstring Source;
	bool IsEventSource = false;
	bool ResetTime = false;
	
	@property
	SThreshold dup()
	{
		return SThreshold(State.dup, Condition.dup, Source.dup, IsEventSource, ResetTime);
	}
}

struct SSynThreshold
{
	cstring State;
	cstring Condition;
	cstring Source;
	
	@property
	SSynThreshold dup()
	{
		return SSynThreshold(State.dup, Condition.dup, Source.dup);
	}
}

@property
cstring AddMechFunc(cstring name)()
{
	return 
	`CValue Add` ~ name ~ `(cstring name)
		{
			if(!IsValidName(name))
				throw new Exception("The name '" ~ name.idup ~ "' is reserved.");
			if(IsDuplicateName(name))
				throw new Exception("'" ~ name.idup ~ "' already exists in mechanism '" ~ Name.idup ~ "'.");
			auto val = new CValue(name);				
			` ~ name ~ `s ~= val;
			return val;
		}
	`;
}

class CMechanism
{
	this(cstring name)
	{
		Name = name;
	}
	
	mixin(AddMechFunc!("State"));
	mixin(AddMechFunc!("Local"));
	mixin(AddMechFunc!("Global"));
	mixin(AddMechFunc!("Constant"));
	mixin(AddMechFunc!("Immutable"));
	
	void AddExternal(cstring name)
	{
		if(!IsValidName(name))
			throw new Exception("The name '" ~ name.idup ~ "' is reserved.");
		if(IsDuplicateName(name))
			throw new Exception("'" ~ name.idup ~ "' exists in mechanism '" ~ Name.idup ~ "'.");
		Externals ~= name;
	}
	
	void RemoveValue(cstring name)
	{		
		bool try_remove(ref CValue[] arr)
		{
			auto new_length = arr.removeIf((CValue val) { return val.Name == name; });
			auto ret = new_length != arr.length;
			
			arr.length = new_length;
			
			return ret;
		}
		
		if(try_remove(States)) return;
		if(try_remove(Locals)) return;
		if(try_remove(Globals)) return;
		if(try_remove(Constants)) return;
		if(try_remove(Immutables)) return;
		
		auto new_length = Externals.remove(name);
		if(new_length != Externals.length)
		{
			Externals.length = new_length;
			return;
		}
		
		throw new Exception("Mechanism does not have a value named '" ~ name.idup ~ "'.");
	}
	
	bool IsDuplicateName(cstring name)
	{
		/* TODO: LOL OPTIMIZE */
		foreach(val; &AllValues)
		{
			if(val.Name == name)
				return true;
		}
		return false;
	}
	
	int AllValues(scope int delegate(ref CValue value) dg)
	{
		foreach(val; States)
		{
			if(int ret = dg(val))
				return ret;
		}
		foreach(val; Globals)
		{
			if(int ret = dg(val))
				return ret;
		}
		foreach(val; Locals)
		{
			if(int ret = dg(val))
				return ret;
		}
		foreach(val; Constants)
		{
			if(int ret = dg(val))
				return ret;
		}
		foreach(val; Immutables)
		{
			if(int ret = dg(val))
				return ret;
		}
		return 0;
	}
	
	int AllImmutables(scope int delegate(ref CValue value) dg)
	{
		foreach(val; Immutables)
		{
			if(int ret = dg(val))
				return ret;
		}
		return 0;
	}
	
	int AllStates(scope int delegate(ref CValue value) dg)
	{
		foreach(val; States)
		{
			if(int ret = dg(val))
				return ret;
		}
		return 0;
	}
	
	void SetStage(int stage, cstring source)
	{
		assert(stage >= 0, "stage must be greater than or equal to 0");
		assert(stage < 3, "stage must be less than 3");
		
		Stages[stage] = source;
	}
	
	void AddThreshold(cstring state, cstring condition, cstring source, bool event_source = false, bool resetting = false)
	{
		SThreshold thresh;
		thresh.State = state;
		thresh.Condition = condition;
		thresh.Source = source;
		thresh.IsEventSource = event_source;
		thresh.ResetTime = resetting;
		
		if(thresh.IsEventSource)
			NumEventSources++;
		
		Thresholds ~= thresh;
	}
	
	@property
	void PreStepCode(cstring code)
	{
		PreStepCodeVal = code;
	}
	
	@property
	cstring PreStepCode()
	{
		return PreStepCodeVal;
	}
	
	@property
	void InitCode(cstring code)
	{
		InitCodeVal = code;
	}
	
	@property
	cstring InitCode()
	{
		return InitCodeVal;
	}

	@property
	void PreStageCode(cstring code)
	{
		PreStageCodeVal = code;
	}
	
	@property
	cstring PreStageCode()
	{
		return PreStageCodeVal;
	}
	
	CValue opIndex(cstring name)
	{
		/* TODO: LOL OPTIMIZE */
		foreach(val; &AllValues)
		{
			if(val.Name == name)
				return val;
		}
		
		throw new Exception("'" ~ Name.idup ~ "' does not have a '" ~ name.idup ~ "' value.");
	}
	
	CValue opIndexAssign(double val, cstring name)
	{
		auto value = opIndex(name);
		value = val;
		
		return value;
	}
	
	@property
	CMechanism dup(CMechanism ret = null)
	{
		if(ret is null)
			ret = new CMechanism(Name);
		
		ret.Name = Name.dup;
		foreach(ii, stage; Stages)
			ret.Stages[ii] = stage.dup;
		
		ret.Externals = Externals.deep_dup();
			
		ret.InitCode = InitCode.dup;
		
		ret.PreStepCode = PreStepCode.dup;
		ret.PreStageCode = PreStageCode.dup;
		ret.States = States.deep_dup();
		ret.Globals = Globals.deep_dup();
		ret.Locals = Locals.deep_dup();
		ret.Constants = Constants.deep_dup();
		ret.Immutables = Immutables.deep_dup();
		ret.Thresholds = Thresholds.deep_dup();
		
		ret.NumEventSources = NumEventSources;
		
		return ret;
	}
	
	/* Pre-step is called only once per timestep, after the synaptic currents are taken care of but before the dynamics are solved.
	 */
	cstring PreStepCodeVal;
	
	/* Pre-stage is called only once per dt, before any of the stages are called.
	 */
	cstring PreStageCodeVal;
	
	/* Mechanism evaluation proceeds in stages. Each mechanism's stage N is run at the same time,
	 * and before stage N + 1. The suggested nature of operations that go in each stage is as follows:
	 * 0 - Initialize local variables
	 * 1 - Modify local variables
	 * 2 - Compute state derivatives
	 */
	cstring[3] Stages;
	cstring Name;
	
	/* Externals are value names that come from other mechanisms. */
	cstring[] Externals;
	
	/* The init function gets called after each value gets the default value set to it. Thus, most init
	 * functions should be empty OR set the state initial values given the globals
	 */
	cstring InitCodeVal;
	
	/* States are the dynamical states. They have a first derivative (referred to as state_name' inside the
	 * stage sources. You should never modify a state's value directly outside of a threshold. Or the init
	 * function. These values are unique for each neuron.
	 */
	CValue[] States;
	
	/* Globals are the non-dynamical states. You can use these as per-neuron parameters. 
	 * These values are unique for each neuron.
	 */
	CValue[] Globals;
	
	/* Locals are computed during every evaluation. Use these to communicate between mechanisms.
	 * These values are unique for each neuron.
	 */
	CValue[] Locals;
	
	/* Constants are neuron-type parameters. They are the same for each neuron.
	 */
	CValue[] Constants;
	
	/* Immutables are neuron-type parameters. They are the same for each neuron and, unlike constants, they cannot
	 * be changed after the kernel has been generated.
	 */
	CValue[] Immutables;
	
	/* Thresholds are used to provide instantaneous changes in state, with the associated resetting of the dt.
	 */
	SThreshold[] Thresholds;
	
	int NumEventSources = 0;
}

class CSynapse : CMechanism
{
	this(cstring name)
	{
		super(name);
	}
	
	mixin(AddMechFunc!("SynGlobal"));
	
	override
	bool IsDuplicateName(cstring name)
	{
		auto ret = super.IsDuplicateName(name);
		if(ret)
			return true;
		foreach(val; &AllSynGlobals)
		{
			if(val.Name == name)
				return true;
		}
		return false;
	}
	
	mixin(Prop!("cstring", "SynCode"));
	mixin(Prop!("cstring", "SynThreshCode"));
	
	void AddSynThreshold(cstring state, cstring condition, cstring source)
	{
		SSynThreshold thresh;
		thresh.State = state;
		thresh.Condition = condition;
		thresh.Source = source;
		
		SynThresholds ~= thresh;
	}
	
	int AllSynGlobals(scope int delegate(ref CValue value) dg)
	{
		foreach(val; SynGlobals)
		{
			if(int ret = dg(val))
				return ret;
		}
		return 0;
	}
	
	override
	CValue opIndex(cstring name)
	{
		/* TODO: LOL OPTIMIZE */
		foreach(val; &AllValues)
		{
			if(val.Name == name)
				return val;
		}
		
		foreach(val; &AllSynGlobals)
		{
			if(val.Name == name)
				return val;
		}
		
		throw new Exception("'" ~ Name.idup ~ "' does not have a '" ~ name.idup ~ "' value.");
	}
	
	alias CMechanism.dup dup;
	
	@property
	CSynapse dup(CSynapse ret = null)
	{
		if(ret is null)
			ret = new CSynapse(Name);
		
		super.dup(ret);
		
		ret.SynGlobals = SynGlobals.deep_dup();
		ret.SynThresholds = SynThresholds.deep_dup();
		ret.SynCode = SynCode.dup;
		ret.SynThreshCode = SynThreshCode.dup;
		
		return ret;
	}
	
	/* A value that every synapse has (like synaptic weight).
	 */
	CValue[] SynGlobals;
	
	cstring SynCodeVal;
	cstring SynThreshCodeVal;
	
	SSynThreshold[] SynThresholds;
}

struct SSynType
{
	CSynapse Synapse;
	int NumSynapses;
	cstring Prefix;
}

class CNeuronType
{
	this(cstring name)
	{
		Name = name;
	}
	
	/* Returns null if it isn't duplicate and the name of the containing mechanism if it is */
	cstring IsDuplicateName(cstring name)
	{
		auto old_mech = name in Values;
		if(old_mech !is null)
			return (*old_mech).Name;
		
		auto old_syn = name in SynGlobals;
		if(old_syn !is null)
			return (*old_syn).Name;
		
		return null;
	}
	
	void AddConnector(CConnector conn, bool no_dup = false)
	{
		assert(conn);
		if(!no_dup)
			conn = conn.dup;
		
		foreach(c; Connectors)
		{
			if(c.Name == conn.Name)
				throw new Exception("Connector '" ~ c.Name.idup ~ "' already exists in this neuron type.");
		}
		
		Connectors ~= conn;
	}
	
	void AddMechanism(CMechanism mech, cstring prefix = "", bool no_dup = false)
	{
		assert(mech);
		if(!no_dup)
			mech = mech.dup;
		foreach(val; &mech.AllValues)
		{
			auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
			auto mech_name = IsDuplicateName(name);
			if(mech_name !is null)
			{
				throw new Exception("'" ~ name.idup ~ "' has already been added by the '" ~ mech_name.idup ~ "' mechanism.");
			}

			Values[name] = mech;
		}
		
		NumEventSources += mech.NumEventSources;
			
		Mechanisms ~= mech;
		MechanismPrefixes ~= prefix;
	}
	
	void AddSynapse(CSynapse syn, int num_slots, cstring prefix = "", bool no_dup = false)
	{
		if(!no_dup)
			syn = syn.dup;
		AddMechanism(syn, prefix, true);
		foreach(val; &syn.AllSynGlobals)
		{
			auto name = prefix == "" ? val.Name : prefix ~ "_" ~ val.Name;
			auto mech_name = IsDuplicateName(name);
			if(mech_name !is null)
			{
				throw new Exception("'" ~ name.idup ~ "' has already been added by the '" ~ mech_name.idup ~ "' mechanism.");
			}
			
			SynGlobals[name] = syn;
		}
		SynapseTypes ~= SSynType(syn, num_slots, prefix);
	}
	
	@property
	int NumDestSynapses()
	{
		int ret = 0;
		foreach(type; SynapseTypes)
			ret += type.NumSynapses;
		
		return ret;
	}
	
	/* Double checks that each mechanism has its externals satisfied*/
	void VerifyExternals()
	{
		cstring error;
		foreach(mech; Mechanisms)
		{
			foreach(external; mech.Externals)
			{
				if((external in Values) is null)
				{
					error ~= "\n'" ~ external ~ "' from '" ~ mech.Name ~ "'.";
				}
			}
		}
		if(error.length)
			throw new Exception("Unreasolved externals in '" ~ Name.idup ~ "' neuron type." ~ error.idup);
	}
	
	/* Goes through all the states and returns the missing tolerance names */
	int MissingTolerances(scope int delegate(ref cstring name) dg)
	{
		outer: foreach(name, state; &AllStates)
		{
			auto tol_name = name ~ "_tol";
			foreach(val_name, _; &AllImmutables)
			{
				if(tol_name == val_name)
					continue outer;
			}
			foreach(val_name, _; &AllConstants)
			{
				if(tol_name == val_name)
					continue outer;
			}
			foreach(val_name, _; &AllGlobals)
			{
				if(tol_name == val_name)
					continue outer;
			}
			
			if(int ret = dg(tol_name))
				return ret;
		}
		return 0;
	}
	
	int AllSynGlobals(scope int delegate(ref cstring name, ref CValue value) dg)
	{
		foreach(syn_type; SynapseTypes)
		{
			foreach(val; &syn_type.Synapse.AllSynGlobals)
			{
				auto name = syn_type.Prefix == "" ? val.Name : syn_type.Prefix ~ "_" ~ val.Name;
				if(int ret = dg(name, val))
					return ret;
			}
		}
		return 0;
	}
	
	int AllImmutables(scope int delegate(ref cstring name, ref CValue value) dg)
	{
		foreach(ii, mech; Mechanisms)
		{
			foreach(val; mech.Immutables)
			{
				auto name = MechanismPrefixes[ii] == "" ? val.Name : MechanismPrefixes[ii] ~ "_" ~ val.Name;
				if(int ret = dg(name, val))
					return ret;
			}
		}
		return 0;
	}
	
	int AllStates(scope int delegate(ref cstring name, ref CValue value) dg)
	{
		foreach(ii, mech; Mechanisms)
		{
			foreach(val; mech.States)
			{
				auto name = MechanismPrefixes[ii] == "" ? val.Name : MechanismPrefixes[ii] ~ "_" ~ val.Name;
				if(int ret = dg(name, val))
					return ret;
			}
		}
		return 0;
	}
	
	/* Globals and states*/
	int AllNonLocals(scope int delegate(ref cstring name, ref CValue value) dg)
	{
		foreach(ii, mech; Mechanisms)
		{
			foreach(val; mech.States)
			{
				auto name = MechanismPrefixes[ii] == "" ? val.Name : MechanismPrefixes[ii] ~ "_" ~ val.Name;
				if(int ret = dg(name, val))
					return ret;
			}
			foreach(val; mech.Globals)
			{
				auto name = MechanismPrefixes[ii] == "" ? val.Name : MechanismPrefixes[ii] ~ "_" ~ val.Name;
				if(int ret = dg(name, val))
					return ret;
			}
		}
		return 0;
	}
	
	int AllGlobals(scope int delegate(ref cstring name, ref CValue value) dg)
	{
		foreach(ii, mech; Mechanisms)
		{
			foreach(val; mech.Globals)
			{
				auto name = MechanismPrefixes[ii] == "" ? val.Name : MechanismPrefixes[ii] ~ "_" ~ val.Name;
				if(int ret = dg(name, val))
					return ret;
			}
		}
		return 0;
	}
	
	int AllConstants(scope int delegate(ref cstring name, ref CValue value) dg)
	{
		foreach(ii, mech; Mechanisms)
		{
			foreach(val; mech.Constants)
			{
				auto name = MechanismPrefixes[ii] == "" ? val.Name : MechanismPrefixes[ii] ~ "_" ~ val.Name;
				if(int ret = dg(name, val))
					return ret;
			}
		}
		return 0;
	}
	
	int AllLocals(scope int delegate(ref cstring name, ref CValue value) dg)
	{
		foreach(ii, mech; Mechanisms)
		{
			foreach(val; mech.Locals)
			{
				auto name = MechanismPrefixes[ii] == "" ? val.Name : MechanismPrefixes[ii] ~ "_" ~ val.Name;
				if(int ret = dg(name, val))
					return ret;
			}
		}
		return 0;
	}
	
	/* Note that this returns the thresholds with all the strings modified appropriately with a prefix */
	int AllThresholds(scope int delegate(ref SThreshold thresh) dg)
	{
		foreach(ii, mech; Mechanisms)
		{
			auto prefix = MechanismPrefixes[ii];
			bool need_prefix = prefix != "";
			
			foreach(thresh; mech.Thresholds)
			{
				auto thresh2 = thresh;
				if(need_prefix)
				{
					thresh2.State = thresh2.State.dup;
					thresh2.Condition = thresh2.Condition.dup;
					thresh2.Source = thresh2.Source.dup;
					
					/* If the state name is one of the states of the mechanism, it gets a prefix...
					 * otherwise, it's external, and it gets nothing */
					foreach(state; &mech.AllStates)
					{
						if(state.Name == thresh2.State)
						{
							thresh2.State = prefix ~ "_" ~ thresh2.State;
							break;
						}
					}
					 
					foreach(val; &mech.AllValues)
					{
						auto name = val.Name;
						thresh2.Condition = thresh2.Condition.c_substitute(name, prefix ~ "_" ~ name);
						thresh2.Source = thresh2.Source.c_substitute(name, prefix ~ "_" ~ name);
					}
				}
				if(int ret = dg(thresh2))
					return ret;
			}
		}
		return 0;
	}
	
	/* Note that this returns the thresholds with all the strings modified appropriately with a prefix */
	int AllSynThresholdsEx(scope int delegate(ref SSynType type, ref SSynThreshold thresh) dg)
	{
		foreach(ii, syn_type; SynapseTypes)
		{
			auto prefix = syn_type.Prefix;
			bool need_prefix = prefix != "";
			auto syn = syn_type.Synapse;
			
			foreach(thresh; syn.SynThresholds)
			{
				auto thresh2 = thresh;
				if(need_prefix)
				{
					thresh2.State = thresh2.State.dup;
					thresh2.Condition = thresh2.Condition.dup;
					thresh2.Source = thresh2.Source.dup;
					
					/* If the state name is one of the states of the synapse, it gets a prefix...
					 * otherwise, it's external, and it gets nothing */
					foreach(state; &syn.AllStates)
					{
						if(state.Name == thresh2.State)
						{
							thresh2.State = prefix ~ "_" ~ thresh2.State;
							break;
						}
					}
					 
					foreach(val; &syn.AllValues)
					{
						auto name = val.Name;
						thresh2.Condition = thresh2.Condition.c_substitute(name, prefix ~ "_" ~ name);
						thresh2.Source = thresh2.Source.c_substitute(name, prefix ~ "_" ~ name);
					}
					
					foreach(val; &syn.AllSynGlobals)
					{
						auto name = val.Name;
						thresh2.Condition = thresh2.Condition.c_substitute(name, prefix ~ "_" ~ name);
						thresh2.Source = thresh2.Source.c_substitute(name, prefix ~ "_" ~ name);
					}
				}
				if(int ret = dg(syn_type, thresh2))
					return ret;
			}
		}
		return 0;
	}
	
	int AllSynThresholds(scope int delegate(ref SSynThreshold thresh) dg)
	{
		return AllSynThresholdsEx((ref SSynType type, ref SSynThreshold thresh) {return dg(thresh);});
	}
	
	/* This one, unlike AllThresholds returns the raw thresholds 
	 * TODO: Is this okay? */
	int AllEventSources(scope int delegate(ref SThreshold thresh) dg)
	{
		foreach(mech; Mechanisms)
		{
			foreach(thresh; mech.Thresholds)
			{
				if(thresh.IsEventSource)
				{
					if(int ret = dg(thresh))
						return ret;
				}
			}
		}
		return 0;
	}
	
	cstring GetEvalSource()
	{
		cstring ret;
		foreach(ii; range(3))
		{
			foreach(jj, mech; Mechanisms)
			{
				auto prefix = MechanismPrefixes[jj];
				bool need_prefix = prefix != "";
				
				if(mech.Stages[ii].length)
				{
					auto stage_src = mech.Stages[ii].dup;
					
					if(need_prefix)
					{
						foreach(val; &mech.AllValues)
						{
							auto name = val.Name;
							stage_src = stage_src.c_substitute(name, prefix ~ "_" ~ name);
						}
					}
					
					ret ~= "{\n" ~ stage_src ~ "\n}\n";
				}
				else if(ii == 2)
				{
					/* Generate a dummy stage that sets all the derivatives to 0 */
					foreach(val; &mech.AllStates)
					{
						auto name = need_prefix ? prefix ~ "_" ~ val.Name : val.Name;
						ret ~= "{\n";
						ret ~= name ~ "' = 0;";
						ret ~= "\n}\n";
					}
				}
			}
		}
		return ret;
	}
	
	private cstring GetFixedCode(cstring code, scope cstring delegate(CMechanism mech) mech_code_extractor)
	{
		cstring ret;
		if(code.length)
		{
			ret ~= "{\n" ~ code ~ "\n}\n";
		}
		foreach(ii, mech; Mechanisms)
		{
			auto mech_code = mech_code_extractor(mech);
			if(mech_code.length)
			{
				auto prefix = MechanismPrefixes[ii];
				auto src = mech_code.dup;
				if(prefix != "")
				{
					foreach(val; &mech.AllValues)
					{
						auto name = val.Name;
						src = src.c_substitute(name, prefix ~ "_" ~ name);
					}
				}
				ret ~= "{\n" ~ src ~ "\n}\n";
			}
		}
		return ret;
	}
	
	cstring GetPreStepSource()
	{
		return GetFixedCode(PreStepCode, (CMechanism mech) { return mech.PreStepCode; });
	}
	
	cstring GetPreStageSource()
	{
		return GetFixedCode(PreStageCode, (CMechanism mech) { return mech.PreStageCode; });
	}
	
	cstring GetInitSource()
	{
		return GetFixedCode(InitCode, (CMechanism mech) { return mech.InitCode; });
	}
	
	mixin(Prop!("cstring", "InitCode"));
	mixin(Prop!("cstring", "PreStageCode"));
	mixin(Prop!("cstring", "PreStepCode"));
	
	CConnector[] Connectors;
	CMechanism[char[]] Values;
	CMechanism[] Mechanisms;
	cstring[] MechanismPrefixes;
	CSynapse[char[]] SynGlobals;
	SSynType[] SynapseTypes;
	cstring Name;
	cstring InitCodeVal;
	cstring PreStepCodeVal;
	cstring PreStageCodeVal;
	
	/* Length of the random state: 0-4
	 * 0 is no rand required */
	int RandLen = 0;
	int RecordLength = 1000;
	int RecordRate = 0;
	int CircBufferSize = 20;
	int NumEventSources = 0;
	
	double MinDt = 0.01;
	
	int NumSrcSynapses = 0;
}

class CConnector
{
	this(cstring name)
	{
		Name = name;
	}
	
	@property
	CConnector dup(CConnector ret = null)
	{
		if(ret is null)
			ret = new CConnector(Name);
		
		ret.Code = Code.dup;
		ret.Name = Name.dup;
		ret.Constants = Constants.deep_dup();
		
		return ret;
	}
	
	CValue AddConstant(cstring name)
	{
		if(!IsValidName(name))
			throw new Exception("The name '" ~ name.idup ~ "' is reserved.");
		if(IsDuplicateName(name))
			throw new Exception("'" ~ name.idup ~ "' already exists in connector '" ~ Name.idup ~ "'.");
		auto val = new CValue(name);				
		Constants ~= val;
		return val;
	}
	
	bool IsDuplicateName(cstring name)
	{
		foreach(val; Constants)
		{
			if(val.Name == name)
				return true;
		}
		return false;
	}
	
	void SetCode(cstring code)
	{
		Code = code;
	}
	
	CValue[] Constants;
	cstring Code;
	cstring Name;
}

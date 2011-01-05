module celeme.frontend;

import celeme.util;

import tango.core.Array;
import tango.io.Stdout;

/* A front end value, primarily stores the name and default value */
class CValue
{
	this(char[] name)
	{
		Name = name;
	}
	
	double opAssign(double val)
	{
		return Value = val;
	}
	
	CValue dup(CValue ret = null)
	{
		if(ret is null)
			ret = new CValue(Name.dup);

		ret.Name = Name.dup;
		ret.Value = Value;
		ret.ReadOnly = ReadOnly;
		ret.Tolerance = Tolerance;
		
		return ret;
	}
	
	char[] Name;
	double Value = 0;
	bool ReadOnly = false;
	double Tolerance = 0.1;
}

bool IsValidName(char[] name)
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
	char[] State;
	char[] Condition;
	char[] Source;
	bool IsEventSource = false;
	bool ResetTime = false;
	
	SThreshold dup()
	{
		return SThreshold(State.dup, Condition.dup, Source.dup, IsEventSource, ResetTime);
	}
}

char[] AddMechFunc(char[] name)()
{
	return 
	`CValue Add` ~ name ~ `(char[] name)
		{
			if(!IsValidName(name))
				throw new Exception("The name '" ~ name ~ "' is reserved.");
			if(IsDuplicateName(name))
				throw new Exception("'" ~ name ~ "' already exists in mechanism '" ~ Name ~ "'.");
			auto val = new CValue(name);				
			` ~ name ~ `s ~= val;
			return val;
		}
	`;
}

class CMechanism
{
	this(char[] name)
	{
		Name = name;
	}
	
	mixin(AddMechFunc!("State"));
	mixin(AddMechFunc!("Local"));
	mixin(AddMechFunc!("Global"));
	mixin(AddMechFunc!("Constant"));
	
	void AddExternal(char[] name)
	{
		if(!IsValidName(name))
			throw new Exception("The name '" ~ name ~ "' is reserved.");
		if(IsDuplicateName(name))
			throw new Exception("'" ~ name ~ "' exists in mechanism '" ~ Name ~ "'.");
		Externals ~= name;
	}
	
	bool IsDuplicateName(char[] name)
	{
		foreach(val; &AllValues)
		{
			if(val.Name == name)
				return true;
		}
		return false;
	}
	
	int AllValues(int delegate(ref CValue value) dg)
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
		return 0;
	}
	
	int AllStates(int delegate(ref CValue value) dg)
	{
		foreach(val; States)
		{
			if(int ret = dg(val))
				return ret;
		}
		return 0;
	}
	
	void SetStage(int stage, char[] source)
	{
		assert(stage >= 0, "stage must be greater than or equal to 0");
		assert(stage < 3, "stage must be less than 3");
		
		Stages[stage] = source;
	}
	
	void AddThreshold(char[] state, char[] condition, char[] source, bool event_source = false, bool resetting = false)
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
	
	void SetInitCode(char[] source)
	{
		Init = source;
	}
	
	void SetPreStage(char[] pre_stage)
	{
		PreStage = pre_stage;
	}
	
	CValue opIndex(char[] name)
	{
		/* TODO: LOL OPTIMIZE */
		foreach(val; &AllValues)
		{
			if(val.Name == name)
				return val;
		}
		
		throw new Exception("'" ~ Name ~ "' does not have a '" ~ name ~ "' value.");
	}
	
	CValue opIndexAssign(double val, char[] name)
	{
		auto value = opIndex(name);
		value = val;
		
		return value;
	}
	
	CMechanism dup(CMechanism ret = null)
	{
		if(ret is null)
			ret = new CMechanism(Name);
		
		ret.Name = Name.dup;
		foreach(ii, stage; Stages)
			ret.Stages[ii] = stage.dup;
		
		ret.Externals = Externals.deep_dup();
			
		ret.Init = Init.dup;
		
		ret.PreStage = PreStage.dup;
		ret.States = States.deep_dup();
		ret.Globals = Globals.deep_dup();
		ret.Locals = Locals.deep_dup();
		ret.Constants = Constants.deep_dup();
		ret.Thresholds = Thresholds.deep_dup();
		
		ret.NumEventSources = NumEventSources;
		
		return ret;
	}
	
	/* Pre-stage is called only once per dt, before any of the stages are called.
	 */
	char[] PreStage;
	
	/* Mechanism evaluation proceeds in stages. Each mechanism's stage N is run at the same time,
	 * and before stage N + 1. The suggested nature of operations that go in each stage is as follows:
	 * 0 - Initialize local variables
	 * 1 - Modify local variables
	 * 2 - Compute state derivatives
	 */
	char[][3] Stages;
	char[] Name;
	
	/* Externals are value names that come from other mechanisms. */
	char[][] Externals;
	
	/* The init function gets called after each value gets the default value set to it. Thus, most init
	 * functions should be empty OR set the state initial values given the globals
	 */
	char[] Init;
	
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
	
	/* Thresholds are used to provide instantaneous changes in state, with the associated resetting of the dt.
	 */
	SThreshold[] Thresholds;
	
	int NumEventSources = 0;
}

class CSynapse : CMechanism
{
	this(char[] name)
	{
		super(name);
	}
	
	mixin(AddMechFunc!("SynGlobal"));
	
	bool IsDuplicateName(char[] name)
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
	
	void SetSynCode(char[] code)
	{
		SynCode = code;
	}
	
	int AllSynGlobals(int delegate(ref CValue value) dg)
	{
		foreach(val; SynGlobals)
		{
			if(int ret = dg(val))
				return ret;
		}
		return 0;
	}
	
	CValue opIndex(char[] name)
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
		
		throw new Exception("'" ~ Name ~ "' does not have a '" ~ name ~ "' value.");
	}
	
	CSynapse dup(CSynapse ret = null)
	{
		if(ret is null)
			ret = new CSynapse(Name);
		
		super.dup(ret);
		
		ret.SynGlobals = SynGlobals.deep_dup();
		ret.SynCode = SynCode.dup;
		
		return ret;
	}
	
	/* A value that every synapse has (like synaptic weight).
	 */
	CValue[] SynGlobals;
	
	char[] SynCode;
}

struct SSynType
{
	CSynapse Synapse;
	int NumSynapses;
	char[] Prefix;
}

class CNeuronType
{
	this(char[] name)
	{
		Name = name;
	}
	
	/* Returns null if it isn't duplicate and the name of the containing mechanism if it is */
	char[] IsDuplicateName(char[] name)
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
				throw new Exception("Connector '" ~ c.Name ~ "' already exists in this neuron type.");
		}
		
		Connectors ~= conn;
	}
	
	void AddMechanism(CMechanism mech, char[] prefix = "", bool no_dup = false)
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
				throw new Exception("'" ~ name ~ "' has already been added by the '" ~ mech_name ~ "' mechanism.");
			}

			Values[name] = mech;
		}
		
		NumEventSources += mech.NumEventSources;
			
		Mechanisms ~= mech;
		MechanismPrefixes ~= prefix;
	}
	
	void AddSynapse(CSynapse syn, int num_slots, char[] prefix = "", bool no_dup = false)
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
				throw new Exception("'" ~ name ~ "' has already been added by the '" ~ mech_name ~ "' mechanism.");
			}
			
			SynGlobals[name] = syn;
		}
		SynapseTypes ~= SSynType(syn, num_slots, prefix);
	}
	
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
		char[] error;
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
			throw new Exception("Unreasolved externals in '" ~ Name ~ "' neuron type." ~ error);
	}
	
	int AllSynGlobals(int delegate(ref char[] name, ref CValue value) dg)
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
	
	int AllStates(int delegate(ref char[] name, ref CValue value) dg)
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
	
	/* I.e. all globals */
	int AllNonLocals(int delegate(ref char[] name, ref CValue value) dg)
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
	
	int AllConstants(int delegate(ref char[] name, ref CValue value) dg)
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
	
	int AllLocals(int delegate(ref char[] name, ref CValue value) dg)
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
	int AllThresholds(int delegate(ref SThreshold thresh) dg)
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
	
	/* This one, unlike AllThresholds returns the raw thresholds 
	 * TODO: Is this okay? */
	int AllEventSources(int delegate(ref SThreshold thresh) dg)
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
	
	char[] GetEvalSource()
	{
		char[] ret;
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
	
	char[] GetPreStageSource()
	{
		char[] ret;
		foreach(ii, mech; Mechanisms)
		{
			if(mech.PreStage.length)
			{
				auto prefix = MechanismPrefixes[ii];
				auto pre_stage_src = mech.PreStage.dup;
				if(prefix != "")
				{
					foreach(val; &mech.AllValues)
					{
						auto name = val.Name;
						pre_stage_src = pre_stage_src.c_substitute(name, prefix ~ "_" ~ name);
					}
				}
				ret ~= "{\n" ~ pre_stage_src ~ "\n}\n";
			}
		}
		return ret;
	}
	
	char[] GetInitSource()
	{
		char[] ret;
		if(InitCode.length)
		{
			ret ~= "{\n" ~ InitCode ~ "\n}\n";
		}
		foreach(ii, mech; Mechanisms)
		{
			if(mech.Init.length)
			{
				auto prefix = MechanismPrefixes[ii];
				auto init_src = mech.Init.dup;
				if(prefix != "")
				{
					foreach(val; &mech.AllValues)
					{
						auto name = val.Name;
						init_src = init_src.c_substitute(name, prefix ~ "_" ~ name);
					}
				}
				ret ~= "{\n" ~ init_src ~ "\n}\n";
			}
		}
		return ret;
	}
	
	void SetInitCode(char[] code)
	{
		InitCode = code;
	}
	
	CConnector[] Connectors;
	CMechanism[char[]] Values;
	CMechanism[] Mechanisms;
	char[][] MechanismPrefixes;
	CSynapse[char[]] SynGlobals;
	SSynType[] SynapseTypes;
	char[] Name;
	char[] InitCode;
	
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
	this(char[] name)
	{
		Name = name;
	}
	
	CConnector dup(CConnector ret = null)
	{
		if(ret is null)
			ret = new CConnector(Name);
		
		ret.Code = Code.dup;
		ret.Name = Name.dup;
		ret.Constants = Constants.deep_dup();
		
		return ret;
	}
	
	CValue AddConstant(char[] name)
	{
		if(!IsValidName(name))
			throw new Exception("The name '" ~ name ~ "' is reserved.");
		if(IsDuplicateName(name))
			throw new Exception("'" ~ name ~ "' already exists in connector '" ~ Name ~ "'.");
		auto val = new CValue(name);				
		Constants ~= val;
		return val;
	}
	
	bool IsDuplicateName(char[] name)
	{
		foreach(val; Constants)
		{
			if(val.Name == name)
				return true;
		}
		return false;
	}
	
	void SetCode(char[] code)
	{
		Code = code;
	}
	
	CValue[] Constants;
	char[] Code;
	char[] Name;
}

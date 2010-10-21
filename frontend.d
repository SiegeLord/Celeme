module frontend;

import tango.core.Array;

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
	
	char[] Name;
	double Value = 0;
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
}

class CMechanism
{
	this(char[] name)
	{
		Name = name;
	}
	
	static char[] AddFunc(char[] name)()
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
	
	mixin(AddFunc!("State"));
	mixin(AddFunc!("Local"));
	mixin(AddFunc!("Global"));
	mixin(AddFunc!("Constant"));
	
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
		assert(stage >= 0, "stage must be between positive");
		assert(stage < 3, "stage must be less than 3");
		
		Stages[stage] = source;
	}
	
	/* TODO: think about non-resetting thresholds too */
	void AddThreshold(char[] state, char[] condition, char[] source, bool event_source = false)
	{
		if(!IsDuplicateName(state))
			throw new Exception("'" ~ state ~ "' does not exist in '" ~ Name ~ "'.");
		SThreshold thresh;
		thresh.State = state;
		thresh.Condition = condition;
		thresh.Source = source;
		thresh.IsEventSource = event_source;
		
		if(event_source)
			NumEventSources++;
		
		Thresholds ~= thresh;
	}
	
	void SetInitFunction(char[] source)
	{
		Init = source;
	}
	
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
	bool IsEventSink = false; /* TODO: Possibly WRONG! */
}

struct SSynType
{
	CMechanism Mechanism;
	int NumSynapses;
}

class CNeuronType
{
	this(char[] name)
	{
		Name = name;
	}
	
	void AddMechanism(CMechanism mech)
	{
		assert(mech);
		foreach(val; &mech.AllValues)
		{
			auto old_val = val.Name in Values;
			if(old_val !is null)
			{
				throw new Exception("'" ~ val.Name ~ "' has already been added by the '" ~ (*old_val).Name ~ "' mechanism.");
			}
			Values[val.Name] = mech;
		}
		
		NumEventSources += mech.NumEventSources;
			
		Mechanisms ~= mech;
	}
	
	void AddSynapse(CMechanism mech, int num_slots)
	{
		if(!mech.IsEventSink)
			throw new Exception("'" ~ mech.Name ~ "' cannot accept synapses.");
		AddMechanism(mech);
		SynapseTypes ~= SSynType(mech, num_slots);
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
					if(error.length == 0)
						error ~= "Unresolved externals:";
					error ~= "\n'" ~ external ~ "' from '" ~ mech.Name ~ "'.";
				}
			}
		}
		if(error.length)
			throw new Exception(error);
	}
	
	int AllStates(int delegate(ref CValue value) dg)
	{
		foreach(mech; Mechanisms)
		{
			foreach(state; mech.States)
			{
				if(int ret = dg(state))
					return ret;
			}
		}
		return 0;
	}
	
	/* I.e. all globals */
	int AllNonLocals(int delegate(ref CValue value) dg)
	{
		foreach(mech; Mechanisms)
		{
			foreach(val; mech.States)
			{
				if(int ret = dg(val))
					return ret;
			}
			foreach(val; mech.Globals)
			{
				if(int ret = dg(val))
					return ret;
			}
		}
		return 0;
	}
	
	int AllConstants(int delegate(ref CValue value) dg)
	{
		foreach(mech; Mechanisms)
		{
			foreach(val; mech.Constants)
			{
				if(int ret = dg(val))
					return ret;
			}
		}
		return 0;
	}
	
	int AllLocals(int delegate(ref CValue value) dg)
	{
		foreach(mech; Mechanisms)
		{
			foreach(val; mech.Locals)
			{
				if(int ret = dg(val))
					return ret;
			}
		}
		return 0;
	}
	
	int AllThresholds(int delegate(ref SThreshold thresh) dg)
	{
		foreach(mech; Mechanisms)
		{
			foreach(thresh; mech.Thresholds)
			{
				if(int ret = dg(thresh))
					return ret;
			}
		}
		return 0;
	}
	
	char[] GetEvalSource()
	{
		char[] ret;
		for(int ii = 0; ii < 3; ii++)
		{
			foreach(mech; Mechanisms)
			{
				if(mech.Stages[ii].length)
					ret ~= "{\n" ~ mech.Stages[ii] ~ "\n}\n";
				else if(ii == 2)
				{
					/* Generate a dummy stage that sets all the derivatives to 0 */
					foreach(state; &mech.AllStates)
					{
						ret ~= "{\n";
						ret ~= state.Name ~ "' = 0;";
						ret ~= "\n}\n";
					}
				}
			}
		}
		return ret;
	}
	
	char[] GetInitSource()
	{
		char[] ret;
		foreach(mech; Mechanisms)
		{
			if(mech.Init.length)
				ret ~= "{\n" ~ mech.Init ~ "\n}\n";
		}
		return ret;
	}
	
	CMechanism[char[]] Values;
	CMechanism[] Mechanisms;
	SSynType[] SynapseTypes;
	char[] Name;
	
	int RecordLength = 1000;
	int CircBufferSize = 20;
	int NumEventSources = 0;
	
	int NumSrcSynapses = 10;
}

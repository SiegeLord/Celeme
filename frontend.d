module frontend;

import tango.core.Array;

class CValue
{
	this(char[] name, CMechanism mech)
	{
		assert(mech);
		Name = name;
		Mechanism = mech;
	}
	
	double opAssign(double val)
	{
		return Value = val;
	}
	
	CMechanism Mechanism;
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
				auto val = new CValue(name, this);				
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
	
	void SetStage(int stage, char[] source)
	{
		assert(stage >= 0, "stage must be between positive");
		assert(stage < 3, "stage must be less than 3");
		
		Stages[stage] = source;
	}	
	
	char[][3] Stages;
	char[] Name;
	char[][] Externals;
	CValue[] States;
	CValue[] Globals;
	CValue[] Locals;
	CValue[] Constants;
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
		
		Mechanisms ~= mech;
	}
	
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
	
	char[] GetEvalSource()
	{
		char[] ret;
		for(int ii = 0; ii < 3; ii++)
		{
			foreach(mech; Mechanisms)
			{
				if(mech.Stages[ii].length)
					ret ~= "{\n" ~ mech.Stages[ii] ~ "}\n";
			}
		}
		return ret;
	}
	
	CMechanism[char[]] Values;
	CMechanism[] Mechanisms;
	char[] Name;
}

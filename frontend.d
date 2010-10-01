module frontend;

import tango.core.Array;

class CValue
{
	this(char[] name, CMechanism mech)
	{
		Name = name;
		Mechanism = mech;
	}
	
	double opAssign(double val)
	{
		return Value = val;
	}
	
	static bool EqualsPred(CValue a, CValue b)
	{
		return a.Name == b.Name;
	}
	
	CMechanism Mechanism;
	char[] Name;
	double Value = 0;
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
				auto val = new CValue(name, this);
				if(` ~ name ~ `s.find(val, &CValue.EqualsPred) != ` ~ name ~ `s.length)
					throw new Exception("'" ~ name ~ "' already exists in mechanism '" ~ Name ~ "'.");
				` ~ name ~ `s ~= val;
				return val;
			}
		`;
	}
	
	mixin(AddFunc!("State"));
	mixin(AddFunc!("Local"));
	mixin(AddFunc!("Global"));
	mixin(AddFunc!("Parameter"));
	
	void AddExternal(char[] name)
	{
		Externals ~= name;
	}
	
	int AllExportedValues(int delegate(ref CValue value) dg)
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
		return 0;
	}
	
	char[] Name;
	char[][] Externals;
	CValue[] States;
	CValue[] Globals;
	CValue[] Locals;
	CValue[] Parameters;
}

class CNeuronType
{
	this(char[] name)
	{
		Name = name;
	}
	void AddMechanism(CMechanism mech)
	{
		foreach(val; &mech.AllExportedValues)
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
	
	CMechanism[char[]] Values;
	CMechanism[] Mechanisms;
	char[] Name;
}

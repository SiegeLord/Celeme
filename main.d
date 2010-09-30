module main;

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
	
	CValue AddState(char[] name)
	{
		auto state = new CValue(name, this);
		if(States.find(state, &CValue.EqualsPred) != States.length)
			throw new Exception("'" ~ name ~ "' already exists in mechanism '" ~ Name ~ "'.");
		States ~= state;
		return state;
	}
	
	CValue AddLocal(char[] name)
	{
		auto local = new CValue(name, this);
		if(Locals.find(local, &CValue.EqualsPred) != Locals.length)
			throw new Exception("'" ~ name ~ "' already exists in mechanism '" ~ Name ~ "'.");
		Locals ~= local;
		return local;
	}
	
	CValue AddParameter(char[] name)
	{
		auto param = new CValue(name, this);
		if(Parameters.find(param, &CValue.EqualsPred) != Parameters.length)
			throw new Exception("'" ~ name ~ "' already exists in mechanism '" ~ Name ~ "'.");
		Parameters ~= param;
		return param;
	}
	
	void AddExternal(char[] name)
	{
		Externals ~= name;
	}
	
	private int AllExportedValuesIterator(int delegate(ref CValue value) dg)
	{
		foreach(state; States)
		{
			if(int ret = dg(state))
				return ret;
		}
		foreach(local; Locals)
		{
			if(int ret = dg(local))
				return ret;
		}	
		return 0;
	}
	
	int delegate(int delegate(ref CValue value) dg) AllExportedValues()
	{
		return &AllExportedValuesIterator;
	}
	
	char[] Name;
	char[][] Externals;
	CValue[] States;
	CValue[] Locals;
	CValue[] Parameters;
}

class CNeuronType
{
	void AddMechanism(CMechanism mech)
	{
		foreach(val; mech.AllExportedValues)
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
	
	CMechanism[char[]] Values;
	CMechanism[] Mechanisms;
}

void main()
{
	auto type = new CNeuronType();
	auto iz_mech = new CMechanism("IzMech");
	auto i_clamp = new CMechanism("IClamp");
	iz_mech.AddState("V") = 0;
	iz_mech.AddState("u") = 5;
	iz_mech.AddLocal("I");
	
	i_clamp.AddExternal("I");
	
	type.AddMechanism(iz_mech);
	type.AddMechanism(i_clamp);
	type.VerifyExternals();
}

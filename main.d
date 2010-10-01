module main;

import frontend;
import clgenerator;

void main()
{
	auto type = new CNeuronType("TestNeuron");
	auto iz_mech = new CMechanism("IzMech");
	auto i_clamp = new CMechanism("IClamp");
	iz_mech.AddState("V") = 0;
	iz_mech.AddState("u") = 5;
	iz_mech.AddLocal("I");
	
	i_clamp.AddExternal("I");
	
	type.AddMechanism(iz_mech);
	type.AddMechanism(i_clamp);
	
	auto model = new CModel();
	model.AddNeuronGroup(type, 5);
	model.Generate();
}

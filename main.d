module main;

import frontend;
import clgenerator;

import tango.io.Stdout;

void main()
{
	auto type = new CNeuronType("TestNeuron");
	auto iz_mech = new CMechanism("IzMech");
	auto i_clamp = new CMechanism("IClamp");
	iz_mech.AddState("V") = 0;
	iz_mech.AddState("u") = 5;
	iz_mech.AddLocal("I");
	iz_mech.SetStage(0,
`I = 0;`
);
	iz_mech.SetStage(2, 
`V' = (0.04f * V + 5) * V + 140 - u + I;
u' = 0.02f * (0.2f * V - u);`
);
	iz_mech.AddThreshold("V", "> 0",
`V = -65;
u += 8;`	
);

	iz_mech.SetInitFunction(
`V = 0;
u = 0;`
);

	i_clamp.AddExternal("I");
	i_clamp.AddConstant("amp");
	i_clamp.SetStage(0,
`I = amp;`
);
	
	type.AddMechanism(iz_mech);
	type.AddMechanism(i_clamp);
	
	auto model = new CModel();
	model.AddNeuronGroup(type, 5);
	model.Generate();
	
	model["TestNeuron"]["u"] = 7;
	Stdout.formatln("u = {}", model["TestNeuron"]["u"]);
}

module main;

import frontend;
import clmodel;
import clcore;
import pl = plplot;

import tango.io.Stdout;

void main()
{
	auto iz_mech = new CMechanism("IzMech");
	iz_mech.AddState("V") = -65;
	iz_mech.AddState("u") = 5;
	iz_mech.AddLocal("I");
	iz_mech.SetStage(0, "I = 0;");
	iz_mech.SetStage(2, "V' = (0.04f * V + 5) * V + 140 - u + I; u' = 0.02f * (0.2f * V - u);");
	iz_mech.AddThreshold("V", "> 0", "V = -65; u += 8;", true);
	iz_mech.SetInitFunction(`u = 0;`);

	auto i_clamp = new CMechanism("IClamp");
	i_clamp.AddExternal("I");
	i_clamp.AddConstant("amp");
	i_clamp.SetStage(1, "I += amp; if(i == 1) { I += 2; }");
	
	auto glu_syn = new CSynapse("GluSyn");
	glu_syn.AddConstant("gsyn") = 0.1;
	glu_syn.AddConstant("tau") = 5;
	glu_syn.AddState("s");
	glu_syn.SetStage(1, "I += s;");
	glu_syn.SetStage(2, "s' = -s / tau;");
	glu_syn.SetSynCode("s += gsyn;");
	
	auto type = new CNeuronType("TestNeuron");
	type.AddMechanism(iz_mech);
	type.AddMechanism(i_clamp);
	type.AddSynapse(glu_syn, 10);
	
	auto core = new CCLCore(false);
	
	auto model = new CModel(core);
	
	type.CircBufferSize = 5;
	type.NumSrcSynapses = 10;
	
	model.AddNeuronGroup(type, 5);
	model.Generate();
	Stdout(model.Source).nl;
	
//	model["TestNeuron"]["u"] = 7;
//	Stdout.formatln("u = {}", model["TestNeuron"]["u"]);
	
	model["TestNeuron"]["amp"] = 20;
	
	auto v_rec1 = model["TestNeuron"].Record(0, "V");
	auto v_rec2 = model["TestNeuron"].Record(1, "V");
	
	int tstop = 100;
	model.Run(tstop);
	
	model.Shutdown();
	core.Shutdown();
	
	//if(false)
	{
		pl.Init("wxwidgets", [0, 0, 0]);
		pl.SetColor(1, [0, 255, 0]);
		pl.ChooseColor(1);
		pl.SetEnvironment(0, tstop, -80, 20, 0, 0);
		pl.SetLabels("Time (ms)", "Voltage (mV)", "");
		
		pl.SetColor(2, [255, 128, 128]);
		pl.ChooseColor(2);
		pl.PlotLine(v_rec1.T, v_rec1.Data);
		
		pl.SetColor(3, [128, 128, 255]);
		pl.ChooseColor(3);
		pl.PlotLine(v_rec2.T, v_rec2.Data);
		
		pl.End();
	}
}

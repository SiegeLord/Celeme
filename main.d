module main;

import frontend;
import clmodel;
import clcore;
import pl = plplot;

import tango.io.Stdout;

void main()
{
	auto type = new CNeuronType("TestNeuron");
	auto iz_mech = new CMechanism("IzMech");
	auto i_clamp = new CMechanism("IClamp");
	iz_mech.AddState("V") = -65;
	iz_mech.AddState("u") = 5;
	iz_mech.AddLocal("I");
	iz_mech.SetStage(0, "I = 0;");
	iz_mech.SetStage(2, "V' = (0.04f * V + 5) * V + 140 - u + I; u' = 0.02f * (0.2f * V - u);");
	iz_mech.AddThreshold("V", "> 0", "V = -65; u += 8;", true);

	iz_mech.SetInitFunction(`u = 0;`);

	i_clamp.AddExternal("I");
	i_clamp.AddConstant("amp");
	i_clamp.SetStage(0, "I = amp; if(i == 1) { I = amp + 1; }");
	
	type.AddMechanism(iz_mech);
	type.AddMechanism(i_clamp);
	
	auto core = new CCLCore(false, false);
	
	auto model = new CModel(core);
	
	type.CircBufferSize = 5;
	model.AddNeuronGroup(type, 5);
	model.Generate();
	//Stdout(model.Source).nl;
	
//	model["TestNeuron"]["u"] = 7;
//	Stdout.formatln("u = {}", model["TestNeuron"]["u"]);
	
	model["TestNeuron"]["amp"] = 10;
	
	auto v_rec1 = model["TestNeuron"].Record(0, "V");
	auto v_rec2 = model["TestNeuron"].Record(1, "V");
	
	
	int tstop = 100;
	model.Run(tstop);
	
	/*foreach(ii, t; v_rec1.T)
	{
		Stdout.formatln("{:5}\t{:5}", t, v_rec1.Data[ii]);
	}
	
	Stdout.nl;
	
	foreach(ii, t; v_rec2.T)
	{
		Stdout.formatln("{:5}\t{:5}", t, v_rec2.Data[ii]);
	}*/
	
	
	
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

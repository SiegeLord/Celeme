module main;

import frontend;
import clmodel;
import clcore;
import pl = plplot;

import tango.io.Stdout;

void main()
{
	auto iz_mech = new CMechanism("IzMech");
	with(iz_mech)
	{
		AddState("V") = -65;
		AddState("u") = -5;
		AddLocal("I");
		SetStage(0, "I = 0;");
		SetStage(2, "V' = (0.04f * V + 5) * V + 140 - u + I; u' = 0.02f * (0.2f * V - u);");
		AddThreshold("V", "> 0", "V = -65; u += 8;", 5);
	}

	auto i_clamp = new CMechanism("IClamp");
	with(i_clamp)
	{
		AddExternal("I");
		AddConstant("amp");
		SetStage(1, "if(i == 1) { I += 0; } else { I += amp; }");
	}
	
	auto glu_syn = new CSynapse("GluSyn");
	with(glu_syn)
	{
		AddConstant("gsyn") = 11;
		AddConstant("tau") = 5;
		AddState("s");
		SetStage(1, "I += s;");
		SetStage(2, "s' = -s / tau;");
		SetSynCode("s += gsyn;");
	}
	
	auto type = new CNeuronType("TestNeuron");
	with(type)
	{
		AddMechanism(iz_mech);
		AddMechanism(i_clamp);
		AddSynapse(glu_syn, 10);
		/*SetInitCode(
		"
		if(i == 0)
		{
			dest_syn_buffer[0].s0 = 1;
			dest_syn_buffer[0].s1 = 0;
		}");*/
	}
	
	auto core = new CCLCore(false);
	
	auto model = new CCLModel(core);
	
	type.CircBufferSize = 5;
	type.NumSrcSynapses = 10;
	
	model.AddNeuronGroup(type, 2);
	model.Generate();
	//Stdout(model.Source).nl;
	
//	model["TestNeuron"]["u"] = 7;
//	Stdout.formatln("u = {}", model["TestNeuron"]["u"]);
	
	model["TestNeuron"]["amp"] = 20;
	
	model["TestNeuron"].ConnectTo(0, 0, 0, 1, 0);
	model["TestNeuron"].ConnectTo(1, 0, 0, 0, 0);
	
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

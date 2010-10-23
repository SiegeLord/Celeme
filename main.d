module main;

import celeme.celeme;
import pl = plplot;

import tango.time.StopWatch;
import tango.io.Stdout;

void main()
{
	StopWatch timer;
	
	timer.start;
	
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
	
	auto iz_mech2 = new CMechanism("IzMech2");
	with(iz_mech2)
	{
		AddState("V") = -65;
		AddState("u") = -5;
		AddLocal("I");
		SetStage(0, "I = 0;");
		SetStage(2, "V' = (0.04f * V + 5) * V + 140 - u + I; u' = 0.02f * (0.2f * V - u);");
		AddThreshold("V", "> 0", "V = -50; u += 2;", 5);
	}

	auto i_clamp = new CMechanism("IClamp");
	with(i_clamp)
	{
		AddExternal("I");
		AddConstant("amp");
		SetStage(1, "if(i == 1) { I += amp + 5; } else { I += amp; }");
	}
	
	auto exp_syn = new CSynapse("ExpSyn");
	with(exp_syn)
	{
		AddConstant("gsyn") = 0.1;
		AddConstant("tau") = 5;
		AddConstant("E") = 0;
		AddExternal("V");
		AddState("s");
		SetStage(1, "I += s * (E - V);");
		SetStage(2, "s' = -s / tau;");
		SetSynCode("s += gsyn;");
	}
	
	auto regular = new CNeuronType("Regular");
	with(regular)
	{
		AddMechanism(iz_mech);
		AddMechanism(i_clamp);
		AddSynapse(exp_syn, 10, "glu");
		AddSynapse(exp_syn, 10, "gaba");
	}
	
	auto burster = new CNeuronType("Burster");
	with(burster)
	{
		AddMechanism(iz_mech2);
		AddMechanism(i_clamp);
		AddSynapse(exp_syn, 10, "glu");
		AddSynapse(exp_syn, 10, "gaba");
	}
	
	auto core = new CCLCore(false);
	
	auto model = new CCLModel(core);
	
	regular.CircBufferSize = 5;
	regular.NumSrcSynapses = 10;
	burster.CircBufferSize = 5;
	burster.NumSrcSynapses = 10;
	
	model.AddNeuronGroup(regular, 1000);
	model.AddNeuronGroup(burster, 1000);
	
	Stdout.formatln("Specify time: {}", timer.stop);
	timer.start;
	
	model.Generate();
	
	Stdout.formatln("Generating time: {}", timer.stop);
	timer.start;
	
	//Stdout(model.Source).nl;
	
//	model["Regular"]["u"] = 7;
//	Stdout.formatln("u = {}", model["Regular"]["u"]);

	model["Burster"]["glu_E"] = 0;
	model["Regular"]["glu_E"] = 0;
	model["Burster"]["gaba_E"] = -80;
	model["Regular"]["gaba_E"] = -80;
	
	model["Regular"]["amp"] = 0;
	model["Burster"]["amp"] = 10;
	model["Regular"]["glu_gsyn"] = 0.03;
	model["Regular"]["gaba_gsyn"] = 0.5;
	
	model["Burster"].ConnectTo(0, 0, 0, 0, 0);
	model["Burster"].ConnectTo(1, 0, 0, 0, 10);
//	model["Regular"].ConnectTo(1, 0, 0, 0, 0);
	
	bool record = true;
	CRecorder v_rec1;
	CRecorder v_rec2;
	if(record)
	{
		v_rec1 = model["Regular"].Record(0, "V");
		v_rec2 = model["Burster"].Record(1, "V");
	}
	
	Stdout.formatln("Init time: {}", timer.stop);
	timer.start;
	
	int tstop = 2000;
	model.Run(tstop, 64, 64);
	
	Stdout.formatln("Run time: {}", timer.stop);
	
	model.Shutdown();
	core.Shutdown();
	
	if(record)
	if(false)
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

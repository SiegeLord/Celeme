module main;

import frontend;
import clmodel;
import clcore;
import recorder;
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
	
	auto glu_syn = new CSynapse("GluSyn");
	with(glu_syn)
	{
		AddConstant("gsyn") = 0.1;
		AddConstant("tau") = 5;
		AddExternal("V");
		AddState("s");
		SetStage(1, "I += s * (0 - V);");
		SetStage(2, "s' = -s / tau;");
		SetSynCode("s += gsyn;");
	}
	
	auto gaba_syn = new CSynapse("GABASyn");
	with(gaba_syn)
	{
		AddConstant("gaba_gsyn") = 0.1;
		AddConstant("gaba_tau") = 5;
		AddExternal("V");
		AddState("gaba_s");
		SetStage(1, "I += gaba_s * (-80 - V);");
		SetStage(2, "gaba_s' = -gaba_s / gaba_tau;");
		SetSynCode("gaba_s += gaba_gsyn;");
	}
	
	auto type = new CNeuronType("TestNeuron");
	with(type)
	{
		AddMechanism(iz_mech);
		AddMechanism(i_clamp);
		AddSynapse(glu_syn, 10);
		AddSynapse(gaba_syn, 10);
	}
	
	auto type2 = new CNeuronType("Burster");
	with(type2)
	{
		AddMechanism(iz_mech2);
		AddMechanism(i_clamp);
		AddSynapse(glu_syn, 10);
		AddSynapse(gaba_syn, 10);
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
	type2.NumSrcSynapses = 10;
	type2.NumSrcSynapses = 10;
	
	model.AddNeuronGroup(type, 10000);
	model.AddNeuronGroup(type2, 10000);
	model.Generate();
	//Stdout(model.Source).nl;
	
//	model["TestNeuron"]["u"] = 7;
//	Stdout.formatln("u = {}", model["TestNeuron"]["u"]);
	
	model["TestNeuron"]["amp"] = 0;
	model["Burster"]["amp"] = 10;
	model["TestNeuron"]["gsyn"] = 0.03;
	model["TestNeuron"]["gaba_gsyn"] = 0.5;
	
	model["Burster"].ConnectTo(0, 0, 0, 0, 0);
	model["Burster"].ConnectTo(1, 0, 0, 0, 10);
//	model["TestNeuron"].ConnectTo(1, 0, 0, 0, 0);
	
	bool record = true;
	CRecorder v_rec1;
	CRecorder v_rec2;
	if(record)
	{
		v_rec1 = model["TestNeuron"].Record(0, "V");
		v_rec2 = model["Burster"].Record(1, "V");
	}
	
	Stdout.formatln("Generating time: {}", timer.stop);
	timer.start;
	
	int tstop = 100;
	model.Run(tstop);
	
	Stdout.formatln("Run time: {}", timer.stop);
	
	model.Shutdown();
	core.Shutdown();
	
	if(record)
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

module main;

import celeme.celeme;
import gnuplot;

import tango.time.StopWatch;
import tango.io.Stdout;

/*
 * Split Init into Reset and Init
 * 
 * Reset resets all values to default values
 * 
 * Init just runs the init kernel
 * 
 * Allow setting of default values separately from the current values
 * (assert if try to set the current values)
 *  - Need to store default values separately (already done for normal values)
 */

void main()
{
	StopWatch timer;
	
	timer.start;
	
	auto dummy = new CMechanism("DummyThresh");
	with(dummy)
	{
		AddThreshold("V", "> -10", "delay = 5;", true);
		AddExternal("V");
	}
	
	auto iz_mech = new CMechanism("IzMech");
	with(iz_mech)
	{
		AddState("V") = -65;
		AddState("u") = -5;
		AddLocal("I");
		SetStage(0, "I = 0;");
		SetStage(2, "V' = (0.04f * V + 5) * V + 140 - u + I; u' = 0.02f * (0.2f * V - u);");
		AddThreshold("V", "> 0", "V = -65; u += 8; delay = 5;", true, true);
	}
	
	auto iz_mech2 = new CMechanism("IzMech2");
	with(iz_mech2)
	{
		AddState("V") = -65;
		AddState("u") = -5;
		AddLocal("I");
		SetStage(0, "I = 0;");
		SetStage(2, "V' = (0.04f * V + 5) * V + 140 - u + I; u' = 0.02f * (0.2f * V - u);");
		AddThreshold("V", "> 0", "V = -50; u += 2; delay = 5;", true, true);
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
		RecordLength = 1000;
		RecordRate = 1;
	}
	
	auto burster = new CNeuronType("Burster");
	with(burster)
	{
		AddMechanism(dummy, "hl");
		AddMechanism(iz_mech2);
		AddMechanism(i_clamp);
		AddSynapse(exp_syn, 10, "glu");
		AddSynapse(exp_syn, 10, "gaba");
		RecordLength = 1000;
		RecordRate = 0;
	}
	
	auto core = new CCLCore(false);
	
	auto model = new CCLModel!(float)(core);
	
	regular.CircBufferSize = 10;
	regular.NumSrcSynapses = 10;
	burster.CircBufferSize = 10;
	burster.NumSrcSynapses = 10;
	
	model.AddNeuronGroup(regular, 16);
	model.AddNeuronGroup(burster, 16);
	
	Stdout.formatln("Specify time: {}", timer.stop);
	timer.start;
	
	model.Generate(false);
	
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
	
	model["Regular"]["glu_gsyn"] = 0.04;
	model["Regular"]["gaba_gsyn"] = 0.5;
	
	model["Burster"]["glu_gsyn"] = 0.04;
	model["Burster"]["gaba_gsyn"] = 0.5;
	
	model["Burster"].ConnectTo(0, 0, 0, 0, 0);
	//model["Burster"].ConnectTo(1, 0, 0, 0, 10);
	model["Regular"].ConnectTo(0, 0, 0, 2, 0);
	
	bool record = true;
	CRecorder v_rec1;
	CRecorder v_rec2;
	if(record)
	{
		v_rec1 = model["Regular"].Record(0, "V");
		v_rec2 = model["Burster"].Record(0, "V");
		//v_rec1 = model["Regular"].Record(0, 0);
		//v_rec2 = model["Burster"].Record(0, 0);
	}
	
	Stdout.formatln("Init time: {}", timer.stop);
	timer.start;
	
	int tstop = 100;
	//model.Run(tstop);
	model.InitRun();
	model.RunUntil(50);
	model.RunUntil(101);
	
	Stdout.formatln("Run time: {}", timer.stop);
	
	model.Shutdown();
	core.Shutdown();
	
	timer.start;
	if(record)
	//if(false)
	{
		auto plot = new CGNUPlot;
		with(plot)
		{
			XLabel("Time (ms)");
			YLabel("Voltage (mV)");
			YRange([-80, 10]);
			XRange([0, tstop]);
			
			Hold = true;
			Color([0,0,0]);
			//Style = "points";
			Plot(v_rec1.T, v_rec1.Data, v_rec1.Name);
			Color([255,0,0]);
			//Style = "points";
			Plot(v_rec2.T, v_rec2.Data, v_rec2.Name);
			Hold = false;
		}
		
		auto t_old = v_rec1.T[0];
		auto v_old = v_rec1.Data[0];
		foreach(ii, t; v_rec1.T[1..$])
		{
			auto v = v_rec1.Data[1..$][ii];
			assert(v != v_old);// || t != t_old);
			t_old = t;
			v_old = v;
		}
		
		Stdout.formatln("{} {}", v_rec1.Length, v_rec2.Length);
		Stdout.formatln("{} {}", v_rec1.T[$-1], v_rec2.T[$-1]);
	}
	Stdout.formatln("Plotting time: {}", timer.stop);
}

module main;

import celeme.celeme;
import celeme.capi;
import gnuplot;
import celeme.util;

import tango.time.StopWatch;
import tango.io.Stdout;

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
		SetStage(2, "V' = (0.04f * V + 5) * V + 140 - u + I; u' = 0.01f * (0.2f * V - u);");
		AddThreshold("V", "> 0", "V = -65; u += 2; delay = 2;", true, true);
	}
	iz_mech["V"].Tolerance = 0.2;
	iz_mech["u"].Tolerance = 0.02;
	
	auto iz_mech2 = new CMechanism("IzMech2");
	with(iz_mech2)
	{
		AddState("V") = -65;
		AddState("u") = -5;
		AddLocal("I");
		SetStage(0, "I = 0;");
		SetStage(2, "V' = (0.04f * V + 5) * V + 140 - u + I; u' = 0.02f * (0.2f * V - u);");
		AddThreshold("V", "> 0", "V = -50; u += 2; delay = 2;", true, true);
	}
	iz_mech2["V"].Tolerance = 0.2;
	iz_mech2["u"].Tolerance = 0.02;

	auto i_clamp = new CMechanism("IClamp");
	with(i_clamp)
	{
		AddExternal("I");
		AddConstant("amp");
		SetStage(1, "if(i == 1) { I += amp + 3; } else { I += amp; }");
	}
	
	auto exp_syn = new CSynapse("ExpSyn");
	with(exp_syn)
	{
		AddConstant("gsyn") = 0.1;
		AddConstant("tau") = 5;
		AddConstant("E") = 0;
		AddExternal("V");
		AddSynGlobal("weight") = 1;
		AddState("s");
		SetStage(1, "I += s * (E - V);");
		SetStage(2, "s' = -s / tau;");
		SetSynCode("s += gsyn * weight;");
	}
	exp_syn["weight"].ReadOnly = true;
	
	auto regular = new CNeuronType("Regular");
	with(regular)
	{
		AddMechanism(iz_mech);
		AddMechanism(i_clamp);
		AddSynapse(exp_syn, 10, "glu");
		AddSynapse(exp_syn, 10, "gaba");
		RecordLength = 2000;
		RecordRate = 100;
	}
	
	auto burster = new CNeuronType("Burster");
	with(burster)
	{
		AddMechanism(dummy, "hl");
		AddMechanism(iz_mech2);
		AddMechanism(i_clamp);
		AddSynapse(exp_syn, 10, "glu");
		AddSynapse(exp_syn, 10, "gaba");
		RecordLength = 2000;
		RecordRate = 100;
	}
	
	auto model = new CCLModel!(float)(false);
	scope(exit) model.Shutdown();
	
	auto t_scale = 1;
	
	model.TimeStepSize = 1.0 / t_scale;
	
	regular.CircBufferSize = 10;
	regular.NumSrcSynapses = 10;
	burster.CircBufferSize = 10;
	burster.NumSrcSynapses = 10;
	
	model.AddNeuronGroup(regular, 2000);
	model.AddNeuronGroup(burster, 2000);
	
	Stdout.formatln("Specify time: {}", timer.stop);
	timer.start;
	
	model.Generate(true, true);
	
	Stdout.formatln("Generating time: {}", timer.stop);
	timer.start;
	
	//Stdout(model.Source).nl;
	
//	model["Regular"]["u"] = 7;
//	Stdout.formatln("u = {}", model["Regular"]["u"]);

	//model["Burster"].SetTolerance("V", 0.1);
	//model["Burster"].SetTolerance("u", 0.01);

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
	
	//model.Connect("Burster", 0, 0, 0, "Burster", 1, 0, 0);
	model.Connect("Burster", 0, 0, 0, "Regular", 0, 0, 0);
	//model.Connect("Regular", 0, 0, 0, "Burster", 0, 1, 0);
	//model.Connect("Regular", 0, 0, 1, "Burster", 1, 1, 0);
	
	bool record = true;
	CRecorder v_rec1;
	CRecorder v_rec2;
	CRecorder v_rec3;
	if(record)
	{
		v_rec1 = model["Burster"].Record(0, "V");
		v_rec2 = model["Burster"].Record(1, "V");
		v_rec3 = model["Regular"].Record(0, "V");
		//model["Burster"].RecordEvents(0, 1);
		//v_rec2 = model["Burster"].EventRecorder;
	}
	
	Stdout.formatln("Init time: {}", timer.stop);
	timer.start;
	
	int tstop = cast(int)(200 * t_scale);
	//model.Run(tstop);
	model.ResetRun();
	
	model.InitRun();
	//model.RunUntil(cast(int)(50 * t_scale));
	model.RunUntil(tstop + 1);
	
	Stdout.formatln("Run time: {}", timer.stop);
	
	timer.start;
	
	if(record)
	//if(false)
	{
		auto plot = new C2DPlot;
		with(plot)
		{
			Title(GetGitRevisionHash());
			XLabel("Time (ms)");
			YLabel("Voltage (mV)");
			YRange([-80, 10]);
			XRange([0, cast(int)(tstop/t_scale)]);
			
			Hold = true;
			Style("linespoints");
			PointType(6);
			Thickness(1);
			Color([0,0,0]);
			Plot(v_rec1.T, v_rec1.Data, v_rec1.Name);
			Color([255,0,0]);
			//Plot(v_rec2.T, v_rec2.Data, v_rec2.Name);
			//Color([0,0,255]);
			Plot(v_rec3.T, v_rec3.Data, v_rec3.Name);
			Hold = false;
		}
		
		/+auto plot1 = new C2DPlot;
		with(plot1)
		{
			Title("Neuron A");
			XLabel("Time (ms)");
			YLabel("Voltage (mV)");
			YRange([-80, 10]);
			XRange([650, 900]);
			Color([0,0,0]);
			Plot(v_rec1.T, v_rec1.Data, "");
		}
		
		auto plot2 = new C2DPlot;
		with(plot2)
		{
			Title("Neuron B");
			XLabel("Time (ms)");
			YLabel("Voltage (mV)");
			YRange([-80, 10]);
			XRange([650, 900]);
			Color([0,0,0]);
			Plot(v_rec2.T, v_rec2.Data, "");
		}
		
		auto plot3 = new C2DPlot;
		with(plot3)
		{
			Title("Neuron C");
			XLabel("Time (ms)");
			YLabel("Voltage (mV)");
			YRange([-80, 10]);
			XRange([650, 900]);
			Color([0,0,0]);
			Plot(v_rec3.T, v_rec3.Data, "");
		}+/
		
		
		/+auto t_old = v_rec1.T[0];
		auto v_old = v_rec1.Data[0];
		foreach(ii, t; v_rec1.T[1..$])
		{
			auto v = v_rec1.Data[1..$][ii];
			assert(v != v_old);// || t != t_old);
			t_old = t;
			v_old = v;
		}+/
		// 361 680
		Stdout.formatln("{} {}", v_rec1.Length, v_rec2.Length);
		Stdout.formatln("{} {}", v_rec1.T[$-1], v_rec2.T[$-1]);
	}
	Stdout.formatln("Plotting time: {}", timer.stop);
	
	//foreach(t; v_rec1.T)
	//	Stdout(t).nl;
	
	/+auto plot3d = new C3DPlot;
	with(plot3d)
	{
		XRange([-0.5, 2.5]);
		YRange([-0.5, 2.5]);
		View = null;
		Palette("color");
		Plot([0, 1, 2,
		      1, 2, 3,
		      2, 3, 4], 3, 3);
	}+/
}

module main;

import celeme.celeme;
import celeme.capi;
import celeme.xmlutil;

import opencl.cl;
import gnuplot;
import celeme.util;

import tango.time.StopWatch;
import tango.io.Stdout;
import tango.math.random.Random;

void main()
{
	StopWatch timer;
	
	timer.start;
	
	auto xml_root = GetRoot("stuff.xml");
	auto mechs = LoadMechanisms(xml_root);
	auto syns = LoadSynapses(xml_root);
	auto conns = LoadConnectors(xml_root);
	auto types = LoadNeuronTypes(xml_root, mechs, syns, conns);
	
	auto model = new CCLModel!(float)(false);
	scope(exit) model.Shutdown();
	
	auto t_scale = 1;
	
	model.TimeStepSize = 1.0 / t_scale;	
	const N = 100;
	model.AddNeuronGroup(types["Regular"], N, null, true);
	//model.AddNeuronGroup(types["Burster"], 5, null, true);
	
	Stdout.formatln("Specify time: {}", timer.stop);
	timer.start;
	
	model.Generate(true, true);
	model["Regular"].MinDt = 0.1;
	//model["Burster"].MinDt = 0.1;
	Stdout.formatln("Generating time: {}", timer.stop);
	timer.start;
	
	//Stdout(model.Source).nl;
	
//	model["Regular"]["u"] = 7;
//	Stdout.formatln("u = {}", model["Regular"]["u"]);

	//model["Burster"].SetTolerance("V", 0.1);
	//model["Burster"].SetTolerance("u", 0.01);

	///model["Burster"]["glu_E"] = 0;
	model["Regular"]["glu_E"] = 0;
	///model["Burster"]["gaba_E"] = -80;
	model["Regular"]["gaba_E"] = -80;
	
	model["Regular"]["amp"] = 3.5;
	///model["Burster"]["amp"] = 0;
	
	model["Regular"]["glu_gsyn"] = 0.006;
	model["Regular"]["gaba_gsyn"] = 0.5;
	
	///model["Burster"]["glu_gsyn"] = 0.04;
	///model["Burster"]["gaba_gsyn"] = 0.5;
	
	/*for(int ii = 0; ii < N; ii++)
	{
		for(int jj = 0; jj < N; jj++)
		{
			if(ii != jj && rand.uniform!(float) > 0.96)
				model.Connect("Regular", ii, 0, "Regular", jj, 0);
		}
	}*/
	
	//model.Connect("Regular", 1, 0, "Regular", 0, 0);
	//model.SetConnection("Regular", 0, 0, 0, "Regular", 1, 0, 0);
	model.Connect("RandConn", N, "Regular", [0, N], 0, "Regular", [0, N], 0, ["P": 0.05]);
	//model.Connect("RandConn", 1, "Regular", [0, 1], 0, "Burster", [1, 2], 0, ["P": 1]);
	
	/+auto arr = model["Regular"].DestSynBuffer.Map(CL_MAP_READ);
	foreach(el; arr)
	{
		if(el[0] >= 0)
			println("{} {}", el[0], el[1]);
	}
	
	return;+/
	
	//model.SetConnection("Burster", 0, 0, 0, "Regular", 0, 0, 0);
	//model.SetConnection("Burster", 0, 0, 1, "Regular", 1, 1, 0);
	//model.SetConnection("Burster", 0, 0, 0, "Burster", 1, 0, 0);
	//model.SetConnection("Burster", 0, 0, 0, "Regular", 0, 0, 0);
	//model.SetConnection("Regular", 0, 0, 0, "Burster", 0, 1, 0);
	//model.SetConnection("Regular", 0, 0, 1, "Burster", 1, 1, 0);
	
	bool record = true;
	CRecorder v_rec1;
	CRecorder v_rec2;
	CRecorder v_rec3;
	if(record)
	{
		v_rec1 = model["Regular"].Record(1, "V");
		v_rec2 = model["Regular"].Record(2, "V");
		v_rec3 = model["Regular"].Record(3, "V");
		//model["Burster"].RecordEvents(0, 1);
		//v_rec2 = model["Burster"].EventRecorder;
	}
	
	Stdout.formatln("Init time: {}", timer.stop);
	timer.start;
	
	int tstop = cast(int)(1000 * t_scale);
	//model.Run(tstop);
	model.ResetRun();
	model.InitRun();
	model.RunUntil(cast(int)(50 * t_scale));
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
			Style("lines");
			PointType(6);
			Thickness(1);
			Color([0,0,0]);
			Plot(v_rec1.T, v_rec1.Data, v_rec1.Name);
			Color([255,0,0]);
			Plot(v_rec2.T, v_rec2.Data, v_rec2.Name);
			Color([0,0,255]);
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

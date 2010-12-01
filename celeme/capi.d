module celeme.capi;

import celeme.celeme;
import celeme.capi;
import celeme.xmlutil;

import opencl.cl;
import gnuplot;
import celeme.util;

import tango.time.StopWatch;
import tango.io.Stdout;
import tango.math.random.Random;

import tango.core.Runtime;
import tango.stdc.stdlib : atexit;

bool Inited = false;
bool Registered = false;

extern(C)
void celeme_init()
{
	if(!Inited)
	{
		Runtime.initialize();
		if(!Registered)
		{
			atexit(&celeme_shutdown);
			Registered = true;
		}
	}
	
	Inited = true;
}

extern(C)
void celeme_shutdown()
{
	if(Inited)
	{
		Inited = false;
		Runtime.terminate();
	}
}

extern(C)
void celeme_test()
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
	
	Stdout.formatln("Generating time: {}", timer.stop);
	timer.start;
	
	//Stdout(model.Source).nl;
	
//	model["Regular"]["u"] = 7;
//	Stdout.formatln("u = {}", model["Regular"]["u"]);

	//model["Burster"].SetTolerance("V", 0.1);
	//model["Burster"].SetTolerance("u", 0.01);
	
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

		// 361 680
		Stdout.formatln("{} {}", v_rec1.Length, v_rec2.Length);
		Stdout.formatln("{} {}", v_rec1.T[$-1], v_rec2.T[$-1]);
	}
	Stdout.formatln("Plotting time: {}", timer.stop);
}

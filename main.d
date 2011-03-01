/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2011 Pavel Sountsov

Celeme is free software: you can redistribute it and/or modify
it under the terms of the Lesser GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Celeme is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Celeme. If not, see <http:#www.gnu.org/licenses/>.
*/

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
import tango.text.Arguments;

void main(char[][] arg_list)
{
	bool record = true;
	bool save_to_file = false;
	
	auto args = new Arguments;
	args("run-only").aliased('r').bind({record = false;});
	args("save").aliased('s').bind({save_to_file = true;});
	args.parse(arg_list);
	
	StopWatch timer;
	
	timer.start;
	
	auto model = LoadModel("stuff.cfg", true);
	scope(exit) model.Shutdown();
	
	auto N = model["Regular"].Count;
	auto t_scale = 1.0 / model.TimeStepSize;
	
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
	model.ApplyConnector("RandConn", N, "Regular", [0, N], 0, "Regular", [0, N], 0, ["P": 0.05]);
	//model.Connect("RandConn", 1, "Regular", [0, 1], 0, "Burster", [1, 2], 0, ["P": 1]);
	
	/+auto arr = model["Regular"].DestSynBuffer.Map(CL_MAP_READ);
	foreach(el; arr)
	{
		if(el[0] >= 0)
			println("{} {}", el[0], el[1]);
	}
	
	return;+/
	
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
			if(save_to_file)
			{
				Terminal = "pngcairo";
				OutputFile = "plot.png";
			}
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

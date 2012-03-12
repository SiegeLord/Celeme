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

import opencl.cl;
import gnuplot;
import celeme.internal.util;

import tango.time.StopWatch;
import tango.io.Stdout;
import tango.math.random.Random;
import tango.text.Arguments;
import tango.text.convert.Format;

void main(char[][] arg_list)
{
	bool record = true;
	bool save_to_file = false;
	bool gpu = false;
	
	auto args = new Arguments;
	args("run-only").aliased('r').bind({record = false;});
	args("save").aliased('s').bind({save_to_file = true;});
	args("gpu").aliased('g').bind({gpu = true;});
	args.parse(arg_list);
	
	StopWatch timer;
	
	timer.start();
	
	auto model = LoadModel("stuff.cfg", ["mechanisms"], gpu);
	scope(exit) model.Dispose();
	
	const N = 1000;
	
	model.TimeStepSize = 1.0;
	model.AddNeuronGroup("Regular", N, null, true, gpu);
	
	auto t_scale = 1.0 / model.TimeStepSize;
	
	//model.AddNeuronGroup(types["Burster"], 5, null, true);
	
	Stdout.formatln("Specify time: {}", timer.stop());
	timer.start();
	
	model.Generate();
	
	Stdout.formatln("Generating time: {}", timer.stop());
	timer.start();
	
	//Stdout(model.Source).nl;
	
//	model["Regular"]["u"] = 7;
//	Stdout.formatln("u = {}", model["Regular"]["u"]);

	//model["Burster"].SetTolerance("V", 0.1);
	//model["Burster"].SetTolerance("u", 0.01);
	
	//model.Connect("Regular", 1, 0, "Regular", 0, 0);
	//model.SetConnection("Regular", 0, 0, 0, "Regular", 1, 0, 0);
	model.ApplyConnector("RandConn", N, "Regular", [0, N], 0, "Regular", [0, N], 0, ["P": 0.05]);
	//model.Connect("RandConn", 1, "Regular", [0, 1], 0, "Burster", [1, 2], 0, ["P": 1]);
	
	auto conns = new int[](N * N);
	conns[] = 0;
	auto regular = model["Regular"];
	foreach(src; range(N))
	{
		foreach(slot; range(150))
		{
			auto dest = regular.GetConnectionId(src, 0, slot);
			if(dest > -1)
			{
				conns[src + dest * N] = 1;
			}
		}
	}
	
	/+auto conn_plot = new C3DPlot;
	with(conn_plot)
	{
		Style = "pm3d";
		Plot(conns, N, N);
	}
	
	return;+/
	
	/+auto arr = model["Regular"].DestSynBuffer.Map(CL_MAP_READ);
	foreach(el; arr)
	{
		if(el[0] >= 0)
			println("{} {}", el[0], el[1]);
	}
	
	return;+/
	
	if(record)
	{
		model["Regular"].Record(0, 1);
		//model["Regular"].Record(1, 1);
		//model["Regular"].Record(2, 1);
	}
	
	Stdout.formatln("Init time: {}", timer.stop());
	timer.start();
	
	int tstop = cast(int)(1000 * t_scale);
	//model.Run(tstop);
	model.ResetRun();
	model.InitRun();
	//model.RunUntil(cast(int)(50 * t_scale));
	model.RunUntil(tstop + 1);
	Stdout.formatln("Run time: {}", timer.stop());
	
	Stdout(model["Regular"]["glu_counter", 0, 0]).nl;
	Stdout(model["Regular"]["glu_counter", 0, 1]).nl;
	
	timer.start();
	
	if(record)
	//if(false)
	{
		auto data_arrs = ExtractData(model["Regular"].GetRecordedData());	
	
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
			//Style("linespoints");
			PointType(6);
			Thickness(1);
			foreach(nrn_id, tag_arr; data_arrs)
			{
				foreach(tag, data; tag_arr)
				{
					Plot(data.T, data.Data, Format("{} : {}", nrn_id, tag));
				}
			}
			/*Color([0,0,0]);
			Plot(rec.T, rec.Data, rec.Name);
			Color([255,0,0]);
			Plot(v_rec2.T, v_rec2.Data, v_rec2.Name);
			Color([0,0,255]);
			Plot(v_rec3.T, v_rec3.Data, v_rec3.Name);*/
			Hold = false;
		}

		// 361 680
		/*Stdout.formatln("{} {}", v_rec1.Length, v_rec2.Length);
		Stdout.formatln("{} {}", v_rec1.T[$-1], v_rec2.T[$-1]);*/
	}
	Stdout.formatln("Plotting time: {}", timer.stop());
}

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

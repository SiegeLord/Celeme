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

module celeme.clrand;

import celeme.clcore;
import celeme.clneurongroup;
import celeme.util;

import tango.math.random.Random;
import tango.util.Convert;

import opencl.cl;

/*
 * Taken from NVidia's GPU gems 3.37
 */

const char[] RandComponents = 
`
uint TausStep(uint* z, int S1, int S2, int S3, uint M)  
{  
	uint b = (((*z << S1) ^ *z) >> S2);  
	return *z = (((*z & M) << S3) ^ b);  
}

uint LCGStep(uint* z, uint A, uint C)  
{  
	return *z = (A * *z + C);  
}
`;

const char[][4] RandCode = 
[
`
$num_type$ rand1(uint* z)
{
	return 2.3283064365387e-10 * LCGStep(z, 1664525, 1013904223UL);
}
`,
`
$num_type$ rand2(uint2* zp)
{
	uint z0 = (*zp).s0;
	uint z1 = (*zp).s1;
	$num_type$ ret = 2.3283064365387e-10 * (TausStep(&z0, 13, 19, 12, 4294967294UL)
	                                       ^ LCGStep(&z1, 1664525, 1013904223UL));
	(*zp).s0 = z0;
	(*zp).s1 = z1;
	return ret;
}
`,
``,
``
];


class CCLRand
{
	char[] GetLoadCode()
	{
		return "";
	}
	
	char[] GetSaveCode()
	{
		return "";
	}
	
	char[] GetArgsCode()
	{
		return "";
	}
	
	int SetArgs(CCLKernel kernel, int arg_id)
	{
		return arg_id;
	}
	
	void Seed()
	{
		
	}
	
	void Shutdown()
	{
		
	}
	
	int NumArgs()
	{
		return 0;
	}
}

class CCLRandImpl(uint N) : CCLRand
{
	static if(N == 1)
	{
		alias uint state_t;
	}
	static if(N == 2)
	{
		alias cl_uint2 state_t;
	}
	static if(N == 4)
	{
		alias cl_uint4 state_t;
	}
	
	this(CCLCore core, int count)
	{
		State = new CCLBuffer!(state_t)(core, count);
	}
	
	char[] GetTypeString()
	{
		char[] ret = "uint";
		static if (N > 1)
			ret ~= to!(char[])(N);
		
		return ret;
	}
	
	char[] GetLoadCode()
	{
		return GetTypeString() ~ " rand_state = rand_state_buf[i];";
	}
	
	char[] GetSaveCode()
	{
		return "rand_state_buf[i] = rand_state;";
	}
	
	char[] GetArgsCode()
	{
		return "__global " ~ GetTypeString() ~ "* rand_state_buf,";
	}
	
	int SetArgs(CCLKernel kernel, int arg_id)
	{
		uint a;
		kernel.SetGlobalArg(arg_id, &State.Buffer);
		return arg_id + 1;
	}
	
	void Seed()
	{
		auto arr = State.Map(CL_MAP_WRITE);
		foreach(ref el; arr)
		{
			static if(N == 1)
			{
				el = rand.uniform!(int);
			}
			else
			{
				for(int ii = 0; ii < N; ii++)
					el[ii] = rand.uniform!(int);
			}
		}
		State.UnMap(arr);
	}
	
	void Shutdown()
	{
		State.Release();
	}
	
	int NumArgs()
	{
		return 1;
	}
	
	CCLBuffer!(state_t) State;
}

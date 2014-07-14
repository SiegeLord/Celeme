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

module celeme.internal.clrand;

import celeme.internal.clcore;
import celeme.internal.util;

import tango.math.random.Random;
import tango.util.Convert;
import tango.text.convert.Format;

import opencl.cl;
import dutil.Disposable;

/*
 * Taken from NVidia's GPU gems 3.37
 */

const cstring RandComponents = 
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

const cstring[4] RandCode = 
[
`
$num_type$ _rand_impl1(uint* z)
{
	return 2.3283064365387e-10 * LCGStep(z, 1664525, 1013904223UL);
}
`,
`
$num_type$ _rand_impl2(uint2* zp)
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


class CCLRand : CDisposable
{
	this(size_t idx)
	{
		Rand = new Random;
		Idx = idx;
	}
	
	cstring GetLoadCode()
	{
		return "";
	}
	
	cstring GetSaveCode()
	{
		return "";
	}
	
	cstring GetArgsCode()
	{
		return "";
	}
	
	size_t SetArgs(CCLKernel kernel, size_t arg_id)
	{
		return arg_id;
	}
	
	void Seed(int n)
	{
		
	}
	
	void Seed()
	{
		
	}
	
	void Seed(size_t idx, int n)
	{
		
	}
	
	override
	void Dispose()
	{
		super.Dispose();
	}
	
	@property
	int NumArgs()
	{
		return 0;
	}
protected:
	Random Rand;
	size_t Idx;
}

class CCLRandImpl(size_t N) : CCLRand
{
	static if(N == 1)
	{
		alias uint state_t;
	}
	else static if(N == 2)
	{
		alias cl_uint2 state_t;
	}
	else static if(N == 4)
	{
		alias cl_uint4 state_t;
	}
	else
	{
		static assert("Unsupported random state length.");
	}
	
	this(CCLCore core, size_t idx, size_t count)
	{
		super(idx);
		State = new CCLBuffer!(state_t)(core, count);
	}
	
	cstring GetTypeString()
	{
		cstring ret = "uint";
		static if (N > 1)
			ret ~= to!(char[])(N);
		
		return ret;
	}
	
	override
	cstring GetLoadCode()
	{
		return GetTypeString() ~ Format(" _rand_state_{0} = _rand_state_buf_{0}[i];", Idx);
	}
	
	override
	cstring GetSaveCode()
	{
		return Format("_rand_state_buf_{0}[i] = _rand_state_{0};", Idx);
	}
	
	override
	cstring GetArgsCode()
	{
		return "__global " ~ GetTypeString() ~ Format("* _rand_state_buf_{0},", Idx);
	}
	
	override
	size_t SetArgs(CCLKernel kernel, size_t arg_id)
	{
		kernel.SetGlobalArg(arg_id, State.Buffer);
		return arg_id + 1;
	}
	
	override
	void Seed(int n)
	{
		Rand.seed({return cast(uint)n;});
		Seed();
	}
	
	override
	void Seed()
	{
		auto arr = State.MapWrite();
		scope(exit) State.UnMap();
		foreach(ref el; arr)
		{
			static if(N == 1)
			{
				el = Rand.uniform!(int)();
			}
			else
			{
				for(int ii = 0; ii < N; ii++)
					el[ii] = Rand.uniform!(int)();
			}
		}
	}
	
	override
	void Seed(size_t idx, int n)
	{
		Rand.seed({return cast(uint)n;});
		state_t el;
		static if(N == 1)
		{
			el = Rand.uniform!(int)();
		}
		else
		{
			for(int ii = 0; ii < N; ii++)
				el[ii] = Rand.uniform!(int)();
		}
		State[idx] = el;
	}
	
	override
	void Dispose()
	{
		State.Dispose();
		super.Dispose();
	}
	
	override
	@property
	int NumArgs()
	{
		return 1;
	}
	
	CCLBuffer!(state_t) State;
}

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

module celeme.internal.iclneurongroup;

import opencl.cl;

import celeme.internal.clrand;
import celeme.internal.clcore;
import celeme.internal.clmiscbuffers;
import celeme.internal.util;

import celeme.ineurongroup;

interface ICLNeuronGroup : INeuronGroup
{
	@property cstring Name();
	
	@property size_t RandStateSize();
	@property size_t NumEventSources();
	@property size_t NumSrcSynapses();
	@property size_t NumSynThresholds();
	
	@property CCLRand[] Rand();
	@property CEventSourceBuffer[] EventSourceBuffers();
	@property CSynapseBuffer[] SynapseBuffers();
	@property CCLBuffer!(cl_int2) DestSynBuffer();
	@property CCLBuffer!(int) ErrorBuffer();
	@property cl_program Program();
	
	@property CCLCore Core();
	
	@property bool Initialized();
	@property int IntegratorArgOffset();
	@property double TimeStepSize();
}

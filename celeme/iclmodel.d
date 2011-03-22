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

module celeme.iclmodel;

import celeme.imodel;
import celeme.clcore;

import opencl.cl;

interface ICLModel : IModel
{
	bool Initialized();
	cl_program Program();
	CCLCore Core();
	CCLBuffer!(int) FiredSynIdxBuffer();
	CCLBuffer!(int) FiredSynBuffer();
	void MemsetFloatBuffer(cl_mem buffer, int count, double value);
	void MemsetIntBuffer(cl_mem buffer, int count, int value);
}
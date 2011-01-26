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

module pyceleme.main;

import python.python;

import pyceleme.model;
import pyceleme.neurongroup;
import pyceleme.recorder;
import pyceleme.array;

import tango.stdc.stringz;

char[] ErrorCheck(char[] ret = "-1")
{
	return
`
	if(celeme_get_error() !is null)
	{
		PyErr_SetString(Error, celeme_get_error());
		celeme_set_error(null);
		return ` ~ ret ~ `;
	}
`;
}

char** ToCharPP(char[][] args)
{
	char*[] ret;
	ret.length = args.length;
	
	foreach(ii, arg; args)
	{
		ret[ii] = toStringz(arg);
	}
	
	return ret.ptr;
}

bool DParseTupleAndKeywords(T...)(PyObject* args, PyObject* keywds, char[] arg_types, char[][] kw_list, T t)
{
	auto c_arg_types = toStringz(arg_types);
	auto c_kw_list = ToCharPP(kw_list);
	return 0 != PyArg_ParseTupleAndKeywords(args, keywds, c_arg_types, c_kw_list, t);
}

PyMethodDef CelemeMethods[] = 
[
	{null, null, 0, null}
];

PyObject* Module;
PyObject* Error;

void InitModule()
{
	PreInitModel();
	PreInitNeuronGroup();
	PreInitRecorder();
	PreInitArray();
	
	Module = Py_InitModule("pyceleme", CelemeMethods.ptr);
	if(Module is null)
		return;

	Error = PyErr_NewException("test.error", null, null);
	Py_INCREF(Error);
	PyModule_AddObject(Module, "error", Error);
	
	AddModel();
	AddNeuronGroup();
	AddRecorder();
	AddArray();
}

void main(char[][] args)
{
	Py_Initialize();
	scope(exit) Py_Finalize();
	
	InitModule();

	Py_Main(args.length, ToCharPP(args));
}

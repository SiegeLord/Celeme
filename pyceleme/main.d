module pyceleme.main;

import python.python;

import pyceleme.model;
import pyceleme.neurongroup;
import pyceleme.recorder;

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
	
	Module = Py_InitModule("pyceleme", CelemeMethods.ptr);
	if(Module is null)
		return;

	Error = PyErr_NewException("test.error", null, null);
	Py_INCREF(Error);
	PyModule_AddObject(Module, "error", Error);
	
	AddModel();
	AddNeuronGroup();
	AddRecorder();
}

void main(char[][] args)
{
	Py_Initialize();
	scope(exit) Py_Finalize();
	
	InitModule();

	Py_Main(args.length, ToCharPP(args));
}

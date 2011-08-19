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

module pyceleme.model;

import celeme.capi;
import celeme.imodel;
import celeme.ineurongroup;

import pyceleme.main;
import pyceleme.neurongroup;
import python.python;

import tango.stdc.stringz;
import tango.io.Stdout;

struct SModel
{
    mixin PyObject_HEAD;
    IModel Model;
}

extern (C)
void SModel_dealloc(SModel* self)
{
	self.ob_type.tp_free(cast(PyObject*)self);
}

extern (C)
PyObject* SModel_new(PyTypeObject *type, PyObject* args, PyObject* kwds)
{
	auto self = cast(SModel*)type.tp_alloc(type, 0);
	if(self !is null) 
		self.Model = null;

	return cast(PyObject*)self;
}

extern (C)
int SModel_init(SModel *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["file", "include_dirs", "gpu", "double_precision", null];
	char* str;
	int gpu = 0;
	int double_precision = 0;
	PyObject* include_dirs;

	if(!DParseTupleAndKeywords(args, kwds, "s|Oii", kwlist, &str, &include_dirs, &gpu, &double_precision))
		return -1;
		
	char*[] include_dirs_arr;
		
	if(PyList_Check(include_dirs))
	{
		include_dirs_arr.length = PyList_Size(include_dirs);
		
		foreach(idx, ref include; include_dirs_arr)
		{
			auto item = PyList_GetItem(include_dirs, idx);
			Py_INCREF(item);
			scope(exit) Py_DECREF(item);
			
			if(!PyArg_Parse(item, "s", &include))
			{
				PyErr_SetString(Error, "include directory is supposed to be a string");
				return -1;
			}
		}
		
	}
	else
	{
		PyErr_SetString(Error, "args is supposed to be string list");
		return -1;
	}
	
	self.Model = celeme_load_model(str, include_dirs_arr.length, include_dirs_arr.ptr, cast(bool)gpu, cast(bool)double_precision);
	
	mixin(ErrorCheck("-1"));
	return 0;
}

PyMemberDef[] SModel_members = 
[
    {null}
];

extern(C)
PyObject* SModel_get_timestep_size(SModel *self, void *closure)
{
	auto ret = Py_BuildValue("d", celeme_get_timestep_size(self.Model));
	mixin(ErrorCheck("null"));
    return ret;
}

extern(C)
int SModel_set_timestep_size(SModel *self, PyObject *value, void *closure)
{
	if(value is null)
	{
		PyErr_SetString(Error, "Cannot delete the TimeStepSize attribute");
		return -1;
	}

	double val;

	if(PyArg_Parse(value, "d", &val))
		celeme_set_timestep_size(self.Model, val);
	else
	{
		PyErr_SetString(Error, "Expected a double");
		return -1;
	}
	
	mixin(ErrorCheck("-1"));
	return 0;
}

PyGetSetDef[] SModel_getseters = 
[
	{"TimeStepSize", cast(getter)&SModel_get_timestep_size, cast(setter)&SModel_set_timestep_size, "TimeStepSize", null},
	{null}  /* Sentinel */
];

extern (C)
PyObject* SModel_generate(SModel *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["initialize", null];
	int initialize = 1;

	if(!DParseTupleAndKeywords(args, kwds, "|i", kwlist, &initialize))
		return null;
	
	celeme_generate_model(self.Model, cast(bool)initialize);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SModel_initialize(SModel *self)
{
	celeme_initialize_model(self.Model);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SModel_run(SModel *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["timesteps", null];
	int timesteps;

	if(!DParseTupleAndKeywords(args, kwds, "i", kwlist, &timesteps))
		return null;
	
	celeme_run(self.Model, timesteps);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SModel_reset_run(SModel *self)
{
	celeme_reset_run(self.Model);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SModel_init_run(SModel *self)
{
	celeme_init_run(self.Model);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SModel_run_until(SModel *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["timesteps", null];
	int timesteps;

	if(!DParseTupleAndKeywords(args, kwds, "i", kwlist, &timesteps))
		return null;
	
	celeme_run_until(self.Model, timesteps);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SModel_add_neuron_group(SModel *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["type_name", "number", "name", "adaptive_dt", "parallel_delivery", null];
	
	char* type_name;
	int number;
	char* name;
	int adaptive_dt = 1;
	int parallel_delivery = 1;

	if(!DParseTupleAndKeywords(args, kwds, "si|sii", kwlist, &type_name, &number, &name, &adaptive_dt, &parallel_delivery))
		return null;
	
	celeme_add_neuron_group(self.Model, type_name, number, name, cast(bool)adaptive_dt, cast(bool)parallel_delivery);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SModel_set_connection(SModel *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["src_group", "src_nrn_id", "src_event_source", 
		"src_slot", "dest_group", "dest_nrn_id", "dest_syn_type", "dest_slot", null];
	
	char* src_group;
	int src_nrn_id;
	int src_event_source;
	int src_slot;
	char* dest_group;
	int dest_nrn_id;
	int dest_syn_type;
	int dest_slot;

	if(!DParseTupleAndKeywords(args, kwds, "siiisiii", kwlist, &src_group, &src_nrn_id, &src_event_source, 
		&src_slot, &dest_group, &dest_nrn_id, &dest_syn_type, &dest_slot))
		return null;
	
	celeme_set_connection(self.Model, src_group, src_nrn_id, src_event_source, 
		src_slot, dest_group, dest_nrn_id, dest_syn_type, dest_slot);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SModel_connect(SModel *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["src_group", "src_nrn_id", "src_event_source", 
		"dest_group", "dest_nrn_id", "dest_syn_type", null];
	
	char* src_group;
	int src_nrn_id;
	int src_event_source;
	char* dest_group;
	int dest_nrn_id;
	int dest_syn_type;

	if(!DParseTupleAndKeywords(args, kwds, "siisii", kwlist, &src_group, &src_nrn_id, &src_event_source, 
		&dest_group, &dest_nrn_id, &dest_syn_type))
		return null;
	
	auto ret = celeme_connect(self.Model, src_group, src_nrn_id, src_event_source, 
		dest_group, dest_nrn_id, dest_syn_type);
	
	mixin(ErrorCheck("null"));
	return Py_BuildValue("(ii)", ret.SourceSlot, ret.DestSlot);
}

extern (C)
PyObject* SModel_apply_connector(SModel *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["connector_name", "multiplier", "src_group", 
		"src_nrn_range", "src_event_source", "dest_group", "dest_syn_range", "dest_syn_type", "args", null];
	
	char* connector_name;
	int multiplier;
	char* src_group;
	int src_nrn_start;
	int src_nrn_end;
	int src_event_source;
	char* dest_group;
	int dest_nrn_start;
	int dest_nrn_end;
	int dest_syn_type;	
	PyObject* conn_args;

	if(!DParseTupleAndKeywords(args, kwds, "sis(ii)is(ii)iO", kwlist, &connector_name, &multiplier, &src_group, 
		&src_nrn_start, &src_nrn_end, &src_event_source, &dest_group, &dest_nrn_start, &dest_nrn_end, &dest_syn_type, &conn_args))
		return null;
	
	int argc;
	char*[] arg_keys;
	double[] arg_vals;
		
	if(PyDict_Check(conn_args))
	{
		auto items = PyDict_Items(conn_args);
		scope(exit) Py_DECREF(items);
		
		argc = PyList_Size(items);
		arg_keys.length = argc;
		arg_vals.length = argc;
		
		for(int ii = 0; ii < argc; ii++)
		{
			auto item = PyList_GetItem(items, ii);
			Py_INCREF(item);
			scope(exit) Py_DECREF(item);
			
			char* param;
			double val;
			
			if(!PyArg_ParseTuple(item, "sd", &param, &val))
			{
				PyErr_SetString(Error, "args is supposed to be a string->double dictionary");
				return null;
			}
			
			arg_keys[ii] = param;
			arg_vals[ii] = val;
		}
		
	}
	else
	{
		PyErr_SetString(Error, "args is supposed to be a string->double dictionary");
		return null;
	}
	
	celeme_apply_connector(self.Model, connector_name, multiplier, src_group, 
		src_nrn_start, src_nrn_end, src_event_source, dest_group, dest_nrn_start, dest_nrn_end, dest_syn_type,
		argc, arg_keys.ptr, arg_vals.ptr);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

PyMethodDef[] SModel_methods = 
[
    {"AddNeuronGroup", cast(PyCFunction)&SModel_add_neuron_group, METH_VARARGS | METH_KEYWORDS, "Adds a new neuron group from an internal registry"},
    {"Generate", cast(PyCFunction)&SModel_generate, METH_VARARGS | METH_KEYWORDS, "Generate the model"},
    {"Initialize", cast(PyCFunction)&SModel_initialize, METH_NOARGS, "Initialize the model"},
    {"Run", cast(PyCFunction)&SModel_run, METH_VARARGS | METH_KEYWORDS, "Run the model"},
    {"ResetRun", cast(PyCFunction)&SModel_reset_run, METH_NOARGS, "Reset the run"},
    {"InitRun", cast(PyCFunction)&SModel_init_run, METH_NOARGS, "Init the run"},
    {"RunUntil", cast(PyCFunction)&SModel_run_until, METH_VARARGS | METH_KEYWORDS, "Run the model until"},
    {"SetConnection", cast(PyCFunction)&SModel_set_connection, METH_VARARGS | METH_KEYWORDS, "Set a connection between two neurons"},
    {"Connect", cast(PyCFunction)&SModel_connect, METH_VARARGS | METH_KEYWORDS, "Connect two neurons"},
    {"ApplyConnector", cast(PyCFunction)&SModel_apply_connector, METH_VARARGS | METH_KEYWORDS, "Apply a connector"},
    {null}  /* Sentinel */
];

extern(C)
PyObject* SModel_getitem(SModel* self, PyObject* args)
{	
	PyObject* new_args = args;
	
	bool dec_ref_args = false;
	scope(exit)
	{
		if(dec_ref_args)
		{
			Py_DECREF(new_args);
		}
	}
	
	if(!PyTuple_Check(args))
	{
		new_args = Py_BuildValue("(O)", args);
		dec_ref_args = true;
	}
	
	char* name;
	
	if(!PyArg_ParseTuple(new_args, "s", &name))
		return null;
		
	auto group = celeme_get_neuron_group(self.Model, name);
	mixin(ErrorCheck("null"));
		
	auto ret = SNeuronGroup_new(&SNeuronGroupType, null, null);
	(cast(SNeuronGroup*)ret).Group = group;

	return ret;
}

PyMappingMethods SModelMapping = 
{
	null,
	cast(binaryfunc)&SModel_getitem,
	null
};


PyTypeObject SModelType = 
{
    0,                         /*ob_refcnt*/
    null,                      /*ob_type*/
	0,                         /*ob_size*/
	"pyceleme.Model",             /*tp_name*/
	SModel.sizeof,             /*tp_basicsize*/
	0,                         /*tp_itemsize*/
	cast(destructor)&SModel_dealloc, /*tp_dealloc*/
	null,                      /*tp_print*/
	null,                      /*tp_getattr*/
	null,                      /*tp_setattr*/
	null,                      /*tp_compare*/
	null,                      /*tp_repr*/
	null,                      /*tp_as_number*/
	null,                      /*tp_as_sequence*/
	&SModelMapping,                      /*tp_as_mapping*/
	null,                      /*tp_hash */
	null,                      /*tp_call*/
	null,                      /*tp_str*/
	null,                      /*tp_getattro*/
	null,                      /*tp_setattro*/
	null,                      /*tp_as_buffer*/
	Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE, /*tp_flags*/
	"Model objects",           /* tp_doc */
	null,		               /* tp_traverse */
	null,		               /* tp_clear */
	null,		               /* tp_richcompare */
	0,		                   /* tp_weaklistoffset */
	null,		               /* tp_iter */
	null,		               /* tp_iternext */
	null,                      /* tp_methods */
	null,                      /* tp_members */
	null,                      /* tp_getset */
	null,                      /* tp_base */
	null,                      /* tp_dict */
	null,                      /* tp_descr_get */
	null,                      /* tp_descr_set */
	0,                         /* tp_dictoffset */
	cast(initproc)&SModel_init,  /* tp_init */
	null,                      /* tp_alloc */
	&SModel_new,                 /* tp_new */
};

static this()
{
	SModelType.tp_methods = SModel_methods.ptr;
	SModelType.tp_members = SModel_members.ptr;
	SModelType.tp_getset = SModel_getseters.ptr;
}

void PreInitModel()
{
	if(PyType_Ready(&SModelType) < 0)
		assert(0);
}

void AddModel()
{
	Py_INCREF(cast(PyObject*)&SModelType);
    PyModule_AddObject(Module, "Model", cast(PyObject*)&SModelType);
}

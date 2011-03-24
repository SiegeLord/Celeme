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

module pyceleme.neurongroup;

import celeme.capi;
import celeme.imodel;
import celeme.ineurongroup;
import celeme.recorder;

import pyceleme.main;
import pyceleme.recorder;
import python.python;

import tango.stdc.stringz;
import tango.io.Stdout;

struct SNeuronGroup
{
    mixin PyObject_HEAD;
    INeuronGroup Group;
}

extern (C)
void SNeuronGroup_dealloc(SNeuronGroup* self)
{
	self.ob_type.tp_free(cast(PyObject*)self);
}

extern (C)
PyObject* SNeuronGroup_new(PyTypeObject *type, PyObject* args, PyObject* kwds)
{
	auto self = cast(SNeuronGroup*)type.tp_alloc(type, 0);
	if(self !is null) 
		self.Group = null;

	return cast(PyObject*)self;
}

extern (C)
int SNeuronGroup_init(SNeuronGroup *self, PyObject* args, PyObject* kwds)
{
	PyErr_SetString(Error, "Cannot create a neuron group explicitly (get it from the model).");
	return -1;
}

PyMemberDef[] SNeuronGroup_members = 
[
    {null}
];

extern(C)
PyObject* SNeuronGroup_get_min_dt(SNeuronGroup *self, void *closure)
{
	auto ret = Py_BuildValue("d", celeme_get_min_dt(self.Group));
	mixin(ErrorCheck("null"));
    return ret;
}

extern(C)
int SNeuronGroup_set_min_dt(SNeuronGroup *self, PyObject *value, void *closure)
{
	if(value is null)
	{
		PyErr_SetString(Error, "Cannot delete the MinDt attribute");
		return -1;
	}

	double val;

	if(PyArg_Parse(value, "d", &val))
		celeme_set_min_dt(self.Group, val);
	else
	{
		PyErr_SetString(Error, "Expected a double");
		return -1;
	}
	
	mixin(ErrorCheck("-1"));
	return 0;
}

extern(C)
PyObject* SNeuronGroup_get_count(SNeuronGroup *self, void *closure)
{
	auto ret = Py_BuildValue("i", celeme_get_count(self.Group));
	mixin(ErrorCheck("null"));
    return ret;
}

PyGetSetDef[] SNeuronGroup_getseters = 
[
	{"MinDt", cast(getter)&SNeuronGroup_get_min_dt, cast(setter)&SNeuronGroup_set_min_dt, "TimeStepSize", null},
	{"Count", cast(getter)&SNeuronGroup_get_count, null, "Count", null},
	{null}  /* Sentinel */
];

extern (C)
PyObject* SNeuronGroup_stop_recording(SNeuronGroup *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["neuron_id", null];
	int neuron_id;

	if(!DParseTupleAndKeywords(args, kwds, "i", kwlist, &neuron_id))
		return null;
	
	celeme_stop_recording(self.Group, neuron_id);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

extern (C)
PyObject* SNeuronGroup_record(SNeuronGroup *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["neuron_id", "flags", null];
	int neuron_id;
	int flags;

	if(!DParseTupleAndKeywords(args, kwds, "ii", kwlist, &neuron_id, &flags))
		return null;
	
	auto rec = celeme_record(self.Group, neuron_id, flags);
	mixin(ErrorCheck("null"));
	
	auto ret = SRecorder_new(&SRecorderType, null, null);
	(cast(SRecorder*)ret).Recorder = rec;
	
	return ret;
}

extern (C)
PyObject* SNeuronGroup_seed(SNeuronGroup *self, PyObject* args, PyObject* kwds)
{
	char[][] kwlist = ["seed", null];
	int seed;

	if(!DParseTupleAndKeywords(args, kwds, "i", kwlist, &seed))
		return null;
	
	celeme_seed(self.Group, seed);
	
	mixin(ErrorCheck("null"));
	Py_INCREF(Py_None);
	return Py_None;
}

PyMethodDef[] SNeuronGroup_methods = 
[
    {"StopRecording", cast(PyCFunction)&SNeuronGroup_stop_recording, METH_VARARGS | METH_KEYWORDS, "Stop recording from a particular neuron."},
    {"Record", cast(PyCFunction)&SNeuronGroup_record, METH_VARARGS | METH_KEYWORDS, "Set the record flags of a particular neuron."},
    {"Seed", cast(PyCFunction)&SNeuronGroup_seed, METH_VARARGS | METH_KEYWORDS, "Set the seed for the random number generator."},
    {null}  /* Sentinel */
];

extern(C)
PyObject* SNeuronGroup_getitem(SNeuronGroup* self, PyObject* args)
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
	int nrn_id = -1;
	int syn_id = -1;
	
	if(!PyArg_ParseTuple(new_args, "s|ii", &name, &nrn_id, &syn_id))
		return null;
		
	double ret;
		
	if(nrn_id < 0)
		ret = celeme_get_constant(self.Group, name);
	else if(syn_id < 0)
		ret = celeme_get_global(self.Group, name, nrn_id);
	else
		ret = celeme_get_syn_global(self.Group, name, nrn_id, syn_id);

	mixin(ErrorCheck("null"));
	return Py_BuildValue("d", ret);
}

int SNeuronGroup_setitem(SNeuronGroup* self, PyObject* args, PyObject* val)
{
	PyObject* new_args = args;
	
	double dval;
	
	if(!PyFloat_Check(val) && !PyInt_Check(val))
	{
		PyErr_SetString(Error, "must assign a number");
		return -1;
	}
	
	dval = PyFloat_AsDouble(val);
	
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
	int nrn_id = -1;
	int syn_id = -1;
	
	if(!PyArg_ParseTuple(new_args, "s|ii", &name, &nrn_id, &syn_id))
		return -1;
		
	if(nrn_id < 0)
		celeme_set_constant(self.Group, name, dval);
	else if(syn_id < 0)
		celeme_set_global(self.Group, name, nrn_id, dval);
	else
		celeme_set_syn_global(self.Group, name, nrn_id, syn_id, dval);
		
	mixin(ErrorCheck("-1"));
	return 0;
}

PyMappingMethods SNeuronGroupMapping = 
{
	null,
	cast(binaryfunc)&SNeuronGroup_getitem,
	cast(objobjargproc)&SNeuronGroup_setitem
};

PyTypeObject SNeuronGroupType = 
{
    0,                         /*ob_refcnt*/
    null,                      /*ob_type*/
	0,                         /*ob_size*/
	"pyceleme.NeuronGroup",             /*tp_name*/
	SNeuronGroup.sizeof,             /*tp_basicsize*/
	0,                         /*tp_itemsize*/
	cast(destructor)&SNeuronGroup_dealloc, /*tp_dealloc*/
	null,                      /*tp_print*/
	null,                      /*tp_getattr*/
	null,                      /*tp_setattr*/
	null,                      /*tp_compare*/
	null,                      /*tp_repr*/
	null,                      /*tp_as_number*/
	null,                      /*tp_as_sequence*/
	&SNeuronGroupMapping,                      /*tp_as_mapping*/
	null,                      /*tp_hash */
	null,                      /*tp_call*/
	null,                      /*tp_str*/
	null,                      /*tp_getattro*/
	null,                      /*tp_setattro*/
	null,                      /*tp_as_buffer*/
	Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE, /*tp_flags*/
	"NeuronGroup objects",           /* tp_doc */
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
	cast(initproc)&SNeuronGroup_init,  /* tp_init */
	null,                      /* tp_alloc */
	&SNeuronGroup_new,                 /* tp_new */
};

static this()
{
	SNeuronGroupType.tp_methods = SNeuronGroup_methods.ptr;
	SNeuronGroupType.tp_members = SNeuronGroup_members.ptr;
	SNeuronGroupType.tp_getset = SNeuronGroup_getseters.ptr;
}

void PreInitNeuronGroup()
{
	if(PyType_Ready(&SNeuronGroupType) < 0)
		assert(0);
}

void AddNeuronGroup()
{
	Py_INCREF(cast(PyObject*)&SNeuronGroupType);
    PyModule_AddObject(Module, "NeuronGroup", cast(PyObject*)&SNeuronGroupType);
}

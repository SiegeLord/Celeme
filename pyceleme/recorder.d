module pyceleme.recorder;

import celeme.capi;
import celeme.recorder;

import pyceleme.main;
import pyceleme.array;
import python.python;

import tango.stdc.stringz;
import tango.io.Stdout;

struct SRecorder
{
    mixin PyObject_HEAD;
    CRecorder Recorder;
}

extern (C)
void SRecorder_dealloc(SRecorder* self)
{
	self.ob_type.tp_free(cast(PyObject*)self);
}

extern (C)
PyObject* SRecorder_new(PyTypeObject *type, PyObject* args, PyObject* kwds)
{
	auto self = cast(SRecorder*)type.tp_alloc(type, 0);
	if(self !is null) 
		self.Recorder = null;

	return cast(PyObject*)self;
}

extern (C)
int SRecorder_init(SRecorder *self, PyObject* args, PyObject* kwds)
{
	PyErr_SetString(Error, "Cannot create a Recorder explicitly (get it from the neuron group).");
	return -1;
}

PyMemberDef[] SRecorder_members = 
[
    {null}
];

extern(C)
PyObject* SRecorder_get_length(SRecorder *self, void *closure)
{
	auto ret = Py_BuildValue("i", celeme_get_recorder_length(self.Recorder));
	mixin(ErrorCheck("null"));
    return ret;
}

extern(C)
PyObject* SRecorder_get_name(SRecorder *self, void *closure)
{
	auto ret = Py_BuildValue("s", celeme_get_recorder_name(self.Recorder));
	mixin(ErrorCheck("null"));
    return ret;
}

extern(C)
PyObject* SRecorder_get_t(SRecorder *self, void *closure)
{
	auto ret = SArray_new(&SArrayType, null, null);
	mixin(ErrorCheck("null"));
	
	auto len = celeme_get_recorder_length(self.Recorder);
	auto t = celeme_get_recorder_time(self.Recorder);
	
	(cast(SArray*)ret).Data = t[0..len];
	
    return ret;
}

extern(C)
PyObject* SRecorder_get_data(SRecorder *self, void *closure)
{
	auto ret = SArray_new(&SArrayType, null, null);
	mixin(ErrorCheck("null"));
	
	auto len = celeme_get_recorder_length(self.Recorder);
	auto data = celeme_get_recorder_data(self.Recorder);
	
	(cast(SArray*)ret).Data = data[0..len];
	
    return ret;
}

PyGetSetDef[] SRecorder_getseters = 
[
	{"Length", cast(getter)&SRecorder_get_length, null, "Length", null},
	{"Name", cast(getter)&SRecorder_get_name, null, "Name", null},
	{"T", cast(getter)&SRecorder_get_t, null, "Time", null},
	{"Data", cast(getter)&SRecorder_get_data, null, "Data", null},
	{null}  /* Sentinel */
];

PyMethodDef[] SRecorder_methods = 
[
    {null}  /* Sentinel */
];

PyTypeObject SRecorderType = 
{
    0,                         /*ob_refcnt*/
    null,                      /*ob_type*/
	0,                         /*ob_size*/
	"pyceleme.Recorder",             /*tp_name*/
	SRecorder.sizeof,             /*tp_basicsize*/
	0,                         /*tp_itemsize*/
	cast(destructor)&SRecorder_dealloc, /*tp_dealloc*/
	null,                      /*tp_print*/
	null,                      /*tp_getattr*/
	null,                      /*tp_setattr*/
	null,                      /*tp_compare*/
	null,                      /*tp_repr*/
	null,                      /*tp_as_number*/
	null,                      /*tp_as_sequence*/
	null,                      /*tp_as_mapping*/
	null,                      /*tp_hash */
	null,                      /*tp_call*/
	null,                      /*tp_str*/
	null,                      /*tp_getattro*/
	null,                      /*tp_setattro*/
	null,                      /*tp_as_buffer*/
	Py_TPFLAGS_DEFAULT | Py_TPFLAGS_BASETYPE, /*tp_flags*/
	"Recorder objects",           /* tp_doc */
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
	cast(initproc)&SRecorder_init,  /* tp_init */
	null,                      /* tp_alloc */
	&SRecorder_new,                 /* tp_new */
};

static this()
{
	SRecorderType.tp_methods = SRecorder_methods.ptr;
	SRecorderType.tp_members = SRecorder_members.ptr;
	SRecorderType.tp_getset = SRecorder_getseters.ptr;
}

void PreInitRecorder()
{
	if(PyType_Ready(&SRecorderType) < 0)
		assert(0);
}

void AddRecorder()
{
	Py_INCREF(cast(PyObject*)&SRecorderType);
    PyModule_AddObject(Module, "Recorder", cast(PyObject*)&SRecorderType);
}

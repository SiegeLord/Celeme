module pyceleme.array;

import pyceleme.main;
import python.python;

import tango.stdc.stringz;
import tango.io.Stdout;

struct SArray
{
    mixin PyObject_HEAD;
    double[] Data;
}

extern (C)
void SArray_dealloc(SArray* self)
{
	self.ob_type.tp_free(cast(PyObject*)self);
}

extern (C)
PyObject* SArray_new(PyTypeObject *type, PyObject* args, PyObject* kwds)
{
	auto self = cast(SArray*)type.tp_alloc(type, 0);
	if(self !is null) 
		self.Array = null;

	return cast(PyObject*)self;
}

extern (C)
int SArray_init(SArray *self, PyObject* args, PyObject* kwds)
{
	PyErr_SetString(Error, "Cannot create a Array explicitly (get it from the neuron group).");
	return -1;
	/+self.Data = [1.0, 2.0, 3.0, 4.0, 5.0];
	return 0;+/
}

PyMemberDef[] SArray_members = 
[
    {null}
];

extern(C)
PyObject* SArray_get_array_interface(Noddy *self, void *closure)
{
	auto ret = PyDict_New();
	
	version(X86_64)
	{
		PyDict_SetItemString(ret, "shape", Py_BuildValue("(L)", cast(long)self.Data.length));
		PyDict_SetItemString(ret, "data", Py_BuildValue("(L, i)", cast(long)self.Data.ptr, 1));
	}
	else
	{
		PyDict_SetItemString(ret, "shape", Py_BuildValue("(i)", cast(int)self.Data.length));
		PyDict_SetItemString(ret, "data", Py_BuildValue("(i, i)", cast(int)self.Data.ptr, 1));
	}

	/* TODO: Endianness */
	PyDict_SetItemString(ret, "typestr", PyString_FromString("<f8"));
	PyDict_SetItemString(ret, "version", Py_BuildValue("i", 3));
	
    return ret;
}

PyGetSetDef[] SArray_getseters = 
[
	{"__array_interface__", cast(getter)&SArray_get_array_interface, null, "The array interface.", null},
	{null}  /* Sentinel */
];

PyMethodDef[] SArray_methods = 
[
    {null}  /* Sentinel */
];

PyTypeObject SArrayType = 
{
    0,                         /*ob_refcnt*/
    null,                      /*ob_type*/
	0,                         /*ob_size*/
	"pyceleme.Array",             /*tp_name*/
	SArray.sizeof,             /*tp_basicsize*/
	0,                         /*tp_itemsize*/
	cast(destructor)&SArray_dealloc, /*tp_dealloc*/
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
	"Array objects",           /* tp_doc */
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
	cast(initproc)&SArray_init,  /* tp_init */
	null,                      /* tp_alloc */
	&SArray_new,                 /* tp_new */
};

static this()
{
	SArrayType.tp_methods = SArray_methods.ptr;
	SArrayType.tp_members = SArray_members.ptr;
	SArrayType.tp_getset = SArray_getseters.ptr;
}

void PreInitArray()
{
	if(PyType_Ready(&SArrayType) < 0)
		assert(0);
}

void AddArray()
{
	Py_INCREF(cast(PyObject*)&SArrayType);
    PyModule_AddObject(Module, "Array", cast(PyObject*)&SArrayType);
}

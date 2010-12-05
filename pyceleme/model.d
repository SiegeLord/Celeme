module pyceleme.model;

import celeme.capi;
import celeme.imodel;
import celeme.ineurongroup;

import pyceleme.main;
import python.python;

import tango.stdc.stringz;

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
PyObject* SModel_new(PyTypeObject *type, PyObject *args, PyObject *kwds)
{
	auto self = cast(SModel*)type.tp_alloc(type, 0);
	if(self !is null) 
		self.Model = null;

	return cast(PyObject*)self;
}

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

extern (C)
int SModel_init(SModel *self, PyObject *args, PyObject *kwds)
{
	char[][] kwlist = ["file", null];
	char* str;

	if(!DParseTupleAndKeywords(args, kwds, "s", kwlist, &str))
		return -1;
	
	self.Model = celeme_load_model(str);
	
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
PyObject* SModel_generate(SModel *self, PyObject *args, PyObject *kwds)
{
	char[][] kwlist = ["parallel_delivery", "atomic_delivery", "initialize", null];
	int parallel_delivery = 1;
	int atomic_delivery = 1;
	int initialize = 1;

	if(!DParseTupleAndKeywords(args, kwds, "|iii", kwlist, &parallel_delivery, &atomic_delivery, &initialize))
		return null;
	
	celeme_generate_model(self.Model, parallel_delivery == 1, atomic_delivery == 1, initialize == 1);
	
	mixin(ErrorCheck("null"));
	return Py_None;
}

PyMethodDef[] SModel_methods = 
[
    {"Generate", cast(PyCFunction)&SModel_generate, METH_VARARGS | METH_KEYWORDS, "Generate the model"},
    {null}  /* Sentinel */
];

extern(C)
PyObject* SModel_getitem(PyObject *self, PyObject *args)
{
	int a, b;
	
	PyObject* new_args = args;
	
	bool dec_ref_args = false;
	scope(exit)
	{
		if(dec_ref_args)
		{
			Py_DECREF(args);
			Py_DECREF(new_args);
		}
	}
	
	if(!PyTuple_Check(args))
	{
		new_args = Py_BuildValue("(O)", args);
		dec_ref_args = true;
	}
	
	if(!PyArg_ParseTuple(new_args, "i|i", &a, &b))
		return null;

	return Py_BuildValue("i", a + b);
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

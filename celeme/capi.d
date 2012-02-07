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

/**
 * This module contains the C api to Celeme. 
 * Currently only static linking is supported.
 * 
 * It is critical to check for errors after each call to Celeme.
 * Error codes are not used, instead you should check for the error as follows:
 * 
 * ---
 * const char* error;
 * CELEME_MODEL* model = celeme_load_model("model.cfg", 0, NULL, true, false);
 * if(error = celeme_get_error())
 *     printf("%s\n", error);
 * ---
 */

module celeme.capi;

import celeme.celeme;
import celeme.internal.clmodel;
import celeme.internal.util;

import tango.stdc.stringz;
import tango.core.Runtime;
import tango.core.Array;
import tango.stdc.stdlib : atexit;

bool Inited = false;
bool Registered = false;
IModel[] Models;
cstring ErrorText;

bool iser(T)(T a, T b)
{
	return a is b;
}

extern(C):

/**
 * Initializes Celeme. Registers celeme_shutdown to happen when
 * the program exits.
 * 
 * C signature:
 * ---
 * void celeme_init(void);
 * ---
 */
void celeme_init()
{
	if(!Inited)
	{
		Runtime.initialize();
		if(!Registered)
		{
			atexit(&celeme_shutdown);
			Registered = true;
		}
	}
	
	Inited = true;
}

/**
 * Shuts Celeme down. Normally you do not need to call this function
 * explicitly, as it gets called automatically when the program exits.
 * 
 * C signature:
 * ---
 * void celeme_shutdown(void);
 * ---
 */
void celeme_shutdown()
{
	if(Inited)
	{
		Inited = false;
		Runtime.terminate();
		
		foreach(model; Models)
			model.Dispose();
		
		Models.length = 0;
	}
}

/**
 * Checks to see if any errors occured.
 * Returns: 
 * A zero terminated string describing the error, or NULL if
 * no error has occurred.
 * 
 * C signature:
 * ---
 * const char* celeme_get_error(void);
 * ---
 */
const(char)* celeme_get_error()
{
	if(ErrorText == "")
		return null;
	else
		return ErrorText.c_str();
}

/**
 * Sets the error to a certain string. Useful when you want to reset the error
 * to be empty, if you managed to recover from a previous error.
 * 
 * Params:
 *     error = New error string. Can be NULL.
 * 
 * C signature:
 * ---
 * void celeme_set_error(const char* error);
 * ---
 */
void celeme_set_error(const(char)* error)
{
	if(error is null)
		ErrorText = null;
	else
		ErrorText = fromStringz(error);
}

/*
 * Model bindings
 */

/**
 * Loads a model from a configuration file.
 * 
 * See_Also: $(SYMLINK LoadModel, LoadModel)
 * 
 * C signature:
 * ---
 * CELEME_MODEL* celeme_load_model(const char* file, size_t num_includes, const char** include_dirs, bool gpu, bool double_precision);
 * ---
 */
IModel celeme_load_model(const(char)* file, size_t num_includes, const(char)** include_dirs, bool gpu, bool double_precision)
{
	try
	{
		auto include_arr = new cstring[](num_includes);
		foreach(idx, ref include; include_arr)
		{
			include = fromStringz(include_dirs[idx]).dup;
		}
		
		return LoadModel(fromStringz(file), include_arr, gpu, double_precision);
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return null;
}

/+enum : int
{
	MODEL_FLOAT,
	MODEL_DOUBLE
}

IModel celeme_create_model(int type, bool gpu)
{
	try
	{
		IModel ret;
		if(type == MODEL_FLOAT)
			ret = CreateCLModel!(float)(gpu);
		else if(type == MODEL_DOUBLE)
			ret = CreateCLModel!(double)(gpu);
		else
		{
			ErrorText = "Invalid model type.";
		}
		
		if(ret !is null)
			Models ~= ret;
		
		return ret;
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return null;
}+/

/**
 * Destroys a model. Called automatically when celeme_shutdown() is called, but can be done
 * explicitly as well.
 * 
 * Params:
 *     model - Model to destroy.
 * 
 * See_Also: 
 *     $(SYMLINK2 celeme.imodel, IModel.Dispose, IModel.Dispose)
 * 
 * C signature:
 * ---
 * void celeme_destroy_model(CELEME_MODEL* model);
 * ---
 */
void celeme_destroy_model(IModel model)
{
	try
	{
		assert(model);
		auto len = Models.remove(model, &iser!(IModel));
		if(len < Models.length)
		{
			Models[$ - 1].Dispose();
			Models.length = len;
		}
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
}

version(Doc)
{

/**
 * Initializes the model.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.Initialize, IModel.Initialize)
 * 
 * C signature:
 * ---
 * void celeme_initialize_model(CELEME_MODEL* model);
 * ---
 */
void celeme_initialize_model(IModel model);

/**
 * Generates the model.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.Generate, IModel.Generate)
 * 
 * C signature:
 * ---
 * void celeme_generate_model(CELEME_MODEL* model, bool initialize);
 * ---
 */
void celeme_generate_model(IModel model, bool initialize);

/**
 * Adds a new neuron group from an internal registry.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.AddNeuronGroup, IModel.AddNeuronGroup)
 * 
 * C signature:
 * ---
 * void celeme_add_neuron_group(CELEME_MODEL* model, const char* type_name, size_t number, const char* name, bool adaptive_dt, bool parallel_delivery);
 * ---
 */
void celeme_add_neuron_group(IModel model, const(char)* type_name, size_t number, const(char)* name, bool adaptive_dt, bool parallel_delivery);

/**
 * Returns a neuron group based on its name.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.opIndex, IModel.opIndex)
 * 
 * C signature:
 * ---
 * CELEME_NEURON_GROUP* celeme_get_neuron_group(CELEME_MODEL* model, const char* name);
 * ---
 */
INeuronGroup celeme_get_neuron_group(IModel model, const(char)* name);

/**
 * Run the model.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.Run, IModel.Run)
 * 
 * C signature:
 * ---
 * void celeme_run(CELEME_MODEL* model, size_t num_timesteps);
 * ---
 */
void celeme_run(IModel model, size_t num_timesteps);

/**
 * Reset the run of the model.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.ResetRun, IModel.ResetRun)
 * 
 * C signature:
 * ---
 * void celeme_reset_run(CELEME_MODEL* model);
 * ---
 */
void celeme_reset_run(IModel model);

/**
 * Initialize the run of the model.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.InitRun, IModel.InitRun)
 * 
 * C signature:
 * ---
 * void celeme_init_run(CELEME_MODEL* model);
 * ---
 */
void celeme_init_run(IModel model);

/**
 * Run the model until some time.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.RunUntil, IModel.RunUntil)
 * 
 * C signature:
 * ---
 * void celeme_run_until(CELEME_MODEL* model, size_t num_timesteps);
 * ---
 */
void celeme_run_until(IModel model, size_t num_timesteps);

/**
 * Set a connection between two neurons in a model.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.SetConnection, IModel.SetConnection)
 * 
 * C signature:
 * ---
 * void celeme_set_connection(CELEME_MODEL* model, const char* src_group, size_t src_nrn_id, size_t src_event_source, size_t src_slot, const char* dest_group, size_t dest_nrn_id, size_t dest_syn_type, size_t dest_slot);
 * ---
 */
void celeme_set_connection(IModel model, const(char)* src_group, size_t src_nrn_id, size_t src_event_source, size_t src_slot, const(char)* dest_group, size_t dest_nrn_id, size_t dest_syn_type, size_t dest_slot);

/**
 * Connecto two neurons in a model.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.Connect, IModel.Connect)
 * 
 * C signature:
 * ---
 * CELEME_SLOTS celeme_connect(CELEME_MODEL* model, const char* src_group, size_t src_nrn_id, size_t src_event_source, const char* dest_group, size_t dest_nrn_id, size_t dest_syn_type);
 * ---
 */
IModel.SSlots celeme_connect(IModel model, const(char)* src_group, size_t src_nrn_id, size_t src_event_source, const(char)* dest_group, size_t dest_nrn_id, size_t dest_syn_type);

/**
 * Apply a connector.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.ApplyConnector, IModel.ApplyConnector)
 * 
 * C signature:
 * ---
 * void celeme_apply_connector(CELEME_MODEL* model, const char* connector_name, size_t multiplier, const char* src_group, size_t src_nrn_start, size_t src_nrn_end, size_t src_event_source, const char* dest_group, size_t dest_nrn_start, size_t dest_nrn_end, size_t dest_syn_type, size_t argc, const char** arg_keys, double* arg_vals);
 * ---
 */
void celeme_apply_connector(IModel model, const(char)* connector_name, size_t multiplier, const(char)* src_group, size_t src_nrn_start, size_t src_nrn_end, size_t src_event_source, const(char)* dest_group, size_t dest_nrn_start, size_t dest_nrn_end, size_t dest_syn_type, size_t argc, const(char)** arg_keys, double* arg_vals);

/**
 * Return the timestep size.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.TimeStepSize, IModel.TimeStepSize)
 * 
 * C signature:
 * ---
 * double celeme_get_timestep_size(CELEME_MODEL* model);
 * ---
 */
double celeme_get_timestep_size(IModel model);

/**
 * Set the timestep size.
 * 
 * See_Also: $(SYMLINK2 celeme.imodel, IModel.TimeStepSize, IModel.TimeStepSize)
 * 
 * C signature:
 * ---
 * void celeme_set_timestep_size(CELEME_MODEL* model, double val);
 * ---
 */
void celeme_set_timestep_size(IModel model, double val);


/**
 * Get the value of a constant, or the default value of a global or a syn global.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.TimeStepSize, INeuronGroup.TimeStepSize)
 * 
 * C signature:
 * ---
 * double celeme_get_constant(CELEME_NEURON_GROUP* group, const char* name);
 * ---
 */
double celeme_get_constant(INeuronGroup group, const(char)* name);

/**
 * Set the value of a constant, or the default value of a global or a syn global.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.opIndexAssign, INeuronGroup.opIndexAssign)
 * 
 * C signature:
 * ---
 * double celeme_set_constant(CELEME_NEURON_GROUP* group, const char* name, double val);
 * ---
 */
double celeme_set_constant(INeuronGroup group, const(char)* name, double val);

/**
 * Get the value of a global.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.opIndex, INeuronGroup.opIndex)
 * 
 * C signature:
 * ---
 * double celeme_get_global(CELEME_NEURON_GROUP* group, const char* name, size_t idx);
 * ---
 */
double celeme_get_global(INeuronGroup group, const(char)* name, size_t idx);

/**
 * Set the value of a global.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.opIndexAssign, INeuronGroup.opIndexAssign)
 * 
 * C signature:
 * ---
 * double celeme_set_global(CELEME_NEURON_GROUP* group, const char* name, size_t idx, double val);
 * ---
 */
double celeme_set_global(INeuronGroup group, const(char)* name, size_t idx, double val);

/**
 * Get the value of a syn global.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.opIndex, INeuronGroup.opIndex)
 * 
 * C signature:
 * ---
 * double celeme_get_syn_global(CELEME_NEURON_GROUP* group, const char* name, size_t nrn_idx, size_t syn_idx);
 * ---
 */
double celeme_get_syn_global(INeuronGroup group, const(char)* name, size_t nrn_idx, size_t syn_idx);

/**
 * Set the value of a syn global.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.opIndexAssign, INeuronGroup.opIndexAssign)
 * 
 * C signature:
 * ---
 * double celeme_set_syn_global(CELEME_NEURON_GROUP* group, const char* name, size_t nrn_idx, size_t syn_idx, double val);
 * ---
 */
double celeme_set_syn_global(INeuronGroup group, const(char)* name, size_t nrn_idx, size_t syn_idx, double val);

/**
 * Set the recording flags of a single neuron.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.Record, INeuronGroup.Record)
 * 
 * C signature:
 * ---
 * CELEME_RECORDER* celeme_record(CELEME_NEURON_GROUP* group, size_t nrn_idx, int flags);
 * ---
 */
CRecorder celeme_record(INeuronGroup group, size_t nrn_idx, int flags);

/**
 * Stop all recording in a particular neuron.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.StopRecording, INeuronGroup.StopRecording)
 * 
 * C signature:
 * ---
 * void celeme_stop_recording(CELEME_NEURON_GROUP* group, size_t neuron_id);
 * ---
 */
void celeme_stop_recording(INeuronGroup group, size_t neuron_id);

/**
 * Get the minimum dt.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.MinDt, INeuronGroup.MinDt)
 * 
 * C signature:
 * ---
 * double celeme_get_min_dt(CELEME_NEURON_GROUP* group);
 * ---
 */
double celeme_get_min_dt(INeuronGroup group);

/**
 * Set the minimum dt.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.MinDt, INeuronGroup.MinDt)
 * 
 * C signature:
 * ---
 * void celeme_set_min_dt(CELEME_NEURON_GROUP* group, double min_dt);
 * ---
 */
void celeme_set_min_dt(INeuronGroup group, double min_dt);

/**
 * Get the number of neurons in this group.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.Count, INeuronGroup.Count)
 * 
 * C signature:
 * ---
 * size_t celeme_get_count(CELEME_NEURON_GROUP* group);
 * ---
 */
size_t celeme_get_count(INeuronGroup group);

/**
 * Returns the global index of the first neuron in this neuron group.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.NrnOffset, INeuronGroup.NrnOffset)
 * 
 * C signature:
 * ---
 * size_t celeme_get_nrn_offset(CELEME_NEURON_GROUP* group);
 * ---
 */
size_t celeme_get_nrn_offset(INeuronGroup group);

/**
 * Seeds the random number generator.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.Seed, INeuronGroup.Seed)
 * 
 * C signature:
 * ---
 * int celeme_seed(CELEME_NEURON_GROUP* group, int seed);
 * ---
 */
int celeme_seed(INeuronGroup group);

/**
 * Returns the target global neuron id that an event source is connected to at a specified source slot.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.GetConnectionId, INeuronGroup.GetConnectionId)
 * 
 * C signature:
 * ---
 * int celeme_get_connection_id(CELEME_NEURON_GROUP* group, size_t nrn_id, size_t event_source, size_t src_slot);
 * ---
 */
int celeme_get_connection_id(INeuronGroup group, size_t nrn_id, size_t event_source, size_t src_slot);

/**
 * Returns the target slot that an event source is connected to at a specified source slot.
 * 
 * See_Also: $(SYMLINK2 celeme.ineurongroup, INeuronGroup.GetConnectionSlot, INeuronGroup.GetConnectionSlot)
 * 
 * C signature:
 * ---
 * int celeme_get_connection_slot(CELEME_NEURON_GROUP* group, size_t nrn_id, size_t event_source, size_t src_slot);
 * ---
 */
int celeme_get_connection_slot(INeuronGroup group, size_t nrn_id, size_t event_source, size_t src_slot);
}
else
{

@property
cstring ModelFunc(cstring c_name, cstring ret, cstring d_name, cstring args, cstring call_args, cstring def_ret)()
{
	cstring ret_str = 
ret ~ ` celeme_` ~ c_name ~ `(IModel model` ~ args ~ `)
{
	try
	{
		assert(model);
`;
	if(ret != "void")
		ret_str ~= 
`		return `;
	else
		ret_str ~=
`		`;
	
	ret_str ~= `model.` ~ d_name ~ `(` ~ call_args ~ `);
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return ` ~ def_ret ~ `;
}
`;
	return ret_str;
}

mixin(ModelFunc!("initialize_model", "void", "Initialize", "", "", ""));

mixin(ModelFunc!("add_neuron_group", "void", "AddNeuronGroup", 
	", const(char)* type_name, size_t number, const(char)* name, bool adaptive_dt, bool parallel_delivery", 
	"fromStringz(type_name), number, fromStringz(name), adaptive_dt, parallel_delivery", ""));
mixin(ModelFunc!("generate_model", "void", "Generate", 
	", bool initialize", 
	"initialize", ""));

mixin(ModelFunc!("get_neuron_group", "INeuronGroup", "opIndex", 
	", const(char)* name", 
	"fromStringz(name)", "null"));
	
mixin(ModelFunc!("run", "void", "Run", 
	", size_t num_timesteps", 
	"num_timesteps", ""));
mixin(ModelFunc!("reset_run", "void", "ResetRun", "", "", ""));
mixin(ModelFunc!("init_run", "void", "InitRun", "", "", ""));
mixin(ModelFunc!("run_until", "void", "RunUntil", 
	", size_t num_timesteps", 
	"num_timesteps", ""));
	
mixin(ModelFunc!("set_connection", "void", "SetConnection", 
	", const(char)* src_group, size_t src_nrn_id, size_t src_event_source, size_t src_slot, const(char)* dest_group, size_t dest_nrn_id, size_t dest_syn_type, size_t dest_slot", 
	"fromStringz(src_group), src_nrn_id, src_event_source, src_slot, fromStringz(dest_group), dest_nrn_id, dest_syn_type, dest_slot", ""));
	
mixin(ModelFunc!("connect", "IModel.SSlots", "Connect", 
	", const(char)* src_group, size_t src_nrn_id, size_t src_event_source, const(char)* dest_group, size_t dest_nrn_id, size_t dest_syn_type", 
	"fromStringz(src_group), src_nrn_id, src_event_source, fromStringz(dest_group), dest_nrn_id, dest_syn_type", "IModel.SSlots(-1, -1)"));
	
void celeme_apply_connector(IModel model, const(char)* connector_name, size_t multiplier, const(char)* src_group, size_t src_nrn_start, size_t src_nrn_end, size_t src_event_source, const(char)* dest_group, size_t dest_nrn_start, size_t dest_nrn_end, size_t dest_syn_type, size_t argc, const(char)** arg_keys, double* arg_vals)
{
	try
	{
		assert(model);
		double[char[]] d_args;
		foreach(ii; range(argc))
		{
			d_args[fromStringz(arg_keys[ii]).idup] = arg_vals[ii];
		}
		model.ApplyConnector(fromStringz(connector_name), multiplier, fromStringz(src_group), [src_nrn_start, src_nrn_end], src_event_source, fromStringz(dest_group), [dest_nrn_start, dest_nrn_end], dest_syn_type, d_args);
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
}

mixin(ModelFunc!("get_timestep_size", "double", "TimeStepSize", 
	"", 
	"", "-1"));
	
mixin(ModelFunc!("set_timestep_size", "void", "TimeStepSize", 
	", double val", 
	"val", ""));

/*
 * Neuron group bindings
 */

@property
cstring GroupFunc(cstring c_name, cstring ret, cstring d_name, cstring args, cstring call_args, cstring def_ret)()
{
	cstring ret_str = 
ret ~ ` celeme_` ~ c_name ~ `(INeuronGroup group` ~ args ~ `)
{
	try
	{
`;
	if(ret != "void")
		ret_str ~= 
`		return `;
	else
		ret_str ~=
`		`;
	
	ret_str ~= `group.` ~ d_name ~ `(` ~ call_args ~ `);
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return ` ~ def_ret ~ `;
}
`;
	return ret_str;
}

mixin(GroupFunc!("get_constant", "double", "opIndex", 
	", const(char)* name", 
	"fromStringz(name)", "-1.0"));
	
mixin(GroupFunc!("set_constant", "double", "opIndexAssign", 
	", const(char)* name, double val", 
	"val, fromStringz(name)", "-1.0"));
	
mixin(GroupFunc!("get_global", "double", "opIndex", 
	", const(char)* name, size_t idx", 
	"fromStringz(name), idx", "-1.0"));
	
mixin(GroupFunc!("set_global", "double", "opIndexAssign", 
	", const(char)* name, size_t idx, double val", 
	"val, fromStringz(name), idx", "-1.0"));
	
mixin(GroupFunc!("get_syn_global", "double", "opIndex", 
	", const(char)* name, size_t nrn_idx, size_t syn_idx", 
	"fromStringz(name), nrn_idx, syn_idx", "-1.0"));
	
mixin(GroupFunc!("set_syn_global", "double", "opIndexAssign", 
	", const(char)* name, size_t nrn_idx, size_t syn_idx, double val", 
	"val, fromStringz(name), nrn_idx, syn_idx", "-1.0"));
	
mixin(GroupFunc!("record", "CRecorder", "Record", 
	", size_t nrn_idx, int flags", 
	"nrn_idx, flags", "null"));
	
mixin(GroupFunc!("stop_recording", "void", "StopRecording", 
	", size_t neuron_id", 
	"neuron_id", ""));

mixin(GroupFunc!("get_min_dt", "double", "MinDt", 
	"", 
	"", "-1"));
	
mixin(GroupFunc!("set_min_dt", "void", "MinDt", 
	", double min_dt", 
	"min_dt", ""));
	
mixin(GroupFunc!("get_count", "size_t", "Count", 
	"", 
	"", "0"));
	
mixin(GroupFunc!("get_nrn_offset", "size_t", "NrnOffset", 
	"", 
	"", "-1"));
	
mixin(GroupFunc!("seed", "void", "Seed", 
	", int seed", 
	"seed", ""));
	
mixin(GroupFunc!("get_connection_id", "int", "GetConnectionId", 
	", size_t nrn_id, size_t event_source, size_t src_slot", 
	"nrn_id, event_source, src_slot", "-1"));
	
mixin(GroupFunc!("get_connection_slot", "int", "GetConnectionSlot", 
	", size_t nrn_id, size_t event_source, size_t src_slot", 
	"nrn_id, event_source, src_slot", "-1"));
}

/*
 * Recorder
 */

/**
 * Get the recorder name.
 * 
 * See_Also: $(SYMLINK2 celeme.recorder, CRecorder.Name, CRecorder.Name)
 * 
 * C signature:
 * ---
 * const char* celeme_get_recorder_name(CELEME_RECORDER* recorder);
 * ---
 */
const(char)* celeme_get_recorder_name(CRecorder recorder)
{
	try
	{
		assert(recorder);
		return recorder.Name.c_str();
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return null;
}

/**
 * Get the length of the recorder data.
 * 
 * See_Also: $(SYMLINK2 celeme.recorder, CRecorder.Length, CRecorder.Length)
 * 
 * C signature:
 * ---
 * size_t celeme_get_recorder_length(CELEME_RECORDER* recorder);
 * ---
 */
size_t celeme_get_recorder_length(CRecorder recorder)
{
	try
	{
		assert(recorder);
		return recorder.Length;
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return 0;
}

/**
 * Get a pointer to an array of recorded time points.
 * 
 * See_Also: $(SYMLINK2 celeme.recorder, CRecorder.T, CRecorder.T)
 * 
 * C signature:
 * ---
 * double* celeme_get_recorder_time(CELEME_RECORDER* recorder);
 * ---
 */
double* celeme_get_recorder_time(CRecorder recorder)
{
	try
	{
		assert(recorder);
		return recorder.T.ptr;
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return null;
}

/**
 * Get a pointer to an array of recorded data points.
 * 
 * See_Also: $(SYMLINK2 celeme.recorder, CRecorder.Data, CRecorder.Data)
 * 
 * C signature:
 * ---
 * double* celeme_get_recorder_data(CELEME_RECORDER* recorder);
 * ---
 */
double* celeme_get_recorder_data(CRecorder recorder)
{
	try
	{
		assert(recorder);
		return recorder.Data.ptr;
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return null;
}

/**
 * Get a pointer to an array of recorded data point tags.
 * 
 * See_Also: $(SYMLINK2 celeme.recorder, CRecorder.Tags, CRecorder.Tags)
 * 
 * C signature:
 * ---
 * double* celeme_get_recorder_tags(CELEME_RECORDER* recorder);
 * ---
 */
int* celeme_get_recorder_tags(CRecorder recorder)
{
	try
	{
		assert(recorder);
		return recorder.Tags.ptr;
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return null;
}

/**
 * Get a pointer to an array of recorded data point neuron ids.
 * 
 * See_Also: $(SYMLINK2 celeme.recorder, CRecorder.NeuronIds, CRecorder.NeuronIds)
 * 
 * C signature:
 * ---
 * double* celeme_get_recorder_neuron_ids(CELEME_RECORDER* recorder);
 * ---
 */
size_t* celeme_get_recorder_neuron_ids(CRecorder recorder)
{
	try
	{
		assert(recorder);
		if(recorder.NeuronIds !is null)
			return recorder.NeuronIds.ptr;
		return
			null;
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return null;
}

/**
 * This module contains the C api to Celeme. 
 * Currently only static linking is supported.
 * 
 * It is critical to check for errors after each call to Celeme.
 * Error codes are not used, instead you should check for the error as follows:
 * 
 * ---
 * const char* error;
 * CELEME_MODEL* model = celeme_load_model("model.cfg", true);
 * if(error = celeme_get_error())
 *     printf("%s\n", error);
 * ---
 */

module celeme.capi;

import celeme.celeme;
import celeme.clmodel;
import celeme.util;

import tango.stdc.stringz;
import tango.core.Runtime;
import tango.core.Array;
import tango.stdc.stdlib : atexit;

bool Inited = false;
bool Registered = false;
IModel[] Models;
char[] ErrorText;

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
			model.Shutdown();
		
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
char* celeme_get_error()
{
	if(ErrorText == "")
		return null;
	else
		return toStringz(ErrorText);
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
void celeme_set_error(char* error)
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
 * CELEME_MODEL* celeme_load_model(const char* file, bool gpu);
 * ---
 */
IModel celeme_load_model(char* file, bool gpu)
{
	try
	{		
		return LoadModel(fromStringz(file), gpu);
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
 * See_Also: $(SYMLINK IModel.Shutdown, IModel.Shutdown)
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
		auto len = Models.remove(model, &iser!(IModel));
		if(len < Models.length)
		{
			Models[$ - 1].Shutdown();
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
 * See_Also: $(SYMLINK IModel.Initialize, IModel.Initialize)
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
 * See_Also: $(SYMLINK IModel.Generate, IModel.Generate)
 * 
 * C signature:
 * ---
 * void celeme_generate_model(CELEME_MODEL* model, bool parallel_delivery, bool atomic_delivery, bool initialize);
 * ---
 */
void celeme_generate_model(IModel model, bool parallel_delivery, bool atomic_delivery, bool initialize);

/**
 * Returns a neuron group based on its name.
 * 
 * See_Also: $(SYMLINK IModel.opIndex, IModel.opIndex)
 * 
 * C signature:
 * ---
 * CELEME_NEURON_GROUP* celeme_get_neuron_group(CELEME_MODEL* model, const char* name);
 * ---
 */
INeuronGroup celeme_get_neuron_group(IModel model, char* name);

/**
 * Run the model.
 * 
 * See_Also: $(SYMLINK IModel.Run, IModel.Run)
 * 
 * C signature:
 * ---
 * void celeme_run(CELEME_MODEL* model, int num_timesteps);
 * ---
 */
void celeme_run(IModel model, int num_timesteps);

/**
 * Reset the run of the model.
 * 
 * See_Also: $(SYMLINK IModel.ResetRun, IModel.ResetRun)
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
 * See_Also: $(SYMLINK IModel.InitRun, IModel.InitRun)
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
 * See_Also: $(SYMLINK IModel.RunUntil, IModel.RunUntil)
 * 
 * C signature:
 * ---
 * void celeme_run_until(CELEME_MODEL* model, int num_timesteps);
 * ---
 */
void celeme_run_until(IModel model, int num_timesteps);

/**
 * Set a connection between two neurons in a model.
 * 
 * See_Also: $(SYMLINK IModel.SetConnection, IModel.SetConnection)
 * 
 * C signature:
 * ---
 * void celeme_set_connection(CELEME_MODEL* model, const char* src_group, int src_nrn_id, int src_event_source, int src_slot, const char* dest_group, int dest_nrn_id, int dest_syn_type, int dest_slot);
 * ---
 */
void celeme_set_connection(IModel model, char* src_group, int src_nrn_id, int src_event_source, int src_slot, char* dest_group, int dest_nrn_id, int dest_syn_type, int dest_slot);

/**
 * Connecto two neurons in a model.
 * 
 * See_Also: $(SYMLINK IModel.Connect, IModel.Connect)
 * 
 * C signature:
 * ---
 * void celeme_connect(CELEME_MODEL* model, const char* src_group, int src_nrn_id, int src_event_source, const char* dest_group, int dest_nrn_id, int dest_syn_type);
 * ---
 */
void celeme_connect(IModel model, char* src_group, int src_nrn_id, int src_event_source, char* dest_group, int dest_nrn_id, int dest_syn_type);

/**
 * Apply a connector.
 * 
 * See_Also: $(SYMLINK IModel.ApplyConnector, IModel.ApplyConnector)
 * 
 * C signature:
 * ---
 * void celeme_apply_connector(CELEME_MODEL* model, const char* connector_name, int multiplier, const char* src_group, int src_nrn_start, int src_nrn_end, int src_event_source, const char* dest_group, int dest_nrn_start, int dest_nrn_end, int dest_syn_type, int argc, char** arg_keys, double* arg_vals);
 * ---
 */
void celeme_apply_connector(IModel model, char* connector_name, int multiplier, char* src_group, int src_nrn_start, int src_nrn_end, int src_event_source, char* dest_group, int dest_nrn_start, int dest_nrn_end, int dest_syn_type, int argc, char** arg_keys, double* arg_vals);

/**
 * Return the timestep size.
 * 
 * See_Also: $(SYMLINK IModel.TimeStepSize, IModel.TimeStepSize)
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
 * See_Also: $(SYMLINK IModel.TimeStepSize, IModel.TimeStepSize)
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
 * See_Also: $(SYMLINK INeuronGroup.TimeStepSize, INeuronGroup.TimeStepSize)
 * 
 * C signature:
 * ---
 * double celeme_get_constant(CELEME_NEURON_GROUP* group, const char* name);
 * ---
 */
double celeme_get_constant(INeuronGroup group, char* name);

/**
 * Set the value of a constant, or the default value of a global or a syn global.
 * 
 * See_Also: $(SYMLINK INeuronGroup.opIndexAssign, INeuronGroup.opIndexAssign)
 * 
 * C signature:
 * ---
 * double celeme_set_constant(CELEME_NEURON_GROUP* group, const char* name, double val);
 * ---
 */
double celeme_set_constant(INeuronGroup group, char* name, double val);

/**
 * Get the value of a global.
 * 
 * See_Also: $(SYMLINK INeuronGroup.opIndex, INeuronGroup.opIndex)
 * 
 * C signature:
 * ---
 * double celeme_get_global(CELEME_NEURON_GROUP* group, const char* name, int idx);
 * ---
 */
double celeme_get_global(INeuronGroup group, char* name, int idx);

/**
 * Set the value of a global.
 * 
 * See_Also: $(SYMLINK INeuronGroup.opIndexAssign, INeuronGroup.opIndexAssign)
 * 
 * C signature:
 * ---
 * double celeme_set_global(CELEME_NEURON_GROUP* group, const char* name, int idx, double val);
 * ---
 */
double celeme_set_global(INeuronGroup group, char* name, int idx, double val);

/**
 * Get the value of a syn global.
 * 
 * See_Also: $(SYMLINK INeuronGroup.opIndex, INeuronGroup.opIndex)
 * 
 * C signature:
 * ---
 * double celeme_get_syn_global(CELEME_NEURON_GROUP* group, const char* name, int nrn_idx, int syn_idx);
 * ---
 */
double celeme_get_syn_global(INeuronGroup group, char* name, int nrn_idx, int syn_idx);

/**
 * Set the value of a syn global.
 * 
 * See_Also: $(SYMLINK INeuronGroup.opIndexAssign, INeuronGroup.opIndexAssign)
 * 
 * C signature:
 * ---
 * double celeme_set_syn_global(CELEME_NEURON_GROUP* group, const char* name, int nrn_idx, int syn_idx, double val);
 * ---
 */
double celeme_set_syn_global(INeuronGroup group, char* name, int nrn_idx, int syn_idx, double val);

/**
 * Record the temporal evolution of a state of a single neuron.
 * 
 * See_Also: $(SYMLINK INeuronGroup.Record, INeuronGroup.Record)
 * 
 * C signature:
 * ---
 * CELEME_RECORDER* celeme_record(CELEME_NEURON_GROUP* group, int nrn_idx, const char* name);
 * ---
 */
CRecorder celeme_record(INeuronGroup group, int nrn_idx, char* name);

/**
 * Record the events from a particular event source of a single neuron.
 * 
 * See_Also: $(SYMLINK INeuronGroup.RecordEvents, INeuronGroup.RecordEvents)
 * 
 * C signature:
 * ---
 * CELEME_RECORDER* celeme_record_events(CELEME_NEURON_GROUP* group, int neuron_id, int thresh_id);
 * ---
 */
CRecorder celeme_record_events(INeuronGroup group, int neuron_id, int thresh_id);

/**
 * Stop all recording in a particular neuron.
 * 
 * See_Also: $(SYMLINK INeuronGroup.StopRecording, INeuronGroup.StopRecording)
 * 
 * C signature:
 * ---
 * void celeme_stop_recording(CELEME_NEURON_GROUP* group, int neuron_id);
 * ---
 */
void celeme_stop_recording(INeuronGroup group, int neuron_id);

/**
 * Get the minimum dt.
 * 
 * See_Also: $(SYMLINK INeuronGroup.MinDt, INeuronGroup.MinDt)
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
 * See_Also: $(SYMLINK INeuronGroup.MinDt, INeuronGroup.MinDt)
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
 * See_Also: $(SYMLINK INeuronGroup.Count, INeuronGroup.Count)
 * 
 * C signature:
 * ---
 * int celeme_get_count(CELEME_NEURON_GROUP* group);
 * ---
 */
int celeme_get_count(INeuronGroup group);

}
else
{

char[] ModelFunc(char[] c_name, char[] ret, char[] d_name, char[] args, char[] call_args, char[] def_ret)()
{
	char[] ret_str = 
ret ~ ` celeme_` ~ c_name ~ `(IModel model` ~ args ~ `)
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

/+mixin(ModelFunc!("add_neuron_group", "void", "AddNeuronGroup", 
	", CNeuronType type, int number, char* name, bool adaptive_dt", 
	"type, number, fromStringz(name), adaptive_dt", ""));+/
mixin(ModelFunc!("generate_model", "void", "Generate", 
	", bool parallel_delivery, bool atomic_delivery, bool initialize", 
	"parallel_delivery, atomic_delivery, initialize", ""));

mixin(ModelFunc!("get_neuron_group", "INeuronGroup", "opIndex", 
	", char* name", 
	"fromStringz(name)", "null"));
	
mixin(ModelFunc!("run", "void", "Run", 
	", int num_timesteps", 
	"num_timesteps", ""));
mixin(ModelFunc!("reset_run", "void", "ResetRun", "", "", ""));
mixin(ModelFunc!("init_run", "void", "InitRun", "", "", ""));
mixin(ModelFunc!("run_until", "void", "RunUntil", 
	", int num_timesteps", 
	"num_timesteps", ""));
	
mixin(ModelFunc!("set_connection", "void", "SetConnection", 
	", char* src_group, int src_nrn_id, int src_event_source, int src_slot, char* dest_group, int dest_nrn_id, int dest_syn_type, int dest_slot", 
	"fromStringz(src_group), src_nrn_id, src_event_source, src_slot, fromStringz(dest_group), dest_nrn_id, dest_syn_type, dest_slot", ""));
	
mixin(ModelFunc!("connect", "void", "Connect", 
	", char* src_group, int src_nrn_id, int src_event_source, char* dest_group, int dest_nrn_id, int dest_syn_type", 
	"fromStringz(src_group), src_nrn_id, src_event_source, fromStringz(dest_group), dest_nrn_id, dest_syn_type", ""));
	
void celeme_apply_connector(IModel model, char* connector_name, int multiplier, char* src_group, int src_nrn_start, int src_nrn_end, int src_event_source, char* dest_group, int dest_nrn_start, int dest_nrn_end, int dest_syn_type, int argc, char** arg_keys, double* arg_vals)
{
	try
	{
		double[char[]] d_args;
		foreach(ii; range(argc))
		{
			d_args[fromStringz(arg_keys[ii]).dup] = arg_vals[ii];
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

char[] GroupFunc(char[] c_name, char[] ret, char[] d_name, char[] args, char[] call_args, char[] def_ret)()
{
	char[] ret_str = 
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
	", char* name", 
	"fromStringz(name)", "-1.0"));
	
mixin(GroupFunc!("set_constant", "double", "opIndexAssign", 
	", char* name, double val", 
	"val, fromStringz(name)", "-1.0"));
	
mixin(GroupFunc!("get_global", "double", "opIndex", 
	", char* name, int idx", 
	"fromStringz(name), idx", "-1.0"));
	
mixin(GroupFunc!("set_global", "double", "opIndexAssign", 
	", char* name, int idx, double val", 
	"val, fromStringz(name), idx", "-1.0"));
	
mixin(GroupFunc!("get_syn_global", "double", "opIndex", 
	", char* name, int nrn_idx, int syn_idx", 
	"fromStringz(name), nrn_idx, syn_idx", "-1.0"));
	
mixin(GroupFunc!("set_syn_global", "double", "opIndexAssign", 
	", char* name, int nrn_idx, int syn_idx, double val", 
	"val, fromStringz(name), nrn_idx, syn_idx", "-1.0"));
	
mixin(GroupFunc!("record", "CRecorder", "Record", 
	", int nrn_idx, char* name", 
	"nrn_idx, fromStringz(name)", "null"));
	
mixin(GroupFunc!("record_events", "CRecorder", "RecordEvents", 
	", int neuron_id, int thresh_id", 
	"neuron_id, thresh_id", "null"));
	
mixin(GroupFunc!("stop_recording", "void", "StopRecording", 
	", int neuron_id", 
	"neuron_id", ""));

mixin(GroupFunc!("get_min_dt", "double", "MinDt", 
	"", 
	"", "-1"));
	
mixin(GroupFunc!("set_min_dt", "void", "MinDt", 
	", double min_dt", 
	"min_dt", ""));
	
mixin(GroupFunc!("get_count", "int", "Count", 
	"", 
	"", "0"));
	
}

/*
 * Recorder
 */

/**
 * Get the recorder name.
 * 
 * See_Also: $(SYMLINK CRecorder.Name, CRecorder.Name)
 * 
 * C signature:
 * ---
 * const char* celeme_get_recorder_name(CELEME_RECORDER* recorder);
 * ---
 */
char* celeme_get_recorder_name(CRecorder recorder)
{
	try
	{
		return toStringz(recorder.Name);
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
 * See_Also: $(SYMLINK CRecorder.Length, CRecorder.Length)
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
 * See_Also: $(SYMLINK CRecorder.Time, CRecorder.Time)
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
 * See_Also: $(SYMLINK CRecorder.Data, CRecorder.Data)
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
		return recorder.Data.ptr;
	}
	catch(Exception e)
	{
		ErrorText = e.msg;
	}
	return null;
}

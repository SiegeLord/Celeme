module celeme.capi;

import celeme.celeme;
import celeme.clmodel;
import celeme.xmlutil;
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

char* celeme_get_error()
{
	if(ErrorText == "")
		return null;
	else
		return toStringz(ErrorText);
}


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

IModel celeme_load_model(char* file)
{
	try
	{		
		return LoadModel(fromStringz(file));
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
mixin(ModelFunc!("shutdown_model", "void", "Shutdown", "", "", ""));

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
		model.Connect(fromStringz(connector_name), multiplier, fromStringz(src_group), [src_nrn_start, src_nrn_end], src_event_source, fromStringz(dest_group), [dest_nrn_start, dest_nrn_end], dest_syn_type, d_args);
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

/*
 * Recorder
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

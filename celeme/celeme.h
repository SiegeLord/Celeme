#ifndef CELEME_H
#define CELEME_H

#include <stdbool.h>
#include <stddef.h>

typedef void* CELEME_MODEL;
typedef void* CELEME_NEURON_TYPE;
typedef void* CELEME_NEURON_GROUP;
typedef void* CELEME_RECORDER;

/*enum
{
	CELEME_MODEL_FLOAT,
	CELEME_MODEL_DOUBLE
};*/

void celeme_init(void);
void celeme_shutdown(void);
const char* celeme_get_error(void);

/*
 * Model
 */

/*CELEME_MODEL celeme_create_model(int type, bool gpu);*/
CELEME_MODEL celeme_load_model(const char* file);
void celeme_initialize_model(CELEME_MODEL model);
void celeme_shutdown_model(CELEME_MODEL model);

/*void celeme_add_neuron_group(CELEME_MODEL model, CELEME_NEURON_TYPE type, int number, const char* name, bool adaptive_dt);*/
void celeme_generate_model(CELEME_MODEL model, bool parallel_delivery, bool atomic_delivery, bool initialize);

CELEME_NEURON_GROUP celeme_get_neuron_group(CELEME_MODEL model, const char* name);

void celeme_run(CELEME_MODEL model, int num_timesteps);
void celeme_reset_run(CELEME_MODEL model);
void celeme_init_run(CELEME_MODEL model);
void celeme_run_until(CELEME_MODEL model, int num_timesteps);

void celeme_set_connection(CELEME_MODEL model, const char* src_group, int src_nrn_id, int src_event_source, int src_slot, const char* dest_group, int dest_nrn_id, int dest_syn_type, int dest_slot);
void celeme_connect(CELEME_MODEL model, const char* src_group, int src_nrn_id, int src_event_source, const char* dest_group, int dest_nrn_id, int dest_syn_type);
void celeme_apply_connector(CELEME_MODEL model, const char* connector_name, int multiplier, const char* src_group, int src_nrn_start, int src_nrn_end, int src_event_source, const char* dest_group, int dest_nrn_start, int dest_nrn_end, int dest_syn_type, int argc, char** arg_keys, double* arg_vals);

double celeme_get_timestep_size(CELEME_MODEL model);
void celeme_set_timestep_size(CELEME_MODEL model, double val);

/*
 * Group
 */

double celeme_get_constant(CELEME_NEURON_GROUP group, const char* name);
double celeme_set_constant(CELEME_NEURON_GROUP group, const char* name, double val);

double celeme_get_global(CELEME_NEURON_GROUP group, const char* name, int idx);
double celeme_set_global(CELEME_NEURON_GROUP group, const char* name, int idx, double val);

double celeme_get_syn_global(CELEME_NEURON_GROUP group, const char* name, int nrn_idx, int syn_idx);
double celeme_set_syn_global(CELEME_NEURON_GROUP group, const char* name, int nrn_idx, int syn_idx, double val);

CELEME_RECORDER celeme_record(CELEME_NEURON_GROUP group, int nrn_idx, const char* name);
CELEME_RECORDER celeme_record_events(CELEME_NEURON_GROUP group, int neuron_id, int thresh_id);

void celeme_stop_recording(CELEME_NEURON_GROUP group, int neuron_id);

double celeme_get_min_dt(CELEME_NEURON_GROUP group);
void celeme_set_min_dt(CELEME_NEURON_GROUP group, double min_dt);
int celeme_get_count(CELEME_NEURON_GROUP group);

/*
 * Recorder
 */

const char* celeme_get_recorder_name(CELEME_RECORDER recorder);
size_t celeme_get_recorder_length(CELEME_RECORDER recorder);
double* celeme_get_recorder_time(CELEME_RECORDER recorder);
double* celeme_get_recorder_data(CELEME_RECORDER recorder);

#endif

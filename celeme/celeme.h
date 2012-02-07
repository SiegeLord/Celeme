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

#ifndef CELEME_H
#define CELEME_H

#include <stdbool.h>
#include <stddef.h>

typedef struct CELEME_MODEL CELEME_MODEL;
typedef struct CELEME_NEURON_TYPE CELEME_NEURON_TYPE;
typedef struct CELEME_NEURON_GROUP CELEME_NEURON_GROUP;
typedef struct CELEME_RECORDER CELEME_RECORDER;
typedef struct CELEME_SLOTS
{
	int SourceSlot;
	int DestSlot;
} CELEME_SLOTS;

void celeme_init(void);
void celeme_shutdown(void);
const char* celeme_get_error(void);
void celeme_set_error(const char* error);

/*
 * Model
 */

/*CELEME_MODEL* celeme_create_model(int type, bool gpu);*/
CELEME_MODEL* celeme_load_model(const char* file, size_t num_includes, const char** include_dirs, bool gpu, bool double_precision);
void celeme_initialize_model(CELEME_MODEL* model);
void celeme_destroy_model(CELEME_MODEL* model);

/*void celeme_add_neuron_group(CELEME_MODEL* model, CELEME_NEURON_TYPE* type, size_t number, const char* name, bool adaptive_dt);*/
void celeme_add_neuron_group(CELEME_MODEL* model, const char* type_name, size_t number, const char* name, bool adaptive_dt, bool parallel_delivery);
void celeme_generate_model(CELEME_MODEL* model, bool initialize);

CELEME_NEURON_GROUP* celeme_get_neuron_group(CELEME_MODEL* model, const char* name);

void celeme_run(CELEME_MODEL* model, size_t num_timesteps);
void celeme_reset_run(CELEME_MODEL* model);
void celeme_init_run(CELEME_MODEL* model);
void celeme_run_until(CELEME_MODEL* model, size_t num_timesteps);

void celeme_set_connection(CELEME_MODEL* model, const char* src_group, size_t src_nrn_id, size_t src_event_source, size_t src_slot, const char* dest_group, size_t dest_nrn_id, size_t dest_syn_type, size_t dest_slot);
void celeme_connect(CELEME_MODEL* model, const char* src_group, size_t src_nrn_id, size_t src_event_source, const char* dest_group, size_t dest_nrn_id, size_t dest_syn_type);
void celeme_apply_connector(CELEME_MODEL* model, const char* connector_name, size_t multiplier, const char* src_group, size_t src_nrn_start, size_t src_nrn_end, size_t src_event_source, const char* dest_group, size_t dest_nrn_start, size_t dest_nrn_end, size_t dest_syn_type, size_t argc, const char** arg_keys, double* arg_vals);

double celeme_get_timestep_size(CELEME_MODEL* model);
void celeme_set_timestep_size(CELEME_MODEL* model, double val);

/*
 * Group
 */

double celeme_get_constant(CELEME_NEURON_GROUP* group, const char* name);
double celeme_set_constant(CELEME_NEURON_GROUP* group, const char* name, double val);

double celeme_get_global(CELEME_NEURON_GROUP* group, const char* name, size_t idx);
double celeme_set_global(CELEME_NEURON_GROUP* group, const char* name, size_t idx, double val);

double celeme_get_syn_global(CELEME_NEURON_GROUP* group, const char* name, size_t nrn_idx, size_t syn_idx);
double celeme_set_syn_global(CELEME_NEURON_GROUP* group, const char* name, size_t nrn_idx, size_t syn_idx, double val);

CELEME_RECORDER* celeme_record(CELEME_NEURON_GROUP* group, size_t nrn_idx, int flags);

void celeme_stop_recording(CELEME_NEURON_GROUP* group, size_t neuron_id);

double celeme_get_min_dt(CELEME_NEURON_GROUP* group);
void celeme_set_min_dt(CELEME_NEURON_GROUP* group, double min_dt);
size_t celeme_get_count(CELEME_NEURON_GROUP* group);
size_t celeme_get_nrn_offset(CELEME_NEURON_GROUP* group);

int celeme_get_connection_id(CELEME_NEURON_GROUP* group, size_t nrn_id, size_t event_source, size_t src_slot);
int celeme_get_connection_slot(CELEME_NEURON_GROUP* group, size_t nrn_id, size_t event_source, size_t src_slot);

/*
 * Recorder
 */

const char* celeme_get_recorder_name(CELEME_RECORDER* recorder);
size_t celeme_get_recorder_length(CELEME_RECORDER* recorder);
double* celeme_get_recorder_time(CELEME_RECORDER* recorder);
double* celeme_get_recorder_data(CELEME_RECORDER* recorder);
int* celeme_get_recorder_tags(CELEME_RECORDER* recorder);
size_t* celeme_get_recorder_neuron_ids(CELEME_RECORDER* recorder);

#endif

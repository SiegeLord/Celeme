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

module celeme.ineurongroup;

import celeme.internal.util;

import celeme.recorder;

/**
 * A common interface to multiple types of groups.
 */
interface INeuronGroup
{
	/**
	 * Get the value of a constant, or the default value of a global or a syn global.
	 */
	double opIndex(cstring name);
	
	/**
	 * Set the value of a constant, or the default value of a global or a syn global.
	 */
	double opIndexAssign(double val, cstring name);
	
	/**
	 * Get the value of a global value of a particular neuron.
	 * Params:
	 *     name = Name of the global.
	 *     idx = Index of the neuron.
	 */
	double opIndex(cstring name, size_t idx);
	
	/**
	 * Set the value of a global value of a particular neuron.
	 * Params:
	 *     val = New value.
	 *     name = Name of the global.
	 *     idx = Index of the neuron.
	 */
	double opIndexAssign(double val, cstring name, size_t idx);
	
	/**
	 * Get the value of a syn global value of a particular neuron.
	 * Params:
	 *     name = Name of the global.
	 *     nrn_idx = Index of the neuron.
	 *     syn_idx = Index of the synapse within the neuron.
	 */
	double opIndex(cstring name, size_t nrn_idx, size_t syn_idx);
	
	/**
	 * Set the value of a syn global value of a particular neuron.
	 * Params:
	 *     val = New value.
	 *     name = Name of the global.
	 *     nrn_idx = Index of the neuron.
	 *     syn_idx = Index of the synapse within the neuron.
	 */
	double opIndexAssign(double val, cstring name, size_t nrn_idx, size_t syn_idx);
	
	/**
	 * Set the recording flags of a single neuron.
	 * 
	 * Params:
	 *     neuron_id = Index of the neuron.
	 *     flags = flags to pass to the neuron.
	 * Returns:
	 *     A common recorder that will hold data points consisting of the time, data and a tag as well as the neuron id.
	 */
	CRecorder Record(size_t neuron_id, int flags);
	/**
	 * Stop recording everything
	 */
	void StopRecording(size_t neuron_id);
	
	/**
	 * Sets the minimum dt for this neuron group. When adaptive integration is used, this is the
	 * smallest dt that the integrator can use. When fixed step integration is used, it is
	 * the dt that the integrator uses.
	 */
	@property
	void MinDt(double min_dt);
	
	/**
	 * Returns the minimum dt for this neuron group.
	 */
	@property
	double MinDt();
	
	/**
	 * Returns the number of neurons in this group
	 */
	@property
	size_t Count();
	
	/**
	 * Returns the global index of the first neuron in this neuron group.
	 */
	@property
	size_t NrnOffset();
		
	/**
	 * Seeds the random number generator. Each individual neuron's random generator is set to a pseudo-random
	 * value based on this seed.
	 * 
	 * Params:
	 *     seed = New PRNG seed.
	 */
	void Seed(int seed);
	
	/**
	 * Seeds the random number generator of a single neuron.
	 * 
	 * Params:
	 *     nrn_id = Index of the neuron.
	 *     seed = New PRNG seed.
	 */
	void Seed(size_t nrn_id, int seed);
	
	/**
	 * Returns the target global neuron id that an event source is connected to at a specified source slot.
	 * 
	 * Params:
	 *     nrn_id = Index of the neuron.
	 *     event_source = Index of the event source.
	 *     src_slot = Index of the event source slot.
	 * Returns:
	 *     The global destination neuron id, or -1 if no connection is present.
	 */
	int GetConnectionId(size_t nrn_id, size_t event_source, size_t src_slot);
	
	/**
	 * Returns the target slot that an event source is connected to at a specified source slot.
	 * 
	 * Params:
	 *     nrn_id = Index of the neuron.
	 *     event_source = Index of the event source.
	 *     src_slot = Index of the event source slot.
	 * Returns:
	 *     The destination slot, or -1 if no connection is present.
	 */
	int GetConnectionSlot(size_t src_nrn_id, size_t event_source, size_t src_slot);
}

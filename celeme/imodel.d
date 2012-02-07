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
 * This module provides a common interface to various model types (well, only one for now).
 */

module celeme.imodel;

import celeme.internal.util;
import celeme.internal.clmodel;
import celeme.internal.frontend;
import celeme.ineurongroup;

/**
 * Interface to a generic model
 */ 
interface IModel
{
	/**
	 * Initializes the model. Normally you do not need to call this, as it is called by the
	 * Generate method.
	 */
	void Initialize();
	
	/**
	 * Disposes of the model resources.
	 */
	void Dispose();
	
	/**
	 * Adds a new neuron group from an internal registry.
	 * 
	 * Params:
	 *     type_name = Name of the neuron type to add
	 *     number = Number of neurons to add of this type
	 *     name = What name to use to override the type name
	 *     adaptive_dt = Whether or not to use the adaptive timestep integration
	 *     parallel_delivery = Whether or not to use parallel delivery of events. Parallel delivery
	 *                         is faster on the GPU, but is slow on the CPU.
	 */
	void AddNeuronGroup(cstring type_name, int number, cstring name = null, bool adaptive_dt = true, bool parallel_delivery = true);
	
	/**
	 * Adds a new neuron group.
	 * 
	 * Params:
	 *     type = What neuron type to add
	 *     number = Number of neurons to add of this type
	 *     name = What name to use to override the type name
	 *     adaptive_dt = Whether or not to use the adaptive timestep integration
	 *     parallel_delivery = Whether or not to use parallel delivery of events. Parallel delivery
	 *                         is faster on the GPU, but is slow on the CPU.
	 */
	void AddNeuronGroup(CNeuronType type, int number, cstring name = null, bool adaptive_dt = true, bool parallel_delivery = true);
	
	/**
	 * Generates the model. You must generate it before you run it, or set any neuron-specific
	 * values.
	 * 
	 * Params:
	 *     initialize = Whether or not to call the Initialize method after this method is done. Usually set
	 *                  to true.
	 */
	void Generate(bool initialize = true);
	
	/**
	 * Returns a neuron group with the passed name.
	 */
	INeuronGroup opIndex(cstring name);
	
	/**
	 * Runs the model for a specified number of timesteps. Equivalent to this code:
	 * ---
	 * model.ResetRun();
	 * model.InitRun();
	 * model.RunUntil(num_timesteps);
	 * ---
	 */
	void Run(int num_timesteps);
	
	/**
	 * Resets the buffers of the model, setting the internal time to 0. This clears the pending events, and resets all values to their
	 * default states. It also clears the recorders. The connections between neurons and the allocation
	 * of recorders are not affected, however. Note that this means that if you want to set any per-neuron
	 * values, you should do it after this method call (and possibly after InitRun method also).
	 */
	void ResetRun();
	
	/**
	 * Calls the init code for each neuron group.
	 */
	void InitRun();
	
	/**
	 * Runs the model until the internal clock equals the passed number of timesteps.
	 */
	void RunUntil(int num_timesteps);
	
	/**
	 * Sets a connection between two neurons in this model. This function ignores the used slots,
	 * and thus can be made to overwrite connections.
	 * 
	 * Params:
	 *     src_group = Name of the source neuron group
	 *     src_nrn_id = Index of the source neuron
	 *     src_event_source = Index of the event source to use
	 *     src_slot = Source slot to use
	 *     dest_group = Name of the destination neuron group
	 *     dest_nrn_id = Index of the destination neuron
	 *     dest_syn_type = Index of the synapse to use
	 *     dest_slot = Destination slot to use
	 */
	void SetConnection(cstring src_group, int src_nrn_id, int src_event_source, int src_slot, cstring dest_group, int dest_nrn_id, int dest_syn_type, int dest_slot);
	
	/**
	 * Utility structure to hold the slots used by a connection. Returned by the $(SYMLINK Connect, Connect) method.
	 * Both values will be set to -1 if the connection is not made.
	 */
	struct SSlots
	{
		int SourceSlot;
		int DestSlot;
	}
	
	/**
	 * Adds a connection between two neurons. This function respects the used slots.
	 * 
	 * Params:
	 *     src_group = Name of the source neuron group
	 *     src_nrn_id = Index of the source neuron
	 *     src_event_source = Index of the event source to use
	 *     dest_group = Name of the destination neuron group
	 *     dest_nrn_id = Index of the destination neuron
	 *     dest_syn_type = Index of the synapse to use
	 * 
	 * Returns:
	 *     A $(SYMLINK SSlots, SSlots) structure. The connection might not be made
	 *     because the maximum number of slots has been used.
	 */
	SSlots Connect(cstring src_group, int src_nrn_id, int src_event_source, cstring dest_group, int dest_nrn_id, int dest_syn_type);
	
	/**
	 * Apply a connector to interconnect two ranges of neurons. This is the fastest method to connect neurons,
	 * as the connections are made in parallel. The source neuron's group connector is used, as well as the random state.
	 * 
	 * Params:
	 *     connector_name = Name of the connector to use
	 *     multiplier = How many times to run the connector kernel on each source neuron
	 *     src_group = Name of the source neuron group
	 *     src_nrn_range = Range of the source neurons to connect. The range is closed on the left and open on the right.
	 *     src_event_source = Index of the event source to use
	 *     dest_group = Name of the destination neuron group
	 *     dest_nrn_range = Range of destination neurons to connect. The range is closed on the left and open on the right.
	 *     dest_syn_type = Index of the synapse to use
	 *     args = An associative array of arguments to pass to the connector
	 */
	void ApplyConnector(cstring connector_name, int multiplier, cstring src_group, int[2] src_nrn_range, int src_event_source, cstring dest_group, int[2] dest_nrn_range, int dest_syn_type, double[char[]] args = null);
	
	/**
	 * Returns the timestep size of the model. The model is ran using fixed timesteps, although
	 * each neuron group may advance through each timestep in multiple sub-steps. This value
	 * corresponds to the minimum delay in the network.
	 */
	@property
	double TimeStepSize();
	
	/**
	 * Sets the timestep size of the model.
	 * The model is ran using fixed timesteps, although
	 * each neuron group may advance through each timestep in multiple sub-steps. This value
	 * corresponds to the minimum delay in the network.
	 * 
	 * Note that this cannot be set after the model is generated.
	 */
	@property
	void TimeStepSize(double val);
}

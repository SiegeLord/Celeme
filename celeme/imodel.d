/**
 * This module provides a common interface to various model types (well, only one for now).
 */

module celeme.imodel;

import celeme.clmodel;
import celeme.frontend;
import celeme.ineurongroup;

/**
 * Creates a new OpenCL model.
 * Params:
 *     gpu = Whether or not to use the gpu
 */
IModel CreateCLModel(float_t)(bool gpu = false)
{
	return new CCLModel!(float_t)(gpu);
}

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
	 * Shuts the model down, destroying all of its resources.
	 */
	void Shutdown();
	
	/**
	 * Adds a new neuron group.
	 * 
	 * Params:
	 *     type = What neuron type to add
	 *     number = Number of neurons to add of this type
	 *     name = What name to use to override the type name
	 *     adaptive_dt = Whether or not to use the adaptive timestep integration
	 */
	void AddNeuronGroup(CNeuronType type, int number, char[] name = null, bool adaptive_dt = true);
	
	/**
	 * Generates the model. You must generate it before you run it, or set any neuron-specific
	 * values.
	 * 
	 * Params:
	 *     parallel_delivery = Whether or not to use parallel delivery of events. Parallel delivery
	 *                         is faster on the GPU, but is slow on the CPU.
	 *     atomic_delivery = Whether or not to use atomic delivery of events. Usually set to true.
	 *     initialize = Whether or not to call the Initialize method after this method is done. Usually set
	 *                  to true.
	 */
	void Generate(bool parallel_delivery = true, bool atomic_delivery = true, bool initialize = true);
	
	/**
	 * Returns a neuron group with the passed name.
	 */
	INeuronGroup opIndex(char[] name);
	
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
	void SetConnection(char[] src_group, int src_nrn_id, int src_event_source, int src_slot, char[] dest_group, int dest_nrn_id, int dest_syn_type, int dest_slot);
	
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
	 *     true if the connection was made succesfully, false otherwise. The connection might not be made
	 *     because the maximum number of slots has been used.
	 */
	bool Connect(char[] src_group, int src_nrn_id, int src_event_source, char[] dest_group, int dest_nrn_id, int dest_syn_type);
	
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
	void ApplyConnector(char[] connector_name, int multiplier, char[] src_group, int[2] src_nrn_range, int src_event_source, char[] dest_group, int[2] dest_nrn_range, int dest_syn_type, double[char[]] args = null);
	
	/**
	 * Returns the timestep size of the model. The model is ran using fixed timesteps, although
	 * each neuron group may advance through each timestep in multiple sub-steps. This value
	 * corresponds to the minimum delay in the network.
	 */
	double TimeStepSize();
	
	/**
	 * Sets the timestep size of the model.
	 * The model is ran using fixed timesteps, although
	 * each neuron group may advance through each timestep in multiple sub-steps. This value
	 * corresponds to the minimum delay in the network.
	 * 
	 * Note that this cannot be set after the model is generated.
	 */
	void TimeStepSize(double val);
}

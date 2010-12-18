module celeme.ineurongroup;

import celeme.recorder;

/**
 * A common interface to multiple types of groups.
 */
interface INeuronGroup
{
	/**
	 * Get the value of a constant, or the default value of a global or a syn global.
	 */
	double opIndex(char[] name);
	
	/**
	 * Set the value of a constant, or the default value of a global or a syn global.
	 */
	double opIndexAssign(double val, char[] name);
	
	/**
	 * Get the value of a global value of a particular neuron.
	 * Params:
	 *     name = Name of the global.
	 *     idx = Index of the neuron.
	 */
	double opIndex(char[] name, int idx);
	
	/**
	 * Set the value of a global value of a particular neuron.
	 * Params:
	 *     val = New value.
	 *     name = Name of the global.
	 *     idx = Index of the neuron.
	 */
	double opIndexAssign(double val, char[] name, int idx);
	
	/**
	 * Get the value of a syn global value of a particular neuron.
	 * Params:
	 *     name = Name of the global.
	 *     nrn_idx = Index of the neuron.
	 *     syn_idx = Index of the synapse within the neuron.
	 */
	double opIndex(char[] name, int nrn_idx, int syn_idx);
	
	/**
	 * Set the value of a syn global value of a particular neuron.
	 * Params:
	 *     val = New value.
	 *     name = Name of the global.
	 *     nrn_idx = Index of the neuron.
	 *     syn_idx = Index of the synapse within the neuron.
	 */
	double opIndexAssign(double val, char[] name, int nrn_idx, int syn_idx);
	
	/**
	 * Record a state of a particular neuron. Only one state or threshold can be recorded at a time.
	 */
	CRecorder Record(int neuron_id, char[] name);
	/**
	 * Record the events coming from a particular threshold detector in this neuron.
	 * Only one state or threshold can be recorded at a time.
	 * 
	 * Params:
	 *     neuron_id = Index of the neuron.
	 *     thresh_id = Index of the threshold to record from.
	 */
	CRecorder RecordEvents(int neuron_id, int thresh_id);
	/**
	 * Stop recording everything
	 */
	void StopRecording(int neuron_id);
	
	/**
	 * Sets the minimum dt for this neuron group. When adaptive integration is used, this is the
	 * smallest dt that the integrator can use. When fixed step integration is used, it is
	 * the dt that the integrator uses.
	 */
	void MinDt(double min_dt);
	
	/**
	 * Returns the minimum dt for this neuron group.
	 */
	double MinDt();
	
	/**
	 * Returns the number of neurons in this group
	 */
	int Count();
}

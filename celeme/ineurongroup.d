/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2011 Pavel Sountsov

Celeme is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
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
	 * Record a state of a particular neuron. Only one state or threshold can be recorded at a time in
	 * a single neuron.
	 * 
	 * Returns:
	 *     A recorder that will hold time-state data points. A new recorder is made for
	 *     each recorded state.
	 */
	CRecorder Record(int neuron_id, char[] name);
	/**
	 * Record the events coming from a particular threshold detector in this neuron.
	 * Only one state or threshold can be recorded at a time.
	 * 
	 * Params:
	 *     neuron_id = Index of the neuron.
	 *     thresh_id = Index of the threshold to record from.
	 * Returns:
	 *     A common recorder. The recorder will store times of all the events coming from all recorded
	 *     neurons in the T array. The Data array will hold the global threshold index, identifying
	 *     where the event came from. This is calculated like as follows:
	 *     id = thresh_id + num_thresh * neuron_id.
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

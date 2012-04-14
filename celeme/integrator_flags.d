/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2012 Pavel Sountsov

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

module celeme.integrator_flags;

/**
 * Specifies what integrator to use for a neuron group. All integrators (for now) use sub-stepping, taking multiple
 * smaller steps within the simulation timestep.
 */
enum EIntegratorFlags
{
	/**
	 * Minimize the integration error by varying the integration timestep. Not available for the Euler method.
	 */
	Adaptive = 0x1,
	/**
	 * The second-order explicit Heun method.
	 */
	Heun     = 0x2,
	/**
	 * The first-order explicit Euler method.
	 */
	Euler    = 0x4
}

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

module celeme.platform_flags;

/**
 * Specifies what platform to use. By default it will prefer AMD to NVidia to Intel and GPU to CPU's.
 */
enum EPlatformFlags
{
	/**
	 * Select the AMD platform.
	 */
	AMD    = 0x01,
	/**
	 * Select the NVidia platform.
	 */
	NVidia = 0x02,
	/**
	 * Select the Intel platform.
	 */
	Intel  = 0x04,
	/**
	 * Prefer GPU devices.
	 */
	GPU    = 0x08,
	/**
	 * Prefer CPU devices. If this flag is passed, GPU devices are ignored.
	 */
	CPU    = 0x10,
	/**
	 * Force the selected platform and/or device type.
	 */
	Force  = 0x20
}

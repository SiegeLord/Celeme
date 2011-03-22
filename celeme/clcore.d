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

module celeme.clcore;

import celeme.util;

import opencl.cl;

import tango.io.Stdout;
import tango.util.Convert;

version (AMDPerf)
import perf = celeme.amdperf;

class CCLKernel
{
	this(CCLCore core, cl_program program, char[] name)
	{
		Core = core;
		Name = name;
		
		int err;
		Kernel = clCreateKernel(program, Name.c_str(), &err);
		if(err != CL_SUCCESS)
		{
			throw new Exception("Failed to create '" ~ Name ~ "' kernel.");
		}
	}
	
	void SetGlobalArg(T)(uint argnum, T arg)
	{
		static if(!is(T == int) 
		       && !is(T == uint)
		       && !is(T == float)
		       && !is(T == double)
		       && !is(T == cl_int2)
		       && !is(T == cl_uint2)
		       && !is(T == cl_float2)
		       && !is(T == cl_double2)
		       && !is(T == cl_int4)
		       && !is(T == cl_uint4)
		       && !is(T == cl_float4)
		       && !is(T == cl_double4)
		       && !is(T == cl_mem)
		       && !is(T : CCLBufferBase)
		       )
			static assert(0, "Invalid argument to SetGlobalArg.");

		static if(is(T : CCLBufferBase))
		{
			auto buf = arg.Buffer;
			auto err = clSetKernelArg(Kernel, argnum, arg.Buffer.sizeof, &buf);
		}
		else
			auto err = clSetKernelArg(Kernel, argnum, T.sizeof, &arg);

		if(err != CL_SUCCESS)
		{
			throw new Exception("Failed to set a global argument " ~ to!(char[])(argnum) ~ " of kernel '" ~ Name ~ "'.");
		}
	}

	void SetLocalArg(uint argnum, size_t size)
	{
		auto err = clSetKernelArg(Kernel, argnum, size, null);
		if(err != CL_SUCCESS)
		{
			throw new Exception("Failed to set a local argument " ~ to!(char[])(argnum) ~ " of kernel '" ~ Name ~ "'.");
		}
	}
	
	void Launch(size_t[] num_work_items, size_t[] workgroup_size = null, cl_event* event = null)
	{
		Core.LaunchKernel(this, num_work_items, workgroup_size, event);
	}
	
	void Release()
	{
		clReleaseKernel(Kernel);
	}
	
	CCLCore Core;
	cl_kernel Kernel;
	char[] Name;
}

class CCLBufferBase
{
	void Release()
	{
		clReleaseMemObject(Buffer);
	}
	
	cl_mem Buffer()
	{
		return BufferVal;
	}
	
	size_t Length()
	{
		return LengthVal;
	}
protected:
	CCLCore Core;
	cl_mem BufferVal;
	size_t LengthVal;
}

class CCLBuffer(T) : CCLBufferBase
{
	this(CCLCore core, size_t length)
	{
		Core = core;
		LengthVal = length;
		
		int err;
		BufferVal = clCreateBuffer(Core.Context, CL_MEM_ALLOC_HOST_PTR, LengthVal * T.sizeof, null, &err);
		assert(err == CL_SUCCESS);
	}
	
	T[] MapWrite(size_t start = 0, size_t end = 0)
	{
		return Map(CL_MAP_WRITE, start, end);
	}
	
	T[] MapReadWrite(size_t start = 0, size_t end = 0)
	{
		return Map(CL_MAP_WRITE | CL_MAP_READ, start, end);
	}
	
	T[] MapRead(size_t start = 0, size_t end = 0)
	{
		return Map(CL_MAP_READ, start, end);
	}
	
	T[] Map(cl_map_flags flags, size_t start = 0, size_t end = 0)
	{
		assert(start >= 0 && end <= Length);
		assert(end >= start);
		
		if(end <= 0)
			end = Length;
		int err;
		T* ret = cast(T*)clEnqueueMapBuffer(Core.Commands, Buffer, CL_TRUE, flags, start * T.sizeof, (end - start) * T.sizeof, 0, null, null, &err);
		assert(err == CL_SUCCESS);
		return ret[0..end - start];
	}
	
	void UnMap(T[] arr)
	{
		clEnqueueUnmapMemObject(Core.Commands, Buffer, arr.ptr, 0, null, null);
	}
	
	T opSliceAssign(T val)
	{
		auto arr = MapWrite();
		arr[] = val;
		UnMap(arr);
		return val;
	}
	
	T opSliceAssign(T val, size_t start, size_t end)
	{
		auto arr = MapWrite(start, end);
		arr[] = val;
		UnMap(arr);
		return val;
	}
	
	T opIndex(size_t idx)
	{
		assert(idx >= 0 && idx < Length);
		
		auto arr = MapRead(idx, idx + 1);
		auto ret = arr[0];
		UnMap(arr);
		return ret;
	}
	
	T opIndexAssign(T val, size_t idx)
	{
		assert(idx >= 0 && idx < Length);
		
		auto arr = MapWrite(idx, idx + 1);
		arr[0] = val;
		UnMap(arr);
		return val;
	}
}

class CCLCore
{
	this(bool use_gpu = false, bool verbose = false)
	{
		GPU = use_gpu;
		
		version (AMDPerf)
		if(GPU)
			perf.Initialize();
		
		int err;
		
		/* Get platforms */
		uint num_platforms;
		err = clGetPlatformIDs(0, null, &num_platforms);
		assert(err == CL_SUCCESS);
		assert(num_platforms);
		
		cl_platform_id[] platforms;
		platforms.length = num_platforms;
		err = clGetPlatformIDs(num_platforms, platforms.ptr, null);
		assert(err == CL_SUCCESS);
		
		if(verbose)
		{
			foreach(ii, platform; platforms)
			{
				char[] get_param(cl_platform_info param)
				{
					char[] ret;
					size_t ret_len;
					int err2 = clGetPlatformInfo(platform, param, 0, null, &ret_len);
					assert(err2 == CL_SUCCESS);
					ret.length = ret_len;
					err2 = clGetPlatformInfo(platform, param, ret_len, ret.ptr, null);
					assert(err2 == CL_SUCCESS);
					return ret[0..$-1];
				}
				Stdout.formatln("Platform {}:", ii);
				Stdout.formatln("\tCL_PLATFORM_PROFILE:\n\t\t{}", get_param(CL_PLATFORM_PROFILE));
				Stdout.formatln("\tCL_PLATFORM_VERSION:\n\t\t{}", get_param(CL_PLATFORM_VERSION));
				Stdout.formatln("\tCL_PLATFORM_NAME:\n\t\t{}", get_param(CL_PLATFORM_NAME));
				Stdout.formatln("\tCL_PLATFORM_VENDOR:\n\t\t{}", get_param(CL_PLATFORM_VENDOR));
				Stdout.formatln("\tCL_PLATFORM_EXTENSIONS:\n\t\t{}", get_param(CL_PLATFORM_EXTENSIONS));
			}
		}
		
		Platform = platforms[0];
		
		/* Get devices */
		uint num_devices;
		auto device_type = GPU ? CL_DEVICE_TYPE_GPU : CL_DEVICE_TYPE_CPU;
		err = clGetDeviceIDs(Platform, device_type, 0, null, &num_devices);
		if(err == CL_DEVICE_NOT_FOUND)
			throw new Exception("This platform does not support " ~ (GPU ? "GPU" : "CPU") ~ " devices!");
		assert(err == CL_SUCCESS);
		
		cl_device_id[] devices;
		devices.length = num_devices;
		clGetDeviceIDs(Platform, device_type, num_devices, devices.ptr, null);
		assert(err == CL_SUCCESS);
		
		if(verbose)
		{
			foreach(ii, device; devices)
			{
				Stdout.formatln("Device {}:", ii);
				Stdout.formatln("\tCL_DEVICE_ADDRESS_BITS:\n\t\t{}", GetDeviceParam!(uint)(device, CL_DEVICE_ADDRESS_BITS));
				Stdout.formatln("\tCL_DEVICE_AVAILABLE:\n\t\t{}", 1 == GetDeviceParam!(int)(device, CL_DEVICE_AVAILABLE));
				Stdout.formatln("\tCL_DEVICE_COMPILER_AVAILABLE:\n\t\t{}", 1 == GetDeviceParam!(int)(device, CL_DEVICE_COMPILER_AVAILABLE));
				/* And so on... */
			}
		}
		
		Device = devices[0];
		
		/* Create a compute context */
		Context = clCreateContext(null, 1, &Device, null, null, &err);
		if(!Context)
		{
			throw new Exception("Failed to create a compute context!");
		}

		/* Create a command commands */
		int flags = 0;
		version(Perf) flags = CL_QUEUE_PROFILING_ENABLE;
		Commands = clCreateCommandQueue(Context, Device, flags, &err);
		if(!Commands)
		{
			throw new Exception("Failed to create a command queue!");
		}
		
		version (AMDPerf)
		if(GPU)
			perf.OpenContext(Commands);
	}
	
	private T GetDeviceParam(T)(cl_device_id device, cl_device_info param)
	{
		static if(is(T : char[]))
		{
			char[] ret;
			size_t ret_len;
			int err2 = clGetDeviceInfo(device, param, 0, null, &ret_len);
			assert(err2 == CL_SUCCESS);
			ret.length = ret_len;
			err2 = clGetDeviceInfo(device, param, ret_len, ret.ptr, null);
			assert(err2 == CL_SUCCESS);
			return ret[0..$-1];
		}
		else
		{
			T ret;
			int err2 = clGetDeviceInfo(device, param, T.sizeof, &ret, null);
			assert(err2 == CL_SUCCESS);
			return ret;
		}
	}
	
	void Shutdown()
	{
		clReleaseCommandQueue(Commands);
		
		version (AMDPerf)
		if(GPU)
		{
			perf.CloseContext();
		}
		
		clReleaseContext(Context);
		
		version (AMDPerf)
		if(GPU)
		{
			perf.Destroy();
		}
	}
	
	cl_mem CreateBuffer(size_t size)
	{
		int err;
		auto ret = clCreateBuffer(Context, CL_MEM_READ_WRITE, size, null, &err);
		assert(err == CL_SUCCESS);
		return ret;
	}
	
	CCLBuffer!(T) CreateBufferEx(T)(size_t length)
	{
		return new CCLBuffer!(T)(this, length);
	}
	
	CCLKernel CreateKernel(cl_program program, char[] name)
	{
		return new CCLKernel(this, program, name);
	}
	
	void LaunchKernel(CCLKernel kernel, size_t[] num_work_items, size_t[] workgroup_size = null, cl_event* event = null)
	{
		if(workgroup_size != null)
			assert(num_work_items.length == workgroup_size.length, "Mismatched dimensions.");
		auto err = clEnqueueNDRangeKernel(Commands, kernel.Kernel, num_work_items.length, null, num_work_items.ptr, workgroup_size.ptr, 0, null, event);
		assert(err == CL_SUCCESS);
	}
	
	cl_program BuildProgram(char[] source)
	{
		int err;
		auto program = clCreateProgramWithSource(Context, 1, cast(char**)[source.ptr], cast(size_t*)[source.length], &err);
		if (!program)
			throw new Exception("Failed to create program.");

		err = clBuildProgram(program, 0, null, null, null, null);
		
		if(err != CL_SUCCESS)
		{
			size_t ret_len;
			char[] buffer;
			clGetProgramBuildInfo(program, Device, CL_PROGRAM_BUILD_LOG, 0, null, &ret_len);
			buffer.length = ret_len;
			clGetProgramBuildInfo(program, Device, CL_PROGRAM_BUILD_LOG, buffer.length, buffer.ptr, null);
			if(buffer.length > 1)
				Stdout(buffer[0..$-1]).nl;
			
			throw new Exception("Failed to build program.");
		}
		
		return program;
	}
	
	void Finish()
	{
		clFinish(Commands);
	}
	cl_command_queue Commands;
protected:
	cl_context Context;
	
	cl_platform_id Platform;
	cl_device_id Device;
	bool GPU = false;
}

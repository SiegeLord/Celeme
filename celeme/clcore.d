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
import tango.util.MinMax;

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
	this(CCLCore core, size_t length, size_t cache_size = 1)
	{
		Core = core;
		LengthVal = length;
		CacheSize = cache_size;
		if(CacheSize < 1)
			CacheSize = 1;
		
		int err;
		BufferVal = clCreateBuffer(Core.Context, CL_MEM_ALLOC_HOST_PTR, LengthVal * T.sizeof, null, &err);
		assert(err == 0, GetCLErrorString(err));
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
	
	T[] Map(cl_map_flags mode, size_t start = 0, size_t end = 0)
	{
		assert(start >= 0 && end <= Length);
		assert(end >= start);
		
		if(end <= 0)
			end = Length;
			
		if((mode & MappedMode) && start >= MappedOffset && end <= MappedOffset + Mapped.length)
		{
			return Mapped[start - MappedOffset..end - MappedOffset];
		}
		else
		{
			UnMap();

			int err;
			T* ret = cast(T*)clEnqueueMapBuffer(Core.Commands, Buffer, CL_TRUE, mode, start * T.sizeof, (end - start) * T.sizeof, 0, null, null, &err);
			assert(err == 0, GetCLErrorString(err));
			
			MappedMode = mode;
			MappedOffset = start;
			Mapped = ret[0..end - start];
			return Mapped;
		}
	}
	
	void Release()
	{
		UnMap();
		clReleaseMemObject(Buffer);
	}
	
	void UnMap()
	{
		if(Mapped.length)
		{
			clEnqueueUnmapMemObject(Core.Commands, Buffer, Mapped.ptr, 0, null, null);
			
			Mapped.length = 0;
			MappedOffset = 0;
			MappedMode = 0;
		}
	}
	
	T opSliceAssign(T val)
	{
		auto arr = MapWrite();
		arr[] = val;
		UnMap();
		return val;
	}
	
	T opSliceAssign(T val, size_t start, size_t end)
	{
		auto arr = MapWrite(start, end);
		arr[] = val;
		UnMap();
		return val;
	}
	
	T opIndex(size_t idx)
	{
		assert(idx >= 0 && idx < Length);
		
		if(!(CL_MAP_READ & MappedMode) || idx < MappedOffset || idx >= MappedOffset + Mapped.length)
			MapRead(idx, min(idx + CacheSize, Length));
		
		auto ret = Mapped[idx - MappedOffset];
		
		if(CacheSize == 1)
			UnMap();

		return ret;
	}
	
	T opIndexAssign(T val, size_t idx)
	{
		assert(idx >= 0 && idx < Length);
		
		if(!(CL_MAP_WRITE & MappedMode) || idx < MappedOffset || idx >= MappedOffset + Mapped.length)
			MapWrite(idx, min(idx + CacheSize, Length));
		
		Mapped[idx - MappedOffset] = val;
		
		if(CacheSize == 1)
			UnMap();

		return val;
	}
protected:
	size_t CacheSize = 1;
	T[] Mapped;
	size_t MappedOffset;
	int MappedMode = 0;
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
		assert(err == 0, GetCLErrorString(err));
		assert(num_platforms);
		
		cl_platform_id[] platforms;
		platforms.length = num_platforms;
		err = clGetPlatformIDs(num_platforms, platforms.ptr, null);
		assert(err == 0, GetCLErrorString(err));
		
		if(verbose)
		{
			foreach(ii, platform; platforms)
			{
				char[] get_param(cl_platform_info param)
				{
					char[] ret;
					size_t ret_len;
					auto err2 = clGetPlatformInfo(platform, param, 0, null, &ret_len);
					assert(err2 == 0, GetCLErrorString(err2)); 
					ret.length = ret_len;
					err2 = clGetPlatformInfo(platform, param, ret_len, ret.ptr, null);
					assert(err2 == 0, GetCLErrorString(err2));
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
		assert(err == 0, "This platform does not support " ~ (GPU ? "GPU" : "CPU") ~ " devices:" ~ GetCLErrorString(err));
		
		cl_device_id[] devices;
		devices.length = num_devices;
		err = clGetDeviceIDs(Platform, device_type, num_devices, devices.ptr, null);
		assert(err == 0, GetCLErrorString(err));
		
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
		assert(err == 0, "Failed to create a compute context: " ~ GetCLErrorString(err));

		/* Create a command commands */
		int flags = 0;
		version(Perf) flags = CL_QUEUE_PROFILING_ENABLE;
		Commands = clCreateCommandQueue(Context, Device, flags, &err);
		assert(err == 0, "Failed to create a command queue:" ~ GetCLErrorString(err));
		
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
			auto err2 = clGetDeviceInfo(device, param, 0, null, &ret_len);
			assert(err2 == 0, GetCLErrorString(err2)); 
			ret.length = ret_len;
			err2 = clGetDeviceInfo(device, param, ret_len, ret.ptr, null);
			assert(err2 == 0, GetCLErrorString(err2)); 
			return ret[0..$-1];
		}
		else
		{
			T ret;
			auto err2 = clGetDeviceInfo(device, param, T.sizeof, &ret, null);
			assert(err2 == 0, GetCLErrorString(err2)); 
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
		assert(err == 0, GetCLErrorString(err)); 
		return ret;
	}
	
	CCLBuffer!(T) CreateBufferEx(T)(size_t length, size_t cache_size = 1)
	{
		return new CCLBuffer!(T)(this, length, cache_size);
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
		assert(err == 0, GetCLErrorString(err)); 
	}
	
	cl_program BuildProgram(char[] source)
	{
		int err;
		auto program = clCreateProgramWithSource(Context, 1, cast(char**)[source.ptr], cast(size_t*)[source.length], &err);
		assert(err == 0, "Failed to create program: " ~ GetCLErrorString(err)); 

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
			
			assert(err == 0, "Failed to build program: " ~ GetCLErrorString(err)); 
		}
		
		return program;
	}
	
	void Finish()
	{
		clFinish(Commands);
	}
	
protected:
	cl_context Context;
	cl_command_queue Commands;
	cl_platform_id Platform;
	cl_device_id Device;
	bool GPU = false;
}

class CCLException : Exception
{
	this(char[] msg)
	{
		super(msg);
	}
}

char[] GetCLErrorString(cl_int ret_code)
{
	char[] msg_text;
	
	if(ret_code == CL_SUCCESS)
		return "";

	switch(ret_code)
	{
		case CL_DEVICE_NOT_FOUND:
			return "CL_DEVICE_NOT_FOUND";
		break;
		case CL_DEVICE_NOT_AVAILABLE:
			return "CL_DEVICE_NOT_AVAILABLE";
		break;
		case CL_COMPILER_NOT_AVAILABLE:
			return "CL_COMPILER_NOT_AVAILABLE";
		break;
		case CL_MEM_OBJECT_ALLOCATION_FAILURE:
			return "CL_MEM_OBJECT_ALLOCATION_FAILURE";
		break;
		case CL_OUT_OF_RESOURCES:
			return "CL_OUT_OF_RESOURCES";
		break;
		case CL_OUT_OF_HOST_MEMORY:
			return "CL_OUT_OF_HOST_MEMORY";
		break;
		case CL_PROFILING_INFO_NOT_AVAILABLE:
			return "CL_PROFILING_INFO_NOT_AVAILABLE";
		break;
		case CL_MEM_COPY_OVERLAP:
			return "CL_MEM_COPY_OVERLAP";
		break;
		case CL_IMAGE_FORMAT_MISMATCH:
			return "CL_IMAGE_FORMAT_MISMATCH";
		break;
		case CL_IMAGE_FORMAT_NOT_SUPPORTED:
			return "CL_IMAGE_FORMAT_NOT_SUPPORTED";
		break;
		case CL_BUILD_PROGRAM_FAILURE:
			return "CL_BUILD_PROGRAM_FAILURE";
		break;
		case CL_MAP_FAILURE:
			return "CL_MAP_FAILURE";
		break;
		case CL_MISALIGNED_SUB_BUFFER_OFFSET:
			return "CL_MISALIGNED_SUB_BUFFER_OFFSET";
		break;
		case CL_EXEC_STATUS_ERROR_FOR_EVENTS_IN_WAIT_LIST:
			return "CL_EXEC_STATUS_ERROR_FOR_EVENTS_IN_WAIT_LIST";
		break;
		case CL_INVALID_VALUE:
			return "CL_INVALID_VALUE";
		break;
		case CL_INVALID_DEVICE_TYPE:
			return "CL_INVALID_DEVICE_TYPE";
		break;
		case CL_INVALID_PLATFORM:
			return "CL_INVALID_PLATFORM";
		break;
		case CL_INVALID_DEVICE:
			return "CL_INVALID_DEVICE";
		break;
		case CL_INVALID_CONTEXT:
			return "CL_INVALID_CONTEXT";
		break;
		case CL_INVALID_QUEUE_PROPERTIES:
			return "CL_INVALID_QUEUE_PROPERTIES";
		break;
		case CL_INVALID_COMMAND_QUEUE:
			return "CL_INVALID_COMMAND_QUEUE";
		break;
		case CL_INVALID_HOST_PTR:
			return "CL_INVALID_HOST_PTR";
		break;
		case CL_INVALID_MEM_OBJECT:
			return "CL_INVALID_MEM_OBJECT";
		break;
		case CL_INVALID_IMAGE_FORMAT_DESCRIPTOR:
			return "CL_INVALID_IMAGE_FORMAT_DESCRIPTOR";
		break;
		case CL_INVALID_IMAGE_SIZE:
			return "CL_INVALID_IMAGE_SIZE";
		break;
		case CL_INVALID_SAMPLER:
			return "CL_INVALID_SAMPLER";
		break;
		case CL_INVALID_BINARY:
			return "CL_INVALID_BINARY";
		break;
		case CL_INVALID_BUILD_OPTIONS:
			return "CL_INVALID_BUILD_OPTIONS";
		break;
		case CL_INVALID_PROGRAM:
			return "CL_INVALID_PROGRAM";
		break;
		case CL_INVALID_PROGRAM_EXECUTABLE:
			return "CL_INVALID_PROGRAM_EXECUTABLE";
		break;
		case CL_INVALID_KERNEL_NAME:
			return "CL_INVALID_KERNEL_NAME";
		break;
		case CL_INVALID_KERNEL_DEFINITION:
			return "CL_INVALID_KERNEL_DEFINITION";
		break;
		case CL_INVALID_KERNEL:
			return "CL_INVALID_KERNEL";
		break;
		case CL_INVALID_ARG_INDEX:
			return "CL_INVALID_ARG_INDEX";
		break;
		case CL_INVALID_ARG_VALUE:
			return "CL_INVALID_ARG_VALUE";
		break;
		case CL_INVALID_ARG_SIZE:
			return "CL_INVALID_ARG_SIZE";
		break;
		case CL_INVALID_KERNEL_ARGS:
			return "CL_INVALID_KERNEL_ARGS";
		break;
		case CL_INVALID_WORK_DIMENSION:
			return "CL_INVALID_WORK_DIMENSION";
		break;
		case CL_INVALID_WORK_GROUP_SIZE:
			return "CL_INVALID_WORK_GROUP_SIZE";
		break;
		case CL_INVALID_WORK_ITEM_SIZE:
			return "CL_INVALID_WORK_ITEM_SIZE";
		break;
		case CL_INVALID_GLOBAL_OFFSET:
			return "CL_INVALID_GLOBAL_OFFSET";
		break;
		case CL_INVALID_EVENT_WAIT_LIST:
			return "CL_INVALID_EVENT_WAIT_LIST";
		break;
		case CL_INVALID_EVENT:
			return "CL_INVALID_EVENT";
		break;
		case CL_INVALID_OPERATION:
			return "CL_INVALID_OPERATION";
		break;
		case CL_INVALID_GL_OBJECT:
			return "CL_INVALID_GL_OBJECT";
		break;
		case CL_INVALID_BUFFER_SIZE:
			return "CL_INVALID_BUFFER_SIZE";
		break;
		case CL_INVALID_MIP_LEVEL:
			return "CL_INVALID_MIP_LEVEL";
		break;
		case CL_INVALID_GLOBAL_WORK_SIZE:
			return "CL_INVALID_GLOBAL_WORK_SIZE";
		break;
	}
	assert(0);
}

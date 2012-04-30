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

module celeme.internal.clcore;

import celeme.platform_flags;
import celeme.internal.util;

import opencl.cl;
import dutil.Disposable;

import tango.io.Stdout;
import tango.util.Convert;
import tango.util.MinMax;
import tango.core.ArrayLiteral : AL = ArrayLiteral;
import tango.core.Array;
import tango.text.convert.Format;

class CCLKernel : CDisposable
{
	this(CCLCore core, cl_program program, cstring name)
	{
		Core = core;
		Name = name;
		
		int err;
		Kernel = clCreateKernel(program, Name.c_str(), &err);
		if(err != CL_SUCCESS)
		{
			throw new Exception("Failed to create '" ~ Name.idup ~ "' kernel.");
		}
	}
	
	void SetGlobalArg(T)(size_t argnum, T arg)
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
			auto err = clSetKernelArg(Kernel, cast(uint)argnum, arg.Buffer.sizeof, &buf);
		}
		else
			auto err = clSetKernelArg(Kernel, cast(uint)argnum, T.sizeof, &arg);

		if(err != CL_SUCCESS)
		{
			throw new Exception("Failed to set a global argument " ~ to!(char[])(argnum).idup ~ " of kernel '" ~ Name.idup ~ "'.");
		}
	}

	void SetLocalArg(size_t argnum, size_t size)
	{
		auto err = clSetKernelArg(Kernel, cast(uint)argnum, size, null);
		if(err != CL_SUCCESS)
		{
			throw new Exception("Failed to set a local argument " ~ to!(char[])(argnum).idup ~ " of kernel '" ~ Name.idup ~ "'.");
		}
	}
	
	void Launch(size_t[] num_work_items, size_t[] workgroup_size = null, cl_event* event = null)
	{
		Core.LaunchKernel(this, num_work_items, workgroup_size, event);
	}

	override
	void Dispose()
	{
		clReleaseKernel(Kernel);
		super.Dispose();
	}
	
	CCLCore Core;
	cl_kernel Kernel;
	cstring Name;
}

class CCLBufferBase : CDisposable
{
	@property
	cl_mem Buffer()
	{
		return BufferVal;
	}
	
	@property
	size_t Length()
	{
		return LengthVal;
	}
protected:
	cl_mem BufferVal;
	size_t LengthVal;
	
	cl_mem HostBuffer;
	
	bool UseTwoBuffers = false;
	CCLCore Core;
	bool UseCache = false;
	bool PreserveMappedBuffer = false;
	size_t CacheSize = 1;
	size_t MappedOffset = 0;
	cl_mem_flags MappedMode = 0;
}

class CCLBuffer(T) : CCLBufferBase
{
	this(CCLCore core, size_t length, size_t cache_size = 0, bool read = true, bool write = true, bool use_two_buffers = false)
	{
		Core = core;
		LengthVal = length;
		UseCache = cache_size > 0;
		CacheSize = max(cache_size, 1UL);
		UseTwoBuffers = use_two_buffers;
		
		int err;
		if(UseTwoBuffers)
		{
			int flags;
			if(read)
			{
				if(write)
					flags = CL_MEM_READ_WRITE;
				else
					flags = CL_MEM_READ_ONLY;
			}
			else
			{
				if(write)
					flags = CL_MEM_WRITE_ONLY;
				else
					throw new Exception("Invalid combination of read/write parameters.");
			}
			
			BufferVal = clCreateBuffer(Core.Context, flags, LengthVal * T.sizeof, null, &err);
			assert(err == 0, GetCLErrorString(err));
			HostBuffer = clCreateBuffer(Core.Context, CL_MEM_ALLOC_HOST_PTR, LengthVal * T.sizeof, null, &err);
			assert(err == 0, GetCLErrorString(err));
		}
		else
		{
			BufferVal = clCreateBuffer(Core.Context, CL_MEM_ALLOC_HOST_PTR, LengthVal * T.sizeof, null, &err);
			HostBuffer = BufferVal;
			assert(err == 0, GetCLErrorString(err));
		}
	}
	
	T[] MapWrite(size_t start = 0, size_t end = 0, bool preserve_mapped_buffer = true)
	{
		return Map(CL_MAP_WRITE, start, end, preserve_mapped_buffer);
	}
	
	T[] MapReadWrite(size_t start = 0, size_t end = 0, bool preserve_mapped_buffer = true)
	{
		return Map(CL_MAP_WRITE | CL_MAP_READ, start, end, preserve_mapped_buffer);
	}
	
	T[] MapRead(size_t start = 0, size_t end = 0, bool preserve_mapped_buffer = true)
	{
		return Map(CL_MAP_READ, start, end, preserve_mapped_buffer);
	}
	
	T[] Map(cl_map_flags mode, size_t start = 0, size_t end = 0, bool preserve_mapped_buffer = true)
	{
		assert(end <= Length);
		assert(end >= start);
		
		if(end <= 0)
			end = Length;
			
		if(((mode & MappedMode) == mode) && start >= MappedOffset && end <= MappedOffset + Mapped.length)
		{
			PreserveMappedBuffer = preserve_mapped_buffer;
			return Mapped[start - MappedOffset..end - MappedOffset];
		}
		else
		{
			UnMap();
			
			if(UseTwoBuffers && (mode & CL_MAP_READ))
			{
				auto err = clEnqueueCopyBuffer(Core.Commands, Buffer, HostBuffer, start * T.sizeof, start * T.sizeof, (end - start) * T.sizeof, 0, null, null);
				assert(err == 0, GetCLErrorString(err));
			}

			int err;
			T* ret = cast(T*)clEnqueueMapBuffer(Core.Commands, HostBuffer, CL_TRUE, mode, start * T.sizeof, (end - start) * T.sizeof, 0, null, null, &err);
			assert(err == 0, GetCLErrorString(err));
			
			PreserveMappedBuffer = preserve_mapped_buffer;
			MappedMode = mode;
			MappedOffset = start;
			Mapped = ret[0..end - start];
			return Mapped;
		}
	}
	
	override
	void Dispose()
	{
		UnMap();
		clReleaseMemObject(Buffer);
		if(UseTwoBuffers)
			clReleaseMemObject(HostBuffer);
		
		super.Dispose();
	}
	
	void UnMap()
	{
		if(Mapped.length)
		{
			clEnqueueUnmapMemObject(Core.Commands, HostBuffer, Mapped.ptr, 0, null, null);
			
			if(UseTwoBuffers && (MappedMode & CL_MAP_WRITE))
			{
				auto err = clEnqueueCopyBuffer(Core.Commands, HostBuffer, Buffer, MappedOffset * T.sizeof, MappedOffset * T.sizeof, Mapped.length * T.sizeof, 0, null, null);
				assert(err == 0, GetCLErrorString(err));
			}
			
			Mapped.length = 0;
			MappedOffset = 0;
			MappedMode = 0;
			PreserveMappedBuffer = false;
		}
	}
	
	/*
	 * Read one
	 *    If mapped readable, just read it
	 *    Else, map the cache
	 *       If UseCache is off then uncache
	 */
	T opIndex(size_t idx)
	{
		assert(idx < Length);
		
		bool new_map = false;
		
		if(!(CL_MAP_READ & MappedMode) || idx < MappedOffset || idx >= MappedOffset + Mapped.length)
		{
			if(PreserveMappedBuffer)
				assert("Tried to read outside the mapped region (or from a write only region).");
			MapRead(idx, min(idx + CacheSize, Length), false);
			new_map = true;
		}
		
		auto ret = Mapped[idx - MappedOffset];
		
		if(!UseCache && new_map)
			UnMap();

		return ret;
	}
	
	/*
	 * Write one
	 *    If mapped writable, write it
	 *    Else, map one
	 *       Uncache
	 */
	T opIndexAssign(T val, size_t idx)
	{
		assert(idx < Length);
		
		bool new_map = false;
		
		if(!(CL_MAP_WRITE & MappedMode) || idx < MappedOffset || idx >= MappedOffset + Mapped.length)
		{
			if(PreserveMappedBuffer)
				assert("Tried to write outside the mapped region (or to a read only region).");
			/* When doing cached writes we need to read as well as write */
			if(UseCache)
				MapReadWrite(idx, min(idx + CacheSize, Length), false);
			else
				MapWrite(idx, idx + 1, false);
			new_map = true;
		}
		
		Mapped[idx - MappedOffset] = val;
		
		if(!UseCache && new_map)
			UnMap();

		return val;
	}
	
	/*
	 * See opIndex for rationale
	 */
	T opSliceAssign(T val)
	{
		return this[0..Length] = val;
	}
	
	/*
	 * See opIndex for rationale
	 */
	T opSliceAssign(T val, size_t start, size_t end)
	{
		assert(end >= start);
		
		bool new_map = false;
		
		if(!(CL_MAP_WRITE & MappedMode) || start < MappedOffset || end > MappedOffset + Mapped.length)
		{
			if(PreserveMappedBuffer)
				assert("Tried to write outside the mapped region (or to a read only region).");
			if(UseCache)
				MapReadWrite(start, end, false);
			else
				MapWrite(start, end, false);
			new_map = true;
		}
		
		Mapped[start - MappedOffset..end - MappedOffset] = val;
		
		if(!UseCache && new_map)
			UnMap();

		return val;
	}
protected:
	T[] Mapped;
}

class CCLCore : CDisposable
{
	this(EPlatformFlags platform_flags, size_t device_idx)
	{
		int err;
		PlatformFlags = platform_flags;
		
		bool force = (PlatformFlags & EPlatformFlags.Force) != 0;
		
		/* PlatformFlags are adjusted here to reflect what we actually have */
		auto devices = GetDevices(PlatformFlagsVal, Platform);
		
		if(devices is null)
			throw new Exception("Couldn't find suitable OpenCL devices." ~ (force ? " Try a different platform." : ""));
		
		if(force)
		{
			assert(device_idx < devices.length, "Invalid device index");
			Device = devices[device_idx];
			if(GetDeviceParam!(int)(Device, CL_DEVICE_AVAILABLE) != 1)
				throw new Exception("Device " ~ Format("{}", device_idx).idup ~ " is not available.");
		}
		else
		{
			foreach(device; devices)
			{
				if(GetDeviceParam!(int)(device, CL_DEVICE_AVAILABLE) == 1)
				{
					Device = device;
					break;
				}
			}
			if(Device is null)
				throw new Exception("No available devices.");
		}
		
		/* Create a compute context */
		Context = clCreateContext(null, 1, &Device, null, null, &err);
		assert(err == 0, "Failed to create a compute context: " ~ GetCLErrorString(err));

		/* Create a command commands */
		int flags = 0;
		version(Perf) flags = CL_QUEUE_PROFILING_ENABLE;
		Commands = clCreateCommandQueue(Context, Device, flags, &err);
		assert(err == 0, "Failed to create a command queue:" ~ GetCLErrorString(err));
		
		/* Get the multiplier, for GPU we get it by building a dummy kernel and for CPU we get it from
		 * the number of cores the device has */
		if(GPU)
		{
			auto dummy_program = BuildProgram("__kernel void dummy() {}");
			scope(exit) clReleaseProgram(dummy_program);
			
			auto dummy_kernel = clCreateKernel(dummy_program, "dummy", &err);
			scope(exit) clReleaseKernel(dummy_kernel);
			assert(err == 0, "Failed to create the dummy kernel." ~ GetCLErrorString(err));
			
			err = clGetKernelWorkGroupInfo(dummy_kernel, Device, CL_KERNEL_PREFERRED_WORK_GROUP_SIZE_MULTIPLE, size_t.sizeof, &SizeMultiplier, null);
			assert(err == 0, "Failed to get the preferred workgroup size.");
		}
		else
		{
			/* Overloading the CPU seems to do better than doing 1 workgroup per core */
			SizeMultiplier = cast(size_t)(GetDeviceParam!(uint)(Device, CL_DEVICE_MAX_COMPUTE_UNITS) * 1.9);
		}
	}
	
	cl_device_id[] GetDevices(ref EPlatformFlags flags, out cl_platform_id chosen_platform)
	{
		int err;
		
		enum : size_t
		{
			AMD,
			NVidia,
			Intel,
			NumPlatforms
		}
		
		struct SPlatformDesc
		{
			cstring Vendor;
			EPlatformFlags Flags;
		}
		
		SPlatformDesc[NumPlatforms] platform_descs;
		platform_descs[AMD] = SPlatformDesc("Advanced Micro Devices, Inc.", EPlatformFlags.AMD);
		platform_descs[NVidia] = SPlatformDesc("NVIDIA Corporation", EPlatformFlags.NVidia);
		platform_descs[Intel] = SPlatformDesc("Intel(R) Corporation", EPlatformFlags.Intel);
		
		size_t get_platform_idx(cstring vendor_string)
		{
			return platform_descs.findIf((SPlatformDesc e) { return vendor_string == e.Vendor; });
		}
		
		/* Choose the default platform */
		size_t preferred_platform = AMD;
		bool platform_pref = true;
		if(flags & EPlatformFlags.AMD)
			preferred_platform = AMD;
		else if(flags & EPlatformFlags.Intel)
			preferred_platform = Intel;
		else if(flags & EPlatformFlags.NVidia)
			preferred_platform = NVidia;
		else
			platform_pref = false; /* We choose AMD, but make note that the user picked nothing */
		
		/* Get all the available platforms */
		uint num_platforms;
		err = clGetPlatformIDs(0, null, &num_platforms);
		assert(err == 0, GetCLErrorString(err));
		assert(num_platforms);
		
		cl_platform_id[] platforms;
		platforms.length = num_platforms;
		err = clGetPlatformIDs(num_platforms, platforms.ptr, null);
		assert(err == 0, GetCLErrorString(err));
		
		cstring get_platform_param(cl_platform_id platform, cl_platform_info param)
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
		
		bool platform_sorter(cl_platform_id p1, cl_platform_id p2)
		{
			auto idx1 = get_platform_idx(get_platform_param(p1, CL_PLATFORM_VENDOR));
			auto idx2 = get_platform_idx(get_platform_param(p2, CL_PLATFORM_VENDOR));
			
			if(idx1 == preferred_platform)
				return true;
			else if(idx2 == preferred_platform)
				return false;
			else
				return idx1 < idx2;
		}
		
		platforms.sort(&platform_sorter);
		
		cl_device_id[] test_platform(cl_platform_id platform, bool gpu)
		{
			/* Get devices, check at least one is available */
			uint num_devices;
			auto device_type = gpu ? CL_DEVICE_TYPE_GPU : CL_DEVICE_TYPE_CPU;
			err = clGetDeviceIDs(platform, device_type, 0, null, &num_devices);
			if(err != 0)
				return null;
			
			cl_device_id[] devices;
			devices.length = num_devices;
			err = clGetDeviceIDs(platform, device_type, num_devices, devices.ptr, null);
			assert(err == 0, GetCLErrorString(err));
			
			foreach(device; devices)
			{
				if(GetDeviceParam!(int)(device, CL_DEVICE_AVAILABLE) == 1)
					return devices;
			}
			
			return null;
		}
		
		cl_device_id[] test_platforms(bool gpu)
		{
			foreach(platform; platforms)
			{
				auto platform_idx = get_platform_idx(get_platform_param(platform, CL_PLATFORM_VENDOR));
				
				if(platform_pref && flags & EPlatformFlags.Force && platform_idx != preferred_platform)
					continue;
				
				auto ret = test_platform(platform, gpu);
				if(ret !is null)
				{
					chosen_platform = platform;
					flags = gpu ? EPlatformFlags.GPU : EPlatformFlags.CPU;
					if(platform_idx < NumPlatforms)
						flags |= platform_descs[platform_idx].Flags;
					return ret;
				}
			}
			
			return null;
		}
		
		/* If the flags don't ask for the CPU devices explicitly, try the GPU devices first */
		if(!(flags & EPlatformFlags.CPU))
		{
			auto ret = test_platforms(true);
			if(ret !is null)
				return ret;
			
			if(flags & EPlatformFlags.GPU && flags & EPlatformFlags.Force)
				return null;
		}
		
		/* Try the CPU devices */
		auto ret = test_platforms(false);
		
		return ret;
	}
	
	private T GetDeviceParam(T)(cl_device_id device, cl_device_info param)
	{
		static if(is(T : cstring))
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

	override
	void Dispose()
	{
		clReleaseCommandQueue(Commands);
		clReleaseContext(Context);
		super.Dispose();
	}
	
	CCLBuffer!(T) CreateBuffer(T)(size_t length, bool read = true, bool write = true, size_t cache_size = 0)
	{
		return new CCLBuffer!(T)(this, length, cache_size, read, write, GPU);
	}
	
	CCLKernel CreateKernel(cl_program program, cstring name)
	{
		return new CCLKernel(this, program, name);
	}
	
	void LaunchKernel(CCLKernel kernel, size_t[] num_work_items, size_t[] workgroup_size = null, cl_event* event = null)
	{
		if(workgroup_size != null)
			assert(num_work_items.length == workgroup_size.length, "Mismatched dimensions.");
		auto err = clEnqueueNDRangeKernel(Commands, kernel.Kernel, cast(uint)num_work_items.length, null, num_work_items.ptr, workgroup_size.ptr, 0, null, event);
		assert(err == 0, GetCLErrorString(err)); 
	}
	
	cl_program BuildProgram(cstring source)
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
	
	/* Given the current number of workitems it returns a better number (greater than or equal to
	 * the passed one) as well as the workgroup size that corresponds to it */
	size_t GetGoodNumWorkitems(size_t cur_num, out size_t workgroup_size)
	{
		size_t get_next_multiple(size_t num, size_t mult)
		{
			return num % mult ? (num / mult) * mult + mult : num;
		}
		
		auto ret = get_next_multiple(cur_num, SizeMultiplier);
		if(GPU)
		{
			workgroup_size = SizeMultiplier;
		}
		else
		{
			workgroup_size = ret / SizeMultiplier;
			
			/* Check to see that we can actually make a workgroup size for this */
			auto max_size = GetDeviceParam!(size_t)(Device, CL_DEVICE_MAX_WORK_GROUP_SIZE);
			if(workgroup_size > max_size)
			{
				auto new_mult = get_next_multiple(cur_num, max_size) / max_size;
				ret = get_next_multiple(cur_num, new_mult);
				workgroup_size = ret / new_mult;
			}
		}
		
		return ret;
	}

	mixin(Prop!("EPlatformFlags", "PlatformFlags", "", "private"));
	
	@property
	bool GPU()
	{
		return (PlatformFlags & EPlatformFlags.GPU) != 0;
	}
	
protected:
	EPlatformFlags PlatformFlagsVal;
	cl_context Context;
	cl_command_queue Commands;
	cl_platform_id Platform;
	cl_device_id Device;
	size_t SizeMultiplier;
}

class CCLException : Exception
{
	this(immutable(char)[] msg)
	{
		super(msg);
	}
}

cstring GetCLErrorString(cl_int ret_code)
{
	if(ret_code == CL_SUCCESS)
		return "";

	switch(ret_code)
	{
		case CL_DEVICE_NOT_FOUND:
			return "CL_DEVICE_NOT_FOUND";
		case CL_DEVICE_NOT_AVAILABLE:
			return "CL_DEVICE_NOT_AVAILABLE";
		case CL_COMPILER_NOT_AVAILABLE:
			return "CL_COMPILER_NOT_AVAILABLE";
		case CL_MEM_OBJECT_ALLOCATION_FAILURE:
			return "CL_MEM_OBJECT_ALLOCATION_FAILURE";
		case CL_OUT_OF_RESOURCES:
			return "CL_OUT_OF_RESOURCES";
		case CL_OUT_OF_HOST_MEMORY:
			return "CL_OUT_OF_HOST_MEMORY";
		case CL_PROFILING_INFO_NOT_AVAILABLE:
			return "CL_PROFILING_INFO_NOT_AVAILABLE";
		case CL_MEM_COPY_OVERLAP:
			return "CL_MEM_COPY_OVERLAP";
		case CL_IMAGE_FORMAT_MISMATCH:
			return "CL_IMAGE_FORMAT_MISMATCH";
		case CL_IMAGE_FORMAT_NOT_SUPPORTED:
			return "CL_IMAGE_FORMAT_NOT_SUPPORTED";
		case CL_BUILD_PROGRAM_FAILURE:
			return "CL_BUILD_PROGRAM_FAILURE";
		case CL_MAP_FAILURE:
			return "CL_MAP_FAILURE";
		case CL_MISALIGNED_SUB_BUFFER_OFFSET:
			return "CL_MISALIGNED_SUB_BUFFER_OFFSET";
		case CL_EXEC_STATUS_ERROR_FOR_EVENTS_IN_WAIT_LIST:
			return "CL_EXEC_STATUS_ERROR_FOR_EVENTS_IN_WAIT_LIST";
		case CL_INVALID_VALUE:
			return "CL_INVALID_VALUE";
		case CL_INVALID_DEVICE_TYPE:
			return "CL_INVALID_DEVICE_TYPE";
		case CL_INVALID_PLATFORM:
			return "CL_INVALID_PLATFORM";
		case CL_INVALID_DEVICE:
			return "CL_INVALID_DEVICE";
		case CL_INVALID_CONTEXT:
			return "CL_INVALID_CONTEXT";
		case CL_INVALID_QUEUE_PROPERTIES:
			return "CL_INVALID_QUEUE_PROPERTIES";
		case CL_INVALID_COMMAND_QUEUE:
			return "CL_INVALID_COMMAND_QUEUE";
		case CL_INVALID_HOST_PTR:
			return "CL_INVALID_HOST_PTR";
		case CL_INVALID_MEM_OBJECT:
			return "CL_INVALID_MEM_OBJECT";
		case CL_INVALID_IMAGE_FORMAT_DESCRIPTOR:
			return "CL_INVALID_IMAGE_FORMAT_DESCRIPTOR";
		case CL_INVALID_IMAGE_SIZE:
			return "CL_INVALID_IMAGE_SIZE";
		case CL_INVALID_SAMPLER:
			return "CL_INVALID_SAMPLER";
		case CL_INVALID_BINARY:
			return "CL_INVALID_BINARY";
		case CL_INVALID_BUILD_OPTIONS:
			return "CL_INVALID_BUILD_OPTIONS";
		case CL_INVALID_PROGRAM:
			return "CL_INVALID_PROGRAM";
		case CL_INVALID_PROGRAM_EXECUTABLE:
			return "CL_INVALID_PROGRAM_EXECUTABLE";
		case CL_INVALID_KERNEL_NAME:
			return "CL_INVALID_KERNEL_NAME";
		case CL_INVALID_KERNEL_DEFINITION:
			return "CL_INVALID_KERNEL_DEFINITION";
		case CL_INVALID_KERNEL:
			return "CL_INVALID_KERNEL";
		case CL_INVALID_ARG_INDEX:
			return "CL_INVALID_ARG_INDEX";
		case CL_INVALID_ARG_VALUE:
			return "CL_INVALID_ARG_VALUE";
		case CL_INVALID_ARG_SIZE:
			return "CL_INVALID_ARG_SIZE";
		case CL_INVALID_KERNEL_ARGS:
			return "CL_INVALID_KERNEL_ARGS";
		case CL_INVALID_WORK_DIMENSION:
			return "CL_INVALID_WORK_DIMENSION";
		case CL_INVALID_WORK_GROUP_SIZE:
			return "CL_INVALID_WORK_GROUP_SIZE";
		case CL_INVALID_WORK_ITEM_SIZE:
			return "CL_INVALID_WORK_ITEM_SIZE";
		case CL_INVALID_GLOBAL_OFFSET:
			return "CL_INVALID_GLOBAL_OFFSET";
		case CL_INVALID_EVENT_WAIT_LIST:
			return "CL_INVALID_EVENT_WAIT_LIST";
		case CL_INVALID_EVENT:
			return "CL_INVALID_EVENT";
		case CL_INVALID_OPERATION:
			return "CL_INVALID_OPERATION";
		case CL_INVALID_GL_OBJECT:
			return "CL_INVALID_GL_OBJECT";
		case CL_INVALID_BUFFER_SIZE:
			return "CL_INVALID_BUFFER_SIZE";
		case CL_INVALID_MIP_LEVEL:
			return "CL_INVALID_MIP_LEVEL";
		case CL_INVALID_GLOBAL_WORK_SIZE:
			return "CL_INVALID_GLOBAL_WORK_SIZE";
		default:
			return "Unknown error.";
	}
	assert(0);
}

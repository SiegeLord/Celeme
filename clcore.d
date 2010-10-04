module clcore;

import opencl.cl;

import tango.io.Stdout;

void SetGlobalArg(T)(cl_kernel kernel, uint argnum, T* arg)
{
	auto err = clSetKernelArg(kernel, argnum, T.sizeof, arg);
	if(err != CL_SUCCESS)
	{
		throw new Exception("Failed to set a global kernel argument");
	}
}

void SetLocalArg(cl_kernel kernel, uint argnum, size_t size)
{
	auto err = clSetKernelArg(kernel, argnum, size, null);
	if(err != CL_SUCCESS)
	{
		throw new Exception("Failed to set a local kernel argument");
	}
}

class CCLCore
{
	this(bool use_gpu = false, bool verbose = false)
	{
		GPU = use_gpu;
		
		int err;
		
		/* Get platforms */
		uint num_platforms;
		err = clGetPlatformIDs(0, null, &num_platforms);
		assert(err == CL_SUCCESS);
		assert(num_platforms);
		
		Platforms.length = num_platforms;
		err = clGetPlatformIDs(num_platforms, Platforms.ptr, null);
		assert(err == CL_SUCCESS);
		
		if(verbose)
		{
			foreach(ii, platform; Platforms)
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
		
		/* Get devices */
		uint num_devices;
		auto device_type = GPU ? CL_DEVICE_TYPE_GPU : CL_DEVICE_TYPE_CPU;
		err = clGetDeviceIDs(Platforms[0], device_type, 0, null, &num_devices);
		if(err == CL_DEVICE_NOT_FOUND)
			throw new Exception("This platform does not support " ~ (GPU ? "GPU" : "CPU") ~ " devices!");
		assert(err == CL_SUCCESS);
		
		Devices.length = num_devices;
		clGetDeviceIDs(Platforms[0], device_type, num_devices, Devices.ptr, null);
		assert(err == CL_SUCCESS);
		
		if(verbose)
		{
			foreach(ii, device; Devices)
			{
				Stdout.formatln("Device {}:", ii);
				Stdout.formatln("\tCL_DEVICE_ADDRESS_BITS:\n\t\t{}", GetDeviceParam!(uint)(device, CL_DEVICE_ADDRESS_BITS));
				Stdout.formatln("\tCL_DEVICE_AVAILABLE:\n\t\t{}", 1 == GetDeviceParam!(int)(device, CL_DEVICE_AVAILABLE));
				Stdout.formatln("\tCL_DEVICE_COMPILER_AVAILABLE:\n\t\t{}", 1 == GetDeviceParam!(int)(device, CL_DEVICE_COMPILER_AVAILABLE));
				/* And so on... */
			}
		}
		
		/* Create a compute context */
		Context = clCreateContext(null, 1, &Devices[0], null, null, &err);
		if(!Context)
		{
			throw new Exception("Failed to create a compute context!");
		}

		/* Create a command commands */
		Commands = clCreateCommandQueue(Context, Devices[0], 0, &err);
		if(!Commands)
		{
			throw new Exception("Failed to create a command queue!");
		}
	}
	
	T GetDeviceParam(T)(cl_device_id device, cl_device_info param)
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
		clReleaseContext(Context);
	}
	
	cl_mem CreateBuffer(size_t size)
	{
		int err;
		auto ret = clCreateBuffer(Context, CL_MEM_READ_WRITE, size, null, &err);
		assert(err == CL_SUCCESS);
		return ret;
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
			clGetProgramBuildInfo(program, Devices[0], CL_PROGRAM_BUILD_LOG, 0, null, &ret_len);
			buffer.length = ret_len;
			clGetProgramBuildInfo(program, Devices[0], CL_PROGRAM_BUILD_LOG, buffer.length, buffer.ptr, null);
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
	
	cl_context Context;
	cl_command_queue Commands;
	cl_platform_id[] Platforms;
	cl_device_id[] Devices;
	bool GPU = false;
}

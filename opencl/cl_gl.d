/**********************************************************************************
 * Copyright (c) 2008-2010 The Khronos Group Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and/or associated documentation files (the
 * "Materials"), to deal in the Materials without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Materials, and to
 * permit persons to whom the Materials are furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Materials.
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * MATERIALS OR THE USE OR OTHER DEALINGS IN THE MATERIALS.
 **********************************************************************************/

// $Revision: 11708 $ on $Date: 2010-06-13 23:36:24 -0700 (Sun, 13 Jun 2010) $

/**
 * cl_gl.h contains Khronos-approved (KHR) OpenCL extensions which have
 * OpenGL dependencies. The application is responsible for #including
 * OpenGL or OpenGL ES headers before #including cl_gl.h.
 */
module opencl.cl_gl;

//import opencl.cl_platform;
import opencl.cl;

extern(C):

typedef cl_uint	 cl_gl_object_type;
typedef cl_uint	 cl_gl_texture_info;
typedef cl_uint	 cl_gl_platform_info;
typedef void* cl_GLsync;

enum
{
	// cl_gl_object_type
	CL_GL_OBJECT_BUFFER			= 0x2000,
	CL_GL_OBJECT_TEXTURE2D		= 0x2001,
	CL_GL_OBJECT_TEXTURE3D		= 0x2002,
	CL_GL_OBJECT_RENDERBUFFER	= 0x2003,

	// cl_gl_texture_info
	CL_GL_TEXTURE_TARGET		= 0x2004,
	CL_GL_MIPMAP_LEVEL			= 0x2005,
}

cl_mem clCreateFromGLBuffer(
	cl_context		context,
	cl_mem_flags	flags,
	cl_GLuint		bufobj,
	int*			errcode_ret
);

cl_mem clCreateFromGLTexture2D(
	cl_context		context,
	cl_mem_flags	flags,
	cl_GLenum		target,
	cl_GLint		miplevel,
	cl_GLuint		texture,
	cl_int*			errcode_ret
);

cl_mem clCreateFromGLTexture3D(
	cl_context		context,
	cl_mem_flags	flags,
	cl_GLenum		target,
	cl_GLint		miplevel,
	cl_GLuint		texture,
	cl_int*			errcode_ret
);

cl_mem clCreateFromGLRenderbuffer(
	cl_context		context,
	cl_mem_flags	flags,
	cl_GLuint		renderbuffer,
	cl_int*			errcode_ret
);

cl_int clGetGLObjectInfo(
	cl_mem				memobj,
	cl_gl_object_type*	gl_object_type,
	cl_GLuint*			gl_object_name
);

cl_int clGetGLTextureInfo(
	cl_mem				memobj,
	cl_gl_texture_info	param_name,
	size_t				param_value_size,
	void*				param_value,
	size_t*				param_value_size_ret
);

cl_int clEnqueueAcquireGLObjects(
	cl_command_queue	queue,
	cl_uint				num_objects,
	cl_mem*		        mem_objects,
	cl_uint				num_events_in_wait_list,
	cl_event*	        event_wait_list,
	cl_event*			event
);

cl_int clEnqueueReleaseGLObjects(
	cl_command_queue	queue,
	cl_uint				num_objects,
	cl_mem*		        mem_objects,
	cl_uint				num_events_in_wait_list,
	cl_event*	        event_wait_list,
	cl_event*			event
);


// cl_khr_gl_sharing extension

version = cl_khr_gl_sharing;

typedef cl_uint cl_gl_context_info;

enum
{
	// Additional Error Codes
	CL_INVALID_GL_SHAREGROUP_REFERENCE_KHR	= -1000,
	
	// cl_gl_context_info
	CL_CURRENT_DEVICE_FOR_GL_CONTEXT_KHR	= 0x2006,
	CL_DEVICES_FOR_GL_CONTEXT_KHR			= 0x2007,
	
	// Additional cl_context_properties
	CL_GL_CONTEXT_KHR						= 0x2008,
	CL_EGL_DISPLAY_KHR						= 0x2009,
	CL_GLX_DISPLAY_KHR						= 0x200A,
	CL_WGL_HDC_KHR							= 0x200B,
	CL_CGL_SHAREGROUP_KHR					= 0x200C,
}

cl_int clGetGLContextInfoKHR(
	cl_context_properties*	        properties,
	cl_gl_context_info				param_name,
	size_t							param_value_size,
	void*							param_value,
	size_t*							param_value_size_ret
);

typedef extern(System) cl_int function(
		cl_context_properties*	        properties,
		cl_gl_context_info				param_name,
		size_t							param_value_size,
		void*							param_value,
		size_t*							param_value_size_ret
	) clGetGLContextInfoKHR_fn;

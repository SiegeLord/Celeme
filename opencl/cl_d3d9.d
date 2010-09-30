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

module opencl.cl_d3d9;

import opencl.cl;

extern(C):

/******************************************************************************
 * cl_nv_d3d9_sharing														 */

typedef cl_uint cl_d3d9_device_source_nv;
typedef cl_uint cl_d3d9_device_set_nv;

/******************************************************************************/

// Error Codes
enum
{
	CL_INVALID_D3D9_DEVICE_NV				= -1010,
	CL_INVALID_D3D9_RESOURCE_NV				= -1011,
	CL_D3D9_RESOURCE_ALREADY_ACQUIRED_NV	= -1012,
	CL_D3D9_RESOURCE_NOT_ACQUIRED_NV		= -1013,

// cl_d3d9_device_source_nv
	CL_D3D9_DEVICE_NV					= 0x4022,
	CL_D3D9_ADAPTER_NAME_NV				= 0x4023,

// cl_d3d9_device_set_nv
	CL_PREFERRED_DEVICES_FOR_D3D9_NV	= 0x4024,
	CL_ALL_DEVICES_FOR_D3D9_NV			= 0x4025,

// cl_context_info
	CL_CONTEXT_D3D9_DEVICE_NV			= 0x4026,

// cl_mem_info
	CL_MEM_D3D9_RESOURCE_NV				= 0x4027,

// cl_image_info
	CL_IMAGE_D3D9_FACE_NV				= 0x4028,
	CL_IMAGE_D3D9_LEVEL_NV				= 0x4029,

// cl_command_type
	CL_COMMAND_ACQUIRE_D3D9_OBJECTS_NV	= 0x402A,
	CL_COMMAND_RELEASE_D3D9_OBJECTS_NV	= 0x402B,
}

/******************************************************************************/

typedef extern(System) cl_int function(
	cl_platform_id				platform,
	cl_d3d9_device_source_nv	d3d_device_source,
	void*						d3d_object,
	cl_d3d9_device_set_nv		d3d_device_set,
	cl_uint						num_entries, 
	cl_device_id*				devices, 
	cl_uint*					num_devices) clGetDeviceIDsFromD3D9NV_fn;

typedef extern(System) cl_mem function(
	cl_context				context,
	cl_mem_flags			 flags,
	IDirect3DVertexBuffer9*	resource,
	cl_int*					 errcode_ret) clCreateFromD3D9VertexBufferNV_fn;

typedef extern(System) cl_mem function(
	cl_context				context,
	cl_mem_flags			flags,
	IDirect3DIndexBuffer9*	resource,
	cl_int*					errcode_ret) clCreateFromD3D9IndexBufferNV_fn;

typedef extern(System) cl_mem function(
	cl_context			context,
	cl_mem_flags		flags,
	IDirect3DSurface9*	resource,
	cl_int*				errcode_ret) clCreateFromD3D9SurfaceNV_fn;

typedef extern(System) cl_mem function(
	cl_context		 	context,
	cl_mem_flags		flags,
	IDirect3DTexture9*	resource,
	uint				miplevel,
	cl_int*				errcode_ret) clCreateFromD3D9TextureNV_fn;

typedef extern(System) cl_mem function(
	cl_context				context,
	cl_mem_flags			flags,
	IDirect3DCubeTexture9*	resource,
	D3DCUBEMAP_FACES		facetype,
	uint					miplevel,
	cl_int*					errcode_ret) clCreateFromD3D9CubeTextureNV_fn;

typedef extern(System) cl_mem function(
	cl_context					context,
	cl_mem_flags				flags,
	IDirect3DVolumeTexture9*	resource,
	uint						miplevel,
	cl_int*						errcode_ret) clCreateFromD3D9VolumeTextureNV_fn;

typedef extern(System) cl_int function(
	cl_command_queue	command_queue,
	cl_uint				num_objects,
	cl_mem*		        mem_objects,
	cl_uint				num_events_in_wait_list,
	cl_event*	        event_wait_list,
	cl_event*			event) clEnqueueAcquireD3D9ObjectsNV_fn;

typedef extern(System) cl_int function(
	cl_command_queue	command_queue,
	cl_uint				num_objects,
	cl_mem*				mem_objects,
	cl_uint				num_events_in_wait_list,
	cl_event*	        event_wait_list,
	cl_event*			event) clEnqueueReleaseD3D9ObjectsNV_fn;

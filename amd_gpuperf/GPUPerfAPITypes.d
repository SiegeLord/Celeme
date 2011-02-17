//=============================================================================
//
// Author: GPU Developer Tools
//         AMD, Inc.
//
// Defines the data types and enumerations used by GPUPerfAPI.
// This file does not need to be directly included by an application
// that uses GPUPerfAPI.
//=============================================================================
// Copyright (c) 2010 Advanced Micro Devices, Inc.  All rights reserved.
//=============================================================================

module amd_gpuperf.GPUPerfAPITypes;

extern (C):

alias byte    gpa_int8;
alias short   gpa_int16;
alias int     gpa_int32;
alias long    gpa_int64;
alias float   gpa_float32;
alias double  gpa_float64;
alias ubyte   gpa_uint8;
alias ushort  gpa_uint16;
alias uint    gpa_uint32;
alias ulong   gpa_uint64;

// Limit definitions
const GPA_INT8_MAX = byte.max;
const GPA_INT16_MAX = short.max;
const GPA_INT32_MAX = int.max;
const GPA_INT64_MAX = long.max;

const GPA_UINT8_MAX = ubyte.max;
const GPA_UINT16_MAX = ushort.max;
const GPA_UINT32_MAX = uint.max;
const GPA_UINT64_MAX = ulong.max;


/// Status enumerations
enum GPA_Status
{
   GPA_STATUS_OK = 0,
   GPA_STATUS_ERROR_NULL_POINTER,
   GPA_STATUS_ERROR_COUNTERS_NOT_OPEN,
   GPA_STATUS_ERROR_COUNTERS_ALREADY_OPEN,
   GPA_STATUS_ERROR_INDEX_OUT_OF_RANGE,
   GPA_STATUS_ERROR_NOT_FOUND,
   GPA_STATUS_ERROR_ALREADY_ENABLED,
   GPA_STATUS_ERROR_NO_COUNTERS_ENABLED,
   GPA_STATUS_ERROR_NOT_ENABLED,
   GPA_STATUS_ERROR_SAMPLING_NOT_STARTED,
   GPA_STATUS_ERROR_SAMPLING_ALREADY_STARTED,
   GPA_STATUS_ERROR_SAMPLING_NOT_ENDED,
   GPA_STATUS_ERROR_NOT_ENOUGH_PASSES,
   GPA_STATUS_ERROR_PASS_NOT_ENDED,
   GPA_STATUS_ERROR_PASS_NOT_STARTED,
   GPA_STATUS_ERROR_PASS_ALREADY_STARTED,
   GPA_STATUS_ERROR_SAMPLE_NOT_STARTED,
   GPA_STATUS_ERROR_SAMPLE_ALREADY_STARTED,
   GPA_STATUS_ERROR_SAMPLE_NOT_ENDED,
   GPA_STATUS_ERROR_CANNOT_CHANGE_COUNTERS_WHEN_SAMPLING,
   GPA_STATUS_ERROR_SESSION_NOT_FOUND,
   GPA_STATUS_ERROR_SAMPLE_NOT_FOUND,
   GPA_STATUS_ERROR_SAMPLE_NOT_FOUND_IN_ALL_PASSES,
   GPA_STATUS_ERROR_COUNTER_NOT_OF_SPECIFIED_TYPE,
   GPA_STATUS_ERROR_READING_COUNTER_RESULT,
   GPA_STATUS_ERROR_VARIABLE_NUMBER_OF_SAMPLES_IN_PASSES,
   GPA_STATUS_ERROR_FAILED,
   GPA_STATUS_ERROR_HARDWARE_NOT_SUPPORTED,
}


/// Value type definitions
enum GPA_Type
{
   GPA_TYPE_FLOAT32,             ///< Result will be a 32-bit float
   GPA_TYPE_FLOAT64,             ///< Result will be a 64-bit float
   GPA_TYPE_UINT32,              ///< Result will be a 32-bit unsigned int
   GPA_TYPE_UINT64,              ///< Result will be a 64-bit unsigned int
   GPA_TYPE_INT32,               ///< Result will be a 32-bit int
   GPA_TYPE_INT64,               ///< Result will be a 64-bit int
   GPA_TYPE__LAST                ///< Marker indicating last element
}

/// Result usage type definitions
enum GPA_Usage_Type
{
   GPA_USAGE_TYPE_RATIO,         ///< Result is a ratio of two different values or types
   GPA_USAGE_TYPE_PERCENTAGE,    ///< Result is a percentage, typically within [0,100] range, but may be higher for certain counters
   GPA_USAGE_TYPE_CYCLES,        ///< Result is in clock cycles
   GPA_USAGE_TYPE_MILLISECONDS,  ///< Result is in milliseconds
   GPA_USAGE_TYPE_BYTES,         ///< Result is in bytes
   GPA_USAGE_TYPE_ITEMS,         ///< Result is a count of items or objects (ie, vertices, triangles, threads, pixels, texels, etc)
   GPA_USAGE_TYPE_KILOBYTES,     ///< Result is in kilobytes
   GPA_USAGE_TYPE__LAST          ///< Marker indicating last element
}

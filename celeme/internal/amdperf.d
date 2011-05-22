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

module celeme.internal.amdperf;

version (AMDPerf):

import amd_gpuperf.GPUPerfAPI;

public import amd_gpuperf.GPUPerfAPITypes;

import tango.text.convert.Integer;
import tango.stdc.stringz;
import tango.text.convert.Format;

void GPA_Check(GPA_Status status)
{
	assert(status == GPA_Status.GPA_STATUS_OK, toString(status));
}

void Initialize()
{
	GPA_Check(GPA_Initialize());
}

void Destroy()
{
	GPA_Check(GPA_Destroy());
}

void OpenContext(void* context)
{
	GPA_Check(GPA_OpenContext(context));
}

void CloseContext()
{
	GPA_Check(GPA_CloseContext());
}

void EnableCounters(int max_passes, char[][] counters...)
{
	foreach(counter; counters)
	{
		GPA_Check(GPA_EnableCounterStr(toStringz(counter)));
		gpa_uint32 passes;
		GPA_Check(GPA_GetPassCount(&passes));
		if(passes > max_passes)
		{
			GPA_Check(GPA_DisableCounterStr(toStringz(counter)));
			return;
		}
	}
}

void DisableCounters(char[][] counters...)
{
	foreach(counter; counters)
	{
		GPA_Check(GPA_DisableCounterStr(toStringz(counter)));
	}
}

private gpa_uint32 SessionId;

gpa_uint32 BeginSP()
{
	GPA_Check(GPA_BeginSession(&SessionId));
	GPA_Check(GPA_BeginPass());
	
	return SessionId;
}

void EndSP()
{
	GPA_Check(GPA_EndPass());
	GPA_Check(GPA_EndSession());
}

private gpa_uint32[char[]] Samples;
gpa_uint32 LastSample;

void BeginSample(char[] name)
{
	gpa_uint32 id = LastSample;
	auto id_ptr = name in Samples;
	if(id_ptr !is null)
	{
		id = *id_ptr;
	}
	else
	{
		Samples[name] = id;
		LastSample++;
	}
	GPA_Check(GPA_BeginSample(id));
}

void EndSample()
{
	GPA_Check(GPA_EndSample());
}

char[] GetSessionData(gpa_uint32 session_id)
{
	char[] ret;
	
	gpa_uint32 num_counters;
	GPA_GetEnabledCount(&num_counters);

	foreach(sample_name, sample_id; Samples)
	{
		ret ~= sample_name ~ ":\n";
		for(int ii = 0; ii < num_counters; ii++)
		{
			gpa_uint32 enabled_counter_id;
			GPA_Type type;
			char* name;
			
			GPA_GetEnabledIndex(ii, &enabled_counter_id);
			GPA_GetCounterDataType(enabled_counter_id, &type);
			GPA_GetCounterName(enabled_counter_id, &name);
			
			with(GPA_Type)
			switch(type)
			{
				case GPA_TYPE_UINT32:
				{
					gpa_uint32 value;
					GPA_GetSampleUInt32(session_id, sample_id, enabled_counter_id, &value );
					ret ~= Format("{}: {}\n", fromStringz(name), value);
					break;
				}
				case GPA_TYPE_UINT64:
				{
					gpa_uint64 value;
					GPA_GetSampleUInt64(session_id, sample_id, enabled_counter_id, &value );
					ret ~= Format("{}: {}\n", fromStringz(name), value);
					break;
				}
				case GPA_TYPE_FLOAT32:
				{
					gpa_float32 value;
					GPA_GetSampleFloat32(session_id, sample_id, enabled_counter_id, &value );
					ret ~= Format("{}: {}\n", fromStringz(name), value);
					break;
				}
				case GPA_TYPE_FLOAT64:
				{
					gpa_float64 value;
					GPA_GetSampleFloat64(session_id, sample_id, enabled_counter_id, &value );
					ret ~= Format("{}: {}\n", fromStringz(name), value);
					break;
				}
			}
		}
	}
	
	return ret;
}

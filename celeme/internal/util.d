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

module celeme.internal.util;

import tango.core.Array;
import tango.sys.Process;
import tango.io.stream.Text;
import tango.io.Stdout;
import tango.stdc.stringz;
public import dutil.General;

alias const(char)[] cstring;

bool c_allowed_char(char c)
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

size_t c_find(cstring text, cstring pattern)
{
	cstring rem = text;
	size_t start;
	auto L = pattern.length;
	while((start = rem.find(pattern)) != rem.length)
	{
		if((start > 0 && c_allowed_char(rem[start - 1]))
		     || (start + L < rem.length - 1 && c_allowed_char(rem[start + L])))
		{
			rem = rem[start + L .. $];
		}
		else
		{
			return start + text.length - rem.length;
		}
	}
	return text.length;
}

unittest
{
	cstring a = "abeta beta gamma zeta";
	
	assert(a.c_find("beta") == 6);
	assert(a.c_find("abeta") == 0);
	assert(a.c_find("sda") == a.length);
}

/*
 * Like substitute, but using proper delimeters
 */
char[] c_substitute(cstring text, cstring pattern, cstring what)
{
	char[] ret;
	cstring rem = text;
	size_t start;
	auto L = pattern.length;
	while((start = rem.find(pattern)) != rem.length)
	{
		if((start > 0 && c_allowed_char(rem[start - 1]))
		     || (start + L < rem.length - 1 && c_allowed_char(rem[start + L])))
		{
			ret ~= rem[0..start] ~ pattern;
		}
		else
		{
			ret ~= rem[0..start] ~ what;
		}
		rem = rem[start + L .. $];
	}
	ret ~= rem;
	return ret;
}

unittest
{
	char[] a = "Alpha beta gamma zeta".dup;
	
	a = a.c_substitute("Alpha", "Kappa");
	assert(a == "Kappa beta gamma zeta", a);
	
	a = a.c_substitute("eta", "gddd");
	assert(a == "Kappa beta gamma zeta", a);
	
	a = a.c_substitute("gam", "gddd");
	assert(a == "Kappa beta gamma zeta", a);
	
	a = a.c_substitute("gam", "gddd");
	assert(a == "Kappa beta gamma zeta", a);
	
	a = a.c_substitute("zeta", "eta");
	assert(a == "Kappa beta gamma eta", a);
	
	a = a.c_substitute("eta", "gddd");
	assert(a == "Kappa beta gamma gddd", a);
}

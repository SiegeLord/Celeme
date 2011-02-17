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

module celeme.util;

import tango.core.Array;
import tango.sys.Process;
import tango.io.stream.Text;
import tango.io.Stdout;
import tango.stdc.stringz;

private char[] c_str_buf;
char* c_str(char[] dstr)
{
	if(dstr.length >= c_str_buf.length)
		c_str_buf.length = dstr.length + 1;
	return toStringz(dstr, c_str_buf);
}

void println(T...)(char[] fmt, T args)
{
	Stdout.formatln(fmt, args);
}

/*
 * Like substitute, but using proper delimeters
 */
char[] c_substitute(char[] text, char[] pattern, char[] what)
{
	bool allowed_char(char c)
	{
		return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
	}
	
	char[] ret;
	char[] rem = text;
	int start;
	auto L = pattern.length;
	while((start = rem.find(pattern)) != rem.length)
	{
		if((start > 0 && allowed_char(rem[start - 1]))
		     || (start + L < rem.length - 1 && allowed_char(rem[start + L])))
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

T[] deep_dup(T)(T[] arr)
{
	T[] ret;
	ret.length = arr.length;
	foreach(ii, el; arr)
		ret[ii] = el.dup;
	return ret;
}

range_fruct!(T) range(T)(T end)
{
	range_fruct!(T) ret;
	ret.end = end;
	return ret;
}

range_fruct!(T) range(T)(T start, T end)
{
	range_fruct!(T) ret;
	ret.start = start;
	ret.end = end;
	return ret;
}

range_fruct!(T) range(T)(T start, T end, T step)
{
	range_fruct!(T) ret;
	ret.start = start;
	ret.end = end;
	ret.step = step;
	return ret;
}

struct range_fruct(T)
{	
	int opApply(int delegate(ref T ii) dg)
	{
		for(int ii = start; ii < end; ii += step)
		{
			if(int ret = dg(ii))
				return ret;
		}
		return 0;
	}
	
	T start = 0;
	T end = 0;
	T step = 1;
}

char[] GetGitRevisionHash()
{
	char[] ret;
	try
	{
		auto git = new Process(true, "git rev-parse HEAD");
		git.execute();
		auto input = new TextInput(git.stdout);
		input.readln(ret);
		git.wait();
	}
	catch(Exception e)
	{
		Stdout(e).nl;
	}
	return ret;
}

char[] Prop(type, char[] name, char[] get_attr = "", char[] set_attr = "")()
{
	return
	get_attr ~ "
	" ~ type.stringof ~ " " ~ name ~ "()
	{
		return " ~ name ~ "Val;
	}
	
	" ~ set_attr ~ "
	void " ~ name ~ "(" ~ type.stringof ~ " val)
	{
		" ~ name ~ "Val = val;
	}";
}

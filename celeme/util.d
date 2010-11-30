module celeme.util;

import tango.core.Array;
import tango.sys.Process;
import tango.io.stream.Text;
import tango.io.Stdout;

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

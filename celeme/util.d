module celeme.util;

import tango.core.Array;
import tango.sys.Process;
import tango.io.stream.Text;
import tango.io.Stdout;

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

char[] GetGitRevisionHash()
{
	char[] ret;
	try
	{
		auto git = new Process(true, "git rev-parse HEAD");
		git.execute();
		Stdout.copy(git.stdin);
		/*auto input = new TextInput(git.stdin);
		//input.flush();
		input.readln(ret);*/
		git.wait();
	}
	catch(Exception e)
	{
		Stdout(e).nl;
	}
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

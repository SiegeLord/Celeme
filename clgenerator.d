module clgenerator;

import frontend;

import tango.io.Stdout;
import tango.core.Array;

char[] StepKernelTemplate = "
__kernel void $type_name$_step
	(
$state_args$
		__global $num_type$* dt_buf,
		const $num_type$ t,
		const int count
	)
{
	int i = get_global_id(0);
	if(i < count)
	{
		$num_type$ dt = dt_buf[i];
$load_states$

		while(cur_time < timestep)
		{
			$num_type$ error = 0;
			
			cur_time += dt;
			
			dt *= 0.8f * .46415888f * rootn(error + 0.00001f, -6);
			
			if(cur_time < timestep && cur_time + dt >= timestep)
			{
				dt = timestep - cur_time + 0.0001f;
			}
		}
		
		dt_buf[i] = dt;
$save_states$
	}
}
";

void replace(ref char[] text, char[] pattern, char[] what)
{
	char[] ret;
	char[] rem = text;
	int start;
	while((start = rem.find(pattern)) != rem.length)
	{
		ret ~= rem[0..start] ~ what;
		rem = rem[start + pattern.length .. $];
	}
	ret ~= rem;
	text = ret;
}

class CSource
{
	void Add(char[] text)
	{
		Source ~= text;
	}
	void AddLine(char[] line)
	{
		auto tabs = "\t\t\t\t\t\t\t\t\t\t";
		Source ~= tabs[0..TabLevel] ~ line ~ "\n";
	}
	
	alias AddLine opCatAssign;
	
	void EmptyLine()
	{
		Source ~= "\n";
	}
	
	void Clear()
	{
		TabLevel = 0;
		Source.length = 0;
	}
	
	void Tab(int num = 1)
	{
		TabLevel += num;
		assert(TabLevel < 10, "TabLevel has to be less than 10");
	}
	
	void DeTab(int num = 1)
	{
		TabLevel -= num;
		assert(TabLevel >= 0, "TabLevel cannot be less than 0");
	}
	
	void Retreat(int num)
	{
		assert(Source.length - num >= 0, "Can't retreat past start!");
		Source = Source[0..$-num];
	}
	
	char[] toString()
	{
		return Source;
	}
	
	int TabLevel = 0;
	char[] Source;
}

class CModel
{	
	void AddNeuronGroup(CNeuronType type, int number)
	{
		type.VerifyExternals();
		
		SNeuronGroup group;
		group.Type = type;
		group.Count = number;
		group.InitCompiledNames();
		
		NeuronGroups ~= group;
	}
	
	struct SNeuronGroup
	{
		char[][char[]] CompiledNames;
		CNeuronType Type;
		int Count;
		
		void InitCompiledNames()
		{
			foreach(name, _; Type.Values)
			{
				CompiledNames[name] = name.dup;
			}
		}
	}
	
	void Generate()
	{
		/* Generate the step function */
		auto source = new CSource;
		foreach(group; NeuronGroups)
		{
			auto kernel_source = StepKernelTemplate.dup;
			
			auto type = group.Type;
			
			kernel_source.replace("$type_name$", type.Name);
			
			source.Tab(2);
			foreach(state; &type.AllStates)
			{
				source ~= "__global $num_type$* " ~ group.CompiledNames[state.Name] ~ "_buf,";
			}
			source.Retreat(1); /* Chomp the newline */
			kernel_source.replace("$state_args$", source.toString);
			source.Clear();
			
			source.Tab(2);
			foreach(state; &type.AllStates)
			{
				auto name = group.CompiledNames[state.Name];
				source ~= "$num_type$ " ~ name ~ " = " ~ name ~ "_buf[i];";
			}
			source.Retreat(1); /* Chomp the newline */
			kernel_source.replace("$load_states$", source.toString);
			source.Clear();
			
			source.Tab(2);
			foreach(state; &type.AllStates)
			{
				auto name = group.CompiledNames[state.Name];
				source ~= name ~ "_buf[i] = " ~ name ~ ";";
			}
			source.Retreat(1); /* Chomp the newline */
			kernel_source.replace("$save_states$", source.toString);
			source.Clear();
			
			kernel_source.replace("$num_type$", NumType);
			Source ~= kernel_source;
		}
		Stdout(Source).nl;
	}
	
	char[] NumType = "float";
	SNeuronGroup[] NeuronGroups;
	char[] Source;
}

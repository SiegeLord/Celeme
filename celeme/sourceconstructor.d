module celeme.sourceconstructor;

import tango.text.Util;

class CSourceConstructor
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
	
	void AddBlock(char[] block)
	{
		foreach(line; lines(block))
		{
			AddLine(line);
		}
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

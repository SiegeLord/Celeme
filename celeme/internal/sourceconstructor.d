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

module celeme.internal.sourceconstructor;

import celeme.internal.util;

import tango.text.Util;
import tango.util.Convert;

class CCode
{
	this(cstring src = "")
	{
		Source = src.dup;
	}
	
	void opAssign(cstring src)
	{
		Source = src.dup;
	}
	
	cstring opSlice()
	{
		return Source;
	}
	
	void opIndexAssign(T)(T val, cstring what)
	{
		Source = Source.substitute(what, to!(char[])(val));
	}
	
	struct CAccess
	{
		void opIndexAssign(T)(T val, cstring what)
		{
			Source = Source.c_substitute(what, to!(char[])(val));
		}
		
		char[] Source;
	}
	
	CAccess C()
	{
		return CAccess(Source);
	}
	
	char[] Source;
}

class CSourceConstructor
{
	void Add(cstring text)
	{
		Source ~= text;
	}
	
	void AddLine(cstring line)
	{
		auto tabs = "\t\t\t\t\t\t\t\t\t\t";
		Source ~= tabs[0..TabLevel] ~ line ~ "\n";
	}
	
	void AddLine(CCode code)
	{
		AddLine(code[]);
	}
	
	void AddBlock(cstring block)
	{
		foreach(line; lines(block))
		{
			AddLine(line);
		}
	}
	
	void AddBlock(CCode code)
	{
		AddBlock(code[]);
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
	
	override
	immutable(char)[] toString()
	{
		return Source.idup;
	}
	
	void Inject(ref cstring dest_string, cstring label)
	{
		/* Chomp the newline */
		if(Source.length)
			Retreat(1);
			
		dest_string = dest_string.substitute(label, Source);
		Clear();
	}
	
	void Inject(CCode code, cstring label)
	{
		Inject(code.Source, label);
	}
	
	int TabLevel = 0;
	char[] Source;
}

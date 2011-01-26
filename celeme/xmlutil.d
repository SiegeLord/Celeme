/*
This file is part of Celeme, an Open Source OpenCL neural simulator.
Copyright (C) 2010-2011 Pavel Sountsov

Celeme is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Celeme is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Celeme. If not, see <http:#www.gnu.org/licenses/>.
*/

module celeme.xmlutil;

import tango.text.xml.Document;
import tango.io.device.File;

import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;

alias Document!(char).Node Node;

Node GetRoot(char[] filename)
{
	auto content = cast(char[])File.get(filename);
	auto doc = new Document!(char);
	doc.parse(content);
	
	return doc.tree;
}

T GetAttribute(T)(Node node, char[] name, T def = T.init, bool* is_def = null)
{
	if(is_def !is null)
		*is_def = false;
	
	auto res = node.query.attribute(name);
	if(res.count)
	{
		auto value = res.nodes[0].value;
		static if(is(T == char[]))
			return value;
		static if(is(T == double) || is(T == float))
		{
			uint len;
			T ret = cast(T)Float.parse(value, &len);
			if(len)
				return ret;
		}
		static if(is(T == int) || is(T == long) || is(T == ulong) || is(T == uint))
		{
			uint len;
			T ret = cast(T)Integer.parse(value, 0, &len);
			
			if(len)
				return ret;
		}
		static if(is(T == bool))
		{
			if(value == "true")
				return true;
			else if(value == "false")
				return false;
		}
	}
	
	if(is_def !is null)
		*is_def = true;

	return def;
}

XmlPath!(char).NodeSet GetChildren(Node node, char[] name)
{
	return node.query.child(name).dup;
}

Node GetChild(Node node, char[] name)
{
	auto set = GetChildren(node, name);
	if(set.count())
	{
		return set.nodes[0];
	}
	return null;
}

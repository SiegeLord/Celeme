/**
 * This module provides support for a simple configuration file format
 * with D-like syntax. Both C++ and C comments are supported with
 * the added enhancement that C comments are now nesting. The configuration file
 * is composed of entries. Each entry has a name. The names need not be unique,
 * and it is up to the application what to do with multiple entries (it could even
 * dissallow them if need be). There are two types of entries, single value entries 
 * and aggregate entries. Single value entries can either be empty or hold one value:
 * 
 * ---
 * sentinel; // This one does not hold any value
 * size = 5;
 * mass = 1.2;
 * length = 1.3e-5;
 * name = "Test";
 * some_code = `printf("%d")`;
 * ---
 * 
 * Values can be integers, floating point literals and strings.
 * Strings can either be delimeted by the " character, or the ` character.
 * The former are escaped strings, while the latter are WYSIWYG strings,
 * useful for embedding code.
 * 
 * Aggregate entries contain children entries:
 * 
 * ---
 * address
 * {
 *    street = "Quiet St.";
 *    number = 125;
 * }
 * ---
 * 
 * An alternate syntax can be used if the aggregate only has a single entry:
 * 
 * ---
 * animal dog;
 * 
 * animal
 * {
 *    dog;
 * }
 * ---
 * 
 * The above two animal entries are identical. Naturally, aggregate entries can
 * be nested:
 * 
 * ---
 * animal dog Spotty;
 * object
 * {
 *    children
 *    {
 *        Amy;
 *    }
 * }
 * ---
 * 
 * Lastly, this file format supports textual includes:
 * 
 * ---
 * include "some_other_file"
 * ---
 * 
 * This will effectively paste the contents of the other file inside this file.
 * Circular includes are forbidden. Some example usage:
 * 
 * ---
 * char[] file = 
 * `
 * value = 5;
 * value = 7;
 * container
 * {
 *     contents = "Hello";
 * }
 * `;
 * 
 * auto root = LoadConfig("", file);
 * 
 * // Get all entries named "value"
 * foreach(entry; root["value"])
 *    Stdout(entry.Value!(int)).nl; // Will print 5 and then 7
 * 
 * // Get only the last value
 * auto last_value = root["value", true];
 * Stdout(last_value.Value!(int)).nl; // Will print 7
 * 
 * // A shortcut for the above
 * Stdout(root.ValueOf!(int)("value")).nl; // Will print 7
 * 
 * // Providing a default value
 * Stdout(root.ValueOf!(int)("not_there", -1)).nl; // Will print -1
 * 
 * auto container = root["container", true];
 * if(container.IsAggregateEntry)
 * {
 *    //Loop through all the contents of the container
 *    foreach(entry; container)
 *        Stdout(entry.Name, entry.Value!(char[])).nl; // Will print contents, Hello
 * }
 * ---
 */

module celeme.config;

import TextUtil = tango.text.Util;
import Array = tango.core.Array;
import Float = tango.text.convert.Float;
import Integer = tango.text.convert.Integer;
import tango.core.Variant;
import tango.text.convert.Format;
import tango.io.device.File;
import tango.text.json.JsonEscape;

import tango.io.Stdout;

/**
 * Create a configuration entry from a file or a string.
 * 
 * Params:
 *     filename = Name of the file to load if no source is provided.
 *     src = If set, must contain the source to load from.
 * 
 * Returns:
 *     An entry representing the top-level entry of the configuration file.
 */
CConfigEntry LoadConfig(char[] filename, char[] src = null)
{
	auto ret = new CAggregate("");
	
	LoadConfig(ret, filename, src);
	
	return ret;
}

/**
 * A configuration entry, which represents a single node in the configuration file.
 * 
 * An entry can both be a single entry (e.g. "entry = data;" or "entry;") or an aggregate
 * (e.g. "entry { data; }" or "entry data;").
 */
class CConfigEntry
{
	this(char[] name)
	{
		Name = name;
	}
	
	/**
	 * Get the value of this entry
	 * 
	 * Params:
	 *     def = Default value returned if some error occured.
	 *     is_def = Pointer to a bool that is set to true if the default value is returned.
	 *              Set to false otherwise.
	 * 
	 * Returns: The value of this entry. If the value is not set, or the
	 * entry is an aggregate, then the default value is returned, and the
	 * is_def argument is set to true (if it is not null).
	 */
	T Value(T)(T def = T.init, bool* is_def = null)
	{
		if(is_def !is null)
			*is_def = false;
			
		auto val = cast(CSingleValue)this;
		if(val !is null)
		{
			if(val.Val.isImplicitly!(T))
			{
				return val.Val.get!(T);
			}
		}
			
		if(is_def !is null)
			*is_def = true;
			
		return def;
	}
	
	/**
	 * Shortcut for accessing a single child entry of this aggregate and returning its value.
	 * 
	 * Params:
	 *     name = Name of the child entry.
	 *     def = Default value returned if some error occured.
	 *     is_def = Pointer to a bool that is set to true if the default value is returned.
	 *              Set to false otherwise.
	 * 
	 * Returns: The value of this entry. If the value is not set, or the
	 * entry is an aggregate, then the default value is returned, and the
	 * is_def argument is set to true (if it is not null).
	 * 
	 * See_Also: $(SYMLINK CConfigEntry.Value, Value)
	 */
	T ValueOf(T)(char[] name, T def = T.init, bool* is_def = null)
	{
		if(is_def !is null)
			*is_def = false;

		auto ret = opIndex(name, true);
		
		if(ret !is null)
			return ret.Value!(T)(def, is_def);
		
		if(is_def !is null)
			*is_def = true;
			
		return def;
	}
	
	/**
	 * Get an array of entries that match the provided name.
	 * 
	 * Params:
	 *     name = Name to match.
	 * 
	 * Returns: An array of entries if some were found. null otherwise.
	 */
	CConfigEntry[] opIndex(char[] name)
	{
		auto aggr = cast(CAggregate)this;
		if(aggr !is null)
			return aggr.opIndex(name);
		return null;
	}
	
	/**
	 * Get the last entries that matches the provided name.
	 * 
	 * Params:
	 *     name = Name to match.
	 * 
	 * Returns: The found entry. null otherwise.
	 */
	CConfigEntry opIndex(char[] name, bool last)
	{
		auto aggr = cast(CAggregate)this;
		if(aggr !is null)
		{
			auto arr = aggr.opIndex(name);
			if(arr !is null)
				return arr[$ - 1];
		}
		return null;
	}
	
	struct SEntryFruct
	{
		CAggregate Aggregate;
		
		int opApply(int delegate(ref CConfigEntry entry) dg)
		{
			if(Aggregate is null)
				return 0;

			foreach(entries; Aggregate.Children)
			{
				foreach(entry; entries)
				{
					if(int ret = dg(entry))
						return ret;
				}
			}
			
			return 0;
		}
	}
	
	/**
	 * Returns an iterable fruct that goes over all children of this node.
	 */
	SEntryFruct opSlice()
	{
		return SEntryFruct(cast(CAggregate)this);
	}
	
	/**
	 * Returns true if this entry is an aggregate.
	 */
	bool IsAggregate()
	{
		return cast(CAggregate)this !is null;
	}
	
	/**
	 * Returns true if this entry is a single value.
	 */
	bool IsSingleValue()
	{
		return cast(CSingleValue)this !is null;
	}
	
	/**
	 * Name of this entry.
	 */
	char[] Name;
}

private:

enum EToken
{
	Name,
	String,
	SemiColon,
	Integer,
	Double,
	Boolean,
	Assign,
	LeftBrace,
	RightBrace,
	EOF
}

struct SToken
{
	char[] String;
	int Line;
	int Type;
}

class CConfigException : Exception
{
	this(char[] msg, char[] filename, int line)
	{
		super(Format("{}({}): {}", filename, line, msg));
	}
}

class CTokenizer
{
	this(char[] filename, char[] src)
	{
		FileName = filename;
		Source = src;
		CurLine = 1;
	}
	
	bool IsDigit(char c)
	{
		return c >= '0' && c <= '9';
	}
	
	bool IsDigitStart(char c)
	{
		return IsDigit(c) || c == '+' || c == '-';
	}
	
	bool IsNameStart(char c)
	{
		return 
			(c >= 'a' && c <= 'z') 
			|| (c >= 'A' && c <= 'Z')
			|| (c == '_');
	}
	
	bool IsName(char c)
	{
		return IsNameStart(c) || IsDigit(c);
	}
	
	char[] ConsumeComment(char[] src)
	{
		if(src.length < 2)
			return src;
		
		if(src[0] == '/')
		{
			if(src[1] == '/')
			{
				//TODO: Windows type newlines
				auto end = Array.find(src, '\n');
				
				if(end != src.length)
					CurLine++;
					
				return src[end + 1..$];
			}
			else if(src[1] == '*')
			{
				/*
				 * These comments are nesting
				 */
				size_t comment_num = 1;
				size_t comment_end = 2;
				
				size_t lines_passed = 0;
				
				do
				{
					auto old_end = comment_end;
					
					comment_end = TextUtil.locatePattern(src, "*/", old_end);
					if(comment_end == src.length)
						throw new CConfigException("Unexpected EOF when parsing a multiline comment", FileName, CurLine);
					
					comment_end += 2; //Past the ending * /
					comment_num -= 1; //Closed one
					
					comment_num += TextUtil.count(src[old_end..comment_end], "/*");
					
					//TODO: Windows type newlines
					lines_passed += TextUtil.count(src[old_end..comment_end], "\n");
				} while(comment_num > 0)
				
				CurLine += lines_passed;
			
				return src[comment_end..$];
			}
		}
		return src;
	}
	
	/*
	 * Trims leading whitespace while counting newlines
	 */
	char[] Trim(char[] source)
	{
		char* head = source.ptr,
		tail = head + source.length;

		while(head < tail && TextUtil.isSpace(*head))
		{
			//TODO: Windows type newlines
			if(*head == '\n')
				CurLine++;
			++head;
		}

		return head[0..tail - head];
	}
	
	bool ConsumeString(char[] src, ref size_t end)
	{
		if(src[0] == '"' || src[0] == '`')
		{
			auto quote = src[0];
			int idx = 1;
			int line = CurLine;
			while(true)
			{
				if(idx == src.length)
					throw new CConfigException("Unexpected EOF when parsing a string", FileName, CurLine);
				else if(src[idx] == quote && src[idx - 1] != '\\')
					break;
				//TODO: Windows type newlines
				else if(src[idx] == '\n')
					line++;
					
				idx++;
			}
			
			end = idx + 1;
			CurLine = line;
				
			return true;
		}
		return false;
	}
	
	bool ConsumeBoolean(char[] src, ref size_t end)
	{
		end = Array.find(src, "true") + 4;
		if(end == 4)
			return true;
		end = Array.find(src, "false") + 5;
		if(end == 5)
			return true;
		return false;
	}
	
	bool ConsumeName(char[] src, ref size_t end)
	{
		if(IsNameStart(src[0]))
		{
			end = Array.findIf(src, (char c) {return !IsName(c);});
			return true;
		}
		return false;
	}
	
	bool ConsumeChar(char[] src, char c, ref size_t end)
	{
		if(src[0] == c)
		{
			end = 1;
			return true;
		}
		return false;
	}
	
	bool ConsumeInteger(char[] src, ref size_t end)
	{
		if(IsDigitStart(src[0]))
		{
			if(!IsDigit(src[0]) && (src.length < 2 || !IsDigit(src[1])))
				return false;

			auto cur_end = Array.findIf(src[1..$], (char c) {return !IsDigit(c);}) + 1;
			if(src[cur_end] == '.' || src[cur_end] == 'e' || src[cur_end] == 'E')
				return false;
				
			end = cur_end;
			return true;
		}
		return false;
	}
	
	bool ConsumeDouble(char[] src, ref size_t end)
	{
		if(IsDigitStart(src[0]))
		{
			if(!IsDigit(src[0]) && (src.length < 2 || !IsDigit(src[1])))
				return false;

			auto cur_end = Array.findIf(src[1..$], (char c) {return !IsDigit(c);}) + 1;
			switch(src[cur_end])
			{
				case '.':
				{
					if(cur_end == src.length - 1 || !IsDigit(src[cur_end + 1]))
						return false;
					
					cur_end += Array.findIf(src[cur_end + 1..$], (char c) {return !IsDigit(c);}) + 1;
					if(src[cur_end] != 'e' && src[cur_end] != 'E')
						break;
				}
				case 'e':
				case 'E':
				{
					if(cur_end == src.length - 1)
						return false;
						
					size_t exp_end;
					if(!ConsumeInteger(src[cur_end + 1..$], exp_end))
						return false;
					cur_end += exp_end + 1;
					
					break;
				}
				default:
					return false;
			}
				
			end = cur_end;
			return true;
		}
		return false;
		return false;
	}
	
	SToken Next()
	{
		SToken tok;
		
		/*
		 * Consume non-tokens
		 */
		bool changed = false;
		while(!changed)
		{
			Source = Trim(Source);
			
			auto old_len = Source.length;
			Source = ConsumeComment(Source);
			changed = old_len == Source.length;
		}
		
		/*
		 * Try interpreting a token
		 */
		if(Source.length > 0)
		{			
			size_t end = -1;

			if(ConsumeInteger(Source, end))
				tok.Type = EToken.Integer;
			else if(ConsumeDouble(Source, end))
				tok.Type = EToken.Double;
			else if(ConsumeString(Source, end))
				tok.Type = EToken.String;
			else if(ConsumeBoolean(Source, end))
				tok.Type = EToken.Boolean;
			else if(ConsumeName(Source, end))
				tok.Type = EToken.Name;
			else if(ConsumeChar(Source, ';', end))
				tok.Type = EToken.SemiColon;
			else if(ConsumeChar(Source, '=', end))
				tok.Type = EToken.Assign;
			else if(ConsumeChar(Source, '{', end))
				tok.Type = EToken.LeftBrace;
			else if(ConsumeChar(Source, '}', end))
				tok.Type = EToken.RightBrace;
			else
				throw new CConfigException("Invalid token! '" ~ Source[0] ~ "'", FileName, CurLine);
			
			tok.String = Source[0..end];
			tok.Line = CurLine;
			Source = Source[end..$];
		}
		else
		{
			tok.Type = EToken.EOF;
		}
		return tok;
	}
	
	char[] FileName;
	int CurLine;
	char[] Source;
}

class CParser
{
	this(CTokenizer tokenizer)
	{
		Tokenizer = tokenizer;
		NextToken = Tokenizer.Next();
		Advance();
	}
	
	bool EOF()
	{
		return CurToken.Type == EToken.EOF;
	}
	
	int Advance()
	{
		CurToken = NextToken;
		NextToken = Tokenizer.Next();
		CurLine = CurToken.Line;
		return Peek;
	}
	
	int Peek()
	{
		return CurToken.Type;
	}
	
	int PeekNext()
	{
		return NextToken.Type;
	}
	
	char[] FileName()
	{
		return Tokenizer.FileName;
	}
	
	SToken CurToken;
	SToken NextToken;
	int CurLine;
	CTokenizer Tokenizer;
}



class CAggregate : CConfigEntry
{
	this(char[] name)
	{
		super(name);
	}
	
	alias CConfigEntry.opIndex opIndex;
	
	CConfigEntry[] opIndex(char[] name)
	{
		auto entry_ptr = name in Children;
		if(entry_ptr !is null)
			return *entry_ptr;
		else
			return null;
	}
	
	CConfigEntry[][char[]] Children;
}

class CSingleValue : CConfigEntry
{
	this(char[] name)
	{
		super(name);
	}
	
	void opAssign(T)(T val)
	{
		Val = val;
	}
	
	Variant Val;
}

CConfigEntry CreateEntry(CParser parser)
{
	if(parser.Peek == EToken.Name)
	{
		CConfigEntry ret;
		auto name = parser.CurToken.String;
		if(name == "include")
			throw new CConfigException("'include' is only allowed at the top level.", parser.FileName, parser.CurToken.Line);
		
		switch(parser.Advance())
		{
			case EToken.Assign:
			{
				auto sval = new CSingleValue(name);
				
				switch(parser.Advance())
				{
					case EToken.Boolean:
					{
						sval = parser.CurToken.String == "true";
						break;
					}
					case EToken.Integer:
					{
						uint len;
						auto val = cast(int)Integer.parse(parser.CurToken.String, 0, &len);
						
						if(len)
							sval = val;
						
						break;
					}
					case EToken.Double:
					{
						uint len;
						auto val = cast(double)Float.parse(parser.CurToken.String, &len);
						
						if(len)
							sval = val;
						
						break;
					}
					case EToken.String:
					{
						auto str = parser.CurToken.String;
						if(str[0] == '"')
							str = unescape(str[1..$-1]);
						else
							str = str[1..$-1];
						sval = str;
						break;
					}
					default:
						throw new CConfigException("Expected a value, not: '" ~ parser.CurToken.String ~ "'", parser.FileName, parser.CurToken.Line);
				}
				if(parser.Advance() != EToken.SemiColon)
					throw new CConfigException("Expected a semicolon, found: '" ~ parser.CurToken.String ~ "'", parser.FileName, parser.CurToken.Line);
				
				parser.Advance();
				ret = sval;
				break;
			}
			case EToken.LeftBrace:
			{
				auto line = parser.CurToken.Line;
				parser.Advance();
				
				auto aggr = new CAggregate(name);
				while(parser.Peek != EToken.RightBrace)
				{
					if(parser.Peek == EToken.EOF)
						throw new CConfigException("Unexpected EOF while parsing aggregate", parser.FileName, line);
						
					auto entry = CreateEntry(parser);
					if(entry !is null)
						aggr.Children[entry.Name] ~= entry;
					else
						throw new CConfigException("Unexpected token: '" ~ parser.CurToken.String ~ "'", parser.FileName, parser.CurToken.Line);
				}
				
				parser.Advance();
				ret = aggr;
				break;
			}
			case EToken.Name:
			{
				auto aggr = new CAggregate(name);
				
				auto entry = CreateEntry(parser);
				if(entry !is null)
					aggr.Children[entry.Name] ~= entry;
				else
					throw new CConfigException("Unexpected token: '" ~ parser.CurToken.String ~ "'", parser.FileName, parser.CurToken.Line);
				
				ret = aggr;
				break;
			}
			case EToken.SemiColon:
			{
				parser.Advance();
				ret = new CSingleValue(name);
				
				break;
			}
			default:
				throw new CConfigException("Expected a '{' or a '=', not: '" ~ parser.CurToken.String ~ "'", parser.FileName, parser.CurToken.Line);
		}
		return ret;
	}
	return null;
}

bool HandleInclude(CAggregate root, CParser parser, char[][] include_list)
{
	if(parser.Peek == EToken.Name)
	{
		auto name = parser.CurToken.String;
		if(name == "include")
		{
			if(parser.Advance() != EToken.String)
				throw new CConfigException("Expected a string after the 'include' directive, not : '" ~ parser.CurToken.String ~ "'", parser.FileName, parser.CurToken.Line);
				
			auto path = parser.CurToken.String[1..$-1];
			
			auto old_idx = Array.find(include_list, path);
			if(old_idx != include_list.length)
			{
				auto include_seq = TextUtil.join(include_list[old_idx..$], " -> ");
				include_seq ~= " -> " ~ path;
				throw new CConfigException("Circular include detected:\n" ~ include_seq, parser.FileName, parser.CurToken.Line);
			}
				
			parser.Advance();
			
			LoadConfig(root, path, null, include_list);
			return true;
		}
	}
	return false;
}

void LoadConfig(CAggregate ret, char[] filename, char[] src = null, char[][] include_list = null)
{
	if(src is null)
		src = cast(char[])File.get(filename);
	
	scope tok = new CTokenizer(filename, src);
	scope parser = new CParser(tok);
	
	include_list ~= filename;
	
	while(!parser.EOF)
	{
		if(!HandleInclude(ret, parser, include_list))
		{
			CConfigEntry entry;
			entry = CreateEntry(parser);
			if(entry)
				ret.Children[entry.Name] ~= entry;
			else
				throw new CConfigException("Unexpected token: '" ~ parser.CurToken.String ~ "'", parser.FileName, parser.CurToken.Line);
		}
	}
}
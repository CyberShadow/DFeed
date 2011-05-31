module SummarizeMessage;

import std.stdio;
import std.string;

import Rfc850;

void main()
{
	string s;
	string lines;
	while ((s=readln())!is null)
		if (strip(s) == "")
			break;
		else
			lines ~= s;

	auto m = parseMessage(lines);
	foreach (i, f; m.tupleof)
		writefln("%s: %s", m.tupleof[i].stringof, m.tupleof[i]);
}

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

	writefln("%s", summarizeMessage(lines));
}

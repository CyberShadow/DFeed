/*  Copyright (C) 2011, 2012, 2014, 2015, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module dfeed.progs.unban;

import ae.sys.log;

import std.algorithm.searching;
import std.format;
import std.stdio;
import std.string;

import dfeed.web.web;

void main(string[] args)
{
	string[] logLines;
	void log(string s)
	{
		logLines ~= s;
		writeln(s);
	}

	loadBanList();

	string[][string] parents;
	string[][string] children;
	foreach (key, reason; banned)
	{
		auto p = parseParents(reason);
		parents[key] = p;
		foreach (parent; p)
			children[parent] ~= key;
	}

	string[] queue;
	size_t total;
	void unban(string key, string reason)
	{
		if (key in banned)
		{
			log(format("Unbanning %s (%s)", key, reason));
			banned.remove(key);
			total++;
			queue ~= key;
		}
	}

	foreach (arg; args[1..$])
		unban(arg, "command line");

	while (queue.length)
	{
		auto key = queue[0];
		queue = queue[1..$];
		
		foreach (p; parents.get(key, null))
			unban(p, "Parent of " ~ key);
		foreach (c; children.get(key, null))
			unban(c, "Child of " ~ key);
	}

	writefln("Unbanning a total of %d keys.", total);
	writeln("Type 'yes' to continue");
	if (readln().strip() != "yes")
	{
		writeln("Aborting");
		return;
	}

	auto logFile = fileLogger("Unban");
	foreach (line; logLines)
		logFile(line);
	logFile.close();

	saveBanList();
	writeln("Restart DFeed to apply ban list.");
}

string[] parseParents(string s)
{
	string[] result;
	while ((s = s.findSplit(" (propagated from ")[2]) != null)
	{
		auto p = s.findSplit(")");
		result ~= p[0];
		s = p[2];
	}
	return result;
}

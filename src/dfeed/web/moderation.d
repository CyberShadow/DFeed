/*  Copyright (C) 2011, 2012, 2014, 2015, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.moderation;

import std.array : split, join;
import std.file : exists, read, rename;
import std.stdio : File;

import ae.utils.text : splitAsciiLines;

enum banListFileName = "data/banned.txt";

string[string] banned;

void loadBanList()
{
	if (banListFileName.exists())
		foreach (string line; splitAsciiLines(cast(string)read(banListFileName)))
		{
			auto parts = line.split("\t");
			if (parts.length >= 2)
				banned[parts[0]] = parts[1..$].join("\t");
		}
}

void saveBanList()
{
	const inProgressFileName = banListFileName ~ ".inprogress";
	auto f = File(inProgressFileName, "wb");
	foreach (key, reason; banned)
		f.writefln("%s\t%s", key, reason);
	f.close();
	rename(inProgressFileName, banListFileName);
}

/// Parse parent keys from a propagated ban reason string
string[] parseParents(string s)
{
	import std.algorithm.searching : findSplit;
	string[] result;
	while ((s = s.findSplit(" (propagated from ")[2]) != null)
	{
		auto p = s.findSplit(")");
		result ~= p[0];
		s = p[2];
	}
	return result;
}

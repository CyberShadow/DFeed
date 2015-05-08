/*  Copyright (C) 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module groups;

import std.exception;

struct Config
{
	struct Set
	{
		string name, shortName;
	}
	OrderedMap!(string, Set) sets;

	struct AlsoVia
	{
		string name, url;
	}

	struct Group
	{
		string name, urlName, groupSet, description, postMessage;
		OrderedMap!(string, AlsoVia) alsoVia;
	}
	OrderedMap!(string, Group) groups;
}
immutable Config config;

import ae.utils.aa;
import ae.utils.sini;

shared static this() { config = cast(immutable)loadIni!Config("config/groups.ini"); }

struct GroupSet
{
	Config.Set set;
	alias set this;
	immutable Config.Group[] groups;
}
immutable GroupSet[] groupHierarchy;

shared static this()
{
	import std.algorithm;
	import std.range;

	groupHierarchy =
		config.sets.length.iota
		.map!(setIndex => GroupSet(
			config.sets.values[setIndex],
			config.groups.values.filter!(group => group.groupSet == config.sets.keys[setIndex]).array
		)).array;
}

auto getGroupInfo(string name)
{
	foreach (set; groupHierarchy)
		foreach (ref group; set.groups)
			if (group.name == name)
				return &group;
	return null;
}

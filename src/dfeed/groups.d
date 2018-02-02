/*  Copyright (C) 2015, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.groups;

import std.exception;
import std.string;

struct Config
{
	struct Set
	{
		string name, shortName;
		bool visible = true;
	}
	OrderedMap!(string, Set) sets;

	struct AlsoVia
	{
		string name, url;
	}

	struct Group
	{
		string internalName, publicName, urlName, groupSet, description, postMessage, sinkType, sinkName;
		string[] urlAliases;
		OrderedMap!(string, AlsoVia) alsoVia;
		bool subscriptionRequired = true;
		bool announce;
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

alias GroupInfo = immutable(Config.Group)*;

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

GroupInfo getGroupInfoByField(string field, CaseSensitive cs=CaseSensitive.yes)(string value)
{
	foreach (set; groupHierarchy)
		foreach (ref group; set.groups)
		{
			auto fieldValue = mixin("group." ~ field);
			if (cs ? fieldValue == value : icmp(fieldValue, value) == 0)
				return &group;
		}
	return null;
}

alias getGroupInfo             = getGroupInfoByField!q{internalName};
alias getGroupInfoByUrl        = getGroupInfoByField!q{urlName};
alias getGroupInfoByPublicName = getGroupInfoByField!q{publicName};

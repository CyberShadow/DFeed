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

/// Infer a list template from an example,
/// and allow rendering that template
/// with arbitrary list items.

module dfeed.web.list;

import std.algorithm;
import std.array;
import std.exception;
import std.range;
import std.string;

struct ListTemplate
{
	string listPrefix, listSuffix;
	string[] varPrefix;
	string itemSuffix, itemSeparator;

	string render(in string[][] items)
	{
		return
			listPrefix ~
			items.map!(row =>
				row.length.iota.map!(n =>
					varPrefix[n] ~ row[n]
				).join ~ itemSuffix
			).join(itemSeparator) ~
			listSuffix;
	}
}

ListTemplate inferList(string s, string[][] anchors)
{
	assert(anchors.length > 1 && anchors[0].length > 0, "Insufficient anchors");
	enforce(anchors.all!(row => row.length == anchors[0].length), "Jagged anchor specification array");

	auto anchorStarts = anchors.map!(row => row.map!(anchor => s.indexOf(anchor)                ).array).array;
	auto anchorEnds   = anchors.map!(row => row.map!(anchor => s.indexOf(anchor) + anchor.length).array).array;
	enforce(anchorStarts.joiner.all!(i => i>=0), "An anchor was not found when inferring list");

	ListTemplate result;
	foreach (varIndex; 0..anchors[0].length)
	{
		size_t l = 0;
		auto maxL = varIndex ? anchorStarts[0][varIndex] - anchorEnds[0][varIndex-1] : anchorStarts[0][0];
		while (l < maxL &&
			anchors.length.iota.all!(rowIndex => s[anchorStarts[rowIndex][varIndex]-l-1] ==
			                                     s[anchorStarts[0       ][varIndex]-l-1]))
			l++;
		result.varPrefix ~= s[anchorStarts[0][varIndex]-l .. anchorStarts[0][varIndex]];
	}
	size_t l = 0;
	auto maxSuffixLength = min(s.length - anchorEnds[$-1][$-1], anchorStarts[1][0] - result.varPrefix[0].length - anchorEnds[0][$-1]);
	while (l < maxSuffixLength &&
		anchors.length.iota.all!(rowIndex => s[anchorEnds[rowIndex][$-1]+l] ==
		                                     s[anchorEnds[0       ][$-1]+l]))
		l++;
	result.itemSuffix = s[anchorEnds[0][$-1] .. anchorEnds[0][$-1]+l];
	result.itemSeparator = s[anchorEnds[0][$-1]+l .. anchorStarts[1][0] - result.varPrefix[0].length];

	result.listPrefix = s[0 .. anchorStarts[0][0] - result.varPrefix[0].length];
	result.listSuffix = s[anchorEnds[$-1][$-1] + result.itemSuffix.length .. $];

	return result;
}

unittest
{
	auto s = q"EOF
<p>
	<a href="<?url1?>"><?title1?></a>,
	<a href="<?url2?>"><?title2?></a>
</p>
EOF";

	auto anchors = [["<?url1?>", "<?title1?>"], ["<?url2?>", "<?title2?>"]];
	auto list = inferList(s, anchors);
	assert(list.listPrefix == "<p>");
	assert(list.varPrefix[0] == "\n\t<a href=\"");
	assert(list.varPrefix[1] == "\">");
	assert(list.itemSuffix == "</a>");
	assert(list.itemSeparator == ",");
	assert(list.listSuffix == "\n</p>\n");

	auto s2 = list.render(anchors);
	assert(s == s2);
}

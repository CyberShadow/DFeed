/*  Copyright (C) 2011, 2012, 2014, 2015, 2017, 2018, 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.spam.simple;

import std.algorithm.searching;
import std.string;

import ae.utils.text;

import dfeed.loc;
import dfeed.site;
import dfeed.web.posting;
import dfeed.web.spam;

class SimpleChecker : SpamChecker
{
	override void check(PostProcess process, SpamResultHandler handler)
	{
		auto ua = process.headers.get("User-Agent", "");

		if (ua.startsWith("WWW-Mechanize"))
			return handler(likelySpam, _!"You seem to be posting using an unusual user-agent");

		auto subject = process.draft.clientVars.get("subject", "").toLower();

		// "hardspamtest" triggers certainlySpam (for testing moderation flow)
		if (subject.contains("hardspamtest"))
			return handler(certainlySpam, _!"Your subject contains a keyword that triggers moderation");

		foreach (keyword; ["kitchen", "spamtest"])
			if (subject.contains(keyword))
				return handler(likelySpam, _!"Your subject contains a suspicious keyword or character sequence");

		auto text = process.draft.clientVars.get("text", "").toLower();
		foreach (keyword; ["<a href=", "[url=", "[url]http"])
			if (text.contains(keyword))
				return handler(likelySpam, _!"Your post contains a suspicious keyword or character sequence");

		if (subject.length + text.length < 30 && "parent" !in process.draft.serverVars)
			return handler(likelySpam, _!"Your top-level post is suspiciously short");

		handler(likelyHam, null);
	}
}

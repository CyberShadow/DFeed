/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Search form and results.
module dfeed.web.web.view.search;

import core.time : Duration, days;

import std.algorithm.iteration : map, filter;
import std.algorithm.mutation : stripLeft;
import std.algorithm.searching : startsWith, canFind, findSplit;
import std.array : replace, split, join, replicate;
import std.conv : to;
import std.exception : enforce;
import std.format : format;
import std.functional : not;
import std.range.primitives : empty;
import std.string : strip, indexOf;

import ae.net.ietf.url : UrlParameters, encodeUrlParameters;
import ae.utils.exception : CaughtException;
import ae.utils.meta : I;
import ae.utils.text : segmentByWhitespace;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.time.parse : parseTime;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.loc;
import dfeed.database : query;
import dfeed.groups : getGroupInfoByPublicName;
import dfeed.message : Rfc850Post, idToFragment, idToUrl;
import dfeed.sinks.messagedb : searchTerm;
import dfeed.web.web.page : html, Redirect;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.pager;
import dfeed.web.web.part.post : miniPostInfo;
import dfeed.web.web.part.strings : summarizeTime;
import dfeed.web.web.postinfo : getPost;
import dfeed.web.web.user : user;

/// Delimiters for formatSearchSnippet.
enum searchDelimPrefix     = "\U000FDeed"; // Private Use Area character
enum searchDelimStartMatch = searchDelimPrefix ~ "\x01";
enum searchDelimEndMatch   = searchDelimPrefix ~ "\x02";
enum searchDelimEllipses   = searchDelimPrefix ~ "\x03";
enum searchDelimLength     = searchDelimPrefix.length + 1;

void discussionSearch(UrlParameters parameters)
{
	// HTTP form parameters => search string (visible in form, ?q= parameter) => search query (sent to database)

	string[] terms;
	if (string searchScope = parameters.get("scope", null))
	{
		if (searchScope.startsWith("dlang.org"))
			throw new Redirect("https://www.google.com/search?" ~ encodeUrlParameters(["sitesearch" : searchScope, "q" : parameters.get("q", null)]));
		else
		if (searchScope == "forum")
			{}
		else
		if (searchScope.startsWith("group:") || searchScope.startsWith("threadmd5:"))
			terms ~= searchScope;
	}
	terms ~= parameters.get("q", null);

	if (parameters.get("exact", null).length)
		terms ~= '"' ~ parameters["exact"].replace(`"`, ``) ~ '"';

	if (parameters.get("not", null).length)
		foreach (word; parameters["not"].split)
			terms ~= "-" ~ word.stripLeft('-');

	foreach (param; ["group", "author", "authoremail", "subject", "content", "newthread"])
		if (parameters.get(param, null).length)
			foreach (word; parameters[param].split)
			{
				if (param == "group")
					word = word.getGroupInfoByPublicName.I!(gi => gi ? gi.internalName.searchTerm : word);
				terms ~= param ~ ":" ~ word;
			}

	if (parameters.get("startdate", null).length || parameters.get("enddate", null).length)
		terms ~= "date:" ~ parameters.get("startdate", null) ~ ".." ~ parameters.get("enddate", null);

	auto searchString = terms.map!strip.filter!(not!empty).join(" ");
	bool doSearch = searchString.length > 0;
	string autoFocus = doSearch ? "" : " autofocus";

	if ("advsearch" in parameters)
	{
		html.put(
			`<form method="get" id="advanced-search-form">` ~
			`<h1>`, _!`Advanced Search`, `</h1>` ~
			`<p>`, _!`Find posts with...`, `</p>` ~
			`<table>` ~
				`<tr><td>`, _!`all these words:`     , ` </td><td><input size="50" name="q" value="`), html.putEncodedEntities(searchString), html.put(`"`, autoFocus, `></td></tr>` ~
				`<tr><td>`, _!`this exact phrase:`   , ` </td><td><input size="50" name="exact"></td></tr>` ~
				`<tr><td>`, _!`none of these words:` , ` </td><td><input size="50" name="not"></td></tr>` ~
				`<tr><td>`, _!`posted in the group:` , ` </td><td><input size="50" name="group"></td></tr>` ~
				`<tr><td>`, _!`posted by:`           , ` </td><td><input size="50" name="author"></td></tr>` ~
				`<tr><td>`, _!`posted by (email):`   , ` </td><td><input size="50" name="authoremail"></td></tr>` ~
				`<tr><td>`, _!`in threads titled:`   , ` </td><td><input size="50" name="subject"></td></tr>` ~
				`<tr><td>`, _!`containing:`          , ` </td><td><input size="50" name="content"></td></tr>` ~
				`<tr><td>`, _!`posted between:`      , ` </td><td><input type="date" placeholder="`, _!`yyyy-mm-dd`, `" name="startdate"> `, _!`and`, ` <input type="date" placeholder="`, _!`yyyy-mm-dd`, `" name="enddate"></td></tr>` ~
				`<tr><td>`, _!`posted as new thread:`, ` </td><td><input type="checkbox" name="newthread" value="y"><input size="1" tabindex="-1" style="visibility:hidden"></td></tr>` ~
			`</table>` ~
			`<br>` ~
			`<input name="search" type="submit" value="`, _!`Advanced search`, `">` ~
			`</table>` ~
			`</form>`
		);
		doSearch = false;
	}
	else
	{
		html.put(
			`<form method="get" id="search-form">` ~
			`<h1>`, _!`Search`, `</h1>` ~
			`<input name="q" size="50" value="`), html.putEncodedEntities(searchString), html.put(`"`, autoFocus, `>` ~
			`<input name="search" type="submit" value="`, _!`Search`, `">` ~
			`<input name="advsearch" type="submit" value="`, _!`Advanced search`, `">` ~
			`</form>`
		);
	}

	if (doSearch)
		try
		{
			long startDate = 0;
			long endDate = long.max;

			terms = searchString.split();
			string[] queryTerms;
			foreach (term; terms)
				if (term.startsWith("date:") && term.canFind(".."))
				{
					long parseDate(string date, Duration offset, long def)
					{
						if (!date.length)
							return def;
						else
							try
								return (date.parseTime!`Y-m-d` + offset).stdTime;
							catch (Exception e)
								throw new Exception(_!"Invalid date: %s (%s)".format(date, e.msg));
					}

					auto dates = term.findSplit(":")[2].findSplit("..");
					startDate = parseDate(dates[0], 0.days, startDate);
					endDate   = parseDate(dates[2], 1.days, endDate);
				}
				else
				if (term.startsWith("time:") && term.canFind(".."))
				{
					long parseTime(string time, long def)
					{
						return time.length ? time.to!long : def;
					}

					auto times = term.findSplit(":")[2].findSplit("..");
					startDate = parseTime(times[0], startDate);
					endDate   = parseTime(times[2], endDate);
				}
				else
					queryTerms ~= term;

			enforce(startDate < endDate, _!"Start date must be before end date");
			auto queryString = queryTerms.join(' ');

			int page = parameters.get("page", "1").to!int;
			enforce(page >= 1, _!"Invalid page number");

			enum postsPerPage = 10;

			int n = 0;

			enum queryCommon =
				"SELECT [ROWID], snippet([PostSearch], '" ~ searchDelimStartMatch ~ "', '" ~ searchDelimEndMatch ~ "', '" ~ searchDelimEllipses ~ "', 6) " ~
				"FROM [PostSearch]";
			auto iterator =
				queryTerms.length
				?
					(startDate == 0 && endDate == long.max)
					? query!(queryCommon ~ " WHERE [PostSearch] MATCH ?                            ORDER BY [Time] DESC LIMIT ? OFFSET ?")
						.iterate(queryString,                     postsPerPage + 1, (page-1)*postsPerPage)
					: query!(queryCommon ~ " WHERE [PostSearch] MATCH ? AND [Time] BETWEEN ? AND ? ORDER BY [Time] DESC LIMIT ? OFFSET ?")
						.iterate(queryString, startDate, endDate, postsPerPage + 1, (page-1)*postsPerPage)
				: query!("SELECT [ROWID], '' FROM [Posts] WHERE [Time] BETWEEN ? AND ? ORDER BY [Time] DESC LIMIT ? OFFSET ?")
					.iterate(startDate, endDate, postsPerPage + 1, (page-1)*postsPerPage)
				;

			foreach (int rowid, string snippet; iterator)
			{
				//html.put(`<pre>`, snippet, `</pre>`);
				string messageID;
				foreach (string id; query!"SELECT [ID] FROM [Posts] WHERE [ROWID] = ?".iterate(rowid))
					messageID = id;
				if (!messageID)
					continue; // Can occur with deleted posts

				n++;
				if (n > postsPerPage)
					break;

				auto post = getPost(messageID);
				if (post)
				{
					if (!snippet.length) // No MATCH (date only)
					{
						enum maxWords = 20;
						auto segments = post.newContent.segmentByWhitespace;
						if (segments.length < maxWords*2)
							snippet = segments.join();
						else
							snippet = segments[0..maxWords*2-1].join() ~ searchDelimEllipses;
					}
					formatSearchResult(post, snippet);
				}
			}

			if (n == 0)
				html.put(`<p>`, _!`Your search -`, ` <b>`), html.putEncodedEntities(searchString), html.put(`</b> `, _!`- did not match any forum posts.`, `</p>`);

			if (page != 1 || n > postsPerPage)
			{
				html.put(`<table class="forum-table post-pager">`);
				pager("?" ~ encodeUrlParameters(["q" : searchString]), page, n > postsPerPage ? int.max : page);
				html.put(`</table>`);
			}
		}
		catch (CaughtException e)
			html.put(`<div class="form-error">`, _!`Error:`, ` `), html.putEncodedEntities(e.msg), html.put(`</div>`);
}

void formatSearchSnippet(string s)
{
	while (true)
	{
		auto i = s.indexOf(searchDelimPrefix);
		if (i < 0)
			break;
		html.putEncodedEntities(s[0..i]);
		string delim = s[i..i+searchDelimLength];
		s = s[i+searchDelimLength..$];
		switch (delim)
		{
			case searchDelimStartMatch: html.put(`<b>`       ); break;
			case searchDelimEndMatch  : html.put(`</b>`      ); break;
			case searchDelimEllipses  : html.put(`<b>...</b>`); break;
			default: break;
		}
	}
	html.putEncodedEntities(s);
}

void formatSearchResult(Rfc850Post post, string snippet)
{
	string gravatarHash = getGravatarHash(post.authorEmail);

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="post forum-table`, (post.children ? ` with-children` : ``), `" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(2), `</tr>` ~ // Fixed layout dummies
			`<tr class="post-header"><th colspan="2">` ~
				`<div class="post-time">`, summarizeTime(time), `</div>`,
				encodeHtmlEntities(post.publicGroupNames().join(", ")), ` &raquo; ` ~
				`<a title="`, _!`View this post`, `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="permalink `, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr class="mini-post-info-cell">` ~
				`<td colspan="2">`
		); miniPostInfo(post, null, false); html.put(
				`</td>` ~
			`</tr>` ~
			`<tr>` ~
				`<td class="post-info">` ~
					`<div class="post-author">`), html.putEncodedEntities(author), html.put(`</div>`);
		putGravatar(gravatarHash, author, "http://www.gravatar.com/" ~ gravatarHash, _!`%s's Gravatar profile`.format(author), null, 80);

		html.put(
				`</td>` ~
				`<td class="post-body">` ~
					`<pre class="post-text">`), formatSearchSnippet(snippet), html.put(`</pre>`,
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td>` ~
			`</tr>` ~
			`</table>` ~
			`</div>`
		);
	}
}

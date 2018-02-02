/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.message;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;

public import ae.net.ietf.message;
import ae.net.ietf.url;
import ae.net.ietf.wrap;
import ae.utils.array;
import ae.utils.meta;

import dfeed.bitly;
import dfeed.common;
import dfeed.groups;
import dfeed.site;

alias std.string.indexOf indexOf;

class Rfc850Post : Post
{
	/// Internet message.
	Rfc850Message msg;
	alias msg this;

	/// Internal database index
	int rowid;

	/// Thread ID obtained by examining parent posts
	string cachedThreadID;

	/// URLs for IRC.
	string url, shortURL;

	/// For IRC.
	string verb;

	/// Result of threadify()
	Rfc850Post[] children;

	this(string _message, string _id=null, int rowid=0, string threadID=null)
	{
		msg = new Rfc850Message(_message);
		if (!msg.id && _id)
			msg.id = _id;
		this.rowid = rowid;
		this.cachedThreadID = threadID;

		this.verb = reply ? "replied to" : "posted";

		int bugzillaCommentNumber;
		if ("X-Bugzilla-Who" in headers)
		{
			// Special case for Bugzilla emails
			author = authorEmail = headers["X-Bugzilla-Who"];

			foreach (line; content.split("\n"))
				if (line.endsWith("> changed:"))
					author = line[0..line.indexOf(" <")];
				else
				if (line.startsWith("--- Comment #") && line.indexOf(" from ")>0 && line.indexOf(" <")>0 && line.endsWith(" ---"))
				{
					author = line[line.indexOf(" from ")+6 .. line.indexOf(" <")];
					bugzillaCommentNumber = to!int(line["--- Comment #".length .. line.indexOf(" from ")]);
				}
		}
		else
		if ("List-Id" in headers)
		{
			auto list = headers["List-Id"];
			auto listId = list.findSplit(" <")[2].findSplit(".puremagic.com>")[0];
			auto suffix = " via " ~ listId.toLower();
			if (listId.length && author.toLower().endsWith(suffix))
				author = author[0 .. $ - suffix.length];
		}

		if ("X-DFeed-List" in headers && !xref.length)
			xref = [Xref(headers["X-DFeed-List"])];

		if ("List-ID" in headers && subject.startsWith("[") && xref.length == 1)
		{
			auto p = subject.indexOf("] ");
			if (p >= 0 && !icmp(subject[1..p], xref[0].group))
				subject = subject[p+2..$];
		}

		if (subject.startsWith("[Issue "))
		{
			auto urlBase = headers.get("X-Bugzilla-URL", "http://d.puremagic.com/issues/");
			url = urlBase ~ "show_bug.cgi?id=" ~ subject.split(" ")[1][0..$-1];
			verb = bugzillaCommentNumber ? "commented on" : reply ? "updated" : "created";
			if (bugzillaCommentNumber > 0)
				url ~= "#c" ~ .text(bugzillaCommentNumber);
		}
		else
		if (id.length)
		{
			url = format("%s://%s%s", site.proto, site.host, idToUrl(id));
		}

		super.time = msg.time;
	}

	private this(Rfc850Message msg) { this.msg = msg; }

	static Rfc850Post newPostTemplate(string groups) { return new Rfc850Post(Rfc850Message.newPostTemplate(groups)); }
	Rfc850Post replyTemplate() { return new Rfc850Post(msg.replyTemplate()); }

	/// Set headers and message.
	void compile()
	{
		msg.compile();
		headers["User-Agent"] = "DFeed";
	}

	override void formatForIRC(void delegate(string) handler)
	{
		if (getImportance() >= Importance.normal && url && !shortURL)
			return shortenURL(url, (string shortenedURL) {
				shortURL = shortenedURL;
				formatForIRC(handler);
			});

		string groupPublicName(string internalName)
		{
			auto groupInfo = getGroupInfo(internalName);
			return groupInfo ? groupInfo.publicName : internalName;
		}

		handler(format("%s%s %s %s%s",
			xref.length ? "[" ~ publicGroupNames.join(",") ~ "] " : null,
			author == "" ? "<no name>" : filterIRCName(author),
			verb,
			subject == "" ? "<no subject>" : `"` ~ subject ~ `"`,
			shortURL ? ": " ~ shortURL : url ? ": " ~ url : "",
		));
	}

	override Importance getImportance()
	{
		auto group = getGroup(this);
		if (!reply && group && group.announce)
			return Importance.high;

		// GitHub notifications are already grabbed from RSS
		if (author == "GitHub")
			return Importance.low;

		if (where == "")
			return Importance.low;

		if (where.isIn(ANNOUNCE_REPLIES))
			return Importance.normal;

		return !reply || author.isIn(VIPs) ? Importance.normal : Importance.low;
	}

	@property string[] publicGroupNames()
	{
		return xref.map!(x => x.group.getGroupInfo.I!(gi => gi ? gi.publicName : x.group)).array();
	}

	@property string where()
	{
		string[] groups;
		foreach (x; xref)
			groups ~= x.group;
		return groups.join(",");
	}

	/// Arrange a bunch of posts in a thread hierarchy. Returns the root posts.
	static Rfc850Post[] threadify(Rfc850Post[] posts)
	{
		Rfc850Post[string] postLookup;
		foreach (post; posts)
		{
			post.children = null;
			postLookup[post.id] = post;
		}

		Rfc850Post[] roots;
		postLoop:
		foreach (post; posts)
		{
			foreach_reverse(reference; post.references)
			{
				auto pparent = reference in postLookup;
				if (pparent)
				{
					(*pparent).children ~= post;
					continue postLoop;
				}
			}
			roots ~= post;
		}
		return roots;
	}

	/// Get content excluding quoted text.
	@property string newContent()
	{
		auto paragraphs = content.unwrapText(wrapFormat);
		auto index = paragraphs.length.iota.filter!(i =>
			!paragraphs[i].quotePrefix.length && (i+1 >= paragraphs.length || !paragraphs[i+1].quotePrefix.length)
		).array;
		return paragraphs.indexed(index).map!(p => p.text).join("\n");
	}

private:
	string[] ANNOUNCE_REPLIES = [];
	string[] VIPs = ["Walter Bright", "Andrei Alexandrescu", "Sean Kelly", "Don", "dsimcha"];
}

unittest
{
	auto post = new Rfc850Post("From: msonke at example.org (=?ISO-8859-1?Q?S=F6nke_Martin?=)\n\nText");
	assert(post.author == "Sönke Martin");
	assert(post.authorEmail == "msonke@example.org");

	post = new Rfc850Post("Date: Tue, 06 Sep 2011 14:52 -0700\n\nText");
	assert(post.time.year == 2011);
}

// ***************************************************************************

template urlEncode(string forbidden, char escape = '%')
{
	alias encoder = encodeUrlPart!(c => c >= 0x20 && c < 0x7F && forbidden.indexOf(c) < 0 && c != escape, escape);
	string urlEncode(string s)
	{
		//  !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
		// " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
		return encoder(s);
	}
}

string urlDecode(string encoded)
{
	return decodeUrlParameter!false(encoded);
}

/// Encode a string to one suitable for an HTML anchor
string encodeAnchor(string s)
{
	//return encodeUrlParameter(s).replace("%", ".");
	// RFC 3986: " \"#%<>[\\]^`{|}"
	return urlEncode!(" !\"#$%&'()*+,/;<=>?@[\\]^`{|}~", ':')(s);
}

alias urlEncodeMessageUrl = urlEncode!(" \"#%/<>?[\\]^`{|}", '%');

/// Get relative URL to a post ID.
string idToUrl(string id, string action = "post", int page = 1)
{
	enforce(id.startsWith('<') && id.endsWith('>'), "Invalid message ID: " ~ id);

	// RFC 3986:
	// pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
	// sub-delims    = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
	// unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
	string path = "/" ~ action ~ "/" ~ urlEncodeMessageUrl(id[1..$-1]);

	assert(page >= 1);
	if (page > 1)
		path ~= "?page=" ~ text(page);

	return path;
}

/// Get URL fragment / anchor name for a post on the same page.
string idToFragment(string id)
{
	enforce(id.startsWith('<') && id.endsWith('>'), "Invalid message ID: " ~ id);
	return "post-" ~ encodeAnchor(id[1..$-1]);
}

GroupInfo getGroup(Rfc850Post post)
{
	enforce(post.xref.length, "No groups found in post");
	return getGroupInfo(post.xref[0].group);
}

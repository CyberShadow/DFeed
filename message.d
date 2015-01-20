/*  Copyright (C) 2011, 2012, 2013, 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module message;

import std.algorithm;
import std.array;
import std.conv;
import std.string;
import std.uri;

public import ae.net.ietf.message;
import ae.utils.array;

import common;
import bitly;

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

	/// Result of threadify()
	Rfc850Post[] children;

	this(string _message, string id=null, int rowid=0, string threadID=null)
	{
		msg = new Rfc850Message(_message);
		if (id && !msg.id)
			msg.id = id;
		this.rowid = rowid;
		this.cachedThreadID = threadID;

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

		if (subject.startsWith("[Issue "))
		{
			auto urlBase = headers.get("X-Bugzilla-URL", "http://d.puremagic.com/issues/");
			url = urlBase ~ "show_bug.cgi?id=" ~ subject.split(" ")[1][0..$-1];
			if (bugzillaCommentNumber > 0)
				url ~= "#c" ~ .text(bugzillaCommentNumber);
		}
		else
		if (id.length)
		{
			import std.file;
			url = format("http://%s/post/%s", readText("data/web.txt").splitLines()[1], encodeComponent(id[1..$-1]));
		}
/+		else
		if (xref.length)
		{
			auto group = xref[0].group;
			auto num = xref[0].num;
			//url = format("http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=%s", encodeUrlParameter(group), num);
			//url = format("http://digitalmars.com/webnews/newsgroups.php?art_group=%s&article_id=%s", encodeComponent(group), num);
		}
		else
		if ("LIST-ID" in headers && id)
		{
			if (id.startsWith("<") && id.endsWith(">"))
				url = "http://mid.gmane.org/" ~ id[1..$-1];
		}
+/

		//if ("MESSAGE-ID" in headers)
		//	url = "news://news.digitalmars.com/" ~ headers["MESSAGE-ID"][1..$-1];

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
		if (isImportant() && url && !shortURL)
			return shortenURL(url, (string shortenedURL) {
				shortURL = shortenedURL;
				formatForIRC(handler);
			});

		handler(format("%s%s %s %s%s",
			where is null ? null : "[" ~ where.replace("digitalmars.", "dm.") ~ "] ",
			author == "" ? "<no name>" : filterIRCName(author),
			reply ? "replied to" : "posted",
			subject == "" ? "<no subject>" : `"` ~ subject ~ `"`,
			shortURL ? ": " ~ shortURL : ""
		));
	}

	override bool isImportant()
	{
		// GitHub notifications are already grabbed from RSS
		if (authorEmail == "noreply@github.com")
			return false;

		if (where == "")
			return false;

		if (where.isIn(ANNOUNCE_REPLIES))
			return true;

		return !reply || author.isIn(VIPs);
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

private:
	string[] ANNOUNCE_REPLIES = ["digitalmars.D.bugs"];
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

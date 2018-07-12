/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.web;

import core.time;

import std.algorithm;
import std.array;
import std.base64;
import std.conv;
import std.datetime : SysTime, Clock, UTC;
import std.digest.sha;
import std.exception;
import std.file;
import std.functional;
import std.path;
import std.random;
import std.range;
import std.regex;
import std.stdio;
import std.string;

alias std.string.indexOf indexOf;

import ae.net.asockets;
import ae.net.http.caching;
import ae.net.http.responseex;
import ae.net.http.server;
import ae.net.ietf.headers;
import ae.net.ietf.url;
import ae.net.ietf.wrap;
import ae.sys.log;
import ae.utils.array;
import ae.utils.digest;
import ae.utils.exception;
import ae.utils.feed;
import ae.utils.json;
import ae.utils.meta;
import ae.utils.regex;
import ae.utils.sini : loadIni;
import ae.utils.text;
import ae.utils.text.html;
import ae.utils.textout;
import ae.utils.time.format;
import ae.utils.time.parse;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.bayes;
import dfeed.common;
import dfeed.database;
import dfeed.groups;
import dfeed.mail;
import dfeed.message;
import dfeed.sinks.cache;
import dfeed.sinks.messagedb : searchTerm, threadID;
import dfeed.sinks.subscriptions;
import dfeed.site;
import dfeed.sources.github;
import dfeed.web.captcha;
import dfeed.web.lint;
import dfeed.web.list;
//import dfeed.web.mailhide;
import dfeed.web.posting;
import dfeed.web.user : User, getUser, SettingType;
import dfeed.web.spam : bayes, getSpamicity;
import dfeed.web.web.cache;
import dfeed.web.web.config;
import dfeed.web.web.draft : getDraft, saveDraft, draftToPost;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.pager;
import dfeed.web.web.part.post : postLink, miniPostInfo;
import dfeed.web.web.part.thread : formatThreadedPosts;
import dfeed.web.web.perf;
import dfeed.web.web.posting : postDraft;
import dfeed.web.web.postmod : learnModeratedMessage;
import dfeed.web.web.request : onRequest, currentRequest, ip;
import dfeed.web.web.statics;
import dfeed.web.web.view.thread : getPostThreadIndex, getPostAtThreadIndex;
import dfeed.web.web.user : user, userSettings;

StringBuffer html;

alias config = dfeed.web.web.config.config;

// ***********************************************************************

string resolvePostUrl(string id)
{
	foreach (string threadID; query!"SELECT `ThreadID` FROM `Posts` WHERE `ID` = ?".iterate(id))
		return idToThreadUrl(id, threadID);

	throw new NotFoundException("Post not found");
}

string idToThreadUrl(string id, string threadID)
{
	return idToUrl(threadID, "thread", indexToPage(getPostThreadIndex(id), POSTS_PER_PAGE)) ~ "#" ~ idToFragment(id);
}

static Rfc850Post getPost(string id, uint[] partPath = null)
{
	foreach (int rowid, string message, string threadID; query!"SELECT `ROWID`, `Message`, `ThreadID` FROM `Posts` WHERE `ID` = ?".iterate(id))
	{
		auto post = new Rfc850Post(message, id, rowid, threadID);
		while (partPath.length)
		{
			enforce(partPath[0] < post.parts.length, "Invalid attachment");
			post = post.parts[partPath[0]];
			partPath = partPath[1..$];
		}
		return post;
	}
	return null;
}

static string getPostSource(string id)
{
	foreach (string message; query!"SELECT `Message` FROM `Posts` WHERE `ID` = ?".iterate(id))
		return message;
	return null;
}

struct PostInfo { int rowid; string id, threadID, parentID, author, authorEmail, subject; SysTime time; }
CachedSet!(string, PostInfo*) postInfoCache;

PostInfo* getPostInfo(string id)
{
	return postInfoCache(id, retrievePostInfo(id));
}

PostInfo* retrievePostInfo(string id)
{
	if (id.startsWith('<') && id.endsWith('>'))
		foreach (int rowid, string threadID, string parentID, string author, string authorEmail, string subject, long stdTime; query!"SELECT `ROWID`, `ThreadID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ID` = ?".iterate(id))
		{
			if (authorEmail is null)
			{
				authorEmail = new Rfc850Message(query!"SELECT [Message] FROM [Posts] WHERE [ROWID]=?".iterate(rowid).selectValue!string).authorEmail;
				if (authorEmail is null)
					authorEmail = "";
				assert(authorEmail !is null);
				query!"UPDATE [Posts] SET [AuthorEmail]=? WHERE [ROWID]=?".exec(authorEmail, rowid);
			}
			return [PostInfo(rowid, id, threadID, parentID, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr;
		}
	return null;
}

// ***********************************************************************

static Regex!char reUrl;
static this() { reUrl = regex(`\w+://[^<>\s]+[\w/\-=]`); }

void formatBody(Rfc850Message post)
{
	auto paragraphs = unwrapText(post.content, post.wrapFormat);
	bool inSignature = false;
	int quoteLevel = 0;
	foreach (paragraph; paragraphs)
	{
		int paragraphQuoteLevel;
		foreach (c; paragraph.quotePrefix)
			if (c == '>')
				paragraphQuoteLevel++;

		for (; quoteLevel > paragraphQuoteLevel; quoteLevel--)
			html ~= `</span>`;
		for (; quoteLevel < paragraphQuoteLevel; quoteLevel++)
			html ~= `<span class="forum-quote">`;

		if (!quoteLevel && (paragraph.text == "-- " || paragraph.text == "_______________________________________________"))
		{
			html ~= `<span class="forum-signature">`;
			inSignature = true;
		}

		enum forceWrapThreshold = 30;
		enum forceWrapMinChunkSize =  5;
		enum forceWrapMaxChunkSize = 15;
		static assert(forceWrapMaxChunkSize > forceWrapMinChunkSize * 2);

		import std.utf;
		bool needsWrap = paragraph.text.byChar.splitter(' ').map!(s => s.length).I!(r => reduce!max(size_t.init, r)) > forceWrapThreshold;

		auto hasURL = paragraph.text.contains("://");

		void processText(string s)
		{
			html.put(encodeHtmlEntities(s));
		}

		void processWrap(string s)
		{
			alias processText next;

			if (!needsWrap)
				return next(s);

			auto segments = s.segmentByWhitespace();
			foreach (ref segment; segments)
			{
				if (segment.length > forceWrapThreshold)
				{
					void chunkify(string s, string delimiters)
					{
						if (s.length < forceWrapMaxChunkSize)
						{
							html.put(`<span class="forcewrap">`);
							next(s);
							html.put(`</span>`);
						}
						else
						if (!delimiters.length)
						{
							// Don't cut UTF-8 sequences in half
							static bool canCutAt(char c) { return (c & 0x80) == 0 || (c & 0x40) != 0; }
							foreach (i; s.length.iota.radial)
								if (canCutAt(s[i]))
								{
									chunkify(s[0..i], null);
									chunkify(s[i..$], null);
									return;
								}
							chunkify(s[0..$/2], null);
							chunkify(s[$/2..$], null);
						}
						else
						{
							foreach (i; iota(forceWrapMinChunkSize, s.length-forceWrapMinChunkSize).radial)
								if (s[i] == delimiters[0])
								{
									chunkify(s[0..i+1], delimiters);
									chunkify(s[i+1..$], delimiters);
									return;
								}
							chunkify(s, delimiters[1..$]);
						}
					}

					chunkify(segment, "/&=.-+,;:_\\|`'\"~!@#$%^*()[]{}");
				}
				else
					next(segment);
			}
		}

		void processURLs(string s)
		{
			alias processWrap next;

			if (!hasURL)
				return next(s);

			size_t pos = 0;
			foreach (m; matchAll(s, reUrl))
			{
				next(s[pos..m.pre().length]);
				html.put(`<a rel="nofollow" href="`, m.hit(), `">`);
				next(m.hit());
				html.put(`</a>`);
				pos = m.pre().length + m.hit().length;
			}
			next(s[pos..$]);
		}

		if (paragraph.quotePrefix.length)
			html.put(`<span class="forum-quote-prefix">`), html.putEncodedEntities(paragraph.quotePrefix), html.put(`</span>`);
		processURLs(paragraph.text);
		html.put('\n');
	}
	for (; quoteLevel; quoteLevel--)
		html ~= `</span>`;
	if (inSignature)
		html ~= `</span>`;
}

string summarizeTime(SysTime time, bool colorize = false)
{
	if (!time.stdTime)
		return "-";

	string style;
	if (colorize)
	{
		import std.math;
		auto diff = Clock.currTime() - time;
		auto diffLog = log2(diff.total!"seconds");
		enum LOG_MIN = 10; // 1 hour-ish
		enum LOG_MAX = 18; // 3 days-ish
		enum COLOR_MAX = 0xA0;
		auto f = (diffLog - LOG_MIN) / (LOG_MAX - LOG_MIN);
		f = min(1, max(0, f));
		auto c = cast(int)(f * COLOR_MAX);

		style ~= format("color: #%02X%02X%02X;", c, c, c);
	}

	bool shorter = colorize; // hack
	return `<span style="` ~ style ~ `" title="` ~ encodeHtmlEntities(formatLongTime(time)) ~ `">` ~ encodeHtmlEntities(formatShortTime(time, shorter)) ~ `</span>`;
}

string formatShortTime(SysTime time, bool shorter)
{
	if (!time.stdTime)
		return "-";

	auto now = Clock.currTime(UTC());
	auto duration = now - time;

	if (duration < dur!"days"(7))
		return formatDuration(duration);
	else
	if (duration < dur!"days"(300))
		if (shorter)
			return time.formatTime!"M d"();
		else
			return time.formatTime!"F d"();
	else
		if (shorter)
			return time.formatTime!"M d, Y"();
		else
			return time.formatTime!"F d, Y"();
}

string formatDuration(Duration duration)
{
	string ago(long amount, string units)
	{
		assert(amount > 0);
		return format("%s %s%s ago", amount, units, amount==1 ? "" : "s");
	}

	if (duration < 0.seconds)
		return "from the future";
	else
	if (duration < 1.seconds)
		return "just now";
	else
	if (duration < 1.minutes)
		return ago(duration.total!"seconds", "second");
	else
	if (duration < 1.hours)
		return ago(duration.total!"minutes", "minute");
	else
	if (duration < 1.days)
		return ago(duration.total!"hours", "hour");
	else
	/*if (duration < dur!"days"(2))
		return "yesterday";
	else
	if (duration < dur!"days"(6))
		return formatTime("l", time);
	else*/
	if (duration < 7.days)
		return ago(duration.total!"days", "day");
	else
	if (duration < 31.days)
		return ago(duration.total!"weeks", "week");
	else
	if (duration < 365.days)
		return ago(duration.total!"days" / 30, "month");
	else
		return ago(duration.total!"days" / 365, "year");
}

string formatLongTime(SysTime time)
{
	return time.formatTime!"l, d F Y, H:i:s e"();
}

/// Add thousand-separators
string formatNumber(long n)
{
	string s = text(n);
	int digits = 0;
	foreach_reverse(p; 1..s.length)
		if (++digits % 3 == 0)
			s = s[0..p] ~ ',' ~ s[p..$];
	return s;
}

static string truncateString(string s8, int maxLength = 30)
{
	auto encoded = encodeHtmlEntities(s8);
	return `<span class="truncated" style="max-width: ` ~ text(maxLength * 0.6) ~ `em" title="`~encoded~`">` ~ encoded ~ `</span>`;
}

/+
/// Generate a link to set a user preference
string setOptionLink(string name, string value)
{
	return "/set?" ~ encodeUrlParameters(UrlParameters([name : value, "url" : "__URL__", "secret" : userSettings.secret]));
}
+/

// ***********************************************************************

enum FEED_HOURS_DEFAULT = 24;
enum FEED_HOURS_MAX = 72;

CachedSet!(string, CachedResource) feedCache;

CachedResource getFeed(GroupInfo groupInfo, bool threadsOnly, int hours)
{
	string feedUrl = site.proto ~ "://" ~ site.host ~ "/feed" ~
		(threadsOnly ? "/threads" : "/posts") ~
		(groupInfo ? "/" ~ groupInfo.urlName : "") ~
		(hours!=FEED_HOURS_DEFAULT ? "?hours=" ~ text(hours) : "");

	CachedResource getFeed()
	{
		auto title = "Latest " ~ (threadsOnly ? "threads" : "posts") ~ (groupInfo ? " on " ~ groupInfo.publicName : "");
		auto posts = getFeedPosts(groupInfo, threadsOnly, hours);
		auto feed = makeFeed(posts, feedUrl, title, groupInfo is null);
		return feed;
	}
	return feedCache(feedUrl, getFeed());
}

Rfc850Post[] getFeedPosts(GroupInfo groupInfo, bool threadsOnly, int hours)
{
	string PERF_SCOPE = "getFeedPosts(%s,%s,%s)".format(groupInfo ? groupInfo.internalName : "null", threadsOnly, hours); mixin(MeasurePerformanceMixin);

	auto since = (Clock.currTime() - dur!"hours"(hours)).stdTime;
	auto iterator =
		groupInfo ?
			threadsOnly ?
				query!"SELECT `Message` FROM `Posts` WHERE `ID` IN (SELECT `ID` FROM `Groups` WHERE `Time` > ? AND `Group` = ?) AND `ID` = `ThreadID`".iterate(since, groupInfo.internalName)
			:
				query!"SELECT `Message` FROM `Posts` WHERE `ID` IN (SELECT `ID` FROM `Groups` WHERE `Time` > ? AND `Group` = ?)".iterate(since, groupInfo.internalName)
		:
			threadsOnly ?
				query!"SELECT `Message` FROM `Posts` WHERE `Time` > ? AND `ID` = `ThreadID`".iterate(since)
			:
				query!"SELECT `Message` FROM `Posts` WHERE `Time` > ?".iterate(since)
		;

	Rfc850Post[] posts;
	foreach (string message; iterator)
		posts ~= new Rfc850Post(message);
	return posts;
}

CachedResource makeFeed(Rfc850Post[] posts, string feedUrl, string feedTitle, bool addGroup)
{
	AtomFeedWriter feed;
	feed.startFeed(feedUrl, feedTitle, Clock.currTime());

	foreach (post; posts)
	{
		html.clear();
		html.put("<pre>");
		formatBody(post);
		html.put("</pre>");

		auto postTitle = post.rawSubject;
		if (addGroup)
			postTitle = "[" ~ post.publicGroupNames().join(", ") ~ "] " ~ postTitle;

		feed.putEntry(post.url, postTitle, post.author, post.time, cast(string)html.get(), post.url);
	}
	feed.endFeed();

	return new CachedResource([Data(feed.xml.output.get())], "application/atom+xml");
}

CachedResource getSubscriptionFeed(string subscriptionID)
{
	string feedUrl = site.proto ~ "://" ~ site.host ~ "/subscription-feed/" ~ subscriptionID;

	CachedResource getFeed()
	{
		auto subscription = getSubscription(subscriptionID);
		auto title = "%s subscription (%s)".format(site.host, subscription.trigger.getTextDescription());
		Rfc850Post[] posts;
		foreach (string messageID; query!"SELECT [MessageID] FROM [SubscriptionPosts] WHERE [SubscriptionID] = ? ORDER BY [Time] DESC LIMIT 50"
							.iterate(subscriptionID))
		{
			auto post = getPost(messageID);
			if (post)
				posts ~= post;
		}

		return makeFeed(posts, feedUrl, title, true);
	}
	return feedCache(feedUrl, getFeed());
}

// **************************************************************************

class Redirect : Throwable
{
	string url;
	this(string url) { this.url = url; super("Uncaught redirect"); }
}

class NotFoundException : Exception
{
	this(string str = "The specified resource cannot be found on this server.") { super(str); }
}

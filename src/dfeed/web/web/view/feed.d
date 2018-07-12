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

/// ATOM feeds.
module dfeed.web.web.view.feed;

import core.time : dur;

import std.array : join;
import std.conv : text;
import std.datetime.systime;
import std.format : format;

import ae.net.http.caching : CachedResource;
import ae.sys.data : Data;
import ae.utils.feed : AtomFeedWriter;

import dfeed.database : query;
import dfeed.groups : GroupInfo;
import dfeed.message : Rfc850Post;
import dfeed.sinks.cache : CachedSet;
import dfeed.sinks.subscriptions : getSubscription;
import dfeed.site : site;
import dfeed.web.web.page : html;
import dfeed.web.web.part.postbody : formatBody;
import dfeed.web.web.perf;
import dfeed.web.web.postinfo : getPost;

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

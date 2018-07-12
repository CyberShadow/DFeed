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

/// Front page.
module dfeed.web.web.view.index;

import core.time;

import std.array : split, replicate;
import std.conv : to, text;
import std.datetime.systime : Clock, SysTime;
import std.format : format;
import std.random : uniform;

import ae.net.ietf.url : encodeUrlParameter;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.database;
import dfeed.message;
import dfeed.groups;
import dfeed.sinks.cache;
import dfeed.sinks.subscriptions;
import dfeed.site : site;
import dfeed.web.web.cache;
import dfeed.web.web.page : html;
import dfeed.web.web.part.strings : formatNumber, formatDuration, summarizeTime;
import dfeed.web.web.perf;
import dfeed.web.web.postinfo : getPostInfo;
import dfeed.web.web.user : user, userSettings;

Cached!int totalPostCountCache, totalThreadCountCache;

void discussionIndexHeader()
{
	auto now = Clock.currTime();
	if (now - SysTime(userSettings.sessionCanary.to!long) > 4.hours)
	{
		userSettings.previousSession = userSettings.currentSession;
		userSettings.currentSession = userSettings.sessionCanary = now.stdTime.text;
	}
	long previousSession = userSettings.previousSession.to!long;

	string name = user.isLoggedIn() ? user.getName() : userSettings.name.length ? userSettings.name.split(' ')[0] : `Guest`;
	html.put(
		`<div id="forum-index-header">` ~
		`<h1>`), html.putEncodedEntities(site.name), html.put(`</h1>` ~
		`<p>Welcome`, previousSession ? ` back` : ``, `, `), html.putEncodedEntities(name), html.put(`.</p>` ~

		`<ul>`
	);

	string[][3] bits;

	if (user.isLoggedIn())
	{
		auto subscriptions = getUserSubscriptions(user.getName());
		int numSubscriptions, numNewSubscriptions;
		foreach (subscription; subscriptions)
		{
			auto c = subscription.getUnreadCount();
			if (subscription.trigger.type == "reply")
				if (c)
					bits[0] ~= `<li><b>You have <a href="/subscription-posts/%s">%d new repl%s</a> to <a href="/search?q=authoremail:%s">your posts</a>.</b></li>`
						.format(encodeHtmlEntities(subscription.id), c, c==1 ? "y" : "ies", encodeHtmlEntities(encodeUrlParameter(userSettings.email)));
				else
					bits[2] ~= `<li>No new <a href="/subscription-posts/%s">replies</a> to <a href="/search?q=authoremail:%s">your posts</a>.</li>`
						.format(encodeHtmlEntities(subscription.id), encodeHtmlEntities(encodeUrlParameter(userSettings.email)));
			else
			{
				numSubscriptions++;
				if (c)
				{
					numNewSubscriptions++;
					bits[1] ~= `<li><b>You have <a href="/subscription-posts/%s">%d unread post%s</a> matching your <a href="/settings#subscriptions">%s subscription</a> (%s).</b></li>`
						.format(encodeHtmlEntities(subscription.id), c, c==1 ? "" : "s", subscription.trigger.type, subscription.trigger.getDescription());
				}
			}
		}
		if (numSubscriptions && !numNewSubscriptions)
			bits[2] ~= `<li>No new posts matching your <a href="/settings#subscriptions">subscription%s</a>.</b></li>`
				.format(numSubscriptions==1 ? "" : "s");
	}
	else
	{
		int hasPosts = 0;
		if (userSettings.email)
			hasPosts = query!"SELECT EXISTS(SELECT 1 FROM [Posts] WHERE [AuthorEmail] = ? LIMIT 1)".iterate(userSettings.email).selectValue!int;
		if (hasPosts)
			bits[2] ~= `<li>If you <a href="/register">create an account</a>, you can track replies to <a href="/search?q=authoremail:%s">your posts</a>.</li>`
				.format(encodeHtmlEntities(encodeUrlParameter(userSettings.email)));
		else
			bits[0] ~= `<li>You can read and post on this forum without <a href="/register">creating an account</a>, but doing so offers <a href="/help#accounts">a few benefits</a>.</li>`;
	}

	SysTime cutOff = previousSession ? SysTime(previousSession) : now - 24.hours;
	int numThreads = query!"SELECT COUNT(*)                      FROM [Threads] WHERE [Created] >= ?".iterate(cutOff.stdTime).selectValue!int;
	int numPosts   = query!"SELECT COUNT(*)                      FROM [Posts]   WHERE [Time]    >= ?".iterate(cutOff.stdTime).selectValue!int;
	int numUsers   = query!"SELECT COUNT(DISTINCT [AuthorEmail]) FROM [Posts]   WHERE [Time]    >= ?".iterate(cutOff.stdTime).selectValue!int;

	bits[(numThreads || numPosts) ? 1 : 2] ~=
		"<li>"
		~
		(
			(numThreads || numPosts)
			?
				"%d user%s ha%s created %-(%s and %)"
				.format(
					numUsers,
					numUsers==1 ? "" : "s",
					numThreads+numPosts==1 ? "s" : "ve",
					(numThreads ? [`<a href="/search?q=time:%d..+newthread:y">%s thread%s</a>`.format(cutOff.stdTime, formatNumber(numThreads), numThreads==1 ? "" : "s")] : [])
					~
					(numPosts   ? [`<a href="/search?q=time:%d..">%s post%s</a>`              .format(cutOff.stdTime, formatNumber(numPosts  ), numPosts  ==1 ? "" : "s")] : [])
				)
			:
				"No new forum activity"
		)
		~
		(
			previousSession
			?
				" since your last visit (%s).".format(formatDuration(now - cutOff))
			:
				" in the last 24 hours."
		)
		~
		"</li>"
	;

	bits[2] ~= "<li>There are %s posts, %s threads, and %s registered users on this forum.</li>"
		.format(
			formatNumber(totalPostCountCache  (query!"SELECT COUNT(*) FROM [Posts]"  .iterate().selectValue!int)),
			formatNumber(totalThreadCountCache(query!"SELECT COUNT(*) FROM [Threads]".iterate().selectValue!int)),
			formatNumber(                      query!"SELECT COUNT(*) FROM [Users]"  .iterate().selectValue!int ),
		);

	auto numRead = user.countRead();
	if (numRead)
		bits[2] ~= "<li>You have read a total of %s forum post%s during your visit%s.</li>".format(formatNumber(numRead), numRead==1?"":"s", previousSession?"s":"");

	bits[2] ~= "<li>Random tip: " ~ tips[uniform(0, $)] ~ "</li>";

	foreach (bitGroup; bits[])
		foreach (bit; bitGroup)
			html.put(bit);
	html.put(
		`</ul>` ~
		`</div>`
	);

	//html.put("<p>Random tip: " ~ tips[uniform(0, $)] ~ "</p>");
}

string[] tips =
[
	`This forum has several different <a href="/help#view-modes">view modes</a>. Try them to find one you like best. You can change the view mode in the <a href="/settings">settings</a>.`,
	`This forum supports <a href="/help#keynav">keyboard shortcuts</a>. Press <kbd>?</kbd> to view them.`,
	`You can focus a message with <kbd>j</kbd>/<kbd>k</kbd> and press <kbd>u</kbd> to mark it as unread, to remind you to read it later.`,
	`The <a href="/help#avatars">avatars on this forum</a> are provided by Gravatar, which allows associating a global avatar with an email address.`,
	`This forum remembers your read post history on a per-post basis. If you are logged in, the post history is saved on the server, and in a compressed cookie otherwise.`,
	`Much of this forum's content is also available via classic mailing lists or NNTP - see the "Also via" column on the forum index.`,
	`If you create a Gravatar profile with the email address you post with, it will be accessible when clicking your avatar.`,
//	`You don't need to create an account to post on this forum, but doing so <a href="/help#accounts">offers a few benefits</a>.`,
	`To subscribe to a thread, click the "Subscribe" link on that thread's first post. You need to be logged in to create subscriptions.`,
	`To search the forum, use the search widget at the top, or you can visit <a href="/search">the search page</a> directly.`,
	`This forum is open-source! Read or fork the code <a href="https://github.com/CyberShadow/DFeed">on GitHub</a>.`,
	`If you encounter a bug or need a missing feature, you can <a href="https://github.com/CyberShadow/DFeed/issues">create an issue on GitHub</a>.`,
];

string[string] getLastPosts()
{
	enum PERF_SCOPE = "getLastPosts"; mixin(MeasurePerformanceMixin);
	string[string] lastPosts;
	foreach (set; groupHierarchy)
		foreach (group; set.groups)
			foreach (string id; query!"SELECT `ID` FROM `Groups` WHERE `Group`=? ORDER BY `Time` DESC LIMIT 1".iterate(group.internalName))
				lastPosts[group.internalName] = id;
	return lastPosts;
}

Cached!(string[string]) lastPostCache;

void discussionIndex()
{
	discussionIndexHeader();

	auto threadCounts = threadCountCache(getThreadCounts());
	auto postCounts = postCountCache(getPostCounts());
	auto lastPosts = lastPostCache(getLastPosts());

	string summarizePost(string postID)
	{
		auto info = getPostInfo(postID);
		if (info)
			with (*info)
				return
					`<div class="truncated"><a class="forum-postsummary-subject ` ~ (user.isRead(rowid) ? "forum-read" : "forum-unread") ~ `" href="` ~ encodeHtmlEntities(idToUrl(id)) ~ `" title="` ~ encodeHtmlEntities(subject) ~ `">` ~ encodeHtmlEntities(subject) ~ `</a></div>` ~
					`<div class="truncated">by <span class="forum-postsummary-author" title="` ~ encodeHtmlEntities(author) ~ `">` ~ encodeHtmlEntities(author) ~ `</span></div>` ~
					`<span class="forum-postsummary-time">` ~ summarizeTime(time) ~ `</span>`;

		return `<div class="forum-no-data">-</div>`;
	}
	html.put(
		`<table id="forum-index" class="forum-table">` ~
		`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(5), `</tr>` // Fixed layout dummies
	);
	foreach (set; groupHierarchy)
	{
		if (!set.visible)
			continue;

		html.put(
			`<tr><th colspan="5">`), html.putEncodedEntities(set.name), html.put(`</th></tr>` ~
			`<tr class="subheader"><th>Group</th><th>Last Post</th><th>Threads</th><th>Posts</th><th>Also via</th></tr>`
		);
		foreach (group; set.groups)
		{
			html.put(
				`<tr class="group-row">` ~
					`<td class="forum-index-col-forum">` ~
						`<a href="/group/`), html.putEncodedEntities(group.urlName), html.put(`">`), html.putEncodedEntities(group.publicName), html.put(`</a>` ~
						`<div class="forum-index-description" title="`), html.putEncodedEntities(group.description), html.put(`">`), html.putEncodedEntities(group.description), html.put(`</div>` ~
					`</td>` ~
					`<td class="forum-index-col-lastpost">`, group.internalName in lastPosts    ? summarizePost(   lastPosts[group.internalName]) : `<div class="forum-no-data">-</div>`, `</td>` ~
					`<td class="number-column">`,            group.internalName in threadCounts ? formatNumber (threadCounts[group.internalName]) : `-`, `</td>` ~
					`<td class="number-column">`,            group.internalName in postCounts   ? formatNumber (  postCounts[group.internalName]) : `-`, `</td>` ~
					`<td class="number-column">`
			);
			foreach (i, av; group.alsoVia.values)
				html.put(i ? `<br>` : ``, `<a href="`, av.url, `">`, av.name, `</a>`);
			html.put(
					`</td>` ~
				`</tr>`,
			);
		}
	}
	html.put(`</table>`);
}

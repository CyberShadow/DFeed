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

/// Rendering of iframe widgets.
module dfeed.web.web.view.widgets;

import std.algorithm.searching;
import std.format : format;

import ae.utils.xmllite : putEncodedEntities;

import dfeed.sinks.cache;
import dfeed.web.web : PostInfo, getPostInfo, summarizeTime;
import dfeed.web.web.page : html;
import dfeed.web.web.perf;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.statics;
import dfeed.database;
import dfeed.message;
import dfeed.web.web.user : user;

Cached!(ActiveDiscussion[]) activeDiscussionsCache;
Cached!(string[]) latestAnnouncementsCache;
enum framePostsLimit = 10;

static struct ActiveDiscussion { string id; int postCount; }

ActiveDiscussion[] getActiveDiscussions()
{
	enum PERF_SCOPE = "getActiveDiscussions"; mixin(MeasurePerformanceMixin);
	const groupFilter = ["digitalmars.D.announce", "digitalmars.D.bugs"]; // TODO: config
	enum postCountLimit = 10;
	ActiveDiscussion[] result;
	foreach (string group, string firstPostID; query!"SELECT [Group], [ID] FROM [Threads] ORDER BY [Created] DESC LIMIT 100".iterate())
	{
		if (groupFilter.canFind(group))
			continue;

		int postCount;
		foreach (int count; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?".iterate(firstPostID))
			postCount = count;
		if (postCount < postCountLimit)
			continue;

		result ~= ActiveDiscussion(firstPostID, postCount);
		if (result.length == framePostsLimit)
			break;
	}
	return result;
}

string[] getLatestAnnouncements()
{
	enum PERF_SCOPE = "getLatestAnnouncements"; mixin(MeasurePerformanceMixin);
	enum group = "digitalmars.D.announce"; // TODO: config
	string[] result;
	foreach (string firstPostID; query!"SELECT [Threads].[ID] FROM [Threads] JOIN [Posts] ON [Threads].[ID]=[Posts].[ID] WHERE [Threads].[Group] = ? ORDER BY [Posts].[Time] DESC LIMIT ?".iterate(group, framePostsLimit))
		result ~= firstPostID;
	return result;
}

void summarizeFrameThread(PostInfo* info, string infoText)
{
	if (info)
		with (*info)
		{
			putGravatar(getGravatarHash(info.authorEmail), idToUrl(id), `target="_top" class="forum-postsummary-gravatar" `);
			html.put(
				`<a target="_top" class="forum-postsummary-subject `, (user.isRead(rowid) ? "forum-read" : "forum-unread"), `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`">`), html.putEncodedEntities(subject), html.put(`</a><br>` ~
				`<div class="forum-postsummary-info">`, infoText, `</div>` ~
				`by <span class="forum-postsummary-author">`), html.putEncodedEntities(author), html.put(`</span>`
			);
			return;
		}

	html.put(`<div class="forum-no-data">-</div>`);
}

void discussionFrameAnnouncements()
{
	auto latestAnnouncements = latestAnnouncementsCache(getLatestAnnouncements());

	html.put(`<table class="forum-table"><thead><tr><th>` ~
		`<a target="_top" class="feed-icon" title="Subscribe" href="/feed/threads/digitalmars.D.announce"><img src="`, staticPath("/images/rss.png"),`"></img></a>` ~
		`<a target="_top" href="/group/digitalmars.D.announce">Latest announcements</a>` ~
		`</th></tr></thead><tbody>`);
	foreach (row; latestAnnouncements)
	{
		auto info = getPostInfo(row);
		html.put(`<tr><td>`), summarizeFrameThread(info, summarizeTime(info.time)), html.put(`</td></tr>`);
	}
	html.put(`</tbody></table>`);
}

void discussionFrameDiscussions()
{
	auto activeDiscussions = activeDiscussionsCache(getActiveDiscussions());

	html.put(`<table class="forum-table"><thead><tr><th><a target="_top" href="/">Active discussions</a></th></tr></thead><tbody>`);
	foreach (row; activeDiscussions)
		html.put(`<tr><td>`), summarizeFrameThread(getPostInfo(row.id), "%d posts".format(row.postCount)), html.put(`</td></tr>`);
	html.put(`</tbody></table>`);
}


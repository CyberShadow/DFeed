/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2022  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import dfeed.loc;
import dfeed.sinks.cache;
import dfeed.web.web.page : html;
import dfeed.web.web.perf;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.profile : profileUrl;
import dfeed.web.web.part.strings : summarizeTime;
import dfeed.web.web.postinfo : PostInfo, getPostInfo;
import dfeed.web.web.statics;
import dfeed.database;
import dfeed.message;
import dfeed.web.web.config : config;
import dfeed.web.web.user : user;

Cached!(ActiveDiscussion[]) activeDiscussionsCache;
Cached!(string[]) latestAnnouncementsCache;
enum framePostsLimit = 10;

static struct ActiveDiscussion { string id; int postCount; }

ActiveDiscussion[] getActiveDiscussions()
{
	enum PERF_SCOPE = "getActiveDiscussions"; mixin(MeasurePerformanceMixin);
	enum postCountLimit = 10;
	ActiveDiscussion[] result;
	foreach (string group, string firstPostID; query!"SELECT [Group], [ID] FROM [Threads] ORDER BY [Created] DESC LIMIT 100".iterate())
	{
		if (config.activeDiscussionExclude.canFind(group))
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
	if (!config.announceGroup.length)
		return null;
	string[] result;
	foreach (string firstPostID; query!"SELECT [ID] FROM [Threads] WHERE [Group] = ? ORDER BY [RowID] DESC LIMIT ?".iterate(config.announceGroup, framePostsLimit))
		result ~= firstPostID;
	return result;
}

void summarizeFrameThread(PostInfo* info, string infoText)
{
	if (info)
		with (*info)
		{
			putGravatar(getGravatarHash(info.authorEmail), author, profileUrl(author, authorEmail), _!`%s's profile`.format(author), `target="_top" class="forum-postsummary-gravatar" `);
			html.put(
				`<a target="_top" class="forum-postsummary-subject `, (user.isRead(rowid) ? "forum-read" : "forum-unread"), `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`">`), html.putEncodedEntities(subject), html.put(`</a><br>` ~
				`<div class="forum-postsummary-info">`, infoText, `</div>`,
				_!`by`, ` <span class="forum-postsummary-author">`), html.putEncodedEntities(author), html.put(`</span>`
			);
			return;
		}

	html.put(`<div class="forum-no-data">-</div>`);
}

void discussionFrameAnnouncements()
{
	if (!config.announceGroup.length)
	{
		html.put(`<div class="forum-no-data">`, _!`Announcements widget not configured`, `</div>`);
		return;
	}
	auto latestAnnouncements = latestAnnouncementsCache(getLatestAnnouncements());

	html.put(`<table class="forum-table"><thead><tr><th>` ~
		`<a target="_top" class="feed-icon" title="`, _!`Subscribe`, `" href="/feed/threads/`), html.putEncodedEntities(config.announceGroup), html.put(`"><img src="`, staticPath("/images/rss.png"),`"></img></a>` ~
		`<a target="_top" href="/group/`), html.putEncodedEntities(config.announceGroup), html.put(`">`, _!`Latest announcements`, `</a>` ~
		`</th></tr></thead><tbody>`);
	foreach (row; latestAnnouncements)
		if (auto info = getPostInfo(row))
			html.put(`<tr><td>`), summarizeFrameThread(info, summarizeTime(info.time)), html.put(`</td></tr>`);
	html.put(`</tbody></table>`);
}

void discussionFrameDiscussions()
{
	auto activeDiscussions = activeDiscussionsCache(getActiveDiscussions());

	html.put(`<table class="forum-table"><thead><tr><th><a target="_top" href="/">`, _!`Active discussions`, `</a></th></tr></thead><tbody>`);
	foreach (row; activeDiscussions)
		if (auto info = getPostInfo(row.id))
			html.put(`<tr><td>`), summarizeFrameThread(info, "%d posts".format(row.postCount)), html.put(`</td></tr>`);
	html.put(`</tbody></table>`);
}


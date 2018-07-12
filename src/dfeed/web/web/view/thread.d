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

/// Formatting threads.
module dfeed.web.web.view.thread;

import std.conv : text;
import std.datetime.systime : SysTime;
import std.exception : enforce;
import std.format;

import ae.utils.xmllite : putEncodedEntities;

import dfeed.database : query;
import dfeed.groups : GroupInfo;
import dfeed.message : idToUrl, Rfc850Post, getGroup;
import dfeed.web.web : PostInfo, getPostInfo, NotFoundException, html;
import dfeed.web.web.part.pager : pager, getPageCount, POSTS_PER_PAGE;
import dfeed.web.web.part.thread;
import dfeed.web.web.user : user;
import dfeed.web.web.view.post : formatPost;

// ***********************************************************************

void postPager(string threadID, int page, int postCount)
{
	pager(idToUrl(threadID, "thread"), page, getPageCount(postCount, POSTS_PER_PAGE));
}

int getPostCount(string threadID)
{
	foreach (int count; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?".iterate(threadID))
		return count;
	assert(0);
}

int getPostThreadIndex(string threadID, SysTime postTime)
{
	foreach (int index; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ? AND `Time` < ? ORDER BY `Time` ASC".iterate(threadID, postTime.stdTime))
		return index;
	assert(0);
}

int getPostThreadIndex(string postID)
{
	auto post = getPostInfo(postID);
	enforce(post, "No such post: " ~ postID);
	return getPostThreadIndex(post.threadID, post.time);
}

string getPostAtThreadIndex(string threadID, int index)
{
	foreach (string id; query!"SELECT `ID` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC LIMIT 1 OFFSET ?".iterate(threadID, index))
		return id;
	throw new NotFoundException(format("Post #%d of thread %s not found", index, threadID));
}

void discussionThread(string id, int page, out GroupInfo groupInfo, out string title, out string authorEmail, bool markAsRead)
{
	enforce(page >= 1, "Invalid page");

	auto postCount = getPostCount(id);

	if (page == 1 && postCount > 2)
	{
		// Expandable overview

		html.put(
			`<table id="thread-overview" class="forum-table forum-expand-container">` ~
			`<tr class="group-index-header"><th>`);

		auto pageCount = getPageCount(postCount, POSTS_PER_PAGE);
		if (pageCount > 1)
		{
			html.put(
				`<div class="thread-overview-pager forum-expand-container">` ~
				`Jump to page: <b>1</b> `
			);

			auto threadUrl = idToUrl(id, "thread");

			void pageLink(int n)
			{
				auto nStr = text(n);
				html.put(`<a href="`); html.putEncodedEntities(threadUrl); html.put(`?page=`, nStr, `">`, nStr, `</a> `);
			}

			if (pageCount < 4)
			{
				foreach (p; 2..pageCount+1)
					pageLink(p);
			}
			else
			{
				pageLink(2);
				html.put(`&hellip; `);
				pageLink(pageCount);

				html.put(
					`<a class="thread-overview-pager forum-expand-toggle">&nbsp;</a>` ~
					`<div class="thread-overview-pager-expanded forum-expand-content">` ~
					`<form action="`); html.putEncodedEntities(threadUrl); html.put(`">` ~
					`Page <input name="page" class="thread-overview-pager-pageno"> <input type="submit" value="Go">` ~
					`</form>` ~
					`</div>`
				);
			}

			html.put(
				`</div>`
			);
		}

		html.put(
			`<a class="forum-expand-toggle">Thread overview</a>` ~
			`</th></tr>`,
			`<tr class="forum-expand-content"><td class="group-threads-cell"><div class="group-threads"><table>`);
		formatThreadedPosts(getThreadPosts(id), false);
		html.put(`</table></div></td></tr></table>`);

	}

	Rfc850Post[] posts;
	foreach (int rowid, string postID, string message;
			query!"SELECT `ROWID`, `ID`, `Message` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC LIMIT ? OFFSET ?"
			.iterate(id, POSTS_PER_PAGE, (page-1)*POSTS_PER_PAGE))
		posts ~= new Rfc850Post(message, postID, rowid, id);

	Rfc850Post[string] knownPosts;
	foreach (post; posts)
		knownPosts[post.id] = post;

	enforce(posts.length, "Thread not found");

	groupInfo   = posts[0].getGroup();
	title       = posts[0].subject;
	authorEmail = posts[0].authorEmail;

	html.put(`<div id="thread-posts">`);
	foreach (post; posts)
		formatPost(post, knownPosts, markAsRead);
	html.put(`</div>`);

	if (page > 1 || postCount > POSTS_PER_PAGE)
	{
		html.put(`<table class="forum-table post-pager">`);
		postPager(id, page, postCount);
		html.put(`</table>`);
	}
}

string discussionFirstUnread(string threadID)
{
	foreach (int rowid, string id; query!"SELECT `ROWID`, `ID` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC".iterate(threadID))
		if (!user.isRead(rowid))
			return idToUrl(id);
	return idToUrl(threadID, "thread", getPageCount(getPostCount(threadID), POSTS_PER_PAGE));
}

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

/// Group index.
module dfeed.web.web.view.group;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.mutation : reverse;
import std.algorithm.searching;
import std.algorithm.sorting;
import std.array : replicate, replace, array, join;
import std.conv;
import std.datetime.systime : SysTime;
import std.datetime.timezone : UTC;
import std.exception : enforce;
import std.format;

import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.loc;
import dfeed.database : query;
import dfeed.groups;
import dfeed.message;
import dfeed.sinks.cache;
import dfeed.web.user : User;
import dfeed.web.web.cache : postCountCache, getPostCounts;
import dfeed.web.web.page : html;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.pager : THREADS_PER_PAGE, getPageOffset, threadPager, indexToPage, getPageCount, getPageCount, pager;
import dfeed.web.web.part.strings : formatTinyTime, formatShortTime, formatLongTime, summarizeTime, formatNumber;
import dfeed.web.web.part.thread : formatThreadedPosts;
import dfeed.web.web.postinfo : PostInfo, getPostInfo, getPost;
import dfeed.web.web.statics : staticPath;
import dfeed.web.web.user : user, userSettings;

int[] getThreadPostIndexes(string id)
{
	int[] result;
	foreach (int rowid; query!"SELECT `ROWID` FROM `Posts` WHERE `ThreadID` = ?".iterate(id))
		result ~= rowid;
	return result;
}

CachedSet!(string, int[]) threadPostIndexCache;

void newPostButton(GroupInfo groupInfo)
{
	html.put(
		`<form name="new-post-form" method="get" action="/newpost/`), html.putEncodedEntities(groupInfo.urlName), html.put(`">` ~
			`<div class="header-tools">` ~
				`<input class="btn" type="submit" value="`, _!`Create thread`, `">` ~
				`<input class="img" type="image" src="`, staticPath("/images/newthread.png"), `" alt="`, _!`Create thread`, `">` ~
			`</div>` ~
		`</form>`);
}

void discussionGroup(GroupInfo groupInfo, int page)
{
	enforce(page >= 1, _!"Invalid page");

	struct Thread
	{
		string id;
		PostInfo* _firstPost, _lastPost;
		int postCount, unreadPostCount;

		/// Handle orphan posts
		@property PostInfo* firstPost() { return _firstPost ? _firstPost : _lastPost; }
		@property PostInfo* lastPost() { return _lastPost; }

		@property bool isRead() { return unreadPostCount==0; }
	}

	Thread[] threads;
	threads.reserve(THREADS_PER_PAGE);

	int getUnreadPostCount(string id)
	{
		auto posts = threadPostIndexCache(id, getThreadPostIndexes(id));
		int count = 0;
		foreach (post; posts)
			if (!user.isRead(post))
				count++;
		return count;
	}

	foreach (string firstPostID, string lastPostID; query!"SELECT `ID`, `LastPost` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(groupInfo.internalName, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
		foreach (int count; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?".iterate(firstPostID))
		{
			if (count == 0 && user.getLevel() < User.Level.sysadmin)
			{
				// 0-count threads can occur after deleting the last post in a thread, and that post's message ID did not match the thread's.
				continue;
			}
			threads ~= Thread(firstPostID, getPostInfo(firstPostID), getPostInfo(lastPostID), count, getUnreadPostCount(firstPostID));
		}

	void summarizeThread(string tid, PostInfo* info, bool isRead)
	{
		if (info)
			with (*info)
			{
				putGravatar(getGravatarHash(info.authorEmail), author, idToUrl(tid, "thread"), null, `class="forum-postsummary-gravatar" `);
				html.put(
				//	`<!-- Thread ID: ` ~ encodeHtmlEntities(threadID) ~ ` | First Post ID: ` ~ encodeHtmlEntities(id) ~ `-->` ~
					`<div class="truncated"><a class="forum-postsummary-subject `, (isRead ? "forum-read" : "forum-unread"), `" href="`), html.putEncodedEntities(idToUrl(tid, "thread")), html.put(`" title="`), html.putEncodedEntities(subject), html.put(`">`), html.putEncodedEntities(subject), html.put(`</a></div>` ~
					`<div class="truncated">`, _!`by`, ` <span class="forum-postsummary-author" title="`), html.putEncodedEntities(author), html.put(`">`), html.putEncodedEntities(author), html.put(`</span></div>`);
				return;
			}

		html.put(`<div class="forum-no-data">-</div>`);
	}

	void summarizeLastPost(PostInfo* info)
	{
		if (info)
			with (*info)
			{
				html.put(
					`<a class="forum-postsummary-time `, user.isRead(rowid) ? "forum-read" : "forum-unread", `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`">`, summarizeTime(time), `</a>` ~
					`<div class="truncated">`, _!`by`, ` <span class="forum-postsummary-author" title="`), html.putEncodedEntities(author), html.put(`">`), html.putEncodedEntities(author), html.put(`</span></div>`);
				return;
			}
		html.put(`<div class="forum-no-data">-</div>`);
	}

	void summarizePostCount(ref Thread thread)
	{
		html.put(`<a class="secretlink" href="`), html.putEncodedEntities(idToUrl(thread.id, "thread")), html.put(`">`);
		if (thread.unreadPostCount == 0)
			html ~= formatNumber(thread.postCount-1);
		else
			html.put(`<b>`, formatNumber(thread.postCount-1), `</b>`);
		html.put(`</a>`);

		if (thread.unreadPostCount && thread.unreadPostCount != thread.postCount)
			html.put(
				`<br>(<a href="`, idToUrl(thread.id, "first-unread"), `">`, formatNumber(thread.unreadPostCount), ` new</a>)`);
	}

	html.put(
		`<table id="group-index" class="forum-table">` ~
		`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(3), `</tr>` ~ // Fixed layout dummies
		`<tr class="group-index-header"><th colspan="3"><div class="header-with-tools">`), newPostButton(groupInfo), html.putEncodedEntities(groupInfo.publicName), html.put(`</div></th></tr>` ~
		`<tr class="subheader"><th>`, _!`Thread / Thread Starter`, `</th><th>`, _!`Last Post`, `</th><th>`, _!`Replies`, `</th>`);
	foreach (thread; threads)
		html.put(
			`<tr class="thread-row">` ~
				`<td class="group-index-col-first">`), summarizeThread(thread.id, thread.firstPost, thread.isRead), html.put(`</td>` ~
				`<td class="group-index-col-last">`), summarizeLastPost(thread.lastPost), html.put(`</td>` ~
				`<td class="number-column">`), summarizePostCount(thread), html.put(`</td>` ~
			`</tr>`);
	threadPager(groupInfo, page);
	html.put(
		`</table>`
	);
}

void discussionGroupNarrowIndex(GroupInfo groupInfo, int page)
{
	enforce(page >= 1, _!"Invalid page");

	struct Thread
	{
		string id;
		PostInfo* _firstPost, _lastPost;
		int postCount, unreadPostCount;

		/// Handle orphan posts
		@property PostInfo* firstPost() { return _firstPost ? _firstPost : _lastPost; }
		@property PostInfo* lastPost() { return _lastPost; }

		@property bool isRead() { return unreadPostCount == 0; }
	}

	Thread[] threads;
	threads.reserve(THREADS_PER_PAGE);

	int getUnreadPostCount(string id)
	{
		auto posts = threadPostIndexCache(id, getThreadPostIndexes(id));
		int count = 0;
		foreach (post; posts)
			if (!user.isRead(post))
				count++;
		return count;
	}

	foreach (string firstPostID, string lastPostID; query!"SELECT `ID`, `LastPost` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(groupInfo.internalName, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
		foreach (int count; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?".iterate(firstPostID))
		{
			if (count == 0 && user.getLevel() < User.Level.sysadmin)
			{
				// 0-count threads can occur after deleting the last post in a thread, and that post's message ID did not match the thread's.
				continue;
			}
			threads ~= Thread(firstPostID, getPostInfo(firstPostID), getPostInfo(lastPostID), count, getUnreadPostCount(firstPostID));
		}

	void summarizeThread(ref Thread thread)
	{
		html.put(`<div class="thread">` ~
			`<div class="title">` ~
			`<a ` ~
			`class="`, thread.isRead ? "forum-read" : "forum-unread", `" ` ~
			`href="`);
		html.putEncodedEntities(idToUrl(thread.id, "thread"));
		html.put(`" title="`);
		html.putEncodedEntities(thread.firstPost.subject);
		html.put(`">`);
		html.putEncodedEntities(thread.firstPost.subject);
		html.put(`</a>` ~
			`</div>` ~
			`<time class="firstpost-time" ` ~
			`datetime="`);
		html.putEncodedEntities(thread.firstPost.time.formatTimeLoc!"c");
		html.put(`" ` ~
			`title="`);
		html.putEncodedEntities(thread.firstPost.time.formatTimeLoc!"l, d F Y, H:i:s e");
		html.put(`">` ~
			`<span class="short">`);
		html.putEncodedEntities(formatTinyTime(thread.firstPost.time));
		html.put(`</span>` ~
			`<span class="long">`);
		html.putEncodedEntities(formatShortTime(thread.firstPost.time, false));
		html.put(`</span>` ~
			`</time>` ~
			`<img  class="firstpost-author-image" src="//www.gravatar.com/avatar/`, getGravatarHash(thread.firstPost.authorEmail), `?d=identicon">` ~
			`<div class="firstpost-author-name">`);
		html.putEncodedEntities(thread.firstPost.author);
		html.put(`</div>` ~
			`<div class="replies-total">` ~
			`<span class="short">`,
			formatNumber(thread.postCount - 1),
			`</span>` ~
			`<span class="long">`,
			formatNumber(thread.postCount - 1), " ", (thread.postCount - 1) == 1 ? _!"reply" : _!"replies");
		html.put(`</span>` ~
			`</div>` ~
			`<div class="replies-new">` ~
			`<span class="short">`);
		if (thread.unreadPostCount && thread.unreadPostCount != thread.postCount)
			html.put(`(<a href="`, idToUrl(thread.id, "first-unread"), `">`, formatNumber(thread.unreadPostCount), `</a>)`);
		html.put(`</span>` ~
			`<span class="long">`);
		if (thread.unreadPostCount && thread.unreadPostCount != thread.postCount)
			html.put(`<a href="`, idToUrl(thread.id, "first-unread"), `">`, formatNumber(thread.unreadPostCount), ` `, _!`new`, `</a>`);
		html.put(`</span>` ~
			`</div>` ~
			`<div class="lastpost-time">` ~
			`<a ` ~
			`href="`);
		html.putEncodedEntities(idToUrl(thread.lastPost.id));
		html.put(`">`,
			`<span class="last">`,
			_!`Last`,
			`: ` ~
			`</span>` ~
			`<span class="last-post">`,
			_!`Last Post`,
			`: ` ~
			`</span>` ~
			`<time ` ~
			`datetime="`);
		html.putEncodedEntities(thread.lastPost.time.formatTimeLoc!"c");
		html.put(`" ` ~
			`title="`);
		html.putEncodedEntities(thread.lastPost.time.formatTimeLoc!"l, d F Y, H:i:s e");
		html.put(`">` ~
			`<span class="short">`);
		html.putEncodedEntities(formatTinyTime(thread.lastPost.time));
		html.put(`</span>` ~
			`<span class="long">`);
		html.putEncodedEntities(formatShortTime(thread.lastPost.time, false));
		html.put(`</span>` ~
			`</time>` ~
			`</a>` ~
			`</div>` ~
			`<div class="lastpost-author">` ~
			`<img class="lastpost-author-image" src="//www.gravatar.com/avatar/`, getGravatarHash(thread.lastPost.authorEmail), `?d=identicon">`);
		html.put(`<span class="lastpost-author-name">`);
		html.putEncodedEntities(thread.lastPost.author);
		html.put(`</span>` ~
			`</div>` ~
			`</div>`);
	}
	
	html.put(`<div class="viewmode-narrow-index">` ~
		`<div class="group-index-header">` ~
		`<div class="title">`);
	html.putEncodedEntities(groupInfo.publicName);
	html.put(`</div>` ~
		`<div class="create-thread">`);
	html.put(`<a class="button" href="/newpost/`);
	html.putEncodedEntities(groupInfo.urlName);
	html.put(`">` ~
		`<img src="`, staticPath("/images/newthread.png"), `"> `);
	html.put(_!`Create thread`);
	html.put(`</a>` ~
		`</div>` ~
		`</div>`);
	
	html.put(`<div class="group-index">`);
	foreach (thread; threads)
		summarizeThread(thread);
	html.put(`</div>`);
	
	threadPager(groupInfo, page);
	html.put(`</div>`);
}

// ***********************************************************************

void discussionGroupThreaded(GroupInfo groupInfo, int page, bool narrow = false)
{
	enforce(page >= 1, _!"Invalid page");

	//foreach (string threadID; query!"SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
	//	foreach (string id, string parent, string author, string subject, long stdTime; query!"SELECT `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?".iterate(threadID))
	PostInfo*[] posts;
	enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` IN (SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?)";
	foreach (int rowid, string id, string parent, string author, string authorEmail, string subject, long stdTime; query!ViewSQL.iterate(groupInfo.internalName, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
		posts ~= [PostInfo(rowid, id, null, parent, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr; // TODO: optimize?

	html.put(
		`<table id="group-index-threaded" class="forum-table group-wrapper viewmode-`), html.putEncodedEntities(userSettings.groupViewMode), html.put(`">` ~
		`<tr class="group-index-header"><th><div>`), newPostButton(groupInfo), html.putEncodedEntities(groupInfo.publicName), html.put(`</div></th></tr>`,
	//	`<tr class="group-index-captions"><th>Subject / Author</th><th>Time</th>`,
		`<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
	formatThreadedPosts(posts, narrow);
	html.put(`</table></div></td></tr>`);
	threadPager(groupInfo, page, narrow ? 25 : 50);
	html.put(`</table>`);
}

void discussionGroupSplit(GroupInfo groupInfo, int page)
{
	html.put(
		`<table id="group-split"><tr>` ~
		`<td id="group-split-list"><div>`);
	discussionGroupThreaded(groupInfo, page, true);
	html.put(
		`</div></td>` ~
		`<td id="group-split-message" class="group-split-message-none"><span>`,
			_!`Loading...`,
			`<div class="nojs">`, _!`Sorry, this view requires JavaScript.`, `</div>` ~
		`</span></td>` ~
		`</tr></table>`);
}

void discussionGroupSplitFromPost(string id, out GroupInfo groupInfo, out int page, out string threadID)
{
	auto post = getPost(id);
	enforce(post, _!"Post not found");

	groupInfo = post.getGroup();
	enforce(groupInfo, _!"Unknown group:" ~ " " ~ post.where);
	threadID = post.cachedThreadID;
	page = getThreadPage(groupInfo, threadID);

	discussionGroupSplit(groupInfo, page);
}

int getThreadPage(GroupInfo groupInfo, string thread)
{
	int page = 0;

	foreach (long time; query!"SELECT `LastUpdated` FROM `Threads` WHERE `ID` = ? LIMIT 1".iterate(thread))
		foreach (int threadIndex; query!"SELECT COUNT(*) FROM `Threads` WHERE `Group` = ? AND `LastUpdated` > ? ORDER BY `LastUpdated` DESC".iterate(groupInfo.internalName, time))
			page = indexToPage(threadIndex, THREADS_PER_PAGE);

	enforce(page > 0, _!"Can't find thread's page");
	return page;
}

// ***********************************************************************

void formatVSplitPosts(PostInfo*[] postInfos, string selectedID = null)
{
/*
	html.put(
		`<tr class="thread-post-row">` ~
			`<th>Subject</th>` ~
			`<th>From</th>` ~
		`</tr>`
	);
*/

	foreach (postInfo; postInfos)
	{
		html.put(
			`<tr class="thread-post-row`, (postInfo && postInfo.id==selectedID ? ` focused selected` : ``), `">` ~
				`<td>` ~
					`<a class="postlink `, (user.isRead(postInfo.rowid) ? "forum-read" : "forum-unread" ), `" ` ~
						`href="`), html.putEncodedEntities(idToUrl(postInfo.id)), html.put(`">`
						), html.putEncodedEntities(postInfo.subject), html.put(
					`</a>` ~
				`</td>` ~
				`<td>`
					), html.putEncodedEntities(postInfo.author), html.put(
				`</td>` ~
				`<td>` ~
					`<div class="thread-post-time">`, summarizeTime(postInfo.time, true), `</div>`,
				`</td>` ~
			`</tr>`
		);
	}
}

enum POSTS_PER_GROUP_PAGE = 100;

void discussionGroupVSplitList(GroupInfo groupInfo, int page)
{
	enum postsPerPage = POSTS_PER_GROUP_PAGE;
	enforce(page >= 1, _!"Invalid page");

	//foreach (string threadID; query!"SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
	//	foreach (string id, string parent, string author, string subject, long stdTime; query!"SELECT `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?".iterate(threadID))
	PostInfo*[] posts;
	//enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` IN (SELECT `ID` FROM `Threads` WHERE `Group` = ?) ORDER BY `Time` DESC LIMIT ? OFFSET ?";
	//enum ViewSQL = "SELECT [Posts].[ROWID], [Posts].[ID], `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` "
	//	"INNER JOIN [Threads] ON `ThreadID`==[Threads].[ID] WHERE `Group` = ? ORDER BY `Time` DESC LIMIT ? OFFSET ?";
	enum ViewSQL = "SELECT [Posts].[ROWID], [Posts].[ID], [ParentID], [Author], [AuthorEmail], [Subject], [Posts].[Time] FROM [Groups] " ~
		"INNER JOIN [Posts] ON [Posts].[ID]==[Groups].[ID] WHERE [Group] = ? ORDER BY [Groups].[Time] DESC LIMIT ? OFFSET ?";
	foreach (int rowid, string id, string parent, string author, string authorEmail, string subject, long stdTime; query!ViewSQL.iterate(groupInfo.internalName, postsPerPage, getPageOffset(page, postsPerPage)))
		posts ~= [PostInfo(rowid, id, null, parent, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr; // TODO: optimize?
	posts.reverse();

	html.put(
		`<table id="group-index-vsplit" class="forum-table group-wrapper viewmode-`), html.putEncodedEntities(userSettings.groupViewMode), html.put(`">` ~
		`<tr class="group-index-header"><th><div>`), newPostButton(groupInfo), html.putEncodedEntities(groupInfo.publicName), html.put(`</div></th></tr>`,
	//	`<tr class="group-index-captions"><th>Subject / Author</th><th>Time</th>`,
		`<tr><td class="group-threads-cell"><div class="group-threads"><table id="group-posts-vsplit">` ~
		`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(3), `</tr>` // Fixed layout dummies
	);
	formatVSplitPosts(posts);
	html.put(`</table></div></td></tr>`);
	groupPostPager(groupInfo, page);
	html.put(`</table>`);
}

void discussionGroupVSplit(GroupInfo groupInfo, int page)
{
	html.put(
		`<table id="group-vsplit"><tr>` ~
		`<td id="group-vsplit-list"><div>`);
	discussionGroupVSplitList(groupInfo, page);
	html.put(
		`</div></td></tr>` ~
		`<tr><td id="group-split-message" class="group-split-message-none">`,
			_!`Loading...`,
			`<div class="nojs">`, _!`Sorry, this view requires JavaScript.`, `</div>` ~
		`</td>` ~
		`</tr></table>`);
}

int getVSplitPostPage(GroupInfo groupInfo, string id)
{
	int page = 0;

	foreach (long time; query!"SELECT [Time] FROM [Groups] WHERE [ID] = ? LIMIT 1".iterate(id))
		foreach (int threadIndex; query!"SELECT COUNT(*) FROM [Groups] WHERE [Group] = ? AND [Time] > ? ORDER BY [Time] DESC".iterate(groupInfo.internalName, time))
			page = indexToPage(threadIndex, POSTS_PER_GROUP_PAGE);

	enforce(page > 0, _!"Can't find post's page");
	return page;
}

void discussionGroupVSplitFromPost(string id, out GroupInfo groupInfo, out int page, out string threadID)
{
	auto post = getPost(id);
	enforce(post, _!"Post not found");

	groupInfo = post.getGroup();
	threadID = post.cachedThreadID;
	page = getVSplitPostPage(groupInfo, id);

	discussionGroupVSplit(groupInfo, page);
}

void groupPostPager(GroupInfo groupInfo, int page)
{
	auto postCounts = postCountCache(getPostCounts());
	auto postCount = postCounts.get(groupInfo.internalName, 0);
	auto pageCount = getPageCount(postCount, POSTS_PER_GROUP_PAGE);

	pager(`/group/` ~ groupInfo.urlName, page, pageCount, 50);
}

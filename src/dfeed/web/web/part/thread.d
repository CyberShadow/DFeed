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

/// Formatting threads.
module dfeed.web.web.part.thread;

import std.algorithm.comparison : min;
import std.algorithm.sorting : sort;
import std.datetime.systime : SysTime;
import std.datetime.timezone : UTC;
import std.format : format;

import ae.utils.xmllite : putEncodedEntities;

import dfeed.loc;
import dfeed.database : query;
import dfeed.message : idToUrl;
import dfeed.web.web.page : html;
import dfeed.web.web.perf;
import dfeed.web.web.postinfo : PostInfo, getPost;
import dfeed.web.web.user : user, userSettings;
import dfeed.web.web.part.profile : profileUrl;
import dfeed.web.web.part.strings : summarizeTime, truncateString;

string[][string] referenceCache; // invariant

void formatThreadedPosts(PostInfo*[] postInfos, bool narrow, string selectedID = null)
{
	enum OFFSET_INIT = 1f;
	enum OFFSET_MAX = 2f;
	enum OFFSET_WIDTH = 25f;
	enum OFFSET_UNITS = "%";

	class Post
	{
		PostInfo* info;
		Post parent;

		SysTime maxTime;
		Post[] children;
		int maxDepth;

		bool ghost; // dummy parent for orphans
		string ghostSubject;

		@property string subject() { return ghostSubject ? ghostSubject : info.subject; }

		this(PostInfo* info = null) { this.info = info; }

		void calcStats()
		{
			foreach (child; children)
				child.calcStats();

			if (info)
				maxTime = info.time;
			foreach (child; children)
				if (maxTime < child.maxTime)
					maxTime = child.maxTime;
			//maxTime = reduce!max(time, map!"a.maxTime"(children));

			maxDepth = 1;
			foreach (child; children)
				if (maxDepth < 1 + child.maxDepth)
					maxDepth = 1 + child.maxDepth;
		}
	}

	Post[string] posts;
	foreach (info; postInfos)
		posts[info.id] = new Post(info);

	// Check if linking child under parent would create a cycle
	// by walking up parent's ancestor chain
	bool wouldCreateCycle(Post child, Post parent)
	{
		for (Post p = parent; p !is null; p = p.parent)
			if (p is child)
				return true;
		return false;
	}

	posts[null] = new Post();
	foreach (post; posts.values)
		if (post.info)
		{
			auto parent = post.info.parentID;
			// Parent missing or would create cycle - find alternate parent
			if (parent !in posts || wouldCreateCycle(post, posts[parent]))
			{
				string[] references;
				if (post.info.id in referenceCache)
					references = referenceCache[post.info.id];
				else
					references = referenceCache[post.info.id] = getPost(post.info.id).references;

				// Search References header for any ancestor in this thread
				parent = null;
				foreach_reverse (reference; references)
					if (reference in posts && !wouldCreateCycle(post, posts[reference]))
					{
						parent = reference;
						break;
					}

				// No valid parent found - create ghost post for missing parent
				if (!parent && references.length)
				{
					auto dummy = new Post;
					dummy.ghost = true;
					dummy.ghostSubject = post.info.subject; // HACK
					parent = references[0];
					posts[parent] = dummy;
					dummy.parent = posts[null];
					posts[null].children ~= dummy;
				}
			}
			// Link post to its parent (or root if none was found)
			post.parent = posts[parent];
			posts[parent].children ~= post;
		}

	bool reversed = userSettings.groupViewMode == "threaded";
	posts[null].calcStats();
	foreach (post; posts)
	{
		if (post.info || post.ghost)
			sort!"a.info.time < b.info.time"(post.children);
		else // sort threads by last-update
		if (reversed)
			sort!"a.maxTime > b.maxTime"(post.children);
		else
			sort!"a.maxTime < b.maxTime"(post.children);
	}

	float offsetIncrement; // = max(1f, min(OFFSET_MAX, OFFSET_WIDTH / posts[null].maxDepth));

	string normalizeSubject(string s)
	{
		import std.array : replace;
		import std.algorithm.searching : skipOver;

		s.skipOver("Re: ");
		return s
			.replace("New: ", "") // Bugzilla hack
			.replace("\t", " ")   // Apple Mail hack
			.replace(" ", "")     // Outlook Express hack
		;
	}

	// Group replies under a ghost post when multiple replies have the same subject,
	// but different from their parent (Bugzilla hack)
	foreach (thread; posts[null].children)
	{
		for (int i=1; i<thread.children.length; )
		{
			auto child = thread.children[i];
			auto prevChild = thread.children[i-1];
			if (normalizeSubject(child.subject) != normalizeSubject(thread.subject) &&
				normalizeSubject(child.subject) == normalizeSubject(prevChild.subject))
			{
				if (prevChild.ghost) // add to the existing ghost
				{
					child.parent = prevChild;
					prevChild.children ~= child;
					thread.children = thread.children[0..i] ~ thread.children[i+1..$];
				}
				else // new ghost
				{
					auto dummy = new Post;
					dummy.ghost = true;
					dummy.ghostSubject = child.subject;
					prevChild.parent = child.parent = dummy;
					dummy.children = [prevChild, child];
					dummy.parent = thread;
					thread.children = thread.children[0..i-1] ~ dummy ~ thread.children[i+1..$];
				}
			}
			else
				i++;
		}
	}

	void formatPosts(Post[] posts, int level, string parentSubject, bool topLevel)
	{
		void formatPost(Post post, int level)
		{
			import std.format : format;

			if (post.ghost)
				return formatPosts(post.children, level, post.subject, false);
			html.put(
				`<tr class="thread-post-row`, (post.info && post.info.id==selectedID ? ` focused selected` : ``), `">` ~
					`<td>` ~
						`<div style="padding-left: `, format("%1.1f", OFFSET_INIT + level * offsetIncrement), OFFSET_UNITS, `">` ~
							`<div class="thread-post-time">`, summarizeTime(post.info.time, true), `</div>`,
							`<a class="postlink `, (user.isRead(post.info.rowid) ? "forum-read" : "forum-unread" ), `" href="`), html.putEncodedEntities(idToUrl(post.info.id)), html.put(`">`, truncateString(post.info.author, narrow ? 17 : 50), `</a>` ~
						`</div>` ~
					`</td>` ~
				`</tr>`);
			formatPosts(post.children, level+1, post.subject, false);
		}

		foreach (post; posts)
		{
			if (topLevel)
				offsetIncrement = min(OFFSET_MAX, OFFSET_WIDTH / post.maxDepth);

			if (topLevel || normalizeSubject(post.subject) != normalizeSubject(parentSubject))
			{
				auto offsetStr = format("%1.1f", OFFSET_INIT + level * offsetIncrement) ~ OFFSET_UNITS;
				html.put(
					`<tr><td style="padding-left: `, offsetStr, `">` ~
					`<table class="thread-start">` ~
						`<tr><th>`), html.putEncodedEntities(post.subject), html.put(`</th></tr>`);
                formatPost(post, 0);
				html.put(
					`</table>` ~
					`</td></tr>`);
			}
			else
				formatPost(post, level);
		}
	}

	formatPosts(posts[null].children, 0, null, true);
}

// ***********************************************************************

PostInfo*[] getThreadPosts(string threadID)
{
	PostInfo*[] posts;
	enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?";
	foreach (int rowid, string id, string parent, string author, string authorEmail, string subject, long stdTime; query!ViewSQL.iterate(threadID))
		posts ~= [PostInfo(rowid, id, null, parent, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr;
	return posts;
}

void discussionThreadOverview(string threadID, string selectedID)
{
	enum PERF_SCOPE = "discussionThreadOverview"; mixin(MeasurePerformanceMixin);
	html.put(
		`<table id="thread-index" class="forum-table group-wrapper viewmode-`), html.putEncodedEntities(userSettings.groupViewMode), html.put(`">` ~
		`<tr class="group-index-header"><th><div>` ~ _!`Thread overview` ~ `</div></th></tr>`,
		`<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
	formatThreadedPosts(getThreadPosts(threadID), false, selectedID);
	html.put(`</table></div></td></tr></table>`);
}


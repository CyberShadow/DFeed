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

/// Post data and lookup.
module dfeed.web.web.postinfo;

import ae.net.ietf.message : Rfc850Message;

import std.algorithm.searching : startsWith, endsWith;
import std.datetime.systime : SysTime;
import std.datetime.timezone : UTC;
import std.exception : enforce;

import dfeed.loc;
import dfeed.database : query, selectValue;
import dfeed.message : Rfc850Post, idToUrl, idToFragment;
import dfeed.sinks.cache : CachedSet;
import dfeed.web.web.page : NotFoundException;
import dfeed.web.web.part.pager : indexToPage, POSTS_PER_PAGE;
import dfeed.web.web.view.thread : getPostThreadIndex;

string resolvePostUrl(string id)
{
	foreach (string threadID; query!"SELECT `ThreadID` FROM `Posts` WHERE `ID` = ?".iterate(id))
		return idToThreadUrl(id, threadID);

	throw new NotFoundException(_!"Post not found");
}

string idToThreadUrl(string id, string threadID)
{
	return idToUrl(threadID, "thread", indexToPage(getPostThreadIndex(id), POSTS_PER_PAGE)) ~ "#" ~ idToFragment(id);
}

static Rfc850Post getPost(string id)
{
	foreach (int rowid, string message, string threadID; query!"SELECT `ROWID`, `Message`, `ThreadID` FROM `Posts` WHERE `ID` = ?".iterate(id))
		return new Rfc850Post(message, id, rowid, threadID);
	return null;
}

static Rfc850Message getPostPart(string id, uint[] partPath = null)
{
	foreach (string message; query!"SELECT `Message` FROM `Posts` WHERE `ID` = ?".iterate(id))
	{
		auto post = new Rfc850Message(message);
		while (partPath.length)
		{
			enforce(partPath[0] < post.parts.length, _!"Invalid attachment");
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

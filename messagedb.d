/*  Copyright (C) 2011, 2012, 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module messagedb;

import std.conv;
import std.string;

import ae.sys.log;

import common;
import database;
import message;

final class MessageDBSink : NewsSink
{
	alias Update = Flag!"update";

	this(Update update=Update.no)
	{
		log = createLogger("MessageDBSink");
		this.update = update;
	}

private:
    Logger log;
    Update update;

protected:
	override void handlePost(Post post, Fresh fresh)
	{
		auto message = cast(Rfc850Post)post;
		if (!message)
			return;

		scope(success)
		{
			if (transactionDepth == 1) // This is a batch operation
				if (flushTransactionEvery(50))
					log("Transaction flushed");
		}

		log(format("Saving message %s (%s)", message.id, message.where));
		mixin(DB_TRANSACTION);

		if (!message.rowid)
			foreach (int postRowid; query!"SELECT `ROWID` FROM `Posts` WHERE `ID` = ?".iterate(message.id))
				message.rowid = postRowid;

		if (message.rowid)
		{
			log(format("Message %s already present with ROWID=%d", message.id, message.rowid));
			if (update)
			{
				query!"UPDATE [Posts] SET [ID]=?, [Message]=?, [Author]=?, [AuthorEmail]=?, [Subject]=?, [Time]=?, [ParentID]=?, [ThreadID]=? WHERE [ROWID] = ?"
					.exec(message.id, message.message, message.author, message.authorEmail, message.subject, message.time.stdTime, message.parentID, message.threadID, message.rowid);
				log("Updated.");
			}
		}
		else
		{
			query!"INSERT INTO `Posts` (`ID`, `Message`, `Author`, `AuthorEmail`, `Subject`, `Time`, `ParentID`, `ThreadID`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
				.exec(message.id, message.message, message.author, message.authorEmail, message.subject, message.time.stdTime, message.parentID, message.threadID);
			message.rowid = db.lastInsertRowID.to!int;
			log(format("Message %s saved with ROWID=%d", message.id, message.rowid));
		}

		foreach (xref; message.xref)
		{
			query!"INSERT OR IGNORE INTO `Groups` (`Group`, `ArtNum`, `ID`, `Time`) VALUES (?, ?, ?, ?)"
				.exec(xref.group, xref.num, message.id, message.time.stdTime);

			long threadIndex = 0, lastUpdated;
			foreach (long rowid, long updated; query!"SELECT `ROWID`, `LastUpdated` FROM `Threads` WHERE `ID` = ? AND `Group` = ?".iterate(message.threadID, xref.group))
				threadIndex = rowid, lastUpdated = updated;

			if (!threadIndex) // new thread
				query!"INSERT INTO `Threads` (`Group`, `ID`, `LastPost`, `LastUpdated`) VALUES (?, ?, ?, ?)".exec(xref.group, message.threadID, message.id, message.time.stdTime);
			else
			if (lastUpdated < message.time.stdTime)
				query!"UPDATE `Threads` SET `LastPost` = ?, `LastUpdated` = ? WHERE `ROWID` = ?".exec(message.id, message.time.stdTime, threadIndex);
		}
	}

public:
	void updatePost(Rfc850Post message)
	{
		log(format("Updating message %s (%s)", message.id, message.where));

		query!"UPDATE `Posts` SET `Message`=?, `Author`=?, `AuthorEmail`=?, `Subject`=?, `Time`=?, `ParentID`=?, `ThreadID`=? WHERE `ID` = ?"
			.exec(message.message, message.author, message.authorEmail, message.subject, message.time.stdTime, message.parentID, message.threadID, message.id);
	}
}

/// Look up the real thread ID of a post, by travelling
/// up the chain of the first known ancestor IDs.
string getThreadID(string id)
{
	static string[string] cache;
	auto pcached = id in cache;
	if (pcached)
		return *pcached;

	string result = id;
	foreach (string threadID; query!"SELECT [ThreadID] FROM [Posts] WHERE [ID] = ?".iterate(id))
		result = threadID;

	if (result != id)
		result = getThreadID(result);
	return cache[id] = result;
}

@property string threadID(Rfc850Post post)
{
	return getThreadID(post.firstAncestorID);
}

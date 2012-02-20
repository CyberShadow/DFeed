/*  Copyright (C) 2011, 2012  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.string;

import ae.sys.log;

import common;
import database;
import rfc850;

final class MessageDBSink : NewsSink
{
	this()
	{
		log = createLogger("MessageDBSink");
	}

private:
    Logger log;

protected:
	override void handlePost(Post post)
	{
		auto message = cast(Rfc850Post)post;
		if (!message)
			return;

		log(format("Saving message %s (%s)", message.id, message.where));
		mixin(DB_TRANSACTION);

		long rowid = -1;
		foreach (long postRowid; query("SELECT `ROWID` FROM `Posts` WHERE `ID` = ?").iterate(message.id))
			rowid = postRowid;

		if (rowid >= 0)
			log(format("Message %s already present with ROWID=%d", message.id, rowid));
		else
		{
			query("INSERT INTO `Posts` (`ID`, `Message`, `Author`, `Subject`, `Time`, `ParentID`, `ThreadID`) VALUES (?, ?, ?, ?, ?, ?, ?)")
				.exec(message.id, message.message, message.author, message.subject, message.time.stdTime, message.parentID, message.threadID);
			log(format("Message %s saved with ROWID=%d", message.id, db.lastInsertRowID));
		}

		foreach (xref; message.xref)
		{
			query("INSERT OR IGNORE INTO `Groups` (`Group`, `ArtNum`, `ID`, `Time`) VALUES (?, ?, ?, ?)")
				.exec(xref.group, xref.num, message.id, message.time.stdTime);

			long threadIndex = 0, lastUpdated;
			foreach (long rowid, long updated; query("SELECT `ROWID`, `LastUpdated` FROM `Threads` WHERE `ID` = ? AND `Group` = ?").iterate(message.threadID, xref.group))
				threadIndex = rowid, lastUpdated = updated;

			if (!threadIndex) // new thread
				query("INSERT INTO `Threads` (`Group`, `ID`, `LastPost`, `LastUpdated`) VALUES (?, ?, ?, ?)").exec(xref.group, message.threadID, message.id, message.time.stdTime);
			else
			if (lastUpdated < message.time.stdTime)
				query("UPDATE `Threads` SET `LastPost` = ?, `LastUpdated` = ? WHERE `ROWID` = ?").exec(message.id, message.time.stdTime, threadIndex);
		}
	}

public:
	void updatePost(Rfc850Post message)
	{
		log(format("Updating message %s (%s)", message.id, message.where));

		query("UPDATE `Posts` SET `Message`=?, `Author`=?, `Subject`=?, `Time`=?, `ParentID`=?, `ThreadID`=? WHERE `ID` = ?")
			.exec(message.message, message.author, message.subject, message.time.stdTime, message.parentID, message.threadID, message.id);
	}
}

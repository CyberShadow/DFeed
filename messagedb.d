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

		query("INSERT OR IGNORE INTO `Posts` (`ID`, `Message`, `Author`, `Subject`, `Time`, `ParentID`, `ThreadID`) VALUES (?, ?, ?, ?, ?, ?, ?)")
			.exec(message.id, message.lines, message.author, message.subject, message.time.stdTime, message.parentID, message.threadID);

		foreach (xref; message.xref)
		{
			// The purpose of the "Groups" table is to handle redirects from the old PHP web newsreaders.
			query("INSERT OR IGNORE INTO `Groups` (`Group`, `ArtNum`, `ID`) VALUES (?, ?, ?)")
				.exec(xref.group, xref.num, message.id);

			long threadIndex = 0, lastUpdated;
			auto threadSelect = query("SELECT `ROWID`, `LastUpdated` FROM `Threads` WHERE `ID` = ? AND `Group` = ?");
			threadSelect.bindAll(message.threadID, xref.group);
			while (threadSelect.step())
				threadSelect.columns(threadIndex, lastUpdated);

			if (!threadIndex) // new thread
				query("INSERT INTO `Threads` (`Group`, `ID`, `LastUpdated`) VALUES (?, ?, ?)").exec(xref.group, message.threadID, message.time.stdTime);
			else
			if (lastUpdated < message.time.stdTime)
				query("UPDATE `Threads` SET `LastUpdated` = ? WHERE `ROWID` = ?").exec(message.time.stdTime, threadIndex);
		}
	}
}

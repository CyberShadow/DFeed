module messagedb;

import std.string;

import ae.utils.log;

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
			query("INSERT OR IGNORE INTO `Groups` (`Group`, `ArtNum`, `ID`) VALUES (?, ?, ?)")
				.exec(xref.group, xref.num, message.id);
	}
}

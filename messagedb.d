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

		log(format("Saving message %s (%s:%s)", message.id, message.where, message.num));
		auto insert = query("INSERT INTO `Posts` (`Group`, `ArtNum`, `ID`, `Message`, `Author`, `Subject`, `Time`, `ParentID`, `ThreadID`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
		insert.exec(message.where, message.num, message.id, message.lines, message.author, message.subject, message.time.stdTime, message.parentID, message.threadID);
	}
}

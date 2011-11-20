module rebuilddb;

import std.getopt;

import common;
import database;
import messagedb;
import rfc850;

/// Dummy/test source used for rebuilding the message database.
class DatabaseSource : NewsSource
{
	this()
	{
		super("DatabaseSource");
	}

	override void start()
	{
		auto select = query("SELECT `Message`, `ID` FROM `OldPosts`");
		while (select.step())
		{
			string message, id;
			select.columns(message, id);
			log("Announcing: " ~ id);
			announcePost(new Rfc850Post(message, id));
		}
	}
}

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	//db.exec("DROP TABLE IF EXISTS `OldPosts`");
	//db.exec("ALTER TABLE `Posts` RENAME TO `OldPosts`");
	db.exec("SELECT COUNT(*) FROM `OldPosts`"); // Make sure it exists
	db.exec("DELETE FROM `Posts`");
	db.exec("DELETE FROM `Groups`");

	new DatabaseSource();
	new MessageDBSink();

	startNewsSources();
}

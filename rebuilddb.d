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
		db.exec("BEGIN");
		allowTransactions = false;
		foreach (string message, string id; query("SELECT `Message`, `ID` FROM old.Posts").iterate())
		{
			log("Announcing: " ~ id);
			announcePost(new Rfc850Post(message, id));
		}
		allowTransactions = true;
		log("Committing...");
		db.exec("COMMIT");
	}
}

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	//db.exec("DROP TABLE IF EXISTS `OldPosts`");
	//db.exec("ALTER TABLE `Posts` RENAME TO `OldPosts`");
	db.exec("ATTACH 'data/dfeed_old.s3db' AS old");
	db.exec("SELECT COUNT(*) FROM old.Posts"); // Make sure it exists
	db.exec("DELETE FROM `Posts`");
	db.exec("DELETE FROM `Groups`");
	db.exec("DELETE FROM `Threads`");

	new DatabaseSource();
	new MessageDBSink();

	startNewsSources();
}

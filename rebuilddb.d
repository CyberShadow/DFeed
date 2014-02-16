/*  Copyright (C) 2011, 2014  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module rebuilddb;

import std.getopt;

import common;
import database;
import message;
import messagedb;

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

/*  Copyright (C) 2014  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module rebuildthreads;

import std.getopt;

import common;
import database;
import messagedb;
import rfc850;

MessageDBSink sink;

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
		foreach (string message, string id; query("SELECT `Message`, `ID` FROM Posts").iterate())
		{
			auto post = new Rfc850Post(message, id);
			log("Announcing: " ~ id);
			announcePost(post);
			sink.updatePost(post);
		}
		allowTransactions = true;
		log("Committing...");
		db.exec("COMMIT");
	}

	override void stop() { assert(false); }
}

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	db.exec("DELETE FROM `Groups`");
	db.exec("DELETE FROM `Threads`");

	new DatabaseSource();
	sink = new MessageDBSink();

	startNewsSources();
}

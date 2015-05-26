/*  Copyright (C) 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import common;
import database;
import message;
import messagedb;

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
		static struct Message { string message, id; }
		Message[] messages;

		log("Loading...");
		foreach (string message, string id; query!"SELECT `Message`, `ID` FROM Posts".iterate())
			messages ~= Message(message, id);

		mixin(DB_TRANSACTION);

		log("Deleting...");
		db.exec("DELETE FROM `Groups`");
		db.exec("DELETE FROM `Threads`");

		log("Updating...");
		foreach (m; messages)
		with(m)
		{
			auto post = new Rfc850Post(message, id);
			log("Announcing: " ~ id);
			announcePost(post, Fresh.no);
			sink.updatePost(post);

			if (flushTransactionEvery(50))
				log("Transaction flushed");
		}
		log("Committing...");
	}

	override void stop() { assert(false); }
}

void main()
{
	new DatabaseSource();
	sink = new MessageDBSink();

	startNewsSources();
}

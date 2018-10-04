/*  Copyright (C) 2011, 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.database;

import std.exception;
import std.file : rename, exists;

import ae.sys.file : ensurePathExists;
import ae.sys.sqlite3 : SQLite;
public import ae.sys.sqlite3 : SQLiteException;

import ae.sys.database;

SQLite.PreparedStatement query(string sql)() { return database.stmt!sql(); }
SQLite.PreparedStatement query(string sql)   { return database.stmt(sql);  }
alias selectValue = ae.sys.database.selectValue;
@property SQLite db() { return database.db; }

// ***************************************************************************

private Database database;

enum databasePath = "data/db/dfeed.s3db";

static this()
{
	import std.file;

	enum oldDatabasePath = "data/dfeed.s3db";
	if (!databasePath.exists && oldDatabasePath.exists)
	{
		ensurePathExists(databasePath);
		rename(oldDatabasePath, databasePath);
		version(Posix) symlink("db/dfeed.s3db", oldDatabasePath);
	}

	database = Database(databasePath, [
		// Initial version
		readText("schema_v1.sql"),

		// Add missing index
		q"SQL
CREATE INDEX [SubscriptionUser] ON [Subscriptions] ([Username]);
SQL",
	]);
}

int transactionDepth;

enum DB_TRANSACTION = q{
	if (transactionDepth++ == 0) query!"BEGIN TRANSACTION".exec();
	scope(failure) if (--transactionDepth == 0) query!"ROLLBACK TRANSACTION".exec();
	scope(success) if (--transactionDepth == 0) query!"COMMIT TRANSACTION".exec();
};

bool flushTransactionEvery(int count)
{
	static int calls = 0;

	assert(transactionDepth, "Not in a transaction");

	if (count && ++calls % count == 0 && transactionDepth == 1)
	{
		query!"COMMIT TRANSACTION";
		query!"BEGIN TRANSACTION";
		return true;
	}
	else
		return false;
}

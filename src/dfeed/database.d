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

import ae.sys.sqlite3;
public import ae.sys.sqlite3 : SQLiteException;

SQLite.PreparedStatement query(string sql)()
{
	debug(DATABASE) std.stdio.writeln(sql);
	static SQLite.PreparedStatement statement = null;
	if (!statement)
		statement = db.prepare(sql).enforce("Statement compilation failed: " ~ sql);
	return statement;
}

SQLite.PreparedStatement query(string sql)
{
	debug(DATABASE) std.stdio.writeln(sql);
	static SQLite.PreparedStatement[const(void)*] cache;
	auto pstatement = sql.ptr in cache;
	if (pstatement)
		return *pstatement;

	auto statement = db.prepare(sql);
	enforce(statement, "Statement compilation failed: " ~ sql);
	return cache[sql.ptr] = statement;
}

T selectValue(T, Iter)(Iter iter)
{
	foreach (T val; iter)
		return val;
	throw new Exception("No results for query");
}

@property SQLite db()
{
	static SQLite instance;
	if (instance)
		return instance;

	auto dbFileName = "data/dfeed.s3db";
	if (!dbFileName.exists)
		atomic!createDatabase(schemaFileName, dbFileName);

	instance = new SQLite(dbFileName);
	dumpSchema();

	// Protect against locked database due to queries from command
	// line or cron
	instance.exec("PRAGMA busy_timeout = 100;");

	return instance;
}

// ***************************************************************************

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

// ***************************************************************************

private:

import std.file, std.string, std.array;

enum schemaFileName = "schema.sql";

void dumpSchema()
{
	string schema;
	foreach (string type, string name, string tbl_name, string sql; query!"SELECT `type`, `name`, `tbl_name`, `sql` FROM `sqlite_master`".iterate())
		if (!name.startsWith("sqlite_") && !name.startsWith("PostSearch_")) // skip internal / FTS helper tables
		{
			if (name == tbl_name)
				schema ~= format("-- %s `%s`\n", capitalize(type), name);
			else
				schema ~= format("-- %s `%s` on table `%s`\n", capitalize(type), name, tbl_name);
			schema ~= sql.replace("\r\n", "\n") ~ ";\n\n";
		}
	write(schemaFileName, schema);
}

import ae.sys.file;
import std.process;

public // template alias parameter
void createDatabase(string schema, string target)
{
	static import std.stdio;
	std.stdio.stderr.writeln("Creating new database from schema");
	ensurePathExists(target);
	enforce(spawnProcess(["sqlite3", target], std.stdio.File(schema, "rb")).wait() == 0, "sqlite3 failed");
}

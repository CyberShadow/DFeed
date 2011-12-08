/*  Copyright (C) 2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module database;

import std.exception;

import ae.sys.sqlite3;
public import ae.sys.sqlite3 : SQLiteException;

SQLite db;

SQLite.PreparedStatement query(string sql)
{
	// TODO: find out if the overhead of a sqlite3_prepare_v2 is larger than an associative array lookup
	static SQLite.PreparedStatement[const(void)*] cache;
	auto pstatement = sql.ptr in cache;
	if (pstatement)
		return *pstatement;

	auto statement = db.prepare(sql);
	enforce(statement, "Statement compilation failed: " ~ sql);
	return cache[sql.ptr] = statement;
}

bool allowTransactions = true;

enum DB_TRANSACTION = q{
	if (allowTransactions) query("BEGIN TRANSACTION").exec();
	scope(failure) if (allowTransactions) query("ROLLBACK TRANSACTION").exec();
	scope(success) if (allowTransactions) query("COMMIT TRANSACTION").exec();
};

static this()
{
	db = new SQLite("data/dfeed.s3db");
	dumpSchema();
}

private:

import std.file, std.string, std.array;

void dumpSchema()
{
	string schema;
	foreach (string type, string name, string tbl_name, string sql; query("SELECT `type`, `name`, `tbl_name`, `sql` FROM `sqlite_master`").iterate())
		if (!name.startsWith("sqlite_"))
		{
			if (name == tbl_name)
				schema ~= format("-- %s `%s`\n", capitalize(type), name);
			else
				schema ~= format("-- %s `%s` on table `%s`\n", capitalize(type), name, tbl_name);
			schema ~= sql.replace("\r\n", "\n") ~ ";\n\n";
		}
	write("schema.sql", schema);
}

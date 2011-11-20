module database;

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

	return cache[sql.ptr] = db.prepare(sql);
}

enum DB_TRANSACTION = q{
	query("BEGIN TRANSACTION").exec();
	scope(failure) query("ROLLBACK TRANSACTION").exec();
	scope(success) query("COMMIT TRANSACTION").exec();
};

static this()
{
	db = new SQLite("data/dfeed.s3db");
}

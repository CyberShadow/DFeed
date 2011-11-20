module database;

import ae.sys.sqlite3;
public import ae.sys.sqlite3 : SQLiteException;

SQLite db;

SQLite.PreparedStatement query(string sql)
{
	// is the overhead of a sqlite3_prepare_v2 larger than an associative array lookup?
	static SQLite.PreparedStatement[const(void)*] cache;
	auto pstatement = sql.ptr in cache;
	if (pstatement)
		return *pstatement;

	return cache[sql.ptr] = db.prepare(sql);
}

static this()
{
	db = new SQLite("data/dfeed.s3db");
}

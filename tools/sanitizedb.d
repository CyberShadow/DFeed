import std.utf;
import std.stdio;

import database;
import message;

void main()
{
	foreach (string id, string author, string subject; query(`SELECT "ID", "Author", "Subject" FROM "Posts"`).iterate())
	{
		try
		{
			validate(author);
			validate(subject);
		}
		catch (Exception e)
		{
			writeln(id);
			foreach (string text; query(`SELECT "Message" FROM "Posts" WHERE "ID" = ?`).iterate(id))
			{
				auto message = new Rfc850Post(text);
				query(`UPDATE "Posts" SET "Author" = ?, "Subject" = ? WHERE "ID" = ?`).exec(message.author, message.subject, id);
			}
		}
	}
}

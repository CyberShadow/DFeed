/*  Copyright (C) 2011, 2012, 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module newsgroups;

import std.algorithm;
import std.string;
import std.conv;

import ae.utils.array : queuePop;
import ae.utils.aa : HashSet;
import ae.utils.json;
import ae.net.nntp.client;
import ae.net.nntp.listener;
import ae.sys.timing;

import common;
import database;
import message;

struct NntpConfig
{
	string host;
}

/// Poll the server periodically for new messages
class NntpListenerSource : NewsSource
{
	this(string server)
	{
		super("NNTP-Listener");
		this.server = server;
		client = new NntpListener(log);
		client.handleMessage = &onMessage;
	}

	override void start()
	{
	}

	override void stop()
	{
		if (connected)
			client.disconnect();
		stopped = true;
	}

	/// Call this to start polling the server.
	/// startTime is the timestamp (as returned by the
	/// server DATE command) for the first poll cutoff time.
	void startListening(string startTime=null)
	{
		if (!stopped)
		{
			client.connect(server);
			connected = true;
			client.startPolling(startTime);
		}
	}

private:
	string server;
	bool connected, stopped;
	NntpListener client;

	void onMessage(string[] lines, string num, string id)
	{
		announcePost(new Rfc850Post(lines.join("\n"), id));
	}
}

/// Download articles not present in the database.
class NntpDownloader : NewsSource
{
	enum Mode { newOnly, full, fullPurge }

	NntpClient client;

	this(string server, Mode mode)
	{
		super("NNTP-Downloader");
		this.server = server;
		this.mode = mode;

		initialize();
	}

	override void start()
	{
		running = true;
		log("Starting, mode is " ~ text(mode));
		client.connect(server, &onConnect);
	}

	override void stop()
	{
		if (running)
		{
			running = false;
			stopping = true;
			log("Shutting down");
			client.disconnect();
		}
	}

	void delegate(string startTime) handleFinished;

private:
	string server;
	Mode mode;
	bool running, stopping;
	string startTime;

	void onConnect()
	{
		if (stopping) return;
		log("Listing groups...");
		client.getDate((string date) { startTime = date; });
		client.listGroups(&onGroups);
	}

	void onGroups(GroupInfo[] groups)
	{
		log(format("Got %d groups.", groups.length));

		foreach (group; groups)
			getGroup(group); // Own function for closure

		client.handleIdle = &onIdle;
	}

	void getGroup(GroupInfo group)
	{
		// Get maximum article numbers before fetching messages -
		// a cross-posted message might change a queued group's
		// "maximum article number in database".

		// The listGroup commands will be queued all together
		// before any getMessage commands.

		int maxNum = 0;
		foreach (int num; query!"SELECT MAX(`ArtNum`) FROM `Groups` WHERE `Group` = ?".iterate(group.name))
			maxNum = num;

		void onListGroup(string[] messages)
		{
			if (stopping) return;
			log(format("%d messages in group %s.", messages.length, group.name));

			HashSet!int serverMessages;
			foreach (i, m; messages)
				serverMessages.add(to!int(m));

			HashSet!int localMessages;
			foreach (int num; query!"SELECT `ArtNum` FROM `Groups` WHERE `Group` = ?".iterate(group.name))
				localMessages.add(num);

			// Construct set of posts to download
			HashSet!int messagesToDownload = serverMessages.dup;
			foreach (num; localMessages)
				if (num in messagesToDownload)
					messagesToDownload.remove(num);

			// Remove posts present in the database
			if (messagesToDownload.length)
			{
				client.selectGroup(group.name);
				foreach (num; messagesToDownload.keys.sort().release())
					client.getMessage(to!string(num), &onMessage);
			}

			if (mode == Mode.fullPurge)
			{
				HashSet!int messagesToDelete = localMessages.dup;
				foreach (num; serverMessages)
					if (num in messagesToDelete)
						messagesToDelete.remove(num);

				enum PRETEND = false;

				void logAndDelete(string TABLE, string WHERE, T...)(T args)
				{
					enum selectSql = "SELECT * FROM `" ~ TABLE ~ "` " ~ WHERE;
					enum deleteSql = "DELETE   FROM `" ~ TABLE ~ "` " ~ WHERE;

					log("  " ~ deleteSql);

					auto select = query!selectSql;
					select.bindAll!T(args);
					while (select.step())
						log("    " ~ toJson(select.getAssoc()));

					static if (!PRETEND)
						query!deleteSql.exec(args);
				}

				foreach (num; messagesToDelete)
				{
					log((PRETEND ? "Would delete" : "Deleting") ~ " message: " ~ text(num));
					mixin(DB_TRANSACTION);

					string id;
					foreach (string msgId; query!"SELECT `ID` FROM `Groups` WHERE `Group` = ? AND `ArtNum` = ?".iterate(group.name, num))
						id = msgId;

					logAndDelete!(`Groups`, "WHERE `Group` = ? AND `ArtNum` = ?")(group.name, num);

					if (id)
					{
						logAndDelete!(`Posts`  , "WHERE `ID` = ?")(id);
						logAndDelete!(`Threads`, "WHERE `ID` = ?")(id);
					}
				}
			}
		}

		log(format("Listing group: %s", group.name));
		if (mode == Mode.newOnly)
		{
			log(format("Highest article number in database: %d", maxNum));
			if (group.high > maxNum)
			{
				// news.digitalmars.com doesn't support LISTGROUP ranges, use XOVER
				client.listGroupXover(group.name, maxNum+1, &onListGroup);
			}
		}
		else
			client.listGroup(group.name, &onListGroup);
	}

	void onIdle()
	{
		log("All done!");
		running = false;
		client.handleIdle = null;
		client.disconnect();
		assert(startTime);
		if (handleFinished)
			handleFinished(startTime);
	}

	void onMessage(string[] lines, string num, string id)
	{
		log(format("Got message %s (%s)", num, id));
		announcePost(new Rfc850Post(lines.join("\n"), id));
	}

	void onDisconnect(string reason, DisconnectType type)
	{
		if (running)
			onError("Unexpected NntpDownloader disconnect: " ~ reason);
	}

	void onError(string msg)
	{
		log(msg);
		setTimeout({ log("Retrying..."); restart(); }, 10.seconds);
	}

	void initialize()
	{
		startTime = null;

		client = new NntpClient(log);
		client.handleDisconnect = &onDisconnect;
	}

	void restart()
	{
		if (stopping)
			return;
		initialize();
		start();
	}
}

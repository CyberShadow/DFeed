/*  Copyright (C) 2011, 2012  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.string;
import std.conv;

import ae.utils.array : queuePop;
import ae.net.nntp.client;
import ae.sys.timing;

import common;
import rfc850;
import database;

/// Poll the server periodically for new messages
class NntpListener : NewsSource
{
	this(string server)
	{
		super("NNTP-Listener");
		this.server = server;
		client = new NntpClient(log);
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
	NntpClient client;

	void onMessage(string[] lines, string num, string id)
	{
		announcePost(new Rfc850Post(lines.join("\n"), id));
	}
}

/// Download articles not present in the database.
class NntpDownloader : NewsSource
{
    // TODO: handle unlikely race condition conflicts with NntpClient
    // (at worst we'll have duplicate posts)

    enum PREFETCH = 64;

	NntpClient client;

	this(string server, bool fullCheck)
	{
		super("NNTP-Downloader");
		this.server = server;
		this.fullCheck = fullCheck;

		initialize();
	}

	override void start()
	{
		running = true;
		client.connect(server);
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
	bool fullCheck, running, stopping;
	GroupInfo[] queuedGroups;
	int[] groupMaxNums;
	GroupInfo currentGroup;
	int[] queuedMessages;
	size_t messagesToDownload;
	string startTime;

	void onConnect()
	{
		if (stopping) return;
		log("Listing groups...");
		client.getDate();
		client.listGroups();
	}

	void onGroups(GroupInfo[] groups)
	{
		log(format("Got %d groups.", groups.length));
		queuedGroups = groups;

		// Save maximum article numbers before fetching messages -
		// a cross-posted message might change a queued group's
		// "maximum article number in database".
		groupMaxNums = new int[groups.length];
		foreach (i, ref group; groups)
		{
			int maxNum = 0;
			foreach (int num; query("SELECT MAX(`ArtNum`) FROM `Groups` WHERE `Group` = ?").iterate(group.name))
				maxNum = num;
			groupMaxNums[i] = maxNum;
		}

		nextGroup();
	}

	void nextGroup()
	{
		if (stopping) return;
		if (queuedGroups.length == 0)
			return done();
		currentGroup = queuedGroups.queuePop();
		int maxNum   = groupMaxNums.queuePop();

		log(format("Listing group: %s", currentGroup.name));
		if (fullCheck)
			client.listGroup(currentGroup.name);
		else
		{
			log(format("Highest article number in database: %d", maxNum));
			if (currentGroup.high > maxNum)
			{
				// news.digitalmars.com doesn't support LISTGROUP ranges, use XOVER
				client.listGroupXover(currentGroup.name, maxNum+1);
			}
			else
				nextGroup();
		}
	}

	void done()
	{
		log("All done!");
		running = false;
		client.disconnect();
		assert(startTime, "TODO"); // To fix, add "running==false" check to handleDate and call disconnect / handleFinished from there
		if (handleFinished)
			handleFinished(startTime);
	}

	void onListGroup(string[] messages)
	{
		log(format("%d messages in group.", messages.length));

		// Construct set of posts to download
		bool[int] messageNums;
		foreach (i, m; messages)
			messageNums[to!int(m)] = true;

		// Remove posts present in the database
		foreach (int num; query("SELECT `ArtNum` FROM `Groups` WHERE `Group` = ?").iterate(currentGroup.name))
			if (num in messageNums)
				messageNums.remove(num);

		queuedMessages = messageNums.keys.sort;
		messagesToDownload = queuedMessages.length;

		if (messagesToDownload)
		{
			foreach (n; 0..PREFETCH)
				requestNextMessage();
		}
		else
			nextGroup();
	}

	void requestNextMessage()
	{
		if (stopping) return;
		if (queuedMessages.length)
		{
			auto num = queuedMessages[0];
			queuedMessages = queuedMessages[1..$];

			log(format("Asking for message %d...", num));
			client.getMessage(to!string(num));
		}
	}

	void onMessage(string[] lines, string num, string id)
	{
		log(format("Got message %s (%s)", num, id));

		announcePost(new Rfc850Post(lines.join("\n"), id));
		messagesToDownload--;
		if (messagesToDownload == 0)
			nextGroup();
		else
			requestNextMessage();
	}

	void onDate(string date)
	{
		startTime = date;
	}

	void onDisconnect(string reason)
	{
		if (running)
			onError("Unexpected NntpDownloader disconnect: " ~ reason);
	}

	void onError(string msg)
	{
		log(msg);
		setTimeout({ log("Retrying..."); restart(); }, TickDuration.from!"seconds"(10));
	}

	void initialize()
	{
		queuedGroups = null;
		groupMaxNums = null;
		currentGroup = currentGroup.init;
		queuedMessages = null;
		messagesToDownload = 0;
		startTime = null;

		client = new NntpClient(log);
		client.handleConnect = &onConnect;
		client.handleGroups = &onGroups;
		client.handleListGroup = &onListGroup;
		client.handleMessage = &onMessage;
		client.handleDate = &onDate;
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

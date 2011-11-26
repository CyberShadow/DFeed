module newsgroups;

import std.string;
import std.conv;

import common;
import nntp;
import rfc850;
import database;

/// Poll the server periodically for new messages
class NntpListener : NewsSource
{
	NntpClient client;
	
	this(string server)
	{
		super("NNTP-Listener");
		this.server = server;
		client = new NntpClient(log);
		client.polling = true;
		client.handleMessage = &onMessage;
	}

	override void start()
	{
		client.connect(server);
	}

private:
	string server;

	void onMessage(string[] lines, string num, string id)
	{
		announcePost(new Rfc850Post(lines.join("\n")));
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
		client = new NntpClient(log);
		client.handleConnect = &onConnect;
		client.handleGroups = &onGroups;
		client.handleListGroup = &onListGroup;
		client.handleMessage = &onMessage;
	}

	override void start()
	{
		client.connect(server);
	}

private:
	string server;
	bool fullCheck;
	GroupInfo[] queuedGroups;
	GroupInfo currentGroup;
	int[] queuedMessages;
	size_t messagesToDownload;

	void onConnect()
	{
		log("Listing groups...");
		client.listGroups();
	}

	void onGroups(GroupInfo[] groups)
	{
		log(format("Got %d groups.", groups.length));
		queuedGroups = groups;
		nextGroup();
	}

	void nextGroup()
	{
		if (queuedGroups.length == 0)
			return done();
		currentGroup = queuedGroups[0];
		queuedGroups = queuedGroups[1..$];
		log(format("Listing group: %s", currentGroup.name));
		if (fullCheck)
			client.listGroup(currentGroup.name);
		else
		{
			int maxNum = 0;
			foreach (int num; query("SELECT MAX(`ArtNum`) FROM `Groups` WHERE `Group` = ?").iterate(currentGroup.name))
				maxNum = num;

			log(format("Highest article number is database: %d", maxNum));
			if (currentGroup.high > maxNum)
			{
				// news.digitalmars.com doesn't seem to support LISTGROUP ranges :(
				//client.listGroup(currentGroup.name, maxNum+1);
				client.listGroup(currentGroup.name);
			}
			else
				nextGroup();
		}
	}

	void done()
	{
		log("All done!");
		client.disconnect();
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
}

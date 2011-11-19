module newsgroups;

import std.string;

import common;
import nntp;
import rfc850;

class NewsGroups : NewsSource
{
	NntpClient client;
	
	this(string server)
	{
		super("NNTP");
		this.server = server;
		client = new NntpClient(log);
		client.handleMessage = &onNntpMessage;
	}

	override void start()
	{
		client.connect(server);
	}

private:
	string server;

	void onNntpMessage(string[] lines)
	{
		announcePost(new Rfc850Post(lines.join("\n")));
	}
}

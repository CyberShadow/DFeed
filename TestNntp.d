import Nntp;
import Team15.ASockets;
import std.stdio;

void main()
{
	void onMessage(string[] lines)
	{
		foreach (line; lines)
			writefln("%s", line);
		writefln("---------------------------------");
	}

	auto client = new NntpClient;
	client.handleMessage = &onMessage;
	client.connect("news.digitalmars.com");

	socketManager.loop();
}

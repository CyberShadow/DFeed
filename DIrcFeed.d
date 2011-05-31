module DIrcFeed;

import std.string;
import std.file;
import std.conv;
import std.regexp;

import Team15.ASockets;
import Team15.IrcClient;
import Team15.Logging;
import Team15.CommandLine;
import Team15.Timing;

import Rfc850;
import Nntp;
import StackOverflow;
import Feed;
import Reddit;

class RelaySocket : ClientSocket
{
	string data;

	this(Socket conn) { super(conn); }
}

alias GenericServerSocket!(RelaySocket) RelayServerSocket;

debug const
	CHANNEL = "#d.test",
	CHANNEL2 = "#d.feed.test",
	NICK = "DFeed\\Test";
else const
	CHANNEL = "#d",
	CHANNEL2 = "#d.feed",
	NICK = "DFeed";

//const FORMAT = "PRIVMSG %s :\x01ACTION %s\x01";
const FORMAT = "PRIVMSG %s :\x01ACTION \x0314%s\x01";

final class DIrcFeed
{
private:
	IrcClient conn;
	RelayServerSocket server;
	Logger log, relayLog;

	void addNotifier(T)(T notifier)
	{
		notifier.handleNotify = &sendToIrc;
		notifier.start();
	}

public:
	this()
	{
		log = createLogger("IRC");
		relayLog = createLogger("Relay");

		conn = new IrcClient();
		conn.handleConnect = &onConnect;
		conn.handleDisconnect = &onDisconnect;
		log("Connecting to IRC...");
		connect();

		auto client = new NntpClient();
		client.handleMessage = &onNntpMessage;
		client.connect("news.digitalmars.com");

		auto serverConfig = splitlines(cast(string)read("data/dircfeed.txt"));
		server = new RelayServerSocket();
		server.handleAccept = &onAccept;
		server.listen(toUshort(serverConfig[1]), serverConfig[0]);

		addNotifier(new StackOverflow("d"));
		addNotifier(new Feed("Planet D", "http://feeds.feedburner.com/dplanet"));
		addNotifier(new Feed("Wikipedia", "http://en.wikipedia.org/w/api.php?action=feedwatchlist&allrev=allrev&hours=1&"~cast(string)read("data/wikipedia.txt")~"&feedformat=atom", "edited"));
		addNotifier(new Feed("GitHub", "https://github.com/"~cast(string)read("data/github.txt"), null));
		addNotifier(new Reddit("programming", new RegExp(`(^|[^\w\d\-:*=])D([^\w\-:*=]|$)`)));
		addNotifier(new Feed("Twitter", "http://twitter.com/statuses/user_timeline/18061210.atom", null));
		addNotifier(new Feed("Twitter", "http://twitter.com/statuses/user_timeline/155425162.atom", null));
	}

	void connect()
	{
		conn.connect(NICK, NICK ~ " (operated by CyberShadow)", "irc.freenode.net");
	}

	void onConnect(IrcClient sender)
	{
		conn.join(CHANNEL);
		conn.join(CHANNEL2);
	}

	void onDisconnect(IrcClient sender, string reason, DisconnectType type)
	{
		log(format("IRC connection lost (%s)", reason));
		setTimeout(&connect, 10*TicksPerSecond);
	}

	void onAccept(RelaySocket incoming)
	{
		relayLog("* New connection");
		incoming.handleDisconnect = &onRelayDisconnect;
		incoming.handleReadData = &onRelayData;
	}

	void onRelayData(ClientSocket sender, void[] data)
	{
		auto relay = cast(RelaySocket)sender;
		relay.data ~= cast(string)data;
	}

	void sendToIrc(string s, bool important)
	{
		log("< " ~ s);
		if (important)
			conn.sendRaw(format(FORMAT, CHANNEL, s));
		conn.sendRaw(format(FORMAT, CHANNEL2, s));
	}

	void onRelayDisconnect(ClientSocket sender, string reason, DisconnectType type)
	{
		auto relay = cast(RelaySocket)sender;
		foreach (line; splitlines(relay.data))
			relayLog("> " ~ line);
		relayLog("* Disconnected");
		auto summary = summarizeMessage(relay.data);
		sendToIrc(summary, isMLMessageImportant(summary));
	}

	void onNntpMessage(string[] lines)
	{
		auto summary = summarizeMessage(lines.join("\n"));
		sendToIrc(summary, isNGMessageImportant(summary));
	}

	static bool isNGMessageImportant(string s)
	{
		if (s.startsWith("[dm.D]") || s.startsWith("[dm.D.learn]"))
			return s.contains(" posted \"")
				|| s.contains("Walter Bright")
				|| s.contains("Andrei Alexandrescu");
		else
			return true;
	}

	static bool isMLMessageImportant(string s)
	{
		if (s.contains("noreply@github.com posted"))
			return false;
		else
			return true;
	}
}

void main(string[] args)
{
	parseCommandLine(args);
	new DIrcFeed();
	socketManager.loop();
}

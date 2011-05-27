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

alias GenericServerSocket!(LineBufferedSocket) LineBufferedServerSocket;

const CHANNEL = "#d";
const CHANNEL2 = "#d.feed";
const NICK = "DFeed";
//const FORMAT = "PRIVMSG %s :\x01ACTION %s\x01";
const FORMAT = "PRIVMSG %s :\x01ACTION \x0314%s\x01";

class DIrcFeed
{
private:
	IrcClient conn;
	LineBufferedServerSocket server;
	LineBufferedSocket[] clients;
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
		conn.handleRaw = &onRaw;
		log("Connecting to IRC...");
		connect();

		auto client = new NntpClient();
		client.handleMessage = &onNntpMessage;
		client.connect("news.digitalmars.com");

		auto serverConfig = splitlines(cast(string)read("data/dircfeed.txt"));
		server = new LineBufferedServerSocket();
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

	void onRaw(IrcClient sender, ref string s)
	{
		foreach (client; clients)
			client.send(s);
	}

	void onAccept(LineBufferedSocket incoming)
	{
		relayLog("* New connection");
		incoming.delimiter = "\n";
		incoming.handleDisconnect = &onRelayDisconnect;
		incoming.handleReadLine = &onRelayLine;
		clients ~= incoming;
	}

	void onRelayLine(LineBufferedSocket s, string line)
	{
		relayLog("> " ~ line);
		sendToIrc(line, isMLMessageImportant(line));
	}

	void sendToIrc(string s, bool important)
	{
		log("< " ~ s);
		if (important)
			conn.sendRaw(format(FORMAT, CHANNEL, s));
		conn.sendRaw(format(FORMAT, CHANNEL2, s));
	}

	void onRelayDisconnect(ClientSocket s, string reason, DisconnectType type)
	{
		relayLog("* Disconnected");
		foreach (i, client; clients)
			if (client is s)
			{
				clients = clients[0..i] ~ clients[i+1..$];
				return;
			}
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

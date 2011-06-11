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

const string[] VIP_ONLY = ["digitalmars.D", "digitalmars.D.learn"];
const string[] VIPs = ["Walter Bright", "Andrei Alexandrescu", "Sean Kelly", "Don", "dsimcha"];

final class DIrcFeed
{
private:
	IrcClient conn;
	RelayServerSocket server;
	Logger relayLog;

	void addNotifier(T)(T notifier)
	{
		notifier.handleNotify = &sendToIrc;
		notifier.start();
	}

public:
	this()
	{
		relayLog = createLogger("Relay");

		conn = new IrcClient();
		conn.encoder = conn.decoder = &nullStringTransform;
		conn.log = createLogger("IRC");
		conn.handleConnect = &onConnect;
		conn.handleDisconnect = &onDisconnect;
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
		conn.connect(NICK, "https://github.com/CyberShadow/DIrcFeed", "irc.freenode.net");
	}

	void onConnect(IrcClient sender)
	{
		conn.join(CHANNEL);
		conn.join(CHANNEL2);
	}

	void onDisconnect(IrcClient sender, string reason, DisconnectType type)
	{
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
		auto message = parseMessage(relay.data);
		sendToIrc(summarizeMessage(message), isMessageImportant(message));
	}

	void onNntpMessage(string[] lines)
	{
		auto message = parseMessage(lines.join("\n"));
		sendToIrc(summarizeMessage(message), isMessageImportant(message));
	}

	static string summarizeMessage(MessageInfo m)
	{
		return format("%s%s %s %s%s",
			m.where is null ? null : (
				"[" ~ (
					m.where.startsWith("digitalmars.") ?
						"dm." ~ m.where[12..$]
					:
						m.where
				) ~ "] "
			),
			m.author == "" ? "<no name>" : m.author,
			m.reply ? "replied to" : "posted",
			m.subject == "" ? "<no subject>" : `"` ~ m.subject ~ `"`,
			m.url ? ": " ~ shortenURL(m.url) : ""
		);
	}

	static bool isMessageImportant(MessageInfo m)
	{
		// GitHub notifications are already grabbed from RSS
		if (m.author == "noreply@github.com")
			return false;

		if (inArray(VIP_ONLY, m.where))
			return !m.reply || inArray(VIPs, m.author);

		return true;
	}
}

void main(string[] args)
{
	parseCommandLine(args);
	new DIrcFeed();
	socketManager.loop();
}

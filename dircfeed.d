module dircfeed;

import std.string;
import std.file;
import std.conv;
import std.regex;
import std.getopt;

import ae.net.asockets;
import ae.net.irc.client;
import ae.utils.log;
import ae.utils.cmd;
import ae.utils.array;
import ae.sys.timing;

import rfc850;
import nntp;
import stackoverflow;
import feed;
import reddit;
import common;

alias core.time.TickDuration TickDuration;

class RelaySocket : ClientSocket
{
	Data data;

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

string[] ANNOUNCE_REPLIES = ["digitalmars.D.bugs"];
string[] VIPs = ["Walter Bright", "Andrei Alexandrescu", "Sean Kelly", "Don", "dsimcha"];

final class DIrcFeed
{
	IrcClient conn;
	RelayServerSocket server;
	Logger relayLog;

	this()
	{
		relayLog = createLogger("Relay");

		conn = new IrcClient();
		conn.encoder = conn.decoder = &nullStringTransform;
		conn.exactNickname = true;
		conn.log = createLogger("IRC");
		conn.handleConnect = &onConnect;
		conn.handleDisconnect = &onDisconnect;
		connect();

		auto client = new NntpClient();
		client.handleMessage = &onNntpMessage;
		client.connect("news.digitalmars.com");

		auto serverConfig = splitLines(cast(string)read("data/dircfeed.txt"));
		server = new RelayServerSocket();
		server.handleAccept = &onAccept;
		server.listen(to!ushort(serverConfig[1]), serverConfig[0]);

		new StackOverflow("d", &onNewPost);
		new Feed("Planet D", "http://planetd.thecybershadow.net/_atom.xml", &onNewPost);
		new Feed("Wikipedia", "http://en.wikipedia.org/w/api.php?action=feedwatchlist&allrev=allrev&hours=1&"~cast(string)read("data/wikipedia.txt")~"&feedformat=atom", &onNewPost, "edited");
		new Feed("GitHub", "https://github.com/"~cast(string)read("data/github.txt"), &onNewPost, null);
		new Reddit("programming", regex(`(^|[^\w\d\-:*=])D([^\w\-:*=]|$)`), &onNewPost);
		new Feed("Twitter1", "http://twitter.com/statuses/user_timeline/18061210.atom", &onNewPost, null);
		new Feed("Twitter2", "http://twitter.com/statuses/user_timeline/155425162.atom", &onNewPost, null);
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
		setTimeout(&connect, TickDuration.from!"seconds"(10));
	}

	void onAccept(RelaySocket incoming)
	{
		relayLog("* New connection");
		incoming.handleDisconnect = &onRelayDisconnect;
		incoming.handleReadData = &onRelayData;
	}

	void onRelayData(ClientSocket sender, Data data)
	{
		auto relay = cast(RelaySocket)sender;
		relay.data ~= data;
	}

	void onNewPost(Post post)
	{
		sendToIrc(post.toString(), true);
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
		auto text = (cast(string)relay.data.contents).idup;
		foreach (line; splitAsciiLines(text))
			relayLog("> " ~ line);
		relayLog("* Disconnected");
		auto message = parseMessage(text);
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

		if (m.where == "")
			return false;

		if (inArray(ANNOUNCE_REPLIES, m.where))
			return true;

		return !m.reply || inArray(VIPs, m.author);
	}
}

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	new DIrcFeed();
	socketManager.loop();
}

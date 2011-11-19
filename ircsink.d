module ircsink;

import std.string;
//import std.file;
//import std.conv;
//import std.regex;
//import std.getopt;

import ae.net.asockets;
import ae.net.irc.client;
//import ae.utils.log;
//import ae.utils.array;
import ae.sys.timing;

//import rfc850;
//import nntp;
//import stackoverflow;
//import feed;
//import reddit;
import common;

alias core.time.TickDuration TickDuration;

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

final class IrcSink : NewsSink
{
	this()
	{
		super();

		conn = new IrcClient();
		conn.encoder = conn.decoder = &nullStringTransform;
		conn.exactNickname = true;
		conn.log = createLogger("IRC");
		conn.handleConnect = &onConnect;
		conn.handleDisconnect = &onDisconnect;
		connect();
	}

protected:
	override void handlePost(Post post)
	{
		bool important = post.isImportant();
		if (important || haveUnimportantListeners())
		{
			post.formatForIRC((string summary) {
				conn.sendRaw(format(FORMAT, CHANNEL2, summary));
				if (important)
					conn.sendRaw(format(FORMAT, CHANNEL, summary));
			});
		}
	}

private:
	IrcClient conn;

	void connect()
	{
		conn.connect(NICK, "https://github.com/CyberShadow/DFeed", "irc.freenode.net");
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

	/// This function exists for the sole reason of avoiding creation of
	/// shortened URLs (thus, needlessly polluting bit.ly) when no one
	/// will be there to see them.
	bool haveUnimportantListeners()
	{
		return (CHANNEL2 in conn.channels) && conn.channels[CHANNEL2].users.length > 1;
	}
}


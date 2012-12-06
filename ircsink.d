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

module ircsink;

import std.string;
import std.datetime;
import std.file;

import ae.net.asockets;
import ae.net.irc.client;
import ae.sys.timing;
import ae.sys.shutdown;
import ae.utils.text;

import common;

alias core.time.TickDuration TickDuration;

//const FORMAT = "PRIVMSG %s :\x01ACTION %s\x01";
const FORMAT = "PRIVMSG %s :\x01ACTION \x0314%s\x01";

final class IrcSink : NewsSink
{
	string server, nick, channel, channel2;

	this()
	{
		// Note to hackers: unless you want to work on IRC code, don't create
		// this configuration file to get DFeed to work - use e.g. dfeed_web instead.
		auto configLines = readText("data/irc.txt").splitLines();
		server   = configLines[0];
		nick     = configLines[1];
		channel  = configLines[2];
		channel2 = configLines[3];

		conn = new IrcClient();
		conn.encoder = conn.decoder = &nullStringTransform;
		conn.exactNickname = true;
		conn.log = createLogger("IRC");
		conn.handleConnect = &onConnect;
		conn.handleDisconnect = &onDisconnect;
		connect();

		addShutdownHandler({ stopping = true; if (connecting || connected) conn.disconnect("DFeed shutting down"); });
	}

protected:
	override void handlePost(Post post)
	{
		if (post.time < Clock.currTime() - dur!"days"(1))
			return; // ignore posts older than a day old (e.g. StackOverflow question activity bumps the questions)

		bool important = post.isImportant();
		if (important || haveUnimportantListeners())
		{
			post.formatForIRC((string summary) {
				if (connected)
				{
					summary = summary.newlinesToSpaces();
					conn.sendRaw(format(FORMAT, channel2, summary));
					if (important)
						conn.sendRaw(format(FORMAT, channel, summary));
				}
			});
		}
	}

private:
	IrcClient conn;
	bool connecting, connected, stopping;

	void connect()
	{
		conn.connect(nick, "https://github.com/CyberShadow/DFeed", server);
		connecting = true;
	}

	void onConnect(IrcClient sender)
	{
		connecting = false;
		conn.join(channel);
		conn.join(channel2);
		connected = true;
	}

	void onDisconnect(IrcClient sender, string reason, DisconnectType type)
	{
		connecting = connected = false;
		if (type != DisconnectType.Requested && !stopping)
			setTimeout(&connect, TickDuration.from!"seconds"(10));
	}

	/// This function exists for the sole reason of avoiding creation of
	/// shortened URLs (thus, needlessly polluting bit.ly) when no one
	/// will be there to see them.
	bool haveUnimportantListeners()
	{
		return (channel2 in conn.channels) && conn.channels[channel2].users.length > 1;
	}
}

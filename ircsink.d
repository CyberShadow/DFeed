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

import ae.net.asockets;
import ae.net.irc.client;
import ae.sys.timing;
import ae.utils.text;

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
		if (post.time < Clock.currTime() - dur!"days"(1))
			return; // ignore posts older than a day old (e.g. StackOverflow question activity bumps the questions)

		bool important = post.isImportant();
		if (important || haveUnimportantListeners())
		{
			post.formatForIRC((string summary) {
				if (connected)
				{
					summary = summary.newlinesToSpaces();
					conn.sendRaw(format(FORMAT, CHANNEL2, summary));
					if (important)
						conn.sendRaw(format(FORMAT, CHANNEL, summary));
				}
			});
		}
	}

private:
	IrcClient conn;
	bool connected;

	void connect()
	{
		conn.connect(NICK, "https://github.com/CyberShadow/DFeed", "irc.freenode.net");
	}

	void onConnect(IrcClient sender)
	{
		conn.join(CHANNEL);
		conn.join(CHANNEL2);
		connected = true;
	}

	void onDisconnect(IrcClient sender, string reason, DisconnectType type)
	{
		connected = false;
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

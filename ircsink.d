/*  Copyright (C) 2011, 2012, 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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
import ae.net.shutdown;
import ae.sys.log;
import ae.sys.timing;
import ae.utils.text;

import common;

alias core.time.TickDuration TickDuration;

/// IRC color code for sent lines
enum ircColor = 14; // Dark gray

/// Format string for IRC announcements (as raw IRC protocol line)
const ircFormat = "PRIVMSG %s :\x01ACTION \x03" ~ format("%02d", ircColor) ~ "%s\x01";

final class IrcSink : NewsSink
{
	static struct Config
	{
		string network;
		string server;
		ushort port = 6667;
		string nick;
		string channel;
		string channel2;
	}

	this(Config config)
	{
		if (config.channel.length && !config.channel.startsWith("#"))
			config.channel = '#' ~ config.channel;
		if (config.channel2.length && !config.channel2.startsWith("#"))
			config.channel2 = '#' ~ config.channel2;
		if (!config.network)
			config.network = config.server.split(".")[max(2, $)-2].capitalize();
		this.config = config;

		tcp = new TcpConnection();
		irc = new IrcClient(tcp);
		irc.encoder = irc.decoder = &nullStringTransform;
		irc.exactNickname = true;
		irc.log = createLogger("IRC-"~config.network);
		irc.handleConnect = &onConnect;
		irc.handleDisconnect = &onDisconnect;
		connect();

		addShutdownHandler({ stopping = true; if (connecting || connected) irc.disconnect("DFeed shutting down"); });
	}

	@property string network() { return config.network; }

	void sendMessage(string recipient, string message)
	{
		if (connected)
			irc.message(recipient, message);
	}

protected:
	override void handlePost(Post post, Fresh fresh)
	{
		if (!fresh)
			return;

		if (post.time < Clock.currTime() - dur!"days"(1))
			return; // ignore posts older than a day old (e.g. StackOverflow question activity bumps the questions)

		bool important = post.isImportant();
		if (important || haveUnimportantListeners())
		{
			post.formatForIRC((string summary) {
				if (connected)
				{
					summary = summary.newlinesToSpaces();
					if (config.channel.length && important)
						irc.sendRaw(format(ircFormat, config.channel , summary));
					if (config.channel2.length)
						irc.sendRaw(format(ircFormat, config.channel2, summary));
				}
			});
		}
	}

private:
	TcpConnection tcp;
	IrcClient irc;
	immutable Config config;
	bool connecting, connected, stopping;

	void connect()
	{
		irc.nickname = config.nick;
		irc.realname = "https://github.com/CyberShadow/DFeed";
		tcp.connect(config.server, config.port);
		connecting = true;
	}

	void onConnect()
	{
		connecting = false;
		if (config.channel.length)
			irc.join(config.channel);
		if (config.channel2.length)
			irc.join(config.channel2);
		connected = true;
	}

	void onDisconnect(string reason, DisconnectType type)
	{
		connecting = connected = false;
		if (type != DisconnectType.requested && !stopping)
			setTimeout(&connect, 10.seconds);
	}

	/// This function exists for the sole reason of avoiding creation of
	/// shortened URLs (thus, needlessly polluting bit.ly) when no one
	/// will be there to see them.
	bool haveUnimportantListeners()
	{
		return config.channel2.length
			&& config.channel2 in irc.channels
			&& irc.channels[config.channel2].users.length > 1;
	}
}

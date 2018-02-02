/*  Copyright (C) 2015, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.sources.socket;

import std.exception;
import std.string;
import std.file;

import ae.net.asockets;
import ae.utils.array;
import ae.utils.json;
import ae.utils.text;

import dfeed.bitly;
import dfeed.common;
import dfeed.message;

/// Listen for email messages piped by a helper script to a socket.
class SocketSource : NewsSource
{
	static struct Config
	{
		ushort port;
		string password;
	}

	this(Config config)
	{
		super("SocketSource");

		this.config = config;

		server = new TcpServer();
		server.handleAccept = &onAccept;
	}

	override void start()
	{
		server.listen(config.port);
	}

	override void stop()
	{
		server.close();
	}

private:
	TcpServer server;
	Config config;

	void onAccept(TcpConnection incoming)
	{
		log("* New connection");
		Data[] received;

		incoming.handleReadData = (Data data)
		{
			received ~= data;
			if (received.length > 1*1024*1024)
			{
				received = null;
				incoming.disconnect("Too much data");
			}
		};

		incoming.handleDisconnect = (string reason, DisconnectType type)
		{
			log("* Disconnected");
			try
			{
				if (!received)
					return;

				auto text = cast(string)received.joinToHeap();

				auto receivedPassword = text.eatLine();
				enforce(receivedPassword == config.password, "Wrong password");

				auto component = text.eatLine();

				switch (component)
				{
					case "dwiki":
						handleDWiki(text);
						break;
					default:
						throw new Exception("Unknown component: " ~ component);
				}
			}
			catch (Exception e)
				log("* Error: " ~ e.msg);
		};
	}

	void handleDWiki(string text)
	{
		static struct Info
		{
			string article, user, text, summary, section, url;
			bool isMinor, isWatch;
		}

		auto info = jsonParse!Info(text);

		announcePost(new class Post
		{
			override Importance getImportance() { return info.isMinor ? Importance.low : Importance.normal; }

			override void formatForIRC(void delegate(string) handler)
			{
				shortenURL(info.url, (string shortenedURL) {
					handler(format("[DWiki] %s edited \"%s\"%s%s%s%s: %s",
						filterIRCName(info.user),
						info.article,
						info.summary.length ? " (" : null,
						info.summary,
						info.summary.length ? ")" : null,
						info.isMinor ? " [m]" : null,
						shortenedURL,
					));
				});
			}
		}, Fresh.yes);
	}
}

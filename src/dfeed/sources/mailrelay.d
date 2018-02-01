/*  Copyright (C) 2011, 2012, 2014, 2015, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.sources.mailrelay;

import ae.net.asockets;
import ae.utils.text;

import dfeed.common;
import dfeed.message;

/// Listen for email messages piped by a helper script to a socket.
class MailRelay : NewsSource
{
	static struct Config
	{
		string addr;
		ushort port;
	}

	this(Config config)
	{
		super("MailRelay");

		this.config = config;

		server = new TcpServer();
		server.handleAccept = &onAccept;
	}

	override void start()
	{
		server.listen(config.port, config.addr);
	}

	override void stop()
	{
		server.close();
	}

private:
	TcpServer server;
	immutable Config config;

	void onAccept(TcpConnection incoming)
	{
		log("* New connection");
		Data received;

		incoming.handleReadData = (Data data)
		{
			received ~= data;
		};

		incoming.handleDisconnect = (string reason, DisconnectType type)
		{
			auto text = cast(string)received.toHeap();
			foreach (line; splitAsciiLines(text))
				log("> " ~ line);
			log("* Disconnected");

			announcePost(new Rfc850Post(text), Fresh.yes);
		};
	}
}

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

module mailinglists;

import std.string;
import std.file;

import ae.net.asockets;
import ae.utils.text;

import common;
import message;

/// Listen for email messages piped by a helper script to a socket.
class MailingLists : NewsSource
{
	this()
	{
		super("MailingList");

		auto serverConfig = splitLines(readText("data/mailrelay.txt"));
		host = serverConfig[0];
		port = to!ushort(serverConfig[1]);

		server = new TcpServer();
		server.handleAccept = &onAccept;
	}

	override void start()
	{
		server.listen(port, host);
	}

	override void stop()
	{
		server.close();
	}

private:
	TcpServer server;
	string host;
	ushort port;

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

			announcePost(new Rfc850Post(text));
		};
	}
}

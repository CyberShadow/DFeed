/*  Copyright (C) 2011, 2012, 2014  Vladimir Panteleev <vladimir@thecybershadow.net>
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

		server = new RelayServerSocket();
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
	static class RelaySocket : ClientSocket
	{
		Data data;

		this(Socket conn) { super(conn); }
	}

	alias GenericServerSocket!RelaySocket RelayServerSocket;

	RelayServerSocket server;
	string host;
	ushort port;

	void onAccept(RelaySocket incoming)
	{
		log("* New connection");
		incoming.handleDisconnect = &onRelayDisconnect;
		incoming.handleReadData = &onRelayData;
	}

	void onRelayData(ClientSocket sender, Data data)
	{
		auto relay = cast(RelaySocket)sender;
		relay.data ~= data;
	}

	void onRelayDisconnect(ClientSocket sender, string reason, DisconnectType type)
	{
		auto relay = cast(RelaySocket)sender;
		auto text = (cast(string)relay.data.contents).idup;
		foreach (line; splitAsciiLines(text))
			log("> " ~ line);
		log("* Disconnected");

		announcePost(new Rfc850Post(text));
	}
}

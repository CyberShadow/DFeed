module mailinglists;

import std.string;
import std.file;

import ae.net.asockets;
import ae.utils.text;

import common;
import rfc850;

/// Listen for e-mail messages piped by a helper script to a socket.
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

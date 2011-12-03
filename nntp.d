module nntp;

import std.datetime;
import std.string;
import std.exception;

import ae.net.asockets;
import ae.sys.timing;
import ae.sys.log;

alias core.time.TickDuration TickDuration;

const POLL_PERIOD = 2;

struct GroupInfo { string name; int high, low; char mode; }

class NntpClient
{
private:
	LineBufferedSocket conn;
	SysTime last;
	string[] reply;
	string server;
	int queued;
	string lastTime;
	Logger log;
	bool[string] oldMessages;
	TimerTask pollTimer;

	void reconnect()
	{
		queued = 0;
		lastTime = null;
		reply = null;
		conn.connect(server, 119);
	}

	void onDisconnect(ClientSocket sender, string reason, DisconnectType type)
	{
		log("* Disconnected (" ~ reason ~ ")");
		if (polling && type != DisconnectType.Requested)
		{
			if (pollTimer)
				mainTimer.remove(pollTimer);
			setTimeout(&reconnect, TickDuration.from!"seconds"(10));
		}
	}

	void onReadLine(LineBufferedSocket s, string line)
	{
		log("> " ~ line);

		if (line == ".")
		{
			onReply(reply);
			reply = null;
			return;
		}

		if (line.length && line[0] == '.')
			line = line[1..$];

		if (reply.length==0 && (line.startsWith("200") || line.startsWith("111")))
			onReply([line]);
		else
			reply ~= line;
	}

	void send(string line)
	{
		log("< " ~ line);
		conn.send(line);
	}

	void onReply(string[] reply)
	{
		auto firstLine = split(reply[0]);
		switch (firstLine[0])
		{
			case "200": // greeting
				if (handleConnect)
					handleConnect();
				if (polling)
					send("DATE");
				break;
			case "111": // DATE reply
			{	
				if (polling)
				{
					auto time = firstLine[1];
					enforce(time.length == 14, "DATE format");
					if (lastTime is null)
						pollTimer = setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
					lastTime = time;
				}
				break;
			}
			case "230": // NEWNEWS reply
			{
				assert(polling);

				bool[string] messages;
				foreach (message; reply[1..$])
					messages[message] = true;

				assert(queued == 0);
				foreach (message, b; messages)
					if (!(message in oldMessages))
					{
						send("ARTICLE " ~ message);
						queued++;
					}
				oldMessages = messages;
				if (queued==0)
					pollTimer = setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
				break;
			}
			case "220": // ARTICLE reply
			{
				//enforce(firstLine.length==3);
				auto message = reply[1..$];
				if (handleMessage)
					handleMessage(message, firstLine[1], firstLine[2]);

				if (polling)
				{
					queued--;
					if (queued==0)
						pollTimer = setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
				}
				break;
			}
			case "215": // LIST reply
			{
				// assume the command was LIST [ACTIVE]
				GroupInfo[] groups = new GroupInfo[reply.length-1];
				foreach (i, line; reply[1..$])
				{
					auto info = split(line);
					enforce(info.length == 4, "Unrecognized LIST reply");
					groups[i] = GroupInfo(info[0], to!int(info[1]), to!int(info[2]), info[3][0]);
				}
				if (handleGroups)
					handleGroups(groups);
				break;
			}
			case "211": // LISTGROUP reply
			{
				if (handleListGroup)
					handleListGroup(reply[1..$]);
				break;
			}
			default:
				throw new Exception("Unknown reply: " ~ reply[0]);
		}
	}

	void poll()
	{
		pollTimer = null;
		send("DATE");
		send("NEWNEWS * "~ lastTime[0..8] ~ " " ~ lastTime[8..14] ~ " GMT");
	}

public:
	bool polling;

	this(Logger log)
	{
		this.log = log;
	}

	void connect(string server)
	{
		this.server = server;

		conn = new LineBufferedSocket(TickDuration.from!"seconds"(POLL_PERIOD*10));
		conn.handleDisconnect = &onDisconnect;
		conn.handleReadLine = &onReadLine;
		reconnect();
	}

	void disconnect()
	{
		conn.disconnect();
	}

	void listGroups()
	{
		send("LIST");
	}

	void selectGroup(string name)
	{
		send("GROUP " ~ name);
	}

	void listGroup(string name, int from = 1)
	{
		if (from > 1)
			send(format("LISTGROUP %s %d-", name, from));
		else
			send(format("LISTGROUP %s", name));
	}

	void getMessage(string numOrID)
	{
		send("ARTICLE " ~ numOrID);
	}

	void delegate() handleConnect;
	void delegate(GroupInfo[] groups) handleGroups;
	void delegate(string[] messages) handleListGroup;
	void delegate(string[] lines, string num, string id) handleMessage;
}

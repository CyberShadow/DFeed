module nntp;

import std.datetime;
import std.string;

import ae.net.asockets;
import ae.sys.timing;
import ae.utils.log;

alias core.time.TickDuration TickDuration;

const POLL_PERIOD = 2;

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
			setTimeout(&reconnect, TickDuration.from!"seconds"(10));
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
					assert(time.length == 14);
					if (lastTime is null)
						setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
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
					setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
				break;
			}
			case "220": // ARTICLE reply
			{
				//assert(firstLine.length==3);
				auto message = reply[1..$];
				if (handleMessage)
					handleMessage(message, firstLine[1], firstLine[2]);

				if (polling)
				{
					queued--;
					if (queued==0)
						setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
				}
				break;
			}
			case "215": // LIST reply
			{
				// assume the command was LIST [ACTIVE]
				// TODO: misc info
				string[] names = new string[reply.length-1];
				foreach (i, line; reply[1..$])
					names[i] = split(line)[0];
				if (handleGroups)
					handleGroups(names);
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

	void listGroup(string name)
	{
		send("LISTGROUP " ~ name);
	}

	void getMessage(string numOrID)
	{
		send("ARTICLE " ~ numOrID);
	}

	void delegate() handleConnect;
	void delegate(string[] names) handleGroups;
	void delegate(string[] messages) handleListGroup;
	void delegate(string[] lines, string num, string id) handleMessage;
}

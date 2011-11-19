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
		setTimeout(&reconnect, TickDuration.from!"seconds"(10));
	}

	void onReadLine(LineBufferedSocket s, string line)
	{
		log("> " ~ line);

		if (line == ".")
		{
			onReply(reply);
			reply = null;
		}
		else
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
			case "200":
				send("DATE");
				break;
			case "111":
			{	
				auto time = firstLine[1];
				assert(time.length == 14);
				if (lastTime is null)
					setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
				lastTime = time;
				break;
			}
			case "230":
			{
				bool[string] messages;
				foreach (message; reply[1..$])
					messages[message] = true;

				assert(queued == 0);
				foreach (message, b; messages)
					if (!(message in oldMessages))
					{
						send("HEAD " ~ message);
						queued++;
					}
				oldMessages = messages;
				if (queued==0)
					setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
				break;
			}
			case "221":
			{
				auto message = reply[1..$];
				if (handleMessage)
					handleMessage(message);
				queued--;
				if (queued==0)
					setTimeout(&poll, TickDuration.from!"seconds"(POLL_PERIOD));
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
	this(Logger log)
	{
		this.log = log;
	}

	void connect(string server)
	{
		this.server = server;

		conn = new LineBufferedSocket(TickDuration.from!"seconds"(60));
		conn.handleDisconnect = &onDisconnect;
		conn.handleReadLine = &onReadLine;
		reconnect();
	}

	void delegate(string[] head) handleMessage;
}

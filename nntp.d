/*  Copyright (C) 2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module nntp;

import std.datetime;
import std.string;
import std.exception;

import ae.net.asockets;
import ae.sys.timing;
import ae.sys.log;
import ae.utils.array;

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
	bool[] expectingGroupList;
	string[] postQueue;

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
		if (handleDisconnect)
			handleDisconnect(reason);
		if (polling && type != DisconnectType.Requested)
		{
			if (pollTimer)
				mainTimer.remove(pollTimer);
			setTimeout(&reconnect, TickDuration.from!"seconds"(10));
		}
		expectingGroupList = null;
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

		if (reply.length==0 && isSingleLineReply(line))
			onReply([line]);
		else
			reply ~= line;
	}

	bool isSingleLineReply(string line)
	{
		return line.startsWith("200")
			|| line.startsWith("111")
			||(line.startsWith("211") && !expectingGroupList.queuePeek())
			|| line.startsWith("240")
			|| line.startsWith("340")
			|| line.startsWith("400");
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
			case "211": // GROUP / LISTGROUP reply
			{
				if (expectingGroupList.queuePop())
					if (handleListGroup)
						handleListGroup(reply[1..$]);
				break;
			}
			case "224": // LISTGROUP reply
			{
				auto messages = new string[reply.length-1];
				foreach (i, line; reply[1..$])
					messages[i] = line.split("\t")[0];
				if (handleListGroup)
					handleListGroup(messages);
				break;
			}
			case "340": // POST reply
			{
				assert(postQueue.length);

				foreach (line; postQueue)
					if (line.startsWith("."))
						send("." ~ line);
					else
						send(line);
				send(".");
				postQueue = null;
				break;
			}
			case "240": // Successful post reply
			{
				if (handlePosted)
					handlePosted();
				break;
			}
			default:
				if (handleError)
					handleError(reply[0]);
				else
					conn.disconnect("Unknown reply: " ~ reply[0], DisconnectType.Error);
				break;
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
		expectingGroupList.queuePush(false);
		send("GROUP " ~ name);
	}

	void listGroup(string name, int from = 1)
	{
		expectingGroupList.queuePush(true);
		if (from > 1)
			send(format("LISTGROUP %s %d-", name, from));
		else
			send(format("LISTGROUP %s", name));
	}

	void listGroupXover(string name, int from = 1)
	{
		selectGroup(name);
		if (from > 1)
			send(format("XOVER %d-", from));
		else
			send("XOVER");
	}

	void getMessage(string numOrID)
	{
		send("ARTICLE " ~ numOrID);
	}

	void postMessage(string[] lines)
	{
		postQueue = lines;
		send("POST");
	}

	void delegate() handleConnect;
	void delegate(string reason) handleDisconnect;
	void delegate(string error) handleError;
	void delegate(GroupInfo[] groups) handleGroups;
	void delegate(string[] messages) handleListGroup;
	void delegate(string[] lines, string num, string id) handleMessage;
	void delegate() handlePosted;
}

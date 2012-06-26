/*  Copyright (C) 2011, 2012  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module spam;

import std.string;
import std.file;
import std.exception;

import ae.net.http.client;
import ae.utils.array;

import posting;

void spamCheck(PostProcess process, SpamResultHandler handler)
{
	int totalResults = 0;
	bool foundSpam = false;

	foreach (checker; spamEngines)
		try
			checker(process, (bool ok, string message) {
				totalResults++;
				if (!foundSpam)
				{
					if (!ok)
					{
						handler(false, message);
						foundSpam = true;
					}
					else
					{
						if (totalResults == spamEngines.length)
							handler(true, null);
					}
				}
			});
		catch (Exception e)
		{
			foundSpam = true;
			handler(false, "Spam check error: " ~ e.msg);
		}
}

private:

alias void delegate(bool ok, string message) SpamResultHandler;

void checkAkismet(PostProcess process, SpamResultHandler handler)
{
	auto key = readText("data/akismet.txt");
	auto site = readText("data/web.txt").splitLines()[1];

	string[string] params = [
		"blog"                 : "http://" ~ site ~ "/",
		"user_ip"              : process.ip,
		"user_agent"           : process.headers.get("User-Agent", ""),
		"referrer"             : process.headers.get("Referer", ""),
		"comment_author"       : process.vars.get("name", ""),
		"comment_author_email" : process.vars.get("email", ""),
		"comment_content"      : process.vars.get("text", ""),
	];

	return httpPost("http://" ~ key ~ ".rest.akismet.com/1.1/comment-check", params, (string result) {
		if (result == "false")
			handler(true, null);
		else
		if (result == "true")
			handler(false, "Akismet thinks your post looks like spam");
		else
			handler(false, "Akismet error: " ~ result);
	}, (string error) {
		handler(false, "Akismet error: " ~ error);
	});
}

void checkProjectHoneyPot(PostProcess process, SpamResultHandler handler)
{
	enum DAYS_THRESHOLD  =  7; // consider an IP match as a positive if it was last seen at most this many days ago
	enum SCORE_THRESHOLD = 10; // consider an IP match as a positive if its ProjectHoneyPot score is at least this value

	struct PHPResult
	{
		bool present;
		ubyte daysLastSeen, threatScore, type;
	}

	static PHPResult phpCheck(string ip)
	{
		auto key = readText("data/projecthoneypot.txt");

		import std.socket;
		string[] sections = split(ip, ".");
		if (sections.length != 4) // IPv6
			return PHPResult(false);
		sections.reverse;
		string addr = ([key] ~ sections ~ ["dnsbl.httpbl.org"]).join(".");
		InternetHost ih = new InternetHost;
		if (!ih.getHostByName(addr))
			return PHPResult(false);
		auto resultIP = cast(ubyte[])(&ih.addrList[0])[0..1];
		resultIP.reverse;
		enforce(resultIP[0] == 127, "PHP API error");
		return PHPResult(true, resultIP[1], resultIP[2], resultIP[3]);
	}

	auto result = phpCheck(process.ip);
	with (result)
		if (present && daysLastSeen <= DAYS_THRESHOLD && threatScore >= SCORE_THRESHOLD)
			handler(false, format(
				"ProjectHoneyPot thinks you may be a spammer (%s last seen: %d days ago, threat score: %d/255, type: %s)",
				process.ip,
				daysLastSeen,
				threatScore,
				(
					( type == 0      ? ["Search Engine"  ] : []) ~
					((type & 0b0001) ? ["Suspicious"     ] : []) ~
					((type & 0b0010) ? ["Harvester"      ] : []) ~
					((type & 0b0100) ? ["Comment Spammer"] : [])
				).join(", ")));
		else
			handler(true, null);
}

void checkStopForumSpam(PostProcess process, SpamResultHandler handler)
{
	enum DAYS_THRESHOLD = 3; // consider an IP match as a positive if it was last seen at most this many days ago
	
	httpGet("http://www.stopforumspam.com/api?ip=" ~ process.ip, (string result) {
		import std.stream;
		import std.datetime;
		import ae.utils.xml;
		import ae.utils.time;

		auto xml = new XmlDocument(new MemoryStream(cast(char[])result));
		auto response = xml["response"];
		enforce(response.attributes["success"] == "true", "StopForumSpam API error");
		if (response["appears"].text == "no")
			handler(true, null);
		else
		{
			auto date = parseTime("Y-m-d H:i:s", response["lastseen"].text);
			if (Clock.currTime() - date < dur!"days"(DAYS_THRESHOLD))
				handler(false, format(
					"StopForumSpam thinks you may be a spammer (%s last seen: %s, frequency: %s)",
					process.ip, response["lastseen"].text, response["frequency"].text));
			else
				handler(true, null);
		}
	}, (string errorMessage) {
		handler(false, "StopForumSpam error: " ~ errorMessage);
	});
}

auto spamEngines =
[
	&checkAkismet,
	&checkProjectHoneyPot,
	&checkStopForumSpam,
];

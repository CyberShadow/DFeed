/*  Copyright (C) 2011, 2012, 2014, 2015, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.algorithm;
import std.exception;
import std.file : readText;
import std.string;

import ae.net.http.client;
import ae.sys.data;
import ae.utils.array;
import ae.utils.json;
import ae.utils.text;

import posting;
import site;

void spamCheck(PostProcess process, SpamResultHandler handler)
{
	if (!spamCheckers)
		initSpamCheckers();

	int totalResults = 0;
	bool foundSpam = false;

	// Start all checks simultaneously
	foreach (checker; spamCheckers)
	{
		try
			checker.check(process, (bool ok, string message) {
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
						if (totalResults == spamCheckers.length)
							handler(true, null);
					}
				}
			});
		catch (Exception e)
		{
			foundSpam = true;
			handler(false, "Spam check error: " ~ e.msg);
		}

		// Avoid starting slow checks if the first engines instantly return a positive
		if (foundSpam)
			break;
	}
}

void sendSpamFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
{
	if (!spamCheckers)
		initSpamCheckers();

	foreach (checker; spamCheckers)
		checker.sendFeedback(process, handler, feedback);
}

// **************************************************************************

alias void delegate(bool ok, string message) SpamResultHandler;

enum SpamFeedback { unknown, spam, ham }

class SpamChecker
{
	abstract void check(PostProcess process, SpamResultHandler handler);

	void sendFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
	{
		handler(true, "Not implemented");
	}
}

// **************************************************************************

class Akismet : SpamChecker
{
	struct Config { string key; }
	Config config;
	this(Config config) { this.config = config; }

	override void check(PostProcess process, SpamResultHandler handler)
	{
		if (!config.key)
			return handler(true, "Akismet is not set up");

		string[string] params = [
			"blog"                 : site.config.proto ~ "://" ~ site.config.host ~ "/",
			"user_ip"              : process.ip,
			"user_agent"           : process.headers.get("User-Agent", ""),
			"referrer"             : process.headers.get("Referer", ""),
			"comment_author"       : process.draft.clientVars.get("name", ""),
			"comment_author_email" : process.draft.clientVars.get("email", ""),
			"comment_content"      : process.draft.clientVars.get("text", ""),
		];

		return httpPost("http://" ~ config.key ~ ".rest.akismet.com/1.1/comment-check", UrlParameters(params), (string result) {
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

	override void sendFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
	{
		if (!config.key)
			return handler(true, "Akismet is not set up");

		string[string] params = [
			"blog"                 : site.config.proto ~ "://" ~ site.config.host ~ "/",
			"user_ip"              : process.ip,
			"user_agent"           : process.headers.get("User-Agent", ""),
			"referrer"             : process.headers.get("Referer", ""),
			"comment_author"       : process.draft.clientVars.get("name", ""),
			"comment_author_email" : process.draft.clientVars.get("email", ""),
			"comment_content"      : process.draft.clientVars.get("text", ""),
		];

		string[SpamFeedback] names = [ SpamFeedback.spam : "spam", SpamFeedback.ham : "ham" ];
		return httpPost("http://" ~ config.key ~ ".rest.akismet.com/1.1/submit-" ~ names[feedback], UrlParameters(params), (string result) {
			if (result == "Thanks for making the web a better place.")
				handler(true, null);
			else
				handler(false, "Akismet error: " ~ result);
		}, (string error) {
			handler(false, "Akismet error: " ~ error);
		});
	}
}

// **************************************************************************

class BlogSpam : SpamChecker
{
	private string[string] getParams(PostProcess process)
	{
		return [
			"comment"              : process.draft.clientVars.get("text", ""),
			"ip"                   : process.ip,
			"agent"                : process.headers.get("User-Agent", ""),
			"email"                : process.draft.clientVars.get("email", ""),
			"name"                 : process.draft.clientVars.get("name", ""),
			"site"                 : site.config.proto ~ "://" ~ site.config.host ~ "/",
			"subject"              : process.draft.clientVars.get("subject", ""),
			"version"              : "DFeed (+https://github.com/CyberShadow/DFeed)",
		];
	}

	override void check(PostProcess process, SpamResultHandler handler)
	{
		auto params = getParams(process);

		return httpPost("http://test.blogspam.net:9999/", [Data(toJson(params))], "application/json", (string responseText) {
			auto response = responseText.jsonParse!(string[string]);
			auto result = response.get("result", null);
			auto reason = response.get("reason", "no reason given");
			if (result == "OK")
				handler(true, reason);
			else
			if (result == "SPAM")
				handler(false, "BlogSpam.net thinks your post looks like spam: " ~ reason);
			else
			if (result == "ERROR")
				handler(false, "BlogSpam.net error: " ~ reason);
			else
				handler(false, "BlogSpam.net unexpected response: " ~ result);
		}, (string error) {
			handler(false, "BlogSpam.net error: " ~ error);
		});
	}

	override void sendFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
	{
		auto params = getParams(process);
		string[SpamFeedback] names = [ SpamFeedback.spam : "spam", SpamFeedback.ham : "ok" ];
		params["train"] = names[feedback];
		return httpPost("http://test.blogspam.net:9999/classify", [Data(toJson(params))], "application/json", (string responseText) {
			auto response = responseText.jsonParse!(string[string]);
			auto result = response.get("result", null);
			auto reason = response.get("reason", "no reason given");
			if (result == "OK")
				handler(true, reason);
			else
			if (result == "ERROR")
				handler(false, "BlogSpam.net error: " ~ reason);
			else
				handler(false, "BlogSpam.net unexpected response: " ~ result);
		}, (string error) {
			handler(false, "BlogSpam.net error: " ~ error);
		});
	}
}

// **************************************************************************

class ProjectHoneyPot : SpamChecker
{
	struct Config { string key; }
	Config config;
	this(Config config) { this.config = config; }

	override void check(PostProcess process, SpamResultHandler handler)
	{
		if (!config.key)
			return handler(true, "ProjectHoneyPot is not set up");

		enum DAYS_THRESHOLD  =  7; // consider an IP match as a positive if it was last seen at most this many days ago
		enum SCORE_THRESHOLD = 10; // consider an IP match as a positive if its ProjectHoneyPot score is at least this value

		struct PHPResult
		{
			bool present;
			ubyte daysLastSeen, threatScore, type;
		}

		PHPResult phpCheck(string ip)
		{
			import std.socket;
			string[] sections = split(ip, ".");
			if (sections.length != 4) // IPv6
				return PHPResult(false);
			sections.reverse();
			string addr = ([config.key] ~ sections ~ ["dnsbl.httpbl.org"]).join(".");
			InternetHost ih = new InternetHost;
			if (!ih.getHostByName(addr))
				return PHPResult(false);
			auto resultIP = cast(ubyte[])(&ih.addrList[0])[0..1];
			resultIP.reverse();
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

}


// **************************************************************************

static import ae.utils.xml; // Issue 7016

class StopForumSpam : SpamChecker
{
	override void check(PostProcess process, SpamResultHandler handler)
	{
		enum DAYS_THRESHOLD = 3; // consider an IP match as a positive if it was last seen at most this many days ago

		auto ip = process.ip;

		if (ip.canFind(':') || ip.split(".").length != 4)
		{
			// Not an IPv4 address, skip StopForumSpam check
			return handler(true, "Not an IPv4 address");
		}

		httpGet("http://www.stopforumspam.com/api?ip=" ~ ip, (string result) {
			import std.datetime;
			import ae.utils.xml;
			import ae.utils.time : parseTime;

			auto xml = new XmlDocument(result);
			auto response = xml["response"];
			if (response.attributes["success"] != "true")
			{
				string error = result;
				auto errorNode = response.findChild("error");
				if (errorNode)
					error = errorNode.text;
				enforce(false, "StopForumSpam API error: " ~ error);
			}

			if (response["appears"].text == "no")
				handler(true, null);
			else
			{
				auto date = response["lastseen"].text.parseTime!"Y-m-d H:i:s"();
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
}

// **************************************************************************

class SimpleChecker : SpamChecker
{
	override void check(PostProcess process, SpamResultHandler handler)
	{
		auto ua = process.headers.get("User-Agent", "");

		if (ua.startsWith("WWW-Mechanize"))
			handler(false, "You seem to be posting using an unusual user-agent");

		auto subject = process.draft.clientVars.get("subject", "").toLower();
		foreach (keyword; ["kitchen", "spamtest"])
			if (subject.contains(keyword))
				return handler(false, "Your subject contains a suspicious keyword or character sequence");

		auto text = process.draft.clientVars.get("text", "").toLower();
		foreach (keyword; ["<a href=", "[url=", "[url]http"])
			if (text.contains(keyword))
				return handler(false, "Your post contains a suspicious keyword or character sequence");

		if (subject.length + text.length < 30 && "parent" !in process.draft.serverVars)
			return handler(false, "Your top-level post is suspiciously short");

		handler(true, null);
	}
}

// **************************************************************************

SpamChecker[] spamCheckers;

void initSpamCheckers()
{
	assert(spamCheckers is null);

	import common;
	spamCheckers ~= new SimpleChecker();
	if (auto c = createService!ProjectHoneyPot("apis/projecthoneypot"))
		spamCheckers ~= c;
	if (auto c = createService!Akismet("apis/akismet"))
		spamCheckers ~= c;
	spamCheckers ~= new StopForumSpam();
	//spamCheckers ~= new BlogSpam();
}

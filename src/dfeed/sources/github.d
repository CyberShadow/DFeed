/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.sources.github;

import std.algorithm.searching;
import std.exception;
import std.json;
import std.string;
import std.uni;

import ae.net.http.common;
import ae.sys.dataset;
import ae.utils.array;
import ae.utils.digest;
import ae.utils.sini;
import ae.utils.text;

import dfeed.bitly;
import dfeed.common;

class GitHub : NewsSource
{
	this(Config config)
	{
		super("GitHub");
		this.config = config;
		enforce(config.secret.length, "No secret set");
	}

	struct Config
	{
		string secret;
	}

	immutable Config config;

	override void start() {}
	override void stop () {}

	void handleWebHook(HttpRequest request)
	{
		auto data = cast(string)request.data.joinToHeap();
		auto digest = request.headers.get("X-Hub-Signature", null);
		enforce(digest.length, "No signature");
		enforce(digest.skipOver("sha1="), "Unexpected digest algorithm");
		enforce(icmp(HMAC_SHA1(config.secret.representation, data.representation).toHex(), digest) == 0, "Wrong digest");

		auto event = request.headers.get("X-Github-Event", null);
		log("Got event: " ~ event);
		if (!event.isOneOf("status"))
			announcePost(new GitHubPost(event, data), Fresh.yes);
	}
}

class GitHubPost : Post
{
	this(string event, string data)
	{
		this.event = event;
		this.data = parseJSON(data);
	}

	override void formatForIRC(void delegate(string) handler)
	{
		string str, url;
		switch (event)
		{
			case "ping":
				str = "%s sent a ping (\"%s\")".format(
					data["sender"]["login"].str.filterIRCName,
					data["zen"].str
				);
				break;
			case "push":
				str = "%s pushed %d commit%s to %s %s".format(
					data["sender"]["login"].str.filterIRCName,
					data["commits"].array.length,
					data["commits"].array.length == 1 ? "" : "s",
					data["repository"]["name"].str,
					data["ref"].str.replace("refs/heads/", "branch "),
				);
				url = data["compare"].str;
				break;
			case "pull_request":
				str = "%s %s %s pull request #%s (\"%s\")".format(
					data["sender"]["login"].str.filterIRCName,
					   (data["action"].str == "closed" && data["pull_request"]["merged"].type == JSON_TYPE.TRUE) ? "merged" :
						data["action"].str == "synchronize" ? "updated" :
						data["action"].str,
					data["repository"]["name"].str,
					data["pull_request"]["number"].integer,
					data["pull_request"]["title"].str,
				);
				url = data["pull_request"]["html_url"].str;
				break;
			case "issue_comment":
				str = "%s %s a comment on %s issue #%s (\"%s\")".format(
					data["sender"]["login"].str.filterIRCName,
					data["action"].str,
					data["repository"]["name"].str,
					data["issue"]["number"].integer,
					data["issue"]["title"].str,
				);
				url = data["comment"]["html_url"].str;
				break;
			case "pull_request_review_comment":
				str = "%s %s a review comment on %s pull request #%s (\"%s\")".format(
					data["sender"]["login"].str.filterIRCName,
					data["action"].str,
					data["repository"]["name"].str,
					data["pull_request"]["number"].integer,
					data["pull_request"]["title"].str,
				);
				url = data["comment"]["html_url"].str;
				break;
			case "commit_comment":
				str = "%s %s a comment on %s commit %s".format(
					data["sender"]["login"].str.filterIRCName,
					data["action"].str,
					data["repository"]["name"].str,
					data["comment"]["commit_id"].str[0..8],
				);
				url = data["comment"]["html_url"].str;
				break;
			case "create":
			case "delete":
				str = "%s %sd %s %s on %s".format(
					data["sender"]["login"].str.filterIRCName,
					event,
					data["ref_type"].str,
					data["ref"].str,
					data["repository"]["name"].str,
				);
				if (event == "create")
					url = data["repository"]["html_url"].str ~ "/compare/master..." ~ data["ref"].str;
				break;
			case "fork":
				str = "%s forked %s to %s".format(
					data["sender"]["login"].str.filterIRCName,
					data["repository"]["name"].str,
					data["forkee"]["full_name"].str,
				);
				url = data["forkee"]["html_url"].str;
				break;
			case "watch":
				str = "%s %s watching %s".format(
					data["sender"]["login"].str.filterIRCName,
					data["action"].str,
					data["repository"]["name"].str,
				);
				url = data["sender"]["html_url"].str;
				break;
			default:
				//throw new Exception("Unknown event type: " ~ event);
				str = "(Unknown event: %s)".format(event);
				break;
		}

		str = "[GitHub] " ~ str;

		if (url && getImportance() >= Importance.normal)
			shortenURL(url, (string shortenedURL) {
				handler(str ~ ": " ~ shortenedURL);
			});
		else
		{
			if (url)
				str ~= ": " ~ url;
			handler(str);
		}
	}

	override Importance getImportance()
	{
		debug
			return Importance.low;
		else
			switch (event)
			{
				case "pull_request":
					return data["action"].str.isOneOf("opened", "closed", "reopened") ? Importance.normal : Importance.low;
				default:
					return Importance.low;
			}
	}

private:
	string event;
	JSONValue data;
}

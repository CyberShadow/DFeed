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

module dfeed.sources.mailman;

import std.datetime;
import std.file;
import std.getopt;
import std.random;
import std.string;
import std.regex;

import ae.net.asockets;
import ae.net.http.client;
import ae.sys.dataio;
import ae.sys.file;
import ae.utils.digest;
import ae.utils.gzip;
import ae.sys.data;
import ae.sys.log;
import ae.sys.timing;
import ae.utils.time;

import dfeed.common;
import dfeed.database;
import dfeed.message;

class Mailman : NewsSource
{
	int maxConnections = 5;

	struct ShadowList
	{
		string list, group;
	}

	struct Config
	{
		string baseURL;
		string lists;
		ShadowList[string] shadowLists;
	}
	Config config;

	this(Config config)
	{
		super("Mailman");
		this.config = config;
	}

	override void start()
	{
		foreach (list; config.lists.split(","))
			downloadList(list);
	}

	override void stop()
	{
		stopping = true;
	}

private:
	bool stopping;
	int queued;

	void getURL(string url, void delegate(string fn, bool fresh) callback)
	{
		if (stopping) return;
		if (queued >= maxConnections)
		{
			setTimeout({getURL(url, callback);}, uniform(1, 1000).msecs);
			return;
		}

		auto cachePath = "data/mailman-cache/" ~ getDigestString!MD5(url);
		log("%s URL %s to %s...".format(cachePath.exists ? "Updating" : "Downloading", url, cachePath));

		queued++;
		auto request = new HttpRequest;
		request.resource = url;
		if (cachePath.exists)
			request.headers["If-Modified-Since"] = cachePath.timeLastModified.formatTime!(TimeFormats.RFC2822);
		httpRequest(request,
			(HttpResponse response, string disconnectReason)
			{
				queued--;
				auto okPath = cachePath ~ ".ok";
				if (response && response.status == HttpStatusCode.OK)
				{
					ensurePathExists(cachePath);
					atomicWrite(cachePath, response.getContent().contents);
					callback(cachePath, !okPath.exists);
					okPath.touch();
				}
				else
				if (response && response.status == HttpStatusCode.NotModified)
				{
					callback(cachePath, !okPath.exists);
					okPath.touch();
				}
				else
				{
					log("Error getting URL %s: error=%s status=%s".format(url, disconnectReason, response ? response.status : 0));
					setTimeout({
						log("Retrying...");
						getURL(url, callback);
					}, 10.seconds);
				}
			}
		);
	}

	void downloadList(string list)
	{
		if (stopping) return;
		getURL(config.baseURL ~ list.toLower() ~ "/",
			(string fn, bool fresh)
			{
				log("Got list index: " ~ list);
				if (!fresh)
				{
					log("Stale index, not parsing");
					return;
				}
				auto html = readText(fn);
				auto re = regex(`<A href="(\d+(-\w+)?\.txt(\.gz)?)">`);
				foreach (line; splitLines(html))
				{
					auto m = match(line, re);
					if (!m.empty)
						downloadFile(list, m.captures[1]);
				}
			});
	}

	void downloadFile(string list, string fn)
	{
		if (stopping) return;
		auto url = config.baseURL ~ list.toLower() ~ "/" ~ fn;
		getURL(url,
			(string datafn, bool fresh)
			{
				log("Got %s/%s".format(list, fn));
				if (!fresh)
				{
					log("Stale file, not parsing");
					return;
				}
				auto data = readData(datafn);
				scope(failure) std.file.write("errorfile", data.contents);
				string text;
				if (fn.endsWith(".txt.gz"))
					text = cast(string)(data.uncompress.toHeap);
				else
				if (fn.endsWith(".txt"))
					text = cast(string)(data.toHeap);
				else
					assert(false);
				text = text[text.indexOf('\n')+1..$]; // skip first From line
				auto fromline = regex("\n\nFrom .* at .*  \\w\\w\\w \\w\\w\\w [\\d ]\\d \\d\\d:\\d\\d:\\d\\d \\d\\d\\d\\d\n");
				mixin(DB_TRANSACTION);
				foreach (msg; splitter(text, fromline))
				{
					msg = "X-DFeed-List: " ~ list ~ "\n" ~ msg;
					scope(failure) std.file.write("errormsg", msg);
					Rfc850Post post;
					version (mailman_strict)
						post = new Rfc850Post(msg);
					else
					{
						try
							post = new Rfc850Post(msg);
						catch (Exception e)
						{
							log("Invalid message: " ~ e.msg);
							continue;
						}
					}
					foreach (int n; query!"SELECT COUNT(*) FROM `Posts` WHERE `ID` = ?".iterate(post.id))
						if (n == 0)
						{
							log("Found new post: " ~ post.id);
							announcePost(post, Fresh.no);
						}
				}
			});
	}
}

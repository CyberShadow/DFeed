/*  Copyright (C) 2011, 2014, 2015, 2018, 2023  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.sources.web.reddit;

import std.exception;
import std.string;
import std.regex;
import std.datetime;

import ae.utils.xml;
import ae.net.http.client;
import ae.utils.time;

import dfeed.bitly;
import dfeed.common;
import dfeed.sources.web.webpoller;

class Reddit : WebPoller
{
	static struct Config
	{
		string subreddit;
		string filter;
		int pollPeriod = 60;
	}

	this(Config config)
	{
		this.config = config;
		this.filter = regex(config.filter);
		super("Reddit-" ~ config.subreddit, config.pollPeriod);
	}

private:
	immutable Config config;
	Regex!char filter;

	static string getAuthor(string description)
	{
		auto doc = new XmlDocument(description);
		return strip(doc[1].text);
	}

	class RedditPost : Post
	{
		string title;
		string author;
		string url;

		this(string title, string author, string url, SysTime time)
		{
			this.title = title;
			this.author = author;
			this.url = url;
			this.time = time;
		}

		override void formatForIRC(void delegate(string) handler)
		{
			// TODO: use redd.it
			shortenURL(url, (string shortenedURL) {
				handler(format("[Reddit] %s posted \"%s\": %s", author, title, shortenedURL));
			});
		}
	}

protected:
	override void getPosts()
	{
		auto url = "http://www.reddit.com/r/"~config.subreddit~"/.rss";
		httpGet(url, (HttpResponse response, string disconnectReason) {
			try
			{
				enforce(response, disconnectReason);
				enforce(response.status / 100 == 2, format("HTTP %d (%s)", response.status, response.statusMessage));

				auto result = (cast(char[])response.getContent().contents).idup;
				static import std.utf;
				std.utf.validate(result);

				static import std.file;
				scope(failure) std.file.write("reddit-error.xml", result);

				auto data = new XmlDocument(result);
				Post[string] r;

				auto feed = data["rss"]["channel"];
				foreach (e; feed)
					if (e.tag == "item")
						if (!match(e["title"].text, filter).empty)
							r[e["guid"].text ~ " / " ~ e["pubDate"].text] = new RedditPost(
								e["title"].text,
								getAuthor(e["description"].text),
								e["link"].text,
								e["pubDate"].text.parseTime!(TimeFormats.RSS)()
							);

				handlePosts(r);
			}
			catch (Exception e)
				handleError(e.msg);
		});
	}
}

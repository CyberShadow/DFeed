/*  Copyright (C) 2011, 2012, 2014, 2015, 2016, 2018, 2022  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.sources.web.feed;

import std.exception;
import std.string;
import std.datetime;

import ae.utils.xml;
import ae.net.http.client;

import dfeed.common;
import dfeed.bitly;
import dfeed.sources.web.webpoller;

class Feed : WebPoller
{
	static struct Config
	{
		string name;
		string url;
		string action = "posted";
		int pollPeriod = 60;
	}

	this(Config config)
	{
		this.config = config;
		super(config.name, config.pollPeriod);
	}

private:
	Config config;

	class FeedPost : Post
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
			shortenURL(url, (string shortenedURL) {
				if (config.action.length)
					handler(format("[%s] %s %s \"%s\": %s", this.outer.name, filterIRCName(author), config.action, title, shortenedURL));
				else // author is already indicated in title
					handler(format("[%s] %s: %s", this.outer.name, filterIRCName(title), shortenedURL));
			});
		}
	}

protected:
	override void getPosts()
	{
		httpGet(config.url, (HttpResponse response, string disconnectReason) {
			try
			{
				enforce(response, disconnectReason);
				enforce(response.status / 100 == 2, format("HTTP %d (%s)", response.status, response.statusMessage));

				auto result = (cast(char[])response.getContent().contents).idup;
				static import std.utf;
				std.utf.validate(result);

				static import std.file;
				scope(failure) std.file.write("feed-error.xml", result);
				auto data = new XmlDocument(result);
				Post[string] r;
				auto feed = data["feed"];

				foreach (e; feed)
					if (e.tag == "entry")
					{
						auto key = e["id"].text ~ " / " ~ e["updated"].text;

						auto published = e.findChild("published");
						SysTime time;
						if (published)
							time = SysTime.fromISOExtString(published.text);
						else
							time = Clock.currTime();

						auto post = new FeedPost(e["title"].text, e["author"]["name"].text, e["link"].attributes["href"], time);
						r[key] = post;
					}

				handlePosts(r);
			}
			catch (Exception e)
				handleError(e.msg);
		});
	}
}

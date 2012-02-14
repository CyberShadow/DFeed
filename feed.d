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

module feed;

import std.string;
import std.stream;
import std.datetime;

import ae.utils.xml;
import ae.net.http.client;

import common;
import bitly;
import webpoller;

class Feed : WebPoller
{
	enum POLL_PERIOD = 60;

	this(string name, string url, string action = "posted")
	{
		this.url = url;
		this.action = action;
		super(name, POLL_PERIOD);
	}

private:
	string url, action;

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
				if (action)
					handler(format("[%s] %s %s \"%s\": %s", this.outer.name, author, this.outer.action, title, shortenedURL));
				else // author is already indicated in title
					handler(format("[%s] %s: %s", this.outer.name, title, shortenedURL));
			});
		}
	}

protected:
	override void getPosts()
	{
		httpGet(url, (string result) {
			auto content = cast(char[])result;
			scope(failure) std.file.write("feed-error.xml", content);
			auto data = new XmlDocument(new MemoryStream(content));
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
		}, (string error) {
			handleError(error);
		});
	}
}

module feed;

import std.string;
import std.stream;

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

		this(string title, string author, string url)
		{
			this.title = title;
			this.author = author;
			this.url = url;
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
			auto data = new XmlDocument(new MemoryStream(cast(char[])result));
			Post[string] r;
			auto feed = data["feed"];

			foreach (e; feed)
				if (e.tag == "entry")
				{
					auto key = e["id"].text ~ " / " ~ e["updated"].text;
					auto post = new FeedPost(e["title"].text, e["author"]["name"].text, e["link"].attributes["href"]);
					r[key] = post;
				}

			handlePosts(r);
		}, (string error) {
			handleError(error);
		});
	}
}

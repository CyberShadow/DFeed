module feed;

import std.string;
import std.stream;

import ae.utils.cmd;
import ae.utils.xml;

import common;
import webpoller;

class Feed : WebPoller
{
	enum POLL_PERIOD = 60;

	this(string name, string url, PostHandler postHandler, string action = "posted")
	{
		this.name = name;
		this.url = url;
		this.action = action;
		super(name, POLL_PERIOD, postHandler);
	}

private:
	string name, url, action;

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

		override string toString()
		{
			if (action)
				return format("[%s] %s %s \"%s\": %s", this.outer.name, author, this.outer.action, title, shortenURL(url));
			else // author is already indicated in title
				return format("[%s] %s: %s", this.outer.name, title, shortenURL(url));
		}
	}

protected:
	override Post[string] getPosts()
	{
		auto data = new XmlDocument(new MemoryStream(cast(char[])download(url)));
		Post[string] r;
		auto feed = data["feed"];

		foreach (e; feed)
			if (e.tag == "entry")
				r[e["id"].text ~ " / " ~ e["updated"].text] = new FeedPost(e["title"].text, e["author"]["name"].text, e["link"].attributes["href"]);

		return r;
	}
}

module feed;

import std.string;
import std.stream;

import ae.utils.cmd;
import ae.utils.xml;

import webpoller;

const POLL_PERIOD = 60;

private struct Post
{
	string title;
	string author;
	string url;

	string feedName, action;

	string toString()
	{
		if (action)
			return format("[%s] %s %s \"%s\": %s", feedName, author, action, title, shortenURL(url));
		else // author is already indicated in title
			return format("[%s] %s: %s", feedName, title, shortenURL(url));
	}
}

class Feed : WebPoller!(Post)
{
	this(string name, string url, string action = "posted")
	{
		super(name, POLL_PERIOD);
		this.name = name;
		this.url = url;
		this.action = action;
	}

private:
	string name, url, action;

protected:
	override Post[string] getPosts()
	{
		auto data = new XmlDocument(new MemoryStream(cast(char[])download(url)));
		Post[string] r;
		auto feed = data["feed"];

		foreach (e; feed)
			if (e.tag == "entry")
				r[e["id"].text ~ " / " ~ e["updated"].text] = Post(e["title"].text, e["author"]["name"].text, e["link"].attributes["href"], name, action);

		return r;
	}
}

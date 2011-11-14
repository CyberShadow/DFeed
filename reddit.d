module reddit;

import std.string;
import std.stream;
import std.regex;

import ae.utils.cmd;
import ae.utils.xml;

import webpoller;

const POLL_PERIOD = 60;

private struct Post
{
	string title;
	string author;
	string url;

	string toString()
	{
		return format("[Reddit] %s posted \"%s\": %s", author, title, shortenURL(url));
	}
}

class Reddit : WebPoller!(Post)
{
	this(string subreddit, Regex!char filter)
	{
		super("Reddit", POLL_PERIOD);
		this.subreddit = subreddit;
		this.filter = filter;
	}

private:
	string subreddit;
	Regex!char filter;

	static string getAuthor(string description)
	{
		auto doc = new XmlDocument(new MemoryStream(description.dup));
		return strip(doc[1].text);
	}

protected:
	override Post[string] getPosts()
	{
		auto data = new XmlDocument(new MemoryStream(cast(char[])download("http://www.reddit.com/r/"~subreddit~"/.rss")));
		Post[string] r;

		auto feed = data["rss"]["channel"];
		foreach (e; feed)
			if (e.tag == "item")
				if (!match(e["title"].text, filter).empty)
					r[e["guid"].text ~ " / " ~ e["pubDate"].text] = Post(e["title"].text, getAuthor(e["description"].text), e["link"].text);

		return r;
	}
}

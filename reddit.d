module reddit;

import std.string;
import std.stream;
import std.regex;

import ae.utils.cmd;
import ae.utils.xml;

import common;
import webpoller;

class Reddit : WebPoller
{
	enum POLL_PERIOD = 60;

	this(string subreddit, Regex!char filter, PostHandler postHandler)
	{
		this.subreddit = subreddit;
		this.filter = filter;
		super("Reddit", POLL_PERIOD, postHandler);
	}

private:
	string subreddit;
	Regex!char filter;

	static string getAuthor(string description)
	{
		auto doc = new XmlDocument(new MemoryStream(description.dup));
		return strip(doc[1].text);
	}

	class RedditPost : Post
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
			return format("[Reddit] %s posted \"%s\": %s", author, title, shortenURL(url));
		}
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
					r[e["guid"].text ~ " / " ~ e["pubDate"].text] = new RedditPost(e["title"].text, getAuthor(e["description"].text), e["link"].text);

		return r;
	}
}

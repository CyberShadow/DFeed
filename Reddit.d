module Reddit;

import std.string;
import std.stream;
import std.regexp;

import Team15.Utils;
import Team15.Timing;
import Team15.LiteXML;

import WebPoller;

const POLL_PERIOD = 60 * TicksPerSecond;

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

class Reddit : WebPoller.WebPoller!(Post)
{
	this(string subreddit, RegExp filter)
	{
		super("Reddit", POLL_PERIOD);
		this.subreddit = subreddit;
		this.filter = filter;
	}

private:
	string subreddit;
	RegExp filter;

	static string getAuthor(string description)
	{
		auto doc = new XmlDocument(new MemoryStream(description));
		return strip(doc[1].text);
	}

protected:
	override Post[string] getPosts()
	{
		auto data = new XmlDocument(new MemoryStream(download("http://www.reddit.com/r/"~subreddit~"/.rss")));
		Post[string] r;

		auto feed = data["rss"]["channel"];
		foreach (e; feed)
			if (e.tag == "item")
				if (filter.test(e["title"].text))
					r[e["guid"].text ~ " / " ~ e["pubDate"].text] = Post(e["title"].text, getAuthor(e["description"].text), e["link"].text);

		return r;
	}
}

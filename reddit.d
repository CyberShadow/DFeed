module reddit;

import std.string;
import std.stream;
import std.regex;
import std.datetime;

import ae.utils.xml;
import ae.net.http.client;
import ae.utils.time;

import common;
import webpoller;
import bitly;

class Reddit : WebPoller
{
	enum POLL_PERIOD = 60;

	this(string subreddit, string filter)
	{
		this.subreddit = subreddit;
		this.filter = regex(filter);
		super("Reddit-"~subreddit, POLL_PERIOD);
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
		httpGet("http://www.reddit.com/r/"~subreddit~"/.rss", (string result) {
			auto data = new XmlDocument(new MemoryStream(cast(char[])result));
			Post[string] r;

			auto feed = data["rss"]["channel"];
			foreach (e; feed)
				if (e.tag == "item")
					if (!match(e["title"].text, filter).empty)
						r[e["guid"].text ~ " / " ~ e["pubDate"].text] = new RedditPost(
							e["title"].text,
							getAuthor(e["description"].text),
							e["link"].text,
							parseTime(TimeFormats.RSS, e["pubDate"].text)
						);

			handlePosts(r);
		}, (string error) {
			handleError(error);
		});
	}
}

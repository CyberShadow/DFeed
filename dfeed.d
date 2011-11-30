module dfeed;

import std.file;
import std.getopt;

import ae.net.asockets;

import common;
import web;

// Sources
import newsgroups;
import mailinglists;
import stackoverflow;
import feed;
import reddit;

// Sinks
import ircsink;
import messagedb;

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	// Create sources
	new NntpDownloader("news.digitalmars.com", false);
	new NntpListener("news.digitalmars.com");
	new MailingLists();
	new StackOverflow("d");
	new Feed("Planet D", "http://planetd.thecybershadow.net/_atom.xml");
	new Feed("Wikipedia", "http://en.wikipedia.org/w/api.php?action=feedwatchlist&allrev=allrev&hours=1&"~readText("data/wikipedia.txt")~"&feedformat=atom", "edited");
	//new Feed("GitHub", "https://github.com/"~readText("data/github.txt"), null); // TODO: HTTPS
	new Feed("GitHub", "http://thecybershadow.net/d/ghfeed.php", null);
//	new Reddit("programming", `(^|[^\w\d\-:*=])D([^\w\-:*=]|$)`);
	new Feed("Twitter1", "http://twitter.com/statuses/user_timeline/18061210.atom", null);
	new Feed("Twitter2", "http://twitter.com/statuses/user_timeline/155425162.atom", null);

	// Create sinks
	new IrcSink();
	new MessageDBSink();

	// Start web server
	new WebUI();

	startNewsSources();
	socketManager.loop();
}

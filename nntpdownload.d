module nntpdownload;

import std.getopt;

import ae.net.asockets;

import common;
import newsgroups;
import messagedb;

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	new NntpDownloader("news.digitalmars.com", true);
	new MessageDBSink();

	startNewsSources();
	socketManager.loop();
}

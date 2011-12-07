module nntpdownload;

import std.getopt;

import ae.net.asockets;

import common;
import newsgroups;
import messagedb;

void main(string[] args)
{
	bool full = false;
	getopt(args,
		"q|quiet", &common.quiet,
		"f|full", &full);

	new NntpDownloader("news.digitalmars.com", full);
	new MessageDBSink();

	startNewsSources();
	socketManager.loop();
}

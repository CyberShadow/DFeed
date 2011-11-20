module nntpdownload;

import std.getopt;

import ae.net.asockets;

import common;

// Sources
import newsgroups;

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	new NntpDownloader("news.digitalmars.com");

	startNewsSources();
	socketManager.loop();
}

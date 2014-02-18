/*  Copyright (C) 2011, 2012, 2014  Vladimir Panteleev <vladimir@thecybershadow.net>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module dfeed;

import std.file;
import std.getopt;
import std.stdio;

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
	startNNTP();
	new MailingLists();
	new StackOverflow("d");
	new Feed("Planet D", "http://planetd.thecybershadow.net/_atom.xml");
	new Feed("Wikipedia", "http://en.wikipedia.org/w/api.php?action=feedwatchlist&allrev=allrev&hours=1&"~readText("data/wikipedia.txt")~"&feedformat=atom", "edited");
	//new Feed("GitHub", "https://github.com/"~readText("data/github.txt"), null); // TODO: HTTPS
	new Feed("GitHub", "http://thecybershadow.net/d/ghfeed.php", null);
//	new Reddit("programming", `(^|[^\w\d\-:*=])D([^\w\-:*=]|$)`);
//	new Feed("Twitter-WalterBright", "http://twitter.com/statuses/user_timeline/18061210.atom", null, 120);
//	new Feed("Twitter-incomputable", "http://twitter.com/statuses/user_timeline/155425162.atom", null, 120);
//	new Feed("Twitter-D_programming", "http://twitter.com/statuses/user_timeline/148794328.atom", null, 120);
//	new Feed("Twitter-DigitalMars", "http://twitter.com/statuses/user_timeline/148481064.atom", null, 120);
	new Feed("D Wiki", "http://wiki.dlang.org/?title=Special:RecentChanges&feed=atom", "edited");

	// Create sinks
	new IrcSink();
	new MessageDBSink();

	// Start web server
	new WebUI();

	startNewsSources();
	socketManager.loop();

	if (!common.quiet)
		writeln("Exiting.");
}

/// Avoid any problems (bugs or missed messages) caused by downloader/listener running
/// simultaneously or sequentially by doing the following:
/// 1. Note NNTP server time before starting downloader (sync)
/// 2. Download new messages
/// 3. Start listener with querying for new messages since the download START.
void startNNTP()
{
	auto downloader = new NntpDownloader("news.digitalmars.com", NntpDownloader.Mode.fullPurge);
	auto listener = new NntpListenerSource("news.digitalmars.com");
	downloader.handleFinished = &listener.startListening;
}

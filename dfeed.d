/*  Copyright (C) 2011, 2012, 2014, 2015, 2017  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.getopt;
import std.stdio : stderr;

import ae.net.asockets;
import ae.net.ssl.openssl;
import ae.utils.meta;
import ae.utils.sini;

import backup;
import common;
import web;

// Sources
import newsgroups;
import mailrelay;
import stackoverflow;
import feed;
import reddit;
import socket;
import mailman;
import github;

// Sinks
import ircsink;
import messagedb;
import subscriptions;

// Captcha
import captcha_dcaptcha;

void main(string[] args)
{
	bool refresh;
	bool noSources;
	getopt(args,
		"q|quiet", {}, // handled by ae.sys.log
		"refresh", &refresh,
		"no-sources", &noSources,
	);

	// Create sources
	if (!noSources)
	{
		createServices!NntpSource   ("sources/nntp");
		createServices!MailRelay    ("sources/mailrelay");
		createServices!Feed         ("sources/feeds");
		createServices!StackOverflow("sources/stackoverflow");
		createServices!Reddit       ("sources/reddit");
		createServices!SocketSource ("sources/socket");
		createServices!Mailman      ("sources/mailman");
		createServices!GitHub       ("sources/github");
	}
	if (refresh)
		new MessageDBSource();

	// Create sinks
	createServices!IrcSink("sinks/irc");
	new MessageDBSink(refresh ? Yes.update : No.update);
	new SubscriptionSink();

	// Start web server
	startWebUI();

	startNewsSources();

	socketManager.loop();

	if (!common.quiet)
		stderr.writeln("Exiting.");
}

/// Avoid any problems (bugs or missed messages) caused by downloader/listener running
/// simultaneously or sequentially by doing the following:
/// 1. Note NNTP server time before starting downloader (sync)
/// 2. Download new messages
/// 3. Start listener with querying for new messages since the download START.
class NntpSource
{
	alias Config = NntpConfig;

	this(Config config)
	{
		auto downloader = new NntpDownloader(config.host, isDebug ? NntpDownloader.Mode.newOnly : NntpDownloader.Mode.fullPurge);
		auto listener = new NntpListenerSource(config.host);
		downloader.handleFinished = &listener.startListening;
	}
}

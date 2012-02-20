/*  Copyright (C) 2011, 2012  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Entry point using only sources necessary for the NG web interface.
/// Temporary until we have proper config files. Use this for development.
module dfeed_web;

import std.file;
import std.getopt;

import ae.net.asockets;

import common;
import web;

// Sources
import newsgroups;

// Sinks
import messagedb;

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	// Create sources
	new NntpDownloader("news.digitalmars.com", false);
	new NntpListener("news.digitalmars.com");

	// Create sinks
	new MessageDBSink();

	// Start web server
	new WebUI();

	startNewsSources();
	socketManager.loop();
}

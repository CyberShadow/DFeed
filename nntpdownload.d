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

module nntpdownload;

import std.exception;
import std.getopt;

import ae.net.asockets;
import ae.net.shutdown;

import common;
import newsgroups;
import messagedb;

void main(string[] args)
{
	bool full, purge;
	getopt(args,
		"q|quiet", &common.quiet,
		"f|full", &full,
		"purge", &purge,
	);

	enforce(!(full && purge), "Specify either --full or --purge, not both");
	auto mode = purge ? NntpDownloader.Mode.fullPurge : full ? NntpDownloader.Mode.full : NntpDownloader.Mode.newOnly;

	with (new NntpDownloader("news.digitalmars.com", mode))
		handleFinished = (string date) { shutdown(); };
	new MessageDBSink();

	startNewsSources();
	socketManager.loop();
}

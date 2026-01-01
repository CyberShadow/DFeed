/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2025  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Web server entry point.
module dfeed.web.web.server;

import std.functional : toDelegate;

import dfeed.web.moderation : loadBanList;
import dfeed.web.web.config;
import dfeed.web.web.perf;
import dfeed.web.web.request : onRequest;

import ae.net.http.server : HttpServer;
import ae.net.shutdown;
import ae.sys.log : Logger, createLogger, asyncLogger;

Logger log;
HttpServer server;

void startWebUI()
{
	log = createLogger("Web").asyncLogger();
	static if (measurePerformance) perfLog = createLogger("Performance");

	loadBanList();

	server = new HttpServer();
	server.log = log;
	server.handleRequest = toDelegate(&onRequest);
	server.remoteIPHeader = config.remoteIPHeader;
	server.listen(config.listen.port, config.listen.addr);

	addShutdownHandler((scope const(char)[] reason){ server.close(); });
}

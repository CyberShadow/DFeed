/*  Copyright (C) 2015, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.mail;

import std.exception;
import std.format;
import std.process;

import dfeed.site;

/// Send a fully-formatted (incl. headers) message by email.
void sendMail(string message)
{
	auto pipes = pipeProcess(["sendmail",
			"-t",
			"-r", "%s <no-reply@%s>".format(site.name.length ? site.name : site.host, site.host),
		], Redirect.stdin);
	pipes.stdin.rawWrite(message);
	pipes.stdin.close();
	enforce(wait(pipes.pid) == 0, "mail program failed");
}

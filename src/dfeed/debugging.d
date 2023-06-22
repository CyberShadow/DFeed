/*  Copyright (C) 2023  Vladimir Panteleev <vladimir@thecybershadow.net>
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

// See https://github.com/CyberShadow/ShellUtils/commit/f033d102ce968b71ffa5c0d721922a99d41d302a
module dfeed.debugging;

import core.stdc.stdio;

import dfeed.web.web.page;
import dfeed.web.web.request;

const(char)* _t15_getDebugInfo() @nogc
{
	__gshared char[65536] buf = void;
	auto currentURL = currentRequest ? currentRequest.resource : "(no current request)";
	snprintf(
		buf.ptr,
		buf.length,
		(
			"Current URL: %.*s\n" ~
			"html buffer size: %zu\n"
		).ptr,
		cast(int)currentURL.length, currentURL.ptr,
		html.length,
	);
	return buf.ptr;
}

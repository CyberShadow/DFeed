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

/// Site web stuff.
module dfeed.web.web.site;

import dfeed.loc;
import dfeed.web.web.page;

private string getSiteNotice()
{
	import std.file : readText;
	try
		return readText("config/site-notice.html");
	catch (Exception e)
		return null;
}

void putSiteNotice()
{
	if (auto notice = getSiteNotice())
		html.put(`<div class="forum-notice">`, notice, `</div>`);
}

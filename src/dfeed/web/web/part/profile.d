/*  Copyright (C) 2025  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// User profile utilities.
module dfeed.web.web.part.profile;

import std.ascii : LetterCase;
import std.digest.sha;

import ae.utils.text.html : encodeHtmlEntities;

import dfeed.web.web.page : html;

/// Generate a URL-safe hash for a (name, email) identity tuple.
/// Uses first 32 hex chars of SHA256 of name + null byte + email.
string getProfileHash(string name, string email)
{
	auto hash = sha256Of(name ~ "\0" ~ email);
	return hash.toHexString!(LetterCase.lower)()[0..32].idup;
}

/// Generate the URL path for a user profile.
string profileUrl(string name, string email)
{
	return "/user/" ~ getProfileHash(name, email);
}

/// Output a link to the user's profile page.
void putAuthorLink(string author, string authorEmail)
{
	html.put(`<a href="`, profileUrl(author, authorEmail), `">`);
	html.put(encodeHtmlEntities(author));
	html.put(`</a>`);
}

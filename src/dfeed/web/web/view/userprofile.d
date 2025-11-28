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

/// User profile view.
module dfeed.web.web.view.userprofile;

import std.format : format;

import ae.utils.text.html : encodeHtmlEntities;

import dfeed.database : query, selectValue;
import dfeed.loc;
import dfeed.web.web.page : html, NotFoundException;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.profile : getProfileHash;

/// Look up author name and email from a profile hash.
/// Returns null if not found.
string[2] lookupAuthorByHash(string profileHash)
{
	// Iterate through distinct (Author, AuthorEmail) pairs and find matching hash.
	// This is O(n) in the number of unique authors, but fast in practice
	// since hash computation is cheap and we stop at first match.
	foreach (string author, string email; query!"SELECT DISTINCT [Author], [AuthorEmail] FROM [Posts]".iterate())
	{
		if (getProfileHash(author, email) == profileHash)
			return [author, email];
	}
	return [null, null];
}

/// Display user profile page.
void discussionUserProfile(string profileHash, out string title, out string author)
{
	auto authorInfo = lookupAuthorByHash(profileHash);
	author = authorInfo[0];
	string authorEmail = authorInfo[1];

	if (author is null)
		throw new NotFoundException(_!"User not found");

	title = author;

	// Get post count
	int postCount = query!"SELECT COUNT(*) FROM [Posts] WHERE [Author] = ? AND [AuthorEmail] = ?"
		.iterate(author, authorEmail)
		.selectValue!int;

	string gravatarHash = getGravatarHash(authorEmail);

	// Profile header
	html.put(`<div class="user-profile">`);
	html.put(`<div class="user-profile-header">`);

	// Gravatar
	string gravatarUrl = "https://www.gravatar.com/" ~ gravatarHash;
	html.put(`<div class="user-profile-avatar">`);
	putGravatar(gravatarHash, author, gravatarUrl,
		_!`%s's Gravatar profile`.format(author), null, 128);
	html.put(`</div>`);

	// Name and basic info
	html.put(`<div class="user-profile-info">`);
	html.put(`<h1>`);
	html.put(encodeHtmlEntities(author));
	html.put(`</h1>`);

	html.put(`<p>`);
	html.put(_!`%d posts`.format(postCount));
	html.put(`</p>`);

	html.put(`<p><a href="`, gravatarUrl, `">`, _!`Gravatar profile`, `</a></p>`);

	html.put(`</div>`); // user-profile-info
	html.put(`</div>`); // user-profile-header
	html.put(`</div>`); // user-profile
}

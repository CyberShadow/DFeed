/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Gravatar rendering
module dfeed.web.web.part.gravatar;

import std.conv : text;
import std.format : format;
import std.string;
import std.uni : toLower;

import ae.utils.xmllite : putEncodedEntities;

import dfeed.web.web.page : html;

string gravatar(string authorEmail, int size)
{
	return `https://www.gravatar.com/avatar/%s?d=identicon&s=%d`.format(getGravatarHash(authorEmail), size);
}

enum gravatarMetaSize = 256;

string getGravatarHash(string email)
{
	import std.digest.md;
	import std.ascii : LetterCase;
	return email.toLower().strip().md5Of().toHexString!(LetterCase.lower)().idup; // Issue 9279
}

void putGravatar(string gravatarHash, string personName, string linkTarget, string linkDescription, string aProps = null, int size = 0)
{
	html.put(
		`<a `, aProps, ` href="`), html.putEncodedEntities(linkTarget), html.put(`">` ~
			`<img class="post-gravatar" alt="Gravatar of `), html.putEncodedEntities(personName),
			html.put(`" `);
	if (linkDescription.length)
	{
		html.put(`title="`), html.putEncodedEntities(linkDescription),
		html.put(`" aria-label="`), html.putEncodedEntities(linkDescription),
		html.put(`" `);
	}
	if (size)
	{
		string sizeStr = size ? text(size) : null;
		string x2str = text(size * 2);
		html.put(
			`width="`, sizeStr, `" height="`, sizeStr, `" ` ~
			`src="//www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&amp;s=`, sizeStr, `" ` ~
			`srcset="//www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&amp;s=`, x2str, ` `, x2str, `w"` ~
			`>`
		);
	}
	else
		html.put(
			`src="//www.gravatar.com/avatar/`, gravatarHash, `?d=identicon" ` ~
			`srcset="//www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&amp;s=160 2x"` ~
			`>`
		);
	html.put(`</a>`);
}

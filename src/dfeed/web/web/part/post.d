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

/// Formatting posts.
module dfeed.web.web.part.post;

import ae.net.ietf.message : Rfc850Message;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.message : idToUrl, Rfc850Post, idToFragment;
import dfeed.web.user : User;
import dfeed.web.web : PostInfo, getPostInfo, html;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.statics : staticPath;
import dfeed.web.web.user : user, userSettings;

string postLink(int rowid, string id, string author)
{
	return
		`<a class="postlink ` ~ (user.isRead(rowid) ? "forum-read" : "forum-unread") ~ `" ` ~
			`href="`~ encodeHtmlEntities(idToUrl(id)) ~ `">` ~ encodeHtmlEntities(author) ~ `</a>`;
}

string postLink(PostInfo* info)
{
	return postLink(info.rowid, info.id, info.author);
}

// ***********************************************************************

struct PostAction { string className, text, title, url, icon; }

PostAction[] getPostActions(Rfc850Message msg)
{
	PostAction[] actions;
	auto id = msg.id;
	if (userSettings.groupViewMode == "basic")
		actions ~= PostAction("permalink", "Permalink",
			"Canonical link to this post. See \"Canonical links\" on the Help page for more information.",
			idToUrl(id), "link");
	if (true)
		actions ~= PostAction("replylink", "Reply",
			"Reply to this post",
			idToUrl(id, "reply"), "reply");
/*
	if (mailHide)
		actions ~= PostAction("emaillink", "Email",
			"Solve a CAPTCHA to obtain this poster's email address.",
			mailHide.getUrl(msg.authorEmail), "email");
*/
	if (user.isLoggedIn() && msg.references.length == 0)
		actions ~= PostAction("subscribelink", "Subscribe",
			"Subscribe to this thread",
			idToUrl(id, "subscribe"), "star");
	if (user.getLevel() >= User.Level.canFlag && user.createdAt() < msg.time)
		actions ~= PostAction("flaglink", "Flag",
			"Flag this post for moderator intervention",
			idToUrl(id, "flag"), "flag");
	if (user.getLevel() >= User.Level.hasRawLink)
		actions ~= PostAction("sourcelink", "Source",
			"View this message's source code",
			idToUrl(id, "source"), "source");
	if (user.getLevel() >= User.Level.canDeletePosts)
		actions ~= PostAction("deletelink", "Delete",
			"Delete this message from DFeed's database",
			idToUrl(id, "delete"), "delete");
	return actions;
}

void postActions(PostAction[] actions)
{
	foreach (action; actions)
		html.put(
			`<a class="actionlink `, action.className, `" href="`), html.putEncodedEntities(action.url), html.put(`" ` ~
				`title="`), html.putEncodedEntities(action.title), html.put(`">` ~
				`<img src="`, staticPath("/images/" ~ action.icon~ ".png"), `">`), html.putEncodedEntities(action.text), html.put(
			`</a>`);
}

// ***********************************************************************

string getParentLink(Rfc850Post post, Rfc850Post[string] knownPosts)
{
	if (post.parentID)
	{
		string author, link;
		if (post.parentID in knownPosts)
		{
			auto parent = knownPosts[post.parentID];
			author = parent.author;
			link = '#' ~ idToFragment(parent.id);
		}
		else
		{
			auto parent = getPostInfo(post.parentID);
			if (parent)
			{
				author = parent.author;
				link = idToUrl(parent.id);
			}
		}

		if (author && link)
			return `<a href="` ~ encodeHtmlEntities(link) ~ `">` ~ encodeHtmlEntities(author) ~ `</a>`;
	}

	return null;
}

void miniPostInfo(Rfc850Post post, Rfc850Post[string] knownPosts, bool showActions = true)
{
	string horizontalInfo;
	string gravatarHash = getGravatarHash(post.authorEmail);
	auto parentLink = getParentLink(post, knownPosts);
	with (post.msg)
	{
		html.put(
			`<table class="mini-post-info"><tr>` ~
				`<td class="mini-post-info-avatar">`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 32);
		html.put(
				`</td>` ~
				`<td>` ~
					`Posted by <b>`), html.putEncodedEntities(author), html.put(`</b>`,
					parentLink ? `<br>in reply to ` ~ parentLink : null,
				`</td>`
		);
		if (showActions)
			html.put(
				`<td class="post-info-actions">`), postActions(getPostActions(post.msg)), html.put(`</td>`
			);
		html.put(
			`</tr></table>`
		);
	}
}

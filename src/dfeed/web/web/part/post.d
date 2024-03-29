﻿/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2021  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.algorithm.iteration : map;
import std.array : array, join, replicate;
import std.conv : text;
import std.format;

import ae.net.ietf.message : Rfc850Message;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.loc;
import dfeed.message : idToUrl, Rfc850Post, idToFragment;
import dfeed.web.user : User;
import dfeed.web.web.page : html;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.postbody : formatBody;
import dfeed.web.web.part.strings : formatShortTime, summarizeTime;
import dfeed.web.web.postinfo : PostInfo, getPostInfo, idToThreadUrl;
import dfeed.web.web.statics : staticPath;
import dfeed.web.web.user : user, userSettings;

// ***********************************************************************

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
		actions ~= PostAction("permalink", _!"Permalink",
			_!"Canonical link to this post. See \"Canonical links\" on the Help page for more information.",
			idToUrl(id), "link");
	if (true)
		actions ~= PostAction("replylink", _!"Reply",
			_!"Reply to this post",
			idToUrl(id, "reply"), "reply");
/*
	if (mailHide)
		actions ~= PostAction("emaillink", _!"Email",
			_!"Solve a CAPTCHA to obtain this poster's email address.",
			mailHide.getUrl(msg.authorEmail), "email");
*/
	if (user.isLoggedIn() && msg.references.length == 0)
		actions ~= PostAction("subscribelink", _!"Subscribe",
			_!"Subscribe to this thread",
			idToUrl(id, "subscribe"), "star");
	if (user.getLevel() >= User.Level.canFlag && user.createdAt() < msg.time)
		actions ~= PostAction("flaglink", _!"Flag",
			_!"Flag this post for moderator intervention",
			idToUrl(id, "flag"), "flag");
	if (user.getLevel() >= User.Level.hasRawLink)
		actions ~= PostAction("sourcelink", _!"Source",
			_!"View this message's source code",
			idToUrl(id, "source"), "source");
	if (user.getLevel() >= User.Level.canModerate)
		actions ~= PostAction("modlink", _!"Moderate",
			_!"Perform moderation actions on this post",
			idToUrl(id, "moderate"), "delete");
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
		putGravatar(gravatarHash, author, "http://www.gravatar.com/" ~ gravatarHash, _!`%s's Gravatar profile`.format(author), null, 32);
		html.put(
				`</td>` ~
				`<td>` ~
					_!`Posted by %s`.format(`<b>` ~ encodeHtmlEntities(author) ~ `</b>`),
					parentLink ? `<br>` ~ _!`in reply to` ~ ` ` ~ parentLink : null,
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

// ***********************************************************************

string[] formatPostParts(Rfc850Post post)
{
	string[] partList;
	void visitParts(Rfc850Message[] parts, int[] path)
	{
		foreach (i, part; parts)
		{
			if (part.parts.length)
				visitParts(part.parts, path~cast(int)i);
			else
			if (part.content !is post.content)
			{
				string partUrl = ([idToUrl(post.id, "raw")] ~ array(map!text(path~cast(int)i))).join("/");
				with (part)
					partList ~=
						(name || fileName) ?
							`<a href="` ~ encodeHtmlEntities(partUrl) ~ `" title="` ~ encodeHtmlEntities(mimeType) ~ `">` ~
							encodeHtmlEntities(name) ~
							(name && fileName ? " - " : "") ~
							encodeHtmlEntities(fileName) ~
							`</a>` ~
							(description ? ` (` ~ encodeHtmlEntities(description) ~ `)` : "")
						:
							`<a href="` ~ encodeHtmlEntities(partUrl) ~ `">` ~
							encodeHtmlEntities(mimeType) ~
							`</a> ` ~ _!`part` ~
							(description ? ` (` ~ encodeHtmlEntities(description) ~ `)` : "");
			}
		}
	}
	visitParts(post.parts, null);
	return partList;
}

void formatPost(Rfc850Post post, Rfc850Post[string] knownPosts, bool markAsRead = true)
{
	string gravatarHash = getGravatarHash(post.authorEmail);

	string[] infoBits;

	auto parentLink = getParentLink(post, knownPosts);
	if (parentLink)
		infoBits ~= _!`Posted in reply to` ~ ` ` ~ parentLink;

	auto partList = formatPostParts(post);
	if (partList.length)
		infoBits ~=
			_!`Attachments:` ~ `<ul class="post-info-parts"><li>` ~ partList.join(`</li><li>`) ~ `</li></ul>`;

	if (knownPosts is null && post.cachedThreadID)
		infoBits ~=
			`<a href="` ~ encodeHtmlEntities(idToThreadUrl(post.id, post.cachedThreadID)) ~ `">` ~ _!`View in thread` ~ `</a>`;

	string repliesTitle = encodeHtmlEntities(_!`Replies to %s's post from %s`.format(post.author, formatShortTime(post.time, false)));

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="post forum-table`, (post.children ? ` with-children` : ``), `" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(2), `</tr>` ~ // Fixed layout dummies
			`<tr class="post-header"><th colspan="2">` ~
				`<div class="post-time">`, summarizeTime(time), `</div>` ~
				`<a title="`, _!`Permanent link to this post`, `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="permalink `, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr class="mini-post-info-cell">` ~
				`<td colspan="2">`
		); miniPostInfo(post, knownPosts); html.put(
				`</td>` ~
			`</tr>` ~
			`<tr>` ~
				`<td class="post-info">` ~
					`<div class="post-author">`), html.putEncodedEntities(author), html.put(`</div>`);
		putGravatar(gravatarHash, author, "http://www.gravatar.com/" ~ gravatarHash, _!`%s's Gravatar profile`.format(author), null, 80);
		if (infoBits.length)
		{
			html.put(`<hr>`);
			foreach (b; infoBits)
				html.put(`<div class="post-info-bit">`, b, `</div>`);
		}
		else
			html.put(`<br>`);
		auto actions = getPostActions(post.msg);
		foreach (n; 0..actions.length)
			html.put(`<br>`); // guarantee space for the "toolbar"

		html.put(
					`<div class="post-actions">`), postActions(actions), html.put(`</div>` ~
				`</td>` ~
				`<td class="post-body">`,
//		); miniPostInfo(post, knownPosts); html.put(
					), formatBody(post), html.put(
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td>` ~
			`</tr>` ~
			`</table>` ~
			`</div>`);

		if (post.children)
		{
			html.put(
				`<table class="post-nester"><tr>` ~
				`<td class="post-nester-bar" title="`, /* for IE */ repliesTitle, `">` ~
					`<a href="#`), html.putEncodedEntities(idToFragment(id)), html.put(`" ` ~
						`title="`, repliesTitle, `"></a>` ~
				`</td>` ~
				`<td>`);
			foreach (child; post.children)
				formatPost(child, knownPosts);
			html.put(`</td>` ~
				`</tr></table>`);
		}
	}

	if (post.rowid && markAsRead)
		user.setRead(post.rowid, true);
}

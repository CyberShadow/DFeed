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
module dfeed.web.web.view.post;

import std.algorithm.iteration : map;
import std.array : array, join, replicate;
import std.conv : text;
import std.exception : enforce;

import ae.net.ietf.message : Rfc850Message;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.database : query;
import dfeed.groups : GroupInfo;
import dfeed.message : Rfc850Post, idToUrl, idToFragment, getGroup;
import dfeed.web.web : PostInfo, getPost, idToThreadUrl, formatShortTime, html, summarizeTime, formatBody, formatLongTime, getPostInfo;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.post : getParentLink, miniPostInfo, getPostActions, postActions, postLink, formatPost, formatPostParts;
import dfeed.web.web.part.thread : discussionThreadOverview;
import dfeed.web.web.user : user;

// ***********************************************************************

void discussionVSplitPost(string id)
{
	auto post = getPost(id);
	enforce(post, "Post not found");

	formatPost(post, null);
}

// ***********************************************************************

struct InfoRow { string name, value; }

/// Alternative post formatting, with the meta-data header on top
void formatSplitPost(Rfc850Post post, bool footerNav)
{
	scope(success) user.setRead(post.rowid, true);

	InfoRow[] infoRows;
	string parentLink;

	infoRows ~= InfoRow("From", encodeHtmlEntities(post.author));
	//infoRows ~= InfoRow("Date", format("%s (%s)", formatLongTime(post.time), formatShortTime(post.time, false)));
	infoRows ~= InfoRow("Date", formatLongTime(post.time));

	if (post.parentID)
	{
		auto parent = post.parentID ? getPostInfo(post.parentID) : null;
		if (parent)
		{
			parentLink = postLink(parent.rowid, parent.id, parent.author);
			infoRows ~= InfoRow("In reply to", parentLink);
		}
	}

	string[] replies;
	foreach (int rowid, string id, string author; query!"SELECT `ROWID`, `ID`, `Author` FROM `Posts` WHERE ParentID = ?".iterate(post.id))
		replies ~= postLink(rowid, id, author);
	if (replies.length)
		infoRows ~= InfoRow("Replies", `<span class="avoid-wrap">` ~ replies.join(`,</span> <span class="avoid-wrap">`) ~ `</span>`);

	auto partList = formatPostParts(post);
	if (partList.length)
		infoRows ~= InfoRow("Attachments", partList.join(", "));

	string gravatarHash = getGravatarHash(post.authorEmail);

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="split-post forum-table" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="post-header"><th>` ~
				`<div class="post-time">`, summarizeTime(time), `</div>` ~
				`<a title="Permanent link to this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="`, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr><td class="horizontal-post-info">` ~
				`<table><tr>` ~
					`<td class="post-info-avatar" rowspan="`, text(infoRows.length), `">`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 48);
		html.put(
					`</td>` ~
					`<td><table>`);
		foreach (a; infoRows)
			html.put(`<tr><td class="horizontal-post-info-name">`, a.name, `</td><td class="horizontal-post-info-value">`, a.value, `</td></tr>`);
		html.put(
					`</table></td>` ~
					`<td class="post-info-actions">`), postActions(getPostActions(post.msg)), html.put(`</td>` ~
				`</tr></table>` ~
			`</td></tr>` ~
			`<tr><td class="post-body">` ~
				`<table class="post-layout"><tr class="post-layout-header"><td>`);
		miniPostInfo(post, null);
		html.put(
				`</td></tr>` ~
				`<tr class="post-layout-body"><td>` ~
					`<pre class="post-text">`), formatBody(post), html.put(`</pre>`,
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td></tr>` ~
				`<tr class="post-layout-footer"><td>`
					); postFooter(footerNav, infoRows[1..$]); html.put(
				`</td></tr></table>` ~
			`</td></tr>` ~
			`</table>` ~
			`</div>`
		);
	}
}

void postFooter(bool footerNav, InfoRow[] infoRows)
{
	html.put(
		`<table class="post-footer"><tr>`,
			(footerNav ? `<td class="post-footer-nav"><a href="javascript:navPrev()">&laquo; Prev</a></td>` : null),
			`<td class="post-footer-info">`);
	foreach (a; infoRows)
		html.put(`<div><span class="horizontal-post-info-name">`, a.name, `</span>: <span class="horizontal-post-info-value">`, a.value, `</span></div>`);
	html.put(
			`</td>`,
			(footerNav ? `<td class="post-footer-nav"><a href="javascript:navNext()">Next &raquo;</a></td>` : null),
		`</tr></table>`
	);
}

void discussionSplitPost(string id)
{
	auto post = getPost(id);
	enforce(post, "Post not found");

	formatSplitPost(post, true);
}

void discussionSinglePost(string id, out GroupInfo groupInfo, out string title, out string authorEmail, out string threadID)
{
	auto post = getPost(id);
	enforce(post, "Post not found");
	groupInfo = post.getGroup();
	enforce(groupInfo, "Unknown group");
	title       = post.subject;
	authorEmail = post.authorEmail;
	threadID = post.cachedThreadID;

	formatSplitPost(post, false);
	discussionThreadOverview(threadID, id);
}

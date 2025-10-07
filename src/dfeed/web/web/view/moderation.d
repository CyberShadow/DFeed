﻿/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Moderation views.
module dfeed.web.web.view.moderation;

import std.algorithm.iteration : map, filter, uniq;
import std.algorithm.searching : canFind, findSplit;
import std.algorithm.sorting : sort;
import std.array : array, join;
import std.conv : text;
import std.datetime.systime : Clock;
import std.exception : enforce;
import std.format : format;
import std.string : capitalize, strip;
import std.typecons : Yes, No;

import ae.net.ietf.url : UrlParameters;
import ae.utils.meta : identity;
import ae.utils.sini : loadIni;
import ae.utils.text : splitAsciiLines;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.database : query, selectValue;
import dfeed.groups : getGroupInfo;
import dfeed.loc;
import dfeed.mail : sendMail;
import dfeed.message : Rfc850Post, idToUrl;
import dfeed.site : site;
import dfeed.sources.newsgroups : NntpConfig;
import dfeed.web.posting : PostDraft, PostProcess;
import dfeed.web.user : User;
import dfeed.web.web.draft : getDraft, draftToPost;
import dfeed.web.web.page : html, Redirect;
import dfeed.web.web.part.post : formatPost;
import dfeed.web.web.posting : postDraft;
import dfeed.web.web.moderation : findPostingLog, moderatePost, approvePost, getUnbanPreviewByKey, unbanPoster, UnbanTree;
import dfeed.web.web.user : user, userSettings;

void discussionModeration(Rfc850Post post, UrlParameters postVars)
{
	if (postVars == UrlParameters.init)
	{
		auto sinkNames = post.xref
			.map!(x => x.group.getGroupInfo())
			.filter!(g => g.sinkType == "nntp")
			.map!(g => g.sinkName[])
			.array.sort.uniq
		;
		auto deleteCommands = sinkNames
			.map!(sinkName => loadIni!NntpConfig("config/sources/nntp/" ~ sinkName ~ ".ini").deleteCommand)
			.filter!identity
		;
		html.put(
			`<form method="post" class="forum-form delete-form" id="deleteform">` ~
				`<input type="hidden" name="id" value="`), html.putEncodedEntities(post.id), html.put(`">` ~
				`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~

				`<div id="deleteform-info">` ~
					_!`Perform which moderation actions on this post?` ~
				`</div>` ~

				`<textarea id="deleteform-message" readonly="readonly" rows="25" cols="80">`
					), html.putEncodedEntities(post.message), html.put(
				`</textarea><br>` ~

				`<input type="checkbox" name="delete" value="Yes" checked id="deleteform-delete"></input>` ~
				`<label for="deleteform-delete">` ~
					_!`Delete local cached copy of this post from DFeed's database` ~
				`</label><br>`,

				findPostingLog(post.id)
				?	`<input type="checkbox" name="ban" value="Yes" id="deleteform-ban"></input>` ~
					`<label for="deleteform-ban">` ~
						_!`Ban poster (place future posts in moderation queue)` ~
					`</label><br>`
				: ``,

				!deleteCommands.empty
				?	`<input type="checkbox" name="delsource" value="Yes" id="deleteform-delsource"></input>` ~
					`<label for="deleteform-delsource">` ~
						_!`Delete source copy from %-(%s/%)`.format(sinkNames.map!encodeHtmlEntities) ~
					`</label><br>`
				: ``,

				`<input type="checkbox" name="callsinks" value="Yes" checked id="deleteform-sinks"></input>` ~
				`<label for="deleteform-sinks">` ~
					_!`Try to moderate in other message sinks (e.g. Twitter)` ~
				`</label><br>`,

				_!`Reason:`, ` <input name="reason" value="spam"></input><br>` ~
				`<input type="submit" value="`, _!`Moderate`, `"></input>` ~
			`</form>`
		);
	}
	else
	{
		if (postVars.get("secret", "") != userSettings.secret)
			throw new Exception(_!"XSRF secret verification failed. Are your cookies enabled?");

		string messageID = postVars.get("id", "");
		string userName = user.getName();
		string reason = postVars.get("reason", "");
		bool deleteLocally = postVars.get("delete"   , "No") == "Yes";
		bool ban           = postVars.get("ban"      , "No") == "Yes";
		bool delSource     = postVars.get("delsource", "No") == "Yes";
		bool callSinks     = postVars.get("callsinks", "No") == "Yes";

		if (deleteLocally || ban || delSource)
			moderatePost(
				messageID,
				reason,
				userName,
				deleteLocally ? Yes.deleteLocally : No.deleteLocally,
				ban           ? Yes.ban           : No.ban          ,
				delSource     ? Yes.deleteSource  : No.deleteSource ,
				callSinks     ? Yes.callSinks     : No.callSinks    ,
				(string s) { html.put(encodeHtmlEntities(s) ~ "<br>"); },
			);
		else
			html.put("No actions specified!");
	}
}

void deletePostApi(string group, int artNum)
{
	string messageID;
	foreach (string id; query!"SELECT [ID] FROM [Groups] WHERE [Group] = ? AND [ArtNum] = ?".iterate(group, artNum))
		messageID = id;
	enforce(messageID, "No such article in this group");

	string reason = "API call";
	string userName = "API";

	moderatePost(
		messageID,
		reason,
		userName,
		Yes.deleteLocally,
		No.ban,
		No.deleteSource,
		Yes.callSinks,
		(string s) { html.put(s ~ "\n"); },
	);
}

private void discussionFlagPageImpl(bool flag)(Rfc850Post post, UrlParameters postParams)
{
	static immutable string[2] actions = ["unflag", "flag"];
	bool isFlagged = query!`SELECT COUNT(*) FROM [Flags] WHERE [Username]=? AND [PostID]=?`.iterate(user.getName(), post.id).selectValue!int > 0;
	if (postParams == UrlParameters.init)
	{
		if (flag == isFlagged)
		{
		html.put(
			`<div id="flagform-info" class="forum-notice">` ~
				_!(`It looks like you've already ` ~ actions[flag] ~ `ged this post.`), ` `,
				_!(`Would you like to %s` ~ actions[!flag] ~ ` it%s?`).format(
					`<a href="` ~ encodeHtmlEntities(idToUrl(post.id, actions[!flag])) ~ `">`,
					`</a>`,
				),
			`</div>`);
		}
		else
		{
			html.put(
				`<div id="flagform-info" class="forum-notice">`,
					_!(`Are you sure you want to ` ~ actions[flag] ~ ` this post?`),
				`</div>`);
			formatPost(post, null, false);
			html.put(
				`<form action="" method="post" class="forum-form flag-form" id="flagform">` ~
					`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
					`<input type="submit" name="flag" value="`, _!(actions[flag].capitalize), `"></input>` ~
					`<input type="submit" name="cancel" value="`, _!`Cancel`, `"></input>` ~
				`</form>`);
		}
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, _!"XSRF secret verification failed. Are your cookies enabled?");
		enforce(user.getLevel() >= User.Level.canFlag, _!"You can't flag posts!");
		enforce(user.createdAt() < post.time, _!"You can't flag this post!");

		if ("flag" in postParams)
		{
			enforce(flag != isFlagged, _!("You've already " ~ actions[flag] ~ "ged this post."));

			if (flag)
				query!`INSERT INTO [Flags] ([PostID], [Username], [Date]) VALUES (?, ?, ?)`.exec(post.id, user.getName(), Clock.currTime.stdTime);
			else
				query!`DELETE FROM [Flags] WHERE [PostID]=? AND [Username]=?`.exec(post.id, user.getName());

			html.put(
				`<div id="flagform-info" class="forum-notice">`,
					_!(`Post ` ~ actions[flag] ~ `ged.`),
				`</div>` ~
				`<form action="" method="post" class="forum-form flag-form" id="flagform">` ~
					`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
					`<input type="submit" name="cancel" value="`, _!`Return to post`, `"></input>` ~
				`</form>`);

			static if (flag)
			{
				auto subject = "%s flagged %s's post in the thread \"%s\"".format(
					user.getName(),
					post.author,
					post.subject,
				);

				foreach (mod; site.moderators)
					sendMail(q"EOF
From: %1$s <no-reply@%2$s>
To: %3$s
Subject: %4$s
Content-Type: text/plain; charset=utf-8

Howdy %5$s,

%4$s:
%6$s://%7$s%8$s

Here is the message that was flagged:
----------------------------------------------
%9$-(%s
%)
----------------------------------------------

If you believe this message should be deleted, you can click here to do so:
%6$s://%7$s%10$s

All the best,
%1$s

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
You are receiving this message because you are configured as a site moderator on %2$s.

To stop receiving messages like this, please ask the administrator of %1$s to remove you from the list of moderators.
.
EOF"
						.format(
							/* 1*/ site.name.length ? site.name : site.host,
							/* 2*/ site.host,
							/* 3*/ mod,
							/* 4*/ subject,
							/* 5*/ mod.canFind("<") ? mod.findSplit("<")[0].findSplit(" ")[0] : mod.findSplit("@")[0],
							/* 6*/ site.proto,
							/* 7*/ site.host,
							/* 8*/ idToUrl(post.id),
							/* 9*/ post.content.strip.splitAsciiLines.map!(line => line.length ? "> " ~ line : ">"),
							/*10*/ idToUrl(post.id, "delete"),
						));
			}
		}
		else
			throw new Redirect(idToUrl(post.id));
	}
}

void discussionFlagPage(Rfc850Post post, bool flag, UrlParameters postParams)
{
	if (flag)
		discussionFlagPageImpl!true (post, postParams);
	else
		discussionFlagPageImpl!false(post, postParams);
}

void discussionApprovePage(string draftID, UrlParameters postParams)
{
	auto draft = getDraft(draftID);
	if (draft.status == PostDraft.Status.sent && "pid" in draft.serverVars)
	{
		html.put(_!`This message has already been posted.`, ` ` ~
			`<a href="`), html.putEncodedEntities(idToUrl(PostProcess.pidToMessageID(draft.serverVars["pid"]))), html.put(`">`, _!`You can view it here.`, `</a>`);
		return;
	}
	enforce(draft.status == PostDraft.Status.moderation,
		_!"This is not a post in need of moderation. Its status is currently:" ~ " " ~ text(draft.status));

	if (postParams == UrlParameters.init)
	{
		html.put(
			`<div id="approveform-info" class="forum-notice">`,
				_!`Are you sure you want to approve this post?`,
			`</div>`);
		auto post = draftToPost(draft);
		formatPost(post, null, false);
		html.put(
			`<form action="" method="post" class="forum-form approve-form" id="approveform">` ~
				`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
				`<input type="submit" name="approve" value="`, _!`Approve`, `"></input>` ~
				`<input type="submit" name="cancel" value="`, _!`Cancel`, `"></input>` ~
			`</form>`);
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, _!"XSRF secret verification failed. Are your cookies enabled?");

		if ("approve" in postParams)
		{
			auto pid = approvePost(draftID, user.getName());

			html.put(_!`Post approved!`, ` <a href="/posting/` ~ pid ~ `">`, _!`View posting`, `</a>`);
		}
		else
			throw new Redirect("/");
	}
}

void discussionUnbanByKeyPage(string key, UrlParameters postParams)
{
	import std.algorithm.iteration : map;
	import std.conv : to;

	if (postParams == UrlParameters.init)
	{
		auto tree = getUnbanPreviewByKey(key);
		if (tree.allNodes.length == 0)
		{
			html.put(
				`<div id="unbanform-info" class="forum-notice">`,
					_!`The specified key is not banned.`,
				`</div>` ~
				`<form action="" method="get" class="forum-form unban-form" id="unbanform">` ~
					`<label for="key">`, _!`Key to unban:`, `</label>` ~
					`<input type="text" name="key" id="key" size="60" value="`), html.putEncodedEntities(key), html.put(`">` ~
					`<input type="submit" value="`, _!`Look up`, `"></input>` ~
				`</form>`);
			return;
		}

		html.put(
			`<div id="unbanform-info" class="forum-notice">`,
				_!`Select which keys to unban:`,
			`</div>` ~
			`<style>` ~
				`.unban-tree { margin-left: 0; padding-left: 20px; list-style: none; }` ~
				`.unban-tree li { margin: 8px 0; }` ~
				`.unban-tree .unban-key { font-family: monospace; font-weight: bold; }` ~
				`.unban-tree .unban-reason { color: #666; font-style: italic; }` ~
				`.unban-tree .unban-unban-reason { color: #080; }` ~
				`.unban-node { padding: 4px; }` ~
				`.unban-node:hover { background-color: #f0f0f0; }` ~
			`</style>`);

		void renderNode(UnbanTree.Node* node, int depth = 0)
		{
			html.put(`<li><div class="unban-node">`);
			html.put(`<input type="checkbox" name="key" value="`);
			html.putEncodedEntities(node.key);
			html.put(`" id="key-`, depth.to!string, `-`);
			html.putEncodedEntities(node.key);
			html.put(`" checked> <label for="key-`, depth.to!string, `-`);
			html.putEncodedEntities(node.key);
			html.put(`"><span class="unban-key">`);
			html.putEncodedEntities(node.key);
			html.put(`</span> <span class="unban-reason">(`);
			html.putEncodedEntities(node.reason);
			html.put(`)</span> <span class="unban-unban-reason">— `);
			html.putEncodedEntities(node.unbanReason);
			html.put(`</span></label></div>`);

			if (node.children.length > 0)
			{
				html.put(`<ul class="unban-tree">`);
				foreach (child; node.children)
					renderNode(child, depth + 1);
				html.put(`</ul>`);
			}

			html.put(`</li>`);
		}

		html.put(`<ul class="unban-tree">`);
		foreach (root; tree.roots)
			renderNode(root);
		html.put(`</ul>`);

		html.put(
			`<form action="" method="post" class="forum-form unban-form" id="unbanform">` ~
				`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
				`<input type="hidden" name="lookup-key" value="`), html.putEncodedEntities(key), html.put(`">` ~
				`<input type="submit" name="unban" value="`, _!`Unban Selected`, `"></input>` ~
				`<input type="submit" name="cancel" value="`, _!`Cancel`, `"></input>` ~
			`</form>`);
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, _!"XSRF secret verification failed. Are your cookies enabled?");

		if ("unban" in postParams)
		{
			// Collect all checked keys
			string[] keysToUnban;
			foreach (name, value; postParams)
				if (name == "key")
					keysToUnban ~= value;

			enforce(keysToUnban.length > 0, _!"No keys selected to unban");

			// Use the lookup key as a dummy ID for logging
			auto lookupKey = postParams.get("lookup-key", key);
			unbanPoster(user.getName(), "<unban-by-key:" ~ lookupKey ~ ">", keysToUnban);

			html.put(format(_!`Unbanned %d key(s)!`, keysToUnban.length), ` <a href="/unban">`, _!`Unban another key`, `</a>`);
		}
		else
			throw new Redirect("/");
	}
}

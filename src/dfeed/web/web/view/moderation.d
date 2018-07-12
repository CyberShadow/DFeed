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

/// Moderation views.
module dfeed.web.web.view.moderation;

import std.algorithm.iteration : map;
import std.algorithm.searching : canFind, findSplit;
import std.conv : text;
import std.datetime.systime : Clock;
import std.exception : enforce;
import std.format : format;
import std.string : capitalize, strip;

import ae.net.ietf.headers : Headers;
import ae.net.ietf.url : UrlParameters;
import ae.utils.json : jsonParse;
import ae.utils.text : splitAsciiLines;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.database : query, selectValue;
import dfeed.mail : sendMail;
import dfeed.message : Rfc850Post, idToUrl;
import dfeed.site : site;
import dfeed.web.posting : PostDraft, PostProcess;
import dfeed.web.user : User;
import dfeed.web.web.draft : getDraft, draftToPost, saveDraft;
import dfeed.web.web.posting : postDraft;
import dfeed.web.web.postmod : learnModeratedMessage;
import dfeed.web.web.request : html, Redirect;
import dfeed.web.web.moderation : findPostingLog, deletePostImpl;
import dfeed.web.web.view.post : formatPost;
import dfeed.web.web.user : user, userSettings;

void deletePost(UrlParameters vars)
{
	if (vars.get("secret", "") != userSettings.secret)
		throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

	string messageID = vars.get("id", "");
	string userName = user.getName();
	string reason = vars.get("reason", "");
	bool ban = vars.get("ban", "No") == "Yes";

	deletePostImpl(messageID, reason, userName, ban, (string s) { html.put(s ~ "<br>"); });
}

void deletePostApi(string group, int artNum)
{
	string messageID;
	foreach (string id; query!"SELECT [ID] FROM [Groups] WHERE [Group] = ? AND [ArtNum] = ?".iterate(group, artNum))
		messageID = id;
	enforce(messageID, "No such article in this group");

	string reason = "API call";
	string userName = "API";
	bool ban = false;

	deletePostImpl(messageID, reason, userName, ban, (string s) { html.put(s ~ "\n"); });
}

void discussionDeleteForm(Rfc850Post post)
{
	html.put(
		`<form action="/dodelete" method="post" class="forum-form delete-form" id="deleteform">` ~
		`<input type="hidden" name="id" value="`), html.putEncodedEntities(post.id), html.put(`">` ~
		`<div id="deleteform-info">` ~
			`Are you sure you want to delete this post from DFeed's database?` ~
		`</div>` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`<textarea id="deleteform-message" readonly="readonly" rows="25" cols="80">`), html.putEncodedEntities(post.message), html.put(`</textarea><br>` ~
		`Reason: <input name="reason" value="spam"></input><br>`,
		 findPostingLog(post.id)
			? `<input type="checkbox" name="ban" value="Yes" id="deleteform-ban"></input><label for="deleteform-ban">Also ban the poster from accessing the forum</label><br>`
			: ``,
		`<input type="submit" value="Delete"></input>` ~
	`</form>`);
}

void discussionFlagPage(Rfc850Post post, bool flag, UrlParameters postParams)
{
	static immutable string[2] actions = ["unflag", "flag"];
	bool isFlagged = query!`SELECT COUNT(*) FROM [Flags] WHERE [Username]=? AND [PostID]=?`.iterate(user.getName(), post.id).selectValue!int > 0;
	if (postParams == UrlParameters.init)
	{
		if (flag == isFlagged)
		{
		html.put(
			`<div id="flagform-info" class="forum-notice">` ~
				`It looks like you've already ` ~ actions[flag] ~ `ged this post. ` ~
				`Would you like to <a href="`), html.putEncodedEntities(idToUrl(post.id, actions[!flag])), html.put(`">` ~ actions[!flag] ~ ` it</a>?` ~
			`</div>`);
		}
		else
		{
			html.put(
				`<div id="flagform-info" class="forum-notice">` ~
					`Are you sure you want to ` ~ actions[flag] ~ ` this post?` ~
				`</div>`);
			formatPost(post, null, false);
			html.put(
				`<form action="" method="post" class="forum-form flag-form" id="flagform">` ~
					`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
					`<input type="submit" name="flag" value="` ~ actions[flag].capitalize ~ `"></input>` ~
					`<input type="submit" name="cancel" value="Cancel"></input>` ~
				`</form>`);
		}
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, "XSRF secret verification failed. Are your cookies enabled?");
		enforce(user.getLevel() >= User.Level.canFlag, "You can't flag posts!");
		enforce(user.createdAt() < post.time, "You can't flag this post!");

		if ("flag" in postParams)
		{
			enforce(flag != isFlagged, "You've already " ~ actions[flag] ~ "ged this post.");

			if (flag)
				query!`INSERT INTO [Flags] ([PostID], [Username], [Date]) VALUES (?, ?, ?)`.exec(post.id, user.getName(), Clock.currTime.stdTime);
			else
				query!`DELETE FROM [Flags] WHERE [PostID]=? AND [Username]=?`.exec(post.id, user.getName());

			html.put(
				`<div id="flagform-info" class="forum-notice">` ~
					`Post ` ~ actions[flag] ~ `ged.` ~
				`</div>` ~
				`<form action="" method="post" class="forum-form flag-form" id="flagform">` ~
					`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
					`<input type="submit" name="cancel" value="Return to post"></input>` ~
				`</form>`);

			if (flag)
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

void discussionApprovePage(string draftID, UrlParameters postParams)
{
	auto draft = getDraft(draftID);
	if (draft.status == PostDraft.Status.sent && "pid" in draft.serverVars)
	{
		html.put(`This message has already been posted.`);
		html.put(`<a href="`), html.putEncodedEntities(idToUrl(PostProcess.pidToMessageID(draft.serverVars["pid"]))), html.put(`">You can view it here.</a>`);
		return;
	}
	enforce(draft.status == PostDraft.Status.moderation,
		"This is not a post in need of moderation. Its status is currently: " ~ text(draft.status));

	if (postParams == UrlParameters.init)
	{
		html.put(
			`<div id="approveform-info" class="forum-notice">` ~
				`Are you sure you want to approve this post?` ~
			`</div>`);
		auto post = draftToPost(draft);
		formatPost(post, null, false);
		html.put(
			`<form action="" method="post" class="forum-form approve-form" id="approveform">` ~
				`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
				`<input type="submit" name="approve" value="Approve"></input>` ~
				`<input type="submit" name="cancel" value="Cancel"></input>` ~
			`</form>`);
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, "XSRF secret verification failed. Are your cookies enabled?");

		if ("approve" in postParams)
		{
			draft.serverVars["preapproved"] = null;
			auto headers = Headers(draft.serverVars.get("headers", "null").jsonParse!(string[][string]));
			auto pid = postDraft(draft, headers);
			saveDraft(draft);

			learnModeratedMessage(draft, false, 10);

			html.put(`Post approved! <a href="/posting/` ~ pid ~ `">View posting</a>`);
		}
		else
			throw new Redirect("/");
	}
}

/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2021, 2022  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Authoring new posts.
module dfeed.web.web.posting;

import core.time : seconds, minutes, weeks;

import std.algorithm.iteration : map;
import std.algorithm.searching : canFind, findSplit;
import std.conv : to;
import std.datetime.systime : SysTime, Clock;
import std.datetime.timezone : UTC;
import std.exception : enforce;
import std.format : format;
import std.string : strip;

import ae.net.ietf.headers : Headers;
import ae.net.ietf.url : UrlParameters;
import ae.utils.aa : aaGet;
import ae.utils.json : toJson, jsonParse;
import ae.utils.meta : I, isDebug;
import ae.utils.sini : loadIni;
import ae.utils.text : splitAsciiLines;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite;

import dfeed.loc;
import dfeed.database : query;
import dfeed.groups : getGroupInfo;
import dfeed.mail : sendMail;
import dfeed.message : idToUrl;
import dfeed.sinks.subscriptions : createReplySubscription;
import dfeed.site : site;
import dfeed.web.captcha;
import dfeed.web.lint : getLintRule, lintRules;
import dfeed.web.markdown : haveMarkdown;
import dfeed.web.posting : PostDraft, PostProcess, PostError, SmtpConfig, PostingStatus;
import dfeed.web.web.draft : getDraft, saveDraft, draftToPost;
import dfeed.web.web.page : html;
import dfeed.web.web.part.post : formatPost, postLink;
import dfeed.web.web.part.strings : formatShortTime, formatDuration;
import dfeed.web.web.postinfo : getPostInfo, getPost;
import dfeed.web.web.postmod : shouldModerate, learnModeratedMessage;
import dfeed.web.web.request : ip;
import dfeed.web.web.user : user, userSettings;

void draftNotices(string except = null)
{
	foreach (string id, long time; query!"SELECT [ID], [Time] FROM [Drafts] WHERE [UserID]==? AND [Status]==?".iterate(userSettings.id, PostDraft.Status.edited))
	{
		if (id == except)
			continue;
		auto t = SysTime(time, UTC());
		html.put(`<div class="forum-notice">`,
			_!`You have an %sunsent draft message from %s%s.`.format(
				`<a href="/posting/` ~ id ~ `">`, formatShortTime(t, false), `</a>`
			),
			`</div>`);
	}
}

bool discussionPostForm(PostDraft draft, Captcha captcha=null, PostError error=PostError.init)
{
	auto draftID = draft.clientVars.get("did", null);
	draftNotices(draftID);

	if (draft.status == PostDraft.Status.moderation)
		throw new Exception(_!"This message is awaiting moderation.");

	// Only happens if visiting a posting page when it's not in
	// postProcesses, i.e., from a previous DFeed process instance.
	if (draft.status == PostDraft.Status.sent)
		throw new Exception(_!"This message has already been posted.");

	// Immediately resurrect discarded posts when user clicks "Undo" or "Back"
	if (draft.status == PostDraft.Status.discarded)
		query!"UPDATE [Drafts] SET [Status]=? WHERE [ID]=?".exec(PostDraft.Status.edited, draftID);

	auto where = draft.serverVars.get("where", null);
	auto info = getGroupInfo(where);
	if (!info)
		throw new Exception(_!"Unknown group:" ~ " " ~ where);
	if (info.postMessage)
	{
		html.put(
			`<table class="forum-table forum-error">` ~
				`<tr><th>`, _!`Can't post to archive`, `</th></tr>` ~
				`<tr><td class="forum-table-message">`
					, info.postMessage,
				`</td></tr>` ~
			`</table>`);
		return false;
	}
	if (info.sinkType == "smtp" && info.subscriptionRequired)
	{
		auto config = loadIni!SmtpConfig("config/sources/smtp/" ~ info.sinkName ~ ".ini");
		html.put(`<div class="forum-notice">`, _!`Note: you are posting to a mailing list.`, `<br>`,
			_!`Your message will not go through unless you %ssubscribe to the mailing list%s first.`.format(
				`<a href="` ~ encodeHtmlEntities(config.listInfo ~ info.internalName) ~`">`,
				`</a>`,
			), `<br>`,
			_!`You must then use the same email address when posting here as the one you used to subscribe to the list.`, `<br>`,
			_!`If you do not want to receive mailing list mail, you can disable mail delivery at the above link.`, `</div>`);
	}

	auto parent = draft.serverVars.get("parent", null);
	auto parentInfo	= parent ? getPostInfo(parent) : null;
	if (parentInfo && Clock.currTime - parentInfo.time > 2.weeks)
		html.put(`<div class="forum-notice">`, _!`Warning: the post you are replying to is from`, ` `,
			formatDuration(Clock.currTime - parentInfo.time), ` (`, formatShortTime(parentInfo.time, false), `).</div>`);

	html.put(`<form action="/send" method="post" class="forum-form post-form" id="postform">`);

	if (error.message)
		html.put(`<div class="form-error">`), html.putEncodedEntities(error.message), html.put(error.extraHTML, `</div>`);
	html.put(draft.clientVars.get("html-top", null));

	if (parent)
		html.put(`<input type="hidden" name="parent" value="`), html.putEncodedEntities(parent), html.put(`">`);
	else
		html.put(`<input type="hidden" name="where" value="`), html.putEncodedEntities(where), html.put(`">`);

	auto subject = draft.clientVars.get("subject", null);

	html.put(
		`<div id="postform-info">`,
			_!`Posting to`, ` <b>`), html.putEncodedEntities(info.publicName), html.put(`</b>`,
			(parent
				? parentInfo
					? ` ` ~ _!`in reply to` ~ ` ` ~ postLink(parentInfo)
					: ` ` ~ _!`in reply to` ~ ` (` ~ _!`unknown post` ~ `)`
				: info
					? `:<br>(<b>` ~ encodeHtmlEntities(info.description) ~ `</b>)`
					: ``),
		`</div>` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`<input type="hidden" name="did" value="`), html.putEncodedEntities(draftID), html.put(`">` ~
		`<label for="postform-name">`, _!`Your name:` ~ `</label>`,
		`<input id="postform-name" name="name" size="40" value="`), html.putEncodedEntities(draft.clientVars.get("name", null)), html.put(`">` ~
		`<label for="postform-email">`, _!`Your email address`, ` (<a href="/help#email">?</a>):</label>` ~
		`<input id="postform-email" type="email" name="email" size="40" value="`), html.putEncodedEntities(draft.clientVars.get("email", null)), html.put(`">` ~
		`<label for="postform-subject">`, _!`Subject:`, `</label>` ~
		`<input id="postform-subject" name="subject" size="80"`, subject.length ? `` : ` autofocus`, ` value="`), html.putEncodedEntities(subject), html.put(`">` ~
		`<label for="postform-text">`, _!`Message:`, `</label>` ~
		`<textarea id="postform-text" name="text" rows="25" cols="80"`, subject.length ? ` autofocus` : ``, `>`), html.putEncodedEntities(draft.clientVars.get("text", null)), html.put(`</textarea>`);

	if (captcha)
		html.put(`<div id="postform-captcha">`, captcha.getChallengeHtml(error.captchaError), `</div>`);

	html.put(
		`<div>` ~
			`<div class="postform-action-left">` ~
				`<input name="action-save" type="submit" value="`, _!`Save and preview`, `">` ~
				`<input name="action-send" type="submit" value="`, _!`Send`, `">`);
				if (haveMarkdown && userSettings.renderMarkdown == "true") html.put(
					`<label for="postform-markdown"><input name="markdown" id="postform-markdown" type="checkbox" `,
						("markdown" in draft.clientVars ? `checked="checked"` : ""),
						`> `, _!"Enable %sMarkdown%s".format(`<a href="/help#markdown">`, `</a>`), `</label>`);
			html.put(`</div>` ~
			`<div class="postform-action-right">` ~
				`<input name="action-discard" type="submit" value="`, _!`Discard draft`, `">` ~
			`</div>` ~
			`<div style="clear:right"></div>` ~
		`</div>` ~
	`</form>`);
	return true;
}

/// Calculate a secret string from a key.
/// Can be used in URLs in emails to authenticate an action on a
/// public/guessable identifier.
version(none)
string authHash(string s)
{
	import dfeed.web.user : userConfig = config;
	auto digest = sha256Of(s ~ userConfig.salt);
	return Base64.encode(digest)[0..10];
}

SysTime[][string] lastPostAttempts;

// Reject posts if the threshold of post attempts is met under the
// given time limit.
enum postThrottleRejectTime = 30.seconds;
enum postThrottleRejectCount = 3;

// Challenge posters with a CAPTCHA if the threshold of post attempts
// is met under the given time limit.
enum postThrottleCaptchaTime = 3.minutes;
enum postThrottleCaptchaCount = 3;

string discussionSend(UrlParameters clientVars, Headers headers)
{
	import std.algorithm.iteration : filter;
	import std.algorithm.searching : startsWith;
	import std.range : chain, only;

	auto draftID = clientVars.get("did", null);
	auto draft = getDraft(draftID);

	try
	{
		if (draft.status == PostDraft.Status.sent)
		{
			// Redirect if we know where to
			if ("pid" in draft.serverVars)
				return idToUrl(PostProcess.pidToMessageID(draft.serverVars["pid"]));
			else
				throw new Exception(_!"This message has already been sent.");
		}

		if (clientVars.get("secret", "") != userSettings.secret)
			throw new Exception(_!"XSRF secret verification failed. Are your cookies enabled?");

		if (draft.status == PostDraft.Status.moderation)
			throw new Exception(_!"This message is awaiting moderation.");
		
		draft.clientVars = clientVars;
		draft.status = PostDraft.Status.edited;
		scope(exit) saveDraft(draft);

		auto action = clientVars.byKey.filter!(key => key.startsWith("action-")).chain("action-none".only).front[7..$];

		static struct UndoInfo { UrlParameters clientVars; string[string] serverVars; }
		bool lintDetails;
		if (action.startsWith("lint-ignore-"))
		{
			draft.serverVars[action] = null;
			action = "send";
		}
		else
		if (action.startsWith("lint-fix-"))
		{
			auto ruleID = action[9..$];
			try
			{
				draft.serverVars["lint-undo"] = UndoInfo(draft.clientVars, draft.serverVars).toJson;
				getLintRule(ruleID).fix(draft);
				draft.clientVars["html-top"] = `<div class="forum-notice">` ~ _!`Automatic fix applied.` ~ ` ` ~
					`<input name="action-lint-undo" type="submit" value="` ~ _!`Undo` ~ `"></div>`;
			}
			catch (Exception e)
			{
				draft.serverVars["lint-ignore-" ~ ruleID] = null;
				html.put(`<div class="forum-notice">` ~ _!`Sorry, a problem occurred while attempting to fix your post` ~ ` ` ~
					`(`), html.putEncodedEntities(e.msg), html.put(`).</div>`);
			}
			discussionPostForm(draft);
			return null;
		}
		else
		if (action == "lint-undo")
		{
			enforce("lint-undo" in draft.serverVars, _!"Undo information not found.");
			auto undoInfo = draft.serverVars["lint-undo"].jsonParse!UndoInfo;
			draft.clientVars = undoInfo.clientVars;
			draft.serverVars = undoInfo.serverVars;
			html.put(`<div class="forum-notice">` ~ _!`Automatic fix undone.` ~ `</div>`);
			discussionPostForm(draft);
			return null;
		}
		else
		if (action == "lint-explain")
		{
			lintDetails = true;
			action = "send";
		}

		switch (action)
		{
			case "save":
			{
				discussionPostForm(draft);
				// Show preview
				auto post = draftToPost(draft, headers, ip);
				post.compile();
				formatPost(post, null);
				return null;
			}
			case "send":
			{
				userSettings.name  = aaGet(clientVars, "name");
				userSettings.email = aaGet(clientVars, "email");

				foreach (rule; lintRules)
					if ("lint-ignore-" ~ rule.id !in draft.serverVars && rule.check(draft))
					{
						PostError error;
						error.message = _!"Warning:" ~ " " ~ rule.shortDescription();
						error.extraHTML ~= ` <input name="action-lint-ignore-` ~ rule.id ~ `" type="submit" value="` ~ _!`Ignore` ~ `">`;
						if (!lintDetails)
							error.extraHTML ~= ` <input name="action-lint-explain" type="submit" value="` ~ _!`Explain` ~ `">`;
						if (rule.canFix(draft))
							error.extraHTML ~= ` <input name="action-lint-fix-` ~ rule.id ~ `" type="submit" value="` ~ _!`Fix it for me` ~ `">`;
						if (lintDetails)
							error.extraHTML ~= `<div class="lint-description">` ~ rule.longDescription() ~ `</div>`;
						discussionPostForm(draft, null, error);
						return null;
					}

				auto now = Clock.currTime();

				auto ipPostAttempts = lastPostAttempts.get(ip, null);
				if (ipPostAttempts.length >= postThrottleRejectCount && now - ipPostAttempts[$-postThrottleRejectCount+1] < postThrottleRejectTime)
				{
					discussionPostForm(draft, null,
						PostError(_!"You've attempted to post %d times in the past %s. Please wait a little bit before trying again."
							.format(postThrottleRejectCount, postThrottleRejectTime)));
					return null;
				}

				if (ipPostAttempts.length >= postThrottleCaptchaCount && now - ipPostAttempts[$-postThrottleCaptchaCount+1] < postThrottleCaptchaTime)
				{
					auto captcha = getCaptcha(draftToPost(draft).captcha);
					if (captcha)
					{
						bool captchaPresent = captcha.isPresent(clientVars);
						if (!captchaPresent)
						{
							discussionPostForm(draft, captcha,
								PostError(_!"You've attempted to post %d times in the past %s. Please solve a CAPTCHA to continue."
									.format(postThrottleCaptchaCount, postThrottleCaptchaTime)));
							return null;
						}
					}
					else
					{
						discussionPostForm(draft, null,
							PostError(_!"You've attempted to post %d times in the past %s. Please wait a little bit before trying again."
								.format(postThrottleCaptchaCount, postThrottleCaptchaTime)));
						return null;
					}
				}

				if (auto reason = shouldModerate(draft))
				{
					// draft will be saved by scope(exit) above
					moderateMessage(draft, headers, reason);

					html.put(`<p>`, _!`Your message has been saved, and will be posted after being approved by a moderator.`, `</p>`);
					return null;
				}

				auto pid = postDraft(draft, headers);

				lastPostAttempts[ip] ~= Clock.currTime();
				if (user.isLoggedIn())
					createReplySubscription(user.getName());

				return "/posting/" ~ pid;
			}
			case "discard":
			{
				// Show undo notice
				userSettings.pendingNotice = "draft-deleted:" ~ draftID;
				// Mark as deleted
				draft.status = PostDraft.Status.discarded;
				// Redirect to relevant page
				if ("parent" in draft.serverVars)
					return idToUrl(draft.serverVars["parent"]);
				else
				if ("where" in draft.serverVars)
					return "/group/" ~ draft.serverVars["where"];
				else
					return "/";
			}
			default:
				throw new Exception(_!"Unknown action");
		}
	}
	catch (Exception e)
	{
		auto error = isDebug ? e.toString() : e.msg;
		discussionPostForm(draft, null, PostError(error));
		return null;
	}
}

string postDraft(ref PostDraft draft, Headers headers)
{
	auto parent = "parent" in draft.serverVars ? getPost(draft.serverVars["parent"]) : null;
	auto process = new PostProcess(draft, user, userSettings.id, ip, headers, parent);
	if (process.status == PostingStatus.redirect)
		return process.pid;
	process.run();
	draft.serverVars["pid"] = process.pid;

	return process.pid;
}

void moderateMessage(ref PostDraft draft, Headers headers, string reason)
{
	import std.range : chain, only;

	learnModeratedMessage(draft, true, 1);
	draft.serverVars["headers"] = headers.to!(string[][string]).toJson;
	draft.status = PostDraft.Status.moderation;

	string sanitize(string s) { return "%(%s%)".format(s.only)[1..$-1]; }

	try
	{
		import std.file : readText;
		auto badStrings = "config/known-spammers.txt".readText();
		foreach (badString; badStrings)
			if (draft.clientVars.get("text", null).canFind(badString))
			{
				import ae.sys.log : fileLogger;
				auto moderationLog = fileLogger("Deleted");
				scope(exit) moderationLog.close();

				moderationLog("Silently ignoring known spammer: " ~ draft.clientVars.get("did", "").I!sanitize);
				return;
			}
	}
	catch (Exception e) {}

	string context;
	{
		context = `The message was submitted`;
		string contextURL = null;
		auto urlPrefix = site.proto ~ "://" ~ site.host;
		if (auto parentID = "parent" in draft.serverVars)
		{
			context ~= ` in reply to `;
			auto parent = getPostInfo(*parentID);
			if (parent)
				context ~= parent.author.I!sanitize ~ "'s post";
			else
				context ~= "a post";
			contextURL = urlPrefix ~ idToUrl(*parentID);
		}
		if ("where" in draft.serverVars)
		{
			context ~= ` on the ` ~ draft.serverVars["where"] ~ ` group`;
			if (!contextURL)
				contextURL = urlPrefix ~  `/group/` ~ draft.serverVars["where"];
		}
		else
			context ~= ` on an unknown group`;

		context ~= contextURL ? ":\n" ~ contextURL : ".";
	}

	foreach (mod; site.moderators)
		sendMail(q"EOF
From: %1$s <no-reply@%2$s>
To: %3$s
Subject: Please moderate: post by %5$s with subject "%7$s"
Content-Type: text/plain; charset=utf-8

Howdy %4$s,

User %5$s <%6$s> attempted to post a message with the subject "%7$s".
This post was held for moderation for the following reason: %8$s

Here is the message:
----------------------------------------------
%9$-(%s
%)
----------------------------------------------

%13$s

IP address this message was posted from: %12$s

You can preview and approve this message here:
%10$s://%2$s/approve-moderated-draft/%11$s

Otherwise, no action is necessary.

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
			/* 4*/ mod.canFind("<") ? mod.findSplit("<")[0].findSplit(" ")[0] : mod.findSplit("@")[0],
			/* 5*/ draft.clientVars.get("name", "").I!sanitize,
			/* 6*/ draft.clientVars.get("email", "").I!sanitize,
			/* 7*/ draft.clientVars.get("subject", "").I!sanitize,
			/* 8*/ reason,
			/* 9*/ draft.clientVars.get("text", "").strip.splitAsciiLines.map!(line => line.length ? "> " ~ line : ">"),
			/*10*/ site.proto,
			/*11*/ draft.clientVars.get("did", "").I!sanitize,
			/*12*/ ip,
			/*13*/ context,
		));
}

void discussionPostStatusMessage(string messageHtml)
{
	html.put(
		`<table class="forum-table">` ~
			`<tr><th>`, _!`Posting status`, `</th></tr>` ~
			`<tr><td class="forum-table-message">`, messageHtml, `</th></tr>` ~
		`</table>`);
}

void discussionPostStatus(PostProcess process, out bool refresh, out string redirectTo, out bool form)
{
	refresh = form = false;
	PostError error = process.error;
	switch (process.status)
	{
		case PostingStatus.spamCheck:
			// discussionPostStatusMessage(_!"Checking for spam...");
			discussionPostStatusMessage(_!"Validating...");
			refresh = true;
			return;
		case PostingStatus.captcha:
			discussionPostStatusMessage(_!"Verifying reCAPTCHA...");
			refresh = true;
			return;
		case PostingStatus.connecting:
			discussionPostStatusMessage(_!"Connecting to server...");
			refresh = true;
			return;
		case PostingStatus.posting:
			discussionPostStatusMessage(_!"Sending message to server...");
			refresh = true;
			return;
		case PostingStatus.waiting:
			discussionPostStatusMessage(_!"Message sent." ~ "<br>" ~ _!"Waiting for message announcement...");
			refresh = true;
			return;

		case PostingStatus.posted:
			redirectTo = idToUrl(process.post.id);
			discussionPostStatusMessage(_!`Message posted! Redirecting...`);
			refresh = true;
			return;

		case PostingStatus.captchaFailed:
			discussionPostForm(process.draft, getCaptcha(process.post.captcha), error);
			form = true;
			return;
		case PostingStatus.spamCheckFailed:
			if (auto captcha = getCaptcha(process.post.captcha))
			{
				error.message = format(_!"%s. Please solve a CAPTCHA to continue.", error.message);
				discussionPostForm(process.draft, captcha, error);
				form = true;
			}
			else
			{
				moderateMessage(process.draft, process.headers,
					"No CAPTCHA configured and spam check failed: " ~ error.message);
				saveDraft(process.draft);
				discussionPostStatusMessage(_!`Your message has been saved, and will be posted after being approved by a moderator.`);
			}
			return;
		case PostingStatus.serverError:
			discussionPostForm(process.draft, null, error);
			form = true;
			return;

		default:
			discussionPostStatusMessage("???");
			refresh = true;
			return;
	}
}

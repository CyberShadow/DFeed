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

module dfeed.web.web;

import core.time;

import std.algorithm;
import std.array;
import std.base64;
import std.conv;
import std.datetime : SysTime, Clock, UTC;
import std.digest.sha;
import std.exception;
import std.file;
import std.functional;
import std.path;
import std.random;
import std.range;
import std.regex;
import std.stdio;
import std.string;

alias std.string.indexOf indexOf;

import ae.net.asockets;
import ae.net.http.caching;
import ae.net.http.responseex;
import ae.net.http.server;
import ae.net.ietf.headers;
import ae.net.ietf.url;
import ae.net.ietf.wrap;
import ae.sys.log;
import ae.utils.array;
import ae.utils.digest;
import ae.utils.exception;
import ae.utils.feed;
import ae.utils.json;
import ae.utils.meta;
import ae.utils.regex;
import ae.utils.sini : loadIni;
import ae.utils.text;
import ae.utils.text.html;
import ae.utils.textout;
import ae.utils.time.format;
import ae.utils.time.parse;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.bayes;
import dfeed.common;
import dfeed.database;
import dfeed.groups;
import dfeed.mail;
import dfeed.message;
import dfeed.sinks.cache;
import dfeed.sinks.messagedb : searchTerm, threadID;
import dfeed.sinks.subscriptions;
import dfeed.site;
import dfeed.sources.github;
import dfeed.web.captcha;
import dfeed.web.lint;
import dfeed.web.list;
//import dfeed.web.mailhide;
import dfeed.web.posting;
import dfeed.web.user : User, getUser, SettingType;
import dfeed.web.spam : bayes, getSpamicity;
import dfeed.web.web.cache;
import dfeed.web.web.config;
import dfeed.web.web.draft : getDraft, saveDraft, draftToPost;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.pager;
import dfeed.web.web.part.post : postLink, miniPostInfo;
import dfeed.web.web.part.thread : formatThreadedPosts;
import dfeed.web.web.perf;
import dfeed.web.web.request : onRequest, currentRequest, ip, user;
import dfeed.web.web.statics;
import dfeed.web.web.view.post : formatPost, formatSplitPost;
import dfeed.web.web.view.thread : getPostThreadIndex, getPostAtThreadIndex;

StringBuffer html;

alias config = dfeed.web.web.config.config;

// ***********************************************************************

void draftNotices(string except = null)
{
	foreach (string id, long time; query!"SELECT [ID], [Time] FROM [Drafts] WHERE [UserID]==? AND [Status]==?".iterate(userSettings.id, PostDraft.Status.edited))
	{
		if (id == except)
			continue;
		auto t = SysTime(time, UTC());
		html.put(`<div class="forum-notice">You have an <a href="/posting/`, id, `">unsent draft message from `, formatShortTime(t, false), `</a>.</div>`);
	}
}

bool discussionPostForm(PostDraft draft, bool showCaptcha=false, PostError error=PostError.init)
{
	auto draftID = draft.clientVars.get("did", null);
	draftNotices(draftID);

	if (draft.status == PostDraft.Status.moderation)
		throw new Exception("This message is awaiting moderation.");

	// Immediately resurrect discarded posts when user clicks "Undo" or "Back"
	if (draft.status == PostDraft.Status.discarded)
		query!"UPDATE [Drafts] SET [Status]=? WHERE [ID]=?".exec(PostDraft.Status.edited, draftID);

	auto where = draft.serverVars.get("where", null);
	auto info = getGroupInfo(where);
	if (!info)
		throw new Exception("Unknown group " ~ where);
	if (info.postMessage)
	{
		html.put(
			`<table class="forum-table forum-error">` ~
				`<tr><th>Can't post to archive</th></tr>` ~
				`<tr><td class="forum-table-message">`
					, info.postMessage,
				`</td></tr>` ~
			`</table>`);
		return false;
	}
	if (info.sinkType == "smtp" && info.subscriptionRequired)
	{
		auto config = loadIni!SmtpConfig("config/sources/smtp/" ~ info.sinkName ~ ".ini");
		html.put(`<div class="forum-notice">Note: you are posting to a mailing list.<br>` ~
			`Your message will not go through unless you ` ~
			`<a href="`), html.putEncodedEntities(config.listInfo), html.putEncodedEntities(info.internalName), html.put(`">subscribe to the mailing list</a> first.<br>` ~
			`You must then use the same email address when posting here as the one you used to subscribe to the list.<br>` ~
			`If you do not want to receive mailing list mail, you can disable mail delivery at the above link.</div>`);
	}

	auto parent = draft.serverVars.get("parent", null);
	auto parentInfo	= parent ? getPostInfo(parent) : null;
	if (parentInfo && Clock.currTime - parentInfo.time > 2.weeks)
		html.put(`<div class="forum-notice">Warning: the post you are replying to is from `,
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
		`<div id="postform-info">` ~
			`Posting to <b>`), html.putEncodedEntities(info.publicName), html.put(`</b>`,
			(parent
				? parentInfo
					? ` in reply to ` ~ postLink(parentInfo)
					: ` in reply to (unknown post)`
				: info
					? `:<br>(<b>` ~ encodeHtmlEntities(info.description) ~ `</b>)`
					: ``),
		`</div>` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`<input type="hidden" name="did" value="`), html.putEncodedEntities(draftID), html.put(`">` ~
		`<label for="postform-name">Your name:</label>` ~
		`<input id="postform-name" name="name" size="40" value="`), html.putEncodedEntities(draft.clientVars.get("name", null)), html.put(`">` ~
		`<label for="postform-email">Your email address (<a href="/help#email">?</a>):</label>` ~
		`<input id="postform-email" type="email" name="email" size="40" value="`), html.putEncodedEntities(draft.clientVars.get("email", null)), html.put(`">` ~
		`<label for="postform-subject">Subject:</label>` ~
		`<input id="postform-subject" name="subject" size="80"`, subject.length ? `` : ` autofocus`, ` value="`), html.putEncodedEntities(subject), html.put(`">` ~
		`<label for="postform-text">Message:</label>` ~
		`<textarea id="postform-text" name="text" rows="25" cols="80"`, subject.length ? ` autofocus` : ``, `>`), html.putEncodedEntities(draft.clientVars.get("text", null)), html.put(`</textarea>`);

	if (showCaptcha)
		html.put(`<div id="postform-captcha">`, theCaptcha.getChallengeHtml(error.captchaError), `</div>`);

	html.put(
		`<div>` ~
			`<div class="postform-action-left">` ~
				`<input name="action-save" type="submit" value="Save and preview">` ~
				`<input name="action-send" type="submit" value="Send">` ~
			`</div>` ~
			`<div class="postform-action-right">` ~
				`<input name="action-discard" type="submit" value="Discard draft">` ~
			`</div>` ~
			`<div style="clear:right"></div>` ~
		`</div>` ~
	`</form>`);
	return true;
}

/// Bayes model trained to detect recently moderated messages. RAM only.
/// The model is based off the spam model, but we throw away all spam data at first.
BayesModel* getModerationModel()
{
	static BayesModel* model;
	if (!model)
	{
		model = new BayesModel;
		*model = bayes.model;
		model.words = model.words.dup;
		foreach (word, ref counts; model.words)
			counts.spamCount = 0;
		model.spamPosts =  0;
	}
	return model;
}

void learnModeratedMessage(in ref PostDraft draft, bool isBad, int weight)
{
	auto message = bayes.messageFromDraft(draft);
	auto model = getModerationModel();
	auto words = message.splitWords.array;
	train(*model, words, isBad, weight);
}

double checkModeratedMessage(in ref PostDraft draft)
{
	auto message = bayes.messageFromDraft(draft);
	auto model = getModerationModel();
	return checkMessage(*model, message);
}

/// Should this post be queued for moderation instead of being posted immediately?
/// If yes, return a reason; if no, return null.
string shouldModerate(in ref PostDraft draft)
{
	auto spamicity = getSpamicity(draft);
	if (spamicity >= 0.98)
		return "Very high Bayes spamicity (%s%%)".format(spamicity * 100);

	if (auto reason = banCheck(ip, currentRequest))
		return "Post from banned user (ban reason: " ~ reason ~ ")";

	auto modScore = checkModeratedMessage(draft);
	if (modScore >= 0.95)
		return "Very similar to recently moderated messages (%s%%)".format(modScore * 100);

	return null;
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
				throw new Exception("This message has already been sent.");
		}

		if (clientVars.get("secret", "") != userSettings.secret)
			throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

		if (draft.status == PostDraft.Status.moderation)
			throw new Exception("This message is awaiting moderation.");
		
		draft.clientVars = clientVars;
		draft.status = PostDraft.Status.edited;
		scope(exit) saveDraft(draft);

		auto action = clientVars.byKey.filter!(key => key.startsWith("action-")).chain("action-none".only).front[7..$];

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
				draft.serverVars["lint-undo"] = draft.clientVars.get("text", null);
				getLintRule(ruleID).fix(draft);
				draft.clientVars["html-top"] = `<div class="forum-notice">Automatic fix applied. ` ~
					`<input name="action-lint-undo" type="submit" value="Undo"></div>`;
			}
			catch (Exception e)
			{
				draft.serverVars["lint-ignore-" ~ ruleID] = null;
				html.put(`<div class="forum-notice">Sorry, a problem occurred while attempting to fix your post ` ~
					`(`), html.putEncodedEntities(e.msg), html.put(`).</div>`);
			}
			discussionPostForm(draft);
			return null;
		}
		else
		if (action == "lint-undo")
		{
			enforce("lint-undo" in draft.serverVars, "No undo information..?");
			draft.clientVars["text"] = draft.serverVars["lint-undo"];
			draft.serverVars.remove("lint-undo");
			html.put(`<div class="forum-notice">Automatic fix undone.</div>`);
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
						error.message = "Warning: " ~ rule.shortDescription();
						error.extraHTML ~= ` <input name="action-lint-ignore-` ~ rule.id ~ `" type="submit" value="Ignore">`;
						if (!lintDetails)
							error.extraHTML ~= ` <input name="action-lint-explain" type="submit" value="Explain">`;
						if (rule.canFix(draft))
							error.extraHTML ~= ` <input name="action-lint-fix-` ~ rule.id ~ `" type="submit" value="Fix it for me">`;
						if (lintDetails)
							error.extraHTML ~= `<div class="lint-description">` ~ rule.longDescription() ~ `</div>`;
						discussionPostForm(draft, false, error);
						return null;
					}

				auto now = Clock.currTime();

				auto ipPostAttempts = lastPostAttempts.get(ip, null);
				if (ipPostAttempts.length >= postThrottleRejectCount && now - ipPostAttempts[$-postThrottleRejectCount+1] < postThrottleRejectTime)
				{
					discussionPostForm(draft, false,
						PostError("You've attempted to post %d times in the past %s. Please wait a little bit before trying again."
							.format(postThrottleRejectCount, postThrottleRejectTime)));
					return null;
				}

				bool captchaPresent = theCaptcha.isPresent(clientVars);
				if (!captchaPresent)
				{
					if (ipPostAttempts.length >= postThrottleCaptchaCount && now - ipPostAttempts[$-postThrottleCaptchaCount+1] < postThrottleCaptchaTime)
					{
						discussionPostForm(draft, true,
							PostError("You've attempted to post %d times in the past %s. Please solve a CAPTCHA to continue."
								.format(postThrottleCaptchaCount, postThrottleCaptchaTime)));
						return null;
					}
				}

				if (auto reason = shouldModerate(draft))
				{
					learnModeratedMessage(draft, true, 1);

					draft.status = PostDraft.Status.moderation;
					draft.serverVars["headers"] = headers.to!(string[][string]).toJson;
					// draft will be saved by scope(exit) above

					string sanitize(string s) { return "%(%s%)".format(s.only)[1..$-1]; }

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
							/* 5*/ clientVars.get("name", "").I!sanitize,
							/* 6*/ clientVars.get("email", "").I!sanitize,
							/* 7*/ clientVars.get("subject", "").I!sanitize,
							/* 8*/ reason,
							/* 9*/ draft.clientVars.get("text", "").strip.splitAsciiLines.map!(line => line.length ? "> " ~ line : ">"),
							/*10*/ site.proto,
							/*11*/ draftID,
							/*12*/ ip,
							/*13*/ context,
						));

					html.put(`<p>Your message has been saved, and will be posted after being approved by a moderator.</p>`);
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
				throw new Exception("Unknown action");
		}
	}
	catch (Exception e)
	{
		auto error = isDebug ? e.toString() : e.msg;
		discussionPostForm(draft, false, PostError(error));
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

void discussionPostStatusMessage(string messageHtml)
{
	html.put(
		`<table class="forum-table">` ~
			`<tr><th>Posting status</th></tr>` ~
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
			//discussionPostStatusMessage("Checking for spam...");
			discussionPostStatusMessage("Validating...");
			refresh = true;
			return;
		case PostingStatus.captcha:
			discussionPostStatusMessage("Verifying reCAPTCHA...");
			refresh = true;
			return;
		case PostingStatus.connecting:
			discussionPostStatusMessage("Connecting to server...");
			refresh = true;
			return;
		case PostingStatus.posting:
			discussionPostStatusMessage("Sending message to server...");
			refresh = true;
			return;
		case PostingStatus.waiting:
			discussionPostStatusMessage("Message sent.<br>Waiting for message announcement...");
			refresh = true;
			return;

		case PostingStatus.posted:
			redirectTo = idToUrl(process.post.id);
			discussionPostStatusMessage(`Message posted! Redirecting...`);
			refresh = true;
			return;

		case PostingStatus.captchaFailed:
			discussionPostForm(process.draft, true, error);
			form = true;
			return;
		case PostingStatus.spamCheckFailed:
			error.message = format("%s. Please solve a CAPTCHA to continue.", error.message);
			discussionPostForm(process.draft, true, error);
			form = true;
			return;
		case PostingStatus.serverError:
			discussionPostForm(process.draft, false, error);
			form = true;
			return;

		default:
			discussionPostStatusMessage("???");
			refresh = true;
			return;
	}
}

// ***********************************************************************

string findPostingLog(string id)
{
	if (id.match(`^<[a-z]{20}@` ~ site.host.escapeRE() ~ `>`))
	{
		auto post = id[1..21];
		version (Windows)
			auto logs = dirEntries("logs", "*PostProcess-" ~ post ~ ".log", SpanMode.depth).array;
		else
		{
			import std.process;
			auto result = execute(["find", "logs/", "-name", "*PostProcess-" ~ post ~ ".log"]); // This is MUCH faster than dirEntries.
			enforce(result.status == 0, "find error");
			auto logs = splitLines(result.output);
		}
		if (logs.length == 1)
			return logs[0];
	}
	return null;
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

void deletePostImpl(string messageID, string reason, string userName, bool ban, void delegate(string) feedback)
{
	auto post = getPost(messageID);
	enforce(post, "Post not found");

	auto deletionLog = fileLogger("Deleted");
	scope(exit) deletionLog.close();
	scope(failure) deletionLog("An error occurred");
	deletionLog("User %s is deleting post %s (%s)".format(userName, post.id, reason));
	foreach (line; post.message.splitAsciiLines())
		deletionLog("> " ~ line);

	foreach (string[string] values; query!"SELECT * FROM `Posts` WHERE `ID` = ?".iterate(post.id))
		deletionLog("[Posts] row: " ~ values.toJson());
	foreach (string[string] values; query!"SELECT * FROM `Threads` WHERE `ID` = ?".iterate(post.id))
		deletionLog("[Threads] row: " ~ values.toJson());

	if (ban)
	{
		banPoster(userName, post.id, reason);
		deletionLog("User was banned for this post.");
		feedback("User banned.<br>");
	}

	query!"DELETE FROM `Posts` WHERE `ID` = ?".exec(post.id);
	query!"DELETE FROM `Threads` WHERE `ID` = ?".exec(post.id);

	dbVersion++;
	feedback("Post deleted.");
}

// Create logger on demand, to avoid creating empty log files
Logger banLog;
void needBanLog() { if (!banLog) banLog = fileLogger("Banned"); }

void banPoster(string who, string id, string reason)
{
	needBanLog();
	banLog("User %s is banning poster of post %s (%s)".format(who, id, reason));
	auto fn = findPostingLog(id);
	enforce(fn && fn.exists, "Can't find posting log");

	auto pp = new PostProcess(fn);
	string[] keys;
	keys ~= pp.ip;
	keys ~= pp.draft.clientVars.get("secret", null);
	foreach (cookie; pp.headers.get("Cookie", null).split("; "))
	{
		auto p = cookie.indexOf("=");
		if (p<0) continue;
		auto name = cookie[0..p];
		auto value = cookie[p+1..$];
		if (name == "dfeed_secret" || name == "dfeed_session")
			keys ~= value;
	}

	foreach (key; keys)
		if (key.length)
		{
			if (key in banned)
				banLog("Key already known: " ~ key);
			else
			{
				banned[key] = reason;
				banLog("Adding key: " ~ key);
			}
		}

	saveBanList();
	banLog("Done.");
}

enum banListFileName = "data/banned.txt";

string[string] banned;

void loadBanList()
{
	if (banListFileName.exists())
		foreach (string line; splitAsciiLines(cast(string)read(banListFileName)))
		{
			auto parts = line.split("\t");
			if (parts.length >= 2)
				banned[parts[0]] = parts[1..$].join("\t");
		}
}

void saveBanList()
{
	const inProgressFileName = banListFileName ~ ".inprogress";
	auto f = File(inProgressFileName, "wb");
	foreach (key, reason; banned)
		f.writefln("%s\t%s", key, reason);
	f.close();
	rename(inProgressFileName, banListFileName);
}

/// If the user is banned, returns the ban reason.
/// Otherwise, returns null.
string banCheck(string ip, HttpRequest request)
{
	string[] keys = [ip];
	foreach (cookie; request.headers.get("Cookie", null).split("; "))
	{
		auto p = cookie.indexOf("=");
		if (p<0) continue;
		auto name = cookie[0..p];
		auto value = cookie[p+1..$];
		if (name == "dfeed_secret" || name == "dfeed_session")
			if (value.length)
				keys ~= value;
	}
	string secret = userSettings.secret;
	if (secret.length)
		keys ~= secret;

	string bannedKey = null, reason = null;
	foreach (key; keys)
		if (key in banned)
		{
			bannedKey = key;
			reason = banned[key];
			break;
		}

	if (!bannedKey)
		return null;

	needBanLog();
	banLog("Request from banned user: " ~ request.resource);
	foreach (name, value; request.headers)
		banLog("* %s: %s".format(name, value));

	banLog("Matched on: %s (%s)".format(bannedKey, reason));
	bool propagated;
	foreach (key; keys)
		if (key !in banned)
		{
			banLog("Propagating: %s -> %s".format(bannedKey, key));
			banned[key] = "%s (propagated from %s)".format(reason, bannedKey);
			propagated = true;
		}

	if (propagated)
		saveBanList();

	return reason;
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

// ***********************************************************************

void discussionLoginForm(UrlParameters parameters, string errorMessage = null)
{

	html.put(`<form action="/login" method="post" id="loginform" class="forum-form loginform">` ~
		`<table class="forum-table">` ~
			`<tr><th>Log in</th></tr>` ~
			`<tr><td class="loginform-cell">`);

	if ("url" in parameters)
		html.put(`<input type="hidden" name="url" value="`), html.putEncodedEntities(parameters["url"]), html.put(`">`);

	html.put(
			`<label for="loginform-username">Username:</label>` ~
			`<input id="loginform-username" name="username" value="`), html.putEncodedEntities(parameters.get("username", "")), html.put(`" autofocus>` ~
			`<label for="loginform-password">Password:</label>` ~
			`<input id="loginform-password" type="password" name="password" value="`), html.putEncodedEntities(parameters.get("password", "")), html.put(`">` ~
			`<input id="loginform-remember" type="checkbox" name="remember" `, "username" !in  parameters || "remember" in parameters ? ` checked` : ``, `>` ~
			`<label for="loginform-remember"> Remember me</label>` ~
			`<input type="submit" value="Log in">` ~
		`</td></tr>`);
	if (errorMessage)
		html.put(`<tr><td class="loginform-info"><div class="form-error loginform-error">`), html.putEncodedEntities(errorMessage), html.put(`</div></td></tr>`);
	else
		html.put(
			`<tr><td class="loginform-info">` ~
				`<a href="/registerform`,
					("url" in parameters ? `?url=` ~ encodeUrlParameter(parameters["url"]) : ``),
					`">Register</a> to keep your preferences<br>and read post history on the server.` ~
			`</td></tr>`);
	html.put(`</table></form>`);
}

void discussionLogin(UrlParameters parameters)
{
	user.logIn(aaGet(parameters, "username"), aaGet(parameters, "password"), !!("remember" in parameters));
}

void discussionRegisterForm(UrlParameters parameters, string errorMessage = null)
{
	html.put(`<form action="/register" method="post" id="registerform" class="forum-form loginform">` ~
		`<table class="forum-table">` ~
			`<tr><th>Register</th></tr>` ~
			`<tr><td class="loginform-cell">`);

	if ("url" in parameters)
		html.put(`<input type="hidden" name="url" value="`), html.putEncodedEntities(parameters["url"]), html.put(`">`);

	html.put(
		`<label for="loginform-username">Username:</label>` ~
		`<input id="loginform-username" name="username" value="`), html.putEncodedEntities(parameters.get("username", "")), html.put(`" autofocus>` ~
		`<label for="loginform-password">Password:</label>` ~
		`<input id="loginform-password" type="password" name="password" value="`), html.putEncodedEntities(parameters.get("password", "")), html.put(`">` ~
		`<label for="loginform-password2">Confirm:</label>` ~
		`<input id="loginform-password2" type="password" name="password2" value="`), html.putEncodedEntities(parameters.get("password2", "")), html.put(`">` ~
		`<input id="loginform-remember" type="checkbox" name="remember" `, "username" !in  parameters || "remember" in parameters ? ` checked` : ``, `>` ~
		`<label for="loginform-remember"> Remember me</label>` ~
		`<input type="submit" value="Register">` ~
		`</td></tr>`);
	if (errorMessage)
		html.put(`<tr><td class="loginform-info"><div class="form-error loginform-error">`), html.putEncodedEntities(errorMessage), html.put(`</div></td></tr>`);
	else
		html.put(
			`<tr><td class="loginform-info">` ~
				`Please pick your password carefully.<br>There are no password recovery options.` ~
			`</td></tr>`);
	html.put(`</table></form>`);
}

void discussionRegister(UrlParameters parameters)
{
	enforce(aaGet(parameters, "password") == aaGet(parameters, "password2"), "Passwords do not match");
	user.register(aaGet(parameters, "username"), aaGet(parameters, "password"), !!("remember" in parameters));
}

// ***********************************************************************

struct UserSettings
{
	static SettingType[string] settingTypes;

	template userSetting(string name, string defaultValue, SettingType settingType)
	{
		@property string userSetting() { return user.get(name, defaultValue, settingType); }
		@property string userSetting(string newValue) { user.set(name, newValue, settingType); return newValue; }
		static this() { settingTypes[name] = settingType; }
	}

	template randomUserString(string name, SettingType settingType)
	{
		@property string randomUserString()
		{
			auto value = user.get(name, null, settingType);
			if (value is null)
			{
				value = randomString();
				user.set(name, value, settingType);
			}
			return value;
		}
	}

	/// Posting details. Remembered when posting messages.
	alias name = userSetting!("name", null, SettingType.server);
	alias email = userSetting!("email", null, SettingType.server); /// ditto

	/// View mode. Can be changed in the settings.
	alias groupViewMode = userSetting!("groupviewmode", "basic", SettingType.client);

	/// Enable or disable keyboard hotkeys. Can be changed in the settings.
	alias enableKeyNav = userSetting!("enable-keynav", "true", SettingType.client);

	/// Whether messages are opened automatically after being focused
	/// (message follows focus). Can be changed in the settings.
	alias autoOpen = userSetting!("auto-open", "false", SettingType.client);

	/// Any pending notices that should be shown on the next page shown.
	alias pendingNotice = userSetting!("pending-notice", null, SettingType.session);

	/// Session management
	alias previousSession = userSetting!("previous-session", "0", SettingType.server);
	alias currentSession  = userSetting!("current-session" , "0", SettingType.server);  /// ditto
	alias sessionCanary   = userSetting!("session-canary"  , "0", SettingType.session); /// ditto

	/// A unique ID used to recognize both logged-in and anonymous users.
	alias id = randomUserString!("id", SettingType.server);

	/// Secret token used for CSRF protection.
	/// Visible in URLs.
	alias secret = randomUserString!("secret", SettingType.server);

	void set(string name, string value)
	{
		user.set(name, value, settingTypes.aaGet(name));
	}
}
UserSettings userSettings;

// ***********************************************************************

string settingsReferrer;

void discussionSettings(UrlParameters getVars, UrlParameters postVars)
{
	settingsReferrer = postVars.get("referrer", currentRequest.headers.get("Referer", null));

	if (postVars)
	{
		if (postVars.get("secret", "") != userSettings.secret)
			throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

		auto actions = postVars.keys.filter!(name => name.startsWith("action-"));
		enforce(!actions.empty, "No action specified");
		auto action = actions.front[7..$];

		if (action == "cancel")
			throw new Redirect(settingsReferrer ? settingsReferrer : "/");
		else
		if (action == "save")
		{
			// Inputs
			foreach (setting; ["groupviewmode"])
				if (setting in postVars)
					userSettings.set(setting, postVars[setting]);
			// Checkboxes
			foreach (setting; ["enable-keynav", "auto-open"])
				userSettings.set(setting, setting in postVars ? "true" : "false");

			userSettings.pendingNotice = "settings-saved";
			throw new Redirect(settingsReferrer ? settingsReferrer : "/settings");
		}
		else
		if (action == "subscription-cancel")
			{}
		else
		if (action.skipOver("subscription-edit-"))
		{
			auto subscriptionID = action;
			return discussionSubscriptionEdit(getUserSubscription(user.getName(), subscriptionID));
		}
		else
		if (action.skipOver("subscription-view-"))
			throw new Redirect("/subscription-posts/" ~ action);
		else
		if (action.skipOver("subscription-feed-"))
			throw new Redirect("/subscription-feed/" ~ action);
		else
		if (action == "subscription-save" || action == "subscription-undelete")
		{
			string message;
			if (action == "subscription-undelete")
				message = "Subscription undeleted.";
			else
			if (subscriptionExists(postVars.get("id", null)))
				message = "Subscription saved.";
			else
				message = "Subscription created.";

			auto subscription = Subscription(user.getName(), postVars);
			try
			{
				subscription.save();
				html.put(`<div class="forum-notice">`, message, `</div>`);
			}
			catch (Exception e)
			{
				html.put(`<div class="form-error">`), html.putEncodedEntities(e.msg), html.put(`</div>`);
				return discussionSubscriptionEdit(subscription);
			}
		}
		else
		if (action.skipOver("subscription-delete-"))
		{
			auto subscriptionID = action;
			enforce(subscriptionExists(subscriptionID), "This subscription doesn't exist.");

			html.put(
				`<div class="forum-notice">Subscription deleted. ` ~
				`<input type="submit" name="action-subscription-undelete" value="Undo" form="subscription-form">` ~
				`</div>` ~
				`<div style="display:none">`
			);
			// Replicate the entire edit form here (but make it invisible),
			// so that saving the subscription recreates it on the server.
			discussionSubscriptionEdit(getUserSubscription(user.getName(), subscriptionID));
			html.put(
				`</div>`
			);

			getUserSubscription(user.getName(), subscriptionID).remove();
		}
		else
		if (action == "subscription-create-content")
			return discussionSubscriptionEdit(createSubscription(user.getName(), "content"));
		else
			throw new Exception("Unknown action: " ~ action);
	}

	html.put(
		`<form method="post" id="settings-form">` ~
		`<h1>Settings</h1>` ~
		`<input type="hidden" name="referrer" value="`), html.putEncodedEntities(settingsReferrer), html.put(`">` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~

		`<h2>User Interface</h2>` ~

		`View mode: <select name="groupviewmode">`
	);
	auto currentMode = userSettings.groupViewMode;
	foreach (mode; ["basic", "threaded", "horizontal-split", "vertical-split"])
		html.put(`<option value="`, mode, `"`, mode == currentMode ? ` selected` : null, `>`, mode, `</option>`);
	html.put(
		`</select><br>` ~

		`<input type="checkbox" name="enable-keynav" id="enable-keynav"`, userSettings.enableKeyNav == "true" ? ` checked` : null, `>` ~
		`<label for="enable-keynav">Enable keyboard shortcuts</label> (<a href="/help#keynav">?</a>)<br>` ~

		`<span title="Automatically open messages after selecting them.&#13;&#10;Applicable to threaded, horizontal-split and vertical-split view modes.">` ~
			`<input type="checkbox" name="auto-open" id="auto-open"`, userSettings.autoOpen == "true" ? ` checked` : null, `>` ~
			`<label for="auto-open">Focus follows message</label>` ~
		`</span><br>` ~

		`<p>` ~
			`<input type="submit" name="action-save" value="Save">` ~
			`<input type="submit" name="action-cancel" value="Cancel">` ~
		`</p>` ~

		`<hr>` ~

		`<h2>Subscriptions</h2>`
	);
	if (user.isLoggedIn())
	{
		auto subscriptions = getUserSubscriptions(user.getName());
		if (subscriptions.length)
		{
			html.put(`<table id="subscriptions">`);
			html.put(`<tr><th>Subscription</th><th colspan="2">Actions</th></tr>`);
			foreach (subscription; subscriptions)
			{
				html.put(
					`<tr>` ~
						`<td>`), subscription.trigger.putDescription(html), html.put(`</td>` ~
						`<td><input type="submit" form="subscriptions-form" name="action-subscription-view-`  , subscription.id, `" value="View posts"></td>` ~
						`<td><input type="submit" form="subscriptions-form" name="action-subscription-feed-`  , subscription.id, `" value="Get ATOM feed"></td>` ~
						`<td><input type="submit" form="subscriptions-form" name="action-subscription-edit-`  , subscription.id, `" value="Edit"></td>` ~
						`<td><input type="submit" form="subscriptions-form" name="action-subscription-delete-`, subscription.id, `" value="Delete"></td>` ~
					`</tr>`
				);
			}
			html.put(
				`</table>`
			);
		}
		else
			html.put(`<p>You have no subscriptions.</p>`);
		html.put(
			`<p><input type="submit" form="subscriptions-form" name="action-subscription-create-content" value="Create new content alert subscription"></p>`
		);
	}
	else
		html.put(`<p>Please <a href="/loginform">log in</a> to manage your subscriptions.</p>`);

	html.put(
		`</form>` ~

		`<form method="post" id="subscriptions-form">` ~
		`<input type="hidden" name="referrer" value="`), html.putEncodedEntities(settingsReferrer), html.put(`">` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`</form>`
	);
}

void discussionSubscriptionEdit(Subscription subscription)
{
	html.put(
		`<form action="/settings" method="post" id="subscription-form">` ~
		`<h1>Edit subscription</h1>` ~
		`<input type="hidden" name="referrer" value="`), html.putEncodedEntities(settingsReferrer), html.put(`">` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`<input type="hidden" name="id" value="`, subscription.id, `">` ~

		`<h2>Condition</h2>` ~
		`<input type="hidden" name="trigger-type" value="`, subscription.trigger.type, `">`
	);
	subscription.trigger.putEditHTML(html);

	html.put(
		`<h2>Actions</h2>`
	);

	foreach (action; subscription.actions)
		action.putEditHTML(html);

	html.put(
		`<p>` ~
			`<input type="submit" name="action-subscription-save" value="Save">` ~
			`<input type="submit" name="action-subscription-cancel" value="Cancel">` ~
		`</p>` ~
		`</form>`
	);
}

void discussionSubscriptionUnsubscribe(string subscriptionID)
{
	auto subscription = getSubscription(subscriptionID);
	subscription.unsubscribe();
	html.put(
		`<h1>Unsubscribe</h1>` ~
		`<p>This subscription has been deactivated.</p>` ~
		`<p>If you did not intend to do this, you can reactivate the subscription's actions on your <a href="/settings">settings page</a>.</p>`
	);
}

void discussionSubscriptionPosts(string subscriptionID, int page, out string title)
{
	auto subscription = getUserSubscription(user.getName(), subscriptionID);
	title = "View subscription: " ~ subscription.trigger.getTextDescription();

	enum postsPerPage = POSTS_PER_PAGE;
	html.put(`<h1>`); html.putEncodedEntities(title);
	if (page != 1)
		html.put(" (page ", text(page), ")");
	html.put("</h1>");

	auto postCount = query!"SELECT COUNT(*) FROM [SubscriptionPosts] WHERE [SubscriptionID] = ?".iterate(subscriptionID).selectValue!int;

	if (postCount == 0)
	{
		html.put(`<p>It looks like there's nothing here! No posts matched this subscription so far.</p>`);
	}

	foreach (string messageID; query!"SELECT [MessageID] FROM [SubscriptionPosts] WHERE [SubscriptionID] = ? ORDER BY [Time] DESC LIMIT ? OFFSET ?"
						.iterate(subscriptionID, postsPerPage, (page-1)*postsPerPage))
	{
		auto post = getPost(messageID);
		if (post)
			formatPost(post, null);
	}

	if (page != 1 || postCount > postsPerPage)
	{
		html.put(`<table class="forum-table post-pager">`);
		pager(null, page, getPageCount(postCount, postsPerPage));
		html.put(`</table>`);
	}

	html.put(
		`<form style="display:block;float:right;margin-top:0.5em" action="/settings" method="post">` ~
			`<input type="hidden" name="secret" value="`), html.putEncodedEntities(userSettings.secret), html.put(`">` ~
			`<input type="submit" name="action-subscription-edit-`), html.putEncodedEntities(subscriptionID), html.put(`" value="Edit subscription">` ~
		`</form>` ~
		`<div style="clear:right"></div>`
	);
}

// ***********************************************************************

/// Delimiters for formatSearchSnippet.
enum searchDelimPrefix     = "\U000FDeed"; // Private Use Area character
enum searchDelimStartMatch = searchDelimPrefix ~ "\x01";
enum searchDelimEndMatch   = searchDelimPrefix ~ "\x02";
enum searchDelimEllipses   = searchDelimPrefix ~ "\x03";
enum searchDelimLength     = searchDelimPrefix.length + 1;

void discussionSearch(UrlParameters parameters)
{
	// HTTP form parameters => search string (visible in form, ?q= parameter) => search query (sent to database)

	string[] terms;
	if (string searchScope = parameters.get("scope", null))
	{
		if (searchScope.startsWith("dlang.org"))
			throw new Redirect("https://www.google.com/search?" ~ encodeUrlParameters(["sitesearch" : searchScope, "q" : parameters.get("q", null)]));
		else
		if (searchScope == "forum")
			{}
		else
		if (searchScope.startsWith("group:") || searchScope.startsWith("threadmd5:"))
			terms ~= searchScope;
	}
	terms ~= parameters.get("q", null);

	if (parameters.get("exact", null).length)
		terms ~= '"' ~ parameters["exact"].replace(`"`, ``) ~ '"';

	if (parameters.get("not", null).length)
		foreach (word; parameters["not"].split)
			terms ~= "-" ~ word.stripLeft('-');

	foreach (param; ["group", "author", "authoremail", "subject", "content", "newthread"])
		if (parameters.get(param, null).length)
			foreach (word; parameters[param].split)
			{
				if (param == "group")
					word = word.getGroupInfoByPublicName.I!(gi => gi ? gi.internalName.searchTerm : word);
				terms ~= param ~ ":" ~ word;
			}

	if (parameters.get("startdate", null).length || parameters.get("enddate", null).length)
		terms ~= "date:" ~ parameters.get("startdate", null) ~ ".." ~ parameters.get("enddate", null);

	auto searchString = terms.map!strip.filter!(not!empty).join(" ");
	bool doSearch = searchString.length > 0;
	string autoFocus = doSearch ? "" : " autofocus";

	if ("advsearch" in parameters)
	{
		html.put(
			`<form method="get" id="advanced-search-form">` ~
			`<h1>Advanced Search</h1>` ~
			`<p>Find posts with...</p>` ~
			`<table>` ~
				`<tr><td>all these words:`     ~ ` </td><td><input size="50" name="q" value="`), html.putEncodedEntities(searchString), html.put(`"`, autoFocus, `></td></tr>` ~
				`<tr><td>this exact phrase:`   ~ ` </td><td><input size="50" name="exact"></td></tr>` ~
				`<tr><td>none of these words:` ~ ` </td><td><input size="50" name="not"></td></tr>` ~
				`<tr><td>posted in the group:` ~ ` </td><td><input size="50" name="group"></td></tr>` ~
				`<tr><td>posted by:`           ~ ` </td><td><input size="50" name="author"></td></tr>` ~
				`<tr><td>posted by (email):`   ~ ` </td><td><input size="50" name="authoremail"></td></tr>` ~
				`<tr><td>in threads titled:`   ~ ` </td><td><input size="50" name="subject"></td></tr>` ~
				`<tr><td>containing:`          ~ ` </td><td><input size="50" name="content"></td></tr>` ~
				`<tr><td>posted between:`      ~ ` </td><td><input type="date" placeholder="yyyy-mm-dd" name="startdate"> and <input type="date" placeholder="yyyy-mm-dd" name="enddate"></td></tr>` ~
				`<tr><td>posted as new thread:`~ ` </td><td><input type="checkbox" name="newthread" value="y"><input size="1" tabindex="-1" style="visibility:hidden"></td></tr>` ~
			`</table>` ~
			`<br>` ~
			`<input name="search" type="submit" value="Advanced search">` ~
			`</table>` ~
			`</form>`
		);
		doSearch = false;
	}
	else
	{
		html.put(
			`<form method="get" id="search-form">` ~
			`<h1>Search</h1>` ~
			`<input name="q" size="50" value="`), html.putEncodedEntities(searchString), html.put(`"`, autoFocus, `>` ~
			`<input name="search" type="submit" value="Search">` ~
			`<input name="advsearch" type="submit" value="Advanced search">` ~
			`</form>`
		);
	}

	if (doSearch)
		try
		{
			long startDate = 0;
			long endDate = long.max;

			terms = searchString.split();
			string[] queryTerms;
			foreach (term; terms)
				if (term.startsWith("date:") && term.canFind(".."))
				{
					long parseDate(string date, Duration offset, long def)
					{
						if (!date.length)
							return def;
						else
							try
								return (date.parseTime!`Y-m-d` + offset).stdTime;
							catch (Exception e)
								throw new Exception("Invalid date: %s (%s)".format(date, e.msg));
					}

					auto dates = term.findSplit(":")[2].findSplit("..");
					startDate = parseDate(dates[0], 0.days, startDate);
					endDate   = parseDate(dates[2], 1.days, endDate);
				}
				else
				if (term.startsWith("time:") && term.canFind(".."))
				{
					long parseTime(string time, long def)
					{
						return time.length ? time.to!long : def;
					}

					auto times = term.findSplit(":")[2].findSplit("..");
					startDate = parseTime(times[0], startDate);
					endDate   = parseTime(times[2], endDate);
				}
				else
					queryTerms ~= term;

			enforce(startDate < endDate, "Start date must be before end date");
			auto queryString = queryTerms.join(' ');

			int page = parameters.get("page", "1").to!int;
			enforce(page >= 1, "Invalid page number");

			enum postsPerPage = 10;

			int n = 0;

			enum queryCommon =
				"SELECT [ROWID], snippet([PostSearch], '" ~ searchDelimStartMatch ~ "', '" ~ searchDelimEndMatch ~ "', '" ~ searchDelimEllipses ~ "', 6) " ~
				"FROM [PostSearch]";
			auto iterator =
				queryTerms.length
				?
					(startDate == 0 && endDate == long.max)
					? query!(queryCommon ~ " WHERE [PostSearch] MATCH ?                            ORDER BY [Time] DESC LIMIT ? OFFSET ?")
						.iterate(queryString,                     postsPerPage + 1, (page-1)*postsPerPage)
					: query!(queryCommon ~ " WHERE [PostSearch] MATCH ? AND [Time] BETWEEN ? AND ? ORDER BY [Time] DESC LIMIT ? OFFSET ?")
						.iterate(queryString, startDate, endDate, postsPerPage + 1, (page-1)*postsPerPage)
				: query!("SELECT [ROWID], '' FROM [Posts] WHERE [Time] BETWEEN ? AND ? ORDER BY [Time] DESC LIMIT ? OFFSET ?")
					.iterate(startDate, endDate, postsPerPage + 1, (page-1)*postsPerPage)
				;

			foreach (int rowid, string snippet; iterator)
			{
				//html.put(`<pre>`, snippet, `</pre>`);
				string messageID;
				foreach (string id; query!"SELECT [ID] FROM [Posts] WHERE [ROWID] = ?".iterate(rowid))
					messageID = id;
				if (!messageID)
					continue; // Can occur with deleted posts

				n++;
				if (n > postsPerPage)
					break;

				auto post = getPost(messageID);
				if (post)
				{
					if (!snippet.length) // No MATCH (date only)
					{
						enum maxWords = 20;
						auto segments = post.newContent.segmentByWhitespace;
						if (segments.length < maxWords*2)
							snippet = segments.join();
						else
							snippet = segments[0..maxWords*2-1].join() ~ searchDelimEllipses;
					}
					formatSearchResult(post, snippet);
				}
			}

			if (n == 0)
				html.put(`<p>Your search - <b>`), html.putEncodedEntities(searchString), html.put(`</b> - did not match any forum posts.</p>`);

			if (page != 1 || n > postsPerPage)
			{
				html.put(`<table class="forum-table post-pager">`);
				pager("?" ~ encodeUrlParameters(["q" : searchString]), page, n > postsPerPage ? int.max : page);
				html.put(`</table>`);
			}
		}
		catch (CaughtException e)
			html.put(`<div class="form-error">Error: `), html.putEncodedEntities(e.msg), html.put(`</div>`);
}

void formatSearchSnippet(string s)
{
	while (true)
	{
		auto i = s.indexOf(searchDelimPrefix);
		if (i < 0)
			break;
		html.putEncodedEntities(s[0..i]);
		string delim = s[i..i+searchDelimLength];
		s = s[i+searchDelimLength..$];
		switch (delim)
		{
			case searchDelimStartMatch: html.put(`<b>`       ); break;
			case searchDelimEndMatch  : html.put(`</b>`      ); break;
			case searchDelimEllipses  : html.put(`<b>...</b>`); break;
			default: break;
		}
	}
	html.putEncodedEntities(s);
}

void formatSearchResult(Rfc850Post post, string snippet)
{
	string gravatarHash = getGravatarHash(post.authorEmail);

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="post forum-table`, (post.children ? ` with-children` : ``), `" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(2), `</tr>` ~ // Fixed layout dummies
			`<tr class="post-header"><th colspan="2">` ~
				`<div class="post-time">`, summarizeTime(time), `</div>`,
				encodeHtmlEntities(post.publicGroupNames().join(", ")), ` &raquo; ` ~
				`<a title="View this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="permalink `, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr class="mini-post-info-cell">` ~
				`<td colspan="2">`
		); miniPostInfo(post, null, false); html.put(
				`</td>` ~
			`</tr>` ~
			`<tr>` ~
				`<td class="post-info">` ~
					`<div class="post-author">`), html.putEncodedEntities(author), html.put(`</div>`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 80);

		html.put(
				`</td>` ~
				`<td class="post-body">` ~
					`<pre class="post-text">`), formatSearchSnippet(snippet), html.put(`</pre>`,
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td>` ~
			`</tr>` ~
			`</table>` ~
			`</div>`
		);
	}
}

// ***********************************************************************

string resolvePostUrl(string id)
{
	foreach (string threadID; query!"SELECT `ThreadID` FROM `Posts` WHERE `ID` = ?".iterate(id))
		return idToThreadUrl(id, threadID);

	throw new NotFoundException("Post not found");
}

string idToThreadUrl(string id, string threadID)
{
	return idToUrl(threadID, "thread", indexToPage(getPostThreadIndex(id), POSTS_PER_PAGE)) ~ "#" ~ idToFragment(id);
}

static Rfc850Post getPost(string id, uint[] partPath = null)
{
	foreach (int rowid, string message, string threadID; query!"SELECT `ROWID`, `Message`, `ThreadID` FROM `Posts` WHERE `ID` = ?".iterate(id))
	{
		auto post = new Rfc850Post(message, id, rowid, threadID);
		while (partPath.length)
		{
			enforce(partPath[0] < post.parts.length, "Invalid attachment");
			post = post.parts[partPath[0]];
			partPath = partPath[1..$];
		}
		return post;
	}
	return null;
}

static string getPostSource(string id)
{
	foreach (string message; query!"SELECT `Message` FROM `Posts` WHERE `ID` = ?".iterate(id))
		return message;
	return null;
}

struct PostInfo { int rowid; string id, threadID, parentID, author, authorEmail, subject; SysTime time; }
CachedSet!(string, PostInfo*) postInfoCache;

PostInfo* getPostInfo(string id)
{
	return postInfoCache(id, retrievePostInfo(id));
}

PostInfo* retrievePostInfo(string id)
{
	if (id.startsWith('<') && id.endsWith('>'))
		foreach (int rowid, string threadID, string parentID, string author, string authorEmail, string subject, long stdTime; query!"SELECT `ROWID`, `ThreadID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ID` = ?".iterate(id))
		{
			if (authorEmail is null)
			{
				authorEmail = new Rfc850Message(query!"SELECT [Message] FROM [Posts] WHERE [ROWID]=?".iterate(rowid).selectValue!string).authorEmail;
				if (authorEmail is null)
					authorEmail = "";
				assert(authorEmail !is null);
				query!"UPDATE [Posts] SET [AuthorEmail]=? WHERE [ROWID]=?".exec(authorEmail, rowid);
			}
			return [PostInfo(rowid, id, threadID, parentID, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr;
		}
	return null;
}

// ***********************************************************************

static Regex!char reUrl;
static this() { reUrl = regex(`\w+://[^<>\s]+[\w/\-=]`); }

void formatBody(Rfc850Message post)
{
	auto paragraphs = unwrapText(post.content, post.wrapFormat);
	bool inSignature = false;
	int quoteLevel = 0;
	foreach (paragraph; paragraphs)
	{
		int paragraphQuoteLevel;
		foreach (c; paragraph.quotePrefix)
			if (c == '>')
				paragraphQuoteLevel++;

		for (; quoteLevel > paragraphQuoteLevel; quoteLevel--)
			html ~= `</span>`;
		for (; quoteLevel < paragraphQuoteLevel; quoteLevel++)
			html ~= `<span class="forum-quote">`;

		if (!quoteLevel && (paragraph.text == "-- " || paragraph.text == "_______________________________________________"))
		{
			html ~= `<span class="forum-signature">`;
			inSignature = true;
		}

		enum forceWrapThreshold = 30;
		enum forceWrapMinChunkSize =  5;
		enum forceWrapMaxChunkSize = 15;
		static assert(forceWrapMaxChunkSize > forceWrapMinChunkSize * 2);

		import std.utf;
		bool needsWrap = paragraph.text.byChar.splitter(' ').map!(s => s.length).I!(r => reduce!max(size_t.init, r)) > forceWrapThreshold;

		auto hasURL = paragraph.text.contains("://");

		void processText(string s)
		{
			html.put(encodeHtmlEntities(s));
		}

		void processWrap(string s)
		{
			alias processText next;

			if (!needsWrap)
				return next(s);

			auto segments = s.segmentByWhitespace();
			foreach (ref segment; segments)
			{
				if (segment.length > forceWrapThreshold)
				{
					void chunkify(string s, string delimiters)
					{
						if (s.length < forceWrapMaxChunkSize)
						{
							html.put(`<span class="forcewrap">`);
							next(s);
							html.put(`</span>`);
						}
						else
						if (!delimiters.length)
						{
							// Don't cut UTF-8 sequences in half
							static bool canCutAt(char c) { return (c & 0x80) == 0 || (c & 0x40) != 0; }
							foreach (i; s.length.iota.radial)
								if (canCutAt(s[i]))
								{
									chunkify(s[0..i], null);
									chunkify(s[i..$], null);
									return;
								}
							chunkify(s[0..$/2], null);
							chunkify(s[$/2..$], null);
						}
						else
						{
							foreach (i; iota(forceWrapMinChunkSize, s.length-forceWrapMinChunkSize).radial)
								if (s[i] == delimiters[0])
								{
									chunkify(s[0..i+1], delimiters);
									chunkify(s[i+1..$], delimiters);
									return;
								}
							chunkify(s, delimiters[1..$]);
						}
					}

					chunkify(segment, "/&=.-+,;:_\\|`'\"~!@#$%^*()[]{}");
				}
				else
					next(segment);
			}
		}

		void processURLs(string s)
		{
			alias processWrap next;

			if (!hasURL)
				return next(s);

			size_t pos = 0;
			foreach (m; matchAll(s, reUrl))
			{
				next(s[pos..m.pre().length]);
				html.put(`<a rel="nofollow" href="`, m.hit(), `">`);
				next(m.hit());
				html.put(`</a>`);
				pos = m.pre().length + m.hit().length;
			}
			next(s[pos..$]);
		}

		if (paragraph.quotePrefix.length)
			html.put(`<span class="forum-quote-prefix">`), html.putEncodedEntities(paragraph.quotePrefix), html.put(`</span>`);
		processURLs(paragraph.text);
		html.put('\n');
	}
	for (; quoteLevel; quoteLevel--)
		html ~= `</span>`;
	if (inSignature)
		html ~= `</span>`;
}

string summarizeTime(SysTime time, bool colorize = false)
{
	if (!time.stdTime)
		return "-";

	string style;
	if (colorize)
	{
		import std.math;
		auto diff = Clock.currTime() - time;
		auto diffLog = log2(diff.total!"seconds");
		enum LOG_MIN = 10; // 1 hour-ish
		enum LOG_MAX = 18; // 3 days-ish
		enum COLOR_MAX = 0xA0;
		auto f = (diffLog - LOG_MIN) / (LOG_MAX - LOG_MIN);
		f = min(1, max(0, f));
		auto c = cast(int)(f * COLOR_MAX);

		style ~= format("color: #%02X%02X%02X;", c, c, c);
	}

	bool shorter = colorize; // hack
	return `<span style="` ~ style ~ `" title="` ~ encodeHtmlEntities(formatLongTime(time)) ~ `">` ~ encodeHtmlEntities(formatShortTime(time, shorter)) ~ `</span>`;
}

string formatShortTime(SysTime time, bool shorter)
{
	if (!time.stdTime)
		return "-";

	auto now = Clock.currTime(UTC());
	auto duration = now - time;

	if (duration < dur!"days"(7))
		return formatDuration(duration);
	else
	if (duration < dur!"days"(300))
		if (shorter)
			return time.formatTime!"M d"();
		else
			return time.formatTime!"F d"();
	else
		if (shorter)
			return time.formatTime!"M d, Y"();
		else
			return time.formatTime!"F d, Y"();
}

string formatDuration(Duration duration)
{
	string ago(long amount, string units)
	{
		assert(amount > 0);
		return format("%s %s%s ago", amount, units, amount==1 ? "" : "s");
	}

	if (duration < 0.seconds)
		return "from the future";
	else
	if (duration < 1.seconds)
		return "just now";
	else
	if (duration < 1.minutes)
		return ago(duration.total!"seconds", "second");
	else
	if (duration < 1.hours)
		return ago(duration.total!"minutes", "minute");
	else
	if (duration < 1.days)
		return ago(duration.total!"hours", "hour");
	else
	/*if (duration < dur!"days"(2))
		return "yesterday";
	else
	if (duration < dur!"days"(6))
		return formatTime("l", time);
	else*/
	if (duration < 7.days)
		return ago(duration.total!"days", "day");
	else
	if (duration < 31.days)
		return ago(duration.total!"weeks", "week");
	else
	if (duration < 365.days)
		return ago(duration.total!"days" / 30, "month");
	else
		return ago(duration.total!"days" / 365, "year");
}

string formatLongTime(SysTime time)
{
	return time.formatTime!"l, d F Y, H:i:s e"();
}

/// Add thousand-separators
string formatNumber(long n)
{
	string s = text(n);
	int digits = 0;
	foreach_reverse(p; 1..s.length)
		if (++digits % 3 == 0)
			s = s[0..p] ~ ',' ~ s[p..$];
	return s;
}

static string truncateString(string s8, int maxLength = 30)
{
	auto encoded = encodeHtmlEntities(s8);
	return `<span class="truncated" style="max-width: ` ~ text(maxLength * 0.6) ~ `em" title="`~encoded~`">` ~ encoded ~ `</span>`;
}

/+
/// Generate a link to set a user preference
string setOptionLink(string name, string value)
{
	return "/set?" ~ encodeUrlParameters(UrlParameters([name : value, "url" : "__URL__", "secret" : userSettings.secret]));
}
+/

// ***********************************************************************

enum FEED_HOURS_DEFAULT = 24;
enum FEED_HOURS_MAX = 72;

CachedSet!(string, CachedResource) feedCache;

CachedResource getFeed(GroupInfo groupInfo, bool threadsOnly, int hours)
{
	string feedUrl = site.proto ~ "://" ~ site.host ~ "/feed" ~
		(threadsOnly ? "/threads" : "/posts") ~
		(groupInfo ? "/" ~ groupInfo.urlName : "") ~
		(hours!=FEED_HOURS_DEFAULT ? "?hours=" ~ text(hours) : "");

	CachedResource getFeed()
	{
		auto title = "Latest " ~ (threadsOnly ? "threads" : "posts") ~ (groupInfo ? " on " ~ groupInfo.publicName : "");
		auto posts = getFeedPosts(groupInfo, threadsOnly, hours);
		auto feed = makeFeed(posts, feedUrl, title, groupInfo is null);
		return feed;
	}
	return feedCache(feedUrl, getFeed());
}

Rfc850Post[] getFeedPosts(GroupInfo groupInfo, bool threadsOnly, int hours)
{
	string PERF_SCOPE = "getFeedPosts(%s,%s,%s)".format(groupInfo ? groupInfo.internalName : "null", threadsOnly, hours); mixin(MeasurePerformanceMixin);

	auto since = (Clock.currTime() - dur!"hours"(hours)).stdTime;
	auto iterator =
		groupInfo ?
			threadsOnly ?
				query!"SELECT `Message` FROM `Posts` WHERE `ID` IN (SELECT `ID` FROM `Groups` WHERE `Time` > ? AND `Group` = ?) AND `ID` = `ThreadID`".iterate(since, groupInfo.internalName)
			:
				query!"SELECT `Message` FROM `Posts` WHERE `ID` IN (SELECT `ID` FROM `Groups` WHERE `Time` > ? AND `Group` = ?)".iterate(since, groupInfo.internalName)
		:
			threadsOnly ?
				query!"SELECT `Message` FROM `Posts` WHERE `Time` > ? AND `ID` = `ThreadID`".iterate(since)
			:
				query!"SELECT `Message` FROM `Posts` WHERE `Time` > ?".iterate(since)
		;

	Rfc850Post[] posts;
	foreach (string message; iterator)
		posts ~= new Rfc850Post(message);
	return posts;
}

CachedResource makeFeed(Rfc850Post[] posts, string feedUrl, string feedTitle, bool addGroup)
{
	AtomFeedWriter feed;
	feed.startFeed(feedUrl, feedTitle, Clock.currTime());

	foreach (post; posts)
	{
		html.clear();
		html.put("<pre>");
		formatBody(post);
		html.put("</pre>");

		auto postTitle = post.rawSubject;
		if (addGroup)
			postTitle = "[" ~ post.publicGroupNames().join(", ") ~ "] " ~ postTitle;

		feed.putEntry(post.url, postTitle, post.author, post.time, cast(string)html.get(), post.url);
	}
	feed.endFeed();

	return new CachedResource([Data(feed.xml.output.get())], "application/atom+xml");
}

CachedResource getSubscriptionFeed(string subscriptionID)
{
	string feedUrl = site.proto ~ "://" ~ site.host ~ "/subscription-feed/" ~ subscriptionID;

	CachedResource getFeed()
	{
		auto subscription = getSubscription(subscriptionID);
		auto title = "%s subscription (%s)".format(site.host, subscription.trigger.getTextDescription());
		Rfc850Post[] posts;
		foreach (string messageID; query!"SELECT [MessageID] FROM [SubscriptionPosts] WHERE [SubscriptionID] = ? ORDER BY [Time] DESC LIMIT 50"
							.iterate(subscriptionID))
		{
			auto post = getPost(messageID);
			if (post)
				posts ~= post;
		}

		return makeFeed(posts, feedUrl, title, true);
	}
	return feedCache(feedUrl, getFeed());
}

// **************************************************************************

class Redirect : Throwable
{
	string url;
	this(string url) { this.url = url; super("Uncaught redirect"); }
}

class NotFoundException : Exception
{
	this(string str = "The specified resource cannot be found on this server.") { super(str); }
}

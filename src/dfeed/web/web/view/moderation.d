/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2025  Vladimir Panteleev <vladimir@thecybershadow.net>
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
import dfeed.paths : resolveSiteFile;
import dfeed.site : site;
import dfeed.sources.newsgroups : NntpConfig;
import dfeed.web.posting : PostDraft, PostProcess;
import dfeed.web.user : User;
import dfeed.web.web.draft : getDraft, draftToPost;
import dfeed.web.web.moderation : findPostingLog, moderatePost, approvePost, getUnbanPreviewByKey, unbanPoster, UnbanTree;
import dfeed.web.web.page : html, Redirect;
import dfeed.web.web.part.post : formatPost;
import dfeed.web.web.posting : postDraft;
import dfeed.web.web.user : user, userSettings;

struct JourneyEvent
{
	string timestamp;
	string type;      // "captcha", "spam_check", "moderation", "posted", "info"
	string message;
	bool success;     // true for success, false for failure
	string details;   // additional details like spamicity value
}

JourneyEvent[] parsePostingJourney(string messageID)
{
	import std.file : exists, read, dirEntries, SpanMode;
	import std.algorithm : filter, startsWith, endsWith;
	import std.array : array;
	import std.string : split, indexOf, strip;
	import std.regex : match, matchFirst;
	import std.path : baseName;
	import std.process : execute;

	JourneyEvent[] events;

	// Extract the post ID from message ID
	if (!messageID.startsWith("<") || !messageID.endsWith(">"))
		return events;

	auto messageIDclean = messageID[1..$-1];
	auto atPos = messageIDclean.indexOf("@");
	if (atPos < 0)
		return events;

	auto postID = messageIDclean[0..atPos];
	if (postID.length != 20)
		return events;

	// Find all PostProcess logs for this post ID (there may be multiple attempts)
	string[] logFiles;
	version (Windows)
		logFiles = dirEntries("logs", "*PostProcess-" ~ postID ~ ".log", SpanMode.depth).array.map!(e => e.name).array;
	else
	{
		auto result = execute(["find", "logs/", "-name", "*PostProcess-" ~ postID ~ ".log"]);
		if (result.status == 0)
			logFiles = result.output.split("\n").filter!(f => f.length > 0).array;
	}

	// Also find previous attempt logs (different post IDs but same user/content)
	// For now, we'll parse all logs for the same date/prefix
	version (Windows)
	{
		// On Windows, search for logs from the same day
		auto dayPrefix = baseName(logFiles.length > 0 ? logFiles[0] : "");
		if (dayPrefix.length >= 10)
		{
			dayPrefix = dayPrefix[0..10]; // e.g., "2025-11-19"
			auto sameDayLogs = dirEntries("logs", dayPrefix ~ "*PostProcess-*.log", SpanMode.depth).array.map!(e => e.name).array;
			logFiles ~= sameDayLogs.filter!(f => !logFiles.canFind(f)).array;
		}
	}
	else
	{
		// Use find to get logs from the same date
		if (logFiles.length > 0)
		{
			auto dayPrefix = baseName(logFiles[0]);
			if (dayPrefix.length >= 10)
			{
				dayPrefix = dayPrefix[0..10];
				auto result2 = execute(["find", "logs/", "-name", dayPrefix ~ "*PostProcess-*.log"]);
				if (result2.status == 0)
				{
					auto sameDayLogs = result2.output.split("\n").filter!(f => f.length > 0).array;
					logFiles ~= sameDayLogs.filter!(f => !logFiles.canFind(f)).array;
				}
			}
		}
	}

	// Sort logs by filename (which includes timestamp)
	import std.algorithm.sorting : sort;
	logFiles.sort();

	// Parse each log file
	foreach (logFile; logFiles)
	{
		if (!exists(logFile))
			continue;

		auto content = cast(string)read(logFile);
		auto logPostID = "";
		auto m = logFile.match(` - PostProcess-([a-z]{20})\.log`);
		if (m)
			logPostID = m.captures[1];

		foreach (line; content.split("\n"))
		{
			if (line.length < 30 || line[0] != '[')
				continue;

			// Extract timestamp
			auto closeBracket = line.indexOf("]");
			if (closeBracket < 0)
				continue;
			auto timestamp = line[1..closeBracket];
			auto message = line[closeBracket + 2 .. $];

			// Parse different event types
			if (message.startsWith("IP: "))
			{
				events ~= JourneyEvent(timestamp, "info", "IP Address", true, message[4..$]);
			}
			else if (message.startsWith("CAPTCHA OK"))
			{
				events ~= JourneyEvent(timestamp, "captcha", "CAPTCHA solved successfully", true, "");
			}
			else if (message.startsWith("CAPTCHA failed: "))
			{
				events ~= JourneyEvent(timestamp, "captcha", "CAPTCHA failed", false, message[16..$]);
			}
			else if (message.startsWith("Spam check failed (spamicity: "))
			{
				auto spamMatch = message.matchFirst(`Spam check failed \(spamicity: ([\d.]+)\): (.+)`);
				if (spamMatch)
					events ~= JourneyEvent(timestamp, "spam_check", "Spam check failed", false,
						"Spamicity: " ~ spamMatch[1] ~ " - " ~ spamMatch[2]);
			}
			else if (message.startsWith("Spam check OK (spamicity: "))
			{
				auto spamMatch = message.matchFirst(`Spam check OK \(spamicity: ([\d.]+)\)`);
				if (spamMatch)
					events ~= JourneyEvent(timestamp, "spam_check", "Spam check passed", true,
						"Spamicity: " ~ spamMatch[1]);
			}
			else if (message.startsWith("Quarantined for moderation: "))
			{
				events ~= JourneyEvent(timestamp, "moderation", "Quarantined for moderation", false, message[28..$]);
			}
			else if (message.startsWith("< Message-ID: <"))
			{
				events ~= JourneyEvent(timestamp, "posted", "Post created with Message-ID", true,
					message[15..$-1]); // Remove "< Message-ID: <" and final ">"
			}
		}
	}

	return events;
}

void renderJourneyTimeline(JourneyEvent[] events)
{
	if (events.length == 0)
		return;

	html.put(
		`<div class="journey-timeline">` ~
			`<h3>User Journey</h3>` ~
			`<style>` ~
				`.journey-timeline { margin: 20px 0; padding: 15px; background: #f9f9f9; border: 1px solid #ddd; border-radius: 4px; }` ~
				`.journey-timeline h3 { margin-top: 0; color: #333; }` ~
				`.journey-event { margin: 10px 0; padding: 10px; background: white; border-left: 4px solid #ccc; }` ~
				`.journey-event.success { border-left-color: #4caf50; }` ~
				`.journey-event.failure { border-left-color: #f44336; }` ~
				`.journey-event.info { border-left-color: #2196f3; }` ~
				`.journey-timestamp { font-family: monospace; color: #666; font-size: 0.9em; }` ~
				`.journey-message { font-weight: bold; margin: 5px 0; }` ~
				`.journey-details { color: #555; font-size: 0.95em; font-family: monospace; }` ~
			`</style>`
	);

	foreach (event; events)
	{
		string cssClass = event.success ? "success" : (event.type == "info" ? "info" : "failure");
		html.put(
			`<div class="journey-event `, cssClass, `">` ~
				`<div class="journey-timestamp">`), html.putEncodedEntities(event.timestamp), html.put(`</div>` ~
				`<div class="journey-message">`), html.putEncodedEntities(event.message), html.put(`</div>`
		);
		if (event.details.length > 0)
		{
			html.put(`<div class="journey-details">`), html.putEncodedEntities(event.details), html.put(`</div>`);
		}
		html.put(`</div>`);
	}

	html.put(`</div>`);
}

void discussionModeration(Rfc850Post post, UrlParameters postVars)
{
	if (postVars == UrlParameters.init)
	{
		// Display user journey timeline
		auto journeyEvents = parsePostingJourney(post.id);
		renderJourneyTimeline(journeyEvents);

		auto sinkNames = post.xref
			.map!(x => x.group.getGroupInfo())
			.filter!(g => g.sinkType == "nntp")
			.map!(g => g.sinkName[])
			.array.sort.uniq
		;
		auto deleteCommands = sinkNames
			.map!(sinkName => loadIni!NntpConfig(resolveSiteFile("config/sources/nntp/" ~ sinkName ~ ".ini")).deleteCommand)
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

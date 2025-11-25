/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2021, 2025  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.posting;

import std.algorithm;
import std.conv;
import std.datetime;
import std.exception;
import std.range.primitives;
import std.string;
import std.file;

import ae.net.ietf.headers;
import ae.net.ietf.url;
import ae.net.nntp.client;
import ae.net.smtp.client;
import ae.sys.log;
import ae.utils.array;
import ae.utils.sini;
import ae.utils.text;

import dfeed.loc;
import dfeed.common;
import dfeed.database;
import dfeed.groups;
import dfeed.message;
import dfeed.site;
import dfeed.sources.newsgroups : NntpConfig;
import dfeed.web.captcha;
import dfeed.web.spam;
import dfeed.web.user;
import dfeed.web.web.postmod : ModerationReason, shouldModerate;
import dfeed.web.web.posting : moderateMessage;

struct PostDraft
{
	/// Note: convert this to int before writing to database!
	enum Status : int
	{
		/// Unused. Default value, invalid.
		reserved   = 0,

		/// Unsent draft.
		edited     = 1,

		/// Sent draft.
		sent       = 2,

		/// Discarded draft.
		/// Persisted in the database, at least for a while, to enable one-click undo.
		discarded  = 3,

		/// In the moderation queue.
		/// Inaccessible to the author while in this state (mainly so
		/// they can't vandalize the message if they know a moderator
		/// will reject it, or recover its text and attempt to repost
		/// it from another identity).
		moderation = 4,
	}

	Status status;
	UrlParameters clientVars;
	string[string] serverVars;
}

enum PostingStatus
{
	none,
	captcha,
	spamCheck,
	connecting,
	posting,
	waiting,
	posted,
	moderated,

	captchaFailed,
	spamCheckFailed,
	serverError,

	redirect,
}

struct PostError
{
	string message;
	CaptchaErrorData captchaError;
	string extraHTML;
}

final class PostProcess
{
	PostDraft draft;
	string pid, ip;
	Headers headers;
	Rfc850Post post;
	PostingStatus status;
	PostError error;
	bool captchaPresent;
	User user;

	this(PostDraft draft, User user, string userID, string ip, Headers headers, Rfc850Post parent)
	{
		this.draft = draft;
		this.ip = ip;
		this.headers = headers;
		this.user = user;

		this.post = createPost(draft, headers, ip, parent);

		enforce(draft.clientVars.get("name", "").length, _!"Please enter a name");
		enforce(draft.clientVars.get("email", "").length, _!"Please enter an email address");
		enforce(draft.clientVars.get("subject", "").length, _!"Please enter a message subject");
		enforce(draft.clientVars.get("text", "").length, _!"Please enter a message");

		this.pid = randomString();
		postProcesses[pid] = this;
		this.post.id = pidToMessageID(pid);

		log = createLogger("PostProcess-" ~ pid);
		log("IP: " ~ ip);
		foreach (name, value; draft.clientVars)
			foreach (line; splitAsciiLines(value))
				log("[Form] " ~ name ~ ": " ~ line);
		foreach (name, value; draft.serverVars)
			foreach (line; splitAsciiLines(value))
				log("[ServerVar] " ~ name ~ ": " ~ line);
		foreach (name, value; headers)
			log("[Header] " ~ name ~ ": " ~ value);

		// Discard duplicate posts (redirect to original)
		string allContent = draftContent(draft);
		if (allContent in postsByContent && postsByContent[allContent] in postProcesses && postProcesses[postsByContent[allContent]].status != PostingStatus.serverError)
		{
			string original = postsByContent[allContent];
			log("Duplicate post, redirecting to " ~ original);
			pid = original;
			status = PostingStatus.redirect;
			return;
		}
		else
			postsByContent[allContent] = pid;

		post.compile();
	}

	/// Parse a log file
	this(string fileName)
	{
		pid = "unknown";

		{
			import std.regex;

			auto m = fileName.match(` - PostProcess-([a-z]{20})\.log`);
			if (m)
				pid = m.captures[1];
		}
		foreach (line; split(cast(string)read(fileName), "\n"))
		{
			if (line.length < 30 || line[0] != '[')
				continue;
			line = line.findSplit("] ")[2]; // trim timestamp

			static void addLine(T)(ref T aa, string var, string line)
			{
				if (var in aa)
				{
					if (!line.isOneOf(aa[var].split("\n")))
						aa[var] ~= "\n" ~ line;
				}
				else
					aa[var] = line;
			}

			if (line.skipOver("[Form] "))
			{
				auto var = line.skipUntil(": ");
				if (var=="where" || var=="parent")
					addLine(draft.serverVars, var, line);
				else
					addLine(draft.clientVars, var, line);
			}
			else
			if (line.skipOver("[ServerVar] "))
			{
				auto var = line.skipUntil(": ");
				addLine(draft.serverVars, var, line);
			}
			else
			if (line.skipOver("[Header] "))
			{
				auto name = line.skipUntil(": ");
				headers[name] = line;
			}
			else
			if (line.skipOver("IP: "))
				ip = line;
			else
			if (line.skipOver("< Message-ID: <"))
				pid = line.skipUntil("@");
		}
		post = createPost(draft, headers, ip, null);
		post.id = pidToMessageID(pid);
		post.compile();
	}

	// Parse back a Rfc850Post (e.g. to check spam of an arbitrary message)
	this(Rfc850Post post)
	{
		this.post = post;

		draft.clientVars["name"] = post.author;
		draft.clientVars["email"] = post.authorEmail;
		draft.clientVars["subject"] = post.subject;
		draft.clientVars["text"] = post.content; // TODO: unwrap
		draft.serverVars["where"] = post.where;

		foreach (name, value; post.headers)
			if (name.skipOver("X-Web-"))
			{
				if (name == "Originating-IP")
					this.ip = value;
				else
					this.headers.add(name, value);
			}
	}

	static string pidToMessageID(string pid)
	{
		return format("<%s@%s>", pid, site.host);
	}

	void logLine(string s)
	{
		try
			log.log(s);
		catch (Exception e) {}
	}

	void run()
	{
		assert(status != PostingStatus.redirect, "Attempting to run a duplicate PostProcess");

		if ("preapproved" in draft.serverVars)
		{
			log("Pre-approved, skipping spam check / CAPTCHA");
			postMessage();
			return;
		}

		auto captcha = getCaptcha(post.captcha);
		captchaPresent = captcha ? captcha.isPresent(draft.clientVars) : false;
		if (captchaPresent)
		{
			log("Checking CAPTCHA");
			status = PostingStatus.captcha;
			captcha.verify(draft.clientVars, ip, &onCaptchaResult);
		}
		else
		{
			if (user)
			{
				auto n = user.get("solved-captchas", "0", SettingType.registered).to!uint;
				enum captchaThreshold = 10;
				if (n >= captchaThreshold)
				{
					log("User is trusted, skipping spam check");
					postMessage();
					return;
				}
			}

			log("Checking for spam");
			status = PostingStatus.spamCheck;
			spamCheck(this, &onSpamResult, &logLine);
		}
	}

	static Rfc850Post createPost(PostDraft draft, Headers headers, string ip, Rfc850Post parent = null)
	{
		Rfc850Post post;
		if ("parent" in draft.serverVars)
		{
			if (parent)
			{
				auto parentID = draft.serverVars["parent"];
				assert(parent.id == parentID, "Invalid parent ID");
				post = parent.replyTemplate();
			}
			else
				post = Rfc850Post.newPostTemplate(null);
		}
		else
		{
			assert(parent is null, "Parent specified but not parent in serverVars");

			if ("where" in draft.serverVars)
				post = Rfc850Post.newPostTemplate(draft.serverVars["where"]);
			else
				assert(false, "No 'parent' or 'where'");
		}

		post.author = draft.clientVars.get("name", null);
		post.authorEmail = draft.clientVars.get("email", null);
		post.subject = post.rawSubject = draft.clientVars.get("subject", null);
		post.setText(draft.clientVars.get("text", null));
		if ("markdown" in draft.clientVars)
			post.markup = "markdown";

		if (auto pUserAgent = "User-Agent" in headers)
			post.headers["X-Web-User-Agent"] = *pUserAgent;
		if (ip)
			post.headers["X-Web-Originating-IP"] = ip;

		if ("did" in draft.clientVars)
			post.id = format("<draft-%s@%s>", draft.clientVars["did"], site.host);
		post.msg.time = post.time;

		return post;
	}

	// **********************************************************************

	private static string draftContent(ref /*const*/ PostDraft draft)
	{
		return draft.clientVars.values.sort().release().join("\0");
	}

	static void allowReposting(ref /*const*/ PostDraft draft)
	{
		postsByContent.remove(draftContent(draft));
	}

	// **********************************************************************

private:
	Logger log;

	void onCaptchaResult(bool ok, string errorMessage, CaptchaErrorData errorData)
	{
		if (!ok)
		{
			this.status = PostingStatus.captchaFailed;
			this.error = PostError(_!"CAPTCHA error:" ~ " " ~ errorMessage, errorData);
			log("CAPTCHA failed: " ~ errorMessage);
			if (errorData) log("CAPTCHA error data: " ~ errorData.toString());
			log.close();
			return;
		}

		log("CAPTCHA OK");
		if (user)
		{
			auto n = user.get("solved-captchas", "0", SettingType.registered).to!uint;
			n++;
			user.set("solved-captchas", text(n), SettingType.registered);
			log("  (user solved %d CAPTCHAs)".format(n));
		}

		checkForModeration();
	}

	void onSpamResult(Spamicity spamicity, string errorMessage)
	{
		// Cache the overall spamicity for later retrieval
		draft.serverVars["spamicity"] = spamicity.text;

		if (spamicity >= spamThreshold)
		{
			log("Spam check failed (spamicity: %.2f): %s".format(spamicity, errorMessage));

			// Check if CAPTCHA is available to challenge the user
			if (getCaptcha(post.captcha))
			{
				// CAPTCHA available - let user try to solve it
				this.status = PostingStatus.spamCheckFailed;
				this.error = PostError(errorMessage);
			}
			else
			{
				// No CAPTCHA configured - quarantine for moderation
				auto reason = ModerationReason(ModerationReason.Kind.spam, "No CAPTCHA configured and spam check failed: " ~ errorMessage);
				this.status = PostingStatus.moderated;
				moderateMessage(draft, headers, reason);
				log("Quarantined for moderation: " ~ reason.toString());
			}

			log.close();
			return;
		}
		log("Spam check OK (spamicity: %.2f)".format(spamicity));

		checkForModeration();
	}

	void checkForModeration()
	{
		auto moderationReason = shouldModerate(draft);
		if (moderationReason.kind != ModerationReason.Kind.none)
		{
			this.status = PostingStatus.moderated;
			moderateMessage(draft, headers, moderationReason);
			log("Quarantined for moderation: " ~ moderationReason.toString());
			log.close();
			return;
		}

		postMessage();
	}

	// **********************************************************************

	void postMessage()
	{
		auto groups = post.xref.map!(x => x.group.getGroupInfo());
		enforce(groups.length, "No groups");
		auto group = groups.front;
		auto sinkTypes = groups.map!(group => group.sinkType.dup); // Issue 17264
		enforce(sinkTypes.uniq.walkLength == 1, "Can't cross-post across protocols");
		switch (group.sinkType)
		{
			case null:
				throw new Exception(_!"You can't post to this group.");
			case "nntp":
				nntpSend(group.sinkName);
				break;
			case "smtp":
				smtpSend(group);
				break;
			case "local":
				localSend();
				break;
			default:
				assert(false, "Unknown sinkType: " ~ group.sinkType);
		}
	}

	void nntpSend(string name)
	{
		NntpClient nntp;

		void onDisconnect(string reason, DisconnectType type)
		{
			this.status = PostingStatus.serverError;
			this.error = PostError(_!"NNTP connection error:" ~ " " ~ reason);
			log("NNTP connection error: " ~ reason);
			log.close();
		}

		void onError(string error)
		{
			this.status = PostingStatus.serverError;
			this.error = PostError(_!"NNTP error:" ~ " " ~ error);
			nntp.handleDisconnect = null;
			if (nntp.connected)
				nntp.disconnect();
			log("NNTP error: " ~ error);
			log.close();
		}

		void onPosted()
		{
			if (this.status == PostingStatus.posting)
				this.status = PostingStatus.waiting;
			nntp.handleDisconnect = null;
			nntp.disconnect();
			log("Message posted successfully.");
			log.close();
		}

		void onConnect()
		{
			this.status = PostingStatus.posting;
			nntp.postMessage(post.message.splitAsciiLines(), &onPosted, &onError);
		}

		status = PostingStatus.connecting;

		auto config = loadIni!NntpConfig("config/sources/nntp/" ~ name ~ ".ini");
		if (!config.postingAllowed)
			throw new Exception(_!"Posting is disabled");

		nntp = new NntpClient(log);
		nntp.handleDisconnect = &onDisconnect;
		nntp.connect(config.host, &onConnect);
	}

	void smtpSend(in dfeed.groups.Config.Group* group)
	{
		SmtpClient smtp;

		void onError(string error)
		{
			this.status = PostingStatus.serverError;
			this.error = PostError(_!"SMTP error:" ~ " " ~ error);
			log("SMTP error: " ~ error);
			log.close();
		}

		void onSent()
		{
			if (this.status == PostingStatus.posting)
				this.status = PostingStatus.waiting;
			log("Message posted successfully.");
			log.close();
		}

		void onStateChanged()
		{
			if (smtp.state == SmtpClient.State.mailFrom)
				status = PostingStatus.posting;
		}

		status = PostingStatus.connecting;

		auto config = loadIni!SmtpConfig("config/sources/smtp/" ~ group.sinkName ~ ".ini");
		auto recipient = "<" ~ toLower(group.internalName) ~ "@" ~ config.domain ~ ">";

		smtp = new SmtpClient(log, site.host, config.server, config.port);
		smtp.handleSent = &onSent;
		smtp.handleError = &onError;
		smtp.handleStateChanged = &onStateChanged;
		smtp.sendMessage(
			"<" ~ post.authorEmail ~ ">",
			recipient,
			["To: " ~ recipient] ~ post.message.splitAsciiLines()
		);
	}

	void localSend()
	{
		status = PostingStatus.posting;
		announcePost(post, Fresh.yes);
		this.status = PostingStatus.posted;
		log("Message stored locally.");
		log.close();
	}
}

struct SmtpConfig
{
	string domain;
	string server;
	ushort port = 25;
	string listInfo;
}

PostProcess[string] postProcesses;
string[string] postsByContent;

final class PostingNotifySink : NewsSink
{
	override void handlePost(Post post, Fresh fresh)
	{
		auto rfc850post = cast(Rfc850Post)post;
		if (rfc850post)
		{
			auto id = rfc850post.id;
			if (id.endsWith("@" ~ site.host ~ ">"))
			{
				auto pid = id.split("@")[0][1..$];
				if (pid in postProcesses)
				{
					postProcesses[pid].status = PostingStatus.posted;
					postProcesses[pid].post.url = rfc850post.url;
					query!"UPDATE [Drafts] SET [Status]=? WHERE [ID]=?".exec(PostDraft.Status.sent, postProcesses[pid].draft.clientVars.get("did", pid));
				}
			}
		}
	}
}

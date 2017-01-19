/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module posting;

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

import captcha;
import common;
import database;
import groups;
import message;
import newsgroups;
import site;
import spam;
import user;

struct PostDraft
{
	int status;
	UrlParameters clientVars;
	string[string] serverVars;

	// Fake enum (force the type to be int)
	struct Status
	{
		enum reserved  = 0;
		enum edited    = 1;
		enum sent      = 2;
		enum discarded = 3;
	}
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

		enforce(draft.clientVars.get("name", "").length, "Please enter a name");
		enforce(draft.clientVars.get("email", "").length, "Please enter an email address");
		enforce(draft.clientVars.get("subject", "").length, "Please enter a message subject");
		enforce(draft.clientVars.get("text", "").length, "Please enter a message");

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
		string allContent = draft.clientVars.values.sort().release().join("\0");
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
		return format("<%s@%s>", pid, site.config.host);
	}

	void run()
	{
		assert(status != PostingStatus.redirect, "Attempting to run a duplicate PostProcess");

		captchaPresent = theCaptcha.isPresent(draft.clientVars);
		if (captchaPresent)
		{
			log("Checking CAPTCHA");
			status = PostingStatus.captcha;
			theCaptcha.verify(draft.clientVars, ip, &onCaptchaResult);
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
				}
			}

			log("Checking for spam");
			status = PostingStatus.spamCheck;
			spamCheck(this, &onSpamResult);
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

		post.headers["X-Web-User-Agent"] = aaGet(headers, "User-Agent");
		post.headers["X-Web-Originating-IP"] = ip;

		if ("did" in draft.clientVars)
			post.id = format("<draft-%s@%s>", draft.clientVars["did"], site.config.host);
		post.msg.time = post.time;

		return post;
	}

	// **********************************************************************

private:
	Logger log;

	void onCaptchaResult(bool ok, string errorMessage, CaptchaErrorData errorData)
	{
		if (!ok)
		{
			this.status = PostingStatus.captchaFailed;
			this.error = PostError("CAPTCHA error: " ~ errorMessage, errorData);
			log("CAPTCHA failed: " ~ errorMessage);
			if (errorData) log("CAPTCHA error data: " ~ errorData.toString());
			log.close();
			return;
		}

		log("CAPTCHA OK");
		if (user)
		{
			auto n = user.get("solvedCaptchas", "0", SettingType.registered).to!uint;
			n++;
			user.set("solved-captchas", text(n), SettingType.registered);
			log("  (user solved %d CAPTCHAs)".format(n));
		}

		postMessage();
	}

	void onSpamResult(bool ok, string errorMessage)
	{
		if (!ok)
		{
			this.status = PostingStatus.spamCheckFailed;
			this.error = PostError(errorMessage);
			log("Spam check failed: " ~ errorMessage);
			log.close();
			return;
		}
		log("Spam check OK");

		postMessage();
	}

	// **********************************************************************

	void postMessage()
	{
		auto groups = post.xref.map!(x => x.group.getGroupInfo());
		enforce(groups.length, "No groups");
		auto group = groups.front;
		auto sinkTypes = groups.map!(group => group.sinkType);
		enforce(sinkTypes.uniq.walkLength == 1, "Can't cross-post across protocols");
		switch (group.sinkType)
		{
			case null:
				throw new Exception("You can't post to this group.");
			case "nntp":
				nntpSend(group.sinkName);
				break;
			case "smtp":
				smtpSend(group);
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
			this.error = PostError("NNTP connection error: " ~ reason);
			log("NNTP connection error: " ~ reason);
			log.close();
		}

		void onError(string error)
		{
			this.status = PostingStatus.serverError;
			this.error = PostError("NNTP error: " ~ error);
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

		nntp = new NntpClient(log);
		nntp.handleDisconnect = &onDisconnect;
		nntp.connect(config.host, &onConnect);
	}

	void smtpSend(in groups.Config.Group* group)
	{
		SmtpClient smtp;

		void onError(string error)
		{
			this.status = PostingStatus.serverError;
			this.error = PostError("SMTP error: " ~ error);
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

		smtp = new SmtpClient(log, site.config.host, config.server, config.port);
		smtp.handleSent = &onSent;
		smtp.handleError = &onError;
		smtp.handleStateChanged = &onStateChanged;
		smtp.sendMessage(
			"<" ~ post.authorEmail ~ ">",
			recipient,
			["To: " ~ recipient] ~ post.message.splitAsciiLines()
		);
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
			if (id.endsWith("@" ~ site.config.host ~ ">"))
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

static this()
{
	new PostingNotifySink();
}

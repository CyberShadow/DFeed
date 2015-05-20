/*  Copyright (C) 2011, 2012, 2013, 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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
import std.datetime;
import std.exception;
import std.string;
import std.file;

import ae.utils.text;
import ae.utils.array;
import ae.sys.log;
import ae.net.nntp.client;

import captcha;
import common;
import message;
import site;
import spam;

struct PostDraft
{
	string[string] clientVars, serverVars;
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
	nntpError,

	redirect,
}

struct PostError
{
	string message;
	CaptchaErrorData captchaError;
}

final class PostProcess
{
	PostDraft draft;
	string pid, ip;
	string[string] headers;
	Rfc850Post post;
	PostingStatus status;
	PostError error;
	bool captchaPresent;

	this(Rfc850Post post, PostDraft draft, string userID, string ip, string[string] headers)
	{
		this.post = post;
		this.draft = draft;
		this.ip = ip;
		this.headers = headers;

		enforce(draft.clientVars.get("name", "").length, "Please enter a name");
		enforce(draft.clientVars.get("email", "").length, "Please enter an email address");
		enforce(draft.clientVars.get("text", "").length, "Please enter a message");

		this.pid = draft.clientVars["pid"];
		postProcesses[pid] = this;

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
		if (allContent in postsByContent)
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
			line = line[26..$]; // trim timestamp

			if (line.eat("[Form] "))
			{
				auto var = line.eatUntil(": ");
				if (var in draft.clientVars)
					draft.clientVars[var] ~= "\n" ~ line;
				else
					draft.clientVars[var] = line;
			}
			else
			if (line.eat("[ServerVar] "))
			{
				auto var = line.eatUntil(": ");
				if (var in draft.serverVars)
					draft.serverVars[var] ~= "\n" ~ line;
				else
					draft.serverVars[var] = line;
			}
			else
			if (line.eat("[Header] "))
			{
				auto name = line.eatUntil(": ");
				headers[name] = line;
			}
			else
			if (line.eat("IP: "))
				ip = line;
			else
			if (line.eat("< Message-ID: <"))
				pid = line.eatUntil("@");
		}
		post = createPost(draft, headers, ip, null);
		post.id = format("<%s@%s>", pid, site.config.host);
		post.compile();
	}

	void run()
	{
		captchaPresent = theCaptcha.isPresent(draft.clientVars);
		if (captchaPresent)
		{
			log("Checking CAPTCHA");
			status = PostingStatus.captcha;
			theCaptcha.verify(draft.clientVars, ip, &onCaptchaResult);
		}
		else
		{
			log("Checking for spam");
			status = PostingStatus.spamCheck;
			spamCheck(this, &onSpamResult);
		}
	}

	static Rfc850Post createPost(PostDraft draft, string[string] headers, string ip, Rfc850Post delegate(string id) getPost)
	{
		Rfc850Post post;
		if ("parent" in draft.serverVars)
		{
			if (getPost)
			{
				auto parent = getPost(draft.serverVars["parent"]);
				enforce(parent, "Can't find post to reply to.");
				post = parent.replyTemplate();
			}
			else
				post = Rfc850Post.newPostTemplate(null);
		}
		else
		if ("where" in draft.serverVars)
			post = Rfc850Post.newPostTemplate(draft.serverVars["where"]);

		post.author = aaGet(draft.clientVars, "name");
		post.authorEmail = aaGet(draft.clientVars, "email");
		post.subject = post.rawSubject = aaGet(draft.clientVars, "subject");
		post.setText(aaGet(draft.clientVars, "text"));

		post.headers["X-Web-User-Agent"] = aaGet(headers, "User-Agent");
		post.headers["X-Web-Originating-IP"] = ip;

		post.id = format("<%s@%s>", draft.clientVars["pid"], site.config.host);
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

	NntpClient nntp;

	void postMessage()
	{
		status = PostingStatus.connecting;

		nntp = new NntpClient(log);
		nntp.handleDisconnect = &onDisconnect;
		nntp.connect("news.digitalmars.com", &onConnect);
	}

	void onDisconnect(string reason, DisconnectType type)
	{
		this.status = PostingStatus.nntpError;
		this.error = PostError("NNTP connection error: " ~ reason);
		log("NNTP connection error: " ~ reason);
		log.close();
	}

	void onError(string error)
	{
		this.status = PostingStatus.nntpError;
		this.error = PostError("NNTP error: " ~ error);
		nntp.handleDisconnect = null;
		nntp.disconnect();
		log("NNTP error: " ~ error);
		log.close();
	}

	void onConnect()
	{
		this.status = PostingStatus.posting;
		nntp.postMessage(post.message.splitAsciiLines(), &onPosted, &onError);
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
}

PostProcess[string] postProcesses;
string[string] postsByContent;

final class PostingNotifySink : NewsSink
{
	override void handlePost(Post post)
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
				}
			}
		}
	}
}

static this()
{
	new PostingNotifySink();
}

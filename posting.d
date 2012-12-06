/*  Copyright (C) 2011, 2012  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.exception;
import std.string;
import std.file;

import ae.utils.text;
import ae.utils.array;
import ae.sys.log;
import ae.net.nntp.client;

import captcha;
import rfc850;
import spam;
import common;

enum PostingStatus
{
	None,
	Captcha,
	SpamCheck,
	Connecting,
	Posting,
	Waiting,
	Posted,

	CaptchaFailed,
	SpamCheckFailed,
	NntpError,

	Redirect,
}

struct PostError
{
	string message;
	CaptchaErrorData captchaError;
}

final class PostProcess
{
	string pid, ip;
	string[string] vars, headers;
	Rfc850Post post;
	PostingStatus status;
	PostError error;
	bool captchaPresent;

	this(Rfc850Post post, string[string] vars, string ip, string[string] headers)
	{
		this.post = post;
		this.vars = vars;
		this.ip = ip;
		this.headers = headers;

		enforce(vars.get("name", "").length, "Please enter a name");
		enforce(vars.get("email", "").length, "Please enter an e-mail address");
		enforce(vars.get("text", "").length, "Please enter a message");

		pid = randomString();
		postProcesses[pid] = this;

		log = createLogger("PostProcess-" ~ pid);
		log("IP: " ~ ip);
		foreach (name, value; vars)
			foreach (line; splitAsciiLines(value))
				log("[Form] " ~ name ~ ": " ~ line);
		foreach (name, value; headers)
			log("[Header] " ~ name ~ ": " ~ value);

		// Discard duplicate posts (redirect to original)
		string allContent = post.author ~ "\0" ~ post.authorEmail ~ "\0" ~ post.subject ~ "\0" ~ post.content;
		if (allContent in postsByContent)
		{
			string original = postsByContent[allContent];
			log("Duplicate post, redirecting to " ~ original);
			pid = original;
			status = PostingStatus.Redirect;
			return;
		}
		else
			postsByContent[allContent] = pid;

		post.id = format("<%s@%s>", pid, hostname);
		post.compile();

		captchaPresent = theCaptcha.isPresent(vars);
		if (captchaPresent)
		{
			log("Checking CAPTCHA");
			status = PostingStatus.Captcha;
			theCaptcha.verify(vars, ip, &onCaptchaResult);
		}
		else
		{
			log("Checking for spam");
			status = PostingStatus.SpamCheck;
			spamCheck(this, &onSpamResult);
		}
	}

	// **********************************************************************

private:
	Logger log;

	void onCaptchaResult(bool ok, string errorMessage, CaptchaErrorData errorData)
	{
		if (!ok)
		{
			this.status = PostingStatus.CaptchaFailed;
			this.error = PostError(errorMessage, errorData);
			log("CAPTCHA failed: " ~ errorMessage);
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
			this.status = PostingStatus.SpamCheckFailed;
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
		status = PostingStatus.Connecting;

		nntp = new NntpClient(log);
		nntp.handleConnect = &onConnect;
		nntp.handlePosted = &onPosted;
		nntp.handleDisconnect = &onDisconnect;
		nntp.handleError = &onError;
		nntp.connect("news.digitalmars.com");
	}

	void onDisconnect(string error)
	{
		this.status = PostingStatus.NntpError;
		this.error = PostError("NNTP connection error: " ~ error);
		log("NNTP connection error: " ~ error);
		log.close();
	}

	void onError(string error)
	{
		this.status = PostingStatus.NntpError;
		this.error = PostError("NNTP error: " ~ error);
		nntp.handleDisconnect = null;
		nntp.disconnect();
		log("NNTP error: " ~ error);
		log.close();
	}

	void onConnect()
	{
		this.status = PostingStatus.Posting;
		nntp.postMessage(post.message.splitAsciiLines());
	}

	void onPosted()
	{
		if (this.status == PostingStatus.Posting)
			this.status = PostingStatus.Waiting;
		nntp.handleDisconnect = null;
		nntp.disconnect();
	}
}

PostProcess[string] postProcesses;
string[string] postsByContent;
string hostname;

final class PostingNotifySink : NewsSink
{
	override void handlePost(Post post)
	{
		auto rfc850post = cast(Rfc850Post)post;
		if (rfc850post)
		{
			auto id = rfc850post.id;
			if (id.endsWith("@" ~ hostname ~ ">"))
			{
				auto pid = id.split("@")[0][1..$];
				if (pid in postProcesses)
				{
					postProcesses[pid].status = PostingStatus.Posted;
					postProcesses[pid].post.url = rfc850post.url;
				}
			}
		}
	}
}

static this()
{
	hostname = readText("data/web.txt").splitLines()[1];
	new PostingNotifySink();
}

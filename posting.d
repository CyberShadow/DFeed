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

import rfc850;
import recaptcha;
import spam;
import nntp;
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
}

final class PostProcess
{
	string pid, ip;
	string[string] vars, headers;
	Rfc850Post post;
	PostingStatus status;
	string errorMessage;
	bool captchaPresent;

	this(Rfc850Post post, string[string] vars, string ip, string[string] headers)
	{
		this.post = post;
		this.vars = vars;
		this.ip = ip;
		this.headers = headers;

		enforce(aaGet(vars, "name", "").length, "Please enter a name");
		enforce(aaGet(vars, "email", "").length, "Please enter an e-mail address");
		enforce(aaGet(vars, "text", "").length, "Please enter a message");

		pid = randomString();
		postProcesses[pid] = this;

		log = createLogger("PostProcess-" ~ pid);
		log("IP: " ~ ip);
		foreach (name, value; vars)
			foreach (line; splitAsciiLines(value))
				log("[Form] " ~ name ~ ": " ~ line);
		foreach (name, value; headers)
			log("[Header] " ~ name ~ ": " ~ value);

		post.id = format("<%s@%s>", pid, hostname);
		post.compile();

		captchaPresent = recaptchaPresent(vars);
		if (captchaPresent)
		{
			log("Checking CAPTCHA");
			status = PostingStatus.Captcha;
			recaptchaCheck(vars, ip, &onCaptchaResult);
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

	void onCaptchaResult(bool ok, string errorMessage)
	{
		if (!ok)
		{
			this.status = PostingStatus.CaptchaFailed;
			this.errorMessage = errorMessage;
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
			this.errorMessage = errorMessage;
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
		this.errorMessage = "NNTP connection error: " ~ error;
		log("NNTP connection error: " ~ error);
		log.close();
	}

	void onError(string error)
	{
		this.status = PostingStatus.NntpError;
		this.errorMessage = "NNTP error: " ~ error;
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

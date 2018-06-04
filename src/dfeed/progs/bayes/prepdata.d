/*  Copyright (C) 2015, 2016, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Extract data from logs and prepare it for training.

module dfeed.progs.bayes.prepdata;

import std.algorithm.comparison;
import std.algorithm.iteration;
import std.algorithm.searching;
import std.array;
import std.exception;
import std.file;
import std.path;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;

import ae.sys.file;
import ae.utils.aa;
import ae.utils.digest;
import ae.utils.regex;
import ae.utils.text;

import dfeed.web.lint;
import dfeed.web.posting;

void main()
{
	stderr.writeln("Reading deleted posts...");
	bool[string] deletedPosts;
	foreach (de; dirEntries("logs", "* - Deleted.log", SpanMode.shallow))
	{
		foreach (line; de.name.readText().splitLines())
		{
			if (!line.startsWith("["))
				continue;
			line = line.findSplit("] ")[2];

			if (auto m = line.matchFirst(re!`^User .* is deleting post <(.*)@.*> \(spam\)$`))
				deletedPosts[m[1]] = true;
		}
	}

	version (none) // linker error! >:(
	{
		auto manual = [false, true]
			.map!(isSpam =>
				("data/bayes-manual/" ~ ["ham", "spam"][isSpam] ~ "/")
				.dirEntries("*.txt", SpanMode.depth)
				.map!(de => tuple(de.baseName.stripExtension, isSpam))
			)
			.joiner
			.assocArray;
	}
	else
	{
		bool[string] manual;
		foreach (de; dirEntries("data/bayes-manual/ham/", "*.txt", SpanMode.depth))
			manual[de.baseName.stripExtension] = false;
		foreach (de; dirEntries("data/bayes-manual/spam/", "*.txt", SpanMode.depth))
			manual[de.baseName.stripExtension] = true;
	}

	enum Status { unknown, ok, failed, redeemed, deleted, manualHam, manualSpam }
	Status[string] posts;
	string[string] ids;
	string[][string] byDid;

	stderr.writeln("Reading posts...");
	auto logs = dirEntries("logs", "* - PostProcess-*.log", SpanMode.shallow).array();
	foreach (i, de; logs)
	{
		stderr.writefln("[%2d%%] %s", 100 * i / logs.length, de.name);
		PostProcess post;
		try
		{
			enforce(de.size < 1024*1024, "Too big!");
			post = new PostProcess(de.name);
		}
		catch (Throwable e)
		{
			writeln("\t", e.msg);
			continue;
		}

		string message;
		auto subject = post.draft.clientVars["subject"];
		if (!subject.startsWith("Re: "))
			message = subject ~ "\n\n";
		message ~= post.draft.getNonQuoteLines().join("\n");
		//writeln(message);

		auto status = Status.unknown;

		foreach (line; de.name.readText().splitLines())
		{
			if (!line.startsWith("["))
				continue;
			line = line.findSplit("] ")[2];

			if (line == "Spam check OK")
			{
				assert(status == Status.unknown);
				status = Status.ok;
			}
			else
			if (line.startsWith("Spam check failed: ") &&
				!line.contains("error"))
			{
				assert(status == Status.unknown);
				status = Status.failed;
			}
			else
			if (line == "CAPTCHA OK")
			{
				assert(status == Status.unknown);
				status = Status.redeemed;
			}
		}

		if (post.pid in deletedPosts)
			status = Status.deleted;

		if (auto pIsSpam = post.pid in manual)
			status = *pIsSpam ? Status.manualSpam : Status.manualHam;

		posts[message] = max(status, posts.get(message, Status.ok));
		ids[message] = post.pid;
		if ("did" in post.draft.clientVars)
			byDid[post.draft.clientVars["did"]] ~= message;
	}

	stderr.writeln("Collating...");
	foreach (did, messages; byDid)
		if (messages.length > 1)
		{
			auto status = messages.map!(message => posts[message]).reduce!max();
			foreach (message; messages)
				posts[message] = status;
		}

	stderr.writeln("Saving...");
	rmdirRecurse("data/bayes");
	foreach (post, status; posts)
	{
		auto fn = "data/bayes/%s/%s.txt".format(status, ids[post]);
		ensurePathExists(fn);
		std.file.write(fn, post);
	}
}

/*  Copyright (C) 2011, 2012, 2014, 2015, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.spam;

import std.algorithm;
import std.exception;
import std.file : readText;
import std.string;

import ae.net.http.client;
import ae.sys.data;
import ae.utils.array;
import ae.utils.json;
import ae.utils.text;

import dfeed.site;
import dfeed.web.posting;
import dfeed.web.spam.akismet;
import dfeed.web.spam.bayes;
import dfeed.web.spam.blogspam;
import dfeed.web.spam.projecthoneypot;
import dfeed.web.spam.simple;
import dfeed.web.spam.stopforumspam;

void spamCheck(PostProcess process, SpamResultHandler handler, void delegate(string) log = null)
{
	if (!spamCheckers)
		initSpamCheckers();

	int totalResults = 0;
	bool foundSpam = false;

	// Start all checks simultaneously
	foreach (checker; spamCheckers)
	{
		try
			(SpamChecker checker) {
				checker.check(process, (bool ok, string message) {
					totalResults++;
					if (log) log("Got reply from spam checker %s: %s (%s)".format(
						checker.classinfo.name, ok ? "ham" : "spam", message));
					if (!foundSpam)
					{
						if (!ok)
						{
							handler(false, message);
							foundSpam = true;
						}
						else
						{
							if (totalResults == spamCheckers.length)
								handler(true, null);
						}
					}
				});
			} (checker);
		catch (Exception e)
		{
			if (log) log("Error with spam checker %s: %s".format(
				checker.classinfo.name, e.msg));
			foundSpam = true;
			handler(false, "Spam check error: " ~ e.msg);
		}

		// Avoid starting slow checks if the first engines instantly return a positive
		if (foundSpam)
			break;
	}
}

void sendSpamFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
{
	if (!spamCheckers)
		initSpamCheckers();

	foreach (checker; spamCheckers)
		checker.sendFeedback(process, handler, feedback);
}

// **************************************************************************

alias void delegate(bool ok, string message) SpamResultHandler;

enum SpamFeedback { unknown, spam, ham }

class SpamChecker
{
	abstract void check(PostProcess process, SpamResultHandler handler);

	void sendFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
	{
		handler(true, "Not implemented");
	}
}

// **************************************************************************

double getSpamicity(PostDraft draft)
{
	if (!spamCheckers)
		initSpamCheckers();

	return bayes.checkDraft(draft);
}

// **************************************************************************

SpamChecker[] spamCheckers;
BayesChecker bayes;

void initSpamCheckers()
{
	assert(spamCheckers is null);

	import dfeed.common;
	spamCheckers ~= new SimpleChecker();
	spamCheckers ~= bayes = new BayesChecker();
	if (auto c = createService!ProjectHoneyPot("apis/projecthoneypot"))
		spamCheckers ~= c;
	if (auto c = createService!Akismet("apis/akismet"))
		spamCheckers ~= c;
	spamCheckers ~= new StopForumSpam();
	//spamCheckers ~= new BlogSpam();
}

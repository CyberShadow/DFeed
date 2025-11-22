/*  Copyright (C) 2011, 2012, 2014, 2015, 2017, 2018, 2020, 2025  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import dfeed.loc;
import dfeed.site;
import dfeed.web.posting;
import dfeed.web.spam.akismet;
import dfeed.web.spam.bayes;
import dfeed.web.spam.blogspam;
import dfeed.web.spam.openai;
import dfeed.web.spam.projecthoneypot;
import dfeed.web.spam.simple;
import dfeed.web.spam.stopforumspam;

void spamCheck(PostProcess process, SpamResultHandler handler, void delegate(string) log = null)
{
	if (!spamCheckers)
		initSpamCheckers();

	int totalResults = 0;
	bool foundSpam = false;
	Spamicity maxSpamicity = 0.0;
	string maxSpamicityMessage = null;

	// Start all checks simultaneously
	foreach (checker; spamCheckers)
	{
		try
			(SpamChecker checker) {
				checker.check(process, (Spamicity spamicity, string message) {
					totalResults++;
					if (log) log("Got reply from spam checker %s: spamicity %.2f (%s)".format(
						checker.classinfo.name, spamicity, message));
					if (!foundSpam)
					{
						// Track the highest spamicity score
						if (spamicity > maxSpamicity)
						{
							maxSpamicity = spamicity;
							maxSpamicityMessage = message;
						}

						// If spamicity exceeds threshold, immediately report as spam
						if (spamicity >= spamThreshold)
						{
							handler(spamicity, message);
							foundSpam = true;
						}
						else
						{
							// If all checkers are done and none found spam, report max spamicity
							if (totalResults == spamCheckers.length)
								handler(maxSpamicity, maxSpamicityMessage);
						}
					}
				});
			} (checker);
		catch (Exception e)
		{
			if (log) log("Error with spam checker %s: %s".format(
				checker.classinfo.name, e.msg));
			foundSpam = true;
			handler(errorSpam, _!"Spam check error:" ~ " " ~ e.msg);
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

/// Spam confidence score: 0.0 = definitely ham (not spam), 1.0 = definitely spam
/// This follows industry-standard semantics where higher values indicate higher spam probability
alias Spamicity = double;

/// Confidence threshold - scores >= this value are considered spam
enum Spamicity spamThreshold = 0.5;

/// Very high confidence threshold - scores >= this value should be quarantined/moderated
enum Spamicity certainlySpamThreshold = 0.98;

/// Predefined spamicity levels for checkers that don't provide granular scores
enum Spamicity certainlyHam  = 0.0;  /// Definitely not spam
enum Spamicity likelyHam     = 0.25; /// Probably not spam
enum Spamicity likelySpam    = 0.75; /// Probably spam
enum Spamicity certainlySpam = 1.0;  /// Definitely spam

/// Confidence level returned by spam checkers when they are not configured
/// (missing API keys or other configuration).
/// We return 0 so that the maximizing logic in spamCheck treats this result
/// synonymously with the spam checker not being present.
alias unconfiguredHam = certainlyHam;

/// Confidence level for errors (challenge instead of outright rejection)
alias errorSpam = likelySpam;

alias void delegate(Spamicity spamicity, string message) SpamResultHandler;

enum SpamFeedback { unknown, spam, ham }

class SpamChecker
{
	abstract void check(PostProcess process, SpamResultHandler handler);

	void sendFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
	{
		handler(likelyHam, "Not implemented");
	}
}

// **************************************************************************

BayesChecker bayes()
{
	if (!spamCheckers)
		initSpamCheckers();

	return bayesInst;
}

Spamicity getSpamicity(in ref PostDraft draft)
{
	return bayes.checkDraft(draft);
}

// **************************************************************************

SpamChecker[] spamCheckers;
private BayesChecker bayesInst;

void initSpamCheckers()
{
	assert(spamCheckers is null);

	import dfeed.common;
	spamCheckers ~= new SimpleChecker();
	spamCheckers ~= bayesInst = new BayesChecker();
	if (auto c = createService!ProjectHoneyPot("apis/projecthoneypot"))
		spamCheckers ~= c;
	if (auto c = createService!Akismet("apis/akismet"))
		spamCheckers ~= c;
	spamCheckers ~= new StopForumSpam();
	//spamCheckers ~= new BlogSpam();
}

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

module dfeed.web.spam.bayes;

import std.algorithm.searching;
import std.file;
import std.string;

import ae.utils.json;
import ae.utils.text;

import dfeed.bayes;
import dfeed.web.lint;
import dfeed.web.posting;
import dfeed.web.spam;

class BayesChecker : SpamChecker
{
	BayesModel model;
	bool modelLoaded;

	this()
	{
		auto fn = "data/bayes/model.json";
		if (fn.exists)
		{
			model = fn.readText.jsonParse!BayesModel;
			modelLoaded = true;
		}
	}

	double checkDraft(PostDraft draft)
	{
		string message;
		auto subject = draft.clientVars.get("subject", "").toLower();
		if ("parent" !in draft.serverVars || !subject.startsWith("Re: ")) // top-level or custom subject
			message = subject ~ "\n\n";
		message ~= draft.getNonQuoteLines().join("\n");

		return model.checkMessage(message);
	}

	override void check(PostProcess process, SpamResultHandler handler)
	{
		if (!modelLoaded)
			return handler(true, "No model");

		auto prob = checkDraft(process.draft);
		bool isSpam = prob >= probThreshold;

		auto percent = cast(int)(prob * 100);
		if (isSpam)
			handler(false, "Your post looks like spam (%d%% spamicity)".format(percent));
		else
			handler(true, "%d%%".format(percent));
	}
}

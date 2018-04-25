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

	override void check(PostProcess process, SpamResultHandler handler)
	{
		if (!modelLoaded)
			return handler(true, "No model");

		string message;
		auto subject = process.draft.clientVars.get("subject", "").toLower();
		if ("parent" !in process.draft.serverVars || !subject.startsWith("Re: ")) // top-level or custom subject
			message = subject ~ "\n\n";
		message ~= process.draft.getNonQuoteLines().join("\n");

		auto prob = model.checkMessage(message);
		bool isSpam = prob >= probThreshold;

		handler(!isSpam, "Your post looks like spam (probability %d%%)".format(cast(int)(prob * 100)));
	}
}

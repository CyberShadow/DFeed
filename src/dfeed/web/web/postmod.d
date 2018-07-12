/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Automatic moderation of new posts.
module dfeed.web.web.postmod;

import std.array : array;
import std.format : format;

import dfeed.bayes : BayesModel, splitWords, splitWords, train, checkMessage;
import dfeed.web.posting : PostDraft;
import dfeed.web.spam : bayes, getSpamicity;
import dfeed.web.web : banCheck;
import dfeed.web.web.request : ip, currentRequest;

/// Bayes model trained to detect recently moderated messages. RAM only.
/// The model is based off the spam model, but we throw away all spam data at first.
BayesModel* getModerationModel()
{
	static BayesModel* model;
	if (!model)
	{
		model = new BayesModel;
		*model = bayes.model;
		model.words = model.words.dup;
		foreach (word, ref counts; model.words)
			counts.spamCount = 0;
		model.spamPosts =  0;
	}
	return model;
}

void learnModeratedMessage(in ref PostDraft draft, bool isBad, int weight)
{
	auto message = bayes.messageFromDraft(draft);
	auto model = getModerationModel();
	auto words = message.splitWords.array;
	train(*model, words, isBad, weight);
}

double checkModeratedMessage(in ref PostDraft draft)
{
	auto message = bayes.messageFromDraft(draft);
	auto model = getModerationModel();
	return checkMessage(*model, message);
}

/// Should this post be queued for moderation instead of being posted immediately?
/// If yes, return a reason; if no, return null.
string shouldModerate(in ref PostDraft draft)
{
	auto spamicity = getSpamicity(draft);
	if (spamicity >= 0.98)
		return "Very high Bayes spamicity (%s%%)".format(spamicity * 100);

	if (auto reason = banCheck(ip, currentRequest))
		return "Post from banned user (ban reason: " ~ reason ~ ")";

	auto modScore = checkModeratedMessage(draft);
	if (modScore >= 0.95)
		return "Very similar to recently moderated messages (%s%%)".format(modScore * 100);

	return null;
}

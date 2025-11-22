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
import dfeed.web.spam : bayes, getSpamicity, certainlySpamThreshold;
import dfeed.web.web.moderation : banCheck;
import dfeed.web.web.request : ip, currentRequest;

struct ModerationReason
{
	enum Kind
	{
		none,
		spam,
		bannedUser,
		similarToModerated,
	}

	Kind kind;
	string details;  // Additional information (ban reason, percentage, etc.)
	string bannedKey;  // The specific banned key that matched (only for bannedUser)

	/// Returns a human-readable description
	string toString() const
	{
		final switch (kind)
		{
			case Kind.none:
				return null;
			case Kind.spam:
				return "Very high Bayes spamicity (" ~ details ~ ")";
			case Kind.bannedUser:
				return "Post from banned user (ban reason: " ~ details ~ ")";
			case Kind.similarToModerated:
				return "Very similar to recently moderated messages (" ~ details ~ ")";
		}
	}
}

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
/// If yes, return a reason; if no, return ModerationReason with kind == none.
ModerationReason shouldModerate(in ref PostDraft draft)
{
	auto spamicity = getSpamicity(draft);
	if (spamicity >= certainlySpamThreshold)
		return ModerationReason(ModerationReason.Kind.spam, format("%s%%", spamicity * 100), null);

	auto banResult = banCheck(ip, currentRequest);
	if (banResult)
		return ModerationReason(ModerationReason.Kind.bannedUser, banResult.reason, banResult.key);

	auto modScore = checkModeratedMessage(draft);
	if (modScore >= 0.95)
		return ModerationReason(ModerationReason.Kind.similarToModerated, format("%s%%", modScore * 100), null);

	return ModerationReason(ModerationReason.Kind.none, null, null);
}

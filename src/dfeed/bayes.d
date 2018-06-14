/*  Copyright (C) 2015, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Common code for the naive Bayes classifier.

module dfeed.bayes;

struct BayesModel
{
	struct Word
	{
		ulong spamCount, hamCount;
	}
	 
	Word[string] words;
	ulong spamPosts, hamPosts;
}

auto splitWords(string s)
{
	import std.algorithm.iteration;
	import std.algorithm.sorting;
	import std.array;
	import std.conv;
	import std.string;
	import std.uni;

	return s
		.map!(c => dchar(isAlpha(c) ? toLower(c) : ' '))
		.array
		.split()
		.map!(to!string)
		.array
		.sort
		.uniq;
}

void train(R)(ref BayesModel model, R words, bool isSpam, int weight = 1)
{
	foreach (word; words)
	{
		auto pWord = word in model.words;
		if (!pWord)
		{
			model.words[word] = BayesModel.Word();
			pWord = word in model.words;
		}
		if (isSpam)
			pWord.spamCount += weight;
		else
			pWord.hamCount += weight;
	}
	if (isSpam)
		model.spamPosts += weight;
	else
		model.hamPosts += weight;
}

double checkMessage(in ref BayesModel model, string s)
{
	if (model.spamPosts == 0 || model.hamPosts == 0)
		return 0.5;

	import std.math;
	debug(bayes) import std.stdio;

	// Adapted from https://github.com/rejectedsoftware/antispam/blob/master/source/antispam/filters/bayes.d
	double plsum = 0;
	auto bias = 1 / double(model.spamPosts + model.hamPosts + 1);
	foreach (w; s.splitWords)
		if (auto pWord = w in model.words)
		{
			auto p_w_s = (pWord.spamCount + bias) / model.spamPosts;
			auto p_w_h = (pWord.hamCount + bias) / model.hamPosts;
			auto p_w_t = p_w_s + p_w_h;
			if (p_w_t == 0)
				continue;
			auto prob = p_w_s / p_w_t;
			plsum += log(1 - prob) - log(prob);
			debug(bayes) writefln("%s: %s (%d/%d vs. %d/%d)", w, prob,
				pWord.spamCount, model.spamPosts,
				pWord.hamCount, model.hamPosts
			);
		}
		else
			debug(bayes) writefln("%s: unknown word", w);
	auto prob = 1 / (1 + exp(plsum));
	debug(bayes) writefln("---- final probability %s (%s)", prob, plsum);
	return prob;
}

enum probThreshold = 0.5;

/*  Copyright (C) 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Run Bayes model against dataset and print statistics and outliers.

module dfeed.progs.bayes.checkall;

import std.algorithm.iteration;
import std.file;
import std.getopt;
import std.path;
import std.stdio;

import ae.utils.json;

import dfeed.bayes;

void main(string[] args)
{
	string threshold;
	getopt(args,
		"threshold", &threshold,
	);

	auto model = "data/bayes/model.json".readText.jsonParse!BayesModel;

	uint[2][2] counts; // [isPositive][isTrue]
	uint[2][2] counts2; // [isSpam][isCorrect]

	void scanDir(string dir, bool isSpam)
	{
		foreach (de; dirEntries("data/" ~ dir, "*.txt", SpanMode.shallow))
		{
			auto prob = model.checkMessage(de.readText);
			bool rSpam = prob >= probThreshold;
			counts[rSpam][rSpam == isSpam]++;
			counts2[isSpam][rSpam == isSpam]++;

			if (dir == "ok" && !rSpam)
				continue;

			writefln("%s\t%s\t%s\t%s (%1.3f)",
				de.name,
				threshold && de.baseName > threshold ? "verify" : "train",
				isSpam ? "spam" : "ham",
				rSpam == isSpam ? rSpam ? "spam" : "ham" : rSpam ? "SPAM" : "HAM",
				prob,
			);
		}
	}

	scanDir("bayes/ok"                    , false);
	scanDir("bayes/failed"                , true );
	scanDir("bayes/redeemed"              , false);
	scanDir("bayes/deleted"               , true );
	scanDir("bayes-manual/false-positives", false);

	writeln();
	foreach (isPositive; [false, true])
	{
		auto total = sum(counts[isPositive][]);
		foreach (isTrue; [false, true])
			writefln("%s %s: %d/%d (%d%%)",
			isTrue ? "True " : "False",
			isPositive ? "Positive" : "Negative",
			counts[isPositive][isTrue],
			total,
			100 * counts[isPositive][isTrue] / total,
		);
	}

	writeln();
	foreach (isSpam; [false, true])
	{
		auto total = sum(counts2[isSpam][]);
		foreach (isCorrect; [false, true])
			writefln("%s posts classified %s: %d/%d (%d%%)",
			isSpam ? "Spam" : "Ham ",
			isCorrect ? "  correctly" : "incorrectly",
			counts2[isSpam][isCorrect],
			total,
			100 * counts2[isSpam][isCorrect] / total,
		);
	}
}

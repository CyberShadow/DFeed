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

/// Train model from dataset (prepared by prepdata).

module dfeed.progs.bayes.train;

import std.file;
import std.getopt;
import std.path;

import ae.utils.json;

import dfeed.bayes;

void main(string[] args)
{
	string threshold;
	getopt(args,
		"threshold", &threshold,
	);

	BayesModel model;

	void scanDir(string dir, bool isSpam)
	{
		foreach (de; dirEntries("data/bayes/" ~ dir, "*.txt", SpanMode.shallow))
		{
			if (threshold && de.baseName > threshold)
				continue;
			foreach (word; de.readText.splitWords)
			{
				auto pWord = word in model.words;
				if (!pWord)
				{
					model.words[word] = BayesModel.Word();
					pWord = word in model.words;
				}
				if (isSpam)
					pWord.spamCount++;
				else
					pWord.hamCount++;
			}
			if (isSpam)
				model.spamPosts++;
			else
				model.hamPosts++;
		}
	}

	scanDir("ok"         , false);
	scanDir("failed"     , true );
	scanDir("redeemed"   , false);
	scanDir("deleted"    , true );
	scanDir("manualHam"  , false);
	scanDir("manualSpam" , true );

	write("data/bayes/model.json", model.toJson);
}

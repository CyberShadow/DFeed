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

/// Check one .txt file from the dataset.
/// Build with -debug=bayes for best results.

module dfeed.progs.bayes.checkdatum;

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

	writeln(model.checkMessage(args[1].readText));
}

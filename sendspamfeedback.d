/*  Copyright (C) 2014  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module sendspamfeedback;

import std.file;
import std.stdio;
import std.string;

import ae.net.asockets;

import posting;
import spam;

void main(string[] args)
{
	files:
	foreach (fn; args[1..$])
	{
		if (fn.length == 20)
			fn = dirEntries("logs", "* - PostProcess-" ~ fn ~ ".log", SpanMode.shallow).front.name;

		writeln("--------------------------------------------------------------------");
		auto pp = new PostProcess(fn);
		write(pp.post.message);
		writeln();
		writeln("--------------------------------------------------------------------");

		SpamFeedback feedback = SpamFeedback.unknown;
		while (feedback == SpamFeedback.unknown)
		{
			write("Is this message spam or ham? ");
			switch (readln().chomp())
			{
				case "spam": feedback = SpamFeedback.spam; break;
				case "ham":  feedback = SpamFeedback.ham;  break;
				case "skip": continue files;
				default: break;
			}
		}
		void handler(bool ok, string message) { writeln(ok ? "OK!" : "Error: " ~ message); }
		foreach (sender; spamFeedbackSenders)
			sender(pp, &handler, feedback);
		socketManager.loop();
	}
}

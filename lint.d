/*  Copyright (C) 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module lint;

import std.algorithm;
import std.range;
import std.string;

import posting;
import web;

class LintRule
{
	/// ID string - used in forms for button names, etc.
	abstract @property string id();

	/// Short description - visible by default
	abstract @property string shortDescription();

	/// Long description - shown on request, should contain rationale
	abstract @property string longDescription();

	/// Check if the lint rule is triggered.
	abstract bool check(PostDraft);

	/// Fix up the post according to the rule.
	abstract void fix(ref PostDraft);
}

class NotQuotingRule : LintRule
{
	override @property string id() { return "notquoting"; }
	override @property string shortDescription() { return "Parent post is not quoted."; }
	override @property string longDescription() { return 
		"<p>When replying to someone's post, you should provide some context for your replies by quoting the revelant parts of their post.</p>" ~
		"<p>Depending on the software (or its configuration) used to read your message, it may not be obvious to which post you're replying.</p>" ~
		"<p>Thus, when writing a reply, don't delete all quoted text: instead, leave just enough to provide context for your reply. " ~
		   "You can also insert your replies inline (interleaved with quoted text) to address specific parts of the parent post.</p>";
	}

	override bool check(PostDraft draft)
	{
		if ("parent" !in draft.serverVars)
			return false;
		auto lines = draft.clientVars.get("text", null).splitLines();
		return !lines.canFind!(line => line.startsWith(">"));
	}

	override void fix(ref PostDraft draft)
	{
		auto text = web.getPost(draft.serverVars["parent"]).replyTemplate().content.strip();
		draft.clientVars["text"] = text ~ "\n\n" ~ draft.clientVars.get("text", null);
	}
}

class OverquotingRule : LintRule
{
	override @property string id() { return "overquoting"; }
	override @property string shortDescription() { return "You are overquoting."; }
	override @property string longDescription() { return 
		"<p>The ratio between quoted and added text is vastly disproportional.</p>" ~
		"<p>Quoting should be limited to the amount necessary to provide context for your replies. " ~
		   "Quoting posts in their entirety is thus rarely necessary, and is a waste of vertical space.</p>" ~
		"<p>Please trim the quoted text to just the relevant parts you're addressing in your reply, or add more content to your post.</p>";
	}

	bool checkLines(string[] lines)
	{
		auto quoted   = lines.filter!(line =>  line.startsWith(">")).map!(line => line.length).sum();
		auto unquoted = lines.filter!(line => !line.startsWith(">")).map!(line => line.length).sum();
		return unquoted && quoted > unquoted * 4;
	}

	override bool check(PostDraft draft)
	{
		auto lines = draft.clientVars.get("text", null).splitLines();
		return checkLines(lines);
	}

	override void fix(ref PostDraft draft)
	{
		auto lines = draft.clientVars.get("text", null).splitLines();

		static string quotePrefix(string s)
		{
			int i;
			for (; i<s.length; i++)
				if (s[i] == '>' || (s[i] == ' ' && i != 0))
					continue;
				else
					break;
			return s[0..i];
		}

		static size_t quoteLevel(string quotePrefix)
		{
			return quotePrefix.count(">");
		}

		bool check()
		{
			draft.clientVars["text"] = lines.join("\n");
			return !checkLines(lines);
		}

		// First, try to trim inner posting levels
		void trimBeyond(int trimLevel)
		{
			size_t lastLevel = 0;
			foreach_reverse (i, s; lines)
			{
				auto prefix = quotePrefix(s);
				auto level = prefix.count(">");
				if (level >= trimLevel)
				{
					if (level != lastLevel)
						lines[i] = prefix ~ "[...]";
					else
						lines = lines[0..i] ~ lines[i+1..$];
				}
				lastLevel = level;
			}
		}

		foreach_reverse (trimLevel; 2..6)
		{
			trimBeyond(trimLevel);
			if (check())
				return;
		}

		// Next, try to trim to just the first quoted paragraph
		string[] newLines;
		bool sawContent, trimming;
		foreach (line; lines)
		{
			if (line.startsWith(">"))
			{
				if (line.strip() == ">")
				{
					if (!trimming && sawContent)
					{
						newLines ~= ">";
						newLines ~= "> [...]";
						trimming = true;
						sawContent = false;
					}
				}
				else
				if (!line.endsWith(" wrote:")
				 && !line.endsWith("[...]"))
					sawContent = true;
			}
			else
				trimming = false;
			if (!trimming)
				newLines ~= line;
		}
		lines = newLines;
		if (check())
			return;

		// Lastly, just trim all quoted text
		trimBeyond(1);
		check();
	}
}

LintRule[] lintRules;

static this()
{
	lintRules = [
		new NotQuotingRule,
		new OverquotingRule,
	];
}

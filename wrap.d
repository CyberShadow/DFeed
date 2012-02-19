/*  Copyright (C) 2011, 2012  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// RFC 2646. May be upgraded to RFC 3676 for international text.
module wrap;

import std.string;
import ae.utils.text;

struct Paragraph
{
	string quotePrefix, text;
}

Paragraph[] unwrapText(string text, bool flowed, bool delsp)
{
	auto lines = splitAsciiLines(text);

	Paragraph[] paragraphs;

	foreach (line; lines)
	{
		string quotePrefix;
		while (line.startsWith(">"))
		{
			int l = 1;
			// This is against standard, but many clients
			// (incl. Web-News and M$ Outlook) don't give a damn:
			if (line.startsWith("> "))
				l = 2;

			quotePrefix ~= line[0..l];
			line = line[l..$];
		}

		// Remove space-stuffing
		if (flowed && line.startsWith(" "))
			line = line[1..$];

		if (paragraphs.length>0
		 && paragraphs[$-1].quotePrefix==quotePrefix
		 && paragraphs[$-1].text.endsWith(" ")
		 && !line.startsWith(" ")
		 && line.length
		 && line != "-- "
		 && paragraphs[$-1].text != "-- "
		 && (flowed || quotePrefix.length))
		{
			if (delsp)
				paragraphs[$-1].text = paragraphs[$-1].text[0..$-1];
			paragraphs[$-1].text ~= line;
		}
		else
			paragraphs ~= Paragraph(quotePrefix, line);
	}

	return paragraphs;
}

string wrapText(Paragraph[] paragraphs, int margin = 66)
{
	string[] lines;

	void addLine(string quotePrefix, string line)
	{
		line = quotePrefix ~ line;
		// Add space-stuffing
		if (line.startsWith(" ") ||
			line.startsWith("From ") ||
			(line.startsWith(">") && quotePrefix.length==0))
		{
			line = " " ~ line;
		}
		lines ~= line;
	}

	foreach (paragraph; paragraphs)
	{
		string line = paragraph.text;
		auto cutPoint = margin - paragraph.quotePrefix.length;

		while (line.length && line[$-1] == ' ')
			line = line[0..$-1];

		if (!line.length)
		{
			addLine(paragraph.quotePrefix, null);
			continue;
		}

		while (line.length > cutPoint)
		{
			auto i = line[0..cutPoint].lastIndexOf(' ');
			if (i < 0)
			{
				i = cutPoint + line[cutPoint..$].indexOf(' ');
				if (i < cutPoint)
					break;
			}

			i++;
			addLine(paragraph.quotePrefix, line[0..i]);
			line = line[i..$];
		}

		if (line.length)
			addLine(paragraph.quotePrefix, line);
	}

	return lines.join("\n");
}

unittest
{
	// Space-stuffing
	assert(wrapText(unwrapText(" Hello", false, false)) == "  Hello");

	// Don't rewrap user input
	assert(wrapText(unwrapText("Line 1 \nLine 2 ", false, false)) == "Line 1\nLine 2");
	// ...but rewrap quoted text
	assert(wrapText(unwrapText("> Line 1 \n> Line 2 ", false, false)) == "> Line 1 Line 2");
	// Wrap long lines
	assert(wrapText(unwrapText(std.array.replicate("abcde ", 20), false, false)).split("\n").length > 1);
}

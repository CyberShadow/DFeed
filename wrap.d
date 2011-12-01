/// RFC 2646. May be upgraded to RFC 3676 for international text.
module wrap;

import std.string;
import ae.utils.text;

struct Paragraph
{
	string quotePrefix, text;
}

Paragraph[] unwrapText(string text, bool delsp)
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

		if (paragraphs.length>0 && paragraphs[$-1].quotePrefix==quotePrefix && paragraphs[$-1].text.endsWith(" ") && !line.startsWith(" "))
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

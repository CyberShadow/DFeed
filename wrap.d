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

		if (paragraphs.length>0
		 && paragraphs[$-1].quotePrefix==quotePrefix
		 && paragraphs[$-1].text.endsWith(" ")
		 && !line.startsWith(" ")
		 && line != "-- "
		 && paragraphs[$-1].text != "-- ")
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

	foreach (paragraph; paragraphs)
	{
		string line = paragraph.text;
		auto cutPoint = margin - paragraph.quotePrefix.length;

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
			lines ~= paragraph.quotePrefix ~ line[0..i];
			line = line[i..$];
		}


		if (line.length)
			lines ~= paragraph.quotePrefix ~ line;
	}

	return lines.join("\n");
}

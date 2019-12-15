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

/// Formatting post bodies.
module dfeed.web.web.part.postbody;

import std.algorithm.comparison : max;
import std.algorithm.iteration : splitter, map, reduce;
import std.range : iota, radial;
import std.regex : Regex, regex, matchAll;

import ae.net.ietf.message : Rfc850Message;
import ae.net.ietf.wrap : unwrapText;
import ae.utils.meta : I;
import ae.utils.text : contains, segmentByWhitespace;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.web.web.page : html;

static Regex!char reUrl;
static this() { reUrl = regex(`\w+://[^<>\s]+[\w/\-=]`); }

void formatBody(Rfc850Message post)
{
	auto paragraphs = unwrapText(post.content, post.wrapFormat);
	bool inSignature = false;
	int quoteLevel = 0;
	foreach (paragraph; paragraphs)
	{
		int paragraphQuoteLevel;
		foreach (c; paragraph.quotePrefix)
			if (c == '>')
				paragraphQuoteLevel++;

		for (; quoteLevel > paragraphQuoteLevel; quoteLevel--)
			html ~= `</span>`;
		for (; quoteLevel < paragraphQuoteLevel; quoteLevel++)
			html ~= `<span class="forum-quote">`;

		if (!quoteLevel && (paragraph.text == "-- " || paragraph.text == "_______________________________________________"))
		{
			html ~= `<span class="forum-signature">`;
			inSignature = true;
		}

		enum forceWrapThreshold = 30;
		enum forceWrapMinChunkSize =  5;
		enum forceWrapMaxChunkSize = 15;
		static assert(forceWrapMaxChunkSize > forceWrapMinChunkSize * 2);

		import std.utf : byChar;
		bool needsWrap = paragraph.text.byChar.splitter(' ').map!(s => s.length).I!(r => reduce!max(size_t.init, r)) > forceWrapThreshold;

		auto hasURL = paragraph.text.contains("://");

		void processText(string s)
		{
			html.put(encodeHtmlEntities(s));
		}

		void processWrap(string s)
		{
			alias next = processText;

			if (!needsWrap)
				return next(s);

			auto segments = s.segmentByWhitespace();
			foreach (ref segment; segments)
			{
				if (segment.length > forceWrapThreshold)
				{
					void chunkify(string s, string delimiters)
					{
						if (s.length < forceWrapMaxChunkSize)
						{
							html.put(`<span class="forcewrap">`);
							next(s);
							html.put(`</span>`);
						}
						else
						if (!delimiters.length)
						{
							// Don't cut UTF-8 sequences in half
							static bool canCutAt(char c) { return (c & 0x80) == 0 || (c & 0x40) != 0; }
							foreach (i; s.length.iota.radial)
								if (canCutAt(s[i]))
								{
									chunkify(s[0..i], null);
									chunkify(s[i..$], null);
									return;
								}
							chunkify(s[0..$/2], null);
							chunkify(s[$/2..$], null);
						}
						else
						{
							foreach (i; iota(forceWrapMinChunkSize, s.length-forceWrapMinChunkSize).radial)
								if (s[i] == delimiters[0])
								{
									chunkify(s[0..i+1], delimiters);
									chunkify(s[i+1..$], delimiters);
									return;
								}
							chunkify(s, delimiters[1..$]);
						}
					}

					chunkify(segment, "/&=.-+,;:_\\|`'\"~!@#$%^*()[]{}");
				}
				else
					next(segment);
			}
		}

		void processURLs(string s)
		{
			alias next = processWrap;

			if (!hasURL)
				return next(s);

			size_t pos = 0;
			foreach (m; matchAll(s, reUrl))
			{
				next(s[pos..m.pre().length]);
				html.put(`<a rel="nofollow" href="`, m.hit(), `">`);
				next(m.hit());
				html.put(`</a>`);
				pos = m.pre().length + m.hit().length;
			}
			next(s[pos..$]);
		}

		if (paragraph.quotePrefix.length)
			html.put(`<span class="forum-quote-prefix">`), html.putEncodedEntities(paragraph.quotePrefix), html.put(`</span>`);
		processURLs(paragraph.text);
		html.put('\n');
	}
	for (; quoteLevel; quoteLevel--)
		html ~= `</span>`;
	if (inSignature)
		html ~= `</span>`;
}

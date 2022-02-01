/*  Copyright (C) 2021, 2022  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Markdown rendering using cmark.

module dfeed.web.markdown;

import std.array;
import std.concurrency : initOnce;
import std.exception;
import std.functional : memoize;
import std.process;
import std.utf : validate;

import ae.sys.file : readFile;
import ae.utils.path;

/// Do we have the ability to render Markdown on this system?
bool haveMarkdown()
{
	__gshared bool result;
	return initOnce!result(haveExecutable("cmark-gfm"));
}

/// Render this text as Markdown to HTML now.
string renderMarkdown(string s)
{
	// Pre-process the string
	s = s
		.replace("\n-- \n", "\n\n-- \n") // Disambiguate signatures (from setext headings)
	;

	auto p = pipeProcess([
			"timeout", "1",
			"cmark-gfm",
			"--hardbreaks", // paragraphs are unwrapped in formatBody
			"--extension", "table",
			"--extension", "strikethrough", "--strikethrough-double-tilde",
			"--extension", "autolink",
		], Redirect.stdin | Redirect.stdout);
	// cmark reads all input before emitting any output, so it's safe
	// for us to write all input while not reading anything.
	p.stdin.rawWrite(s);
	p.stdin.close();
	auto result = cast(string)readFile(p.stdout);
	p.stdout.close();
	auto status = wait(p.pid);
	enforce(status != 124, "Time-out");
	enforce(status == 0, "cmark failed");
	validate(result);

	// Post-process the results
	result = result
		.replace("<blockquote>\n", `<span class="forum-quote"><span class="forum-quote-prefix">&gt; </span>`)
		.replace("\n</blockquote>", `</span>`)
		.replace("</blockquote>", `</span>`)
		.replace(`<a href="`, `<a rel="nofollow" href="`)
	;

	return result;
}

/// Result of a cached attempt to render some Markdown.
struct MarkdownResult
{
	string html, error;
}

/// Try to render some Markdown and return a struct indicating success / failure.
/*private*/ MarkdownResult tryRenderMarkdown(string markdown)
{
	try
		return MarkdownResult(renderMarkdown(markdown), null);
	catch (Exception e)
		return MarkdownResult(null, e.msg);
}

/// Try to render some Markdown, and cache the results.
alias renderMarkdownCached = memoize!(tryRenderMarkdown, 1024);

/*  Copyright (C) 2011, 2012, 2013  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module rfc850;

import std.string;
import std.conv;
import std.array;
import std.uri;
import std.base64;
import std.datetime;
import std.exception;
import std.algorithm : min;
debug import std.stdio;

import ae.net.http.client;
import ae.net.ietf.headers;
import ae.utils.array;
import ae.utils.time;
import ae.utils.text;
import ae.utils.mime;

import common;
import bitly;
import database;
import wrap;

struct Xref
{
	string group;
	int num;
}

class Rfc850Post : Post
{
	string message, id;
	Xref[] xref;

	string subject, realSubject, author, authorEmail, url, shortURL;
	string[] references;
	bool reply;

	/// Result of threadify()
	Rfc850Post[] children;

	/// Internal database index
	int rowid;

	Headers headers;
	string content; /// text/plain only
	ubyte[] data; /// can be anything
	string error; /// Explanation for null content
	bool flowed, delsp;

	/// Multipart stuff
	string name, fileName, description, mimeType;
	Rfc850Post[] parts;

	this(string _message, string _id=null, int _rowid=0)
	{
		message = _message;
		id    = _id;
		rowid = _rowid;
		debug scope(failure) writeln("Failure while parsing message: ", _id);

		// TODO: actually read RFC 850
		// TODO: this breaks binary encodings, FIXME?
		auto text = message.fastReplace("\r\n", "\n");
		auto headerEnd = text.indexOf("\n\n");
		if (headerEnd < 0) headerEnd = text.length;
		auto header = text[0..headerEnd];
		header = header.fastReplace("\n\t", " ").fastReplace("\n ", " ");

		foreach (s; header.fastSplit('\n'))
		{
			if (s == "") break;

			auto p = s.indexOf(": ");
			if (p<0) continue;
			//assert(p>0, "Bad header line: " ~ s);
			headers[s[0..p]] = s[p+2..$];
		}

		string defaultEncoding = "windows1252";
		if (headers.get("User-Agent", null) == "DFeed")
			defaultEncoding = "utf8"; // Hack...

		foreach (string key, ref string value; headers)
			if (hasIntlCharacters(value))
				value = decodeEncodedText(value, defaultEncoding);

		string rawContent = text[min(headerEnd+2, $)..$]; // not UTF-8

		if ("Content-Transfer-Encoding" in headers)
			try
				rawContent = decodeTransferEncoding(rawContent, headers["Content-Transfer-Encoding"]);
			catch (Exception e)
			{
				rawContent = null;
				error = "Error decoding " ~ headers["Content-Transfer-Encoding"] ~ " message: " ~ e.msg;
			}

		data = cast(ubyte[])rawContent;

		TokenHeader contentType, contentDisposition;
		if ("Content-Type" in headers)
			contentType = decodeTokenHeader(headers["Content-Type"]);
		if ("Content-Disposition" in headers)
			contentDisposition = decodeTokenHeader(headers["Content-Disposition"]);
		mimeType = toLower(contentType.value);
		flowed = contentType.properties.get("format", "fixed") == "flowed";
		delsp = contentType.properties.get("delsp", "no") == "yes";

		if (rawContent)
		{
			if (!mimeType || mimeType == "text/plain")
			{
				if ("charset" in contentType.properties)
					content = decodeEncodedText(rawContent, contentType.properties["charset"]);
				else
					content = decodeEncodedText(rawContent, defaultEncoding);
			}
			else
			if (mimeType.startsWith("multipart/") && "boundary" in contentType.properties)
			{
				string boundary = contentType.properties["boundary"];
				auto end = rawContent.indexOf("--" ~ boundary ~ "--");
				if (end < 0)
					end = rawContent.length;
				rawContent = rawContent[0..end];

				auto rawParts = rawContent.split("--" ~ boundary ~ "\n");
				foreach (rawPart; rawParts[1..$])
				{
					auto part = new Rfc850Post(rawPart);
					if (part.content && !content)
						content = part.content;
					parts ~= part;
				}

				if (!content)
				{
					if (rawParts.length && rawParts[0].asciiStrip().length)
						content = rawParts[0]; // default content to multipart stub
					else
						error = "Couldn't find text part in this " ~ mimeType ~ " message";
				}
			}
			else
				error = "Don't know how parse " ~ mimeType ~ " message";
		}

		enum PGP_START = "-----BEGIN PGP SIGNED MESSAGE-----\n";
		enum PGP_DELIM = "\n-----BEGIN PGP SIGNATURE-----\n";
		enum PGP_END   = "\n-----END PGP SIGNATURE-----";
		if (content.startsWith(PGP_START) && content.contains(PGP_DELIM) && content.asciiStrip().endsWith(PGP_END))
		{
			// Don't attempt to create meaningful signature files... just get the clutter out of the way
			content = content.asciiStrip();
			auto p = content.indexOf(PGP_DELIM);
			auto part = new Rfc850Post(content[p+PGP_DELIM.length..$-PGP_END.length]);
			content = content[PGP_START.length..p];
			p = content.indexOf("\n\n");
			if (p >= 0)
				content = content[p+2..$];
			part.fileName = "pgp.sig";
			parts ~= part;
		}

		if (content.contains("\nbegin "))
		{
			import std.regex;
			auto r = regex(`^begin [0-7]+ \S+$`);
			auto lines = content.split("\n");
			size_t start;
			bool started;
			string fn;

			for (size_t i=0; i<lines.length; i++)
				if (!started && !match(lines[i], r).empty)
				{
					start = i;
					fn = lines[i].split(" ")[2];
					started = true;
				}
				else
				if (started && lines[i] == "end" && lines[i-1]=="`")
				{
					started = false;
					try
					{
						auto data = uudecode(lines[start+1..i]);

						auto part = new Rfc850Post();
						part.fileName = fn;
						part.mimeType = guessMime(fn);
						part.data = data;
						parts ~= part;

						lines = lines[0..start] ~ lines[i+1..$];
						i = start-1;
					}
					catch (Exception e)
						debug writeln(e);
				}

			content = lines.join("\n");
		}

		name = contentType.properties.get("name", string.init);
		fileName = contentDisposition.properties.get("filename", string.init);
		description = headers.get("Content-Description", string.init);
		if (name == fileName)
			name = null;

		if ("References" in headers)
		{
			reply = true;
			auto refs = asciiStrip(headers["References"]);
			while (refs.startsWith("<"))
			{
				auto p = refs.indexOf(">");
				if (p < 0)
					break;
				references ~= refs[0..p+1];
				refs = asciiStrip(refs[p+1..$]);
			}
		}

		subject = realSubject = "Subject" in headers ? decodeRfc1522(headers["Subject"]) : null;
		if (subject.startsWith("Re: "))
		{
			subject = subject[4..$];
			reply = true;
		}

		int bugzillaCommentNumber;
		author = authorEmail = "From" in headers ? decodeRfc1522(headers["From"]) : null;
		if ("X-Bugzilla-Who" in headers)
		{
			author = authorEmail = headers["X-Bugzilla-Who"];

			foreach (line; content.split("\n"))
				if (line.endsWith("> changed:"))
					author = line[0..line.indexOf(" <")];
				else
				if (line.startsWith("--- Comment #") && line.indexOf(" from ")>0 && line.indexOf(" <")>0 && line.endsWith(" ---"))
				{
					author = line[line.indexOf(" from ")+6 .. line.indexOf(" <")];
					bugzillaCommentNumber = to!int(line["--- Comment #".length .. line.indexOf(" from ")]);
				}
		}
		else
		if (author.indexOf('@') < 0 && author.indexOf(" at ") >= 0)
		{
			// Mailing list archive format
			assert(author == authorEmail);
			if (author.indexOf(" (") > 0 && author.endsWith(")"))
			{
				authorEmail = author[0 .. author.lastIndexOf(" (")].replace(" at ", "@");
				author      = author[author.lastIndexOf(" (")+2 .. $-1].decodeRfc1522();
			}
			else
			{
				authorEmail = author.replace(" at ", "@");
				author = author[0 .. author.lastIndexOf(" at ")];
			}
		}
		if (author.indexOf('<')>=0 && author.endsWith('>'))
		{
			auto p = author.indexOf('<');
			authorEmail = author[p+1..$-1];
			author = decodeRfc1522(asciiStrip(author[0..p]));
		}
		if (author.length>2 && author[0]=='"' && author[$-1]=='"')
			author = decodeRfc1522(asciiStrip(author[1..$-1]));
		//if (author == authorEmail && author.indexOf("@") > 0)
		//	author = author[0..author.indexOf("@")];

		//where = "Newsgroups" in headers ? headers["Newsgroups"] : null;
		if ("Xref" in headers)
		{
			auto xrefStrings = split(headers["Xref"], " ")[1..$];
			foreach (str; xrefStrings)
			{
				auto segs = str.split(":");
				xref ~= Xref(segs[0], to!int(segs[1]));
			}
		}

		if ("List-ID" in headers && subject.startsWith("[") && !xref.length)
		{
			auto p = subject.indexOf("] ");
			xref = [Xref(subject[1..p])];
			subject = subject[p+2..$];
		}

		if ("Message-ID" in headers && !id)
			id = headers["Message-ID"];

		if (subject.startsWith("[Issue "))
		{
			auto urlBase = headers.get("X-Bugzilla-URL", "http://d.puremagic.com/issues/");
			url = urlBase ~ "show_bug.cgi?id=" ~ subject.split(" ")[1][0..$-1];
			if (bugzillaCommentNumber > 0)
				url ~= "#c" ~ .text(bugzillaCommentNumber);
		}
		else
		if (id.length)
			url = format("http://%s/post/%s", std.file.readText("data/web.txt").splitLines()[1], encodeComponent(id[1..$-1]));
/+		else
		if (xref.length)
		{
			auto group = xref[0].group;
			auto num = xref[0].num;
			//url = format("http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=%s", encodeUrlParameter(group), num);
			//url = format("http://digitalmars.com/webnews/newsgroups.php?art_group=%s&article_id=%s", encodeComponent(group), num);
		}
		else
		if ("LIST-ID" in headers && id)
		{
			if (id.startsWith("<") && id.endsWith(">"))
				url = "http://mid.gmane.org/" ~ id[1..$-1];
		}
+/

		//if ("MESSAGE-ID" in headers)
		//	url = "news://news.digitalmars.com/" ~ headers["MESSAGE-ID"][1..$-1];

		if ("NNTP-Posting-Date" in headers)
			time = parseTime("D, j M Y H:i:s O", headers["NNTP-Posting-Date"]);
		else
		if ("Date" in headers)
		{
			auto str = headers["Date"];
			try
				time = parseTime(TimeFormats.RFC850, str);
			catch (Exception e)
			try
				time = parseTime(`D, j M Y H:i:s O`, str);
			catch (Exception e)
			try
				time = parseTime(`D, j M Y H:i:s e`, str);
			catch (Exception e)
			try
				time = parseTime(`D, j M Y H:i O`, str);
			catch (Exception e)
			try
				time = parseTime(`D, j M Y H:i e`, str);
			catch (Exception e)
			{ /* fall-back to default (class creation time) */ }
		}
	}

	private this() {} // for attachments and templates

	static Rfc850Post newPostTemplate(string groups)
	{
		auto post = new Rfc850Post();
		foreach (group; groups.split(","))
			post.xref ~= Xref(group);
		return post;
	}

	Rfc850Post replyTemplate()
	{
		auto post = new Rfc850Post();
		post.reply = true;
		post.xref = this.xref;
		post.references = this.references ~ this.id;
		post.subject = this.realSubject;
		if (!post.subject.startsWith("Re:"))
			post.subject = "Re: " ~ post.subject;

		auto paragraphs = unwrapText(this.content, this.flowed, this.delsp);
		foreach (i, ref paragraph; paragraphs)
			if (paragraph.quotePrefix.length)
				paragraph.quotePrefix = ">" ~ paragraph.quotePrefix;
			else
			{
				if (paragraph.text == "-- ")
				{
					paragraphs = paragraphs[0..i];
					break;
				}
				paragraph.quotePrefix = paragraph.text.length ? "> " : ">";
			}
		while (paragraphs.length && paragraphs[$-1].text.length==0)
			paragraphs = paragraphs[0..$-1];

		auto replyTime = time;
		replyTime.timezone = UTC();
		post.content =
			"On " ~ formatTime(`l, j F Y \a\t H:i:s e`, replyTime) ~ ", " ~ this.author ~ " wrote:\n" ~
			wrapText(paragraphs) ~
			"\n\n";
		post.flowed = true;
		post.delsp = false;

		return post;
	}

	// Rewrap
	void setText(string text)
	{
		this.content = wrapText(unwrapText(text, false, false));
		this.flowed = true;
		this.delsp = false;
	}

	/// Set headers and message.
	void compile()
	{
		assert(id);

		headers["Message-ID"] = id;
		headers["From"] = format(`"%s" <%s>`, author, authorEmail);
		headers["Subject"] = subject;
		headers["Newsgroups"] = where;
		headers["Content-Type"] = format("text/plain; charset=utf-8; format=%s; delsp=%s", flowed ? "flowed" : "fixed", delsp ? "yes" : "no");
		headers["Content-Transfer-Encoding"] = "8bit";
		if (references.length)
		{
			headers["References"] = references.join(" ");
			headers["In-Reply-To"] = references[$-1];
		}
		headers["Date"] = formatTime(TimeFormats.RFC2822, time);
		headers["User-Agent"] = "DFeed";

		string[] lines;
		foreach (name, value; headers)
		{
			if (value.hasIntlCharacters())
				value = value.encodeRfc1522();
			auto line = name ~ ": " ~ value;
			auto lineStart = name.length + 2;

			foreach (c; line)
				enforce(c >= 32, "Control characters in headers? I call shenanigans");

			while (line.length >= 80)
			{
				auto p = line[0..80].lastIndexOf(' ');
				if (p < lineStart)
				{
					p = 80 + line[80..$].indexOf(' ');
					if (p < 80)
						break;
				}
				lines ~= line[0..p];
				line = line[p..$];
				lineStart = 1;
			}
			lines ~= line;
		}

		message =
			lines.join("\r\n") ~
			"\r\n\r\n" ~
			splitAsciiLines(content).join("\r\n");
	}

	override void formatForIRC(void delegate(string) handler)
	{
		if (url && !shortURL)
			return shortenURL(url, (string shortenedURL) {
				shortURL = shortenedURL;
				formatForIRC(handler);
			});

		handler(format("%s%s %s %s%s",
			where is null ? null : "[" ~ where.replace("digitalmars.", "dm.") ~ "] ",
			author == "" ? "<no name>" : author,
			reply ? "replied to" : "posted",
			subject == "" ? "<no subject>" : `"` ~ subject ~ `"`,
			shortURL ? ": " ~ shortURL : ""
		));
	}

	override bool isImportant()
	{
		// GitHub notifications are already grabbed from RSS
		if (authorEmail == "noreply@github.com")
			return false;

		if (where == "")
			return false;

		if (where.isIn(ANNOUNCE_REPLIES))
			return true;

		return !reply || author.isIn(VIPs);
	}

	@property string where()
	{
		string[] groups;
		foreach (x; xref)
			groups ~= x.group;
		return groups.join(",");
	}

	@property string parentID()
	{
		return references.length ? references[$-1] : null;
	}

	@property string threadID()
	{
		return references.length ? references[0] : id;
	}

	/// Arrange a bunch of posts in a thread hierarchy. Returns the root posts.
	static Rfc850Post[] threadify(Rfc850Post[] posts)
	{
		Rfc850Post[string] postLookup;
		foreach (post; posts)
		{
			post.children = null;
			postLookup[post.id] = post;
		}

		Rfc850Post[] roots;
		postLoop:
		foreach (post; posts)
		{
			foreach_reverse(reference; post.references)
			{
				auto pparent = reference in postLookup;
				if (pparent)
				{
					(*pparent).children ~= post;
					continue postLoop;
				}
			}
			roots ~= post;
		}
		return roots;
	}

private:
	string[] ANNOUNCE_REPLIES = ["digitalmars.D.bugs"];
	string[] VIPs = ["Walter Bright", "Andrei Alexandrescu", "Sean Kelly", "Don", "dsimcha"];
}

unittest
{
	auto post = new Rfc850Post("From: msonke at example.org (=?ISO-8859-1?Q?S=F6nke_Martin?=)\n\nText");
	assert(post.author == "Sönke Martin");
	assert(post.authorEmail == "msonke@example.org");

	post = new Rfc850Post("Date: Tue, 06 Sep 2011 14:52 -0700\n\nText");
	assert(post.time.year == 2011);
}

private:

string decodeRfc1522(string str)
{
	auto words = str.split(" ");
	bool[] encoded = new bool[words.length];

	foreach (wordIndex, ref word; words)
		if (word.length > 6 && word.startsWith("=?") && word.endsWith("?="))
		{
			auto parts = split(word[2..$-2], "?");
			if (parts.length != 3)
				continue;
			auto charset = parts[0];
			auto encoding = parts[1];
			auto text = parts[2];

			switch (toUpper(encoding))
			{
			case "Q":
				text = decodeQuotedPrintable(text, true);
				break;
			case "B":
				text = cast(string)Base64.decode(text);
				break;
			default:
				continue /*foreach*/;
			}

			word = decodeEncodedText(text, charset);
			encoded[wordIndex] = true;
		}

	string result;
	foreach (wordIndex, word; words)
	{
		if (wordIndex > 0 && !(encoded[wordIndex-1] && encoded[wordIndex]))
			result ~= ' ';
		result ~= word;
	}

	try
	{
		import std.utf;
		validate(result);
	}
	catch
	{
		import ae.utils.iconv;
		result = toUtf8(cast(immutable(ubyte[]))result, "ISO-8859-1", true);
	}

	return result;
}

string encodeRfc1522(string str)
{
	if (!str.hasIntlCharacters())
		return str;

	string[] words;
	bool wasIntl = false;
	foreach (word; str.split(" "))
	{
		bool isIntl = word.hasIntlCharacters();
		if (wasIntl && isIntl)
			words[$-1] ~= " " ~ word;
		else
			words ~= word;
		wasIntl = isIntl;
	}

	enum CHUNK_LENGTH_THRESHOLD = 20;

	foreach (ref word; words)
	{
		if (!word.hasIntlCharacters())
			continue;
		string[] output;
		string s = word;
		while (s.length)
		{
			size_t ptr = 0;
			while (ptr < s.length && ptr < CHUNK_LENGTH_THRESHOLD)
				ptr += stride(s, ptr);
			output ~= encodeRfc1522Chunk(s[0..ptr]);
			s = s[ptr..$];
		}
		word = output.join(" ");
	}
	return words.join(" ");
}

string encodeRfc1522Chunk(string str)
{
	auto result = "=?UTF-8?B?" ~ Base64.encode(cast(ubyte[])str) ~ "?=";
	return assumeUnique(result);
}

unittest
{
	auto text = "В лесу родилась ёлочка";
	assert(decodeRfc1522(encodeRfc1522(text)) == text);

	// Make sure email address isn't mangled
	assert(encodeRfc1522("Sönke Martin <msonke@example.org>").endsWith(" <msonke@example.org>"));
}

string decodeQuotedPrintable(string s, bool inHeaders)
{
	auto r = appender!string();
	for (int i=0; i<s.length; )
		if (s[i]=='=')
		{
			if (i+1 >= s.length || s[i+1] == '\n')
				i+=2; // escape newline
			else
				r.put(cast(char)parse!ubyte(s[i+1..i+3], 16)), i+=3;
		}
		else
		if (s[i]=='_' && inHeaders)
			r.put(' '), i++;
		else
			r.put(s[i++]);
	return r.data;
}

bool hasIntlCharacters(string s)
{
	foreach (char c; s)
		if (c >= 0x80)
			return true;
	return false;
}

// http://d.puremagic.com/issues/show_bug.cgi?id=7016
static import ae.sys.cmd, ae.utils.iconv;

string decodeEncodedText(string s, string textEncoding)
{
	try
	{
		import ae.utils.iconv;
		return toUtf8(cast(immutable(ubyte)[])s, textEncoding, false);
	}
	catch (Exception e)
	{
		debug std.stdio.writefln("iconv fallback for %s (%s)", textEncoding, e.msg);
		try
		{
			import ae.sys.cmd;
			return iconv(s, textEncoding);
		}
		catch (Exception e)
		{
			debug std.stdio.writefln("ISO-8859-1 fallback (%s)", e.msg);
			import ae.utils.iconv;
			return toUtf8(cast(immutable(ubyte)[])s, "ISO-8859-1", false);
		}
	}
}

struct TokenHeader
{
	string value;
	string[string] properties;
}

TokenHeader decodeTokenHeader(string s)
{
	string take(char until)
	{
		string result;
		auto p = s.indexOf(until);
		if (p < 0)
			result = s,
			s = null;
		else
			result = s[0..p],
			s = asciiStrip(s[p+1..$]);
		return result;
	}

	TokenHeader result;
	result.value = take(';');

	while (s.length)
	{
		string name = take('=');
		string value;
		if (s.length && s[0] == '"')
		{
			s = s[1..$];
			value = take('"');
			take(';');
		}
		else
			value = take(';');
		result.properties[name] = value;
	}

	return result;
}

string decodeTransferEncoding(string data, string encoding)
{
	switch (toLower(encoding))
	{
	case "7bit":
		return data;
	case "quoted-printable":
		return decodeQuotedPrintable(data, false);
	case "base64":
		//return cast(string)Base64.decode(data.replace("\n", ""));
	{
		auto s = data.fastReplace("\n", "");
		scope(failure) std.stdio.writeln(s);
		return cast(string)Base64.decode(s);
	}
	default:
		return data;
	}
}

ubyte[] uudecode(string[] lines)
{
	// TODO: optimize
	//auto data = appender!(ubyte[]);  // OPTLINK says no
	ubyte[] data;
	foreach (line; lines)
	{
		if (!line.length || line.startsWith("`"))
			continue;
		ubyte len = to!ubyte(line[0] - 32);
		line = line[1..$];
		while (line.length % 4)
			line ~= 32;
		ubyte[] lineData;
		while (line.length)
		{
			uint v = 0;
			foreach (c; line[0..4])
				if (c == '`') // same as space
					v <<= 6;
				else
				{
					enforce(c >= 32 && c < 96, [c]);
					v = (v<<6) | (c - 32);
				}

			auto a = cast(ubyte[])((&v)[0..1]);
			lineData ~= a[2];
			lineData ~= a[1];
			lineData ~= a[0];

			line = line[4..$];
		}
		while (len > lineData.length)
			lineData ~= 0;
		data ~= lineData[0..len];
	}
	return data;
}

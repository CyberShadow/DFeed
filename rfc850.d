module rfc850;

import std.string;
import std.conv;
import std.array;
import std.uri;
import std.base64;
debug import std.stdio;

import ae.net.http.client;
import ae.utils.array;
import ae.utils.time;
import ae.utils.text;
import ae.utils.mime;

import common;
import bitly;
import database;

struct Xref
{
	string group;
	int num;
}

enum DEFAULT_ENCODING = "windows1252";

class Rfc850Post : Post
{
	string lines, id;
	Xref[] xref;

	string subject, realSubject, author, authorEmail, url, shortURL;
	string[] references;
	bool reply;

	/// Result of threadify()
	Rfc850Post[] children;

	/// Internal database index
	int rowid;

	string[string] headers;
	string content; /// text/plain only
	ubyte[] data; /// can be anything
	string error; /// Explanation for null content
	bool flowed, delsp;

	/// Multipart stuff
	string name, fileName, description, mimeType;
	Rfc850Post[] parts;

	this(string _lines, string _id=null, int _rowid=0)
	{
		lines = _lines;
		id    = _id;
		rowid = _rowid;

		// TODO: actually read RFC 850
		// TODO: this breaks binary encodings, FIXME?
		auto text = lines.replace("\r\n", "\n");
		auto headerEnd = text.indexOf("\n\n");
		if (headerEnd < 0) headerEnd = text.length;
		auto header = text[0..headerEnd];
		header = header.replace("\n\t", " ").replace("\n ", " ");

		foreach (s; header.split("\n"))
		{
			if (s == "") break;
			if (hasIntlCharacters(s))
				s = decodeEncodedText(s, DEFAULT_ENCODING);

			auto p = s.indexOf(": ");
			if (p<0) continue;
			//assert(p>0, "Bad header line: " ~ s);
			headers[toUpper(s[0..p])] = s[p+2..$];
		}

		string rawContent = text[headerEnd+2..$]; // not UTF-8

		if ("CONTENT-TRANSFER-ENCODING" in headers)
			try
				rawContent = decodeTransferEncoding(rawContent, headers["CONTENT-TRANSFER-ENCODING"]);
			catch (Exception e)
			{
				rawContent = null;
				error = "Error decoding " ~ headers["CONTENT-TRANSFER-ENCODING"] ~ " message: " ~ e.msg;
			}

		data = cast(ubyte[])rawContent;

		TokenHeader contentType, contentDisposition;
		if ("CONTENT-TYPE" in headers)
			contentType = decodeTokenHeader(headers["CONTENT-TYPE"]);
		if ("CONTENT-DISPOSITION" in headers)
			contentDisposition = decodeTokenHeader(headers["CONTENT-DISPOSITION"]);
		mimeType = toLower(contentType.value);
		flowed = aaGet(contentType.properties, "format", "fixed") == "flowed";
		delsp = aaGet(contentType.properties, "delsp", "no") == "yes";

		if (rawContent)
		{
			if (!mimeType || mimeType == "text/plain")
			{
				if ("charset" in contentType.properties)
					content = decodeEncodedText(rawContent, contentType.properties["charset"]);
				else
				if (hasIntlCharacters(rawContent))
					content = decodeEncodedText(rawContent, DEFAULT_ENCODING);
				else
					content = rawContent;
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
					if (rawParts.length && rawParts[0].strip().length)
						content = rawParts[0]; // default content to multipart stub
					else
						error = "Couldn't find text part in this " ~ mimeType ~ " message";
				}
			}
			else
				error = "Don't know how parse " ~ mimeType ~ " message";
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

		name = aaGet(contentType.properties, "name", string.init);
		fileName = aaGet(contentDisposition.properties, "filename", string.init);
		description = aaGet(headers, "CONTENT-DESCRIPTION", string.init);
		if (name == fileName)
			name = null;

		if ("REFERENCES" in headers)
		{
			reply = true;
			auto refs = strip(headers["REFERENCES"]);
			while (refs.startsWith("<"))
			{
				auto p = refs.indexOf(">");
				if (p < 0)
					break;
				references ~= refs[0..p+1];
				refs = strip(refs[p+1..$]);
			}
		}

		subject = realSubject = "SUBJECT" in headers ? decodeRfc5335(headers["SUBJECT"]) : null;
		if (subject.startsWith("Re: "))
		{
			subject = subject[4..$];
			reply = true;
		}

		author = authorEmail = "FROM" in headers ? decodeRfc5335(headers["FROM"]) : null;
		if ("X-BUGZILLA-WHO" in headers)
		{
			author = authorEmail = headers["X-BUGZILLA-WHO"];

			foreach (line; content.split("\n"))
				if (line.endsWith("> changed:"))
					author = line[0..line.indexOf(" <")];
				else
				if (line.startsWith("--- Comment #") && line.indexOf(" from ")>0 && line.indexOf(" <")>0 && line.endsWith(" ---"))
					author = line[line.indexOf(" from ")+6 .. line.indexOf(" <")];
		}
		if (author.indexOf('<')>=0 && author.endsWith('>'))
		{
			auto p = author.indexOf('<');
			authorEmail = author[p+1..$-1];
			author = decodeRfc5335(strip(author[0..p]));
		}
		if (author.length>2 && author[0]=='"' && author[$-1]=='"')
			author = decodeRfc5335(strip(author[1..$-1]));

		//where = "NEWSGROUPS" in headers ? headers["NEWSGROUPS"] : null;
		if ("XREF" in headers)
		{
			auto xrefStrings = split(headers["XREF"], " ")[1..$];
			foreach (str; xrefStrings)
			{
				auto segs = str.split(":");
				xref ~= Xref(segs[0], to!int(segs[1]));
			}
		}

		if ("LIST-ID" in headers && subject.startsWith("[") && !xref.length)
		{
			auto p = subject.indexOf("] ");
			xref = [Xref(subject[1..p])];
			subject = subject[p+2..$];
		}

		if ("MESSAGE-ID" in headers && !id)
			id = headers["MESSAGE-ID"];

		if (subject.startsWith("[Issue "))
			url = "http://d.puremagic.com/issues/show_bug.cgi?id=" ~ subject.split(" ")[1][0..$-1];
		else
		if (xref.length)
		{
			auto group = xref[0].group;
			auto num = xref[0].num;
			//url = format("http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=%s", encodeUrlParameter(group), num);
			url = format("http://digitalmars.com/webnews/newsgroups.php?art_group=%s&article_id=%s", encodeComponent(group), num);
		}
		else
		if ("LIST-ID" in headers && id)
		{
			if (id.startsWith("<") && id.endsWith(">"))
				url = "http://mid.gmane.org/" ~ id[1..$-1];
		}

		//if ("MESSAGE-ID" in headers)
		//	url = "news://news.digitalmars.com/" ~ headers["MESSAGE-ID"][1..$-1];

		if ("NNTP-POSTING-DATE" in headers)
			time = parseTime("D, j M Y H:i:s O", headers["NNTP-POSTING-DATE"]);
		else
		if ("DATE" in headers)
		{
			auto str = headers["DATE"];
			try
				time = parseTime(TimeFormats.RFC850, str);
			catch (Exception e)
			try
				time = parseTime(`D, j M Y H:i:s O`, str);
			catch (Exception e)
			try
				time = parseTime(`D, j M Y H:i:s e`, str);
			catch (Exception e)
			{ /* fall-back to default (class creation time) */ }
		}
	}

	private this() // for attachments
	{
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
		if (author == "noreply@github.com")
			return false;

		if (where == "")
			return false;

		if (inArray(ANNOUNCE_REPLIES, where))
			return true;

		return !reply || inArray(VIPs, author);
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

private:

string decodeRfc5335(string str)
{
	// TODO: find the actual RFC this is described in and implement it according to standard

	auto words = str.split(" ");
	bool[] encoded = new bool[words.length];

	foreach (wordIndex, ref word; words)
		if (word.length >= 4 && word.startsWith("=?") && word.endsWith("?="))
		{
			string s = word[2..$-2];

			auto p = s.indexOf('?');
			if (p<=0) continue;
			auto textEncoding = s[0..p];
			s = s[p+1..$];

			p = s.indexOf('?');
			if (p<=0) continue;
			auto contentEncoding = s[0..p];
			s = s[p+1..$];

			switch (toUpper(contentEncoding))
			{
			case "Q":
				s = decodeQuotedPrintable(s);
				break;
			case "B":
				s = cast(string)Base64.decode(s);
				break;
			default:
				continue /*foreach*/;
			}

			word = decodeEncodedText(s, textEncoding);
			encoded[wordIndex] = true;
		}

	string result;
	foreach (wordIndex, word; words)
	{
		if (wordIndex > 0 && !(encoded[wordIndex-1] && encoded[wordIndex]))
			result ~= ' ';
		result ~= word;
	}
	return result;
}

string decodeQuotedPrintable(string s)
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
		if (s[i]=='_')
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
		import ae.sys.cmd;
		return iconv(s, textEncoding);
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
			s = strip(s[p+1..$]);
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
    	return decodeQuotedPrintable(data);
    case "base64":
    	//return cast(string)Base64.decode(data.replace("\n", ""));
    {
    	auto s = data.replace("\n", "");
    	scope(failure) std.stdio.writeln(s);
    	return cast(string)Base64.decode(s);
    }
    default:
    	return data;
    }
}

ubyte[] uudecode(string[] lines)
{
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
		data ~= lineData[0..len];
	}
	return data;
}

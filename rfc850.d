module rfc850;

import std.string;
import std.conv;
import std.array;
import std.uri;
import std.base64;

import ae.net.http.client;
import ae.utils.array;
import ae.utils.time;

import common;
import bitly;
import database;

struct Xref
{
	string group;
	int num;
}

class Rfc850Post : Post
{
	string lines, id;
	Xref[] xref;

	string subject, realSubject, author, authorEmail, url, shortURL, content;
	string[] references;
	bool reply;

	/// Result of threadify()
	Rfc850Post[] children;

	/// Internal database index
	int rowid;

	this(string lines, string id=null, int rowid=0)
	{
		this.lines = lines;
		this.id    = id;
		this.rowid = rowid;

		// TODO: actually read RFC 850
		auto text = lines.replace("\r\n", "\n");
		auto headerEnd = text.indexOf("\n\n");
		if (headerEnd < 0) headerEnd = text.length;
		auto header = text[0..headerEnd];
		header = header.replace("\n\t", " ").replace("\n ", " ");

		content = text[headerEnd+2..$];
		auto contentLines = content.split("\n");

		string[string] headers;
		foreach (s; header.split("\n"))
		{
			if (s == "") break;
			if (hasIntlCharacters(s))
				s = decodeEncodedText(s, "windows1252");

			int p = s.indexOf(": ");
			if (p<0) continue;
			//assert(p>0, "Bad header line: " ~ s);
			headers[toupper(s[0..p])] = s[p+2..$];
		}

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

			foreach (line; contentLines)
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

			int p = s.indexOf('?');
			if (p<=0) continue;
			auto textEncoding = s[0..p];
			s = s[p+1..$];

			p = s.indexOf('?');
			if (p<=0) continue;
			auto contentEncoding = s[0..p];
			s = s[p+1..$];

			switch (toupper(contentEncoding))
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
	string r;
	for (int i=0; i<s.length; )
		if (s[i]=='=')
			r ~= cast(char)parse!ubyte(s[i+1..i+3], 16), i+=3;
		else
		if (s[i]=='_')
			r ~= ' ', i++;
		else
			r ~= s[i++];
	return r;
}

bool hasIntlCharacters(string s)
{
	foreach (char c; s)
		if (c >= 0x80)
			return true;
	return false;
}

string decodeEncodedText(string s, string textEncoding)
{
	try
	{
		import arsd.characterencodings;
		return convertToUtf8(cast(immutable(ubyte)[])s, textEncoding);
	}
	catch (Exception e)
	{
		import ae.sys.cmd;
		return iconv(s, textEncoding);
	}
}

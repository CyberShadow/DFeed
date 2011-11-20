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

class Rfc850Post : Post
{
	string lines, where, num, id;

	string subject, author, url, shortURL;
	string[] references;
	bool reply;

	this(string lines, string where=null, string num=null, string id=null)
	{
		this.lines = lines;
		this.where = where;
		this.num   = num;
		this.id    = id;

		// TODO: actually read RFC 850
		auto text = lines.replace("\r\n", "\n").replace("\n\t", " ").replace("\n ", " ");
		string[string] headers;
		foreach (s; text.split("\n"))
		{
			if (s == "") break;
			int p = s.indexOf(": ");
			if (p<0) continue;
			//assert(p>0, "Bad header line: " ~ s);
			headers[toupper(s[0..p])] = s[p+2..$];
		}

		if ("REFERENCES" in headers)
		{
			reply = true;
			references = headers["REFERENCES"].split();
		}

		subject = "SUBJECT" in headers ? decodeRfc5335(headers["SUBJECT"]) : null;
		if (subject.startsWith("Re: "))
		{
			subject = subject[4..$];
			reply = true;
		}

		author = "FROM" in headers ? decodeRfc5335(headers["FROM"]) : null;
		if ("X-BUGZILLA-WHO" in headers)
			author = headers["X-BUGZILLA-WHO"];
		if (author.indexOf('<')>0)
			author = decodeRfc5335(strip(author[0..author.indexOf('<')]));
		if (author.length>2 && author[0]=='"' && author[$-1]=='"')
			author = decodeRfc5335(strip(author[1..$-1]));

		where = "NEWSGROUPS" in headers ? headers["NEWSGROUPS"] : null;

		if ("LIST-ID" in headers && subject.startsWith("[") && where is null)
		{
			auto p = subject.indexOf("] ");
			where = subject[1..p];
			subject = subject[p+2..$];
		}

		if ("MESSAGE-ID" in headers && !id)
			id = headers["MESSAGE-ID"];

		if (subject.startsWith("[Issue "))
			url = "http://d.puremagic.com/issues/show_bug.cgi?id=" ~ subject.split(" ")[1][0..$-1];
		else
		if ("XREF" in headers)
		{
			auto xref = split(split(headers["XREF"], " ")[1], ":");
			where = xref[0];
			num = xref[1];
			//url = format("http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=%s", encodeUrlParameter(where), num);
			url = format("http://digitalmars.com/webnews/newsgroups.php?art_group=%s&article_id=%s", encodeComponent(where), num);
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
			where is null ? null : (
				"[" ~ (
					where.startsWith("digitalmars.") ?
						"dm." ~ where[12..$]
					:
						where
				) ~ "] "
			),
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

	string parentID()
	{
		return references.length ? references[$-1] : null;
	}

	string threadID()
	{
		return references.length ? references[0] : id;
	}

private:
	string[] ANNOUNCE_REPLIES = ["digitalmars.D.bugs"];
	string[] VIPs = ["Walter Bright", "Andrei Alexandrescu", "Sean Kelly", "Don", "dsimcha"];
}

private:

string decodeRfc5335(string str)
{
	// TODO: actually read RFC 5335

	if (hasIntlCharacters(str))
		str = decodeEncodedText(str, "windows1252");

	int start, end;
conversionLoop:
	while ((start=str.indexOf("=?"))>=0 && (end=str.indexOf("?= "), end<0&&str.endsWith("?=")?(end=str.length-2):0)>=0 && str.length>4)
	{
		string s = str[start+2..end];

		int p = s.indexOf('?');
		if (p<=0) break;
		auto textEncoding = s[0..p];
		s = s[p+1..$];

		p = s.indexOf('?');
		if (p<=0) break;
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
			break conversionLoop;
		}

		str = str[0..start] ~ decodeEncodedText(s, textEncoding) ~ str[end==$-2?$:end+3..$];
	}
	return str;
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
		import ae.utils.cmd;
		return iconv(s, textEncoding);
	}
}

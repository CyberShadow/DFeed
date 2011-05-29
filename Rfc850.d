module Rfc850;

import std.string;

import Team15.Utils;

string summarizeMessage(string lines)
{
	lines = lines.replace("\r\n", "\n").replace("\n\t", " ").replace("\n ", " ");
	string[string] headers;
	foreach (s; splitlines(lines))
	{
		int p = s.find(": ");
		if (p<0) continue;
		//assert(p>0, "Bad header line: " ~ s);
		headers[toupper(s[0..p])] = s[p+2..$];
	}

	bool reply = "REFERENCES" in headers ? true : false;
	auto subject = "SUBJECT" in headers ? decodeRfc5335(headers["SUBJECT"]) : "";
	if (subject.startsWith("Re: "))
		subject = subject[4..$];
	subject = subject.length ? `"` ~ subject ~ `"` : "<no subject>";
	auto author = "FROM" in headers ? headers["FROM"] : "<no sender>";
	if ("X-BUGZILLA-WHO" in headers)
		author = headers["X-BUGZILLA-WHO"];
	if (author.find('<')>0)
		author = decodeRfc5335(strip(author[0..author.find('<')]));
	if (author.length>2 && author[0]=='"' && author[$-1]=='"')
		author = decodeRfc5335(strip(author[1..$-1]));

	auto where = "NEWSGROUPS" in headers ? headers["NEWSGROUPS"] : "<unknown>";

	if ("LIST-ID" in headers && subject.startsWith(`"[`) && where == "<unknown>")
	{
		auto p = subject.find("] ");
		where = subject[2..p];
		subject = subject[0..1] ~ subject[p+2..$];
	}

	if (where.startsWith("digitalmars."))
		where = "dm." ~ where[12..$];

	auto summary = format("[%s] %s %s %s", where, author, reply ? "replied to" : "posted", subject);

	if (subject.startsWith("\"[Issue "))
		summary ~= ": " ~ shortenURL("http://d.puremagic.com/issues/show_bug.cgi?id=" ~ subject.split(" ")[1][0..$-1]);
	else
	if ("XREF" in headers)
	{
		auto xref = split(split(headers["XREF"], " ")[1], ":");
		auto ng = xref[0];
		auto id = xref[1];
		auto link = format("http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=%s", ng, id);
		link = shortenURL(link);
		summary ~= ": " ~ link;
	}
	else
	if ("LIST-ID" in headers && "MESSAGE-ID" in headers)
	{
		auto id = headers["MESSAGE-ID"];
		assert(id.startsWith("<") && id.endsWith(">"));
		auto link = "http://mid.gmane.org/" ~ id[1..$-1];
		link = shortenURL(link);
		summary ~= ": " ~ link;
	}

	/*if ("MESSAGE-ID" in headers)
		fields ~= "news://news.digitalmars.com/" ~ headers["MESSAGE-ID"][1..$-1];*/

	return summary;
}

import std.base64 : decodeBase64 = decode;

string decodeRfc5335(string str)
{
	str = str.replace("?= =?", "?==?");
	int start, end;
	while ((start=str.find("=?"))>=0 && (end=str.find("?="))>=0 && str.length>4)
	{
		string s = str[start+2..end];

		int p = s.find('?');
		if (p<=0) return str;
		auto textEncoding = s[0..p];
		s = s[p+1..$];

		p = s.find('?');
		if (p<=0) return str;
		auto contentEncoding = s[0..p];
		s = s[p+1..$];

		switch (contentEncoding)
		{
		case "Q":
			s = decodeQuotedPrintable(s);
			break;
		case "B":
			s = decodeBase64(s);
			break;
		default:
			return str;
		}

		str = str[0..start] ~ iconv(s, textEncoding) ~ str[end+2..$];
	}
	return str;
}

string decodeQuotedPrintable(string s)
{
	string r;
	for (int i=0; i<s.length; )
		if (s[i]=='=')
			r ~= fromHex(s[i+1..i+3]), i+=3;
		else
		if (s[i]=='_')
			r ~= ' ', i++;
		else
			r ~= s[i++];
	return r;
}

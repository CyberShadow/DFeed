module Rfc850;

import std.string;

import Team15.Utils;

struct MessageInfo
{
	string subject, author, where, url;
	bool reply;
}

MessageInfo parseMessage(string lines)
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

	MessageInfo m;
	m.reply = "REFERENCES" in headers ? true : false;
	m.subject = "SUBJECT" in headers ? decodeRfc5335(headers["SUBJECT"]) : null;
	if (m.subject.startsWith("Re: "))
	{
		m.subject = m.subject[4..$];
		m.reply = true;
	}

	m.author = "FROM" in headers ? decodeRfc5335(headers["FROM"]) : null;
	if ("X-BUGZILLA-WHO" in headers)
		m.author = headers["X-BUGZILLA-WHO"];
	if (m.author.find('<')>0)
		m.author = decodeRfc5335(strip(m.author[0..m.author.find('<')]));
	if (m.author.length>2 && m.author[0]=='"' && m.author[$-1]=='"')
		m.author = decodeRfc5335(strip(m.author[1..$-1]));

	m.where = "NEWSGROUPS" in headers ? headers["NEWSGROUPS"] : null;

	if ("LIST-ID" in headers && m.subject.startsWith("[") && m.where is null)
	{
		auto p = m.subject.find("] ");
		m.where = m.subject[1..p];
		m.subject = m.subject[p+2..$];
	}

	if (m.subject.startsWith("[Issue "))
		m.url = "http://d.puremagic.com/issues/show_bug.cgi?id=" ~ m.subject.split(" ")[1][0..$-1];
	else
	if ("XREF" in headers)
	{
		auto xref = split(split(headers["XREF"], " ")[1], ":");
		auto ng = xref[0];
		auto id = xref[1];
		m.url = format("http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=%s", ng, id);
	}
	else
	if ("LIST-ID" in headers && "MESSAGE-ID" in headers)
	{
		auto id = headers["MESSAGE-ID"];
		if (id.startsWith("<") && id.endsWith(">"))
			m.url = "http://mid.gmane.org/" ~ id[1..$-1];
	}

	//if ("MESSAGE-ID" in headers)
	//	m.url = "news://news.digitalmars.com/" ~ headers["MESSAGE-ID"][1..$-1];

	return m;
}

import std.base64 : decodeBase64 = decode;

string decodeRfc5335(string str)
{
	int start, end;
conversionLoop:
	while ((start=str.find("=?"))>=0 && (end=str.find("?= "), end<0&&str.endsWith("?=")?(end=str.length-2):0)>=0 && str.length>4)
	{
		string s = str[start+2..end];

		int p = s.find('?');
		if (p<=0) break;
		auto textEncoding = s[0..p];
		s = s[p+1..$];

		p = s.find('?');
		if (p<=0) break;
		auto contentEncoding = s[0..p];
		s = s[p+1..$];

		switch (toupper(contentEncoding))
		{
		case "Q":
			s = decodeQuotedPrintable(s);
			break;
		case "B":
			s = decodeBase64(s);
			break;
		default:
			break conversionLoop;
		}

		str = str[0..start] ~ iconv(s, textEncoding) ~ str[end==$-2?$:end+3..$];
	}
	return str;
}

string decodeQuotedPrintable(string s)
{
	string r;
	for (int i=0; i<s.length; )
		if (s[i]=='=')
			r ~= cast(char)fromHex(s[i+1..i+3]), i+=3;
		else
		if (s[i]=='_')
			r ~= ' ', i++;
		else
			r ~= s[i++];
	return r;
}

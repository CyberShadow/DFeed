module Rfc850;

import std.string;

import Team15.Utils;

string summarizeMessage(string lines)
{
	string[string] headers;
	lines = lines.replace("\r\n", "\n").replace("\n ", " ");
	foreach (s; splitlines(lines))
	{
		int p = s.find(": ");
		if (p<0) continue;
		//assert(p>0, "Bad header line: " ~ s);
		headers[s[0..p]] = s[p+2..$];
	}

	bool reply = "References" in headers ? true : false;
	auto subject = "Subject" in headers ? headers["Subject"] : "";
	if (subject.startsWith("Re: "))
		subject = subject[4..$];
	subject = subject.length ? `"` ~ subject ~ `"` : "<no subject>";
	auto author = "From" in headers ? headers["From"] : "<no sender>";
	if ("X-Bugzilla-Who" in headers)
		author = headers["X-Bugzilla-Who"];
	if (author.find('<')>0)
		author = strip(author[0..author.find('<')]);
	if (author.length>2 && author[0]=='"' && author[$-1]=='"')
		author = strip(author[1..$-1]);

	auto where = "Newsgroups" in headers ? headers["Newsgroups"] : "<unknown>";
	if (where.startsWith("digitalmars."))
		where = "dm." ~ where[12..$];

	auto summary = format("[%s] %s %s %s", where, author, reply ? "replied to" : "posted", subject);

	if (subject.startsWith("\"[Issue "))
		summary ~= ": " ~ shortenURL("http://d.puremagic.com/issues/show_bug.cgi?id=" ~ subject.split(" ")[1][0..$-1]);
	else
	if ("Xref" in headers)
	{
		auto xref = split(split(headers["Xref"], " ")[1], ":");
		auto ng = xref[0];
		auto id = xref[1];
		auto link = format("http://www.digitalmars.com/pnews/read.php?server=news.digitalmars.com&group=%s&artnum=%s", ng, id);
		link = shortenURL(link);
		summary ~= ": " ~ link;
	}

	/*if ("Message-ID" in headers)
		fields ~= "news://news.digitalmars.com/" ~ headers["Message-ID"][1..$-1];*/

	return summary;
}

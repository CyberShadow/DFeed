/*  Copyright (C) 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.lint;

import ae.sys.persistence;
import ae.utils.regex;

import std.algorithm;
import std.exception;
import std.range;
import std.regex;
import std.string;

import dfeed.message;
import dfeed.web.posting;
import dfeed.web.web : getPost;
import dfeed.web.web.part.postbody : reUrl;

class LintRule
{
	/// ID string - used in forms for button names, etc.
	abstract @property string id();

	/// Short description - visible by default
	abstract @property string shortDescription();

	/// Long description - shown on request, should contain rationale (HTML)
	abstract @property string longDescription();

	/// Check if the lint rule is triggered.
	abstract bool check(in ref PostDraft);

	/// Should the "Fix it for me" option be presented to the user?
	abstract bool canFix(in ref PostDraft);

	/// Fix up the post according to the rule.
	abstract void fix(ref PostDraft);
}

class NotQuotingRule : LintRule
{
	override @property string id() { return "notquoting"; }
	override @property string shortDescription() { return "Parent post is not quoted."; }
	override @property string longDescription() { return
		"<p>When replying to someone's post, you should provide some context for your replies by quoting the revelant parts of their post.</p>" ~
		"<p>Depending on the software (or its configuration) used to read your message, it may not be obvious which post you're replying to.</p>" ~
		"<p>Thus, when writing a reply, don't delete all quoted text: instead, leave just enough to provide context for your reply. " ~
		   "You can also insert your replies inline (interleaved with quoted text) to address specific parts of the parent post.</p>";
	}

	override bool check(in ref PostDraft draft)
	{
		if (!hasParent(draft))
			return false;
		auto lines = draft.clientVars.get("text", null).splitLines();
		return !lines.canFind!(line => line.startsWith(">"));
	}

	override bool canFix(in ref PostDraft draft) { return true; }

	override void fix(ref PostDraft draft)
	{
		auto text = getParent(draft).replyTemplate().content.strip();
		draft.clientVars["text"] = text ~ "\n\n" ~ draft.clientVars.get("text", null);
		(new OverquotingRule).fix(draft);
	}
}

string[] getLines(in ref PostDraft draft)
{
	return draft.clientVars.get("text", null).strip().splitLines();
}

bool isWroteLine(string line) { return line.startsWith("On ") && line.canFind(", ") && line.endsWith(" wrote:"); }

string[] getWroteLines(in ref PostDraft draft)
{
	return getLines(draft).filter!isWroteLine.array();
}

string[] getNonQuoteLines(in ref PostDraft draft)
{
	return getLines(draft).filter!(line => !line.startsWith(">") && !line.isWroteLine).array();
}

bool hasParent(in ref PostDraft draft) { return "parent" in draft.serverVars && getPost(draft.serverVars["parent"]) !is null; }
Rfc850Post getParent(in ref PostDraft draft) { return getPost(draft.serverVars["parent"]).enforce("Can't find parent post"); }

string[] getParentLines(in ref PostDraft draft)
{
	return getParent(draft).content.strip().splitLines();
}

string[] getQuotedParentLines(in ref PostDraft draft)
{
	return getParent(draft).replyTemplate().content.strip().splitLines();
}

class WrongParentRule : LintRule
{
	override @property string id() { return "wrongparent"; }
	override @property string shortDescription() { return "You are quoting a post other than the parent."; }
	override @property string longDescription() { return
		"<p>When replying a message, the message you are replying to is referenced in the post's headers.</p>" ~
		"<p>Depending on the software (or its configuration) used to read your message, your message may be displayed below its parent post. " ~
		   "If your message contains a reply to a different post, following the conversation may become somewhat confusing.</p>" ~
		"<p>Thus, make sure to click the \"Reply\" link on the actual post you're replying to, and quote the parent post for context.</p>";
	}

	override bool check(in ref PostDraft draft)
	{
		if (!hasParent(draft))
			return false;
		auto wroteLines = getWroteLines(draft);
		return wroteLines.length && !wroteLines.canFind(getQuotedParentLines(draft)[0]);
	}

	override bool canFix(in ref PostDraft draft) { return false; }

	override void fix(ref PostDraft draft)
	{
		//(new NotQuotingRule).fix(draft);
		assert(false);
	}
}

class NoParentRule : LintRule
{
	override @property string id() { return "noparent"; }
	override @property string shortDescription() { return "Parent post is not indicated."; }
	override @property string longDescription() { return
		"<p>When quoting someone's post, you should leave the \"On (date), (author) wrote:\" line.</p>" ~
		"<p>Depending on the software (or its configuration) used to read your message, it may not be obvious which post you're replying to.</p>" ~
		"<p>Thus, this line provides important context for your replies regarding the structure of the conversation.</p>";
	}

	override bool check(in ref PostDraft draft)
	{
		if (!hasParent(draft))
			return false;
		return getWroteLines(draft).length == 0 && getLines(draft).canFind!(line => line.startsWith(">"));
	}

	override bool canFix(in ref PostDraft draft) { return true; }

	override void fix(ref PostDraft draft)
	{
		auto qpLines = getQuotedParentLines(draft);
		auto lines = getLines(draft);
		foreach (i, line; lines)
			if (line.length > 5 && line.startsWith(">") && qpLines.canFind(line))
			{
				auto j = i;
				while (j && lines[j-1].startsWith(">"))
					j--;
				lines = lines[0..j] ~ qpLines[0] ~ lines[j..$];
				draft.clientVars["text"] = lines.join("\n");
				(new OverquotingRule).fix(draft);
				return;
			}

		// Can't find any bit of quoted text in parent
		(new NotQuotingRule).fix(draft);
	}
}

class MultiParentRule : LintRule
{
	override @property string id() { return "multiparent"; }
	override @property string shortDescription() { return "You are quoting multiple posts."; }
	override @property string longDescription() { return
		"<p>When replying a message, the message you are replying to is referenced in the post's headers.</p>" ~
		"<p>Depending on the software (or its configuration) used to read your message, your message may be displayed below its parent post. " ~
		   "If your message contains a reply to a different post, following the conversation may become somewhat confusing.</p>" ~
		"<p>Thus, you should avoid replying to multiple posts in one reply. " ~
		   "If applicable, you should split your message into several, each as a reply to its corresponding parent post.</p>";
	}

	override bool check(in ref PostDraft draft)
	{
		if (!hasParent(draft))
			return false;
		return getWroteLines(draft).sort().uniq().walkLength > 1;
	}

	override bool canFix(in ref PostDraft draft) { return false; }

	override void fix(ref PostDraft draft) { assert(false); }
}

class TopPostingRule : LintRule
{
	override @property string id() { return "topposting"; }
	override @property string shortDescription() { return "You are top-posting."; }
	override @property string longDescription() { return
		"<p>When replying a message, it is generally preferred to add your reply under the quoted parent text.</p>" ~
		"<p>Depending on the software (or its configuration) used to read your message, your message may not be displayed below its parent post. " ~
		   "In such cases, the quoted text provides context for your reply, and readers would need to first read the quoted text below your reply for context.</p>" ~
		"<p>Thus, you should add your reply below the quoted text (or reply to individual paragraphs inline), rather than above it.</p>";
	}

	override bool check(in ref PostDraft draft)
	{
		if (!hasParent(draft))
			return false;

		auto lines = getLines(draft);
		bool inQuote;
		foreach (line; lines)
		{
			if (line.startsWith(">"))
				inQuote = true;
			else
				if (inQuote)
					return false;
		}
		return inQuote;
	}

	override bool canFix(in ref PostDraft draft) { return true; }

	override void fix(ref PostDraft draft)
	{
		auto lines = getLines(draft);
		auto start = lines.countUntil!(line => line.startsWith(">"));
		if (start && lines[start-1].isWroteLine())
			start--;
		lines = lines[start..$] ~ [string.init] ~ lines[0..start];

		if (!lines[0].isWroteLine())
		{
			auto i = lines.countUntil!isWroteLine();
			if (i > 0)
				lines = [lines[i]] ~ lines[0..i] ~ lines[i+1..$];
		}

		draft.clientVars["text"] = lines.join("\n").strip();
	}
}

class OverquotingRule : LintRule
{
	override @property string id() { return "overquoting"; }
	override @property string shortDescription() { return "You are overquoting."; }
	override @property string longDescription() { return
		"<p>The ratio between quoted and added text is vastly disproportional.</p>" ~
		"<p>Quoting should be limited to the amount necessary to provide context for your replies. " ~
		   "Quoting posts in their entirety is thus rarely necessary, and is a waste of vertical space.</p>" ~
		"<p>Please trim the quoted text to just the relevant parts you're addressing in your reply, or add more content to your post.</p>";
	}

	bool checkLines(string[] lines)
	{
		auto quoted   = lines.filter!(line =>  line.startsWith(">")).map!(line => line.length).sum();
		auto unquoted = lines.filter!(line => !line.startsWith(">")).map!(line => line.length).sum();
		if (unquoted < 200)
			unquoted = 200;
		return unquoted && quoted > unquoted * 4;
	}

	override bool check(in ref PostDraft draft)
	{
		auto lines = draft.clientVars.get("text", null).splitLines();
		return checkLines(lines);
	}

	override bool canFix(in ref PostDraft draft) { return true; }

	override void fix(ref PostDraft draft)
	{
		auto lines = draft.clientVars.get("text", null).splitLines();

		static string quotePrefix(string s)
		{
			int i;
			for (; i<s.length; i++)
				if (s[i] == '>' || (s[i] == ' ' && i != 0))
					continue;
				else
					break;
			return s[0..i];
		}

		static size_t quoteLevel(string quotePrefix)
		{
			return quotePrefix.count(">");
		}

		bool check()
		{
			draft.clientVars["text"] = lines.join("\n");
			return !checkLines(lines);
		}

		if (check())
			return; // Nothing to do

		// First, try to trim inner posting levels
		void trimBeyond(int trimLevel)
		{
			bool trimming;
			foreach_reverse (i, s; lines)
			{
				auto prefix = quotePrefix(s);
				auto level = prefix.count(">");
				if (level >= trimLevel)
				{
					if (!trimming)
					{
						lines[i] = prefix ~ "[...]";
						trimming = true;
					}
					else
						lines = lines[0..i] ~ lines[i+1..$];
				}
				else
					trimming = false;
			}
		}

		foreach_reverse (trimLevel; 2..6)
		{
			trimBeyond(trimLevel);
			if (check())
				return;
		}

		// Next, try to trim to just the first quoted paragraph
		string[] newLines;
		int sawContent;
		bool trimming;
		foreach (line; lines)
		{
			if (line.startsWith(">"))
			{
				if (line.strip() == ">")
				{
					if (!trimming && sawContent > 1)
					{
						newLines ~= ">";
						newLines ~= "> [...]";
						trimming = true;
						sawContent = 0;
					}
				}
				else
				if (!line.endsWith(" wrote:")
				 && !line.endsWith("[...]"))
					sawContent++;
			}
			else
				trimming = false;
			if (!trimming)
				newLines ~= line;
		}
		lines = newLines;
		if (check())
			return;

		// Lastly, just trim all quoted text
		trimBeyond(1);
		check();
	}
}

class ShortLinkRule : LintRule
{
	override @property string id() { return "shortlink"; }
	override @property string shortDescription() { return "Don't use URL shorteners."; }
	override @property string longDescription() { return
		"<p>URL shortening services, such as TinyURL, are useful in cases where space is at a premium, e.g. in IRC or Twitter messages. " ~
		   "In other circumstances, however, they provide little benefit, and have the significant disadvantage of being opaque: " ~
		   "readers can only guess where the link will lead to before they click it.</p>" ~
		"<p>Additionally, URL shortening services come and go - your link may work today, but might not in a year or two.</p>" ~
		"<p>Thus, do not use URL shorteners when posting messages online - post the full link instead, even if it seems exceedingly long. " ~
		   "If it is too long to be inserted inline, add it as a footnote instead.</p>";
	}

	// http://longurl.org/services
	static const string[] urlShorteners =
	["0rz.tw", "1link.in", "1url.com", "2.gp", "2big.at", "2tu.us", "3.ly", "307.to", "4ms.me", "4sq.com", "4url.cc", "6url.com", "7.ly", "a.gg", "a.nf", "aa.cx", "abcurl.net", "ad.vu", "adf.ly", "adjix.com", "afx.cc", "all.fuseurl.com", "alturl.com", "amzn.to", "ar.gy", "arst.ch", "atu.ca", "azc.cc", "b23.ru", "b2l.me", "bacn.me", "bcool.bz", "binged.it", "bit.ly", "bizj.us", "bloat.me", "bravo.ly", "bsa.ly", "budurl.com", "canurl.com", "chilp.it", "chzb.gr", "cl.lk", "cl.ly", "clck.ru", "cli.gs", "cliccami.info", "clickthru.ca", "clop.in", "conta.cc", "cort.as", "cot.ag", "crks.me", "ctvr.us", "cutt.us", "dai.ly", "decenturl.com", "dfl8.me", "digbig.com", "digg.com", "disq.us", "dld.bz", "dlvr.it", "do.my", "doiop.com", "dopen.us", "easyuri.com", "easyurl.net", "eepurl.com", "eweri.com", "fa.by", "fav.me", "fb.me", "fbshare.me", "ff.im", "fff.to", "fire.to", "firsturl.de", "firsturl.net", "flic.kr", "flq.us", "fly2.ws", "fon.gs", "freak.to", "fuseurl.com", "fuzzy.to", "fwd4.me", "fwib.net", "g.ro.lt", "gizmo.do", "gl.am", "go.9nl.com", "go.ign.com", "go.usa.gov", "goo.gl", "goshrink.com", "gurl.es", "hex.io", "hiderefer.com", "hmm.ph", "href.in", "hsblinks.com", "htxt.it", "huff.to", "hulu.com", "hurl.me", "hurl.ws", "icanhaz.com", "idek.net", "ilix.in", "is.gd", "its.my", "ix.lt", "j.mp", "jijr.com", "kl.am", "klck.me", "korta.nu", "krunchd.com", "l9k.net", "lat.ms", "liip.to", "liltext.com", "linkbee.com", "linkbun.ch", "liurl.cn", "ln-s.net", "ln-s.ru", "lnk.gd", "lnk.ms", "lnkd.in", "lnkurl.com", "lru.jp", "lt.tl", "lurl.no", "macte.ch", "mash.to", "merky.de", "migre.me", "miniurl.com", "minurl.fr", "mke.me", "moby.to", "moourl.com", "mrte.ch", "myloc.me", "myurl.in", "n.pr", "nbc.co", "nblo.gs", "nn.nf", "not.my", "notlong.com", "nsfw.in", "nutshellurl.com", "nxy.in", "nyti.ms", "o-x.fr", "oc1.us", "om.ly", "omf.gd", "omoikane.net", "on.cnn.com", "on.mktw.net", "onforb.es", "orz.se", "ow.ly", "ping.fm", "pli.gs", "pnt.me", "politi.co", "post.ly", "pp.gg", "profile.to", "ptiturl.com", "pub.vitrue.com", "qlnk.net", "qte.me", "qu.tc", "qy.fi", "r.im", "rb6.me", "read.bi", "readthis.ca", "reallytinyurl.com", "redir.ec", "redirects.ca", "redirx.com", "retwt.me", "ri.ms", "rickroll.it", "riz.gd", "rt.nu", "ru.ly", "rubyurl.com", "rurl.org", "rww.tw", "s4c.in", "s7y.us", "safe.mn", "sameurl.com", "sdut.us", "shar.es", "shink.de", "shorl.com", "short.ie", "short.to", "shortlinks.co.uk", "shorturl.com", "shout.to", "show.my", "shrinkify.com", "shrinkr.com", "shrt.fr", "shrt.st", "shrten.com", "shrunkin.com", "simurl.com", "slate.me", "smallr.com", "smsh.me", "smurl.name", "sn.im", "snipr.com", "snipurl.com", "snurl.com", "sp2.ro", "spedr.com", "srnk.net", "srs.li", "starturl.com", "su.pr", "surl.co.uk", "surl.hu", "t.cn", "t.co", "t.lh.com", "ta.gd", "tbd.ly", "tcrn.ch", "tgr.me", "tgr.ph", "tighturl.com", "tiniuri.com", "tiny.cc", "tiny.ly", "tiny.pl", "tinylink.in", "tinyuri.ca", "tinyurl.com", "tk.", "tl.gd", "tmi.me", "tnij.org", "tnw.to", "tny.com", "to.", "to.ly", "togoto.us", "totc.us", "toysr.us", "tpm.ly", "tr.im", "tra.kz", "trunc.it", "twhub.com", "twirl.at", "twitclicks.com", "twitterurl.net", "twitterurl.org", "twiturl.de", "twurl.cc", "twurl.nl", "u.mavrev.com", "u.nu", "u76.org", "ub0.cc", "ulu.lu", "updating.me", "ur1.ca", "url.az", "url.co.uk", "url.ie", "url360.me", "url4.eu", "urlborg.com", "urlbrief.com", "urlcover.com", "urlcut.com", "urlenco.de", "urli.nl", "urls.im", "urlshorteningservicefortwitter.com", "urlx.ie", "urlzen.com", "usat.ly", "use.my", "vb.ly", "vgn.am", "vl.am", "vm.lc", "w55.de", "wapo.st", "wapurl.co.uk", "wipi.es", "wp.me", "x.vu", "xr.com", "xrl.in", "xrl.us", "xurl.es", "xurl.jp", "y.ahoo.it", "yatuc.com", "ye.pe", "yep.it", "yfrog.com", "yhoo.it", "yiyd.com", "youtu.be", "yuarel.com", "z0p.de", "zi.ma", "zi.mu", "zipmyurl.com", "zud.me", "zurl.ws", "zz.gd", "zzang.kr", "›.ws", "✩.ws", "✿.ws", "❥.ws", "➔.ws", "➞.ws", "➡.ws", "➨.ws", "➯.ws", "➹.ws", "➽.ws"];

	static Regex!char re;

	this()
	{
		if (re.empty)
			re = regex(`https?://(` ~ urlShorteners.map!escapeRE.join("|") ~ `)/\w+`);
	}

	static string expandURLImpl(string url)
	{
		import std.net.curl;
		string result;

		auto http = HTTP(url);
		http.setUserAgent("DFeed (+https://github.com/CyberShadow/DFeed)");
		http.method = HTTP.Method.head;
		http.verifyPeer(false);
		http.onReceiveHeader =
			(in char[] key, in char[] value)
			{
				if (icmp(key, "Location")==0)
					result = value.idup;
			};
		http.perform();

		enforce(result, "Could not expand URL: " ~ url);
		return result;
	}

	enum urlCache = "data/shorturls.json";
	auto expandURL = PersistentMemoized!expandURLImpl(urlCache);

	override bool check(in ref PostDraft draft)
	{
		return !draft.getNonQuoteLines.join("\n").match(re).empty;
	}

	override bool canFix(in ref PostDraft draft) { return true; }

	override void fix(ref PostDraft draft)
	{
		draft.clientVars["text"] = draft.getLines()
			.map!(line =>
				line.startsWith(">")
					? line
					: line.replaceAll!(captures => expandURL(captures[0]))(re)
			)
			.join("\n")
		;
	}
}

class LinkInSubjectRule : LintRule
{
	override @property string id() { return "linkinsubject"; }
	override @property string shortDescription() { return "Don't put links in the subject."; }
	override @property string longDescription() { return
		"<p>Links in message subjects are usually not clickable.</p>" ~
		"<p>Please move the link in the message body instead.</p>";
	}

	override bool check(in ref PostDraft draft)
	{
		auto subject = draft.clientVars.get("subject", null);
		if (subject.startsWith("Re: ") || !subject.canFind("://"))
			return false;
		auto text = draft.clientVars.get("text", null);
		foreach (url; subject.match(reUrl))
			if (!text.canFind(url.captures[0]))
				return true;
		return false; // all URLs are also in the body
	}

	override bool canFix(in ref PostDraft draft) { return true; }

	override void fix(ref PostDraft draft)
	{
		auto subject = draft.clientVars.get("subject", null);
		draft.clientVars["text"] = subject ~ "\n\n" ~ draft.clientVars.get("text", null);
		//draft.clientVars["subject"] = subject.replaceAll(reUrl, "(URL inside)");
	}
}

@property LintRule[] lintRules()
{
	static LintRule[] result;
	if (!result.length)
		result = [
			new NotQuotingRule,
			new WrongParentRule,
			new NoParentRule,
			new MultiParentRule,
			new TopPostingRule,
			new OverquotingRule,
			new ShortLinkRule,
			new LinkInSubjectRule,
		];
	return result;
}

LintRule getLintRule(string id)
{
	foreach (rule; lintRules)
		if (rule.id == id)
			return rule;
	throw new Exception("Unknown lint rule: " ~ id);
}

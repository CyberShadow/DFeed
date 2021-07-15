/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Various string formatting.
module dfeed.web.web.part.strings;

import core.time;

import std.algorithm.comparison : min, max;
import std.conv : text;
import std.datetime.systime : SysTime, Clock;
import std.datetime.timezone : UTC;
import std.format : format;

import ae.utils.text.html : encodeHtmlEntities;

import dfeed.loc;

string summarizeTime(SysTime time, bool colorize = false)
{
	if (!time.stdTime)
		return "-";

	string style;
	if (colorize)
	{
		import std.math;
		auto diff = Clock.currTime() - time;
		auto diffLog = log2(diff.total!"seconds");
		enum LOG_MIN = 10; // 1 hour-ish
		enum LOG_MAX = 18; // 3 days-ish
		enum COLOR_MAX = 0xA0;
		auto f = (diffLog - LOG_MIN) / (LOG_MAX - LOG_MIN);
		f = min(1, max(0, f));
		auto c = cast(int)(f * COLOR_MAX);

		style ~= format("color: #%02X%02X%02X;", c, c, c);
	}

	bool shorter = colorize; // hack
	return `<span style="` ~ style ~ `" title="` ~ encodeHtmlEntities(formatLongTime(time)) ~ `">` ~ encodeHtmlEntities(formatShortTime(time, shorter)) ~ `</span>`;
}

string formatTinyTime(SysTime time)
{
	SysTime now = Clock.currTime(UTC());
	Duration duration = now - time;
	
	if (duration < 1.seconds)
		return "0s";
	else
	if (duration < 1.minutes)
		return text(duration.total!"seconds", "s");
	else
	if (duration < 1.hours)
		return text(duration.total!"minutes", "m");
	else
	if (duration < 1.days)
		return text(duration.total!"hours", "h");
	else
	if (duration < 31.days)
		return text(duration.total!"days", "d");
	else
	if (duration < 365.days)
		return time.formatTimeLoc!"M j"();
	else
		return time.formatTimeLoc!"M 'y"();
}

string formatShortTime(SysTime time, bool shorter)
{
	if (!time.stdTime)
		return "-";

	auto now = Clock.currTime(UTC());
	auto duration = now - time;

	if (duration < dur!"days"(7))
		return formatDuration(duration);
	else
	if (duration < dur!"days"(300))
		if (shorter)
			return time.formatTimeLoc!"M d"();
		else
			return time.formatTimeLoc!"F d"();
	else
		if (shorter)
			return time.formatTimeLoc!"M d, Y"();
		else
			return time.formatTimeLoc!"F d, Y"();
}

string formatDuration(Duration duration)
{
	string ago(string unit)(long amount)
	{
		assert(amount > 0);
		return _!"%d %s ago".format(amount, plural!unit(amount));
	}

	if (duration < 0.seconds)
		return _!"from the future";
	else
	if (duration < 1.seconds)
		return _!"just now";
	else
	if (duration < 1.minutes)
		return ago!"second"(duration.total!"seconds");
	else
	if (duration < 1.hours)
		return ago!"minute"(duration.total!"minutes");
	else
	if (duration < 1.days)
		return ago!"hour"(duration.total!"hours");
	else
	/*if (duration < dur!"days"(2))
		return "yesterday";
	else
	if (duration < dur!"days"(6))
		return formatTimeLoc!"l"(time);
	else*/
	if (duration < 7.days)
		return ago!"day"(duration.total!"days");
	else
	if (duration < 31.days)
		return ago!"week"(duration.total!"weeks");
	else
	if (duration < 365.days)
		return ago!"month"(duration.total!"days" / 30);
	else
		return ago!"year"(duration.total!"days" / 365);
}

string formatLongTime(SysTime time)
{
	return time.formatTimeLoc!"l, d F Y, H:i:s e"();
}

/// Add thousand-separators
string formatNumber(long n)
{
	string s = text(n);
	int digits = 0;
	auto separator = digitGroupingSeparators[currentLanguage];
	foreach_reverse(p; 1..s.length)
		if (++digits % 3 == 0)
			s = s[0..p] ~ separator ~ s[p..$];
	return s;
}

static string truncateString(string s8, int maxLength = 30)
{
	auto encoded = encodeHtmlEntities(s8);
	return `<span class="truncated" style="max-width: ` ~ text(maxLength * 0.6) ~ `em" title="`~encoded~`">` ~ encoded ~ `</span>`;
}

/+
/// Generate a link to set a user preference
string setOptionLink(string name, string value)
{
	return "/set?" ~ encodeUrlParameters(UrlParameters([name : value, "url" : "__URL__", "secret" : userSettings.secret]));
}
+/

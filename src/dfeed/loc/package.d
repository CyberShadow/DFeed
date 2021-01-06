/*  Copyright (C) 2020, 2021  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.loc;

import std.algorithm.iteration;
import std.algorithm.searching;
import std.datetime;
import std.string;

import ae.utils.array;
import ae.utils.json;
import ae.utils.meta;
import ae.utils.time.common;
import ae.utils.time.format;

static import dfeed.loc.english;
static import dfeed.loc.turkish;

enum Language
{
	// English should be first
	english,
	// Sort rest alphabetically
	turkish,
}
Language currentLanguage;

immutable string[enumLength!Language] languageNames = [
	dfeed.loc.english.languageName,
	dfeed.loc.turkish.languageName,
];

immutable string[enumLength!Language] languageCodes = [
	dfeed.loc.english.languageCode,
	dfeed.loc.turkish.languageCode,
];

immutable char[enumLength!Language] digitGroupingSeparators = [
	dfeed.loc.english.digitGroupingSeparator,
	dfeed.loc.turkish.digitGroupingSeparator,
];

static immutable string[][4][enumLength!Language] timeStrings = [
	[
		ae.utils.time.common.WeekdayLongNames,
		ae.utils.time.common.MonthLongNames,
		ae.utils.time.common.WeekdayShortNames,
		ae.utils.time.common.MonthShortNames,
	],
	[
		dfeed.loc.turkish.WeekdayLongNames,
		dfeed.loc.turkish.MonthLongNames,
		dfeed.loc.turkish.WeekdayShortNames,
		dfeed.loc.turkish.MonthShortNames,
	],
];

string _(string s)()
{
	static string[enumLength!Language] translations = [
		s,
		dfeed.loc.turkish.translate(s),
	];
	return translations[currentLanguage];
}

enum pluralMany = 99;

string plural(string unit)(long amount)
{
	final switch (currentLanguage)
	{
		case Language.english:
			return dfeed.loc.english.plural!unit(amount);
		case Language.turkish:
			return dfeed.loc.turkish.plural!unit(amount);
	}
}

auto withLanguage(Language language)
{
	struct WithLanguage
	{
		Language oldLanguage;
		@disable this(this);
		~this() { currentLanguage = oldLanguage; }
	}
	auto oldLanguage = currentLanguage;
	currentLanguage = language;
	return WithLanguage(oldLanguage);
}

Language detectLanguage(string acceptLanguage)
{
	foreach (pref; acceptLanguage.splitter(","))
	{
		auto code = pref.findSplit(";")[0].findSplit("-")[0].strip;
		auto i = languageCodes[].countUntil(code);
		if (i >= 0)
			return cast(Language)i;
	}
	return Language.init;
}

string formatTimeLoc(string timeFormat)(SysTime time)
{
	string s = time.formatTime!timeFormat();
	if (!currentLanguage)
		return s;

	bool[4] needStrings;
	foreach (c; timeFormat)
		switch (c)
		{
			case TimeFormatElement.dayOfWeekName:
				needStrings[0] = true;
				break;
			case TimeFormatElement.monthName:
				needStrings[1] = true;
				break;
			case TimeFormatElement.dayOfWeekNameShort:
				needStrings[2] = true;
				break;
			case TimeFormatElement.monthNameShort:
				needStrings[3] = true;
				break;
			default:
				break;
		}

	string[] sourceStrings, targetStrings;
	foreach (i, b; needStrings)
		if (b)
		{
			sourceStrings ~= timeStrings[Language.init  ][i];
			targetStrings ~= timeStrings[currentLanguage][i];
		}

	string result;
mainLoop:
	while (s.length)
	{
		foreach (i, sourceString; sourceStrings)
			if (s.skipOver(sourceString))
			{
				result ~= targetStrings[i];
				continue mainLoop;
			}
		result ~= s.shift;
	}
	return result;
}

/// List of strings used in dfeed.js.
immutable jsStrings = [
	`Toggle navigation`,
	`Loading message`,
	`Your browser does not support HTML5 pushState.`,
	`Keyboard shortcuts`,
	`Ctrl`,
	`Down Arrow`,
	`Select next message`,
	`Up Arrow`,
	`Select previous message`,
	`Enter / Return`,
	`Open selected message`,
	`Create thread`,
	`Reply`,
	`Mark as unread`,
	`Open link`,
	`Space Bar`,
	`Scroll message / Open next unread message`,
	`(press any key or click to close)`,
	`Draft saved.`,
	`Error auto-saving draft.`,
];

string getJsStrings()
{
	string[enumLength!Language] translations;
	if (!translations[currentLanguage])
	{
		string[string] object;
		foreach (i; RangeTuple!(jsStrings.length))
			object[jsStrings[i]] = _!(jsStrings[i]);
		translations[currentLanguage] = object.toJson();
	}
	return translations[currentLanguage];
}

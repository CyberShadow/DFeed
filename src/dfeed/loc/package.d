/*  Copyright (C) 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import ae.utils.meta;

static import dfeed.loc.english;
static import dfeed.loc.turkish;

enum Language
{
	english,
	turkish,
}
Language currentLanguage;

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

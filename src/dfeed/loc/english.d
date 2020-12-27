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

module dfeed.loc.english;

private string pluralOf(string unit)
{
	switch (unit)
	{
		case "second":
		case "minute":
		case "hour":
		case "day":
		case "week":
		case "month":
		case "year":

		case "thread":
		case "post":
		case "forum post":
		case "subscription":
		case "unread post":
		case "registered user":
		case "visit":
			return unit ~ "s";

		case "new reply":
			return "new replies";

		case "user has created":
			return "users have created";

		default:
			assert(false, "Unknown unit: " ~ unit);
	}
}

string plural(string unit)(long amount)
{
	static immutable unitPlural = pluralOf(unit);
	return amount == 1 ? unit : unitPlural;
}

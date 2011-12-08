/*  Copyright (C) 2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module bitly;

import std.uri;
import std.file;
import std.string;

import ae.net.http.client;

void shortenURL(string url, void delegate(string) handler)
{
	if (std.file.exists("data/bitly.txt"))
		httpGet(
			format(
				"http://api.bitly.com/v3/shorten?%s&longUrl=%s&format=txt&domain=j.mp",
				readText("data/bitly.txt"),
				std.uri.encodeComponent(url)
			), (string shortened) {
				handler(strip(shortened));
			}, (string error) {
				handler(url);
			});
	else
		handler(url);
}

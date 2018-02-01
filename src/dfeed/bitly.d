/*  Copyright (C) 2011, 2012, 2014, 2015, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.bitly;

import std.uri;
import std.file;
import std.string;
import std.exception;

import ae.net.http.client;
import ae.sys.log;

void shortenURL(string url, void delegate(string) handler)
{
	if (urlShortener)
		urlShortener.shorten(url, handler);
	else
		handler(url);
}

// **************************************************************************

private:

class UrlShortener { abstract void shorten(string url, void delegate(string) handler); }
UrlShortener urlShortener;

class Bitly : UrlShortener
{
	static struct Config { string login, apiKey; }
	immutable Config config;
	this(Config config) { this.config = config; }

	Logger log;

	override void shorten(string url, void delegate(string) handler)
	{
		httpGet(
			format(
				"http://api.bitly.com/v3/shorten?login=%s&apiKey=%s&longUrl=%s&format=txt&domain=j.mp",
				config.login,
				config.apiKey,
				std.uri.encodeComponent(url)
			), (string shortened) {
				shortened = shortened.strip();
				enforce(shortened.startsWith("http://"), "Unexpected bit.ly output: " ~ shortened);
				handler(shortened);
			}, (string error) {
				if (!log)
					log = createLogger("bitly");
				log("Error while shortening " ~ url ~ ": " ~ error);

				handler(url);
			});
	}
}

static this()
{
	import dfeed.common : createService;
	urlShortener = createService!Bitly("apis/bitly");
}

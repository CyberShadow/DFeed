/*  Copyright (C) 2011, 2012, 2014, 2015, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.spam.akismet;

import ae.net.http.client;

import dfeed.site;
import dfeed.web.posting;
import dfeed.web.spam;

class Akismet : SpamChecker
{
	struct Config { string key; }
	Config config;
	this(Config config) { this.config = config; }

	override void check(PostProcess process, SpamResultHandler handler)
	{
		if (!config.key)
			return handler(true, "Akismet is not set up");

		string[string] params = [
			"blog"                 : site.proto ~ "://" ~ site.host ~ "/",
			"user_ip"              : process.ip,
			"user_agent"           : process.headers.get("User-Agent", ""),
			"referrer"             : process.headers.get("Referer", ""),
			"comment_author"       : process.draft.clientVars.get("name", ""),
			"comment_author_email" : process.draft.clientVars.get("email", ""),
			"comment_content"      : process.draft.clientVars.get("text", ""),
		];

		return httpPost("http://" ~ config.key ~ ".rest.akismet.com/1.1/comment-check", UrlParameters(params), (string result) {
			if (result == "false")
				handler(true, null);
			else
			if (result == "true")
				handler(false, "Akismet thinks your post looks like spam");
			else
				handler(false, "Akismet error: " ~ result);
		}, (string error) {
			handler(false, "Akismet error: " ~ error);
		});
	}

	override void sendFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
	{
		if (!config.key)
			return handler(true, "Akismet is not set up");

		string[string] params = [
			"blog"                 : site.proto ~ "://" ~ site.host ~ "/",
			"user_ip"              : process.ip,
			"user_agent"           : process.headers.get("User-Agent", ""),
			"referrer"             : process.headers.get("Referer", ""),
			"comment_author"       : process.draft.clientVars.get("name", ""),
			"comment_author_email" : process.draft.clientVars.get("email", ""),
			"comment_content"      : process.draft.clientVars.get("text", ""),
		];

		string[SpamFeedback] names = [ SpamFeedback.spam : "spam", SpamFeedback.ham : "ham" ];
		return httpPost("http://" ~ config.key ~ ".rest.akismet.com/1.1/submit-" ~ names[feedback], UrlParameters(params), (string result) {
			if (result == "Thanks for making the web a better place.")
				handler(true, null);
			else
				handler(false, "Akismet error: " ~ result);
		}, (string error) {
			handler(false, "Akismet error: " ~ error);
		});
	}
}

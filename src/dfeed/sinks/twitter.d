/*  Copyright (C) 2018  Sebastian Wilzbach
 *  Copyright (C) 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.sinks.twitter;

import std.algorithm.iteration;
import std.datetime;
import std.string;

import dfeed.common;
import dfeed.message;

import ae.net.http.client;
import ae.net.http.common;
import ae.net.oauth.common;
import ae.sys.data;

final class TwitterSink : NewsSink
{
	static struct Config
	{
		OAuthConfig oauth;
		string postStatusURL = "https://api.twitter.com/1.1/statuses/update.json";
		string oauthAccessToken;
		string oauthAccessTokenSecret;
		string formatString = "%s by %s: %s";
	}

	this(Config config)
	{
		this.config = config;
		this.session.config = config.oauth;
		this.session.token = config.oauthAccessToken;
		this.session.tokenSecret = config.oauthAccessTokenSecret;
	}

protected:
	override void handlePost(Post post, Fresh fresh)
	{
		if (!fresh)
			return;

		if (post.time < Clock.currTime() - dur!"days"(1))
			return; // ignore posts older than a day old (e.g. StackOverflow question activity bumps the questions)

		if (post.getImportance() < Post.Importance.high)
			return;

		auto rfcPost = cast(Rfc850Post)post;
		if (!rfcPost)
			return;

		tweet(config.formatString.format(
			rfcPost.subject,
			rfcPost.author,
			rfcPost.url,
		));
	}

	void tweet(string message)
	{
		UrlParameters parameters;
		parameters["status"] = message;
		auto request = new HttpRequest;
		//auto queryString = encodeUrlParameters(parameters);
		auto queryString = parameters.pairs.map!(p => session.encode(p.key) ~ "=" ~ session.encode(p.value)).join("&");
		auto baseURL = config.postStatusURL;
		auto fullURL = baseURL ~ "?" ~ queryString;
		request.resource = fullURL;
		request.method = "POST";
		request.headers["Authorization"] = session.prepareRequest(baseURL, "POST", parameters).oauthHeader;
		request.data = [Data([])];
		httpRequest(request, null);
	}

private:
	immutable Config config;
	OAuthSession session;
}

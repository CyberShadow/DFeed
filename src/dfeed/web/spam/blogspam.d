/*  Copyright (C) 2011, 2012, 2014, 2015, 2017, 2018, 2020, 2021  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.spam.blogspam;

import ae.net.http.client;
import ae.sys.data;
import ae.utils.json;

import dfeed.loc;
import dfeed.site;
import dfeed.web.posting;
import dfeed.web.spam;

class BlogSpam : SpamChecker
{
	private string[string] getParams(PostProcess process)
	{
		return [
			"comment"              : process.draft.clientVars.get("text", ""),
			"ip"                   : process.ip,
			"agent"                : process.headers.get("User-Agent", ""),
			"email"                : process.draft.clientVars.get("email", ""),
			"name"                 : process.draft.clientVars.get("name", ""),
			"site"                 : site.proto ~ "://" ~ site.host ~ "/",
			"subject"              : process.draft.clientVars.get("subject", ""),
			"version"              : "DFeed (+https://github.com/CyberShadow/DFeed)",
		];
	}

	override void check(PostProcess process, SpamResultHandler handler)
	{
		auto params = getParams(process);

		return httpPost("http://test.blogspam.net:9999/", DataVec(Data(toJson(params))), "application/json", (string responseText) {
			auto response = responseText.jsonParse!(string[string]);
			auto result = response.get("result", null);
			auto reason = response.get("reason", "no reason given");
			if (result == "OK")
				handler(likelyHam, reason);
			else
			if (result == "SPAM")
				handler(likelySpam, _!"BlogSpam.net thinks your post looks like spam:" ~ " " ~ reason);
			else
			if (result == "ERROR")
				handler(errorSpam, _!"BlogSpam.net error:" ~ " " ~ reason);
			else
				handler(errorSpam, _!"BlogSpam.net unexpected response:" ~ " " ~ result);
		}, (string error) {
			handler(errorSpam, _!"BlogSpam.net error:" ~ " " ~ error);
		});
	}

	override void sendFeedback(PostProcess process, SpamResultHandler handler, SpamFeedback feedback)
	{
		auto params = getParams(process);
		string[SpamFeedback] names = [ SpamFeedback.spam : "spam", SpamFeedback.ham : "ok" ];
		params["train"] = names[feedback];
		return httpPost("http://test.blogspam.net:9999/classify", DataVec(Data(toJson(params))), "application/json", (string responseText) {
			auto response = responseText.jsonParse!(string[string]);
			auto result = response.get("result", null);
			auto reason = response.get("reason", "no reason given");
			if (result == "OK")
				handler(likelyHam, reason);
			else
			if (result == "ERROR")
				handler(errorSpam, _!"BlogSpam.net error:" ~ " " ~ reason);
			else
				handler(errorSpam, _!"BlogSpam.net unexpected response:" ~ " " ~ result);
		}, (string error) {
			handler(errorSpam, _!"BlogSpam.net error:" ~ " " ~ error);
		});
	}
}


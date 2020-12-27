/*  Copyright (C) 2011, 2012, 2014, 2015, 2017, 2018, 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.spam.stopforumspam;

import std.algorithm.searching;
import std.array;
import std.exception;
import std.string;

import ae.net.http.client;

import dfeed.loc;
import dfeed.site;
import dfeed.web.posting;
import dfeed.web.spam;

static import ae.utils.xml; // Issue 7016

class StopForumSpam : SpamChecker
{
	override void check(PostProcess process, SpamResultHandler handler)
	{
		enum DAYS_THRESHOLD = 3; // consider an IP match as a positive if it was last seen at most this many days ago

		auto ip = process.ip;

		if (ip.canFind(':') || ip.split(".").length != 4)
		{
			// Not an IPv4 address, skip StopForumSpam check
			return handler(true, "Not an IPv4 address");
		}

		httpGet("http://api.stopforumspam.org/api?ip=" ~ ip, (string result) {
			import std.datetime;
			import ae.utils.xml;
			import ae.utils.time : parseTime;

			auto xml = new XmlDocument(result);
			auto response = xml["response"];
			if (response.attributes["success"] != "true")
			{
				string error = result;
				auto errorNode = response.findChild("error");
				if (errorNode)
					error = errorNode.text;
				enforce(false, _!"StopForumSpam API error:" ~ " " ~ error);
			}

			if (response["appears"].text == "no")
				handler(true, null);
			else
			{
				auto date = response["lastseen"].text.parseTime!"Y-m-d H:i:s"();
				if (Clock.currTime() - date < dur!"days"(DAYS_THRESHOLD))
					handler(false, format(
						_!"StopForumSpam thinks you may be a spammer (%s last seen: %s, frequency: %s)",
						process.ip, response["lastseen"].text, response["frequency"].text));
				else
					handler(true, null);
			}
		}, (string errorMessage) {
			handler(false, "StopForumSpam error: " ~ errorMessage);
		});
	}
}

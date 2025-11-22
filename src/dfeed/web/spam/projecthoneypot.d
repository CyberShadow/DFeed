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

module dfeed.web.spam.projecthoneypot;

import std.algorithm.mutation;
import std.array;
import std.exception;
import std.string;

import dfeed.loc;
import dfeed.site;
import dfeed.web.posting;
import dfeed.web.spam;

class ProjectHoneyPot : SpamChecker
{
	struct Config { string key; }
	Config config;
	this(Config config) { this.config = config; }

	override void check(PostProcess process, SpamResultHandler handler)
	{
		if (!config.key)
			return handler(certainlyHam, "ProjectHoneyPot is not set up");

		enum DAYS_THRESHOLD  =  7; // consider an IP match as a positive if it was last seen at most this many days ago
		enum SCORE_THRESHOLD = 10; // consider an IP match as a positive if its ProjectHoneyPot score is at least this value

		struct PHPResult
		{
			bool present;
			ubyte daysLastSeen, threatScore, type;
		}

		PHPResult phpCheck(string ip)
		{
			import std.socket;
			string[] sections = split(ip, ".");
			if (sections.length != 4) // IPv6
				return PHPResult(false);
			sections.reverse();
			string addr = ([config.key] ~ sections ~ ["dnsbl.httpbl.org"]).join(".");
			InternetHost ih = new InternetHost;
			if (!ih.getHostByName(addr))
				return PHPResult(false);
			auto resultIP = cast(ubyte[])(&ih.addrList[0])[0..1];
			resultIP.reverse();
			enforce(resultIP[0] == 127, "PHP API error");
			return PHPResult(true, resultIP[1], resultIP[2], resultIP[3]);
		}

		auto result = phpCheck(process.ip);
		with (result)
			if (present && daysLastSeen <= DAYS_THRESHOLD && threatScore >= SCORE_THRESHOLD)
			{
				// Normalize threat score (0-255) to spamicity (0.0-1.0)
				auto spamicity = threatScore / 255.0;
				handler(spamicity, format(
					_!"ProjectHoneyPot thinks you may be a spammer (%s last seen: %d days ago, threat score: %d/255, type: %s)",
					process.ip,
					daysLastSeen,
					threatScore,
					(
						( type == 0      ? ["Search Engine"  ] : []) ~
						((type & 0b0001) ? ["Suspicious"     ] : []) ~
						((type & 0b0010) ? ["Harvester"      ] : []) ~
						((type & 0b0100) ? ["Comment Spammer"] : [])
					).join(", ")));
			}
			else
				handler(likelyHam, null);
	}

}

/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.sources.web.stackoverflow;

import std.string;
import std.file;
import std.conv;
import std.datetime;

import ae.net.http.client;
import ae.utils.json;
import ae.utils.text;

import dfeed.bitly;
import dfeed.common;
import dfeed.sources.web.webpoller;

class StackOverflow : WebPoller
{
	static struct Config
	{
		string tags;
		string key;
		int pollPeriod = 60;
	}

	this(Config config)
	{
		this.config = config;
		super("StackOverflow-" ~ config.tags, config.pollPeriod);
	}

private:
	Config config;

	class Question : Post
	{
		string title;
		string author;
		string url;

		this(string title, string author, string url, SysTime time)
		{
			this.title = title;
			this.author = author;
			this.url = url;
			this.time = time;
		}

		override void formatForIRC(void delegate(string) handler)
		{
			shortenURL(url, (string shortenedURL) {
				handler(format("[StackOverflow] %s asked \"%s\": %s", filterIRCName(author), title, shortenedURL));
			});
		}
	}

protected:
	override void getPosts()
	{
		auto url = "http://api.stackexchange.com/2.2/questions?pagesize=10&order=desc&sort=creation&site=stackoverflow&tagged=" ~ config.tags ~
			(config.key ? "&key=" ~ config.key : "");
		httpGet(url, (string json) {
			if (json == "<html><body><h1>408 Request Time-out</h1>\nYour browser didn't send a complete request in time.\n</body></html>\n")
			{
				log("Server reports request timeout");
				return; // Temporary problem
			}

			if (json.contains("<title>We are Offline</title>"))
			{
				log("Server reports SO is offline");
				return; // Temporary problem
			}

			struct JsonQuestionOwner
			{
				int reputation;
				int user_id;
				string user_type;
				int accept_rate;
				string profile_image;
				string display_name;
				string link;
			}

			struct JsonQuestion
			{
				string[] tags;
				bool is_answered;
				int answer_count, accepted_answer_id, favorite_count;
				int closed_date;
				string closed_reason;
				int bounty_closes_date, bounty_amount;
				string question_timeline_url, question_comments_url, question_answers_url;
				int question_id;
				int locked_date;
				JsonQuestionOwner owner;
				int creation_date, last_edit_date, last_activity_date;
				int up_vote_count, down_vote_count, view_count, score;
				bool community_owned;
				string title, link;
			}

			struct JsonQuestions
			{
				JsonQuestion[] items;
				bool has_more;
				int quota_max, quota_remaining, backoff;
			}

			scope(failure) std.file.write("so-error.txt", json);
			auto data = jsonParse!(JsonQuestions)(json);
			Post[string] r;

			foreach (q; data.items)
				r[text(q.question_id)] = new Question(q.title, q.owner.display_name, format("http://stackoverflow.com/q/%d", q.question_id), SysTime(unixTimeToStdTime(q.creation_date)));

			handlePosts(r);
		}, (string error) {
			handleError(error);
		});
	}
}

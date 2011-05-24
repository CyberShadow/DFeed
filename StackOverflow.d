module StackOverflow;

import std.string;
import std.file;

import WebPoller;

import Team15.Utils;
import Team15.Timing;
import Team15.Http.Json;

const POLL_PERIOD = 15 * TicksPerSecond;

private struct Question
{
	string title;
	string author;
	string url;

	string toString()
	{
		return format("[StackOverflow] %s asked \"%s\": %s", author, title, shortenURL(url));
	}
}

class StackOverflow : WebPoller.WebPoller!(Question)
{
	this(string tags)
	{
		super("StackOverflow", POLL_PERIOD);
		this.tags = tags;
	}

private:
	string tags;

protected:
	override Question[string] getPosts()
	{
		struct JsonQuestionOwner
		{
			int user_id;
			string user_type;
			string display_name;
			int reputation;
			string email_hash;
		}

		struct JsonQuestion
		{
			string[] tags;
			int answer_count, accepted_answer_id, favorite_count;
			string question_timeline_url, question_comments_url, question_answers_url;
			int question_id;
			JsonQuestionOwner owner;
			long creation_date, last_edit_date, last_activity_date;
			int up_vote_count, down_vote_count, view_count, score;
			bool community_owned;
			string title;
		}

		struct JsonQuestions
		{
			int total, page, pagesize;
			JsonQuestion[] questions;
		}

		auto json = download("http://api.stackoverflow.com/1.1/questions?pagesize=10&tagged=" ~ tags ~ (exists("data/stackoverflow.txt") ? "&key=" ~ cast(string)read("data/stackoverflow.txt") : ""), " | gzip -d");
		scope(failure) std.file.write("so-error.txt", json);
		auto data = jsonParse!(JsonQuestions)(json);
		Question[string] r;

		foreach (q; data.questions)
			r[.toString(q.question_id)] = Question(q.title, q.owner.display_name, format("http://stackoverflow.com/q/%d", q.question_id));

		return r;
	}
}

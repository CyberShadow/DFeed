module stackoverflow;

import std.string;
import std.file;
import std.conv;

import ae.utils.cmd;
import ae.utils.json;

import common;
import webpoller;

const POLL_PERIOD = 15;

class StackOverflow : WebPoller
{
	this(string tags, PostHandler handler)
	{
		this.tags = tags;
		super("StackOverflow", POLL_PERIOD, handler);
	}

private:
	string tags;

	class Question : Post
	{
		string title;
		string author;
		string url;

		this(string title, string author, string url)
		{
			this.title = title;
			this.author = author;
			this.url = url;
		}

		override string toString()
		{
			return format("[StackOverflow] %s asked \"%s\": %s", author, title, shortenURL(url));
		}
	}

protected:
	override Post[string] getPosts()
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
			int bounty_closes_date, bounty_amount;
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

		auto gzip = download("http://api.stackoverflow.com/1.1/questions?pagesize=10&tagged=" ~ tags ~ (exists("data/stackoverflow.txt") ? "&key=" ~ cast(string)read("data/stackoverflow.txt") : ""));
		auto json = .run("gzip -d", gzip);
		scope(failure) std.file.write("so-error.txt", json);
		auto data = jsonParse!(JsonQuestions)(json);
		Post[string] r;

		foreach (q; data.questions)
			r[text(q.question_id)] = new Question(q.title, q.owner.display_name, format("http://stackoverflow.com/q/%d", q.question_id));

		return r;
	}
}

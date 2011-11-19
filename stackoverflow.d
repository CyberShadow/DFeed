module stackoverflow;

import std.string;
import std.file;
import std.conv;
import std.datetime;

import ae.net.http.client;
import ae.utils.json;

import bitly;
import common;
import webpoller;

const POLL_PERIOD = 15;

class StackOverflow : WebPoller
{
	this(string tags)
	{
		this.tags = tags;
		super("StackOverflow-" ~ tags, POLL_PERIOD);
	}

private:
	string tags;

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
				handler(format("[StackOverflow] %s asked \"%s\": %s", author, title, shortenedURL));
			});
		}
	}

protected:
	override void getPosts()
	{
		auto url = "http://api.stackoverflow.com/1.1/questions?pagesize=10&tagged=" ~ tags ~
			(exists("data/stackoverflow.txt") ? "&key=" ~ readText("data/stackoverflow.txt") : "");
		httpGet(url, (string json) {
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
				int closed_date;
				string closed_reason;
				int bounty_closes_date, bounty_amount;
				string question_timeline_url, question_comments_url, question_answers_url;
				int question_id;
				JsonQuestionOwner owner;
				int creation_date, last_edit_date, last_activity_date;
				int up_vote_count, down_vote_count, view_count, score;
				bool community_owned;
				string title;
			}

			struct JsonQuestions
			{
				int total, page, pagesize;
				JsonQuestion[] questions;
			}

			scope(failure) std.file.write("so-error.txt", json);
			auto data = jsonParse!(JsonQuestions)(json);
			Post[string] r;

			foreach (q; data.questions)
				r[text(q.question_id)] = new Question(q.title, q.owner.display_name, format("http://stackoverflow.com/q/%d", q.question_id), SysTime(unixTimeToStdTime(q.creation_date)));

			handlePosts(r);
		}, (string error) {
			handleError(error);
		});
	}
}

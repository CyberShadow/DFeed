module webpoller;

import ae.sys.timing;

import std.random;
import std.string;

import common;

/// Periodically polls a resource (e.g. on the web), and announces new posts.
class WebPoller : NewsSource
{
	/// If there are more than LIMIT new posts,
	/// assume a glitch happened and don't announce them.
	enum LIMIT = 5;

	this(string name, int pollPeriod)
	{
		super(name);
		this.pollPeriod = pollPeriod;
	}

	override void start()
	{
		getPosts();
	}

private:
	int pollPeriod;
	bool[string] oldPosts;
	bool first = true;

	void scheduleNextRequest()
	{
		// Use a jitter to avoid making multiple simultaneous resquests
		auto delay = pollPeriod + uniform(-5, 5);
		log(format("Next poll in %d seconds", delay));
		setTimeout(&startNextRequest, TickDuration.from!"seconds"(delay));
	}

	void startNextRequest()
	{
		log("Running...");
		getPosts();
	}

protected:
	void handlePosts(Post[string] posts)
	{
		Post[string] newPosts;
		log(format("Got %d posts", posts.length));
		foreach (id, q; posts)
		{
			if (!first && !(id in oldPosts))
				newPosts[id] = q;
			oldPosts[id] = true;
		}
		first = false;

		if (newPosts.length > LIMIT)
			return handleError("Too many posts, aborting!");

		foreach (id, q; newPosts)
		{
			log(format("Announcing %s", id));
			announcePost(q);
		}

		scheduleNextRequest();
	}

	void handleError(string message)
	{
		log(format("WebPoller error: %s", message));

		scheduleNextRequest();
	}

	/// Asynchronously fetch new posts, and call handlePosts or handleError when done.
	abstract void getPosts();
}

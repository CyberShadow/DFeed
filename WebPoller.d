module WebPoller;

import Team15.Timing;
import Team15.ASockets;
import Team15.Logging;
import Team15.CommandLine;

import std.random;
import std.string;

enum { LIMIT = 5 }

class WebPoller(Post)
{
	this(string name, int pollPeriod)
	{
		this.pollPeriod = pollPeriod;
		log = createLogger(name);
	}

	void start()
	{
		run();
	}

	void delegate(string, bool) handleNotify;

private:
	int pollPeriod;
	bool[string] oldPosts;
	Logger log;
	bool first = true;

	void run()
	{
		log("Running...");
		try
		{
			auto posts = getPosts();
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
				throw new Exception("Too many posts, aborting!");

			foreach (id, q; newPosts)
			{
				log(format("Announcing %s", id));
				if (handleNotify)
					handleNotify(q.toString(), true);
			}
		}
		catch (Object o)
			log(format("WebPoller error: %s", o.toString()));

		auto delay = pollPeriod + (rand()%10-5) * TicksPerSecond;
		log(format("Next poll in %d seconds", delay/TicksPerSecond));
		setTimeout(&run, delay);
	}

protected:
	abstract Post[string] getPosts();
}

static this() { logFormatVersion = 1; }

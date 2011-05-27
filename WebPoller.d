module WebPoller;

import Team15.Timing;
import Team15.ASockets;
import Team15.Logging;
import Team15.CommandLine;

import std.random;
import std.string;

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
	Post[string] oldPosts;
	Logger log;

	void run()
	{
		log("Running...");
		try
		{
			auto posts = getPosts();
			log(format("Got %d posts", posts.length));
			if (oldPosts !is null)
			{
				foreach (id, q; posts)
					if (!(id in oldPosts))
					{
						log(format("Announcing %s", id));
						if (handleNotify)
							handleNotify(q.toString(), true);
					}
			}
			oldPosts = posts;
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

module webpoller;

import ae.sys.timing;
import ae.net.asockets;
import ae.utils.log;

import std.random;
import std.string;

import common;

class WebPoller : PostSource
{
	enum LIMIT = 5;

	this(string name, int pollPeriod, PostHandler postHandler)
	{
		super(postHandler);
		this.pollPeriod = pollPeriod;
		log = createLogger(name);
		run();
	}

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
				postHandler(q);
			}
		}
		catch (Exception e)
			log(format("WebPoller error: %s", e.toString()));

		auto delay = pollPeriod + uniform(-5, 5);
		log(format("Next poll in %d seconds", delay));
		setTimeout(&run, TickDuration.from!"seconds"(delay));
	}

protected:
	abstract Post[string] getPosts();
}

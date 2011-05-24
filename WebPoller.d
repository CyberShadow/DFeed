module WebPoller;

import Team15.Timing;
import Team15.ASockets;

import std.stdio;

class WebPoller(Post)
{
	this(int pollPeriod)
	{
		this.pollPeriod = pollPeriod;
	}

	void start()
	{
		run();
	}

	void delegate(string) handleNotify;

private:
	int pollPeriod;
	Post[string] oldPosts;

	void run()
	{
		try
		{
			auto posts = getPosts();
			if (oldPosts !is null)
			{
				foreach (id, q; posts)
					if (!(id in oldPosts))
						if (handleNotify)
							handleNotify(q.toString());
			}
			oldPosts = posts;
		}
		catch (Object o)
			writefln("WebPoller error: %s", o.toString());
		setTimeout(&run, pollPeriod);
	}

protected:
	abstract Post[string] getPosts();
}

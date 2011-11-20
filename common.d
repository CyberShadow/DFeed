module common;

import ae.utils.log;
import std.datetime;

bool quiet;

Logger createLogger(string name)
{
	return quiet ? new FileLogger(name) : new FileAndConsoleLogger(name);
}

// ***************************************************************************

abstract class Post
{
	/// Asynchronously summarise this post to a single line, ready to be sent to IRC
	abstract void formatForIRC(void delegate(string) handler);

	/// Only "important" posts are sent to IRC
	bool isImportant() { return true; }

	this()
	{
		time = Clock.currTime();
	}

	SysTime time;
}

abstract class NewsSource
{
	this(string name)
	{
		this.name = name;
		log = createLogger(name);
		newsSources[name] = this;
	}

	abstract void start();

protected:
	Logger log;

public:
	string name;
}

abstract class NewsSink
{
	this()
	{
		newsSinks ~= this;
	}

	abstract void handlePost(Post p);
}

private NewsSource[string] newsSources;
private NewsSink[] newsSinks;

void startNewsSources()
{
	foreach (source; newsSources)
		source.start();
}

void announcePost(Post p)
{
	foreach (sink; newsSinks)
		sink.handlePost(p);
}

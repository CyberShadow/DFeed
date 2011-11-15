module common;

import ae.utils.log;

bool quiet;

Logger createLogger(string name)
{
	return quiet ? new FileLogger(name) : new FileAndConsoleLogger(name);
}

// ***************************************************************************

abstract class Post
{
}

alias void delegate(Post) PostHandler;

abstract class PostSource
{
	this(PostHandler postHandler)
	{
		this.postHandler = postHandler;
	}

protected:
	PostHandler postHandler;
}

/*  Copyright (C) 2011  Vladimir Panteleev <vladimir@thecybershadow.net>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module common;

import ae.sys.log;
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

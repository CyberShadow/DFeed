/*  Copyright (C) 2011, 2012, 2014  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.datetime;

import ae.sys.log;
import ae.net.shutdown;

alias quiet = ae.sys.log.quiet;

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
	abstract void stop();

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

	addShutdownHandler({
		foreach (source; newsSources)
			source.stop();
	});
}

void announcePost(Post p)
{
	foreach (sink; newsSinks)
		sink.handlePost(p);
}

// ***************************************************************************

/// Formatting codes inserted into names to disrupt IRC highlight.
enum ircHighlightBreaker = "\u200b"; // zero-width space

/// Filter a name in an announcement to avoid an IRC highlight.
string filterIRCName(string name)
{
	import std.string;
	import std.algorithm;
	return name.split(" ").map!(s => s[0..$/2] ~ ircHighlightBreaker ~ s[$/2..$]).join(" ");
}

unittest
{
	assert(filterIRCName("Vladimir Panteleev") == "Vlad" ~ ircHighlightBreaker ~ "imir Pant" ~ ircHighlightBreaker ~ "eleev");
}

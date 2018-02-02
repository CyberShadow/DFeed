/*  Copyright (C) 2011, 2012, 2014, 2015, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.common;

import std.datetime;
public import std.typecons;

import ae.sys.log;
import ae.net.shutdown;

alias quiet = ae.sys.log.quiet;

// ***************************************************************************

abstract class Post
{
	/// Asynchronously summarise this post to a single line, ready to be sent to IRC.
	abstract void formatForIRC(void delegate(string) handler);

	enum Importance
	{
		/// Replies to threads, general activity.
		/// Should only be shown in "all activity" feeds.
		low,

		/// Suitable to be announced on general feeds.
		normal,

		/// Project announcements and other important posts.
		high,
	}

	Importance getImportance() { return Importance.normal; }

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

alias Fresh = Flag!q{Fresh};

abstract class NewsSink
{
	this()
	{
		newsSinks ~= this;
	}

	abstract void handlePost(Post p, Fresh fresh);
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

void announcePost(Post p, Fresh fresh)
{
	foreach (sink; newsSinks)
		sink.handlePost(p, fresh);
}

// ***************************************************************************

/// Some zero-width control/formatting sequence codes inserted into names
/// to disrupt IRC highlight.
enum ircHighlightBreaker = "\u200E"; // LEFT-TO-RIGHT MARK

/// Filter a name in an announcement to avoid an IRC highlight.
string filterIRCName(string name)
{
	import std.algorithm;
	import std.array;
	import std.conv;
	import std.string;

	name = name
		.to!dstring
		.split(" "d)
		.map!(s =>
			s.length < 2
			?
				s
			:
				s[0..$/2] ~ ircHighlightBreaker ~ s[$/2..$]
		)
		.join(" "d)
		.to!string;

	// Split additional keywords
	foreach (word; ["Cyber"])
		if (name.indexOf(word) >= 0)
			name = name.replace(word, word[0..$/2] ~ ircHighlightBreaker ~ word[$/2..$]);

	return name;
}

unittest
{
	assert(filterIRCName("Vladimir Panteleev") == "Vlad" ~ ircHighlightBreaker ~ "imir Pant" ~ ircHighlightBreaker ~ "eleev");
	assert(filterIRCName("CyberShadow") == "Cy" ~ ircHighlightBreaker ~ "ber" ~ ircHighlightBreaker ~ "Shadow");
	assert(filterIRCName("Rémy") == "Ré" ~ ircHighlightBreaker ~ "my");
}

// ***************************************************************************

import ae.utils.sini;
import std.file;
import std.path;

template services(C)
{
	C[string] services;
}

/// Create a Class instance if the corresponding .ini file exists.
Class createService(Class)(string configName)
{
	auto fn = "config/" ~ configName ~ ".ini";
	if (fn.exists)
		return new Class(loadIni!(Class.Config)(fn));
	return null;
}

/// Create one instance of Class for each .ini configuration file
/// found in the specified config subdirectory.
void createServices(Class, Args...)(string configDir, Args args)
{
	auto dir = "config/" ~ configDir;
	if (!dir.exists)
		return;
	foreach (de; dir.dirEntries("*.ini", SpanMode.breadth))
	{
		auto config = loadIni!(Class.Config)(de.name);
		services!Class[de.baseName.stripExtension] = new Class(config, args);
	}
}

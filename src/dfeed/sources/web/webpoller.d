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

module dfeed.sources.web.webpoller;

import ae.sys.timing;
import ae.utils.aa;

import std.algorithm;
import std.random;
import std.string;

import dfeed.common;

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

	override void stop()
	{
		if (timerTask)
			clearTimeout(timerTask);
		else
			stopping = true;
	}

private:
	int pollPeriod;
	bool[string] oldPosts;
	bool first = true;
	bool stopping;
	TimerTask timerTask;

	void scheduleNextRequest()
	{
		if (stopping) return;

		// Use a jitter to avoid making multiple simultaneous requests
		auto delay = pollPeriod + uniform(-5, 5);
		log(format("Next poll in %d seconds", delay));
		timerTask = setTimeout(&startNextRequest, delay.seconds);
	}

	void startNextRequest()
	{
		timerTask = null;
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

		auto newPostList = newPosts.pairs();
		newPostList.sort!`a.value.time < b.value.time`();
		foreach (pair; newPostList)
		{
			log(format("Announcing %s", pair.key));
			announcePost(pair.value, Fresh.yes);
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

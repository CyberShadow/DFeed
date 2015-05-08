/*  Copyright (C) 2011, 2012, 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module mldownload;

import std.getopt;
import std.string;
import std.regex;

import ae.net.asockets;
import ae.net.http.client;
import ae.utils.gzip;
import ae.sys.data;
import ae.sys.log;
import ae.sys.timing;

import common;
import database;
import messagedb;
import message;

bool update;
MessageDBSink sink;
MLDownloader downloader;

int flushInterval = 50;

class MLDownloader : NewsSource
{
	bool stopping;

	this()
	{
		super("ML-Downloader");
	}

	override void start()
	{
		foreach (list; ["dmd-beta", "dmd-concurrency", "dmd-internals", "phobos", "d-runtime"])
			downloadList(list);
	}

	override void stop()
	{
		stopping = true;
	}

	void downloadList(string list)
	{
		if (stopping) return;
		httpGet("http://lists.puremagic.com/pipermail/" ~ list ~ "/",
			(string html)
			{
				log("Got list index: " ~ list);
				auto re = regex(`<A href="(\d+-\w+\.txt\.gz)">`);
				foreach (line; splitLines(html))
				{
					auto m = match(line, re);
					if (!m.empty)
						downloadFile(list, m.captures[1]);
				}
			},
			(string error)
			{
				log("Error downloading list " ~ list ~ ": " ~ error);
				setTimeout({ downloadList(list); }, 10.seconds);
			});
	}

	void downloadFile(string list, string fn)
	{
		if (stopping) return;
		auto url = "http://lists.puremagic.com/pipermail/" ~ list ~ "/" ~ fn;
		httpGet(url,
			(Data data)
			{
				log("Got %s/%s".format(list, fn));
				scope(failure) std.file.write("errorfile", data.contents);
				auto text = cast(string)(uncompress(data).contents).idup;
				text = text[text.indexOf('\n')+1..$]; // skip first From line
				auto fromline = regex("\n\nFrom .* at .*  \\w\\w\\w \\w\\w\\w [\\d ]\\d \\d\\d:\\d\\d:\\d\\d \\d\\d\\d\\d\n");
				foreach (msg; splitter(text, fromline))
				{
					msg = "List-ID: " ~ list ~ "\n" ~ msg;
					scope(failure) std.file.write("errormsg", msg);
					auto post = new Rfc850Post(msg);
					foreach (int n; query!"SELECT COUNT(*) FROM `Posts` WHERE `ID` = ?".iterate(post.id))
						if (n == 0)
						{
							log("Found new post: " ~ post.id);
							announcePost(post);
						}
						else if (update)
						{
							log("Updating post: " ~ post.id);
							sink.updatePost(post);
						}
					if (flushTransactionEvery(flushInterval))
						log("Transaction flushed");
				}
			},
			(string error)
			{
				log("Error downloading file " ~ fn ~ " on list " ~ list ~ ": " ~ error);
				setTimeout({ downloadFile(list, fn); }, 10.seconds);
			});
	}
}

void main(string[] args)
{
	getopt(args,
		"u|update", &update,
		"flush-every", &flushInterval,
	);

	sink = new MessageDBSink();
	downloader = new MLDownloader();

	startNewsSources();

	mixin(DB_TRANSACTION);
	socketManager.loop();
}

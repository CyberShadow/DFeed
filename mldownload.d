module mldownload;

import std.getopt;
import std.string;
import std.regex;

import ae.net.asockets;
import ae.net.http.client;
import ae.utils.gzip;
import ae.sys.data;
import ae.sys.log;

import common;
import database;
import messagedb;
import rfc850;

class MLDownloader : NewsSource
{
	this()
	{
		super("ML-Downloader");
	}

	override void start()
	{
		foreach (list; ["dmd-beta", "dmd-concurrency", "dmd-internals", "phobos", "d-runtime"])
			downloadList(list);
	}

	void downloadList(string list)
	{
		httpGet("http://lists.puremagic.com/pipermail/" ~ list ~ "/",
			(string html)
			{
				log("Got list index: " ~ list);
				auto re = regex(`<A href="(\d+-\w+\.txt\.gz)">`);
				foreach (line; splitLines(html))
				{
					auto m = match(line, re);
					if (!m.empty)
					{
						auto fn = m.captures[1];
						auto url = "http://lists.puremagic.com/pipermail/" ~ list ~ "/" ~ fn;
						httpGet(url,
							(Data data)
							{
								scope(failure) std.file.write("errorfile", data.contents);
								auto text = cast(string)(uncompress(data).contents).idup;
								text = text[text.indexOf('\n')+1..$]; // skip first From line
								auto fromline = regex("\n\nFrom .* at .*  \\w\\w\\w \\w\\w\\w \\d\\d \\d\\d:\\d\\d:\\d\\d \\d\\d\\d\\d\n");
								foreach (msg; splitter(text, fromline))
								{
									msg = "List-ID: " ~ list ~ "\n" ~ msg;
									scope(failure) std.file.write("errormsg", msg);
									auto post = new Rfc850Post(msg);
									foreach (int n; query("SELECT COUNT(*) FROM `Posts` WHERE `ID` = ?").iterate(post.id))
										if (n == 0)
										{
											log("Found new post: " ~ post.id);
											announcePost(post);
										}
								}
							}, null);
					}
				}
			}, null);
	}
}

void main(string[] args)
{
	getopt(args,
		"q|quiet", &common.quiet);

	new MessageDBSink();
	auto downloader = new MLDownloader();

	startNewsSources();

	db.exec("BEGIN"); allowTransactions = false;
	socketManager.loop();
	downloader.log("Committing...");
	db.exec("COMMIT");
}

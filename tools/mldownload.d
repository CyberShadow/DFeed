module mldownload;

import news_sources.mldownloader;

import std.getopt;
import ae.net.asockets;
import ae.sys.log;

import common;
import database;
import messagedb;
import message;

void main(string[] args)
{
	getopt(args,
		"u|update", &update);

	sink = new MessageDBSink();
	downloader = new MLDownloader();

	startNewsSources();

	db.exec("BEGIN"); allowTransactions = false;
	socketManager.loop();
	downloader.log("Committing...");
	db.exec("COMMIT");
}

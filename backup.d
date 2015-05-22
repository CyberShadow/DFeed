/*  Copyright (C) 2011, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module backup;

import std.datetime;
import std.file;
import std.functional;
import std.process;

import ae.net.shutdown;
import ae.sys.file;
import ae.sys.log;
import ae.sys.timing;
import ae.utils.time;

import database;

Logger log;

static this()
{
	log = createLogger("Backup");
	auto backupTask = setInterval(toDelegate(&checkBackup), 1.minutes);
	addShutdownHandler({ backupTask.cancel(); });
}

void checkBackup()
{
	auto now = Clock.currTime();
	if (now.hour == 0 && now.minute == 0)
		runBackup();
}

enum backupDir = "data/backup/";
enum dataFile = "data/dfeed.s3db";
enum lastFile = dataFile ~ ".last";
enum thisFile = dataFile ~ ".this";
enum baseFile = backupDir ~ "base.s3db";

void runBackup()
{
	if (transactionDepth)
	{
		log("Transaction in progress, delaying backup.");
		setTimeout(toDelegate(&runBackup), 1.minutes);
		return;
	}

	log("Starting backup.");

	if (!baseFile.exists)
	{
		log("Creating base backup.");
		ensurePathExists(baseFile);
		atomicCopy(dataFile, baseFile);
	}
	else
	{
		auto base = lastFile.exists ? lastFile : baseFile;
		log("Using " ~ base ~ " as base file.");

		log("Copying database");
		// No locks required as this will run in the main thread and block DB access.
		copy(dataFile, thisFile);

		auto deltaFile = backupDir ~ "dfeed-" ~ Clock.currTime.formatTime!`Ymd-His` ~ ".vcdiff";
		log("Creating delta file: " ~ deltaFile);

		auto deltaTmpFile = deltaFile ~ ".tmp";
		auto pid = spawnProcess(["xdelta3", "-e", "-s", base, thisFile, deltaTmpFile]);
		enforce(pid.wait() == 0, "xdelta3 failed.");

		log("Delta file created.");
		rename(deltaTmpFile, deltaFile);
		rename(thisFile, lastFile);
	}

	log("Backup complete.");
}

debug(BACKUP_MAIN)
void main()
{
	runBackup();
}

/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Performance logging.
module dfeed.web.web.perf;

import ae.sys.log;

enum measurePerformance = true;

static if (is(typeof({import std.datetime.stopwatch;})))
{
	import std.datetime.stopwatch;
	alias StopWatch = std.datetime.stopwatch.StopWatch;
	Duration readStopwatch(ref StopWatch sw) { return sw.peek(); }
}
else
	Duration readStopwatch(ref StopWatch sw) { return sw.peek().msecs.msecs; }

static if (measurePerformance) Logger perfLog;

enum MeasurePerformanceMixin =
q{
	static if (measurePerformance)
	{
		StopWatch performanceSW;
		performanceSW.start();
		scope(success)
		{
			performanceSW.stop();
			perfLog(PERF_SCOPE ~ ": " ~ text(performanceSW.readStopwatch));
		}
	}
};

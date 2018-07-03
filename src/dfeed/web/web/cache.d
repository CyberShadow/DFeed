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

/// Some cached data.
module dfeed.web.web.cache;

import dfeed.database;
import dfeed.sinks.cache;
import dfeed.web.web.perf;

int[string] getThreadCounts()
{
	enum PERF_SCOPE = "getThreadCounts"; mixin(MeasurePerformanceMixin);
	int[string] threadCounts;
	foreach (string group, int count; query!"SELECT `Group`, COUNT(*) FROM `Threads` GROUP BY `Group`".iterate())
		threadCounts[group] = count;
	return threadCounts;
}

int[string] getPostCounts()
{
	enum PERF_SCOPE = "getPostCounts"; mixin(MeasurePerformanceMixin);
	int[string] postCounts;
	foreach (string group, int count; query!"SELECT `Group`, COUNT(*) FROM `Groups`  GROUP BY `Group`".iterate())
		postCounts[group] = count;
	return postCounts;
}

Cached!(int[string]) threadCountCache, postCountCache;

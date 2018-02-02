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

module dfeed.sinks.cache;

import dfeed.common;
import dfeed.database;

version(Posix) import ae.sys.signals;

int dbVersion = 1;

/// Fake sink used only to invalidate the cache on new data.
final class CacheSink : NewsSink
{
	override void handlePost(Post post, Fresh fresh)
	{
		dbVersion++;
	}
}

struct Cached(T)
{
	int cacheVersion;
	T cachedData;

	T opCall(lazy T dataSource)
	{
		if (cacheVersion != dbVersion)
		{
			cachedData = dataSource;
			cacheVersion = dbVersion;
			debug(NOCACHE) cacheVersion = -1;
		}
		return cachedData;
	}
}

/// Clears the whole set when the cache is invalidated, to save memory
struct CachedSet(K, T)
{
	int cacheVersion;
	T[K] cachedData;

	T opCall(K key, lazy T dataSource)
	{
		if (cacheVersion != dbVersion)
		{
			cachedData = null;
			cacheVersion = dbVersion;
		}

		auto pdata = key in cachedData;
		if (pdata)
			return *pdata;
		else
			return cachedData[key] = dataSource;
	}
}

static this()
{
	new CacheSink();

	version(Posix) addSignalHandler(SIGHUP, { dbVersion++; });
}

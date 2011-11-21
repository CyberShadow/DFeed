module cache;

import common;
import database;

int dbVersion = 1;

final class CacheSink : NewsSink
{
	override void handlePost(Post post)
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
}

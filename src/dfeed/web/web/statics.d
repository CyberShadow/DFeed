/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2021  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Handling of static files and resources.
module dfeed.web.web.statics;

import core.time : MonoTime, seconds;

import std.algorithm.comparison : max;
import std.algorithm.iteration : map, reduce;
import std.algorithm.searching : endsWith, canFind;
import std.array : replace, split;
import std.conv : to, text;
import std.datetime.systime : SysTime;
import std.exception : enforce;
import std.file : exists;
import std.format : format;
import std.path : buildNormalizedPath, dirName, stripExtension, extension;
import std.regex : replaceAll, replaceFirst;
static import std.file;
import std.regex : Regex, matchAll;

import ae.net.http.responseex : HttpResponseEx;
import ae.sys.data : Data, DataVec;
import ae.utils.meta : isDebug;
import ae.utils.regex : re;

import dfeed.web.web.config : config;

/// Caching wrapper
SysTime timeLastModified(string path)
{
	static if (is(MonoTimeImpl!(ClockType.coarse)))
		alias CoarseTime = MonoTimeImpl!(ClockType.coarse);
	else
		alias CoarseTime = MonoTime;

	static SysTime[string] cache;
	static CoarseTime cacheTime;

	enum expiration = isDebug ? 1.seconds : 5.seconds;

	auto now = CoarseTime.currTime();
	if (now - cacheTime > expiration)
	{
		cacheTime = now;
		cache = null;
	}

	auto pcache = path in cache;
	if (pcache)
		return *pcache;
	return cache[path] = std.file.timeLastModified(path);
}

string staticPath(string path)
{
	auto url = "/static/" ~ text(timeLastModified("web/static" ~ path).stdTime) ~ path;
	if (config.staticDomain !is null)
		url = "//" ~ config.staticDomain ~ url;
	return url;
}

string optimizedPath(string base, string resource)
{
	debug
		return resource;
	else
	{
		string optimizedResource = resource.stripExtension ~ ".min" ~ resource.extension;
		auto origPath = base ~ resource;
		auto optiPath = base ~ optimizedResource;
		if (exists(origPath) && exists(optiPath) && timeLastModified(optiPath) >= timeLastModified(origPath))
			return optimizedResource;
		else
			return resource;
	}
}

HttpResponseEx serveFile(HttpResponseEx response, string path)
{
	response.cacheForever();
	return response.serveFile(optimizedPath("web/static/", path), "web/static/");
}

// ***********************************************************************

string createBundles(string page, Regex!char re)
{
	string[] paths;
	foreach (m; page.matchAll(re))
		paths ~= m.captures[1];
	auto maxTime = paths.map!(path => path[8..26].to!long).reduce!max;
	string bundleUrl = "/static-bundle/%d/%-(%s+%)".format(maxTime, paths.map!(path => path[27..$]));
	int index;
	page = page.replaceAll!(captures => index++ ? null : captures[0].replace(captures[1], bundleUrl))(re);
	return page;
}

HttpResponseEx makeBundle(string time, string url)
{
	static struct Bundle
	{
		string time;
		HttpResponseEx response;
	}
	static Bundle[string] cache;

	if (url !in cache || cache[url].time != time || isDebug)
	{
		auto bundlePaths = url.split("+");
		enforce(bundlePaths.length > 0, "Empty bundle");
		HttpResponseEx bundleResponse;
		foreach (n, bundlePath; bundlePaths)
		{
			auto pathResponse = new HttpResponseEx;
			serveFile(pathResponse, bundlePath);
			assert(pathResponse.data.length == 1);
			if (bundlePath.endsWith(".css"))
			{
				auto oldText = cast(string)pathResponse.data[0].contents;
				auto newText = fixCSS(oldText, bundlePath, n == 0);
				if (oldText !is newText)
					pathResponse.data = DataVec(Data(newText));
			}
			if (!bundleResponse)
				bundleResponse = pathResponse;
			else
				bundleResponse.data ~= pathResponse.data[];
		}
		cache[url] = Bundle(time, bundleResponse);
	}
	return cache[url].response.dup;
}

string fixCSS(string css, string path, bool first)
{
	css = css.replaceFirst(re!(`@charset "utf-8";`, "i"), ``);
	if (first)
		css = `@charset "utf-8";` ~ css;
	css = css.replaceAll!(captures =>
		captures[2].canFind("//")
		? captures[0]
		: captures[0].replace(captures[2], staticPath(buildNormalizedPath(dirName("/" ~ path), captures[2]).replace(`\`, `/`)))
	)(re!`\burl\(('?)(.*?)\1\)`);
	return css;
}


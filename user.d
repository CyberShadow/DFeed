module user;

import std.string;

struct User
{
	// TODO: database backing for registered users

	string[string] cookies, newCookies;

	this(string cookieHeader)
	{
		auto segments = cookieHeader.split("; ");
		foreach (segment; segments)
		{
			auto p = segment.indexOf('=');
			if (p > 0)
			{
			    string name = segment[0..p];
			    if (name.startsWith("dfeed_"))
					cookies[name[6..$]] = segment[p+1..$];
			}
		}
	}

	string opIndex(string name)
	{
		auto pNewCookie = name in newCookies;
		if (pNewCookie)
			return *pNewCookie;
		else
			return cookies[name];
	}

	string get(string name, string defaultValue)
	{
		auto pCookie = name in newCookies;
		if (pCookie)
			return *pCookie;
		pCookie = name in cookies;
		if (pCookie)
			return *pCookie;
		return defaultValue;
	}

	string opIndexAssign(string value, string name)
	{
		return newCookies[name] = value;
	}

	string[] getCookies()
	{
		string[] result;
		foreach (name, value; newCookies)
		{
			if (name in cookies && cookies[name] == value)
				continue;

			// TODO
			result ~= "dfeed_" ~ name ~ "=" ~ value ~ "; Expires=Wed, 09 Jun 2021 10:18:14 GMT";
		}
		return result;
	}
}

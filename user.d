module user;

import std.string;
import std.exception;
import std.base64;
import ae.sys.data;
import ae.utils.zlib;

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

	bool opIn_r(string name)
	{
		return (name in newCookies) || (name in cookies);
	}

	string opIndex(string name)
	{
		auto pNewCookie = name in newCookies;
		if (pNewCookie)
			return *pNewCookie;
		else
			return cookies[name];
	}

	string opIndexAssign(string value, string name)
	{
		return newCookies[name] = value;
	}

	string[] getCookies()
	{
		encodeReadPosts();

		string[] result;
		foreach (name, value; newCookies)
		{
			if (name in cookies && cookies[name] == value)
				continue;

			// TODO Expires
			result ~= "dfeed_" ~ name ~ "=" ~ value ~ "; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Path=/";
		}
		return result;
	}

	// ***********************************************************************

	Data* readPosts;
	bool readPostsDirty;

	void needReadPosts()
	{
		if (!readPosts)
		{
			auto b64 = get("readposts", null);
			if (b64)
			{
				auto zcode = Base64.decode(b64);
				readPosts = [uncompress(Data(zcode))].ptr;
			}
			else
				readPosts = new Data();
		}
	}

	void encodeReadPosts()
	{
		if (readPosts && readPosts.length && readPostsDirty)
		{
			auto b64 = Base64.encode(cast(ubyte[])compress(*readPosts, 1).contents);
			newCookies["readposts"] = assumeUnique(b64);
		}
	}

	bool isRead(size_t post)
	{
		needReadPosts();
		auto pos = post/8;
		if (pos >= readPosts.length)
			return false;
		else
			return ((cast(ubyte[])readPosts.contents)[pos] & (1 << (post % 8))) != 0;
	}

	void setRead(size_t post, bool value)
	{
		needReadPosts();
		auto pos = post/8;
		if (pos >= readPosts.length)
		{
			if (value)
				readPosts.length = pos+1;
			else
				return;
		}
		ubyte mask = cast(ubyte)(1 << (post % 8));
		assert(pos < readPosts.length);
		auto pbyte = (cast(ubyte*)readPosts.ptr) + pos;
		if (value)
			*pbyte = *pbyte | mask;
		else
			*pbyte = *pbyte & ~mask;
		readPostsDirty = true;
	}
}

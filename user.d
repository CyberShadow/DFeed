/*  Copyright (C) 2011, 2012, 2013, 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module user;

import std.functional;
import std.string;
import std.exception;
import std.base64;
import ae.net.shutdown;
import ae.sys.data;
import ae.sys.log;
import ae.sys.timing;
import ae.utils.text;
import ae.utils.zlib;

enum SettingType
{
	server,
	client,
	session,
}

abstract class User
{
	abstract string get(string name, string defaultValue, SettingType settingType);
	abstract void set(string name, string value, SettingType settingType);
	abstract void remove(string name, SettingType settingType);
	abstract string[] save();

	abstract void logIn(string username, string password);
	abstract void logOut();
	abstract void register(string username, string password);
	abstract bool isLoggedIn();

	enum Level : int
	{
		guest          =   0, /// Default user level
		hasRawLink     =   1, /// Get a clickable "raw post" link.
		canDeletePosts = 100, /// Can delete posts locally
	}

	string getName() { return null; }
	Level getLevel() { return Level.init; }

protected:
	/// Save misc data to string settings
	final void finalize()
	{
		flushReadPosts();
	}

	// ***********************************************************************

	void getReadPosts()
	in  { assert(!this.readPosts); }
	out { assert( this.readPosts); }
	body
	{
		auto b64 = get("readposts", null, SettingType.server);
		if (b64.length)
		{
			// Temporary hack to catch Phobos bug
			ubyte[] zcode;

			enum advice = "Try clearing your browser's cookies. Create an account to avoid repeated incidents.";

			try
				zcode = Base64.decode(b64);
			catch
			{
				import std.file; write("bad-base64.txt", b64);
				throw new Exception("Malformed Base64 in read post history cookie. " ~ advice);
			}

			try
				readPosts = [uncompress(Data(zcode))].ptr;
			catch (ZlibException e)
			{
				import std.file; write("bad-zlib.z", zcode);
				throw new Exception("Malformed deflated data in read post history cookie (" ~ e.msg ~ "). " ~ advice);
			}
		}
		else
			readPosts = new Data();
	}

	static string encodeReadPosts(Data* readPosts)
	{
		auto b64 = Base64.encode(cast(ubyte[])compress(*readPosts, 1).contents);
		return assumeUnique(b64);
	}

	void saveReadPosts()
	in  { assert(readPosts && readPosts.length && readPostsDirty); }
	body
	{
		set("readposts", encodeReadPosts(readPosts), SettingType.server);
	}

	Data* readPosts;
	bool readPostsDirty;

final:
	void needReadPosts()
	{
		if (!readPosts)
			getReadPosts();
	}

	void flushReadPosts()
	{
		if (readPosts && readPosts.length && readPostsDirty)
		{
			saveReadPosts();
			readPostsDirty = false;
		}
	}

	public bool isRead(size_t post)
	{
		needReadPosts();
		auto pos = post/8;
		if (pos >= readPosts.length)
			return false;
		else
			return ((cast(ubyte[])readPosts.contents)[pos] & (1 << (post % 8))) != 0;
	}

	public void setRead(size_t post, bool value)
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

// ***************************************************************************

class GuestUser : User
{
	string[string] cookies, newCookies;
	SettingType[string] settingTypes;

	this(string cookieHeader)
	{
		auto segments = cookieHeader.split(";");
		foreach (segment; segments)
		{
			segment = segment.strip();
			auto p = segment.indexOf('=');
			if (p > 0)
			{
			    string name = segment[0..p];
			    if (name.startsWith("dfeed_"))
					cookies[name[6..$]] = segment[p+1..$];
			}
		}
	}

	override string get(string name, string defaultValue, SettingType settingType)
	{
		auto pCookie = name in newCookies;
		if (pCookie)
			return *pCookie;
		pCookie = name in cookies;
		if (pCookie)
			return *pCookie;
		return defaultValue;
	}

	override void set(string name, string value, SettingType settingType)
	{
		newCookies[name] = value;
		settingTypes[name] = settingType;
	}

	override void remove(string name, SettingType settingType)
	{
		newCookies[name] = null;
		settingTypes[name] = settingType;
	}

	override string[] save()
	{
		finalize();

		string[] result;
		foreach (name, value; newCookies)
		{
			if (value is null)
			{
				if (name !in cookies)
					continue;

				result ~= "dfeed_" ~ name ~ "=deleted; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/";
			}
			else
			{
				if (name in cookies && cookies[name] == value)
					continue;

				if (settingTypes[name] == SettingType.session)
					result ~= "dfeed_" ~ name ~ "=" ~ value ~ "; Path=/";
				else
					// TODO Expires
					result ~= "dfeed_" ~ name ~ "=" ~ value ~ "; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Path=/";
			}
		}
		return result;
	}

	static string encryptPassword(string password)
	{
		// TODO: use bcrypt()
		enforce(config.salt.length, "Salt not set!");
		import std.digest.md;
		return (password ~ config.salt).md5Of().toHexString!(LetterCase.lower)().idup; // Issue 9279
	}

	override void logIn(string username, string password)
	{
		foreach (string session; query!"SELECT `Session` FROM `Users` WHERE `Username` = ? AND `Password` = ?".iterate(username, encryptPassword(password)))
		{
			set("session", session, SettingType.client);
			return;
		}
		throw new Exception("No such username/password combination");
	}

	override void register(string username, string password)
	{
		enforce(username.length, "Please enter a username");
		enforce(username.length < 32, "Username too long");
		enforce(password.length < 64, "Password too long");

		// Create user
		auto session = randomString();
		query!"INSERT INTO `Users` (`Username`, `Password`, `Session`) VALUES (?, ?, ?)".exec(username, encryptPassword(password), session);

		// Copy cookies to database
		auto user = new RegisteredUser(username);
		foreach (name, value; cookies)
			user.set(name, value, SettingType.server);
		user.save();

		// Log them in
		this.set("session", session, SettingType.client);
	}

	override void logOut() { throw new Exception("Not logged in"); }
	override bool isLoggedIn() { return false; }
}

// ***************************************************************************

import database;

final class RegisteredUser : GuestUser
{
	string[string] settings, newSettings;
	string username;
	Level level;

	this(string username, string cookieHeader = null, Level level = Level.init)
	{
		super(cookieHeader);
		this.username = username;
		this.level = level;
	}

	override string get(string name, string defaultValue, SettingType settingType)
	{
		if (settingType != SettingType.server)
			return super.get(name, defaultValue, settingType);

		auto pSetting = name in newSettings;
		if (pSetting)
			return *pSetting;

		pSetting = name in settings;
		string value;
		if (pSetting)
			value = *pSetting;
		else
		{
			foreach (string v; query!"SELECT `Value` FROM `UserSettings` WHERE `User` = ? AND `Name` = ?".iterate(username, name))
				value = v;
			settings[name] = value;
		}

		return value ? value : defaultValue;
	}

	override void set(string name, string value, SettingType settingType)
	{
		if (settingType == SettingType.server)
			newSettings[name] = value;
		else
			super.set(name, value, settingType);
	}

	override void remove(string name, SettingType settingType)
	{
		if (settingType == SettingType.server)
			newSettings[name] = null;
		else
			super.remove(name, settingType);
	}

	override string[] save()
	{
		finalize();

		foreach (name, value; newSettings)
		{
			if (value is null)
			{
				if (name !in settings)
					continue;

				query!"DELETE FROM `UserSettings` WHERE `User` = ? AND `Name` = ?".exec(username, name);
			}
			else
			{
				if (name in settings && settings[name] == value)
					continue;

				query!"INSERT OR REPLACE INTO `UserSettings` (`User`, `Name`, `Value`) VALUES (?, ?, ?)".exec(username, name, value);
			}
		}

		return super.save();
	}

	override void logIn(string username, string password) { throw new Exception("Already logged in"); }
	override bool isLoggedIn() { return true; }
	override void register(string username, string password) { throw new Exception("Already registered"); }
	override string getName() { return username; }
	override Level getLevel() { return level; }

	override void logOut()
	{
		query!"UPDATE `Users` SET `Session` = ? WHERE `Username` = ?".exec(randomString(), username);
		super.remove("session", SettingType.client);
	}

	// ***************************************************************************

	/// Keep read posts for registered users in memory,
	/// and flush them out to the database periodically.

	static class ReadPostsCache
	{
		static struct Entry
		{
			Data* readPosts;
			bool dirty;
		}
		Entry[string] entries;
		Logger log;

		this()
		{
			auto flushTimer = setInterval(&flushReadPostCache, 5.minutes);
			addShutdownHandler({ flushTimer.cancel(); flushReadPostCache(); });
			log = createLogger("ReadPostsCache");
		}

		int counter;

		void flushReadPostCache()
		{
			mixin(DB_TRANSACTION);
			foreach (username, ref cacheEntry; entries)
				if (cacheEntry.dirty)
				{
					log("Flushing " ~ username);
					auto user = new RegisteredUser(username);
					user.set("readposts", encodeReadPosts(cacheEntry.readPosts), SettingType.server);
					user.save();
					cacheEntry.dirty = false;
				}
			if (++counter % 100 == 0)
			{
				log("Clearing cache.");
				entries = null;
			}
		}
	}
	static ReadPostsCache readPostsCache;

	override void getReadPosts()
	{
		if (!readPostsCache) readPostsCache = new ReadPostsCache();
		auto pcache = username in readPostsCache.entries;
		if (pcache)
			readPosts = pcache.readPosts;
		else
		{
			super.getReadPosts();
			readPostsCache.entries[username] = ReadPostsCache.Entry(readPosts, false);
		}
	}

	override void saveReadPosts()
	{
		if (!readPostsCache) readPostsCache = new ReadPostsCache();
		auto pcache = username in readPostsCache.entries;
		if (pcache)
		{
			assert(readPosts is pcache.readPosts);
			pcache.dirty = true;
		}
		else
			readPostsCache.entries[username] = ReadPostsCache.Entry(readPosts, true);
	}
}

// ***************************************************************************

User getUser(string cookieHeader)
{
	auto guest = new GuestUser(cookieHeader);
	if ("session" in guest.cookies)
	{
		foreach (string username, int level; query!"SELECT `Username`, `Level` FROM `Users` WHERE `Session` = ?".iterate(guest.cookies["session"]))
			return new RegisteredUser(username, cookieHeader, cast(User.Level)level);
	}
	return guest;
}

// ***************************************************************************

struct Config
{
	string salt;
}
immutable Config config;

import ae.utils.sini;
shared static this() { config = loadIni!Config("config/user.ini"); }

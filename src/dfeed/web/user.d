/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2021  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.user;

import core.bitop;

import std.datetime : SysTime, Clock;
import std.functional;
import std.string;
import std.exception;
import std.base64;
import ae.net.shutdown;
import ae.sys.data;
import std.typecons : RefCounted, refCounted;
import ae.sys.log;
import ae.sys.timing;
import ae.utils.math : flipBits;
import ae.utils.text;
import ae.utils.time : StdTime;
import ae.utils.time.common;
import ae.utils.time.format;
import ae.utils.meta.rcclass : RCClass, rcClass;
import ae.utils.zlib;

enum SettingType
{
	registered,  /// Always saved server-side, for registered users only
	server,      /// Stored on the server for registered users, and cookies for non-registered ones
	client,      /// Always stored in cookies
	session,     /// Always stored in cookies, and expires at the end of the session
}

struct AccountData // for export
{
	string username;
	int level;
	StdTime creationDate;
	string[string] settings;
}

abstract class CUser
{
	abstract string get(string name, string defaultValue, SettingType settingType);
	abstract void set(string name, string value, SettingType settingType);
	abstract void remove(string name, SettingType settingType);
	abstract string[] save();

	abstract void logIn(string username, string password, bool remember);
	abstract bool checkPassword(string password);
	abstract void changePassword(string password);
	abstract void logOut();
	abstract void register(string username, string password, bool remember);
	abstract AccountData exportData();
	abstract void deleteAccount();
	abstract bool isLoggedIn();
	abstract SysTime createdAt();

	enum Level : int
	{
		guest            =    0, /// Default user level
		hasRawLink       =    1, /// Get a clickable "raw post" link.
		canFlag          =    2, /// Can flag posts
		canApproveDrafts =   90, /// Can approve moderated drafts
		canModerate      =  100, /// Can delete posts locally/remotely and ban users
		sysadmin         = 1000, /// Can edit the database (presumably)
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

	alias ReadPostsData = RefCounted!Data;

	void getReadPosts()
	in  { assert(this.readPosts is ReadPostsData.init); }
	out { assert(this.readPosts !is ReadPostsData.init); }
	do
	{
		auto b64 = get("readposts", null, SettingType.server);
		if (b64.length)
		{
			// Temporary hack to catch Phobos bug
			ubyte[] zcode;

			string advice = _!"Try clearing your browser's cookies. Create an account to avoid repeated incidents.";

			try
				zcode = Base64.decode(b64);
			catch (Throwable /* Base64 throws AssertErrors on invalid data */)
			{
				import std.file; write("bad-base64.txt", b64);
				throw new Exception(_!"Malformed Base64 in read post history cookie." ~ " " ~ advice);
			}

			try
				readPosts = refCounted(uncompress(Data(zcode)));
			catch (ZlibException e)
			{
				import std.file; write("bad-zlib.z", zcode);
				throw new Exception(_!"Malformed deflated data in read post history cookie" ~ " (" ~ e.msg ~ "). " ~ advice);
			}
		}
		else
			readPosts = refCounted(Data());
	}

	static string encodeReadPosts(ref ReadPostsData readPosts)
	{
		auto b64 = Base64.encode(cast(ubyte[])compress(readPosts, 1).contents);
		return assumeUnique(b64);
	}

	void saveReadPosts()
	in  { assert(readPosts !is ReadPostsData.init && readPosts.length && readPostsDirty); }
	do
	{
		set("readposts", encodeReadPosts(readPosts), SettingType.server);
	}

	ReadPostsData readPosts;
	bool readPostsDirty;

final:
	void needReadPosts()
	{
		if (readPosts is ReadPostsData.init)
			getReadPosts();
	}

	void flushReadPosts()
	{
		if (readPosts !is ReadPostsData.init && readPosts.length && readPostsDirty)
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
			*pbyte = *pbyte & mask.flipBits;
		readPostsDirty = true;
	}

	public size_t countRead()
	{
		needReadPosts();
		if (!readPosts.length)
			return 0;

		size_t count;
		auto uints = cast(uint*)readPosts.contents.ptr;
		foreach (uint u; uints[0..readPosts.length/uint.sizeof])
			count += popcnt(u);
		foreach (ubyte b; cast(ubyte[])readPosts.contents[$/uint.sizeof*uint.sizeof..$])
			count += popcnt(b);
		return count;
	}
}
alias User = RCClass!CUser;

// ***************************************************************************

class CGuestUser : CUser
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
				auto settingType = settingTypes[name];

				if (settingType == SettingType.registered)
					continue;

				if (name in cookies && cookies[name] == value)
					continue;

				if (settingType == SettingType.session)
					result ~= "dfeed_" ~ name ~ "=" ~ value ~ "; Path=/";
				else
					result ~= "dfeed_" ~ name ~ "=" ~ value ~ "; Expires=" ~ (Clock.currTime() + 365.days).formatTime!(TimeFormats.HTTP) ~ "; Path=/";
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

	override void logIn(string username, string password, bool remember)
	{
		foreach (string session; query!"SELECT `Session` FROM `Users` WHERE `Username` = ? AND `Password` = ?".iterate(username, encryptPassword(password)))
		{
			set("session", session, remember ? SettingType.client : SettingType.session);
			return;
		}
		throw new Exception("No such username/password combination");
	}

	enum maxPasswordLength = 64;

	override void register(string username, string password, bool remember)
	{
		enforce(username.length, _!"Please enter a username");
		enforce(username.length <= 32, _!"Username too long");
		enforce(password.length <= maxPasswordLength, _!"Password too long");

		// Create user
		auto session = randomString();
		query!"INSERT INTO `Users` (`Username`, `Password`, `Session`, `Created`) VALUES (?, ?, ?, ?)"
			.exec(username, encryptPassword(password), session, Clock.currTime.stdTime);

		// Copy cookies to database
		auto user = registeredUser(username);
		foreach (name, value; cookies)
			user.set(name, value, SettingType.server);
		user.save();

		// Log them in
		this.set("session", session, remember ? SettingType.client : SettingType.session);
	}

	override bool checkPassword(string password) { throw new Exception(_!"Not logged in"); }
	override void changePassword(string password) { throw new Exception(_!"Not logged in"); }
	override void logOut() { throw new Exception(_!"Not logged in"); }
	override AccountData exportData() { throw new Exception(_!"Not logged in"); } // just check your cookies
	override void deleteAccount() { throw new Exception(_!"Not logged in"); } // just clear your cookies
	override bool isLoggedIn() { return false; }
	override SysTime createdAt() { return Clock.currTime(); }
}
alias GuestUser = RCClass!CGuestUser;
alias guestUser = rcClass!CGuestUser;

// ***************************************************************************

import dfeed.loc;
import dfeed.database;

final class CRegisteredUser : CGuestUser
{
	string[string] settings, newSettings;
	string username;
	Level level;
	StdTime creationTime;

	this(string username, string cookieHeader = null, Level level = Level.init, StdTime creationTime = 0)
	{
		super(cookieHeader);
		this.username = username;
		this.level = level;
		this.creationTime = creationTime;
	}

	override string get(string name, string defaultValue, SettingType settingType)
	{
		if (settingType != SettingType.server && settingType != SettingType.registered)
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
		if (settingType == SettingType.server || settingType == SettingType.registered)
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

	override void logIn(string username, string password, bool remember) { throw new Exception(_!"Already logged in"); }
	override bool isLoggedIn() { return true; }
	override void register(string username, string password, bool remember) { throw new Exception(_!"Already registered"); }
	override string getName() { return username; }
	override Level getLevel() { return level; }
	override SysTime createdAt() { return SysTime(creationTime); }

	override bool checkPassword(string password)
	{
		return query!"SELECT COUNT(*) FROM `Users` WHERE `Username` = ? AND `Password` = ?"
			.iterate(username, encryptPassword(password))
			.selectValue!int != 0;
	}

	override void changePassword(string password)
	{
		enforce(password.length <= maxPasswordLength, _!"Password too long");
		query!"UPDATE `Users` SET `Password` = ? WHERE `Username` = ?"
			.exec(encryptPassword(password), username);
	}

	override void logOut()
	{
		query!"UPDATE `Users` SET `Session` = ? WHERE `Username` = ?".exec(randomString(), username);
		super.remove("session", SettingType.client);
	}

	override AccountData exportData()
	{
		AccountData result;
		result.username = username;
		// Omit password hash here for security reasons
		// Omit session; it is already in a cookie
		result.level = level;
		result.creationDate = query!"SELECT `Created` FROM `Users` WHERE `Username` = ?"
			.iterate(username).selectValue!StdTime;
		foreach (string name, string value; query!"SELECT `Name`, `Value` FROM `UserSettings` WHERE `User` = ?".iterate(username))
			result.settings[name] = value;
		return result;
	}

	override void deleteAccount()
	{
		// Delete all preferences
		foreach (string name; query!"SELECT `Name` FROM `UserSettings` WHERE `User` = ?".iterate(username))
			this.remove(name, SettingType.server);
		save();

		// Delete user
		query!"DELETE FROM `Users` WHERE `Username` = ?".exec(username);
		query!"DELETE FROM `UserSettings` WHERE `User` = ?".exec(username);
	}

	// ***************************************************************************

	/// Keep read posts for registered users in memory,
	/// and flush them out to the database periodically.

	static class ReadPostsCache
	{
		static struct Entry
		{
			ReadPostsData readPosts;
			bool dirty;
		}
		Entry[string] entries;
		Logger log;

		this()
		{
			auto flushTimer = setInterval(&flushReadPostCache, 5.minutes);
			addShutdownHandler((scope const(char)[] reason){ flushTimer.cancel(); flushReadPostCache(); });
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
					auto user = registeredUser(username);
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
alias RegisteredUser = RCClass!CRegisteredUser;
alias registeredUser = rcClass!CRegisteredUser;

// ***************************************************************************

User getUser(string cookieHeader)
{
	auto guest = guestUser(cookieHeader);
	if ("session" in guest.cookies)
	{
		foreach (string username, int level, StdTime creationTime; query!"SELECT `Username`, `Level`, `Created` FROM `Users` WHERE `Session` = ?".iterate(guest.cookies["session"]))
			return User(registeredUser(username, cookieHeader, cast(CUser.Level)level, creationTime));
	}
	return User(guest);
}

// ***************************************************************************

struct Config
{
	string salt;
}
immutable Config config;

import ae.utils.sini;
import dfeed.paths : resolveSiteFile;
shared static this() { config = loadIni!Config(resolveSiteFile("config/user.ini")); }

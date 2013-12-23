/*  Copyright (C) 2011, 2012, 2013  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.string;
import std.exception;
import std.base64;
import ae.sys.data;
import ae.utils.text;
import ae.utils.zlib;

abstract class User
{
	abstract string get(string name, string defaultValue);
	abstract void set(string name, string value);
	abstract string[] save();

	abstract void logIn(string username, string password);
	abstract void logOut();
	abstract void register(string username, string password);
	abstract bool isLoggedIn();

	string getName() { return null; }

	final bool opIn_r(string name)
	{
		return get(name, null) !is null;
	}

	final string opIndex(string name)
	{
		auto result = get(name, null);
		enforce(result, "No such user setting: " ~ name);
		return result;
	}

	final string opIndexAssign(string value, string name)
	{
		set(name, value);
		return value;
	}

protected:
	/// Save misc data to string settings
	final void finalize()
	{
		encodeReadPosts();
	}

	// ***********************************************************************

private:
	Data* readPosts;
	bool readPostsDirty;

final:
	void needReadPosts()
	{
		if (!readPosts)
		{
			auto b64 = get("readposts", null);
			if (b64)
			{
				// Temporary hack to catch Phobos bug
				ubyte[] zcode;
				try
					zcode = Base64.decode(b64);
				catch
				{
					std.file.write("bad-base64.txt", b64);
					throw new Exception("Malformed Base64 in read post history cookie. Try clearing your cookies.");
				}
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
			set("readposts", assumeUnique(b64));
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

final class GuestUser : User
{
	string[string] cookies, newCookies;

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

	override string get(string name, string defaultValue)
	{
		auto pCookie = name in newCookies;
		if (pCookie)
			return *pCookie;
		pCookie = name in cookies;
		if (pCookie)
			return *pCookie;
		return defaultValue;
	}

	override void set(string name, string value)
	{
		newCookies[name] = value;
	}

	override string[] save()
	{
		finalize();

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

	static string encryptPassword(string password)
	{
		// TODO: use bcrypt()
		import std.digest.md, std.file;
		return (password ~ readText("data/salt.txt")).md5Of().toHexString!(LetterCase.lower)().idup; // Issue 9279
	}

	override void logIn(string username, string password)
	{
		foreach (string session; query("SELECT `Session` FROM `Users` WHERE `Username` = ? AND `Password` = ?").iterate(username, encryptPassword(password)))
		{
			set("session", session);
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
		query("INSERT INTO `Users` (`Username`, `Password`, `Session`) VALUES (?, ?, ?)").exec(username, encryptPassword(password), session);

		// Copy cookies to database
		auto user = new RegisteredUser(username);
		foreach (name, value; cookies)
			user.set(name, value);
		user.save();

		// Log them in
		this.set("session", session);
	}

	override void logOut() { throw new Exception("Not logged in"); }
	override bool isLoggedIn() { return false; }
}

import database;

final class RegisteredUser : User
{
	string[string] settings, newSettings;
	string username;

	this(string username)
	{
		this.username = username;
	}

	override string get(string name, string defaultValue)
	{
		auto pSetting = name in newSettings;
		if (pSetting)
			return *pSetting;

		pSetting = name in settings;
		string value;
		if (pSetting)
			value = *pSetting;
		else
		{
			foreach (string v; query("SELECT `Value` FROM `UserSettings` WHERE `User` = ? AND `Name` = ?").iterate(username, name))
				value = v;
			settings[name] = value;
		}

		return value ? value : defaultValue;
	}

	override void set(string name, string value)
	{
		newSettings[name] = value;
	}

	override string[] save()
	{
		finalize();

		foreach (name, value; newSettings)
		{
			if (name in settings && settings[name] == value)
				continue;

			query("INSERT OR REPLACE INTO `UserSettings` (`User`, `Name`, `Value`) VALUES (?, ?, ?)").exec(username, name, value);
		}

		return null;
	}

	override void logIn(string username, string password) { throw new Exception("Already logged in"); }
	override bool isLoggedIn() { return true; }
	override void register(string username, string password) { throw new Exception("Already registered"); }
	override string getName() { return username; }

	override void logOut()
	{
		query("UPDATE `Users` SET `Session` = ? WHERE `Username` = ?").exec(randomString(), username);
	}
}

User getUser(string cookieHeader)
{
	auto guest = new GuestUser(cookieHeader);
	if ("session" in guest.cookies)
	{
		foreach (string username; query("SELECT `Username` FROM `Users` WHERE `Session` = ?").iterate(guest.cookies["session"]))
			return new RegisteredUser(username);
	}
	return guest;
}

/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// User settings.
module dfeed.web.web.user;

import ae.utils.aa : aaGet;
import ae.utils.text : randomString;

import dfeed.loc;
import dfeed.web.user : User, SettingType;

User user;

struct UserSettings
{
	static SettingType[string] settingTypes;

	template userSetting(string name, string defaultValue, SettingType settingType)
	{
		@property string userSetting() { return user.get(name, defaultValue, settingType); }
		@property string userSetting(string newValue) { user.set(name, newValue, settingType); return newValue; }
		static this() { settingTypes[name] = settingType; }
	}

	template randomUserString(string name, SettingType settingType)
	{
		@property string randomUserString()
		{
			auto value = user.get(name, null, settingType);
			if (value is null)
			{
				value = randomString();
				user.set(name, value, settingType);
			}
			return value;
		}
	}

	/// Posting details. Remembered when posting messages.
	alias name = userSetting!("name", null, SettingType.server);
	alias email = userSetting!("email", null, SettingType.server); /// ditto

	/// View mode. Can be changed in the settings.
	alias groupViewMode = userSetting!("groupviewmode", "basic", SettingType.client);

	/// Enable or disable keyboard hotkeys. Can be changed in the settings.
	alias enableKeyNav = userSetting!("enable-keynav", "true", SettingType.client);

	/// Whether messages are opened automatically after being focused
	/// (message follows focus). Can be changed in the settings.
	alias autoOpen = userSetting!("auto-open", "false", SettingType.client);

	/// Any pending notices that should be shown on the next page shown.
	alias pendingNotice = userSetting!("pending-notice", null, SettingType.session);

	/// Session management
	alias previousSession = userSetting!("previous-session", "0", SettingType.server);
	alias currentSession  = userSetting!("current-session" , "0", SettingType.server);  /// ditto
	alias sessionCanary   = userSetting!("session-canary"  , "0", SettingType.session); /// ditto

	/// A unique ID used to recognize both logged-in and anonymous users.
	alias id = randomUserString!("id", SettingType.server);

	/// Secret token used for CSRF protection.
	/// Visible in URLs.
	alias secret = randomUserString!("secret", SettingType.server);

	/// UI language.
	alias language = userSetting!("language", null, SettingType.server);

	void set(string name, string value)
	{
		user.set(name, value, settingTypes.aaGet(name));
	}
}
UserSettings userSettings;

static immutable allViewModes = ["basic", "threaded", "horizontal-split", "vertical-split"];
string viewModeName(string viewMode)
{
	switch (viewMode)
	{
		case "basic"           : return _!"basic"           ;
		case "threaded"        : return _!"threaded"        ;
		case "horizontal-split": return _!"horizontal-split";
		case "vertical-split"  : return _!"vertical-split"  ;
		default: throw new Exception(_!"Unknown view mode");
	}
}

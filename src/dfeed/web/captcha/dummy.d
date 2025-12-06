/*  Copyright (C) 2025  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.captcha.dummy;

import dfeed.loc;
import dfeed.web.captcha.common;

/// A dummy CAPTCHA for testing purposes.
/// Simply presents an "I am not a robot" checkbox.
/// NOT suitable for production use.
final class DummyCaptcha : Captcha
{
	override string getChallengeHtml(CaptchaErrorData errorData)
	{
		return
			`<label style="display: block; margin: 1em 0;">` ~
			`<input type="checkbox" name="dummy_captcha_checkbox" value="1"> ` ~
			_!`I am not a robot` ~
			`</label>`;
	}

	override bool isPresent(UrlParameters fields)
	{
		return ("dummy_captcha_checkbox" in fields) !is null;
	}

	override void verify(UrlParameters fields, string ip, void delegate(bool success, string errorMessage, CaptchaErrorData errorData) handler)
	{
		bool checked = fields.get("dummy_captcha_checkbox", "") == "1";
		handler(checked, checked ? null : _!"Please confirm you are not a robot", null);
	}
}

static this()
{
	captchas["dummy"] = new DummyCaptcha();
}

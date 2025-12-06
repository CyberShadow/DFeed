/*  Copyright (C) 2012, 2014, 2015, 2016, 2018, 2021  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.captcha;

import std.exception;

public import dfeed.web.captcha.common;

static import dfeed.web.captcha.dcaptcha;
static import dfeed.web.captcha.dummy;
static import dfeed.web.captcha.recaptcha;

Captcha getCaptcha(string name)
{
	auto pcaptcha = name in captchas;
	enforce(name, "CAPTCHA mechanism unknown or not configured: " ~ name);
	return *pcaptcha;
}

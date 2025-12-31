/*  Copyright (C) 2012, 2014, 2015, 2016, 2018, 2021, 2025  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.captcha.common;

import std.exception;

public import ae.net.ietf.url : UrlParameters;

class Captcha
{
	/// Get a HTML fragment to insert into the HTML form to present a challenge to the user.
	/// If showing the form again in response to a wrong CAPTCHA solution,
	/// the error data passed to the verify handler should be supplied.
	abstract string getChallengeHtml(CaptchaErrorData error = null);

	/// Get a description of the challenge for logging purposes.
	/// Returns null if not available.
	/// Must be called before verify() as verify may invalidate the challenge.
	string getChallengeDescription(UrlParameters fields)
	{
		return null;
	}

	/// Get a description of the user's response for logging purposes.
	/// Returns null if not available.
	string getResponseDescription(UrlParameters fields)
	{
		return null;
	}

	/// Check whether a CAPTCHA attempt is included in the form
	/// (check for the presence of fields added by getChallengeHtml).
	abstract bool isPresent(UrlParameters fields);

	/// Verify the correctness of the user's CAPTCHA solution.
	/// handler can be called asynchronously.
	abstract void verify(UrlParameters fields, string ip, void delegate(bool success, string errorMessage, CaptchaErrorData errorData) handler);
}

/// Opaque class for preserving error data.
class CaptchaErrorData
{
}

package Captcha[string] captchas;

/// Try all registered captchas to get a response description from a single form field.
/// Returns null if no captcha recognizes the field as its response field.
string getCaptchaResponseFromField(string fieldName, string fieldValue)
{
	// Create a minimal UrlParameters with just this field
	UrlParameters fields;
	fields[fieldName] = fieldValue;

	foreach (captcha; captchas.byValue)
	{
		if (captcha is null)
			continue;
		auto desc = captcha.getResponseDescription(fields);
		if (desc !is null)
			return desc;
	}
	return null;
}

/// Get the CAPTCHA response description from all registered captchas given form fields.
/// Returns null if no captcha recognizes the fields.
string getCaptchaResponseDescription(UrlParameters fields)
{
	foreach (captcha; captchas.byValue)
	{
		if (captcha is null)
			continue;
		auto desc = captcha.getResponseDescription(fields);
		if (desc !is null)
			return desc;
	}
	return null;
}

static this()
{
	captchas["none"] = null;
}

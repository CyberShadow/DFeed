/*  Copyright (C) 2012, 2014, 2015, 2016, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

public import ae.net.ietf.url : UrlParameters;

class Captcha
{
	/// Get a HTML fragment to insert into the HTML form to present a challenge to the user.
	/// If showing the form again in response to a wrong CAPTCHA solution,
	/// the error data passed to the verify handler should be supplied.
	abstract string getChallengeHtml(CaptchaErrorData error = null);

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

Captcha theCaptcha;

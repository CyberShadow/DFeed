/*  Copyright (C) 2012, 2014  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module services.captcha;

class Captcha
{
	/// Get a HTML fragment to insert into the HTML form to present a challenge to the user.
	/// If showing the form again in response to a wrong CAPTCHA solution,
	/// the error data passed to the verify handler should be supplied.
	abstract string getChallengeHtml(CaptchaErrorData error = null);

	/// Check whether a CAPTCHA attempt is included in the form
	/// (check for the presence of fields added by getChallengeHtml).
	abstract bool isPresent(string[string] fields);

	/// Verify the correctness of the user's CAPTCHA solution.
	/// handler can be called asynchronously.
	abstract void verify(string[string] fields, string ip, void delegate(bool success, string errorMessage, CaptchaErrorData errorData) handler);
}

/// Opaque class for preserving error data.
class CaptchaErrorData
{
}

Captcha theCaptcha;

// ***************************************************************************

private:

import std.string;

import ae.net.http.client;

class Recaptcha : Captcha
{
	override string getChallengeHtml(CaptchaErrorData errorData)
	{
		string error = errorData ? (cast(RecaptchaErrorData)errorData).code : null;

		auto publicKey = getOptions().publicKey;
		return
			`<script type="text/javascript" src="http://www.google.com/recaptcha/api/challenge?k=` ~ publicKey ~ (error ? `&error=` ~ error : ``) ~ `">`
			`</script>`
			`<noscript>`
				`<iframe src="http://www.google.com/recaptcha/api/noscript?k=` ~ publicKey ~ (error ? `&error=` ~ error : ``) ~ `"`
					` height="300" width="500" frameborder="0"></iframe><br>`
				`<textarea name="recaptcha_challenge_field" rows="3" cols="40">`
				`</textarea>`
				`<input type="hidden" name="recaptcha_response_field" value="manual_challenge">`
			`</noscript>`;
	}

	override bool isPresent(string[string] fields)
	{
		return "recaptcha_challenge_field" in fields && "recaptcha_response_field" in fields;
	}

	override void verify(string[string] fields, string ip, void delegate(bool success, string errorMessage, CaptchaErrorData errorData) handler)
	{
		assert(isPresent(fields));

		httpPost("http://www.google.com/recaptcha/api/verify", [
			"privatekey" : getOptions().privateKey,
			"remoteip" : ip,
			"challenge" : fields["recaptcha_challenge_field"],
			"response" : fields["recaptcha_response_field"],
		], (string result) {
			auto lines = result.splitLines();
			if (lines[0] == "true")
				handler(true, null, null);
			else
			if (lines.length >= 2)
				handler(false, "reCAPTCHA error: " ~ errorText(lines[1]), new RecaptchaErrorData(lines[1]));
			else
				handler(false, "Unexpected reCAPTCHA reply: " ~ result, null);
		}, (string error) {
			handler(false, error, null);
		});
	}

private:
	struct RecaptchaOptions { string publicKey, privateKey; }
	static RecaptchaOptions getOptions()
	{
		import std.file, std.string;
		auto lines = splitLines(readText("data/recaptcha.txt"));
		return RecaptchaOptions(lines[0], lines[1]);
	}

	static string errorText(string code)
	{
		switch (code)
		{
			case "incorrect-captcha-sol":
				return "The CAPTCHA solution was incorrect.";
			case "captcha-timeout":
				return "The solution was received after the CAPTCHA timed out.";
			default:
				return code;
		}
	}
}

class RecaptchaErrorData : CaptchaErrorData
{
	string code;
	this(string code) { this.code = code; }
	override string toString() { return code; }
}

static this()
{
	theCaptcha = new Recaptcha();
}

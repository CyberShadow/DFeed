/*  Copyright (C) 2011  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module recaptcha;

import std.string;

import ae.net.http.client;

enum RecaptchaErrorPrefix = "reCAPTCHA error: ";

string recaptchaChallengeHtml(string error = null)
{
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

bool recaptchaPresent(string[string] fields)
{
	return "recaptcha_challenge_field" in fields && "recaptcha_response_field" in fields;
}

void recaptchaCheck(string[string] fields, string ip, void delegate(bool success, string errorMessage) handler)
{
	assert(recaptchaPresent(fields));

	httpPost("http://www.google.com/recaptcha/api/verify", [
		"privatekey" : getOptions().privateKey,
		"remoteip" : ip,
		"challenge" : fields["recaptcha_challenge_field"],
		"response" : fields["recaptcha_response_field"],
	], (string result) {
		auto lines = result.splitLines();
		if (lines[0] == "true")
			handler(true, null);
		else
			handler(false, lines.length>1 ? RecaptchaErrorPrefix ~ lines[1] : result);
	}, (string error) {
		handler(false, error);
	});
}

private:

struct RecaptchaOptions { string publicKey, privateKey; }
RecaptchaOptions getOptions()
{
	import std.file, std.string;
	auto lines = splitLines(readText("data/recaptcha.txt"));
	return RecaptchaOptions(lines[0], lines[1]);
}

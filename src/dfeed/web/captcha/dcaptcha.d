/*  Copyright (C) 2012, 2014, 2015, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.captcha.dcaptcha;

import std.algorithm : any;
import std.string : strip, icmp;

import ae.utils.text;
import ae.utils.xmllite : encodeEntities;

import dcaptcha.dcaptcha;

import dfeed.web.captcha;

final class Dcaptcha : Captcha
{
	static Challenge[string] challenges;

	string createChallenge()
	{
		auto challenge = getCaptcha();
		auto key = randomString();
		challenges[key] = challenge;
		return key;
	}

	override string getChallengeHtml(CaptchaErrorData errorData)
	{
		auto key = createChallenge();
		auto challenge = challenges[key];

		return
			challenge.question.encodeEntities() ~ "\n" ~
			`<pre>` ~ challenge.code.encodeEntities() ~ `</pre>` ~
			`<input type="hidden" name="dcaptcha_challenge_field" value="` ~ key ~ `">` ~
			`<input type="hidden" "dcaptcha_response_field"></input>` ~
			`<input name="dcaptcha_response_field"></input>` ~
			`<p><b>Hint</b>: ` ~ challenge.hint ~ `</p>` ~
			`<p>Is the CAPTCHA too hard?<br>Refresh the page to get a different question,<br>or ask in the ` ~
				`<a href="http://webchat.freenode.net?randomnick=1&channels=%23d">#d IRC channel on Freenode</a>.</p>`
		;
	}

	override bool isPresent(UrlParameters fields)
	{
		return "dcaptcha_challenge_field" in fields && "dcaptcha_response_field" in fields;
	}

	override void verify(UrlParameters fields, string ip, void delegate(bool success, string errorMessage, CaptchaErrorData errorData) handler)
	{
		assert(isPresent(fields));

		auto key = fields["dcaptcha_challenge_field"];

		auto pchallenge = key in challenges;
		if (!pchallenge)
			return handler(false, "Unknown or expired CAPTCHA challenge", null);
		auto challenge = *pchallenge;
		challenges.remove(key);

		auto response = fields["dcaptcha_response_field"].strip();

		bool correct = challenge.answers.any!(answer => icmp(answer, response) == 0);

		return handler(correct, correct ? null : "The answer is incorrect", null);
	}
}

static this()
{
	theCaptcha = new Dcaptcha();
}

module recaptcha;

import ae.net.http.client;

string recaptchaChallengeHtml()
{
	return
		`<script type="text/javascript" src="http://www.google.com/recaptcha/api/challenge?k=your_public_key">`
		`</script>`
		`<noscript>`
			`<iframe src="http://www.google.com/recaptcha/api/noscript?k=` ~ getOptions().publicKey ~ `" height="300" width="500" frameborder="0"></iframe><br>`
			`<textarea name="recaptcha_challenge_field" rows="3" cols="40">`
			`</textarea>`
			`<input type="hidden" name="recaptcha_response_field" value="manual_challenge">`
		`</noscript>`;
}

private:

struct RecaptchaOptions { string publicKey, privateKey; }
RecaptchaOptions getOptions()
{
	import std.file, std.string;
	auto lines = splitLines(readText("data/recaptcha.txt"));
	return RecaptchaOptions(lines[0], lines[1]);
}

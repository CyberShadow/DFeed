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

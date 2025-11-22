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

module dfeed.web.spam.openai;

import std.algorithm;
import std.conv;
import std.format;
import std.math;
import std.string;

import ae.net.http.client;
import ae.sys.data;
import ae.sys.dataset;
import ae.utils.json;

import dfeed.loc;
import dfeed.site;
import dfeed.web.posting;
import dfeed.web.spam;

class OpenAI : SpamChecker
{
	struct Config
	{
		string apiKey;
		string model = "gpt-4o-mini";
	}
	Config config;

	this(Config config) { this.config = config; }

	override void check(PostProcess process, SpamResultHandler handler)
	{
		if (!config.apiKey)
			return handler(unconfiguredHam, "OpenAI is not set up");
		if (!site.name.length)
			return handler(unconfiguredHam, "Site name is not set - edit config/site.ini");

		// Build the prompt - ask for reasoning first, then verdict
		// This helps the model think through the decision while still being parseable
		auto systemPrompt = format(
			"You are a spam detection system for the online forum titled \"%s\". " ~
			"Analyze posts and determine if they are spam or legitimate (ham). " ~
			"First, briefly explain your reasoning (1-2 sentences), then on a new line, " ~
			"provide your verdict as either 'VERDICT: spam' or 'VERDICT: ham'.\n\n" ~
			"Consider spam to be:\n" ~
			"- New threads completely unrelated to this forum's topic (even if they appear helpful for other topics)\n" ~
			"- Unsolicited advertising or promotional content\n" ~
			"- Generic troubleshooting guides for consumer products unrelated to the forum's purpose\n" ~
			"- Malicious links or suspicious URLs\n" ~
			"- Repetitive patterns or poor grammar used to evade filters\n\n" ~
			"Consider ham to be:\n" ~
			"- Posts relevant to this forum's topic and purpose\n" ~
			"- Posts that continue an existing discussion, even if tangential to the forum's topic",
			site.name
		);

		auto userMessage = format(
			"Author: %s\nEmail: %s\nSubject: %s\n\nContent:\n%s",
			process.draft.clientVars.get("name", ""),
			process.draft.clientVars.get("email", ""),
			process.draft.clientVars.get("subject", ""),
			process.draft.clientVars.get("text", "")
		);

		// Build the API request as JSON string
		import std.json : JSONValue, JSONType;

		JSONValue requestBody = JSONValue([
			"model": JSONValue(config.model),
			"messages": JSONValue([
				JSONValue([
					"role": JSONValue("system"),
					"content": JSONValue(systemPrompt),
				]),
				JSONValue([
					"role": JSONValue("user"),
					"content": JSONValue(userMessage),
				]),
			]),
			"logprobs": JSONValue(true),
			"top_logprobs": JSONValue(5),
			"max_tokens": JSONValue(100),
			"temperature": JSONValue(0.0),
		]);

		auto requestData = requestBody.toString();

		// Make the API call
		// Note: We need to use httpRequest instead of httpPost to add custom headers (Authorization)
		auto request = new HttpRequest;
		request.resource = "https://api.openai.com/v1/chat/completions";
		request.method = "POST";
		request.headers["Authorization"] = "Bearer " ~ config.apiKey;
		request.headers["Content-Type"] = "application/json";
		request.data = DataVec(Data(requestData));

		httpRequest(request, (HttpResponse response, string disconnectReason) {
			if (!response)
			{
				handler(errorSpam, "OpenAI error: " ~ disconnectReason);
				return;
			}

			if (response.status != HttpStatusCode.OK)
			{
				auto errorMsg = cast(string)response.getContent().toGC();
				handler(errorSpam, format("OpenAI API error (HTTP %d): %s",
					response.status, errorMsg.length > 200 ? errorMsg[0..200] ~ "..." : errorMsg));
				return;
			}

			auto responseText = cast(string)response.getContent().toGC();

			try
			{
				import std.json : parseJSON;
				auto responseJson = parseJSON(responseText);

				// Extract the response text
				auto choices = responseJson["choices"].array;
				if (choices.length == 0)
				{
					handler(errorSpam, "OpenAI error: No choices in response");
					return;
				}

				auto choice = choices[0];
				auto message = choice["message"];
				auto content = message["content"].str;

				// Parse verdict from response (should contain "VERDICT: spam" or "VERDICT: ham")
				bool isSpam;
				if (content.toLower().canFind("verdict: spam") || content.toLower().canFind("verdict:spam"))
					isSpam = true;
				else if (content.toLower().canFind("verdict: ham") || content.toLower().canFind("verdict:ham"))
					isSpam = false;
				else
				{
					// Fallback: check for spam/ham keywords in response
					auto lowerContent = content.toLower();
					if (lowerContent.canFind("spam") && !lowerContent.canFind("not spam"))
						isSpam = true;
					else if (lowerContent.canFind("ham") || lowerContent.canFind("legitimate"))
						isSpam = false;
					else
					{
						handler(errorSpam, format("OpenAI error: Could not parse verdict from response: %s",
							content.length > 200 ? content[0..200] ~ "..." : content));
						return;
					}
				}

				// Extract confidence from logprobs by finding "spam" and "ham" probabilities
				Spamicity spamicity;
				bool hasLogprobs = false;

				if (auto logprobs = "logprobs" in choice.object)
				{
					if (auto content_logprobs = "content" in logprobs.object)
					{
						// Check the last token's top_logprobs for " spam" and " ham"
						double spamProb = 0.0;
						double hamProb = 0.0;

						auto tokens = content_logprobs.array;
						if (tokens.length > 0)
						{
							auto lastToken = tokens[$-1];

							// Check if the last token has top_logprobs
							if (auto top_logprobs = "top_logprobs" in lastToken.object)
							{
								// Search through the top alternatives for " spam" or " ham"
								foreach (altToken; top_logprobs.array)
								{
									auto tokenStr = altToken["token"].str;
									auto logprob = altToken["logprob"].floating;
									auto prob = exp(logprob); // Convert log to linear probability

									if (tokenStr == " spam")
										spamProb = prob;
									else if (tokenStr == " ham")
										hamProb = prob;
								}
							}
						}

						// Calculate spamicity as weighted proportion
						auto totalProb = spamProb + hamProb;
						if (totalProb > 0)
						{
							spamicity = spamProb / totalProb;
							hasLogprobs = true;
						}
					}
				}

				// If no logprobs available, use likely constants
				if (!hasLogprobs)
					spamicity = isSpam ? likelySpam : likelyHam;

				// Return full model response in the message
				auto verdict = isSpam ? "spam" : "ham";
				auto resultMessage = format("%s thinks your post is %s: %s",
					config.model, verdict, content);
				handler(spamicity, resultMessage);
			}
			catch (Exception e)
			{
				handler(errorSpam, format("OpenAI error: %s", e.msg));
			}
		});
	}
}

version (main_openai)
void main(string[] args)
{
	import std.exception : enforce;
	import std.file : dirEntries, SpanMode;
	import std.stdio : stdout;
	import ae.net.asockets : socketManager;
	static import ae.net.ssl.openssl;

	import dfeed.common : createService;
	auto openai = createService!OpenAI("apis/openai").enforce("OpenAI is not configured");

	foreach (fn; args[1..$])
	{
		if (fn.length == 20)
			fn = dirEntries("logs", "* - PostProcess-" ~ fn ~ ".log", SpanMode.shallow).front.name;

		stdout.writeln("--------------------------------------------------------------------");
		auto pp = new PostProcess(fn);
		stdout.write(pp.post.message);
		stdout.writeln();
		stdout.writeln("--------------------------------------------------------------------");

		void handler(Spamicity spamicity, string message) { stdout.writefln("%s: %s", message, spamicity); }
		openai.check(pp, &handler);
		socketManager.loop();
	}
}

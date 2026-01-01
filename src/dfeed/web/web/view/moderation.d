/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020, 2025, 2026  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// Moderation views.
module dfeed.web.web.view.moderation;

import std.algorithm.iteration : map, filter, uniq;
import std.algorithm.searching : canFind, findSplit;
import std.algorithm.sorting : sort;
import std.array : array, join;
import std.conv : text;
import std.datetime.systime : Clock;
import std.exception : enforce;
import std.format : format;
import std.string : capitalize, strip;
import std.typecons : Yes, No;

import ae.net.ietf.url : UrlParameters;
import ae.utils.json : jsonParse;
import ae.utils.meta : identity;
import ae.utils.sini : loadIni;
import ae.utils.text : splitAsciiLines;
import ae.utils.text.html : encodeHtmlEntities;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.database : query, selectValue;
import dfeed.groups : getGroupInfo;
import dfeed.loc;
import dfeed.mail : sendMail;
import dfeed.message : Rfc850Post, idToUrl;
import dfeed.paths : resolveSiteFile;
import dfeed.site : site;
import dfeed.sources.newsgroups : NntpConfig;
import dfeed.web.captcha.common : getCaptchaResponseFromField;
import dfeed.web.posting : PostDraft, PostProcess;
import dfeed.web.user : User;
import dfeed.web.web.draft : getDraft, draftToPost;
import dfeed.web.web.moderation : findPostingLog, moderatePost, approvePost, getUnbanPreviewByKey, unbanPoster, UnbanTree;
import dfeed.web.web.page : html, Redirect;
import dfeed.web.web.part.post : formatPost;
import dfeed.web.web.posting : postDraft;
import dfeed.web.web.user : user, userSettings;

struct JourneyEvent
{
	string timestamp;
	string type;      // "captcha", "spam_check", "moderation", "posted", "info", "log_file", "approval", "page_visit", "referrer"
	string message;
	bool success;     // true for success, false for failure
	string details;   // additional details like spamicity value
	string sourceFile; // log file name
	int lineNumber;    // line number in log file (1-based)
	string url;       // for page_visit events, the URL to link to
}

JourneyEvent[] parsePostingJourney(string messageID)
{
	import std.file : exists, read, dirEntries, SpanMode;
	import std.algorithm : filter, startsWith, endsWith, map;
	import std.algorithm.mutation : reverse;
	import std.array : array;
	import std.string : split, indexOf;
	import std.regex : matchFirst;
	import std.process : execute;
	import std.path : baseName;

	JourneyEvent[] events;

	// Extract the post ID from message ID
	if (!messageID.startsWith("<") || !messageID.endsWith(">"))
		return events;

	auto messageIDclean = messageID[1..$-1];
	auto atPos = messageIDclean.indexOf("@");
	if (atPos < 0)
		return events;

	auto postID = messageIDclean[0..atPos];
	if (postID.length != 20)
		return events;

	// Helper function to extract previous pid from log content (from [ServerVar] pid: xxx)
	string extractPreviousPid(string content)
	{
		foreach (line; content.split("\n"))
		{
			if (line.indexOf("[ServerVar] pid:") >= 0)
			{
				auto pidMatch = line.matchFirst(`\[ServerVar\] pid: ([a-z]{20})`);
				if (pidMatch)
					return pidMatch[1];
			}
		}
		return null;
	}

	// Helper function to find log file for a given pid
	string findLogForPid(string pid)
	{
		version (Windows)
		{
			auto matches = dirEntries("logs", "*PostProcess-" ~ pid ~ ".log", SpanMode.depth).array;
			return matches.length > 0 ? matches[0].name : null;
		}
		else
		{
			auto result = execute(["find", "logs/", "-name", "*PostProcess-" ~ pid ~ ".log"]);
			if (result.status == 0)
			{
				auto files = result.output.split("\n").filter!(f => f.length > 0).array;
				return files.length > 0 ? files[0] : null;
			}
			return null;
		}
	}

	// Track which log files are related and why
	struct RelatedLog
	{
		string file;
		string evidence; // Why this log was included
	}
	RelatedLog[] relatedLogs;

	// Find the primary log and follow the pid chain backwards
	auto primaryLog = findLogForPid(postID);
	if (primaryLog is null)
		return events;

	// Follow the chain of previous pids
	string currentPid = postID;
	string currentLog = primaryLog;
	string nextPid = postID; // For building the "leads to" evidence

	while (currentLog !is null)
	{
		if (!exists(currentLog))
			break;

		string evidence;
		if (currentPid == postID)
			evidence = "Primary log (post ID: " ~ postID ~ ")";
		else
			evidence = "Previous attempt (retry led to: " ~ nextPid ~ ")";

		relatedLogs ~= RelatedLog(currentLog, evidence);

		// Look for previous pid in this log
		auto content = cast(string)read(currentLog);
		auto prevPid = extractPreviousPid(content);

		if (prevPid is null || prevPid == currentPid)
			break;

		// Find the log for the previous pid
		nextPid = currentPid;
		currentPid = prevPid;
		currentLog = findLogForPid(prevPid);
	}

	// Reverse so oldest attempt is first
	relatedLogs.reverse();

	// Search for approval events in the Banned log file (same date as the PostProcess log)
	void searchBannedLog(string pid, string postProcessLogFile)
	{
		// Replace "PostProcess-xxx.log" with "Banned.log" to get the Banned log for the same date
		auto bannedLogFile = postProcessLogFile.matchFirst(`^(.* - )PostProcess-[a-z]+\.log$`);
		if (!bannedLogFile)
			return;

		auto logPath = bannedLogFile[1] ~ "Banned.log";
		if (!exists(logPath))
			return;

		auto content = cast(string)read(logPath);
		auto logFileName = baseName(logPath);
		int lineNum = 0;

		foreach (line; content.split("\n"))
		{
			lineNum++;
			if (line.length < 30 || line[0] != '[')
				continue;

			// Look for approval entries containing our post ID
			auto approvalMatch = line.matchFirst(`\[([^\]]+)\] User ([^ ]+) is approving draft ([^ ]+) \(post ` ~ pid ~ `\) titled "(.*)" by "(.*)"`);
			if (approvalMatch)
			{
				auto timestamp = approvalMatch[1];
				auto moderator = approvalMatch[2];
				events ~= JourneyEvent(timestamp, "approval", "Approved by moderator", true,
					"Moderator: " ~ moderator, logFileName, lineNum);
				return; // Found it
			}
		}
	}

	// Parse Web.log for page visits matching IP and User-Agent
	// Returns the web events separately (not added to main events array)
	JourneyEvent[] parseWebLog(string postProcessLogFile, string ip, string userAgent)
	{
		JourneyEvent[] webEvents;

		if (ip.length == 0)
			return webEvents;

		// Replace "PostProcess-xxx.log" with "Web.log" to get the Web log for the same date
		auto webLogFile = postProcessLogFile.matchFirst(`^(.* - )PostProcess-[a-z]+\.log$`);
		if (!webLogFile)
			return webEvents;

		auto logPath = webLogFile[1] ~ "Web.log";
		if (!exists(logPath))
			return webEvents;

		auto content = cast(string)read(logPath);
		auto logFileName = baseName(logPath);
		int lineNum = 0;

		// Track referrers we've already added to avoid duplicates
		bool[string] seenReferrers;

		foreach (line; content.split("\n"))
		{
			lineNum++;
			if (line.length < 30 || line[0] != '[')
				continue;

			// Parse log line: [timestamp] \tIP\tSTATUS\tTIME\tMETHOD\tURL\tCONTENT-TYPE[\tREFERER\tUSER-AGENT]
			auto closeBracket = line.indexOf("]");
			if (closeBracket < 0)
				continue;
			auto timestamp = line[1..closeBracket];
			auto rest = line[closeBracket + 2 .. $];

			auto fields = rest.split("\t");
			if (fields.length < 7)
				continue;

			// Field indices (first field is empty for alignment):
			// [0]=empty, [1]=IP, [2]=STATUS, [3]=TIME, [4]=METHOD, [5]=URL, [6]=CONTENT-TYPE, [7]=REFERER, [8]=USER-AGENT
			auto logIP = fields[1];
			auto status = fields[2];
			auto method = fields[4];
			auto url = fields[5];
			auto contentType = fields[6];
			string referer = fields.length > 7 ? fields[7] : "-";
			string logUserAgent = fields.length > 8 ? fields[8] : "";

			// Check if this matches our user's IP
			if (logIP != ip)
				continue;

			// If we have a User-Agent to match, check it (but don't require it)
			if (userAgent.length > 0 && logUserAgent.length > 0 && logUserAgent != userAgent)
				continue;

			// Only interested in text/html pages (GET and POST requests)
			// Also include POST redirects (3xx status with no content type)
			if (method != "GET" && method != "POST")
				continue;
			bool isRedirect = status.length >= 1 && status[0] == '3';
			if (!contentType.startsWith("text/html") && !(method == "POST" && isRedirect))
				continue;

			// Skip static resources
			if (url.canFind("/static/"))
				continue;

			// Extract just the path from the URL for display
			string displayPath = url;
			auto hostEnd = url.indexOf("://");
			if (hostEnd >= 0)
			{
				auto pathStart = url.indexOf("/", hostEnd + 3);
				if (pathStart >= 0)
					displayPath = url[pathStart .. $];
			}

			// Check for external referrer (not from same site)
			if (referer != "-" && referer.length > 0)
			{
				// Check if referrer is external (doesn't contain our host)
				auto urlHost = url.indexOf("://");
				string ourHost;
				if (urlHost >= 0)
				{
					auto hostStart = urlHost + 3;
					auto hostEndPos = url.indexOf("/", hostStart);
					ourHost = hostEndPos >= 0 ? url[hostStart .. hostEndPos] : url[hostStart .. $];
				}

				bool isExternal = ourHost.length > 0 && !referer.canFind(ourHost);

				if (isExternal && referer !in seenReferrers)
				{
					seenReferrers[referer] = true;
					auto evt = JourneyEvent(timestamp, "referrer", "External referrer", true, "", logFileName, lineNum);
					evt.url = referer;
					webEvents ~= evt;
				}
			}

			// Add page visit event
			auto eventMessage = method == "POST" ? "Form submission" : "Page visit";
			auto evt = JourneyEvent(timestamp, "page_visit", eventMessage, true, displayPath, logFileName, lineNum);
			evt.url = url;
			webEvents ~= evt;
		}

		return webEvents;
	}

	// Track IP and User-Agent for web log correlation
	string userIP;
	string userAgent;

	// Parse each log file
	foreach (ref related; relatedLogs)
	{
		auto logFile = related.file;
		if (!exists(logFile))
			continue;

		auto content = cast(string)read(logFile);
		auto logFileName = baseName(logFile);

		// Extract post ID from filename to show which attempt this is
		string logPostID;
		auto m = logFile.matchFirst(`PostProcess-([a-z]{20})\.log`);
		if (m)
			logPostID = m.captures[1];

		// Add log file header with evidence
		events ~= JourneyEvent("", "log_file", logFileName, true, related.evidence, logFileName, 0);

		int lineNum = 0;
		foreach (line; content.split("\n"))
		{
			lineNum++;
			if (line.length < 30 || line[0] != '[')
				continue;

			// Extract timestamp
			auto closeBracket = line.indexOf("]");
			if (closeBracket < 0)
				continue;
			auto timestamp = line[1..closeBracket];
			auto message = line[closeBracket + 2 .. $];

			// Parse different event types
			if (message.startsWith("IP: "))
			{
				userIP = message[4..$];
				events ~= JourneyEvent(timestamp, "info", "IP Address", true, message[4..$], logFileName, lineNum);
			}
			else if (message.startsWith("[Header] User-Agent: "))
			{
				userAgent = message[21..$];
			}
			else if (message.startsWith("CAPTCHA OK"))
			{
				events ~= JourneyEvent(timestamp, "captcha", "CAPTCHA solved successfully", true, "", logFileName, lineNum);
			}
			else if (message.startsWith("  CAPTCHA question: "))
			{
				auto jsonStr = message[20..$];
				string question;
				try
					question = jsonParse!string(jsonStr);
				catch (Exception)
					question = jsonStr; // Fallback if not valid JSON
				events ~= JourneyEvent(timestamp, "captcha", "CAPTCHA question", true, question, logFileName, lineNum);
			}
			else if (message.startsWith("[Form] "))
			{
				// Check if this form field is a CAPTCHA response
				auto formContent = message[7..$];
				auto colonPos = formContent.indexOf(": ");
				if (colonPos >= 0)
				{
					auto fieldName = formContent[0..colonPos];
					auto fieldValue = formContent[colonPos + 2..$];
					auto captchaResponse = getCaptchaResponseFromField(fieldName, fieldValue);
					if (captchaResponse !is null)
						events ~= JourneyEvent(timestamp, "captcha", "CAPTCHA answer", true, captchaResponse, logFileName, lineNum);
				}
			}
			else if (message.startsWith("CAPTCHA failed: "))
			{
				events ~= JourneyEvent(timestamp, "captcha", "CAPTCHA failed", false, message[16..$], logFileName, lineNum);
			}
			else if (message.startsWith("Spam check failed (spamicity: "))
			{
				auto spamMatch = message.matchFirst(`Spam check failed \(spamicity: ([\d.]+)\): (.+)`);
				if (spamMatch)
					events ~= JourneyEvent(timestamp, "spam_check", "Spam check failed", false,
						"Spamicity: " ~ spamMatch[1] ~ " - " ~ spamMatch[2], logFileName, lineNum);
			}
			else if (message.startsWith("Spam check OK (spamicity: "))
			{
				auto spamMatch = message.matchFirst(`Spam check OK \(spamicity: ([\d.]+)\)`);
				if (spamMatch)
					events ~= JourneyEvent(timestamp, "spam_check", "Spam check passed", true,
						"Spamicity: " ~ spamMatch[1], logFileName, lineNum);
			}
			else if (message.startsWith("User is trusted, skipping spam check"))
			{
				events ~= JourneyEvent(timestamp, "spam_check", "Trusted user, spam check skipped", true, "", logFileName, lineNum);
			}
			else if (message.startsWith("Got reply from spam checker "))
			{
				auto checkerMatch = message.matchFirst(`Got reply from spam checker [^:]+\.([^.:]+): spamicity ([\d.]+) \(([^)]*)\)`);
				if (checkerMatch)
				{
					auto checkerName = checkerMatch[1];
					auto spamicity = checkerMatch[2];
					auto detail = checkerMatch[3];
					auto detailStr = detail.length > 0 ? " (" ~ detail ~ ")" : "";
					events ~= JourneyEvent(timestamp, "spam_detail", checkerName, true,
						"Spamicity: " ~ spamicity ~ detailStr, logFileName, lineNum);
				}
			}
			else if (message.startsWith("Quarantined for moderation: "))
			{
				events ~= JourneyEvent(timestamp, "moderation", "Quarantined for moderation", false, message[28..$], logFileName, lineNum);
			}
			else if (message.startsWith("< Message-ID: <"))
			{
				events ~= JourneyEvent(timestamp, "posted", "Post created with Message-ID", true,
					message[15..$-1], logFileName, lineNum); // Remove "< Message-ID: <" and final ">"
			}
		}
	}

	// Search for approval event
	if (primaryLog !is null)
		searchBannedLog(postID, primaryLog);

	// Parse Web.log for page visits (returns separate array, doesn't modify events)
	JourneyEvent[] webEvents;
	if (primaryLog !is null)
		webEvents = parseWebLog(primaryLog, userIP, userAgent);

	// Interleave web events between PostProcess log sections based on timestamps
	if (webEvents.length > 0)
	{
		// Sort web events by timestamp
		webEvents.sort!((a, b) => a.timestamp < b.timestamp);

		// Split events into sections (each section starts with a log_file header)
		struct LogSection
		{
			size_t startIdx;  // Index of log_file header in events array
			size_t endIdx;    // Index after last event in this section
			string firstTimestamp;  // First non-header event timestamp
		}
		LogSection[] sections;

		for (size_t i = 0; i < events.length; i++)
		{
			if (events[i].type == "log_file")
			{
				LogSection section;
				section.startIdx = i;
				// Find the end of this section (next log_file header or end of array)
				size_t j = i + 1;
				while (j < events.length && events[j].type != "log_file")
				{
					if (section.firstTimestamp.length == 0 && events[j].timestamp.length > 0)
						section.firstTimestamp = events[j].timestamp;
					j++;
				}
				section.endIdx = j;
				sections ~= section;
				i = j - 1;  // Continue from end of section
			}
		}

		// Rebuild events with web events interleaved
		JourneyEvent[] newEvents;
		size_t webIdx = 0;

		foreach (sectionIdx, ref section; sections)
		{
			// Insert web events that occurred before this section's first event
			while (webIdx < webEvents.length &&
				   (section.firstTimestamp.length == 0 || webEvents[webIdx].timestamp < section.firstTimestamp))
			{
				newEvents ~= webEvents[webIdx];
				webIdx++;
			}

			// Add this section's events
			for (size_t i = section.startIdx; i < section.endIdx; i++)
				newEvents ~= events[i];
		}

		// Add any remaining web events after all sections
		while (webIdx < webEvents.length)
		{
			newEvents ~= webEvents[webIdx];
			webIdx++;
		}

		events = newEvents;
	}

	return events;
}

void renderJourneyTimeline(JourneyEvent[] events)
{
	import std.conv : to;

	if (events.length == 0)
		return;

	html.put(
		`<style>` ~
			`.journey-timeline { margin-bottom: 1em; }` ~
			`.journey-timeline h3 { margin: 0 0 0.5em 0; }` ~
			`.journey-events { border-top: 2px solid #E6E6E6; font-family: Consolas, Lucida Console, Menlo, monospace; font-size: 0.9em; }` ~
			`.journey-event { padding: 0.5em 0.75em; border-left: 4px solid #E6E6E6; border-right: 2px solid #E6E6E6; background: #FCFCFC; border-bottom: 1px solid #E6E6E6; }` ~
			`.journey-event:last-child { border-bottom: 2px solid #E6E6E6; }` ~
			`.journey-event.success { border-left-color: #5A5; background: #F5FFF5; }` ~
			`.journey-event.failure { border-left-color: #A55; background: #FFF5F5; }` ~
			`.journey-event.info { border-left-color: #58A; background: #F5F9FF; }` ~
			`.journey-event.spam_detail { border-left-color: #A85; background: #FFFAF5; padding: 0.33em 0.75em; }` ~
			`.journey-event.log_file { border-left-color: #85A; background: #F5F5F5; }` ~
			`.journey-event.approval { border-left-color: #5A5; background: #F0FFF0; }` ~
			`.journey-event.page_visit { border-left-color: #59A; background: #F5FAFF; }` ~
			`.journey-event.referrer { border-left-color: #A59; background: #FAF5FF; }` ~
			`.journey-event.log_file:not(:first-child) { margin-top: 1em; border-top: 2px solid #E6E6E6; }` ~
			`.journey-timestamp { color: #666; font-size: 0.95em; }` ~
			`.journey-message { font-weight: bold; }` ~
			`.journey-details { color: #666; font-size: 0.95em; margin-top: 0.25em; }` ~
			`.journey-details a { color: #369; }` ~
			`.journey-source { color: #999; font-size: 0.9em; float: right; }` ~
		`</style>` ~
		`<div class="journey-timeline">` ~
			`<h3>User Journey</h3>` ~
			`<div class="journey-events">`
	);

	foreach (event; events)
	{
		string cssClass;
		if (event.type == "log_file")
			cssClass = "log_file";
		else if (event.type == "spam_detail")
			cssClass = "spam_detail";
		else if (event.type == "approval")
			cssClass = "approval";
		else if (event.type == "page_visit")
			cssClass = "page_visit";
		else if (event.type == "referrer")
			cssClass = "referrer";
		else if (event.success)
			cssClass = "success";
		else if (event.type == "info")
			cssClass = "info";
		else
			cssClass = "failure";

		html.put(`<div class="journey-event `, cssClass, `">`);

		// Show source file:line for regular events
		if (event.type != "log_file" && event.sourceFile.length > 0 && event.lineNumber > 0)
		{
			html.put(`<span class="journey-source">`);
			html.putEncodedEntities(event.sourceFile ~ ":" ~ event.lineNumber.to!string);
			html.put(`</span>`);
		}

		if (event.timestamp.length > 0)
		{
			html.put(`<span class="journey-timestamp">`);
			html.putEncodedEntities(event.timestamp);
			html.put(` </span>`);
		}

		html.put(`<span class="journey-message">`);
		html.putEncodedEntities(event.message);
		html.put(`</span>`);

		if (event.details.length > 0 || event.url.length > 0)
		{
			html.put(`<div class="journey-details">`);
			if (event.url.length > 0)
			{
				html.put(`<a href="`);
				html.putEncodedEntities(event.url);
				html.put(`" target="_blank" rel="noopener">`);
				// For page visits, show the path; for referrers, show the full URL
				if (event.details.length > 0)
					html.putEncodedEntities(event.details);
				else
					html.putEncodedEntities(event.url);
				html.put(`</a>`);
			}
			else
			{
				html.putEncodedEntities(event.details);
			}
			html.put(`</div>`);
		}
		html.put(`</div>`);
	}

	html.put(`</div></div>`);
}

void discussionModeration(Rfc850Post post, UrlParameters postVars)
{
	if (postVars == UrlParameters.init)
	{
		// Display user journey timeline
		auto journeyEvents = parsePostingJourney(post.id);
		renderJourneyTimeline(journeyEvents);

		auto sinkNames = post.xref
			.map!(x => x.group.getGroupInfo())
			.filter!(g => g.sinkType == "nntp")
			.map!(g => g.sinkName[])
			.array.sort.uniq
		;
		auto deleteCommands = sinkNames
			.map!(sinkName => loadIni!NntpConfig(resolveSiteFile("config/sources/nntp/" ~ sinkName ~ ".ini")).deleteCommand)
			.filter!identity
		;
		html.put(
			`<form method="post" class="forum-form delete-form" id="deleteform">` ~
				`<input type="hidden" name="id" value="`), html.putEncodedEntities(post.id), html.put(`">` ~
				`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~

				`<div id="deleteform-info">` ~
					_!`Perform which moderation actions on this post?` ~
				`</div>` ~

				`<textarea id="deleteform-message" readonly="readonly" rows="25" cols="80">`
					), html.putEncodedEntities(post.message), html.put(
				`</textarea><br>` ~

				`<input type="checkbox" name="delete" value="Yes" checked id="deleteform-delete"></input>` ~
				`<label for="deleteform-delete">` ~
					_!`Delete local cached copy of this post from DFeed's database` ~
				`</label><br>`,

				findPostingLog(post.id)
				?	`<input type="checkbox" name="ban" value="Yes" id="deleteform-ban"></input>` ~
					`<label for="deleteform-ban">` ~
						_!`Ban poster (place future posts in moderation queue)` ~
					`</label><br>`
				: ``,

				!deleteCommands.empty
				?	`<input type="checkbox" name="delsource" value="Yes" id="deleteform-delsource"></input>` ~
					`<label for="deleteform-delsource">` ~
						_!`Delete source copy from %-(%s/%)`.format(sinkNames.map!encodeHtmlEntities) ~
					`</label><br>`
				: ``,

				`<input type="checkbox" name="callsinks" value="Yes" checked id="deleteform-sinks"></input>` ~
				`<label for="deleteform-sinks">` ~
					_!`Try to moderate in other message sinks (e.g. Twitter)` ~
				`</label><br>`,

				_!`Reason:`, ` <input name="reason" value="spam"></input><br>` ~
				`<input type="submit" value="`, _!`Moderate`, `"></input>` ~
			`</form>`
		);
	}
	else
	{
		if (postVars.get("secret", "") != userSettings.secret)
			throw new Exception(_!"XSRF secret verification failed. Are your cookies enabled?");

		string messageID = postVars.get("id", "");
		string userName = user.getName();
		string reason = postVars.get("reason", "");
		bool deleteLocally = postVars.get("delete"   , "No") == "Yes";
		bool ban           = postVars.get("ban"      , "No") == "Yes";
		bool delSource     = postVars.get("delsource", "No") == "Yes";
		bool callSinks     = postVars.get("callsinks", "No") == "Yes";

		if (deleteLocally || ban || delSource)
			moderatePost(
				messageID,
				reason,
				userName,
				deleteLocally ? Yes.deleteLocally : No.deleteLocally,
				ban           ? Yes.ban           : No.ban          ,
				delSource     ? Yes.deleteSource  : No.deleteSource ,
				callSinks     ? Yes.callSinks     : No.callSinks    ,
				(string s) { html.put(encodeHtmlEntities(s) ~ "<br>"); },
			);
		else
			html.put("No actions specified!");
	}
}

void deletePostApi(string group, int artNum)
{
	string messageID;
	foreach (string id; query!"SELECT [ID] FROM [Groups] WHERE [Group] = ? AND [ArtNum] = ?".iterate(group, artNum))
		messageID = id;
	enforce(messageID, "No such article in this group");

	string reason = "API call";
	string userName = "API";

	moderatePost(
		messageID,
		reason,
		userName,
		Yes.deleteLocally,
		No.ban,
		No.deleteSource,
		Yes.callSinks,
		(string s) { html.put(s ~ "\n"); },
	);
}

private void discussionFlagPageImpl(bool flag)(Rfc850Post post, UrlParameters postParams)
{
	static immutable string[2] actions = ["unflag", "flag"];
	bool isFlagged = query!`SELECT COUNT(*) FROM [Flags] WHERE [Username]=? AND [PostID]=?`.iterate(user.getName(), post.id).selectValue!int > 0;
	if (postParams == UrlParameters.init)
	{
		if (flag == isFlagged)
		{
		html.put(
			`<div id="flagform-info" class="forum-notice">` ~
				_!(`It looks like you've already ` ~ actions[flag] ~ `ged this post.`), ` `,
				_!(`Would you like to %s` ~ actions[!flag] ~ ` it%s?`).format(
					`<a href="` ~ encodeHtmlEntities(idToUrl(post.id, actions[!flag])) ~ `">`,
					`</a>`,
				),
			`</div>`);
		}
		else
		{
			html.put(
				`<div id="flagform-info" class="forum-notice">`,
					_!(`Are you sure you want to ` ~ actions[flag] ~ ` this post?`),
				`</div>`);
			formatPost(post, null, false);
			html.put(
				`<form action="" method="post" class="forum-form flag-form" id="flagform">` ~
					`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
					`<input type="submit" name="flag" value="`, _!(actions[flag].capitalize), `"></input>` ~
					`<input type="submit" name="cancel" value="`, _!`Cancel`, `"></input>` ~
				`</form>`);
		}
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, _!"XSRF secret verification failed. Are your cookies enabled?");
		enforce(user.getLevel() >= User.Level.canFlag, _!"You can't flag posts!");
		enforce(user.createdAt() < post.time, _!"You can't flag this post!");

		if ("flag" in postParams)
		{
			enforce(flag != isFlagged, _!("You've already " ~ actions[flag] ~ "ged this post."));

			if (flag)
				query!`INSERT INTO [Flags] ([PostID], [Username], [Date]) VALUES (?, ?, ?)`.exec(post.id, user.getName(), Clock.currTime.stdTime);
			else
				query!`DELETE FROM [Flags] WHERE [PostID]=? AND [Username]=?`.exec(post.id, user.getName());

			html.put(
				`<div id="flagform-info" class="forum-notice">`,
					_!(`Post ` ~ actions[flag] ~ `ged.`),
				`</div>` ~
				`<form action="" method="post" class="forum-form flag-form" id="flagform">` ~
					`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
					`<input type="submit" name="cancel" value="`, _!`Return to post`, `"></input>` ~
				`</form>`);

			static if (flag)
			{
				auto subject = "%s flagged %s's post in the thread \"%s\"".format(
					user.getName(),
					post.author,
					post.subject,
				);

				foreach (mod; site.moderators)
					sendMail(q"EOF
From: %1$s <no-reply@%2$s>
To: %3$s
Subject: %4$s
Content-Type: text/plain; charset=utf-8

Howdy %5$s,

%4$s:
%6$s://%7$s%8$s

Here is the message that was flagged:
----------------------------------------------
%9$-(%s
%)
----------------------------------------------

If you believe this message should be deleted, you can click here to do so:
%6$s://%7$s%10$s

All the best,
%1$s

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
You are receiving this message because you are configured as a site moderator on %2$s.

To stop receiving messages like this, please ask the administrator of %1$s to remove you from the list of moderators.
.
EOF"
						.format(
							/* 1*/ site.name.length ? site.name : site.host,
							/* 2*/ site.host,
							/* 3*/ mod,
							/* 4*/ subject,
							/* 5*/ mod.canFind("<") ? mod.findSplit("<")[0].findSplit(" ")[0] : mod.findSplit("@")[0],
							/* 6*/ site.proto,
							/* 7*/ site.host,
							/* 8*/ idToUrl(post.id),
							/* 9*/ post.content.strip.splitAsciiLines.map!(line => line.length ? "> " ~ line : ">"),
							/*10*/ idToUrl(post.id, "delete"),
						));
			}
		}
		else
			throw new Redirect(idToUrl(post.id));
	}
}

void discussionFlagPage(Rfc850Post post, bool flag, UrlParameters postParams)
{
	if (flag)
		discussionFlagPageImpl!true (post, postParams);
	else
		discussionFlagPageImpl!false(post, postParams);
}

void discussionApprovePage(string draftID, UrlParameters postParams)
{
	auto draft = getDraft(draftID);
	if (draft.status == PostDraft.Status.sent && "pid" in draft.serverVars)
	{
		html.put(_!`This message has already been posted.`, ` ` ~
			`<a href="`), html.putEncodedEntities(idToUrl(PostProcess.pidToMessageID(draft.serverVars["pid"]))), html.put(`">`, _!`You can view it here.`, `</a>`);
		return;
	}
	enforce(draft.status == PostDraft.Status.moderation,
		_!"This is not a post in need of moderation. Its status is currently:" ~ " " ~ text(draft.status));

	if (postParams == UrlParameters.init)
	{
		// Display user journey timeline if we have a pid
		if ("pid" in draft.serverVars)
		{
			auto messageID = PostProcess.pidToMessageID(draft.serverVars["pid"]);
			auto journeyEvents = parsePostingJourney(messageID);
			renderJourneyTimeline(journeyEvents);
		}

		html.put(
			`<div id="approveform-info" class="forum-notice">`,
				_!`Are you sure you want to approve this post?`,
			`</div>`);
		auto post = draftToPost(draft);
		formatPost(post, null, false);
		html.put(
			`<form action="" method="post" class="forum-form approve-form" id="approveform">` ~
				`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
				`<input type="submit" name="approve" value="`, _!`Approve`, `"></input>` ~
				`<input type="submit" name="cancel" value="`, _!`Cancel`, `"></input>` ~
			`</form>`);
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, _!"XSRF secret verification failed. Are your cookies enabled?");

		if ("approve" in postParams)
		{
			auto pid = approvePost(draftID, user.getName());

			html.put(_!`Post approved!`, ` <a href="/posting/` ~ pid ~ `">`, _!`View posting`, `</a>`);
		}
		else
			throw new Redirect("/");
	}
}

void discussionUnbanByKeyPage(string key, UrlParameters postParams)
{
	import std.algorithm.iteration : map;
	import std.conv : to;

	if (postParams == UrlParameters.init)
	{
		auto tree = getUnbanPreviewByKey(key);
		if (tree.allNodes.length == 0)
		{
			html.put(
				`<div id="unbanform-info" class="forum-notice">`,
					_!`The specified key is not banned.`,
				`</div>` ~
				`<form action="" method="get" class="forum-form unban-form" id="unbanform">` ~
					`<label for="key">`, _!`Key to unban:`, `</label>` ~
					`<input type="text" name="key" id="key" size="60" value="`), html.putEncodedEntities(key), html.put(`">` ~
					`<input type="submit" value="`, _!`Look up`, `"></input>` ~
				`</form>`);
			return;
		}

		html.put(
			`<div id="unbanform-info" class="forum-notice">`,
				_!`Select which keys to unban:`,
			`</div>` ~
			`<style>` ~
				`.unban-tree { margin-left: 0; padding-left: 20px; list-style: none; }` ~
				`.unban-tree li { margin: 8px 0; }` ~
				`.unban-tree .unban-key { font-family: monospace; font-weight: bold; }` ~
				`.unban-tree .unban-reason { color: #666; font-style: italic; }` ~
				`.unban-tree .unban-unban-reason { color: #080; }` ~
				`.unban-node { padding: 4px; }` ~
				`.unban-node:hover { background-color: #f0f0f0; }` ~
			`</style>`);

		void renderNode(UnbanTree.Node* node, int depth = 0)
		{
			html.put(`<li><div class="unban-node">`);
			html.put(`<input type="checkbox" name="key" value="`);
			html.putEncodedEntities(node.key);
			html.put(`" id="key-`, depth.to!string, `-`);
			html.putEncodedEntities(node.key);
			html.put(`" checked> <label for="key-`, depth.to!string, `-`);
			html.putEncodedEntities(node.key);
			html.put(`"><span class="unban-key">`);
			html.putEncodedEntities(node.key);
			html.put(`</span> <span class="unban-reason">(`);
			html.putEncodedEntities(node.reason);
			html.put(`)</span> <span class="unban-unban-reason">— `);
			html.putEncodedEntities(node.unbanReason);
			html.put(`</span></label></div>`);

			if (node.children.length > 0)
			{
				html.put(`<ul class="unban-tree">`);
				foreach (child; node.children)
					renderNode(child, depth + 1);
				html.put(`</ul>`);
			}

			html.put(`</li>`);
		}

		html.put(
			`<form action="" method="post" class="forum-form unban-form" id="unbanform">` ~
				`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
				`<input type="hidden" name="lookup-key" value="`), html.putEncodedEntities(key), html.put(`">`);

		html.put(`<ul class="unban-tree">`);
		foreach (root; tree.roots)
			renderNode(root);
		html.put(`</ul>`);

		html.put(
				`<input type="submit" name="unban" value="`, _!`Unban Selected`, `"></input>` ~
				`<input type="submit" name="cancel" value="`, _!`Cancel`, `"></input>` ~
			`</form>`);
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, _!"XSRF secret verification failed. Are your cookies enabled?");

		if ("unban" in postParams)
		{
			// Collect all checked keys
			string[] keysToUnban;
			foreach (name, value; postParams)
				if (name == "key")
					keysToUnban ~= value;

			enforce(keysToUnban.length > 0, _!"No keys selected to unban");

			// Use the lookup key as a dummy ID for logging
			auto lookupKey = postParams.get("lookup-key", key);
			unbanPoster(user.getName(), "<unban-by-key:" ~ lookupKey ~ ">", keysToUnban);

			html.put(format(_!`Unbanned %d key(s)!`, keysToUnban.length), ` <a href="/unban">`, _!`Unban another key`, `</a>`);
		}
		else
			throw new Redirect("/");
	}
}

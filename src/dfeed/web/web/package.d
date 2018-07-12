/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.web.web;

import core.time;

import std.algorithm;
import std.array;
import std.base64;
import std.conv;
import std.datetime : SysTime, Clock, UTC;
import std.digest.sha;
import std.exception;
import std.file;
import std.functional;
import std.path;
import std.random;
import std.range;
import std.regex;
import std.stdio;
import std.string;

alias std.string.indexOf indexOf;

import ae.net.asockets;
import ae.net.http.caching;
import ae.net.http.responseex;
import ae.net.http.server;
import ae.net.ietf.headers;
import ae.net.ietf.url;
import ae.net.ietf.wrap;
import ae.sys.log;
import ae.utils.array;
import ae.utils.digest;
import ae.utils.exception;
import ae.utils.feed;
import ae.utils.json;
import ae.utils.meta;
import ae.utils.regex;
import ae.utils.sini : loadIni;
import ae.utils.text;
import ae.utils.text.html;
import ae.utils.textout;
import ae.utils.time.format;
import ae.utils.time.parse;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.bayes;
import dfeed.common;
import dfeed.database;
import dfeed.groups;
import dfeed.mail;
import dfeed.message;
import dfeed.sinks.cache;
import dfeed.sinks.messagedb : searchTerm, threadID;
import dfeed.sinks.subscriptions;
import dfeed.site;
import dfeed.sources.github;
import dfeed.web.captcha;
import dfeed.web.lint;
import dfeed.web.list;
//import dfeed.web.mailhide;
import dfeed.web.posting;
import dfeed.web.user : User, getUser, SettingType;
import dfeed.web.spam : bayes, getSpamicity;
import dfeed.web.web.cache;
import dfeed.web.web.config;
import dfeed.web.web.draft : getDraft, saveDraft, draftToPost;
import dfeed.web.web.part.gravatar : getGravatarHash, putGravatar;
import dfeed.web.web.part.pager;
import dfeed.web.web.part.post : postLink, miniPostInfo;
import dfeed.web.web.part.thread : formatThreadedPosts;
import dfeed.web.web.perf;
import dfeed.web.web.posting : postDraft;
import dfeed.web.web.postmod : learnModeratedMessage;
import dfeed.web.web.request : onRequest, currentRequest, ip;
import dfeed.web.web.statics;
import dfeed.web.web.view.post : formatPost, formatSplitPost;
import dfeed.web.web.view.thread : getPostThreadIndex, getPostAtThreadIndex;
import dfeed.web.web.user : user, userSettings;

StringBuffer html;

alias config = dfeed.web.web.config.config;

// ***********************************************************************

string settingsReferrer;

void discussionSettings(UrlParameters getVars, UrlParameters postVars)
{
	settingsReferrer = postVars.get("referrer", currentRequest.headers.get("Referer", null));

	if (postVars)
	{
		if (postVars.get("secret", "") != userSettings.secret)
			throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

		auto actions = postVars.keys.filter!(name => name.startsWith("action-"));
		enforce(!actions.empty, "No action specified");
		auto action = actions.front[7..$];

		if (action == "cancel")
			throw new Redirect(settingsReferrer ? settingsReferrer : "/");
		else
		if (action == "save")
		{
			// Inputs
			foreach (setting; ["groupviewmode"])
				if (setting in postVars)
					userSettings.set(setting, postVars[setting]);
			// Checkboxes
			foreach (setting; ["enable-keynav", "auto-open"])
				userSettings.set(setting, setting in postVars ? "true" : "false");

			userSettings.pendingNotice = "settings-saved";
			throw new Redirect(settingsReferrer ? settingsReferrer : "/settings");
		}
		else
		if (action == "subscription-cancel")
			{}
		else
		if (action.skipOver("subscription-edit-"))
		{
			auto subscriptionID = action;
			return discussionSubscriptionEdit(getUserSubscription(user.getName(), subscriptionID));
		}
		else
		if (action.skipOver("subscription-view-"))
			throw new Redirect("/subscription-posts/" ~ action);
		else
		if (action.skipOver("subscription-feed-"))
			throw new Redirect("/subscription-feed/" ~ action);
		else
		if (action == "subscription-save" || action == "subscription-undelete")
		{
			string message;
			if (action == "subscription-undelete")
				message = "Subscription undeleted.";
			else
			if (subscriptionExists(postVars.get("id", null)))
				message = "Subscription saved.";
			else
				message = "Subscription created.";

			auto subscription = Subscription(user.getName(), postVars);
			try
			{
				subscription.save();
				html.put(`<div class="forum-notice">`, message, `</div>`);
			}
			catch (Exception e)
			{
				html.put(`<div class="form-error">`), html.putEncodedEntities(e.msg), html.put(`</div>`);
				return discussionSubscriptionEdit(subscription);
			}
		}
		else
		if (action.skipOver("subscription-delete-"))
		{
			auto subscriptionID = action;
			enforce(subscriptionExists(subscriptionID), "This subscription doesn't exist.");

			html.put(
				`<div class="forum-notice">Subscription deleted. ` ~
				`<input type="submit" name="action-subscription-undelete" value="Undo" form="subscription-form">` ~
				`</div>` ~
				`<div style="display:none">`
			);
			// Replicate the entire edit form here (but make it invisible),
			// so that saving the subscription recreates it on the server.
			discussionSubscriptionEdit(getUserSubscription(user.getName(), subscriptionID));
			html.put(
				`</div>`
			);

			getUserSubscription(user.getName(), subscriptionID).remove();
		}
		else
		if (action == "subscription-create-content")
			return discussionSubscriptionEdit(createSubscription(user.getName(), "content"));
		else
			throw new Exception("Unknown action: " ~ action);
	}

	html.put(
		`<form method="post" id="settings-form">` ~
		`<h1>Settings</h1>` ~
		`<input type="hidden" name="referrer" value="`), html.putEncodedEntities(settingsReferrer), html.put(`">` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~

		`<h2>User Interface</h2>` ~

		`View mode: <select name="groupviewmode">`
	);
	auto currentMode = userSettings.groupViewMode;
	foreach (mode; ["basic", "threaded", "horizontal-split", "vertical-split"])
		html.put(`<option value="`, mode, `"`, mode == currentMode ? ` selected` : null, `>`, mode, `</option>`);
	html.put(
		`</select><br>` ~

		`<input type="checkbox" name="enable-keynav" id="enable-keynav"`, userSettings.enableKeyNav == "true" ? ` checked` : null, `>` ~
		`<label for="enable-keynav">Enable keyboard shortcuts</label> (<a href="/help#keynav">?</a>)<br>` ~

		`<span title="Automatically open messages after selecting them.&#13;&#10;Applicable to threaded, horizontal-split and vertical-split view modes.">` ~
			`<input type="checkbox" name="auto-open" id="auto-open"`, userSettings.autoOpen == "true" ? ` checked` : null, `>` ~
			`<label for="auto-open">Focus follows message</label>` ~
		`</span><br>` ~

		`<p>` ~
			`<input type="submit" name="action-save" value="Save">` ~
			`<input type="submit" name="action-cancel" value="Cancel">` ~
		`</p>` ~

		`<hr>` ~

		`<h2>Subscriptions</h2>`
	);
	if (user.isLoggedIn())
	{
		auto subscriptions = getUserSubscriptions(user.getName());
		if (subscriptions.length)
		{
			html.put(`<table id="subscriptions">`);
			html.put(`<tr><th>Subscription</th><th colspan="2">Actions</th></tr>`);
			foreach (subscription; subscriptions)
			{
				html.put(
					`<tr>` ~
						`<td>`), subscription.trigger.putDescription(html), html.put(`</td>` ~
						`<td><input type="submit" form="subscriptions-form" name="action-subscription-view-`  , subscription.id, `" value="View posts"></td>` ~
						`<td><input type="submit" form="subscriptions-form" name="action-subscription-feed-`  , subscription.id, `" value="Get ATOM feed"></td>` ~
						`<td><input type="submit" form="subscriptions-form" name="action-subscription-edit-`  , subscription.id, `" value="Edit"></td>` ~
						`<td><input type="submit" form="subscriptions-form" name="action-subscription-delete-`, subscription.id, `" value="Delete"></td>` ~
					`</tr>`
				);
			}
			html.put(
				`</table>`
			);
		}
		else
			html.put(`<p>You have no subscriptions.</p>`);
		html.put(
			`<p><input type="submit" form="subscriptions-form" name="action-subscription-create-content" value="Create new content alert subscription"></p>`
		);
	}
	else
		html.put(`<p>Please <a href="/loginform">log in</a> to manage your subscriptions.</p>`);

	html.put(
		`</form>` ~

		`<form method="post" id="subscriptions-form">` ~
		`<input type="hidden" name="referrer" value="`), html.putEncodedEntities(settingsReferrer), html.put(`">` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`</form>`
	);
}

void discussionSubscriptionEdit(Subscription subscription)
{
	html.put(
		`<form action="/settings" method="post" id="subscription-form">` ~
		`<h1>Edit subscription</h1>` ~
		`<input type="hidden" name="referrer" value="`), html.putEncodedEntities(settingsReferrer), html.put(`">` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`<input type="hidden" name="id" value="`, subscription.id, `">` ~

		`<h2>Condition</h2>` ~
		`<input type="hidden" name="trigger-type" value="`, subscription.trigger.type, `">`
	);
	subscription.trigger.putEditHTML(html);

	html.put(
		`<h2>Actions</h2>`
	);

	foreach (action; subscription.actions)
		action.putEditHTML(html);

	html.put(
		`<p>` ~
			`<input type="submit" name="action-subscription-save" value="Save">` ~
			`<input type="submit" name="action-subscription-cancel" value="Cancel">` ~
		`</p>` ~
		`</form>`
	);
}

void discussionSubscriptionUnsubscribe(string subscriptionID)
{
	auto subscription = getSubscription(subscriptionID);
	subscription.unsubscribe();
	html.put(
		`<h1>Unsubscribe</h1>` ~
		`<p>This subscription has been deactivated.</p>` ~
		`<p>If you did not intend to do this, you can reactivate the subscription's actions on your <a href="/settings">settings page</a>.</p>`
	);
}

void discussionSubscriptionPosts(string subscriptionID, int page, out string title)
{
	auto subscription = getUserSubscription(user.getName(), subscriptionID);
	title = "View subscription: " ~ subscription.trigger.getTextDescription();

	enum postsPerPage = POSTS_PER_PAGE;
	html.put(`<h1>`); html.putEncodedEntities(title);
	if (page != 1)
		html.put(" (page ", text(page), ")");
	html.put("</h1>");

	auto postCount = query!"SELECT COUNT(*) FROM [SubscriptionPosts] WHERE [SubscriptionID] = ?".iterate(subscriptionID).selectValue!int;

	if (postCount == 0)
	{
		html.put(`<p>It looks like there's nothing here! No posts matched this subscription so far.</p>`);
	}

	foreach (string messageID; query!"SELECT [MessageID] FROM [SubscriptionPosts] WHERE [SubscriptionID] = ? ORDER BY [Time] DESC LIMIT ? OFFSET ?"
						.iterate(subscriptionID, postsPerPage, (page-1)*postsPerPage))
	{
		auto post = getPost(messageID);
		if (post)
			formatPost(post, null);
	}

	if (page != 1 || postCount > postsPerPage)
	{
		html.put(`<table class="forum-table post-pager">`);
		pager(null, page, getPageCount(postCount, postsPerPage));
		html.put(`</table>`);
	}

	html.put(
		`<form style="display:block;float:right;margin-top:0.5em" action="/settings" method="post">` ~
			`<input type="hidden" name="secret" value="`), html.putEncodedEntities(userSettings.secret), html.put(`">` ~
			`<input type="submit" name="action-subscription-edit-`), html.putEncodedEntities(subscriptionID), html.put(`" value="Edit subscription">` ~
		`</form>` ~
		`<div style="clear:right"></div>`
	);
}

// ***********************************************************************

/// Delimiters for formatSearchSnippet.
enum searchDelimPrefix     = "\U000FDeed"; // Private Use Area character
enum searchDelimStartMatch = searchDelimPrefix ~ "\x01";
enum searchDelimEndMatch   = searchDelimPrefix ~ "\x02";
enum searchDelimEllipses   = searchDelimPrefix ~ "\x03";
enum searchDelimLength     = searchDelimPrefix.length + 1;

void discussionSearch(UrlParameters parameters)
{
	// HTTP form parameters => search string (visible in form, ?q= parameter) => search query (sent to database)

	string[] terms;
	if (string searchScope = parameters.get("scope", null))
	{
		if (searchScope.startsWith("dlang.org"))
			throw new Redirect("https://www.google.com/search?" ~ encodeUrlParameters(["sitesearch" : searchScope, "q" : parameters.get("q", null)]));
		else
		if (searchScope == "forum")
			{}
		else
		if (searchScope.startsWith("group:") || searchScope.startsWith("threadmd5:"))
			terms ~= searchScope;
	}
	terms ~= parameters.get("q", null);

	if (parameters.get("exact", null).length)
		terms ~= '"' ~ parameters["exact"].replace(`"`, ``) ~ '"';

	if (parameters.get("not", null).length)
		foreach (word; parameters["not"].split)
			terms ~= "-" ~ word.stripLeft('-');

	foreach (param; ["group", "author", "authoremail", "subject", "content", "newthread"])
		if (parameters.get(param, null).length)
			foreach (word; parameters[param].split)
			{
				if (param == "group")
					word = word.getGroupInfoByPublicName.I!(gi => gi ? gi.internalName.searchTerm : word);
				terms ~= param ~ ":" ~ word;
			}

	if (parameters.get("startdate", null).length || parameters.get("enddate", null).length)
		terms ~= "date:" ~ parameters.get("startdate", null) ~ ".." ~ parameters.get("enddate", null);

	auto searchString = terms.map!strip.filter!(not!empty).join(" ");
	bool doSearch = searchString.length > 0;
	string autoFocus = doSearch ? "" : " autofocus";

	if ("advsearch" in parameters)
	{
		html.put(
			`<form method="get" id="advanced-search-form">` ~
			`<h1>Advanced Search</h1>` ~
			`<p>Find posts with...</p>` ~
			`<table>` ~
				`<tr><td>all these words:`     ~ ` </td><td><input size="50" name="q" value="`), html.putEncodedEntities(searchString), html.put(`"`, autoFocus, `></td></tr>` ~
				`<tr><td>this exact phrase:`   ~ ` </td><td><input size="50" name="exact"></td></tr>` ~
				`<tr><td>none of these words:` ~ ` </td><td><input size="50" name="not"></td></tr>` ~
				`<tr><td>posted in the group:` ~ ` </td><td><input size="50" name="group"></td></tr>` ~
				`<tr><td>posted by:`           ~ ` </td><td><input size="50" name="author"></td></tr>` ~
				`<tr><td>posted by (email):`   ~ ` </td><td><input size="50" name="authoremail"></td></tr>` ~
				`<tr><td>in threads titled:`   ~ ` </td><td><input size="50" name="subject"></td></tr>` ~
				`<tr><td>containing:`          ~ ` </td><td><input size="50" name="content"></td></tr>` ~
				`<tr><td>posted between:`      ~ ` </td><td><input type="date" placeholder="yyyy-mm-dd" name="startdate"> and <input type="date" placeholder="yyyy-mm-dd" name="enddate"></td></tr>` ~
				`<tr><td>posted as new thread:`~ ` </td><td><input type="checkbox" name="newthread" value="y"><input size="1" tabindex="-1" style="visibility:hidden"></td></tr>` ~
			`</table>` ~
			`<br>` ~
			`<input name="search" type="submit" value="Advanced search">` ~
			`</table>` ~
			`</form>`
		);
		doSearch = false;
	}
	else
	{
		html.put(
			`<form method="get" id="search-form">` ~
			`<h1>Search</h1>` ~
			`<input name="q" size="50" value="`), html.putEncodedEntities(searchString), html.put(`"`, autoFocus, `>` ~
			`<input name="search" type="submit" value="Search">` ~
			`<input name="advsearch" type="submit" value="Advanced search">` ~
			`</form>`
		);
	}

	if (doSearch)
		try
		{
			long startDate = 0;
			long endDate = long.max;

			terms = searchString.split();
			string[] queryTerms;
			foreach (term; terms)
				if (term.startsWith("date:") && term.canFind(".."))
				{
					long parseDate(string date, Duration offset, long def)
					{
						if (!date.length)
							return def;
						else
							try
								return (date.parseTime!`Y-m-d` + offset).stdTime;
							catch (Exception e)
								throw new Exception("Invalid date: %s (%s)".format(date, e.msg));
					}

					auto dates = term.findSplit(":")[2].findSplit("..");
					startDate = parseDate(dates[0], 0.days, startDate);
					endDate   = parseDate(dates[2], 1.days, endDate);
				}
				else
				if (term.startsWith("time:") && term.canFind(".."))
				{
					long parseTime(string time, long def)
					{
						return time.length ? time.to!long : def;
					}

					auto times = term.findSplit(":")[2].findSplit("..");
					startDate = parseTime(times[0], startDate);
					endDate   = parseTime(times[2], endDate);
				}
				else
					queryTerms ~= term;

			enforce(startDate < endDate, "Start date must be before end date");
			auto queryString = queryTerms.join(' ');

			int page = parameters.get("page", "1").to!int;
			enforce(page >= 1, "Invalid page number");

			enum postsPerPage = 10;

			int n = 0;

			enum queryCommon =
				"SELECT [ROWID], snippet([PostSearch], '" ~ searchDelimStartMatch ~ "', '" ~ searchDelimEndMatch ~ "', '" ~ searchDelimEllipses ~ "', 6) " ~
				"FROM [PostSearch]";
			auto iterator =
				queryTerms.length
				?
					(startDate == 0 && endDate == long.max)
					? query!(queryCommon ~ " WHERE [PostSearch] MATCH ?                            ORDER BY [Time] DESC LIMIT ? OFFSET ?")
						.iterate(queryString,                     postsPerPage + 1, (page-1)*postsPerPage)
					: query!(queryCommon ~ " WHERE [PostSearch] MATCH ? AND [Time] BETWEEN ? AND ? ORDER BY [Time] DESC LIMIT ? OFFSET ?")
						.iterate(queryString, startDate, endDate, postsPerPage + 1, (page-1)*postsPerPage)
				: query!("SELECT [ROWID], '' FROM [Posts] WHERE [Time] BETWEEN ? AND ? ORDER BY [Time] DESC LIMIT ? OFFSET ?")
					.iterate(startDate, endDate, postsPerPage + 1, (page-1)*postsPerPage)
				;

			foreach (int rowid, string snippet; iterator)
			{
				//html.put(`<pre>`, snippet, `</pre>`);
				string messageID;
				foreach (string id; query!"SELECT [ID] FROM [Posts] WHERE [ROWID] = ?".iterate(rowid))
					messageID = id;
				if (!messageID)
					continue; // Can occur with deleted posts

				n++;
				if (n > postsPerPage)
					break;

				auto post = getPost(messageID);
				if (post)
				{
					if (!snippet.length) // No MATCH (date only)
					{
						enum maxWords = 20;
						auto segments = post.newContent.segmentByWhitespace;
						if (segments.length < maxWords*2)
							snippet = segments.join();
						else
							snippet = segments[0..maxWords*2-1].join() ~ searchDelimEllipses;
					}
					formatSearchResult(post, snippet);
				}
			}

			if (n == 0)
				html.put(`<p>Your search - <b>`), html.putEncodedEntities(searchString), html.put(`</b> - did not match any forum posts.</p>`);

			if (page != 1 || n > postsPerPage)
			{
				html.put(`<table class="forum-table post-pager">`);
				pager("?" ~ encodeUrlParameters(["q" : searchString]), page, n > postsPerPage ? int.max : page);
				html.put(`</table>`);
			}
		}
		catch (CaughtException e)
			html.put(`<div class="form-error">Error: `), html.putEncodedEntities(e.msg), html.put(`</div>`);
}

void formatSearchSnippet(string s)
{
	while (true)
	{
		auto i = s.indexOf(searchDelimPrefix);
		if (i < 0)
			break;
		html.putEncodedEntities(s[0..i]);
		string delim = s[i..i+searchDelimLength];
		s = s[i+searchDelimLength..$];
		switch (delim)
		{
			case searchDelimStartMatch: html.put(`<b>`       ); break;
			case searchDelimEndMatch  : html.put(`</b>`      ); break;
			case searchDelimEllipses  : html.put(`<b>...</b>`); break;
			default: break;
		}
	}
	html.putEncodedEntities(s);
}

void formatSearchResult(Rfc850Post post, string snippet)
{
	string gravatarHash = getGravatarHash(post.authorEmail);

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="post forum-table`, (post.children ? ` with-children` : ``), `" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(2), `</tr>` ~ // Fixed layout dummies
			`<tr class="post-header"><th colspan="2">` ~
				`<div class="post-time">`, summarizeTime(time), `</div>`,
				encodeHtmlEntities(post.publicGroupNames().join(", ")), ` &raquo; ` ~
				`<a title="View this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="permalink `, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr class="mini-post-info-cell">` ~
				`<td colspan="2">`
		); miniPostInfo(post, null, false); html.put(
				`</td>` ~
			`</tr>` ~
			`<tr>` ~
				`<td class="post-info">` ~
					`<div class="post-author">`), html.putEncodedEntities(author), html.put(`</div>`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 80);

		html.put(
				`</td>` ~
				`<td class="post-body">` ~
					`<pre class="post-text">`), formatSearchSnippet(snippet), html.put(`</pre>`,
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td>` ~
			`</tr>` ~
			`</table>` ~
			`</div>`
		);
	}
}

// ***********************************************************************

string resolvePostUrl(string id)
{
	foreach (string threadID; query!"SELECT `ThreadID` FROM `Posts` WHERE `ID` = ?".iterate(id))
		return idToThreadUrl(id, threadID);

	throw new NotFoundException("Post not found");
}

string idToThreadUrl(string id, string threadID)
{
	return idToUrl(threadID, "thread", indexToPage(getPostThreadIndex(id), POSTS_PER_PAGE)) ~ "#" ~ idToFragment(id);
}

static Rfc850Post getPost(string id, uint[] partPath = null)
{
	foreach (int rowid, string message, string threadID; query!"SELECT `ROWID`, `Message`, `ThreadID` FROM `Posts` WHERE `ID` = ?".iterate(id))
	{
		auto post = new Rfc850Post(message, id, rowid, threadID);
		while (partPath.length)
		{
			enforce(partPath[0] < post.parts.length, "Invalid attachment");
			post = post.parts[partPath[0]];
			partPath = partPath[1..$];
		}
		return post;
	}
	return null;
}

static string getPostSource(string id)
{
	foreach (string message; query!"SELECT `Message` FROM `Posts` WHERE `ID` = ?".iterate(id))
		return message;
	return null;
}

struct PostInfo { int rowid; string id, threadID, parentID, author, authorEmail, subject; SysTime time; }
CachedSet!(string, PostInfo*) postInfoCache;

PostInfo* getPostInfo(string id)
{
	return postInfoCache(id, retrievePostInfo(id));
}

PostInfo* retrievePostInfo(string id)
{
	if (id.startsWith('<') && id.endsWith('>'))
		foreach (int rowid, string threadID, string parentID, string author, string authorEmail, string subject, long stdTime; query!"SELECT `ROWID`, `ThreadID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ID` = ?".iterate(id))
		{
			if (authorEmail is null)
			{
				authorEmail = new Rfc850Message(query!"SELECT [Message] FROM [Posts] WHERE [ROWID]=?".iterate(rowid).selectValue!string).authorEmail;
				if (authorEmail is null)
					authorEmail = "";
				assert(authorEmail !is null);
				query!"UPDATE [Posts] SET [AuthorEmail]=? WHERE [ROWID]=?".exec(authorEmail, rowid);
			}
			return [PostInfo(rowid, id, threadID, parentID, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr;
		}
	return null;
}

// ***********************************************************************

static Regex!char reUrl;
static this() { reUrl = regex(`\w+://[^<>\s]+[\w/\-=]`); }

void formatBody(Rfc850Message post)
{
	auto paragraphs = unwrapText(post.content, post.wrapFormat);
	bool inSignature = false;
	int quoteLevel = 0;
	foreach (paragraph; paragraphs)
	{
		int paragraphQuoteLevel;
		foreach (c; paragraph.quotePrefix)
			if (c == '>')
				paragraphQuoteLevel++;

		for (; quoteLevel > paragraphQuoteLevel; quoteLevel--)
			html ~= `</span>`;
		for (; quoteLevel < paragraphQuoteLevel; quoteLevel++)
			html ~= `<span class="forum-quote">`;

		if (!quoteLevel && (paragraph.text == "-- " || paragraph.text == "_______________________________________________"))
		{
			html ~= `<span class="forum-signature">`;
			inSignature = true;
		}

		enum forceWrapThreshold = 30;
		enum forceWrapMinChunkSize =  5;
		enum forceWrapMaxChunkSize = 15;
		static assert(forceWrapMaxChunkSize > forceWrapMinChunkSize * 2);

		import std.utf;
		bool needsWrap = paragraph.text.byChar.splitter(' ').map!(s => s.length).I!(r => reduce!max(size_t.init, r)) > forceWrapThreshold;

		auto hasURL = paragraph.text.contains("://");

		void processText(string s)
		{
			html.put(encodeHtmlEntities(s));
		}

		void processWrap(string s)
		{
			alias processText next;

			if (!needsWrap)
				return next(s);

			auto segments = s.segmentByWhitespace();
			foreach (ref segment; segments)
			{
				if (segment.length > forceWrapThreshold)
				{
					void chunkify(string s, string delimiters)
					{
						if (s.length < forceWrapMaxChunkSize)
						{
							html.put(`<span class="forcewrap">`);
							next(s);
							html.put(`</span>`);
						}
						else
						if (!delimiters.length)
						{
							// Don't cut UTF-8 sequences in half
							static bool canCutAt(char c) { return (c & 0x80) == 0 || (c & 0x40) != 0; }
							foreach (i; s.length.iota.radial)
								if (canCutAt(s[i]))
								{
									chunkify(s[0..i], null);
									chunkify(s[i..$], null);
									return;
								}
							chunkify(s[0..$/2], null);
							chunkify(s[$/2..$], null);
						}
						else
						{
							foreach (i; iota(forceWrapMinChunkSize, s.length-forceWrapMinChunkSize).radial)
								if (s[i] == delimiters[0])
								{
									chunkify(s[0..i+1], delimiters);
									chunkify(s[i+1..$], delimiters);
									return;
								}
							chunkify(s, delimiters[1..$]);
						}
					}

					chunkify(segment, "/&=.-+,;:_\\|`'\"~!@#$%^*()[]{}");
				}
				else
					next(segment);
			}
		}

		void processURLs(string s)
		{
			alias processWrap next;

			if (!hasURL)
				return next(s);

			size_t pos = 0;
			foreach (m; matchAll(s, reUrl))
			{
				next(s[pos..m.pre().length]);
				html.put(`<a rel="nofollow" href="`, m.hit(), `">`);
				next(m.hit());
				html.put(`</a>`);
				pos = m.pre().length + m.hit().length;
			}
			next(s[pos..$]);
		}

		if (paragraph.quotePrefix.length)
			html.put(`<span class="forum-quote-prefix">`), html.putEncodedEntities(paragraph.quotePrefix), html.put(`</span>`);
		processURLs(paragraph.text);
		html.put('\n');
	}
	for (; quoteLevel; quoteLevel--)
		html ~= `</span>`;
	if (inSignature)
		html ~= `</span>`;
}

string summarizeTime(SysTime time, bool colorize = false)
{
	if (!time.stdTime)
		return "-";

	string style;
	if (colorize)
	{
		import std.math;
		auto diff = Clock.currTime() - time;
		auto diffLog = log2(diff.total!"seconds");
		enum LOG_MIN = 10; // 1 hour-ish
		enum LOG_MAX = 18; // 3 days-ish
		enum COLOR_MAX = 0xA0;
		auto f = (diffLog - LOG_MIN) / (LOG_MAX - LOG_MIN);
		f = min(1, max(0, f));
		auto c = cast(int)(f * COLOR_MAX);

		style ~= format("color: #%02X%02X%02X;", c, c, c);
	}

	bool shorter = colorize; // hack
	return `<span style="` ~ style ~ `" title="` ~ encodeHtmlEntities(formatLongTime(time)) ~ `">` ~ encodeHtmlEntities(formatShortTime(time, shorter)) ~ `</span>`;
}

string formatShortTime(SysTime time, bool shorter)
{
	if (!time.stdTime)
		return "-";

	auto now = Clock.currTime(UTC());
	auto duration = now - time;

	if (duration < dur!"days"(7))
		return formatDuration(duration);
	else
	if (duration < dur!"days"(300))
		if (shorter)
			return time.formatTime!"M d"();
		else
			return time.formatTime!"F d"();
	else
		if (shorter)
			return time.formatTime!"M d, Y"();
		else
			return time.formatTime!"F d, Y"();
}

string formatDuration(Duration duration)
{
	string ago(long amount, string units)
	{
		assert(amount > 0);
		return format("%s %s%s ago", amount, units, amount==1 ? "" : "s");
	}

	if (duration < 0.seconds)
		return "from the future";
	else
	if (duration < 1.seconds)
		return "just now";
	else
	if (duration < 1.minutes)
		return ago(duration.total!"seconds", "second");
	else
	if (duration < 1.hours)
		return ago(duration.total!"minutes", "minute");
	else
	if (duration < 1.days)
		return ago(duration.total!"hours", "hour");
	else
	/*if (duration < dur!"days"(2))
		return "yesterday";
	else
	if (duration < dur!"days"(6))
		return formatTime("l", time);
	else*/
	if (duration < 7.days)
		return ago(duration.total!"days", "day");
	else
	if (duration < 31.days)
		return ago(duration.total!"weeks", "week");
	else
	if (duration < 365.days)
		return ago(duration.total!"days" / 30, "month");
	else
		return ago(duration.total!"days" / 365, "year");
}

string formatLongTime(SysTime time)
{
	return time.formatTime!"l, d F Y, H:i:s e"();
}

/// Add thousand-separators
string formatNumber(long n)
{
	string s = text(n);
	int digits = 0;
	foreach_reverse(p; 1..s.length)
		if (++digits % 3 == 0)
			s = s[0..p] ~ ',' ~ s[p..$];
	return s;
}

static string truncateString(string s8, int maxLength = 30)
{
	auto encoded = encodeHtmlEntities(s8);
	return `<span class="truncated" style="max-width: ` ~ text(maxLength * 0.6) ~ `em" title="`~encoded~`">` ~ encoded ~ `</span>`;
}

/+
/// Generate a link to set a user preference
string setOptionLink(string name, string value)
{
	return "/set?" ~ encodeUrlParameters(UrlParameters([name : value, "url" : "__URL__", "secret" : userSettings.secret]));
}
+/

// ***********************************************************************

enum FEED_HOURS_DEFAULT = 24;
enum FEED_HOURS_MAX = 72;

CachedSet!(string, CachedResource) feedCache;

CachedResource getFeed(GroupInfo groupInfo, bool threadsOnly, int hours)
{
	string feedUrl = site.proto ~ "://" ~ site.host ~ "/feed" ~
		(threadsOnly ? "/threads" : "/posts") ~
		(groupInfo ? "/" ~ groupInfo.urlName : "") ~
		(hours!=FEED_HOURS_DEFAULT ? "?hours=" ~ text(hours) : "");

	CachedResource getFeed()
	{
		auto title = "Latest " ~ (threadsOnly ? "threads" : "posts") ~ (groupInfo ? " on " ~ groupInfo.publicName : "");
		auto posts = getFeedPosts(groupInfo, threadsOnly, hours);
		auto feed = makeFeed(posts, feedUrl, title, groupInfo is null);
		return feed;
	}
	return feedCache(feedUrl, getFeed());
}

Rfc850Post[] getFeedPosts(GroupInfo groupInfo, bool threadsOnly, int hours)
{
	string PERF_SCOPE = "getFeedPosts(%s,%s,%s)".format(groupInfo ? groupInfo.internalName : "null", threadsOnly, hours); mixin(MeasurePerformanceMixin);

	auto since = (Clock.currTime() - dur!"hours"(hours)).stdTime;
	auto iterator =
		groupInfo ?
			threadsOnly ?
				query!"SELECT `Message` FROM `Posts` WHERE `ID` IN (SELECT `ID` FROM `Groups` WHERE `Time` > ? AND `Group` = ?) AND `ID` = `ThreadID`".iterate(since, groupInfo.internalName)
			:
				query!"SELECT `Message` FROM `Posts` WHERE `ID` IN (SELECT `ID` FROM `Groups` WHERE `Time` > ? AND `Group` = ?)".iterate(since, groupInfo.internalName)
		:
			threadsOnly ?
				query!"SELECT `Message` FROM `Posts` WHERE `Time` > ? AND `ID` = `ThreadID`".iterate(since)
			:
				query!"SELECT `Message` FROM `Posts` WHERE `Time` > ?".iterate(since)
		;

	Rfc850Post[] posts;
	foreach (string message; iterator)
		posts ~= new Rfc850Post(message);
	return posts;
}

CachedResource makeFeed(Rfc850Post[] posts, string feedUrl, string feedTitle, bool addGroup)
{
	AtomFeedWriter feed;
	feed.startFeed(feedUrl, feedTitle, Clock.currTime());

	foreach (post; posts)
	{
		html.clear();
		html.put("<pre>");
		formatBody(post);
		html.put("</pre>");

		auto postTitle = post.rawSubject;
		if (addGroup)
			postTitle = "[" ~ post.publicGroupNames().join(", ") ~ "] " ~ postTitle;

		feed.putEntry(post.url, postTitle, post.author, post.time, cast(string)html.get(), post.url);
	}
	feed.endFeed();

	return new CachedResource([Data(feed.xml.output.get())], "application/atom+xml");
}

CachedResource getSubscriptionFeed(string subscriptionID)
{
	string feedUrl = site.proto ~ "://" ~ site.host ~ "/subscription-feed/" ~ subscriptionID;

	CachedResource getFeed()
	{
		auto subscription = getSubscription(subscriptionID);
		auto title = "%s subscription (%s)".format(site.host, subscription.trigger.getTextDescription());
		Rfc850Post[] posts;
		foreach (string messageID; query!"SELECT [MessageID] FROM [SubscriptionPosts] WHERE [SubscriptionID] = ? ORDER BY [Time] DESC LIMIT 50"
							.iterate(subscriptionID))
		{
			auto post = getPost(messageID);
			if (post)
				posts ~= post;
		}

		return makeFeed(posts, feedUrl, title, true);
	}
	return feedCache(feedUrl, getFeed());
}

// **************************************************************************

class Redirect : Throwable
{
	string url;
	this(string url) { this.url = url; super("Uncaught redirect"); }
}

class NotFoundException : Exception
{
	this(string str = "The specified resource cannot be found on this server.") { super(str); }
}

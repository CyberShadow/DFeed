/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module web;

import core.time;

import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
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
import ae.net.shutdown;
import ae.sys.log;
import ae.utils.array;
import ae.utils.digest;
import ae.utils.exception;
import ae.utils.feed;
import ae.utils.json;
import ae.utils.meta;
import ae.utils.text;
import ae.utils.text.html;
import ae.utils.textout;
import ae.utils.time.format;
import ae.utils.time.parse;
import ae.utils.xmllite : putEncodedEntities;

import cache;
import captcha;
import common;
import database;
import github;
import groups;
import lint;
import list;
//import mailhide;
import message;
import messagedb : searchTerm, threadID;
import posting;
import site;
import subscriptions;
import user : User, getUser, SettingType;

version = MeasurePerformance;

Logger log;
version(MeasurePerformance) Logger perfLog;
HttpServer server;
string vhost;
User user;
string ip;
HttpRequest currentRequest;
StringBuffer html;
string[string] banned;

void startWebUI()
{
	log = createLogger("Web");
	version(MeasurePerformance) perfLog = createLogger("Performance");

	loadBanList();

	vhost = site.config.host;

	server = new HttpServer();
	server.log = log;
	server.handleRequest = toDelegate(&onRequest);
	server.listen(config.listen.port, config.listen.addr);

	addShutdownHandler({ server.close(); });
}

// ***********************************************************************

/// Caching wrapper
SysTime timeLastModified(string path)
{
	static if (is(MonoTimeImpl!(ClockType.coarse)))
		alias CoarseTime = MonoTimeImpl!(ClockType.coarse);
	else
		alias CoarseTime = MonoTime;

	static SysTime[string] cache;
	static CoarseTime cacheTime;

	enum expiration = isDebug ? 1.seconds : 5.seconds;

	auto now = CoarseTime.currTime();
	if (now - cacheTime > expiration)
	{
		cacheTime = now;
		cache = null;
	}

	auto pcache = path in cache;
	if (pcache)
		return *pcache;
	return cache[path] = std.file.timeLastModified(path);
}

string staticPath(string path)
{
	auto url = "/static/" ~ text(timeLastModified("web/static" ~ path).stdTime) ~ path;
	if (config.staticDomain !is null)
		url = "//" ~ config.staticDomain ~ url;
	return url;
}

string optimizedPath(string base, string resource)
{
	debug
		return resource;
	else
	{
		string optimizedResource = resource.stripExtension ~ ".min" ~ resource.extension;
		auto origPath = base ~ resource;
		auto optiPath = base ~ optimizedResource;
		if (exists(origPath) && exists(optiPath) && timeLastModified(optiPath) >= timeLastModified(origPath))
			return optimizedResource;
		else
			return resource;
	}
}

HttpResponseEx serveFile(HttpResponseEx response, string path)
{
	response.cacheForever();
	return response.serveFile(optimizedPath("web/static/", path), "web/static/");
}

// ***********************************************************************

void onRequest(HttpRequest request, HttpServerConnection conn)
{
	conn.sendResponse(handleRequest(request, conn));
}

HttpResponse handleRequest(HttpRequest request, HttpServerConnection conn)
{
	StopWatch responseTime;
	responseTime.start();
	currentRequest = request;
	auto response = new HttpResponseEx();

	ip = request.remoteHosts(conn.remoteAddress.toAddrString())[0];
	user = getUser(request.headers.get("Cookie", null));
	string[] cookies;
	scope(success)
	{
		if (!cookies)
			cookies = user.save();
		foreach (cookie; cookies)
			response.headers.add("Set-Cookie", cookie);
	}

	string title;
	string[] breadcrumbs;
	string bodyClass = "narrowdoc";
	string returnPage = request.resource;
	html.clear();
	string[] tools, extraHeaders;
	string[string] jsVars;
	auto status = HttpStatusCode.OK;
	GroupInfo currentGroup; string currentThread; // for search

	// Redirect to canonical domain name
	auto host = request.headers.get("Host", "");
	host = request.headers.get("X-Forwarded-Host", host);
	if (host != vhost && host != "localhost" && vhost != "localhost" && ip != "127.0.0.1" && !request.resource.startsWith("/.well-known/acme-challenge/"))
		return response.redirect("http://" ~ vhost ~ request.resource, HttpStatusCode.MovedPermanently);

	auto canonicalHeader =
		`<link rel="canonical" href="http://`~vhost~request.resource~`"/>`;
	enum horizontalSplitHeaders =
		`<link rel="stylesheet" href="//fonts.googleapis.com/css?family=Open+Sans:400,600">`;

	void addMetadata(string description, string canonicalLocation, string image)
	{
		assert(title, "No title for metadata");

		if (!description)
			description = site.config.name;

		if (!image)
			image = "https://dlang.org/images/dlogo_opengraph.png";

		auto canonicalURL = "http://" ~ site.config.host ~ canonicalLocation;

		extraHeaders ~= [
			`<meta property="og:title" content="` ~ encodeHtmlEntities(title) ~ `" />`,
			`<meta property="og:type" content="website" />`,
			`<meta property="og:url" content="` ~ encodeHtmlEntities(canonicalURL) ~ `" />`,
			`<meta property="og:image" content="` ~ encodeHtmlEntities(image) ~ `" />`,
			`<meta property="og:description" content="` ~ encodeHtmlEntities(description) ~ `" />`,
		];

		// Maybe emit <meta name="description" ...> here as well one day
		// Needs changes to forum-template.dd
	}

	try
	{
		if (banCheck(ip, request))
			return response.writeError(HttpStatusCode.Forbidden, "You're banned!");

		auto pathStr = request.resource;
		enforce(pathStr.startsWith('/'), "Invalid path");
		UrlParameters parameters;
		if (pathStr.indexOf('?') >= 0)
		{
			auto p = pathStr.indexOf('?');
			parameters = decodeUrlParameters(pathStr[p+1..$]);
			pathStr = pathStr[0..p];
		}
		auto path = pathStr[1..$].split("/");
		if (!path.length) path = [""];
		auto pathX = path[1..$].join("%2F"); // work around Apache bug

		switch (path[0])
		{
			// Obsolete "/discussion/" prefix
			case "discussion":
				return response.redirect(request.resource["/discussion".length..$], HttpStatusCode.MovedPermanently);

			case "":
				// Handle redirects from pnews

				// Abort on redirect from URLs with unsupported features.
				// Only search engines would be likely to hit these.
				if ("path" in parameters || "mid" in parameters)
					throw new NotFoundException("Legacy redirect - unsupported feature");

				// Redirect to our URL scheme
				string redirectGroup, redirectNum;
				if ("group" in parameters)
					redirectGroup = parameters["group"];
				if ("art_group" in parameters)
					redirectGroup = parameters["art_group"];
				if ("artnum" in parameters)
					redirectNum = parameters["artnum"];
				if ("article_id" in parameters)
					redirectNum = parameters["article_id"];
				if (redirectGroup && redirectNum)
				{
					foreach (string id; query!"SELECT `ID` FROM `Groups` WHERE `Group`=? AND `ArtNum`=?".iterate(redirectGroup, redirectNum))
						return response.redirect(idToUrl(id), HttpStatusCode.MovedPermanently);
					throw new NotFoundException("Legacy redirect - article not found");
				}
				else
				if (redirectNum)
				{
					string[] ids;
					foreach (string id; query!"SELECT `ID` FROM `Groups` WHERE `ArtNum`=?".iterate(redirectNum))
						ids ~= id;
					if (ids.length == 1)
						return response.redirect(idToUrl(ids[0]), HttpStatusCode.MovedPermanently);
					else
					if (ids.length > 1)
						throw new NotFoundException("Legacy redirect - ambiguous artnum (group parameter missing)");
					else
						throw new NotFoundException("Legacy redirect - article not found");
				}
				else
				if (redirectGroup)
					return response.redirect("/group/" ~ redirectGroup, HttpStatusCode.MovedPermanently);

				if (request.resource != "/")
					return response.redirect("/");

				title = "Index";
				//breadcrumbs ~= `<a href="/">Forum Index</a>`;
				foreach (what; ["posts", "threads"])
					extraHeaders ~= `<link rel="alternate" type="application/atom+xml" title="New `~what~`" href="/feed/`~what~`" />`;
				addMetadata(null, "/", null);
				discussionIndex();
				break;
			case "group":
			{
				enforce(path.length > 1, "No group specified");
				string groupUrlName = path[1];

				foreach (groupInfo; groupHierarchy.map!(set => set.groups).join)
					if (groupInfo.urlAliases.canFind(groupUrlName))
						throw new Redirect("/group/" ~ groupInfo.urlName);
				foreach (groupInfo; groupHierarchy.map!(set => set.groups).join)
					if (groupInfo.urlAliases.canFind!(not!icmp)(groupUrlName))
						throw new Redirect("/group/" ~ groupInfo.urlName);

				int page = to!int(parameters.get("page", "1"));
				string pageStr = page==1 ? "" : format(" (page %d)", page);
				auto groupInfo = currentGroup = getGroupInfoByUrl(groupUrlName);
				enforce(groupInfo, "Unknown group");
				title = groupInfo.publicName ~ " group index" ~ pageStr;
				breadcrumbs ~= `<a href="/group/`~encodeHtmlEntities(groupUrlName)~`">` ~ encodeHtmlEntities(groupInfo.publicName) ~ `</a>` ~ pageStr;
				auto viewMode = userSettings.groupViewMode;
				if (viewMode == "basic")
					discussionGroup(groupInfo, page);
				else
				if (viewMode == "threaded")
					discussionGroupThreaded(groupInfo, page);
				else
				if (viewMode == "horizontal-split")
				{
					discussionGroupSplit(groupInfo, page);
					extraHeaders ~= horizontalSplitHeaders;
				}
				else
					discussionGroupVSplit(groupInfo, page);
				foreach (what; ["posts", "threads"])
					extraHeaders ~= `<link rel="alternate" type="application/atom+xml" title="New `~what~` on `~encodeHtmlEntities(groupInfo.publicName)~`" href="/feed/`~what~`/`~encodeHtmlEntities(groupInfo.urlName)~`" />`;
				addMetadata(groupInfo.description, "/group/" ~ groupInfo.urlName, null);
				break;
			}
			case "thread":
			{
				enforce(path.length > 1, "No thread specified");
				int page = to!int(parameters.get("page", "1"));
				string threadID = '<' ~ urlDecode(pathX) ~ '>';

				auto firstPostUrl = idToUrl(getPostAtThreadIndex(threadID, getPageOffset(page, POSTS_PER_PAGE)));
				auto viewMode = userSettings.groupViewMode;
				if (viewMode != "basic")
					html.put(`<div class="forum-notice">Viewing thread in basic view mode &ndash; click a post's title to open it in `, encodeHtmlEntities(viewMode), ` view mode</div>`);
				returnPage = firstPostUrl;

				string pageStr = page==1 ? "" : format(" (page %d)", page);
				GroupInfo groupInfo;
				string subject, authorEmail;
				discussionThread(threadID, page, groupInfo, subject, authorEmail, viewMode == "basic");
				enforce(groupInfo, "Unknown group");
				title = subject ~ pageStr;
				currentGroup = groupInfo;
				currentThread = threadID;
				breadcrumbs ~= `<a href="/group/` ~encodeHtmlEntities(groupInfo.urlName)~`">` ~ encodeHtmlEntities(groupInfo.publicName) ~ `</a>`;
				breadcrumbs ~= `<a href="/thread/`~encodeHtmlEntities(pathX)~`">` ~ encodeHtmlEntities(subject) ~ `</a>` ~ pageStr;
				extraHeaders ~= canonicalHeader; // Google confuses /post/ URLs with threads
				addMetadata(null, idToUrl(threadID, "thread"), gravatar(authorEmail, gravatarMetaSize));
				break;
			}
			case "post":
				enforce(path.length > 1, "No post specified");
				string id = '<' ~ urlDecode(pathX) ~ '>';

				// Normalize URL encoding to allow JS to find message by URL
				if (urlEncodeMessageUrl(urlDecode(pathX)) != pathX)
					return response.redirect(idToUrl(id));

				auto viewMode = userSettings.groupViewMode;
				if (viewMode == "basic")
					return response.redirect(resolvePostUrl(id));
				else
				if (viewMode == "threaded")
				{
					string subject, authorEmail;
					discussionSinglePost(id, currentGroup, subject, authorEmail, currentThread);
					title = subject;
					breadcrumbs ~= `<a href="/group/` ~encodeHtmlEntities(currentGroup.urlName)~`">` ~ encodeHtmlEntities(currentGroup.publicName) ~ `</a>`;
					breadcrumbs ~= `<a href="/post/`~encodeHtmlEntities(pathX)~`">` ~ encodeHtmlEntities(subject) ~ `</a> (view single post)`;
					addMetadata(null, idToUrl(id), gravatar(authorEmail, gravatarMetaSize));
					break;
				}
				else
				{
					int page;
					if (viewMode == "horizontal-split")
						discussionGroupSplitFromPost(id, currentGroup, page, currentThread);
					else
						discussionGroupVSplitFromPost(id, currentGroup, page, currentThread);

					string pageStr = page==1 ? "" : format(" (page %d)", page);
					title = currentGroup.publicName ~ " group index" ~ pageStr;
					breadcrumbs ~= `<a href="/group/`~encodeHtmlEntities(currentGroup.urlName)~`">` ~ encodeHtmlEntities(currentGroup.publicName) ~ `</a>` ~ pageStr;
					extraHeaders ~= horizontalSplitHeaders;
					addMetadata(null, idToUrl(id), null);
					break;
				}
			case "raw":
			{
				enforce(path.length > 1, "Invalid URL");
				auto post = getPost('<' ~ urlDecode(path[1]) ~ '>', array(map!(to!uint)(path[2..$])));
				enforce(post, "Post not found");
				if (!post.data && post.error)
					throw new Exception(post.error);
				if (post.fileName)
					//response.headers["Content-Disposition"] = `inline; filename="` ~ post.fileName ~ `"`;
					response.headers["Content-Disposition"] = `attachment; filename="` ~ post.fileName ~ `"`; // "
				else
					// TODO: separate subdomain for attachments
					response.headers["Content-Disposition"] = `attachment; filename="raw"`;
				return response.serveData(Data(post.data), post.mimeType ? post.mimeType : "application/octet-stream");
			}
			case "source":
			{
				enforce(path.length > 1, "Invalid URL");
				auto message = getPostSource('<' ~ urlDecode(path[1]) ~ '>');
				enforce(message !is null, "Post not found");
				return response.serveData(Data(message), "text/plain");
			}
			case "split-post":
				enforce(path.length > 1, "No post specified");
				discussionSplitPost('<' ~ urlDecode(pathX) ~ '>');
				return response.serveData(cast(string)html.get());
			case "vsplit-post":
				enforce(path.length > 1, "No post specified");
				discussionVSplitPost('<' ~ urlDecode(pathX) ~ '>');
				return response.serveData(cast(string)html.get());
		/+
			case "set":
			{
				if (parameters.get("secret", "") != userSettings.secret)
					throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

				foreach (name, value; parameters)
					if (name != "url" && name != "secret")
						user.set(name, value); // TODO: is this a good idea?

				if ("url" in parameters)
					return response.redirect(parameters["url"]);
				else
					return response.serveText("OK");
			}
		+/
			case "mark-unread":
			{
				enforce(path.length > 1, "No post specified");
				auto post = getPostInfo('<' ~ urlDecode(pathX) ~ '>');
				enforce(post, "Post not found");
				user.setRead(post.rowid, false);
				return response.serveText("OK");
			}
			case "first-unread":
			{
				enforce(path.length > 1, "No thread specified");
				return response.redirect(discussionFirstUnread('<' ~ urlDecode(pathX) ~ '>'));
			}
			case "newpost":
			{
				enforce(path.length > 1, "No group specified");
				string groupUrlName = path[1];
				currentGroup = getGroupInfoByUrl(groupUrlName).enforce("No such group");
				title = "Posting to " ~ currentGroup.publicName;
				breadcrumbs ~= `<a href="/group/`~encodeHtmlEntities(currentGroup.urlName)~`">` ~ encodeHtmlEntities(currentGroup.publicName) ~ `</a>`;
				breadcrumbs ~= `<a href="/newpost/`~encodeHtmlEntities(currentGroup.urlName)~`">New thread</a>`;
				if (discussionPostForm(newPostDraft(currentGroup, parameters)))
					bodyClass ~= " formdoc";
				break;
			}
			case "reply":
			{
				enforce(path.length > 1, "No post specified");
				auto post = getPost('<' ~ urlDecode(pathX) ~ '>');
				enforce(post, "Post not found");
				title = `Replying to "` ~ post.subject ~ `"`; // "
				currentGroup = post.getGroup();
				currentThread = post.threadID;
				breadcrumbs ~= `<a href="/group/`~encodeHtmlEntities(currentGroup.urlName)~`">` ~ encodeHtmlEntities(currentGroup.publicName) ~ `</a>`;
				breadcrumbs ~= `<a href="` ~ encodeHtmlEntities(idToUrl(post.id)) ~ `">` ~ encodeHtmlEntities(post.subject) ~ `</a>`;
				breadcrumbs ~= `<a href="/reply/`~pathX~`">Post reply</a>`;
				if (discussionPostForm(newReplyDraft(post)))
					bodyClass = "formdoc";
				break;
			}
			case "send":
			{
				auto postVars = request.decodePostData();
				auto redirectTo = discussionSend(postVars, request.headers);
				if (redirectTo)
					return response.redirect(redirectTo);

				breadcrumbs ~= title = `Posting`;
				bodyClass ~= " formdoc";
				break;
			}
			case "posting":
			{
				enforce(path.length > 1, "No post ID specified");
				auto pid = pathX;
				if (pid in postProcesses)
				{
					bool refresh, form;
					string redirectTo;
					discussionPostStatus(postProcesses[pid], refresh, redirectTo, form);
					if (refresh)
						response.setRefresh(1, redirectTo);
					if (form)
					{
						breadcrumbs ~= title = `Posting`;
						bodyClass ~= " formdoc";
					}
					else
						breadcrumbs ~= title = `Posting status`;
				}
				else
				{
					auto draftID = pid;
					foreach (string id; query!"SELECT [ID] FROM [Drafts] WHERE [PostID]=?".iterate(pid))
						draftID = id;
					discussionPostForm(getDraft(draftID));
					title = "Composing message";
				}
				break;
			}
			case "auto-save":
			{
				auto postVars = request.decodePostData();
				if (postVars.get("secret", "") != userSettings.secret)
					throw new Exception("XSRF secret verification failed");
				autoSaveDraft(postVars);
				return response.serveText("OK");
			}
			case "subscribe":
			{
				enforce(path.length > 1, "No post specified");
				enforce(user.isLoggedIn(), "Please log in to do that");
				auto id = '<' ~ urlDecode(pathX) ~ '>';
				Subscription threadSubscription;
				foreach (subscription; getUserSubscriptions(user.getName()))
					if (auto threadTrigger = cast(ThreadTrigger)subscription.trigger)
						if (threadTrigger.threadID == id)
						{
							threadSubscription = subscription;
							break;
						}
				if (!threadSubscription.trigger)
					threadSubscription = createSubscription(user.getName(), "thread", ["trigger-thread-id" : id]);
				title = "Subscribe to thread";
				discussionSubscriptionEdit(threadSubscription);
				break;
			}
			case "subscription-posts":
			{
				enforce(path.length > 1, "No subscription specified");
				int page = to!int(parameters.get("page", "1"));
				breadcrumbs ~= "View subscription";
				discussionSubscriptionPosts(urlDecode(pathX), page, title);
				break;
			}
			case "subscription-feed":
			{
				enforce(path.length > 1, "No subscription specified");
				return getSubscriptionFeed(urlDecode(pathX)).getResponse(request);
			}
			case "subscription-unsubscribe":
			{
				enforce(path.length > 1, "No subscription specified");
				title = "Unsubscribe";
				discussionSubscriptionUnsubscribe(urlDecode(pathX));
				break;
			}
			case "search":
			{
				breadcrumbs ~= title = "Search";
				discussionSearch(parameters);
				break;
			}
			case "delete":
			{
				enforce(user.getLevel() >= User.Level.canDeletePosts, "You can't delete posts");
				enforce(path.length > 1, "No post specified");
				auto post = getPost('<' ~ urlDecode(pathX) ~ '>');
				enforce(post, "Post not found");
				title = `Delete "` ~ post.subject ~ `"?`; // "
				breadcrumbs ~= `<a href="` ~ encodeHtmlEntities(idToUrl(post.id)) ~ `">` ~ encodeHtmlEntities(post.subject) ~ `</a>`;
				breadcrumbs ~= `<a href="/delete/`~pathX~`">Delete post</a>`;
				discussionDeleteForm(post);
				bodyClass ~= " formdoc";
				break;
			}
			case "dodelete":
			{
				enforce(user.getLevel() >= User.Level.canDeletePosts, "You can't delete posts");
				auto postVars = request.decodePostData();
				title = "Deleting post";
				deletePost(postVars);
				break;
			}
			case "api-delete":
			{
				enforce(config.apiSecret.length, "No API secret configured");
				enforce(parameters.get("secret", null) == config.apiSecret, "Incorrect secret");
				enforce(path.length == 3, "Invalid URL");
				auto group = path[1];
				auto id = path[2].to!int;
				deletePostApi(group, id);
				return response.serveText(html.get().idup);
			}
			case "flag":
			case "unflag":
			{
				enforce(user.getLevel() >= User.Level.canFlag, "You can't flag posts");
				enforce(path.length > 1, "No post specified");
				auto post = getPost('<' ~ urlDecode(pathX) ~ '>');
				enforce(post, "Post not found");
				title = `Flag "` ~ post.subject ~ `" by ` ~ post.author; // "
				breadcrumbs ~= `<a href="` ~ encodeHtmlEntities(idToUrl(post.id)) ~ `">` ~ encodeHtmlEntities(post.subject) ~ `</a>`;
				breadcrumbs ~= `<a href="/`~path[0]~`/`~pathX~`">Flag post</a>`;
				discussionFlagPage(post, path[0] == "flag", request.method == "POST" ? request.decodePostData() : UrlParameters.init);
				bodyClass ~= " formdoc";
				break;
			}
			case "loginform":
			{
				discussionLoginForm(parameters);
				breadcrumbs ~= title = `Log in`;
				tools ~= `<a href="/registerform?url=__URL__">Register</a>`;
				returnPage = "/";
				break;
			}
			case "registerform":
			{
				discussionRegisterForm(parameters);
				breadcrumbs ~= title = `Registration`;
				tools ~= `<a href="/registerform?url=__URL__">Register</a>`;
				returnPage = "/";
				break;
			}
			case "login":
			{
				try
				{
					parameters = request.decodePostData();
					discussionLogin(parameters);
					return response.redirect(parameters.get("url", "/"));
				}
				catch (Exception e)
				{
					discussionLoginForm(parameters, e.msg);
					breadcrumbs ~= title = `Login error`;
					tools ~= `<a href="/registerform?url=__URL__">Register</a>`;
					returnPage = "/";
					break;
				}
			}
			case "register":
			{
				try
				{
					parameters = request.decodePostData();
					discussionRegister(parameters);
					return response.redirect(parameters.get("url", "/"));
				}
				catch (Exception e)
				{
					discussionRegisterForm(parameters, e.msg);
					breadcrumbs ~= title = `Registration error`;
					tools ~= `<a href="/registerform?url=__URL__">Register</a>`;
					returnPage = "/";
					break;
				}
			}
			case "logout":
			{
				enforce(user.isLoggedIn(), "Not logged in");
				user.logOut();
				if ("url" in parameters)
					return response.redirect(parameters["url"]);
				else
					return response.serveText("OK");
			}
			case "settings":
				breadcrumbs ~= title = "Settings";
				discussionSettings(parameters, request.method == "POST" ? request.decodePostData() : UrlParameters.init);
				break;
			case "help":
				breadcrumbs ~= title = "Help";
				html.put(readText(optimizedPath(null, "web/help.htt"))
					.parseTemplate(
						(string name)
						{
							switch (name)
							{
								case "about" : return site.config.about;
								default: throw new Exception("Unknown variable in help template: " ~ name);
							}
						}
					));
				break;

			// dlang.org front page iframes
			case "frame-discussions":
				bodyClass = "frame";
				breadcrumbs ~= title = "Forum activity summary";
				discussionFrameDiscussions();
				break;
			case "frame-announcements":
				bodyClass = "frame";
				breadcrumbs ~= title = "Forum activity summary";
				discussionFrameAnnouncements();
				break;

			case "feed":
			{
				enforce(path.length > 1, "Feed type not specified");
				enforce(path[1]=="posts" || path[1]=="threads", "Unknown feed type");
				bool threadsOnly = path[1] == "threads";
				string groupUrlName;
				if (path.length > 2)
					groupUrlName = path[2];
				auto hours = to!int(parameters.get("hours", text(FEED_HOURS_DEFAULT)));
				enforce(hours <= FEED_HOURS_MAX, "hours parameter exceeds limit");
				auto groupInfo = getGroupInfoByUrl(groupUrlName);
				if (groupUrlName && !groupInfo)
					groupInfo = getGroupInfo(groupUrlName);
				if (groupUrlName && !groupInfo)
					throw new NotFoundException("No such group");
				return getFeed(groupInfo, threadsOnly, hours).getResponse(request);
			}
			case "github-webhook":
				foreach (service; services!GitHub)
					service.handleWebHook(request);
				return response.serveText("DFeed OK\n");

			case "js":
			case "css":
			case "images":
			case "files":
			case "ircstats":
			case "favicon.ico":
			case ".well-known":
				return serveFile(response, pathStr[1..$]);

			case "robots.txt":
				return serveFile(response, config.indexable ? "robots_public.txt" : "robots_private.txt");

			case "static":
				enforce(path.length > 2);
				return serveFile(response, path[2..$].join("/"));
			case "static-bundle":
				enforce(path.length > 2);
				return makeBundle(path[1], path[2..$].join("/"));

			default:
				return response.writeError(HttpStatusCode.NotFound);
		}
	}
	catch (Redirect r)
	{
		cookies = user.save();
		return response.redirect(r.url);
	}
	catch (CaughtException e)
	{
		//return response.writeError(HttpStatusCode.InternalServerError, "Unprocessed exception: " ~ e.msg);
		if (cast(NotFoundException) e)
		{
			breadcrumbs ~= title = "Not Found";
			status = HttpStatusCode.NotFound;
		}
		else
		{
			breadcrumbs ~= title = "Error";
			status = HttpStatusCode.InternalServerError;
		}
		auto text = encodeHtmlEntities(e.msg).replace("\n", "<br>");
		debug text ~= `<pre>` ~ encodeHtmlEntities(e.toString()) ~ `</pre>`;
		html.clear();
		html.put(
			`<table class="forum-table forum-error">` ~
				`<tr><th>`, encodeHtmlEntities(title), `</th></tr>` ~
				`<tr><td class="forum-table-message">`, text, `</td></tr>` ~
			`</table>`);
	}

	assert(title, "No title");
	assert(html.length, "No HTML");
	if (breadcrumbs.length) breadcrumbs = [`<a href="/">Index</a>`] ~ breadcrumbs;

	if (user.isLoggedIn())
		tools ~= `<a href="/logout?url=__URL__">Log out ` ~ encodeHtmlEntities(user.getName()) ~ `</a>`;
	else
		tools ~= `<a href="/loginform?url=__URL__">Log in</a>`;
	tools ~= `<a href="/settings">Settings</a>`;
	tools ~= `<a href="/help">Help</a>`;

	string toolStr = tools
		.map!(t => `<div class="tip">` ~ t ~ `</div>`)
		.join(" ");
	jsVars["toolsTemplate"] = toJson(toolStr);
	toolStr =
		toolStr.replace("__URL__",  encodeUrlParameter(returnPage));
	toolStr =
		`<div id="forum-tools-right">` ~ toolStr ~ `</div>` ~
		`<div id="forum-tools-left">` ~
		breadcrumbs.join(` &raquo; `) ~ `</div>`
	;
	string htmlStr = cast(string) html.get(); // html contents will be overwritten on next request

	auto pendingNotice = userSettings.pendingNotice;
	if (pendingNotice)
	{
		userSettings.pendingNotice = null;
		auto parts = pendingNotice.findSplit(":");
		auto kind = parts[0];
		switch (kind)
		{
			case "draft-deleted":
			{
				auto draftID = parts[2];
				htmlStr =
					`<div class="forum-notice">Draft discarded. <a href="/posting/` ~ encodeHtmlEntities(draftID) ~ `">Undo</a></div>` ~ htmlStr;
				break;
			}
			case "settings-saved":
				htmlStr =
					`<div class="forum-notice">Settings saved.</div>` ~ htmlStr;
				break;
			default:
				throw new Exception("Unknown kind of pending notice: " ~ kind);
		}
	}

	jsVars["enableKeyNav"] = userSettings.enableKeyNav;
	jsVars["autoOpen"] = userSettings.autoOpen;

	string[] extraJS;
	if (jsVars.length)
		extraJS ~= "var %-(%s,%);".format(jsVars.byKeyValue.map!(pair => pair.key ~ "=" ~ pair.value));

	cookies = user.save();
	foreach (cookie; cookies)
		if (cookie.length > 4096 * 15/16)
		{
			htmlStr =
				`<div class="forum-notice">Warning: cookie size approaching RFC 2109 limit.` ~
				`Please consider <a href="/registerform">creating an account</a> to avoid losing your read post history.</div>` ~ htmlStr;
			break;
		}

	string searchOptionStr;
	{
		struct SearchOption { string name, value; }
		SearchOption[] searchOptions;

		searchOptions ~= SearchOption("Forums", "forum");
		if (currentGroup)
			searchOptions ~= SearchOption(currentGroup.publicName ~ " group", "group:" ~ currentGroup.internalName.searchTerm);
		if (currentThread)
			searchOptions ~= SearchOption("This thread", "threadmd5:" ~ currentThread.getDigestString!MD5().toLower());

		foreach (i, option; searchOptions)
			searchOptionStr ~=
				`<option value="` ~ encodeHtmlEntities(option.value) ~ `"` ~ (i==searchOptions.length-1 ? ` selected` : ``) ~ `>` ~
					encodeHtmlEntities(option.name) ~ `</option>`;
	}

	string getVar(string name)
	{
		switch (name)
		{
			case "title"          : return encodeHtmlEntities(title);
			case "content"        : return htmlStr;
			case "extraheaders"   : return extraHeaders.join();
			case "extrajs"        : return extraJS.join();
			case "bodyclass"      : return bodyClass;
			case "tools"          : return toolStr;
			case "search-options" : return searchOptionStr;
			default:
				if (name.startsWith("static:"))
					return staticPath(name[7..$]);
				throw new Exception("Unknown variable in template: " ~ name);
		}
	}

	response.disableCache();

	auto page = readText(optimizedPath(null, "web/skel.htt"));
	//scope(failure) std.file.write("bad-tpl.html", page);
	page = renderNav(page, currentGroup);
	page = parseTemplate(page, &getVar);
	debug {} else
	{
		page = createBundles(page, re!`<link rel="stylesheet" href="(/[^/][^"]*?)" ?/?>`);
		page = createBundles(page, re!`<script type="text/javascript" src="(/[^/][^"]*?\.js)"></script>`);
	}
	response.serveData(page);

	response.setStatus(status);
	return response;
}

string createBundles(string page, Regex!char re)
{
	string[] paths;
	foreach (m; page.matchAll(re))
		paths ~= m.captures[1];
	auto maxTime = paths.map!(path => path[8..26].to!long).reduce!max;
	string bundleUrl = "/static-bundle/%d/%-(%s+%)".format(maxTime, paths.map!(path => path[27..$]));
	int index;
	page = page.replaceAll!(captures => index++ ? null : captures[0].replace(captures[1], bundleUrl))(re);
	return page;
}

HttpResponseEx makeBundle(string time, string url)
{
	static struct Bundle
	{
		string time;
		HttpResponseEx response;
	}
	static Bundle[string] cache;

	if (url !in cache || cache[url].time != time || isDebug)
	{
		auto bundlePaths = url.split("+");
		enforce(bundlePaths.length > 0, "Empty bundle");
		HttpResponseEx bundleResponse;
		foreach (n, bundlePath; bundlePaths)
		{
			auto pathResponse = new HttpResponseEx;
			serveFile(pathResponse, bundlePath);
			assert(pathResponse.data.length == 1);
			if (bundlePath.endsWith(".css"))
			{
				auto oldText = cast(string)pathResponse.data[0].contents;
				auto newText = fixCSS(oldText, bundlePath, n == 0);
				if (oldText !is newText)
					pathResponse.data = [Data(newText)];
			}
			if (!bundleResponse)
				bundleResponse = pathResponse;
			else
				bundleResponse.data ~= pathResponse.data;
		}
		cache[url] = Bundle(time, bundleResponse);
	}
	return cache[url].response.dup;
}

string fixCSS(string css, string path, bool first)
{
	css = css.replace(re!(`@charset "utf-8";`, "i"), ``);
	if (first)
		css = `@charset "utf-8";` ~ css;
	css = css.replaceAll!(captures =>
		captures[2].canFind("//")
		? captures[0]
		: captures[0].replace(captures[2], staticPath(buildNormalizedPath(dirName("/" ~ path), captures[2]).replace(`\`, `/`)))
	)(re!`\burl\(('?)(.*?)\1\)`);
	return css;
}

string renderNav(string html, GroupInfo currentGroup)
{
	string highlightCurrent(string html)
	{
		return currentGroup
			? html.replace(
				`href=' /group/` ~ currentGroup.urlName ~ `'`,
				`href=' /group/` ~ currentGroup.urlName ~ `' class="active"`)
			: html;
	}

	auto nav = inferList(html, [["<?category1?>"], ["<?category2?>"]]);
	auto nav2 = inferList(nav.itemSuffix, [["<?url1?>", "<?title1?>"], ["<?url2?>", "<?title2?>"]]);
	nav.itemSuffix = null; nav.varPrefix ~= null;

	return nav.render(groupHierarchy.filter!(set => set.visible).map!(set =>
		[set.shortName, nav2.render(set.groups.map!(group =>
			["/group/" ~ group.urlName, group.publicName]
		).array).I!highlightCurrent]
	).array);
}

static string parseTemplate(string data, string delegate(string) dictionary)
{
	import ae.utils.textout;
	StringBuilder sb;
	sb.preallocate(data.length / 100 * 110);
	while (true)
	{
		auto startpos = data.indexOf("<?");
		if (startpos==-1)
			break;
		auto endpos = data.indexOf("?>");
		if (endpos<startpos+2)
			throw new Exception("Bad syntax in template");
		string token = data[startpos+2 .. endpos];
		auto value = dictionary(token);
		sb.put(data[0 .. startpos], value);
		data = data[endpos+2 .. $];
	}
	sb.put(data);
	return sb.get();
}

// ***********************************************************************

enum MeasurePerformanceMixin =
q{
	StopWatch performanceSW;
	performanceSW.start();
	scope(success)
	{
		performanceSW.stop();
		perfLog(PERF_SCOPE ~ ": " ~ text(performanceSW.peek().msecs) ~ "ms");
	}
};

Cached!int totalPostCountCache, totalThreadCountCache;

void discussionIndexHeader()
{
	auto now = Clock.currTime();
	if (now - SysTime(userSettings.sessionCanary.to!long) > 4.hours)
	{
		userSettings.previousSession = userSettings.currentSession;
		userSettings.currentSession = userSettings.sessionCanary = now.stdTime.text;
	}
	long previousSession = userSettings.previousSession.to!long;

	string name = user.isLoggedIn() ? user.getName() : userSettings.name.length ? userSettings.name.split(' ')[0] : `Guest`;
	html.put(
		`<div id="forum-index-header">` ~
		`<h1>`), html.putEncodedEntities(site.config.name), html.put(`</h1>` ~
		`<p>Welcome`, previousSession ? ` back` : ``, `, `), html.putEncodedEntities(name), html.put(`.</p>` ~

		`<ul>`
	);

	string[][3] bits;

	if (user.isLoggedIn())
	{
		auto subscriptions = getUserSubscriptions(user.getName());
		int numSubscriptions, numNewSubscriptions;
		foreach (subscription; subscriptions)
		{
			auto c = subscription.getUnreadCount();
			if (subscription.trigger.type == "reply")
				if (c)
					bits[0] ~= `<li><b>You have <a href="/subscription-posts/%s">%d new repl%s</a> to <a href="/search?q=authoremail:%s">your posts</a>.</b></li>`
						.format(encodeHtmlEntities(subscription.id), c, c==1 ? "y" : "ies", encodeHtmlEntities(encodeUrlParameter(userSettings.email)));
				else
					bits[2] ~= `<li>No new <a href="/subscription-posts/%s">replies</a> to <a href="/search?q=authoremail:%s">your posts</a>.</li>`
						.format(encodeHtmlEntities(subscription.id), encodeHtmlEntities(encodeUrlParameter(userSettings.email)));
			else
			{
				numSubscriptions++;
				if (c)
				{
					numNewSubscriptions++;
					bits[1] ~= `<li><b>You have <a href="/subscription-posts/%s">%d unread post%s</a> matching your <a href="/settings#subscriptions">%s subscription</a> (%s).</b></li>`
						.format(encodeHtmlEntities(subscription.id), c, c==1 ? "" : "s", subscription.trigger.type, subscription.trigger.getDescription());
				}
			}
		}
		if (numSubscriptions && !numNewSubscriptions)
			bits[2] ~= `<li>No new posts matching your <a href="/settings#subscriptions">subscription%s</a>.</b></li>`
				.format(numSubscriptions==1 ? "" : "s");
	}
	else
	{
		int hasPosts = 0;
		if (userSettings.email)
			hasPosts = query!"SELECT EXISTS(SELECT 1 FROM [Posts] WHERE [AuthorEmail] = ? LIMIT 1)".iterate(userSettings.email).selectValue!int;
		if (hasPosts)
			bits[2] ~= `<li>If you <a href="/register">create an account</a>, you can track replies to <a href="/search?q=authoremail:%s">your posts</a>.</li>`
				.format(encodeHtmlEntities(encodeUrlParameter(userSettings.email)));
		else
			bits[0] ~= `<li>You can read and post on this forum without <a href="/register">creating an account</a>, but doing so offers <a href="/help#accounts">a few benefits</a>.</li>`;
	}

	SysTime cutOff = previousSession ? SysTime(previousSession) : now - 24.hours;
	int numThreads = query!"SELECT COUNT(*)                      FROM [Threads] WHERE [Created] >= ?".iterate(cutOff.stdTime).selectValue!int;
	int numPosts   = query!"SELECT COUNT(*)                      FROM [Posts]   WHERE [Time]    >= ?".iterate(cutOff.stdTime).selectValue!int;
	int numUsers   = query!"SELECT COUNT(DISTINCT [AuthorEmail]) FROM [Posts]   WHERE [Time]    >= ?".iterate(cutOff.stdTime).selectValue!int;

	bits[(numThreads || numPosts) ? 1 : 2] ~=
		"<li>"
		~
		(
			(numThreads || numPosts)
			?
				"%d user%s ha%s created %-(%s and %)"
				.format(
					numUsers,
					numUsers==1 ? "" : "s",
					numThreads+numPosts==1 ? "s" : "ve",
					(numThreads ? [`<a href="/search?q=time:%d..+newthread:y">%s thread%s</a>`.format(cutOff.stdTime, formatNumber(numThreads), numThreads==1 ? "" : "s")] : [])
					~
					(numPosts   ? [`<a href="/search?q=time:%d..">%s post%s</a>`              .format(cutOff.stdTime, formatNumber(numPosts  ), numPosts  ==1 ? "" : "s")] : [])
				)
			:
				"No new forum activity"
		)
		~
		(
			previousSession
			?
				" since your last visit (%s).".format(formatDuration(now - cutOff))
			:
				" in the last 24 hours."
		)
		~
		"</li>"
	;

	bits[2] ~= "<li>There are %s posts, %s threads, and %s registered users on this forum.</li>"
		.format(
			formatNumber(totalPostCountCache  (query!"SELECT COUNT(*) FROM [Posts]"  .iterate().selectValue!int)),
			formatNumber(totalThreadCountCache(query!"SELECT COUNT(*) FROM [Threads]".iterate().selectValue!int)),
			formatNumber(                      query!"SELECT COUNT(*) FROM [Users]"  .iterate().selectValue!int ),
		);

	auto numRead = user.countRead();
	if (numRead)
		bits[2] ~= "<li>You have read a total of %s forum post%s during your visit%s.</li>".format(formatNumber(numRead), numRead==1?"":"s", previousSession?"s":"");

	bits[2] ~= "<li>Random tip: " ~ tips[uniform(0, $)] ~ "</li>";

	foreach (bitGroup; bits[])
		foreach (bit; bitGroup)
			html.put(bit);
	html.put(
		`</ul>` ~
		`</div>`
	);

	//html.put("<p>Random tip: " ~ tips[uniform(0, $)] ~ "</p>");
}

string[] tips =
[
	`This forum has several different <a href="/help#view-modes">view modes</a>. Try them to find one you like best. You can change the view mode in the <a href="/settings">settings</a>.`,
	`This forum supports <a href="/help#keynav">keyboard shortcuts</a>. Press <kbd>?</kbd> to view them.`,
	`You can focus a message with <kbd>j</kbd>/<kbd>k</kbd> and press <kbd>u</kbd> to mark it as unread, to remind you to read it later.`,
	`The <a href="/help#avatars">avatars on this forum</a> are provided by Gravatar, which allows associating a global avatar with an email address.`,
	`This forum remembers your read post history on a per-post basis. If you are logged in, the post history is saved on the server, and in a compressed cookie otherwise.`,
	`Much of this forum's content is also available via classic mailing lists or NNTP - see the "Also via" column on the forum index.`,
	`If you create a Gravatar profile with the email address you post with, it will be accessible when clicking your avatar.`,
//	`You don't need to create an account to post on this forum, but doing so <a href="/help#accounts">offers a few benefits</a>.`,
	`To subscribe to a thread, click the "Subscribe" link on that thread's first post. You need to be logged in to create subscriptions.`,
	`To search the forum, use the search widget at the top, or you can visit <a href="/search">the search page</a> directly.`,
	`This forum is open-source! Read or fork the code <a href="https://github.com/CyberShadow/DFeed">on GitHub</a>.`,
	`If you encounter a bug or need a missing feature, you can <a href="https://github.com/CyberShadow/DFeed/issues">create an issue on GitHub</a>.`,
];

int[string] getThreadCounts()
{
	enum PERF_SCOPE = "getThreadCounts"; mixin(MeasurePerformanceMixin);
	int[string] threadCounts;
	foreach (string group, int count; query!"SELECT `Group`, COUNT(*) FROM `Threads` GROUP BY `Group`".iterate())
		threadCounts[group] = count;
	return threadCounts;
}

int[string] getPostCounts()
{
	enum PERF_SCOPE = "getPostCounts"; mixin(MeasurePerformanceMixin);
	int[string] postCounts;
	foreach (string group, int count; query!"SELECT `Group`, COUNT(*) FROM `Groups`  GROUP BY `Group`".iterate())
		postCounts[group] = count;
	return postCounts;
}

string[string] getLastPosts()
{
	enum PERF_SCOPE = "getLastPosts"; mixin(MeasurePerformanceMixin);
	string[string] lastPosts;
	foreach (set; groupHierarchy)
		foreach (group; set.groups)
			foreach (string id; query!"SELECT `ID` FROM `Groups` WHERE `Group`=? ORDER BY `Time` DESC LIMIT 1".iterate(group.internalName))
				lastPosts[group.internalName] = id;
	return lastPosts;
}

Cached!(int[string]) threadCountCache, postCountCache;
Cached!(string[string]) lastPostCache;

void discussionIndex()
{
	discussionIndexHeader();

	auto threadCounts = threadCountCache(getThreadCounts());
	auto postCounts = postCountCache(getPostCounts());
	auto lastPosts = lastPostCache(getLastPosts());

	string summarizePost(string postID)
	{
		auto info = getPostInfo(postID);
		if (info)
			with (*info)
				return
					`<div class="truncated"><a class="forum-postsummary-subject ` ~ (user.isRead(rowid) ? "forum-read" : "forum-unread") ~ `" href="` ~ encodeHtmlEntities(idToUrl(id)) ~ `" title="` ~ encodeHtmlEntities(subject) ~ `">` ~ encodeHtmlEntities(subject) ~ `</a></div>` ~
					`<div class="truncated">by <span class="forum-postsummary-author" title="` ~ encodeHtmlEntities(author) ~ `">` ~ encodeHtmlEntities(author) ~ `</span></div>` ~
					`<span class="forum-postsummary-time">` ~ summarizeTime(time) ~ `</span>`;

		return `<div class="forum-no-data">-</div>`;
	}
	html.put(
		`<table id="forum-index" class="forum-table">` ~
		`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(5), `</tr>` // Fixed layout dummies
	);
	foreach (set; groupHierarchy)
	{
		if (!set.visible)
			continue;

		html.put(
			`<tr><th colspan="5">`), html.putEncodedEntities(set.name), html.put(`</th></tr>` ~
			`<tr class="subheader"><th>Group</th><th>Last Post</th><th>Threads</th><th>Posts</th><th>Also via</th></tr>`
		);
		foreach (group; set.groups)
		{
			html.put(
				`<tr class="group-row">` ~
					`<td class="forum-index-col-forum">` ~
						`<a href="/group/`), html.putEncodedEntities(group.urlName), html.put(`">`), html.putEncodedEntities(group.publicName), html.put(`</a>` ~
						`<div class="forum-index-description" title="`), html.putEncodedEntities(group.description), html.put(`">`), html.putEncodedEntities(group.description), html.put(`</div>` ~
					`</td>` ~
					`<td class="forum-index-col-lastpost">`, group.internalName in lastPosts    ? summarizePost(   lastPosts[group.internalName]) : `<div class="forum-no-data">-</div>`, `</td>` ~
					`<td class="number-column">`,            group.internalName in threadCounts ? formatNumber (threadCounts[group.internalName]) : `-`, `</td>` ~
					`<td class="number-column">`,            group.internalName in postCounts   ? formatNumber (  postCounts[group.internalName]) : `-`, `</td>` ~
					`<td class="number-column">`
			);
			foreach (i, av; group.alsoVia.values)
				html.put(i ? `<br>` : ``, `<a href="`, av.url, `">`, av.name, `</a>`);
			html.put(
					`</td>` ~
				`</tr>`,
			);
		}
	}
	html.put(`</table>`);
}

Cached!(ActiveDiscussion[]) activeDiscussionsCache;
Cached!(string[]) latestAnnouncementsCache;
enum framePostsLimit = 10;

static struct ActiveDiscussion { string id; int postCount; }

ActiveDiscussion[] getActiveDiscussions()
{
	enum PERF_SCOPE = "getActiveDiscussions"; mixin(MeasurePerformanceMixin);
	const groupFilter = ["digitalmars.D.announce", "digitalmars.D.bugs"]; // TODO: config
	enum postCountLimit = 10;
	ActiveDiscussion[] result;
	foreach (string group, string firstPostID; query!"SELECT [Group], [ID] FROM [Threads] ORDER BY [Created] DESC LIMIT 100".iterate())
	{
		if (groupFilter.canFind(group))
			continue;

		int postCount;
		foreach (int count; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?".iterate(firstPostID))
			postCount = count;
		if (postCount < postCountLimit)
			continue;

		result ~= ActiveDiscussion(firstPostID, postCount);
		if (result.length == framePostsLimit)
			break;
	}
	return result;
}

string[] getLatestAnnouncements()
{
	enum PERF_SCOPE = "getLatestAnnouncements"; mixin(MeasurePerformanceMixin);
	enum group = "digitalmars.D.announce"; // TODO: config
	string[] result;
	foreach (string firstPostID; query!"SELECT [Threads].[ID] FROM [Threads] JOIN [Posts] ON [Threads].[ID]=[Posts].[ID] WHERE [Threads].[Group] = ? ORDER BY [Posts].[Time] DESC LIMIT ?".iterate(group, framePostsLimit))
		result ~= firstPostID;
	return result;
}

void summarizeFrameThread(PostInfo* info, string infoText)
{
	if (info)
		with (*info)
		{
			putGravatar(getGravatarHash(info.authorEmail), idToUrl(id), `target="_top" class="forum-postsummary-gravatar" `);
			html.put(
				`<a target="_top" class="forum-postsummary-subject `, (user.isRead(rowid) ? "forum-read" : "forum-unread"), `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`">`), html.putEncodedEntities(subject), html.put(`</a><br>` ~
				`<div class="forum-postsummary-info">`, infoText, `</div>` ~
				`by <span class="forum-postsummary-author">`), html.putEncodedEntities(author), html.put(`</span>`
			);
			return;
		}

	html.put(`<div class="forum-no-data">-</div>`);
}

void discussionFrameAnnouncements()
{
	auto latestAnnouncements = latestAnnouncementsCache(getLatestAnnouncements());

	html.put(`<table class="forum-table"><thead><tr><th>` ~
		`<a target="_top" class="feed-icon" title="Subscribe" href="/feed/threads/digitalmars.D.announce"><img src="`, staticPath("/images/rss.png"),`"></img></a>` ~
		`<a target="_top" href="/group/digitalmars.D.announce">Latest announcements</a>` ~
		`</th></tr></thead><tbody>`);
	foreach (row; latestAnnouncements)
	{
		auto info = getPostInfo(row);
		html.put(`<tr><td>`), summarizeFrameThread(info, summarizeTime(info.time)), html.put(`</td></tr>`);
	}
	html.put(`</tbody></table>`);
}

void discussionFrameDiscussions()
{
	auto activeDiscussions = activeDiscussionsCache(getActiveDiscussions());

	html.put(`<table class="forum-table"><thead><tr><th><a target="_top" href="/">Active discussions</a></th></tr></thead><tbody>`);
	foreach (row; activeDiscussions)
		html.put(`<tr><td>`), summarizeFrameThread(getPostInfo(row.id), "%d posts".format(row.postCount)), html.put(`</td></tr>`);
	html.put(`</tbody></table>`);
}

// ***********************************************************************

int[] getThreadPostIndexes(string id)
{
	int[] result;
	foreach (int rowid; query!"SELECT `ROWID` FROM `Posts` WHERE `ThreadID` = ?".iterate(id))
		result ~= rowid;
	return result;
}

CachedSet!(string, int[]) threadPostIndexCache;

void newPostButton(GroupInfo groupInfo)
{
	html.put(
		`<form name="new-post-form" method="get" action="/newpost/`), html.putEncodedEntities(groupInfo.urlName), html.put(`">` ~
			`<div class="header-tools">` ~
				`<input class="btn" type="submit" value="Create thread">` ~
				`<input class="img" type="image" src="`, staticPath("/images/newthread.png"), `" alt="Create thread">` ~
			`</div>` ~
		`</form>`);
}

/// pageCount==int.max indicates unknown number of pages
void pager(string base, int page, int pageCount, int maxWidth = 50)
{
	string linkOrNot(string text, int page, bool cond)
	{
		if (cond)
			return `<a href="` ~ encodeHtmlEntities(base) ~ (base.canFind('?') ? `&` : `?`) ~ `page=` ~ .text(page) ~ `">` ~ text ~ `</a>`;
		else
			return `<span class="disabled-link">` ~ text ~ `</span>`;
	}

	// Try to make the pager as wide as it will fit in the alotted space

	int widthAt(int radius)
	{
		import std.math : log10;

		int pagerStart = max(1, page - radius);
		int pagerEnd = min(pageCount, page + radius);
		if (pageCount==int.max)
			pagerEnd = page + 1;

		int width = pagerEnd - pagerStart;
		foreach (n; pagerStart..pagerEnd+1)
			width += 1 + cast(int)log10(n);
		if (pagerStart > 1)
			width += 3;
		if (pagerEnd < pageCount)
			width += 3;
		return width;
	}

	int radius = 0;
	for (; radius < 10 && widthAt(radius+1) < maxWidth; radius++) {}

	int pagerStart = max(1, page - radius);
	int pagerEnd = min(pageCount, page + radius);
	if (pageCount==int.max)
		pagerEnd = page + 1;

	string[] pager;
	if (pagerStart > 1)
		pager ~= "&hellip;";
	foreach (pagerPage; pagerStart..pagerEnd+1)
		if (pagerPage == page)
			pager ~= `<b>` ~ text(pagerPage) ~ `</b>`;
		else
			pager ~= linkOrNot(text(pagerPage), pagerPage, true);
	if (pagerEnd < pageCount)
		pager ~= "&hellip;";

	html.put(
		`<tr class="pager"><th colspan="3">` ~
			`<div class="pager-left">`,
				linkOrNot("&laquo; First", 1, page!=1),
				`&nbsp;&nbsp;&nbsp;`,
				linkOrNot("&lsaquo; Prev", page-1, page>1),
			`</div>` ~
			`<div class="pager-right">`,
				linkOrNot("Next &rsaquo;", page+1, page<pageCount),
				`&nbsp;&nbsp;&nbsp;`,
				linkOrNot("Last &raquo; ", pageCount, page!=pageCount && pageCount!=int.max),
			`</div>` ~
			`<div class="pager-numbers">`, pager.join(` `), `</div>` ~
		`</th></tr>`);
}

enum THREADS_PER_PAGE = 15;
enum POSTS_PER_PAGE = 10;

static int indexToPage(int index, int perPage)  { return index / perPage + 1; } // Return value is 1-based, index is 0-based
static int getPageCount(int count, int perPage) { return indexToPage(count-1, perPage); }
static int getPageOffset(int page, int perPage) { return (page-1) * perPage; }

void threadPager(GroupInfo groupInfo, int page, int maxWidth = 40)
{
	auto threadCounts = threadCountCache(getThreadCounts());
	enforce(groupInfo.internalName in threadCounts, "Empty group: " ~ groupInfo.publicName);
	auto threadCount = threadCounts[groupInfo.internalName];
	auto pageCount = getPageCount(threadCount, THREADS_PER_PAGE);

	pager(`/group/` ~ groupInfo.urlName, page, pageCount, maxWidth);
}

void discussionGroup(GroupInfo groupInfo, int page)
{
	enforce(page >= 1, "Invalid page");

	struct Thread
	{
		string id;
		PostInfo* _firstPost, _lastPost;
		int postCount, unreadPostCount;

		/// Handle orphan posts
		@property PostInfo* firstPost() { return _firstPost ? _firstPost : _lastPost; }
		@property PostInfo* lastPost() { return _lastPost; }

		@property bool isRead() { return unreadPostCount==0; }
	}
	Thread[] threads;

	int getUnreadPostCount(string id)
	{
		auto posts = threadPostIndexCache(id, getThreadPostIndexes(id));
		int count = 0;
		foreach (post; posts)
			if (!user.isRead(post))
				count++;
		return count;
	}

	foreach (string firstPostID, string lastPostID; query!"SELECT `ID`, `LastPost` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(groupInfo.internalName, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
		foreach (int count; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?".iterate(firstPostID))
			threads ~= Thread(firstPostID, getPostInfo(firstPostID), getPostInfo(lastPostID), count, getUnreadPostCount(firstPostID));

	void summarizeThread(string tid, PostInfo* info, bool isRead)
	{
		if (info)
			with (*info)
			{
				putGravatar(getGravatarHash(info.authorEmail), idToUrl(tid, "thread"), `class="forum-postsummary-gravatar" `);
				html.put(
				//	`<!-- Thread ID: ` ~ encodeHtmlEntities(threadID) ~ ` | First Post ID: ` ~ encodeHtmlEntities(id) ~ `-->` ~
					`<div class="truncated"><a class="forum-postsummary-subject `, (isRead ? "forum-read" : "forum-unread"), `" href="`), html.putEncodedEntities(idToUrl(tid, "thread")), html.put(`" title="`), html.putEncodedEntities(subject), html.put(`">`), html.putEncodedEntities(subject), html.put(`</a></div>` ~
					`<div class="truncated">by <span class="forum-postsummary-author" title="`), html.putEncodedEntities(author), html.put(`">`), html.putEncodedEntities(author), html.put(`</span></div>`);
				return;
			}

		html.put(`<div class="forum-no-data">-</div>`);
	}

	void summarizeLastPost(PostInfo* info)
	{
		if (info)
			with (*info)
			{
				html.put(
					`<a class="forum-postsummary-time `, user.isRead(rowid) ? "forum-read" : "forum-unread", `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`">`, summarizeTime(time), `</a>` ~
					`<div class="truncated">by <span class="forum-postsummary-author" title="`), html.putEncodedEntities(author), html.put(`">`), html.putEncodedEntities(author), html.put(`</span></div>`);
				return;
			}
		html.put(`<div class="forum-no-data">-</div>`);
	}

	void summarizePostCount(ref Thread thread)
	{
		html.put(`<a class="secretlink" href="`), html.putEncodedEntities(idToUrl(thread.id, "thread")), html.put(`">`);
		if (thread.unreadPostCount == 0)
			html ~= formatNumber(thread.postCount-1);
		else
			html.put(`<b>`, formatNumber(thread.postCount-1), `</b>`);
		html.put(`</a>`);

		if (thread.unreadPostCount && thread.unreadPostCount != thread.postCount)
			html.put(
				`<br>(<a href="`, idToUrl(thread.id, "first-unread"), `">`, formatNumber(thread.unreadPostCount), ` new</a>)`);
	}

	html.put(
		`<table id="group-index" class="forum-table">` ~
		`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(3), `</tr>` ~ // Fixed layout dummies
		`<tr class="group-index-header"><th colspan="3"><div class="header-with-tools">`), newPostButton(groupInfo), html.putEncodedEntities(groupInfo.publicName), html.put(`</div></th></tr>` ~
		`<tr class="subheader"><th>Thread / Thread Starter</th><th>Last Post</th><th>Replies</th>`);
	foreach (thread; threads)
		html.put(
			`<tr class="thread-row">` ~
				`<td class="group-index-col-first">`), summarizeThread(thread.id, thread.firstPost, thread.isRead), html.put(`</td>` ~
				`<td class="group-index-col-last">`), summarizeLastPost(thread.lastPost), html.put(`</td>` ~
				`<td class="number-column">`), summarizePostCount(thread), html.put(`</td>` ~
			`</tr>`);
	threadPager(groupInfo, page);
	html.put(
		`</table>`
	);
}

// ***********************************************************************

string[][string] referenceCache; // invariant

void formatThreadedPosts(PostInfo*[] postInfos, bool narrow, string selectedID = null)
{
	enum OFFSET_INIT = 1f;
	enum OFFSET_MAX = 2f;
	enum OFFSET_WIDTH = 25f;
	enum OFFSET_UNITS = "%";

	class Post
	{
		PostInfo* info;

		SysTime maxTime;
		Post[] children;
		int maxDepth;

		bool ghost; // dummy parent for orphans
		string ghostSubject;

		@property string subject() { return ghostSubject ? ghostSubject : info.subject; }

		this(PostInfo* info = null) { this.info = info; }

		void calcStats()
		{
			foreach (child; children)
				child.calcStats();

			if (info)
				maxTime = info.time;
			foreach (child; children)
				if (maxTime < child.maxTime)
					maxTime = child.maxTime;
			//maxTime = reduce!max(time, map!"a.maxTime"(children));

			maxDepth = 1;
			foreach (child; children)
				if (maxDepth < 1 + child.maxDepth)
					maxDepth = 1 + child.maxDepth;
		}
	}

	Post[string] posts;
	foreach (info; postInfos)
		posts[info.id] = new Post(info);

	posts[null] = new Post();
	foreach (post; posts.values)
		if (post.info)
		{
			auto parent = post.info.parentID;
			if (parent !in posts) // mailing-list users
			{
				string[] references;
				if (post.info.id in referenceCache)
					references = referenceCache[post.info.id];
				else
					references = referenceCache[post.info.id] = getPost(post.info.id).references;

				parent = null;
				foreach_reverse (reference; references)
					if (reference in posts)
					{
						parent = reference;
						break;
					}

				if (!parent)
				{
					auto dummy = new Post;
					dummy.ghost = true;
					dummy.ghostSubject = post.info.subject; // HACK
					parent = references[0];
					posts[parent] = dummy;
					posts[null].children ~= dummy;
				}
			}
			posts[parent].children ~= post;
		}

	bool reversed = userSettings.groupViewMode == "threaded";
	foreach (post; posts)
	{
		post.calcStats();
		if (post.info || post.ghost)
			sort!"a.info.time < b.info.time"(post.children);
		else // sort threads by last-update
		if (reversed)
			sort!"a.maxTime > b.maxTime"(post.children);
		else
			sort!"a.maxTime < b.maxTime"(post.children);
	}

	float offsetIncrement; // = max(1f, min(OFFSET_MAX, OFFSET_WIDTH / posts[null].maxDepth));

	string normalizeSubject(string s)
	{
		s.skipOver("Re: ");
		return s
			.replace("New: ", "") // Bugzilla hack
			.replace("\t", " ")   // Apple Mail hack
			.replace(" ", "")     // Outlook Express hack
		;
	}

	// Group replies under a ghost post when multiple replies have the same subject,
	// but different from their parent (Bugzilla hack)
	foreach (thread; posts[null].children)
	{
		for (int i=1; i<thread.children.length; )
		{
			auto child = thread.children[i];
			auto prevChild = thread.children[i-1];
			if (normalizeSubject(child.subject) != normalizeSubject(thread.subject) &&
				normalizeSubject(child.subject) == normalizeSubject(prevChild.subject))
			{
				if (prevChild.ghost) // add to the existing ghost
				{
					prevChild.children ~= child;
					thread.children = thread.children[0..i] ~ thread.children[i+1..$];
				}
				else // new ghost
				{
					auto dummy = new Post;
					dummy.ghost = true;
					dummy.ghostSubject = child.subject;
					dummy.children = [prevChild, child];
					thread.children = thread.children[0..i-1] ~ dummy ~ thread.children[i+1..$];
				}
			}
			else
				i++;
		}
	}

	void formatPosts(Post[] posts, int level, string parentSubject, bool topLevel)
	{
		void formatPost(Post post, int level)
		{
			if (post.ghost)
				return formatPosts(post.children, level, post.subject, false);
			html.put(
				`<tr class="thread-post-row`, (post.info && post.info.id==selectedID ? ` focused selected` : ``), `">` ~
					`<td>` ~
						`<div style="padding-left: `, format("%1.1f", OFFSET_INIT + level * offsetIncrement), OFFSET_UNITS, `">` ~
							`<div class="thread-post-time">`, summarizeTime(post.info.time, true), `</div>`,
							`<a class="postlink `, (user.isRead(post.info.rowid) ? "forum-read" : "forum-unread" ), `" href="`), html.putEncodedEntities(idToUrl(post.info.id)), html.put(`">`, truncateString(post.info.author, narrow ? 17 : 50), `</a>` ~
						`</div>` ~
					`</td>` ~
				`</tr>`);
			formatPosts(post.children, level+1, post.subject, false);
		}

		foreach (post; posts)
		{
			if (topLevel)
				offsetIncrement = min(OFFSET_MAX, OFFSET_WIDTH / post.maxDepth);

			if (topLevel || normalizeSubject(post.subject) != normalizeSubject(parentSubject))
			{
				auto offsetStr = format("%1.1f", OFFSET_INIT + level * offsetIncrement) ~ OFFSET_UNITS;
				html.put(
					`<tr><td style="padding-left: `, offsetStr, `">` ~
					`<table class="thread-start">` ~
						`<tr><th>`), html.putEncodedEntities(post.subject), html.put(`</th></tr>`);
                formatPost(post, 0);
				html.put(
					`</table>` ~
					`</td></tr>`);
			}
			else
				formatPost(post, level);
		}
	}

	formatPosts(posts[null].children, 0, null, true);
}

void discussionGroupThreaded(GroupInfo groupInfo, int page, bool narrow = false)
{
	enforce(page >= 1, "Invalid page");

	//foreach (string threadID; query!"SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
	//	foreach (string id, string parent, string author, string subject, long stdTime; query!"SELECT `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?".iterate(threadID))
	PostInfo*[] posts;
	enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` IN (SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?)";
	foreach (int rowid, string id, string parent, string author, string authorEmail, string subject, long stdTime; query!ViewSQL.iterate(groupInfo.internalName, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
		posts ~= [PostInfo(rowid, id, null, parent, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr; // TODO: optimize?

	html.put(
		`<table id="group-index-threaded" class="forum-table group-wrapper viewmode-`), html.putEncodedEntities(userSettings.groupViewMode), html.put(`">` ~
		`<tr class="group-index-header"><th><div>`), newPostButton(groupInfo), html.putEncodedEntities(groupInfo.publicName), html.put(`</div></th></tr>`,
	//	`<tr class="group-index-captions"><th>Subject / Author</th><th>Time</th>`,
		`<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
	formatThreadedPosts(posts, narrow);
	html.put(`</table></div></td></tr>`);
	threadPager(groupInfo, page, narrow ? 25 : 50);
	html.put(`</table>`);
}

void discussionGroupSplit(GroupInfo groupInfo, int page)
{
	html.put(
		`<table id="group-split"><tr>` ~
		`<td id="group-split-list"><div>`);
	discussionGroupThreaded(groupInfo, page, true);
	html.put(
		`</div></td>` ~
		`<td id="group-split-message" class="group-split-message-none"><span>` ~
			`Loading...` ~
			`<div class="nojs">Sorry, this view requires JavaScript.</div>` ~
		`</span></td>` ~
		`</tr></table>`);
}

void discussionGroupSplitFromPost(string id, out GroupInfo groupInfo, out int page, out string threadID)
{
	auto post = getPost(id);
	enforce(post, "Post not found");

	groupInfo = post.getGroup();
	enforce(groupInfo, "Unknown group: " ~ post.where);
	threadID = post.cachedThreadID;
	page = getThreadPage(groupInfo, threadID);

	discussionGroupSplit(groupInfo, page);
}

int getThreadPage(GroupInfo groupInfo, string thread)
{
	int page = 0;

	foreach (long time; query!"SELECT `LastUpdated` FROM `Threads` WHERE `ID` = ? LIMIT 1".iterate(thread))
		foreach (int threadIndex; query!"SELECT COUNT(*) FROM `Threads` WHERE `Group` = ? AND `LastUpdated` > ? ORDER BY `LastUpdated` DESC".iterate(groupInfo.internalName, time))
			page = indexToPage(threadIndex, THREADS_PER_PAGE);

	enforce(page > 0, "Can't find thread's page");
	return page;
}

string[] formatPostParts(Rfc850Post post)
{
	string[] partList;
	void visitParts(Rfc850Message[] parts, int[] path)
	{
		foreach (int i, part; parts)
		{
			if (part.parts.length)
				visitParts(part.parts, path~i);
			else
			if (part.content !is post.content)
			{
				string partUrl = ([idToUrl(post.id, "raw")] ~ array(map!text(path~i))).join("/");
				with (part)
					partList ~=
						(name || fileName) ?
							`<a href="` ~ encodeHtmlEntities(partUrl) ~ `" title="` ~ encodeHtmlEntities(mimeType) ~ `">` ~
							encodeHtmlEntities(name) ~
							(name && fileName ? " - " : "") ~
							encodeHtmlEntities(fileName) ~
							`</a>` ~
							(description ? ` (` ~ encodeHtmlEntities(description) ~ `)` : "")
						:
							`<a href="` ~ encodeHtmlEntities(partUrl) ~ `">` ~
							encodeHtmlEntities(mimeType) ~
							`</a> part` ~
							(description ? ` (` ~ encodeHtmlEntities(description) ~ `)` : "");
			}
		}
	}
	visitParts(post.parts, null);
	return partList;
}

string gravatar(string authorEmail, int size)
{
	return `https://www.gravatar.com/avatar/%s?d=identicon&s=%d`.format(getGravatarHash(authorEmail), size);
}

enum gravatarMetaSize = 256;

string getGravatarHash(string email)
{
	import std.digest.md;
	import std.ascii : LetterCase;
	return email.toLower().strip().md5Of().toHexString!(LetterCase.lower)().idup; // Issue 9279
}

void putGravatar(string gravatarHash, string linkTarget, string aProps = null, int size = 0)
{
	html.put(
		`<a `, aProps, ` href="`), html.putEncodedEntities(linkTarget), html.put(`">` ~
			`<img alt="Gravatar" class="post-gravatar" `);
	if (size)
	{
		string sizeStr = size ? text(size) : null;
		string x2str = text(size * 2);
		html.put(
			`width="`, sizeStr, `" height="`, sizeStr, `" ` ~
			`src="//www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&amp;s=`, sizeStr, `" ` ~
			`srcset="//www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&amp;s=`, x2str, ` `, x2str, `w"` ~
			`>`
		);
	}
	else
		html.put(
			`src="//www.gravatar.com/avatar/`, gravatarHash, `?d=identicon" ` ~
			`srcset="//www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&amp;s=160 2x"` ~
			`>`
		);
	html.put(`</a>`);
}
// ***********************************************************************

void formatVSplitPosts(PostInfo*[] postInfos, string selectedID = null)
{
/*
	html.put(
		`<tr class="thread-post-row">` ~
			`<th>Subject</th>` ~
			`<th>From</th>` ~
		`</tr>`
	);
*/

	foreach (postInfo; postInfos)
	{
		html.put(
			`<tr class="thread-post-row`, (postInfo && postInfo.id==selectedID ? ` focused selected` : ``), `">` ~
				`<td>` ~
					`<a class="postlink `, (user.isRead(postInfo.rowid) ? "forum-read" : "forum-unread" ), `" ` ~
						`href="`), html.putEncodedEntities(idToUrl(postInfo.id)), html.put(`">`
						), html.putEncodedEntities(postInfo.subject), html.put(
					`</a>` ~
				`</td>` ~
				`<td>`
					), html.putEncodedEntities(postInfo.author), html.put(
				`</td>` ~
				`<td>` ~
					`<div class="thread-post-time">`, summarizeTime(postInfo.time, true), `</div>`,
				`</td>` ~
			`</tr>`
		);
	}
}

enum POSTS_PER_GROUP_PAGE = 100;

void discussionGroupVSplitList(GroupInfo groupInfo, int page)
{
	enum postsPerPage = POSTS_PER_GROUP_PAGE;
	enforce(page >= 1, "Invalid page");

	//foreach (string threadID; query!"SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
	//	foreach (string id, string parent, string author, string subject, long stdTime; query!"SELECT `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?".iterate(threadID))
	PostInfo*[] posts;
	//enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` IN (SELECT `ID` FROM `Threads` WHERE `Group` = ?) ORDER BY `Time` DESC LIMIT ? OFFSET ?";
	//enum ViewSQL = "SELECT [Posts].[ROWID], [Posts].[ID], `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` "
	//	"INNER JOIN [Threads] ON `ThreadID`==[Threads].[ID] WHERE `Group` = ? ORDER BY `Time` DESC LIMIT ? OFFSET ?";
	enum ViewSQL = "SELECT [Posts].[ROWID], [Posts].[ID], [ParentID], [Author], [AuthorEmail], [Subject], [Posts].[Time] FROM [Groups] " ~
		"INNER JOIN [Posts] ON [Posts].[ID]==[Groups].[ID] WHERE [Group] = ? ORDER BY [Groups].[Time] DESC LIMIT ? OFFSET ?";
	foreach (int rowid, string id, string parent, string author, string authorEmail, string subject, long stdTime; query!ViewSQL.iterate(groupInfo.internalName, postsPerPage, getPageOffset(page, postsPerPage)))
		posts ~= [PostInfo(rowid, id, null, parent, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr; // TODO: optimize?
	posts.reverse();

	html.put(
		`<table id="group-index-vsplit" class="forum-table group-wrapper viewmode-`), html.putEncodedEntities(userSettings.groupViewMode), html.put(`">` ~
		`<tr class="group-index-header"><th><div>`), newPostButton(groupInfo), html.putEncodedEntities(groupInfo.publicName), html.put(`</div></th></tr>`,
	//	`<tr class="group-index-captions"><th>Subject / Author</th><th>Time</th>`,
		`<tr><td class="group-threads-cell"><div class="group-threads"><table id="group-posts-vsplit">` ~
		`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(3), `</tr>` // Fixed layout dummies
	);
	formatVSplitPosts(posts);
	html.put(`</table></div></td></tr>`);
	groupPostPager(groupInfo, page);
	html.put(`</table>`);
}

void discussionGroupVSplit(GroupInfo groupInfo, int page)
{
	html.put(
		`<table id="group-vsplit"><tr>` ~
		`<td id="group-vsplit-list"><div>`);
	discussionGroupVSplitList(groupInfo, page);
	html.put(
		`</div></td></tr>` ~
		`<tr><td id="group-split-message" class="group-split-message-none">` ~
			`Loading...` ~
			`<div class="nojs">Sorry, this view requires JavaScript.</div>` ~
		`</td>` ~
		`</tr></table>`);
}

int getVSplitPostPage(GroupInfo groupInfo, string id)
{
	int page = 0;

	foreach (long time; query!"SELECT [Time] FROM [Groups] WHERE [ID] = ? LIMIT 1".iterate(id))
		foreach (int threadIndex; query!"SELECT COUNT(*) FROM [Groups] WHERE [Group] = ? AND [Time] > ? ORDER BY [Time] DESC".iterate(groupInfo.internalName, time))
			page = indexToPage(threadIndex, POSTS_PER_GROUP_PAGE);

	enforce(page > 0, "Can't find post's page");
	return page;
}

void discussionGroupVSplitFromPost(string id, out GroupInfo groupInfo, out int page, out string threadID)
{
	auto post = getPost(id);
	enforce(post, "Post not found");

	groupInfo = post.getGroup();
	threadID = post.cachedThreadID;
	page = getVSplitPostPage(groupInfo, id);

	discussionGroupVSplit(groupInfo, page);
}

void groupPostPager(GroupInfo groupInfo, int page)
{
	auto postCounts = postCountCache(getPostCounts());
	enforce(groupInfo.internalName in postCounts, "Empty group: " ~ groupInfo.publicName);
	auto postCount = postCounts[groupInfo.internalName];
	auto pageCount = getPageCount(postCount, POSTS_PER_GROUP_PAGE);

	pager(`/group/` ~ groupInfo.urlName, page, pageCount, 50);
}

void discussionVSplitPost(string id)
{
	auto post = getPost(id);
	enforce(post, "Post not found");

	formatPost(post, null);
}

// ***********************************************************************

struct PostAction { string className, text, title, url, icon; }

PostAction[] getPostActions(Rfc850Message msg)
{
	PostAction[] actions;
	auto id = msg.id;
	if (userSettings.groupViewMode == "basic")
		actions ~= PostAction("permalink", "Permalink",
			"Canonical link to this post. See \"Canonical links\" on the Help page for more information.",
			idToUrl(id), "link");
	if (true)
		actions ~= PostAction("replylink", "Reply",
			"Reply to this post",
			idToUrl(id, "reply"), "reply");
/*
	if (mailHide)
		actions ~= PostAction("emaillink", "Email",
			"Solve a CAPTCHA to obtain this poster's email address.",
			mailHide.getUrl(msg.authorEmail), "email");
*/
	if (user.isLoggedIn() && msg.references.length == 0)
		actions ~= PostAction("subscribelink", "Subscribe",
			"Subscribe to this thread",
			idToUrl(id, "subscribe"), "star");
	if (user.getLevel() >= User.Level.canFlag && user.createdAt() < msg.time)
		actions ~= PostAction("flaglink", "Flag",
			"Flag this post for moderator intervention",
			idToUrl(id, "flag"), "flag");
	if (user.getLevel() >= User.Level.hasRawLink)
		actions ~= PostAction("sourcelink", "Source",
			"View this message's source code",
			idToUrl(id, "source"), "source");
	if (user.getLevel() >= User.Level.canDeletePosts)
		actions ~= PostAction("deletelink", "Delete",
			"Delete this message from DFeed's database",
			idToUrl(id, "delete"), "delete");
	return actions;
}

void postActions(PostAction[] actions)
{
	foreach (action; actions)
		html.put(
			`<a class="actionlink `, action.className, `" href="`), html.putEncodedEntities(action.url), html.put(`" ` ~
				`title="`), html.putEncodedEntities(action.title), html.put(`">` ~
				`<img src="`, staticPath("/images/" ~ action.icon~ ".png"), `">`), html.putEncodedEntities(action.text), html.put(
			`</a>`);
}

string getParentLink(Rfc850Post post, Rfc850Post[string] knownPosts)
{
	if (post.parentID)
	{
		string author, link;
		if (post.parentID in knownPosts)
		{
			auto parent = knownPosts[post.parentID];
			author = parent.author;
			link = '#' ~ idToFragment(parent.id);
		}
		else
		{
			auto parent = getPostInfo(post.parentID);
			if (parent)
			{
				author = parent.author;
				link = idToUrl(parent.id);
			}
		}

		if (author && link)
			return `<a href="` ~ encodeHtmlEntities(link) ~ `">` ~ encodeHtmlEntities(author) ~ `</a>`;
	}

	return null;
}

void formatPost(Rfc850Post post, Rfc850Post[string] knownPosts, bool markAsRead = true)
{
	string gravatarHash = getGravatarHash(post.authorEmail);

	string[] infoBits;

	auto parentLink = getParentLink(post, knownPosts);
	if (parentLink)
		infoBits ~= `Posted in reply to ` ~ parentLink;

	auto partList = formatPostParts(post);
	if (partList.length)
		infoBits ~=
			`Attachments:<ul class="post-info-parts"><li>` ~ partList.join(`</li><li>`) ~ `</li></ul>`;

	if (knownPosts is null && post.cachedThreadID)
		infoBits ~=
			`<a href="` ~ encodeHtmlEntities(idToThreadUrl(post.id, post.cachedThreadID)) ~ `">View in thread</a>`;

	string repliesTitle = `Replies to `~encodeHtmlEntities(post.author)~`'s post from `~encodeHtmlEntities(formatShortTime(post.time, false));

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="post forum-table`, (post.children ? ` with-children` : ``), `" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(2), `</tr>` ~ // Fixed layout dummies
			`<tr class="post-header"><th colspan="2">` ~
				`<div class="post-time">`, summarizeTime(time), `</div>` ~
				`<a title="Permanent link to this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="permalink `, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr class="mini-post-info-cell">` ~
				`<td colspan="2">`
		); miniPostInfo(post, knownPosts); html.put(
				`</td>` ~
			`</tr>` ~
			`<tr>` ~
				`<td class="post-info">` ~
					`<div class="post-author">`), html.putEncodedEntities(author), html.put(`</div>`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 80);
		if (infoBits.length)
		{
			html.put(`<hr>`);
			foreach (b; infoBits)
				html.put(`<div class="post-info-bit">`, b, `</div>`);
		}
		else
			html.put(`<br>`);
		auto actions = getPostActions(post.msg);
		foreach (n; 0..actions.length)
			html.put(`<br>`); // guarantee space for the "toolbar"

		html.put(
					`<div class="post-actions">`), postActions(actions), html.put(`</div>` ~
				`</td>` ~
				`<td class="post-body">` ~
//		); miniPostInfo(post, knownPosts); html.put(
					`<pre class="post-text">`), formatBody(post), html.put(`</pre>`,
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td>` ~
			`</tr>` ~
			`</table>` ~
			`</div>`);

		if (post.children)
		{
			html.put(
				`<table class="post-nester"><tr>` ~
				`<td class="post-nester-bar" title="`, /* for IE */ repliesTitle, `">` ~
					`<a href="#`), html.putEncodedEntities(idToFragment(id)), html.put(`" ` ~
						`title="`, repliesTitle, `"></a>` ~
				`</td>` ~
				`<td>`);
			foreach (child; post.children)
				formatPost(child, knownPosts);
			html.put(`</td>` ~
				`</tr></table>`);
		}
	}

	if (post.rowid && markAsRead)
		user.setRead(post.rowid, true);
}

void miniPostInfo(Rfc850Post post, Rfc850Post[string] knownPosts, bool showActions = true)
{
	string horizontalInfo;
	string gravatarHash = getGravatarHash(post.authorEmail);
	auto parentLink = getParentLink(post, knownPosts);
	with (post.msg)
	{
		html.put(
			`<table class="mini-post-info"><tr>` ~
				`<td class="mini-post-info-avatar">`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 32);
		html.put(
				`</td>` ~
				`<td>` ~
					`Posted by <b>`), html.putEncodedEntities(author), html.put(`</b>`,
					parentLink ? `<br>in reply to ` ~ parentLink : null,
				`</td>`
		);
		if (showActions)
			html.put(
				`<td class="post-info-actions">`), postActions(getPostActions(post.msg)), html.put(`</td>`
			);
		html.put(
			`</tr></table>`
		);
	}
}

string postLink(int rowid, string id, string author)
{
	return
		`<a class="postlink ` ~ (user.isRead(rowid) ? "forum-read" : "forum-unread") ~ `" ` ~
			`href="`~ encodeHtmlEntities(idToUrl(id)) ~ `">` ~ encodeHtmlEntities(author) ~ `</a>`;
}

string postLink(PostInfo* info)
{
	return postLink(info.rowid, info.id, info.author);
}

struct InfoRow { string name, value; }

/// Alternative post formatting, with the meta-data header on top
void formatSplitPost(Rfc850Post post, bool footerNav)
{
	scope(success) user.setRead(post.rowid, true);

	InfoRow[] infoRows;
	string parentLink;

	infoRows ~= InfoRow("From", encodeHtmlEntities(post.author));
	//infoRows ~= InfoRow("Date", format("%s (%s)", formatLongTime(post.time), formatShortTime(post.time, false)));
	infoRows ~= InfoRow("Date", formatLongTime(post.time));

	if (post.parentID)
	{
		auto parent = post.parentID ? getPostInfo(post.parentID) : null;
		if (parent)
		{
			parentLink = postLink(parent.rowid, parent.id, parent.author);
			infoRows ~= InfoRow("In reply to", parentLink);
		}
	}

	string[] replies;
	foreach (int rowid, string id, string author; query!"SELECT `ROWID`, `ID`, `Author` FROM `Posts` WHERE ParentID = ?".iterate(post.id))
		replies ~= postLink(rowid, id, author);
	if (replies.length)
		infoRows ~= InfoRow("Replies", `<span class="avoid-wrap">` ~ replies.join(`,</span> <span class="avoid-wrap">`) ~ `</span>`);

	auto partList = formatPostParts(post);
	if (partList.length)
		infoRows ~= InfoRow("Attachments", partList.join(", "));

	string gravatarHash = getGravatarHash(post.authorEmail);

	with (post.msg)
	{
		html.put(
			`<div class="post-wrapper">` ~
			`<table class="split-post forum-table" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">` ~
			`<tr class="post-header"><th>` ~
				`<div class="post-time">`, summarizeTime(time), `</div>` ~
				`<a title="Permanent link to this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="`, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
					encodeHtmlEntities(rawSubject),
				`</a>` ~
			`</th></tr>` ~
			`<tr><td class="horizontal-post-info">` ~
				`<table><tr>` ~
					`<td class="post-info-avatar" rowspan="`, text(infoRows.length), `">`);
		putGravatar(gravatarHash, "http://www.gravatar.com/" ~ gravatarHash, `title="` ~ encodeHtmlEntities(author) ~ `'s Gravatar profile"`, 48);
		html.put(
					`</td>` ~
					`<td><table>`);
		foreach (a; infoRows)
			html.put(`<tr><td class="horizontal-post-info-name">`, a.name, `</td><td class="horizontal-post-info-value">`, a.value, `</td></tr>`);
		html.put(
					`</table></td>` ~
					`<td class="post-info-actions">`), postActions(getPostActions(post.msg)), html.put(`</td>` ~
				`</tr></table>` ~
			`</td></tr>` ~
			`<tr><td class="post-body">` ~
				`<table class="post-layout"><tr class="post-layout-header"><td>`);
		miniPostInfo(post, null);
		html.put(
				`</td></tr>` ~
				`<tr class="post-layout-body"><td>` ~
					`<pre class="post-text">`), formatBody(post), html.put(`</pre>`,
					(error ? `<span class="post-error">` ~ encodeHtmlEntities(error) ~ `</span>` : ``),
				`</td></tr>` ~
				`<tr class="post-layout-footer"><td>`
					); postFooter(footerNav, infoRows[1..$]); html.put(
				`</td></tr></table>` ~
			`</td></tr>` ~
			`</table>` ~
			`</div>`
		);
	}
}

void postFooter(bool footerNav, InfoRow[] infoRows)
{
	html.put(
		`<table class="post-footer"><tr>`,
			(footerNav ? `<td class="post-footer-nav"><a href="javascript:navPrev()">&laquo; Prev</a></td>` : null),
			`<td class="post-footer-info">`);
	foreach (a; infoRows)
		html.put(`<div><span class="horizontal-post-info-name">`, a.name, `</span>: <span class="horizontal-post-info-value">`, a.value, `</span></div>`);
	html.put(
			`</td>`,
			(footerNav ? `<td class="post-footer-nav"><a href="javascript:navNext()">Next &raquo;</a></td>` : null),
		`</tr></table>`
	);
}

void discussionSplitPost(string id)
{
	auto post = getPost(id);
	enforce(post, "Post not found");

	formatSplitPost(post, true);
}

void postPager(string threadID, int page, int postCount)
{
	pager(idToUrl(threadID, "thread"), page, getPageCount(postCount, POSTS_PER_PAGE));
}

int getPostCount(string threadID)
{
	foreach (int count; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?".iterate(threadID))
		return count;
	assert(0);
}

int getPostThreadIndex(string threadID, SysTime postTime)
{
	foreach (int index; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ? AND `Time` < ? ORDER BY `Time` ASC".iterate(threadID, postTime.stdTime))
		return index;
	assert(0);
}

int getPostThreadIndex(string postID)
{
	auto post = getPostInfo(postID);
	enforce(post, "No such post: " ~ postID);
	return getPostThreadIndex(post.threadID, post.time);
}

string getPostAtThreadIndex(string threadID, int index)
{
	foreach (string id; query!"SELECT `ID` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC LIMIT 1 OFFSET ?".iterate(threadID, index))
		return id;
	throw new NotFoundException(format("Post #%d of thread %s not found", index, threadID));
}

void discussionThread(string id, int page, out GroupInfo groupInfo, out string title, out string authorEmail, bool markAsRead)
{
	enforce(page >= 1, "Invalid page");

	auto postCount = getPostCount(id);

	if (page == 1 && postCount > 2)
	{
		// Expandable overview

		html.put(
			`<table id="thread-overview" class="forum-table forum-expand-container">` ~
			`<tr class="group-index-header"><th>`);

		auto pageCount = getPageCount(postCount, POSTS_PER_PAGE);
		if (pageCount > 1)
		{
			html.put(
				`<div class="thread-overview-pager forum-expand-container">` ~
				`Jump to page: <b>1</b> `
			);

			auto threadUrl = idToUrl(id, "thread");

			void pageLink(int n)
			{
				auto nStr = text(n);
				html.put(`<a href="`); html.putEncodedEntities(threadUrl); html.put(`?page=`, nStr, `">`, nStr, `</a> `);
			}

			if (pageCount < 4)
			{
				foreach (p; 2..pageCount+1)
					pageLink(p);
			}
			else
			{
				pageLink(2);
				html.put(`&hellip; `);
				pageLink(pageCount);

				html.put(
					`<a class="thread-overview-pager forum-expand-toggle">&nbsp;</a>` ~
					`<div class="thread-overview-pager-expanded forum-expand-content">` ~
					`<form action="`); html.putEncodedEntities(threadUrl); html.put(`">` ~
					`Page <input name="page" class="thread-overview-pager-pageno"> <input type="submit" value="Go">` ~
					`</form>` ~
					`</div>`
				);
			}

			html.put(
				`</div>`
			);
		}

		html.put(
			`<a class="forum-expand-toggle">Thread overview</a>` ~
			`</th></tr>`,
			`<tr class="forum-expand-content"><td class="group-threads-cell"><div class="group-threads"><table>`);
		formatThreadedPosts(getThreadPosts(id), false);
		html.put(`</table></div></td></tr></table>`);

	}

	Rfc850Post[] posts;
	foreach (int rowid, string postID, string message;
			query!"SELECT `ROWID`, `ID`, `Message` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC LIMIT ? OFFSET ?"
			.iterate(id, POSTS_PER_PAGE, (page-1)*POSTS_PER_PAGE))
		posts ~= new Rfc850Post(message, postID, rowid, id);

	Rfc850Post[string] knownPosts;
	foreach (post; posts)
		knownPosts[post.id] = post;

	enforce(posts.length, "Thread not found");

	groupInfo   = posts[0].getGroup();
	title       = posts[0].subject;
	authorEmail = posts[0].authorEmail;

	html.put(`<div id="thread-posts">`);
	foreach (post; posts)
		formatPost(post, knownPosts, markAsRead);
	html.put(`</div>`);

	if (page > 1 || postCount > POSTS_PER_PAGE)
	{
		html.put(`<table class="forum-table post-pager">`);
		postPager(id, page, postCount);
		html.put(`</table>`);
	}
}

PostInfo*[] getThreadPosts(string threadID)
{
	PostInfo*[] posts;
	enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `AuthorEmail`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?";
	foreach (int rowid, string id, string parent, string author, string authorEmail, string subject, long stdTime; query!ViewSQL.iterate(threadID))
		posts ~= [PostInfo(rowid, id, null, parent, author, authorEmail, subject, SysTime(stdTime, UTC()))].ptr;
	return posts;
}

void discussionThreadOverview(string threadID, string selectedID)
{
	enum PERF_SCOPE = "discussionThreadOverview"; mixin(MeasurePerformanceMixin);
	html.put(
		`<table id="thread-index" class="forum-table group-wrapper viewmode-`), html.putEncodedEntities(userSettings.groupViewMode), html.put(`">` ~
		`<tr class="group-index-header"><th><div>Thread overview</div></th></tr>`,
		`<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
	formatThreadedPosts(getThreadPosts(threadID), false, selectedID);
	html.put(`</table></div></td></tr></table>`);
}

void discussionSinglePost(string id, out GroupInfo groupInfo, out string title, out string authorEmail, out string threadID)
{
	auto post = getPost(id);
	enforce(post, "Post not found");
	groupInfo = post.getGroup();
	enforce(groupInfo, "Unknown group");
	title       = post.subject;
	authorEmail = post.authorEmail;
	threadID = post.cachedThreadID;

	formatSplitPost(post, false);
	discussionThreadOverview(threadID, id);
}

string discussionFirstUnread(string threadID)
{
	foreach (int rowid, string id; query!"SELECT `ROWID`, `ID` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC".iterate(threadID))
		if (!user.isRead(rowid))
			return idToUrl(id);
	return idToUrl(threadID, "thread", getPageCount(getPostCount(threadID), POSTS_PER_PAGE));
}

// ***********************************************************************

void createDraft(PostDraft draft)
{
	query!"INSERT INTO [Drafts] ([ID], [UserID], [Status], [ClientVars], [ServerVars], [Time]) VALUES (?, ?, ?, ?, ?, ?)"
		.exec(draft.clientVars["did"], userSettings.id, draft.status, draft.clientVars.toJson, draft.serverVars.toJson, Clock.currTime.stdTime);
}

// Handle backwards compatibility in stored drafts
UrlParameters jsonParseUrlParameters(string json)
{
	if (!json)
		return UrlParameters.init;
	try
		return jsonParse!UrlParameters(json);
	catch (Exception e)
	{
		static struct S { string[][string] items; }
		S s = jsonParse!S(json);
		return UrlParameters(s.items);
	}
}

PostDraft getDraft(string draftID)
{
	T parse(T)(string json) { return json ? json.jsonParse!T : T.init; }
	foreach (int status, string clientVars, string serverVars; query!"SELECT [Status], [ClientVars], [ServerVars] FROM [Drafts] WHERE [ID] == ?".iterate(draftID))
		return PostDraft(status, jsonParseUrlParameters(clientVars), parse!(string[string])(serverVars));
	throw new Exception("Can't find this message draft");
}

void saveDraft(PostDraft draft)
{
	auto draftID = draft.clientVars.get("did", null);
	auto postID = draft.serverVars.get("pid", null);
	query!"UPDATE [Drafts] SET [PostID]=?, [ClientVars]=?, [ServerVars]=?, [Time]=?, [Status]=? WHERE [ID] == ?"
		.exec(postID, draft.clientVars.toJson, draft.serverVars.toJson, Clock.currTime.stdTime, draft.status, draftID);
}

void autoSaveDraft(UrlParameters clientVars)
{
	auto draftID = clientVars.get("did", null);
	query!"UPDATE [Drafts] SET [ClientVars]=?, [Time]=?, [Status]=? WHERE [ID] == ?"
		.exec(clientVars.toJson, Clock.currTime.stdTime, PostDraft.Status.edited, draftID);
}

PostDraft newPostDraft(GroupInfo groupInfo, UrlParameters parameters = null)
{
	auto draftID = randomString();
	auto draft = PostDraft(PostDraft.Status.reserved, UrlParameters([
		"did" : draftID,
		"name" : userSettings.name,
		"email" : userSettings.email,
		"subject" : parameters.get("subject", null),
	]), [
		"where" : groupInfo.internalName,
	]);
	createDraft(draft);
	return draft;
}

PostDraft newReplyDraft(Rfc850Post post)
{
	auto postTemplate = post.replyTemplate();
	auto draftID = randomString();
	auto draft = PostDraft(PostDraft.Status.reserved, UrlParameters([
		"did" : draftID,
		"name" : userSettings.name,
		"email" : userSettings.email,
		"subject" : postTemplate.subject,
		"text" : postTemplate.content,
	]), [
		"where" : post.where,
		"parent" : post.id,
	]);
	createDraft(draft);
	return draft;
}

void draftNotices(string except = null)
{
	foreach (string id, long time; query!"SELECT [ID], [Time] FROM [Drafts] WHERE [UserID]==? AND [Status]==?".iterate(userSettings.id, PostDraft.Status.edited))
	{
		if (id == except)
			continue;
		auto t = SysTime(time, UTC());
		html.put(`<div class="forum-notice">You have an <a href="/posting/`, id, `">unsent draft message from `, formatShortTime(t, false), `</a>.</div>`);
	}
}

bool discussionPostForm(PostDraft draft, bool showCaptcha=false, PostError error=PostError.init)
{
	auto draftID = draft.clientVars.get("did", null);
	draftNotices(draftID);

	// Immediately resurrect discarded posts when user clicks "Undo" or "Back"
	if (draft.status == PostDraft.Status.discarded)
		query!"UPDATE [Drafts] SET [Status]=? WHERE [ID]=?".exec(PostDraft.Status.edited, draftID);

	auto where = draft.serverVars.get("where", null);
	auto info = getGroupInfo(where);
	if (!info)
		throw new Exception("Unknown group " ~ where);
	if (info.postMessage)
	{
		html.put(
			`<table class="forum-table forum-error">` ~
				`<tr><th>Can't post to archive</th></tr>` ~
				`<tr><td class="forum-table-message">`
					, info.postMessage,
				`</td></tr>` ~
			`</table>`);
		return false;
	}
	if (info.sinkType == "smtp" && info.subscriptionRequired)
	{
		auto config = loadIni!SmtpConfig("config/sources/smtp/" ~ info.sinkName ~ ".ini");
		html.put(`<div class="forum-notice">Note: you are posting to a mailing list.<br>` ~
			`Your message will not go through unless you ` ~
			`<a href="`), html.putEncodedEntities(config.listInfo), html.putEncodedEntities(info.internalName), html.put(`">subscribe to the mailing list</a> first.<br>` ~
			`You must then use the same email address when posting here as the one you used to subscribe to the list.<br>` ~
			`If you do not want to receive mailing list mail, you can disable mail delivery at the above link.</div>`);
	}

	auto parent = draft.serverVars.get("parent", null);
	auto parentInfo	= parent ? getPostInfo(parent) : null;
	if (parentInfo && Clock.currTime - parentInfo.time > 2.weeks)
		html.put(`<div class="forum-notice">Warning: the post you are replying to is from `,
			formatDuration(Clock.currTime - parentInfo.time), ` (`, formatShortTime(parentInfo.time, false), `).</div>`);

	html.put(`<form action="/send" method="post" class="forum-form post-form" id="postform">`);

	if (error.message)
		html.put(`<div class="form-error">`), html.putEncodedEntities(error.message), html.put(error.extraHTML, `</div>`);
	html.put(draft.clientVars.get("html-top", null));

	if (parent)
		html.put(`<input type="hidden" name="parent" value="`), html.putEncodedEntities(parent), html.put(`">`);
	else
		html.put(`<input type="hidden" name="where" value="`), html.putEncodedEntities(where), html.put(`">`);

	auto subject = draft.clientVars.get("subject", null);

	html.put(
		`<div id="postform-info">` ~
			`Posting to <b>`), html.putEncodedEntities(info.publicName), html.put(`</b>`,
			(parent
				? parentInfo
					? ` in reply to ` ~ postLink(parentInfo)
					: ` in reply to (unknown post)`
				: info
					? `:<br>(<b>` ~ encodeHtmlEntities(info.description) ~ `</b>)`
					: ``),
		`</div>` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`<input type="hidden" name="did" value="`), html.putEncodedEntities(draftID), html.put(`">` ~
		`<label for="postform-name">Your name:</label>` ~
		`<input id="postform-name" name="name" size="40" value="`), html.putEncodedEntities(draft.clientVars.get("name", null)), html.put(`">` ~
		`<label for="postform-email">Your email address (<a href="/help#email">?</a>):</label>` ~
		`<input id="postform-email" type="email" name="email" size="40" value="`), html.putEncodedEntities(draft.clientVars.get("email", null)), html.put(`">` ~
		`<label for="postform-subject">Subject:</label>` ~
		`<input id="postform-subject" name="subject" size="80"`, subject.length ? `` : ` autofocus`, ` value="`), html.putEncodedEntities(subject), html.put(`">` ~
		`<label for="postform-text">Message:</label>` ~
		`<textarea id="postform-text" name="text" rows="25" cols="80"`, subject.length ? ` autofocus` : ``, `>`), html.putEncodedEntities(draft.clientVars.get("text", null)), html.put(`</textarea>`);

	if (showCaptcha)
		html.put(`<div id="postform-captcha">`, theCaptcha.getChallengeHtml(error.captchaError), `</div>`);

	html.put(
		`<div>` ~
			`<div class="postform-action-left">` ~
				`<input name="action-send" type="submit" value="Send">` ~
				`<input name="action-save" type="submit" value="Save and preview">` ~
			`</div>` ~
			`<div class="postform-action-right">` ~
				`<input name="action-discard" type="submit" value="Discard draft">` ~
			`</div>` ~
			`<div style="clear:right"></div>` ~
		`</div>` ~
	`</form>`);
	return true;
}

SysTime[][string] lastPostAttempts;

// Reject posts if the threshold of post attempts is met under the
// given time limit.
enum postThrottleRejectTime = 30.seconds;
enum postThrottleRejectCount = 3;

// Challenge posters with a CAPTCHA if the threshold of post attempts
// is met under the given time limit.
enum postThrottleCaptchaTime = 3.minutes;
enum postThrottleCaptchaCount = 3;

string discussionSend(UrlParameters clientVars, Headers headers)
{
	auto draftID = clientVars.get("did", null);
	auto draft = getDraft(draftID);

	try
	{
		if (draft.status == PostDraft.Status.sent)
		{
			// Redirect if we know where to
			if ("pid" in draft.serverVars)
				return idToUrl(PostProcess.pidToMessageID(draft.serverVars["pid"]));
			else
				throw new Exception("This message has already been sent.");
		}

		if (clientVars.get("secret", "") != userSettings.secret)
			throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

		draft.clientVars = clientVars;
		draft.status = PostDraft.Status.edited;
		scope(exit) saveDraft(draft);

		auto action = clientVars.byKey.filter!(key => key.startsWith("action-")).chain("action-none".only).front[7..$];

		bool lintDetails;
		if (action.startsWith("lint-ignore-"))
		{
			draft.serverVars[action] = null;
			action = "send";
		}
		else
		if (action.startsWith("lint-fix-"))
		{
			auto ruleID = action[9..$];
			try
			{
				draft.serverVars["lint-undo"] = draft.clientVars.get("text", null);
				getLintRule(ruleID).fix(draft);
				draft.clientVars["html-top"] = `<div class="forum-notice">Automatic fix applied. ` ~
					`<input name="action-lint-undo" type="submit" value="Undo"></div>`;
			}
			catch (Exception e)
			{
				draft.serverVars["lint-ignore-" ~ ruleID] = null;
				html.put(`<div class="forum-notice">Sorry, a problem occurred while attempting to fix your post ` ~
					`(`), html.putEncodedEntities(e.msg), html.put(`).</div>`);
			}
			discussionPostForm(draft);
			return null;
		}
		else
		if (action == "lint-undo")
		{
			enforce("lint-undo" in draft.serverVars, "No undo information..?");
			draft.clientVars["text"] = draft.serverVars["lint-undo"];
			draft.serverVars.remove("lint-undo");
			html.put(`<div class="forum-notice">Automatic fix undone.</div>`);
			discussionPostForm(draft);
			return null;
		}
		else
		if (action == "lint-explain")
		{
			lintDetails = true;
			action = "send";
		}

		switch (action)
		{
			case "save":
			{
				discussionPostForm(draft);
				// Show preview
				auto parent = "parent" in draft.serverVars ? getPost(draft.serverVars["parent"]) : null;
				auto post = PostProcess.createPost(draft, headers, ip, parent);
				formatPost(post, null);
				return null;
			}
			case "send":
			{
				userSettings.name  = aaGet(clientVars, "name");
				userSettings.email = aaGet(clientVars, "email");

				foreach (rule; lintRules)
					if ("lint-ignore-" ~ rule.id !in draft.serverVars && rule.check(draft))
					{
						PostError error;
						error.message = "Warning: " ~ rule.shortDescription();
						error.extraHTML ~= ` <input name="action-lint-ignore-` ~ rule.id ~ `" type="submit" value="Ignore">`;
						if (!lintDetails)
							error.extraHTML ~= ` <input name="action-lint-explain" type="submit" value="Explain">`;
						if (rule.canFix(draft))
							error.extraHTML ~= ` <input name="action-lint-fix-` ~ rule.id ~ `" type="submit" value="Fix it for me">`;
						if (lintDetails)
							error.extraHTML ~= `<div class="lint-description">` ~ rule.longDescription() ~ `</div>`;
						discussionPostForm(draft, false, error);
						return null;
					}

				auto now = Clock.currTime();

				auto ipPostAttempts = lastPostAttempts.get(ip, null);
				if (ipPostAttempts.length >= postThrottleRejectCount && now - ipPostAttempts[$-postThrottleRejectCount+1] < postThrottleRejectTime)
				{
					discussionPostForm(draft, false,
						PostError("You've attempted to post %d times in the past %s. Please wait a little bit before trying again."
							.format(postThrottleRejectCount, postThrottleRejectTime)));
					return null;
				}

				bool captchaPresent = theCaptcha.isPresent(clientVars);
				if (!captchaPresent)
				{
					if (ipPostAttempts.length >= postThrottleCaptchaCount && now - ipPostAttempts[$-postThrottleCaptchaCount+1] < postThrottleCaptchaTime)
					{
						discussionPostForm(draft, true,
							PostError("You've attempted to post %d times in the past %s. Please solve a CAPTCHA to continue."
								.format(postThrottleCaptchaCount, postThrottleCaptchaTime)));
						return null;
					}
				}

				auto parent = "parent" in draft.serverVars ? getPost(draft.serverVars["parent"]) : null;
				auto process = new PostProcess(draft, user, userSettings.id, ip, headers, parent);
				if (process.status == PostingStatus.redirect)
					return "/posting/" ~ process.pid;
				process.run();
				lastPostAttempts[ip] ~= Clock.currTime();
				draft.serverVars["pid"] = process.pid;

				if (user.isLoggedIn())
					createReplySubscription(user.getName());

				return "/posting/" ~ process.pid;
			}
			case "discard":
			{
				// Show undo notice
				userSettings.pendingNotice = "draft-deleted:" ~ draftID;
				// Mark as deleted
				draft.status = PostDraft.Status.discarded;
				// Redirect to relevant page
				if ("parent" in draft.serverVars)
					return idToUrl(draft.serverVars["parent"]);
				else
				if ("where" in draft.serverVars)
					return "/group/" ~ draft.serverVars["where"];
				else
					return "/";
			}
			default:
				throw new Exception("Unknown action");
		}
	}
	catch (Exception e)
	{
		auto error = isDebug ? e.toString() : e.msg;
		discussionPostForm(draft, false, PostError(error));
		return null;
	}
}

void discussionPostStatusMessage(string messageHtml)
{
	html.put(
		`<table class="forum-table">` ~
			`<tr><th>Posting status</th></tr>` ~
			`<tr><td class="forum-table-message">`, messageHtml, `</th></tr>` ~
		`</table>`);
}

void discussionPostStatus(PostProcess process, out bool refresh, out string redirectTo, out bool form)
{
	refresh = form = false;
	PostError error = process.error;
	switch (process.status)
	{
		case PostingStatus.spamCheck:
			//discussionPostStatusMessage("Checking for spam...");
			discussionPostStatusMessage("Validating...");
			refresh = true;
			return;
		case PostingStatus.captcha:
			discussionPostStatusMessage("Verifying reCAPTCHA...");
			refresh = true;
			return;
		case PostingStatus.connecting:
			discussionPostStatusMessage("Connecting to server...");
			refresh = true;
			return;
		case PostingStatus.posting:
			discussionPostStatusMessage("Sending message to server...");
			refresh = true;
			return;
		case PostingStatus.waiting:
			discussionPostStatusMessage("Message sent.<br>Waiting for message announcement...");
			refresh = true;
			return;

		case PostingStatus.posted:
			redirectTo = idToUrl(process.post.id);
			discussionPostStatusMessage(`Message posted! Redirecting...`);
			refresh = true;
			return;

		case PostingStatus.captchaFailed:
			discussionPostForm(process.draft, true, error);
			form = true;
			return;
		case PostingStatus.spamCheckFailed:
			error.message = format("%s. Please solve a CAPTCHA to continue.", error.message);
			discussionPostForm(process.draft, true, error);
			form = true;
			return;
		case PostingStatus.serverError:
			discussionPostForm(process.draft, false, error);
			form = true;
			return;

		default:
			discussionPostStatusMessage("???");
			refresh = true;
			return;
	}
}

// ***********************************************************************

string findPostingLog(string id)
{
	if (id.match(`^<[a-z]{20}@` ~ vhost.escapeRE() ~ `>`))
	{
		auto post = id[1..21];
		version (Windows)
			auto logs = dirEntries("logs", "*PostProcess-" ~ post ~ ".log", SpanMode.depth).array;
		else
		{
			import std.process;
			auto result = execute(["find", "logs/", "-name", "*PostProcess-" ~ post ~ ".log"]); // This is MUCH faster than dirEntries.
			enforce(result.status == 0, "find error");
			auto logs = splitLines(result.output);
		}
		if (logs.length == 1)
			return logs[0];
	}
	return null;
}

void discussionDeleteForm(Rfc850Post post)
{
	html.put(
		`<form action="/dodelete" method="post" class="forum-form delete-form" id="deleteform">` ~
		`<input type="hidden" name="id" value="`), html.putEncodedEntities(post.id), html.put(`">` ~
		`<div id="deleteform-info">` ~
			`Are you sure you want to delete this post from DFeed's database?` ~
		`</div>` ~
		`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
		`<textarea id="deleteform-message" readonly="readonly" rows="25" cols="80">`), html.putEncodedEntities(post.message), html.put(`</textarea><br>` ~
		`Reason: <input name="reason" value="spam"></input><br>`,
		 findPostingLog(post.id)
			? `<input type="checkbox" name="ban" value="Yes" id="deleteform-ban"></input><label for="deleteform-ban">Also ban the poster from accessing the forum</label><br>`
			: ``,
		`<input type="submit" value="Delete"></input>` ~
	`</form>`);
}

void deletePost(UrlParameters vars)
{
	if (vars.get("secret", "") != userSettings.secret)
		throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

	string messageID = vars.get("id", "");
	string userName = user.getName();
	string reason = vars.get("reason", "");
	bool ban = vars.get("ban", "No") == "Yes";

	deletePostImpl(messageID, reason, userName, ban, (string s) { html.put(s ~ "<br>"); });
}

void deletePostApi(string group, int artNum)
{
	string messageID;
	foreach (string id; query!"SELECT [ID] FROM [Groups] WHERE [Group] = ? AND [ArtNum] = ?".iterate(group, artNum))
		messageID = id;
	enforce(messageID, "No such article in this group");

	string reason = "API call";
	string userName = "API";
	bool ban = false;

	deletePostImpl(messageID, reason, userName, ban, (string s) { html.put(s ~ "\n"); });
}

void deletePostImpl(string messageID, string reason, string userName, bool ban, void delegate(string) feedback)
{
	auto post = getPost(messageID);
	enforce(post, "Post not found");

	auto deletionLog = new FileLogger("Deleted");
	scope(exit) deletionLog.close();
	scope(failure) deletionLog("An error occurred");
	deletionLog("User %s is deleting post %s (%s)".format(userName, post.id, reason));
	foreach (line; post.message.splitAsciiLines())
		deletionLog("> " ~ line);

	foreach (string[string] values; query!"SELECT * FROM `Posts` WHERE `ID` = ?".iterate(post.id))
		deletionLog("[Posts] row: " ~ values.toJson());
	foreach (string[string] values; query!"SELECT * FROM `Threads` WHERE `ID` = ?".iterate(post.id))
		deletionLog("[Threads] row: " ~ values.toJson());

	if (ban)
	{
		banPoster(userName, post.id, reason);
		deletionLog("User was banned for this post.");
		feedback("User banned.<br>");
	}

	query!"DELETE FROM `Posts` WHERE `ID` = ?".exec(post.id);
	query!"DELETE FROM `Threads` WHERE `ID` = ?".exec(post.id);

	dbVersion++;
	feedback("Post deleted.");
}

// Create logger on demand, to avoid creating empty log files
Logger banLog;
void needBanLog() { if (!banLog) banLog = new FileLogger("Banned"); }

void banPoster(string who, string id, string reason)
{
	needBanLog();
	banLog("User %s is banning poster of post %s (%s)".format(who, id, reason));
	auto fn = findPostingLog(id);
	enforce(fn && fn.exists, "Can't find posting log");

	auto pp = new PostProcess(fn);
	string[] keys;
	keys ~= pp.ip;
	keys ~= pp.draft.clientVars.get("secret", null);
	foreach (cookie; pp.headers.get("Cookie", null).split("; "))
	{
		auto p = cookie.indexOf("=");
		if (p<0) continue;
		auto name = cookie[0..p];
		auto value = cookie[p+1..$];
		if (name == "dfeed_secret" || name == "dfeed_session")
			keys ~= value;
	}

	foreach (key; keys)
		if (key.length)
		{
			if (key in banned)
				banLog("Key already known: " ~ key);
			else
			{
				banned[key] = reason;
				banLog("Adding key: " ~ key);
			}
		}

	saveBanList();
	banLog("Done.");
}

enum banListFileName = "data/banned.txt";

void loadBanList()
{
	if (banListFileName.exists())
		foreach (string line; splitAsciiLines(cast(string)read(banListFileName)))
		{
			auto parts = line.split("\t");
			if (parts.length >= 2)
				banned[parts[0]] = parts[1..$].join("\t");
		}
}

void saveBanList()
{
	const inProgressFileName = banListFileName ~ ".inprogress";
	auto f = File(inProgressFileName, "wb");
	foreach (key, reason; banned)
		f.writefln("%s\t%s", key, reason);
	f.close();
	rename(inProgressFileName, banListFileName);
}

/// Returns true if the user is banned.
bool banCheck(string ip, HttpRequest request)
{
	string[] keys = [ip];
	foreach (cookie; request.headers.get("Cookie", null).split("; "))
	{
		auto p = cookie.indexOf("=");
		if (p<0) continue;
		auto name = cookie[0..p];
		auto value = cookie[p+1..$];
		if (name == "dfeed_secret" || name == "dfeed_session")
			if (value.length)
				keys ~= value;
	}
	string secret = userSettings.secret;
	if (secret.length)
		keys ~= secret;

	string bannedKey = null, reason = null;
	foreach (key; keys)
		if (key in banned)
		{
			bannedKey = key;
			reason = banned[key];
			break;
		}

	if (!bannedKey)
		return false;

	needBanLog();
	banLog("Request from banned user: " ~ request.resource);
	foreach (name, value; request.headers)
		banLog("* %s: %s".format(name, value));

	banLog("Matched on: %s (%s)".format(bannedKey, reason));
	bool propagated;
	foreach (key; keys)
		if (key !in banned)
		{
			banLog("Propagating: %s -> %s".format(bannedKey, key));
			banned[key] = "%s (propagated from %s)".format(reason, bannedKey);
			propagated = true;
		}

	if (propagated)
		saveBanList();

	return true;
}

void discussionFlagPage(Rfc850Post post, bool flag, UrlParameters postParams)
{
	static immutable string[2] actions = ["unflag", "flag"];
	bool isFlagged = query!`SELECT COUNT(*) FROM [Flags] WHERE [Username]=? AND [PostID]=?`.iterate(user.getName(), post.id).selectValue!int > 0;
	if (postParams == UrlParameters.init)
	{
		if (flag == isFlagged)
		{
		html.put(
			`<div id="flagform-info" class="forum-notice">` ~
				`It looks like you've already ` ~ actions[flag] ~ `ged this post. ` ~
				`Would you like to <a href="`), html.putEncodedEntities(idToUrl(post.id, actions[!flag])), html.put(`">` ~ actions[!flag] ~ ` it</a>?` ~
			`</div>`);
		}
		else
		{
			html.put(
				`<div id="flagform-info" class="forum-notice">` ~
					`Are you sure you want to ` ~ actions[flag] ~ ` this post?` ~
				`</div>`);
			formatPost(post, null, false);
			html.put(
				`<form action="" method="post" class="forum-form flag-form" id="flagform">` ~
					`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
					`<input type="submit" name="flag" value="` ~ actions[flag].capitalize ~ `"></input>` ~
					`<input type="submit" name="cancel" value="Cancel"></input>` ~
				`</form>`);
		}
	}
	else
	{
		enforce(postParams.get("secret", "") == userSettings.secret, "XSRF secret verification failed. Are your cookies enabled?");
		enforce(user.getLevel() >= User.Level.canFlag, "You can't flag posts!");
		enforce(user.createdAt() < post.time, "You can't flag this post!");

		if ("flag" in postParams)
		{
			enforce(flag != isFlagged, "You've already " ~ actions[flag] ~ "ged this post.");

			if (flag)
				query!`INSERT INTO [Flags] ([PostID], [Username], [Date]) VALUES (?, ?, ?)`.exec(post.id, user.getName(), Clock.currTime.stdTime);
			else
				query!`DELETE FROM [Flags] WHERE [PostID]=? AND [Username]=?`.exec(post.id, user.getName());

			html.put(
				`<div id="flagform-info" class="forum-notice">` ~
					`Post ` ~ actions[flag] ~ `ged.` ~
				`</div>` ~
				`<form action="" method="post" class="forum-form flag-form" id="flagform">` ~
					`<input type="hidden" name="secret" value="`, userSettings.secret, `">` ~
					`<input type="submit" name="cancel" value="Return to post"></input>` ~
				`</form>`);
		}
		else
			throw new Redirect(idToUrl(post.id));
	}
}

// ***********************************************************************

void discussionLoginForm(UrlParameters parameters, string errorMessage = null)
{

	html.put(`<form action="/login" method="post" id="loginform" class="forum-form loginform">` ~
		`<table class="forum-table">` ~
			`<tr><th>Log in</th></tr>` ~
			`<tr><td class="loginform-cell">`);

	if ("url" in parameters)
		html.put(`<input type="hidden" name="url" value="`), html.putEncodedEntities(parameters["url"]), html.put(`">`);

	html.put(
			`<label for="loginform-username">Username:</label>` ~
			`<input id="loginform-username" name="username" value="`), html.putEncodedEntities(parameters.get("username", "")), html.put(`" autofocus>` ~
			`<label for="loginform-password">Password:</label>` ~
			`<input id="loginform-password" type="password" name="password" value="`), html.putEncodedEntities(parameters.get("password", "")), html.put(`">` ~
			`<input id="loginform-remember" type="checkbox" name="remember" `, "username" !in  parameters || "remember" in parameters ? ` checked` : ``, `>` ~
			`<label for="loginform-remember"> Remember me</label>` ~
			`<input type="submit" value="Log in">` ~
		`</td></tr>`);
	if (errorMessage)
		html.put(`<tr><td class="loginform-info"><div class="form-error loginform-error">`), html.putEncodedEntities(errorMessage), html.put(`</div></td></tr>`);
	else
		html.put(
			`<tr><td class="loginform-info">` ~
				`<a href="/registerform`,
					("url" in parameters ? `?url=` ~ encodeUrlParameter(parameters["url"]) : ``),
					`">Register</a> to keep your preferences<br>and read post history on the server.` ~
			`</td></tr>`);
	html.put(`</table></form>`);
}

void discussionLogin(UrlParameters parameters)
{
	user.logIn(aaGet(parameters, "username"), aaGet(parameters, "password"), !!("remember" in parameters));
}

void discussionRegisterForm(UrlParameters parameters, string errorMessage = null)
{
	html.put(`<form action="/register" method="post" id="registerform" class="forum-form loginform">` ~
		`<table class="forum-table">` ~
			`<tr><th>Register</th></tr>` ~
			`<tr><td class="loginform-cell">`);

	if ("url" in parameters)
		html.put(`<input type="hidden" name="url" value="`), html.putEncodedEntities(parameters["url"]), html.put(`">`);

	html.put(
		`<label for="loginform-username">Username:</label>` ~
		`<input id="loginform-username" name="username" value="`), html.putEncodedEntities(parameters.get("username", "")), html.put(`" autofocus>` ~
		`<label for="loginform-password">Password:</label>` ~
		`<input id="loginform-password" type="password" name="password" value="`), html.putEncodedEntities(parameters.get("password", "")), html.put(`">` ~
		`<label for="loginform-password2">Confirm:</label>` ~
		`<input id="loginform-password2" type="password" name="password2" value="`), html.putEncodedEntities(parameters.get("password2", "")), html.put(`">` ~
		`<input id="loginform-remember" type="checkbox" name="remember" `, "username" !in  parameters || "remember" in parameters ? ` checked` : ``, `>` ~
		`<label for="loginform-remember"> Remember me</label>` ~
		`<input type="submit" value="Register">` ~
		`</td></tr>`);
	if (errorMessage)
		html.put(`<tr><td class="loginform-info"><div class="form-error loginform-error">`), html.putEncodedEntities(errorMessage), html.put(`</div></td></tr>`);
	else
		html.put(
			`<tr><td class="loginform-info">` ~
				`Please pick your password carefully.<br>There are no password recovery options.` ~
			`</td></tr>`);
	html.put(`</table></form>`);
}

void discussionRegister(UrlParameters parameters)
{
	enforce(aaGet(parameters, "password") == aaGet(parameters, "password2"), "Passwords do not match");
	user.register(aaGet(parameters, "username"), aaGet(parameters, "password"), !!("remember" in parameters));
}

// ***********************************************************************

struct UserSettings
{
	static SettingType[string] settingTypes;

	template userSetting(string name, string defaultValue, SettingType settingType)
	{
		@property string userSetting() { return user.get(name, defaultValue, settingType); }
		@property string userSetting(string newValue) { user.set(name, newValue, settingType); return newValue; }
		static this() { settingTypes[name] = settingType; }
	}

	template randomUserString(string name, SettingType settingType)
	{
		@property string randomUserString()
		{
			auto value = user.get(name, null, settingType);
			if (value is null)
			{
				value = randomString();
				user.set(name, value, settingType);
			}
			return value;
		}
	}

	/// Posting details. Remembered when posting messages.
	alias name = userSetting!("name", null, SettingType.server);
	alias email = userSetting!("email", null, SettingType.server); /// ditto

	/// View mode. Can be changed in the settings.
	alias groupViewMode = userSetting!("groupviewmode", "basic", SettingType.client);

	/// Enable or disable keyboard hotkeys. Can be changed in the settings.
	alias enableKeyNav = userSetting!("enable-keynav", "true", SettingType.client);

	/// Whether messages are opened automatically after being focused
	/// (message follows focus). Can be changed in the settings.
	alias autoOpen = userSetting!("auto-open", "false", SettingType.client);

	/// Any pending notices that should be shown on the next page shown.
	alias pendingNotice = userSetting!("pending-notice", null, SettingType.session);

	/// Session management
	alias previousSession = userSetting!("previous-session", "0", SettingType.server);
	alias currentSession  = userSetting!("current-session" , "0", SettingType.server);  /// ditto
	alias sessionCanary   = userSetting!("session-canary"  , "0", SettingType.session); /// ditto

	/// A unique ID used to recognize both logged-in and anonymous users.
	alias id = randomUserString!("id", SettingType.server);

	/// Secret token used for CSRF protection.
	/// Visible in URLs.
	alias secret = randomUserString!("secret", SettingType.server);

	void set(string name, string value)
	{
		user.set(name, value, settingTypes.aaGet(name));
	}
}
UserSettings userSettings;

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
				pager("?q=" ~ searchString, page, n > postsPerPage ? int.max : page);
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
	string feedUrl = "http://" ~ vhost ~ "/feed" ~
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
	string feedUrl = "http://" ~ vhost ~ "/subscription-feed/" ~ subscriptionID;

	CachedResource getFeed()
	{
		auto subscription = getSubscription(subscriptionID);
		auto title = "%s subscription (%s)".format(vhost, subscription.trigger.getTextDescription());
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

// **************************************************************************

struct ListenConfig
{
	string addr;
	ushort port = 80;
}

struct Config
{
	ListenConfig listen;
	string staticDomain = null;
	string apiSecret = null;
	bool indexable = false;
}
const Config config;

import ae.utils.sini;
shared static this() { config = loadIni!Config("config/web.ini"); }

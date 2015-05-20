/*  Copyright (C) 2011, 2012, 2013, 2014, 2015  Vladimir Panteleev <vladimir@thecybershadow.net>
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

import std.file;
import std.path;
import std.string;
import std.conv;
import std.exception;
import std.array, std.algorithm;
import std.datetime;
import std.regex;
import std.stdio;

alias std.string.indexOf indexOf;

import ae.net.asockets;
import ae.net.http.caching;
import ae.net.http.responseex;
import ae.net.http.server;
import ae.net.ietf.headers;
import ae.net.ietf.wrap;
import ae.net.shutdown;
import ae.sys.log;
import ae.utils.array;
import ae.utils.feed;
import ae.utils.json;
import ae.utils.meta;
import ae.utils.text;
import ae.utils.textout;
import ae.utils.time;
import ae.utils.xmllite : putEncodedEntities;

import cache;
import captcha;
import common;
import database;
import groups;
import list;
//import mailhide;
import message;
import posting;
import site;
import user;

version = MeasurePerformance;

class WebUI
{
	Logger log;
	version(MeasurePerformance) Logger perfLog;
	HttpServer server;
	string vhost;
	User user;
	string ip;
	StringBuffer html;
	string[string] banned;

	this()
	{
		log = createLogger("Web");
		version(MeasurePerformance) perfLog = createLogger("Performance");

		loadBanList();

		vhost = site.config.host;

		server = new HttpServer();
		server.log = log;
		server.handleRequest = &onRequest;
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
		return "/static/" ~ text(timeLastModified("web/static" ~ path).stdTime) ~ path;
	}

	string optimizedPath(string base, string resource)
	{
	    string optimizedResource = resource.stripExtension ~ ".min" ~ resource.extension;
		auto origPath = base ~ resource;
		auto optiPath = base ~ optimizedResource;
		if (exists(origPath) && exists(optiPath) && timeLastModified(optiPath) >= timeLastModified(origPath))
			return optimizedResource;
		else
			return resource;
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
		auto response = new HttpResponseEx();

		ip = request.remoteHosts(conn.remoteAddress.toAddrString())[0];
		user = getUser("Cookie" in request.headers ? request.headers["Cookie"] : null);
		string[] cookies;
		scope(success)
		{
			if (!cookies)
				cookies = user.save();
			foreach (cookie; cookies)
				response.headers.add("Set-Cookie", cookie);
		}

		string title, breadcrumb1, breadcrumb2;
		string bodyClass = "narrowdoc";
		string returnPage = request.resource;
		html.clear();
		string[] tools, extraHeaders, extraScripts;
		auto status = HttpStatusCode.OK;

		// Redirect to canonical domain name
		auto host = request.headers.get("Host", "");
		host = request.headers.get("X-Forwarded-Host", host);
		if (host != vhost && host != "localhost" && ip != "127.0.0.1")
			return response.redirect("http://" ~ vhost ~ request.resource, HttpStatusCode.MovedPermanently);

		extraScripts ~=
			`<script src="` ~ staticPath("/js/dfeed.js") ~ `"></script>`;

		auto canonicalHeader =
			`<link rel="canonical" href="http://`~vhost~request.resource~`"/>`;

		try
		{
			if (banCheck(ip, request))
				return response.writeError(HttpStatusCode.Forbidden, "You're banned!");

			auto pathStr = request.resource;
			enforce(pathStr.startsWith('/'), "Invalid path");
			string[string] parameters;
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
					breadcrumb1 = `<a href="/">Forum Index</a>`;
					foreach (what; ["posts", "threads"])
						extraHeaders ~= `<link rel="alternate" type="application/atom+xml" title="New `~what~`" href="/feed/`~what~`" />`;
					discussionIndex();
					break;
				case "group":
				{
					enforce(path.length > 1, "No group specified");
					string group = path[1];
					int page = to!int(parameters.get("page", "1"));
					string pageStr = page==1 ? "" : format(" (page %d)", page);
					title = group ~ " index" ~ pageStr;
					breadcrumb1 = `<a href="/group/`~encodeEntities(group)~`">` ~ encodeEntities(group) ~ `</a>` ~ pageStr;
					auto viewMode = user.get("groupviewmode", "basic");
					if (viewMode == "basic")
						discussionGroup(group, page);
					else
					if (viewMode == "threaded")
						discussionGroupThreaded(group, page);
					else
						discussionGroupSplit(group, page);
					//tools ~= viewModeTool(["basic", "threaded"], "group");
					tools ~= viewModeTool(["basic", "threaded", "horizontal-split"], "group");
					foreach (what; ["posts", "threads"])
						extraHeaders ~= `<link rel="alternate" type="application/atom+xml" title="New `~what~` on `~encodeEntities(group)~`" href="/feed/`~what~`/`~encodeEntities(group)~`" />`;
					break;
				}
				case "thread":
				{
					enforce(path.length > 1, "No thread specified");
					int page = to!int(parameters.get("page", "1"));
					string threadID = '<' ~ urlDecode(pathX) ~ '>';

					auto firstPostUrl = idToUrl(getPostAtThreadIndex(threadID, getPageOffset(page, POSTS_PER_PAGE)));
					auto viewMode = user.get("groupviewmode", "basic");
					if (viewMode != "basic")
						html.put(`<div class="forum-notice">Viewing thread in basic view mode &ndash; click a post's title to open it in `, encodeEntities(viewMode), ` view mode</div>`);
					returnPage = firstPostUrl;

					string pageStr = page==1 ? "" : format(" (page %d)", page);
					string group, subject;
					discussionThread(threadID, page, group, subject);
					title = subject ~ pageStr;
					breadcrumb1 = `<a href="/group/` ~encodeEntities(group)~`">` ~ encodeEntities(group  ) ~ `</a>`;
					breadcrumb2 = `<a href="/thread/`~encodeEntities(pathX)~`">` ~ encodeEntities(subject) ~ `</a>` ~ pageStr;
					//tools ~= viewModeTool(["flat", "nested"], "thread");
					tools ~= viewModeTool(["basic", "threaded", "horizontal-split"], "group");
					extraHeaders ~= canonicalHeader; // Google confuses /post/ URLs with threads
					break;
				}
				case "post":
					enforce(path.length > 1, "No post specified");
					if (user.get("groupviewmode", "basic") == "basic")
						return response.redirect(resolvePostUrl('<' ~ urlDecode(pathX) ~ '>'));
					else
					if (user.get("groupviewmode", "basic") == "threaded")
					{
						string group, subject;
						discussionSinglePost('<' ~ urlDecode(pathX) ~ '>', group, subject);
						title = subject;
						breadcrumb1 = `<a href="/group/` ~encodeEntities(group)~`">` ~ encodeEntities(group  ) ~ `</a>`;
						breadcrumb2 = `<a href="/thread/`~encodeEntities(pathX)~`">` ~ encodeEntities(subject) ~ `</a> (view single post)`;
						tools ~= viewModeTool(["basic", "threaded", "horizontal-split"], "group");
						break;
					}
					else
					{
						string group;
						int page;
						discussionGroupSplitFromPost('<' ~ urlDecode(pathX) ~ '>', group, page);

						string pageStr = page==1 ? "" : format(" (page %d)", page);
						title = group ~ " index" ~ pageStr;
						breadcrumb1 = `<a href="/group/`~encodeEntities(group)~`">` ~ encodeEntities(group) ~ `</a>` ~ pageStr;
						tools ~= viewModeTool(["basic", "threaded", "horizontal-split"], "group");

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
				case "set":
				{
					if (parameters.get("secret", "") != getUserSecret())
						throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

					foreach (name, value; parameters)
						if (name != "url" && name != "secret")
							user[name] = value; // TODO: is this a good idea?

					if ("url" in parameters)
						return response.redirect(parameters["url"]);
					else
						return response.serveText("OK");
				}
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
					string group = path[1];
					title = "Posting to " ~ group;
					breadcrumb1 = `<a href="/group/`~encodeEntities(group)~`">` ~ encodeEntities(group) ~ `</a>`;
					breadcrumb2 = `<a href="/newpost/`~encodeEntities(group)~`">New thread</a>`;
					if (discussionPostForm(Rfc850Post.newPostTemplate(group)))
						bodyClass ~= " formdoc";
					break;
				}
				case "reply":
				{
					enforce(path.length > 1, "No post specified");
					auto post = getPost('<' ~ urlDecode(pathX) ~ '>');
					enforce(post, "Post not found");
					title = `Replying to "` ~ post.subject ~ `"`; // "
					breadcrumb1 = `<a href="` ~ encodeEntities(idToUrl(post.id)) ~ `">` ~ encodeEntities(post.subject) ~ `</a>`;
					breadcrumb2 = `<a href="/reply/`~pathX~`">Post reply</a>`;
					if (discussionPostForm(post.replyTemplate()))
						bodyClass = "formdoc";
					break;
				}
				case "send":
				{
					auto postVars = request.decodePostData();
					auto process = discussionSend(postVars, cast(string[string])request.headers);
					if (process)
						return response.redirect("/poststatus/" ~ process.pid);

					title = breadcrumb1 = `Posting error`;
					bodyClass ~= " formdoc";
					break;
				}
				case "poststatus":
				{
					enforce(path.length > 1, "No PID specified");
					auto pid = pathX;
					enforce(pid in postProcesses, "Sorry, this is not a post I know of.");

					bool refresh, form;
					string redirectTo;
					discussionPostStatus(postProcesses[pid], refresh, redirectTo, form);
					if (refresh)
						response.setRefresh(1, redirectTo);
					if (form)
					{
						title = breadcrumb1 = `Posting error`;
						bodyClass ~= " formdoc";
					}
					else
						title = breadcrumb1 = `Posting status`;
					break;
				}
				case "delete":
				{
					enforce(user.getLevel() >= User.Level.canDeletePosts, "You can't delete posts");
					enforce(path.length > 1, "No post specified");
					auto post = getPost('<' ~ urlDecode(pathX) ~ '>');
					enforce(post, "Post not found");
					title = `Delete "` ~ post.subject ~ `"?`; // "
					breadcrumb1 = `<a href="` ~ encodeEntities(idToUrl(post.id)) ~ `">` ~ encodeEntities(post.subject) ~ `</a>`;
					breadcrumb2 = `<a href="/delete/`~pathX~`">Delete post</a>`;
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
				case "loginform":
				{
					discussionLoginForm(parameters);
					title = breadcrumb1 = `Log in`;
					tools ~= `<a href="/registerform?url=__URL__">Register</a>`;
					returnPage = "/";
					break;
				}
				case "registerform":
				{
					discussionRegisterForm(parameters);
					title = breadcrumb1 = `Registration`;
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
						if ("url" in parameters)
							return response.redirect(parameters["url"]);
						else
							return response.serveText("OK");
					}
					catch (Exception e)
					{
						discussionLoginForm(parameters, e.msg);
						title = breadcrumb1 = `Login error`;
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
						if ("url" in parameters)
							return response.redirect(parameters["url"]);
						else
							return response.serveText("OK");
					}
					catch (Exception e)
					{
						discussionRegisterForm(parameters, e.msg);
						title = breadcrumb1 = `Registration error`;
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
				case "help":
					title = breadcrumb1 = "Help";
					html.put(readText(optimizedPath(null, "web/help.htt")));
					break;

				// dlang.org front page iframes
				case "frame-discussions":
					bodyClass = "frame";
					title = breadcrumb1 = "Forum activity summary";
					discussionFrameDiscussions();
					break;
				case "frame-announcements":
					bodyClass = "frame";
					title = breadcrumb1 = "Forum activity summary";
					discussionFrameAnnouncements();
					break;

				case "feed":
				{
					enforce(path.length > 1, "Feed type not specified");
					enforce(path[1]=="posts" || path[1]=="threads", "Unknown feed type");
					bool threadsOnly = path[1] == "threads";
					string group;
					if (path.length > 2)
						group = path[2];
					auto hours = to!int(parameters.get("hours", text(FEED_HOURS_DEFAULT)));
					enforce(hours <= FEED_HOURS_MAX, "hours parameter exceeds limit");
					return getFeed(group, threadsOnly, hours).getResponse(request);
				}

				case "js":
				case "css":
				case "images":
				case "files":
				case "ircstats":
				case "favicon.ico":
				case "robots.txt":
					return serveFile(response, pathStr[1..$]);

				case "static":
					enforce(path.length > 2);
					return serveFile(response, path[2..$].join("/"));

				default:
					return response.writeError(HttpStatusCode.NotFound);
			}
		}
		catch (Exception e)
		{
			//return response.writeError(HttpStatusCode.InternalServerError, "Unprocessed exception: " ~ e.msg);
			if (cast(NotFoundException) e)
			{
				breadcrumb1 = title = "Not Found";
				status = HttpStatusCode.NotFound;
			}
			else
			{
				breadcrumb1 = title = "Error";
				status = HttpStatusCode.InternalServerError;
			}
			auto text = encodeEntities(e.msg).replace("\n", "<br>");
			debug text ~= `<pre>` ~ encodeEntities(e.toString()) ~ `</pre>`;
			html.clear();
			html.put(
				`<table class="forum-table forum-error">`
					`<tr><th>`, encodeEntities(title), `</th></tr>`
					`<tr><td class="forum-table-message">`, text, `</td></tr>`
				`</table>`);
		}

		assert(title, "No title");
		assert(html.length, "No HTML");
		if (breadcrumb1) breadcrumb1 = "&rsaquo; " ~ breadcrumb1;
		if (breadcrumb2) breadcrumb2 = "&raquo; " ~ breadcrumb2;

		if (user.isLoggedIn())
			tools ~= `<a href="/logout?url=__URL__">Log out ` ~ encodeEntities(user.getName()) ~ `</a>`;
		else
			tools ~= `<a href="/loginform?url=__URL__">Log in</a>`;
		tools ~= `<a href="/help">Help</a>`;

		string toolStr = tools.join(" &middot; ");
		toolStr =
			toolStr.replace("__URL__",  encodeUrlParameter(returnPage)) ~
			`<script type="text/javascript">var toolsTemplate = ` ~ toJson(toolStr) ~ `;</script>`;
		toolStr =
			`<div id="forum-tools-left"></div>`
			`<div id="forum-tools-right">` ~ toolStr ~ `</div>`
			`<div style="clear: both"></div>`;
		string htmlStr = cast(string) html.get(); // html contents will be overwritten on next request

		cookies = user.save();
		foreach (cookie; cookies)
			if (cookie.length > 4096 * 15/16)
			{
				htmlStr =
					`<div class="forum-notice">Warning: cookie size approaching RFC 2109 limit.`
					`Please consider <a href="/registerform">creating an account</a> to avoid losing your read post history.</div>` ~ htmlStr;
				break;
			}

		string getVar(string name)
		{
			switch (name)
			{
				case "title"        : return encodeEntities(title);
				case "content"      : return htmlStr;
				case "breadcrumb1"  : return breadcrumb1;
				case "breadcrumb2"  : return breadcrumb2;
				case "extraheaders" : return extraHeaders.join("\n");
				case "extrascripts" : return extraScripts.join("\n");
				case "bodyclass"    : return bodyClass;
				case "tools"        : return toolStr;
				default:
					if (name.startsWith("static:"))
						return staticPath(name[7..$]);
					throw new Exception("Unknown variable in template: " ~ name);
			}
		}

		response.disableCache();

		auto page = readText(optimizedPath(null, "web/skel.htt"));
		//scope(failure) std.file.write("bad-tpl.html", page);
		page = renderNav(page);
		page = parseTemplate(page, &getVar);
		response.serveData(page);

		response.setStatus(status);
		return response;
	}

	string renderNav(string html)
	{
		auto nav = inferList(html, [["<?category1?>"], ["<?category2?>"]]);
		auto nav2 = inferList(nav.itemSuffix, [["<?url1?>", "<?title1?>"], ["<?url2?>", "<?title2?>"]]);
		nav.itemSuffix = null; nav.varPrefix ~= null;

		return nav.render(groupHierarchy.map!(set =>
			[set.shortName, nav2.render(set.groups.map!(group =>
				["/group/" ~ group.name, group.name]
			).array)]
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
				foreach (string id; query!"SELECT `ID` FROM `Groups` WHERE `Group`=? ORDER BY `Time` DESC LIMIT 1".iterate(group.name))
					lastPosts[group.name] = id;
		return lastPosts;
	}

	Cached!(int[string]) threadCountCache, postCountCache;
	Cached!(string[string]) lastPostCache;

	void discussionIndex()
	{
		auto threadCounts = threadCountCache(getThreadCounts());
		auto postCounts = postCountCache(getPostCounts());
		auto lastPosts = lastPostCache(getLastPosts());

		string summarizePost(string postID)
		{
			auto info = getPostInfo(postID);
			if (info)
				with (*info)
					return
						`<div class="truncated"><a class="forum-postsummary-subject ` ~ (user.isRead(rowid) ? "forum-read" : "forum-unread") ~ `" href="` ~ encodeEntities(idToUrl(id)) ~ `" title="` ~ encodeEntities(subject) ~ `">` ~ encodeEntities(subject) ~ `</a></div>` ~
						`<div class="truncated">by <span class="forum-postsummary-author" title="` ~ encodeEntities(author) ~ `">` ~ encodeEntities(author) ~ `</span></div>` ~
						`<span class="forum-postsummary-time">` ~ summarizeTime(time) ~ `</span>`;

			return `<div class="forum-no-data">-</div>`;
		}

		html.put(`<table id="forum-index" class="forum-table">`);
		html.put(`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(5), `</tr>`); // Fixed layout dummies
		foreach (set; groupHierarchy)
		{
			html.put(
				`<tr><th colspan="5">`), html.putEncodedEntities(set.name), html.put(`</th></tr>`
				`<tr class="subheader"><th>Forum</th><th>Last Post</th><th>Threads</th><th>Posts</th><th>Also via</th></tr>`);
			foreach (group; set.groups)
			{
				html.put(
					`<tr class="group-row">`
						`<td class="forum-index-col-forum">`
							`<a href="/group/`), html.putEncodedEntities(group.name), html.put(`">`), html.putEncodedEntities(group.name), html.put(`</a>`
							`<div class="truncated forum-index-description" title="`), html.putEncodedEntities(group.description), html.put(`">`), html.putEncodedEntities(group.description), html.put(`</div>`
						`</td>`
						`<td class="forum-index-col-lastpost">`, group.name in lastPosts    ? summarizePost(   lastPosts[group.name]) : `<div class="forum-no-data">-</div>`, `</td>`
						`<td class="number-column">`,            group.name in threadCounts ? formatNumber (threadCounts[group.name]) : `-`, `</td>`
						`<td class="number-column">`,            group.name in postCounts   ? formatNumber (  postCounts[group.name]) : `-`, `</td>`
						`<td class="number-column">`);
				foreach (i, av; group.alsoVia.values)
					html.put(i ? `<br>` : ``, `<a href="`, av.url, `">`, av.name, `</a>`);
				html.put(`</td>`
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
		foreach (string group, string firstPostID; query!"SELECT [Group], [Threads].[ID] FROM [Threads] INNER JOIN (SELECT [ID] FROM [Posts] WHERE [ID]=[ThreadID] ORDER BY [Time] DESC LIMIT 100) AS [ThreadPosts] ON [ThreadPosts].[ID]==[Threads].[ID] LIMIT 100".iterate())
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

	CachedSet!(string, string) authorEmailCache;

	string getAuthorEmail(string id)
	{
		foreach (int rowid, string postID, string message; query!"SELECT `ROWID`, `ID`, `Message` FROM `Posts` WHERE `ID` = ?".iterate(id))
			return new Rfc850Post(message, postID, rowid, id).authorEmail;
		return null;
	}

	void summarizeFrameThread(PostInfo* info, string infoText)
	{
		if (info)
			with (*info)
			{
				html.put(
					`<a target="_top" class="forum-postsummary-gravatar" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`">`
						`<img alt="Gravatar" class="post-gravatar" src="http://www.gravatar.com/avatar/`, getGravatarHash(authorEmailCache(id, getAuthorEmail(id))), `?d=identicon">`
					`</a>`
					`<a target="_top" class="forum-postsummary-subject `, (user.isRead(rowid) ? "forum-read" : "forum-unread"), `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`">`), html.putEncodedEntities(subject), html.put(`</a><br>`
					`<div class="forum-postsummary-info">`, infoText, `</div>`
					`by <span class="forum-postsummary-author">`), html.putEncodedEntities(author), html.put(`</span>`
				);
				return;
			}

		html.put(`<div class="forum-no-data">-</div>`);
	}

	void discussionFrameAnnouncements()
	{
		auto latestAnnouncements = latestAnnouncementsCache(getLatestAnnouncements());

		html.put(`<table class="forum-table"><thead><tr><th>`
			`<a target="_top" class="feed-icon" title="Subscribe" href="/feed/threads/digitalmars.D.announce"><img src="`, staticPath("/images/rss.png"),`"></img></a>`
			`<a target="_top" href="/group/digitalmars.D.announce">Latest announcements</a>`
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

	void newPostButton(string group)
	{
		html.put(
			`<form name="new-post-form" method="get" action="/newpost/`), html.putEncodedEntities(group), html.put(`">`
				`<div class="header-tools">`
					`<input class="btn" type="submit" value="Create thread">`
					`<input class="img" type="image" src="`, staticPath("/images/newthread.png"), `" alt="Create thread">`
				`</div>`
			`</form>`);
	}

	void pager(string base, int page, int pageCount, int maxWidth = 50)
	{
		string linkOrNot(string text, int page, bool cond)
		{
			if (cond)
				return `<a href="` ~ encodeEntities(base) ~ `?page=` ~ .text(page) ~ `">` ~ text ~ `</a>`;
			else
				return `<span class="disabled-link">` ~ text ~ `</span>`;
		}

		// Try to make the pager as wide as it will fit in the alotted space

		int widthAt(int radius)
		{
			import std.math : log10;

			int pagerStart = max(1, page - radius);
			int pagerEnd = min(pageCount, page + radius);

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
			`<tr class="pager"><th colspan="3">`
				`<div class="pager-left">`,
					linkOrNot("&laquo; First", 1, page!=1),
					`&nbsp;&nbsp;&nbsp;`,
					linkOrNot("&lsaquo; Prev", page-1, page>1),
				`</div>`
				`<div class="pager-right">`,
					linkOrNot("Next &rsaquo;", page+1, page<pageCount),
					`&nbsp;&nbsp;&nbsp;`,
					linkOrNot("Last &raquo; ", pageCount, page!=pageCount),
				`</div>`
				`<div class="pager-numbers">`, pager.join(` `), `</div>`
			`</th></tr>`);
	}

	enum THREADS_PER_PAGE = 15;
	enum POSTS_PER_PAGE = 10;

	static int indexToPage(int index, int perPage)  { return index / perPage + 1; } // Return value is 1-based, index is 0-based
	static int getPageCount(int count, int perPage) { return indexToPage(count-1, perPage); }
	static int getPageOffset(int page, int perPage) { return (page-1) * perPage; }

	void threadPager(string group, int page, int maxWidth = 40)
	{
		auto threadCounts = threadCountCache(getThreadCounts());
		enforce(group in threadCounts, "Empty or unknown group");
		auto threadCount = threadCounts[group];
		auto pageCount = getPageCount(threadCount, THREADS_PER_PAGE);

		pager(`/group/` ~ group, page, pageCount, maxWidth);
	}

	void discussionGroup(string group, int page)
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

		foreach (string firstPostID, string lastPostID; query!"SELECT `ID`, `LastPost` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(group, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
			foreach (int count; query!"SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?".iterate(firstPostID))
				threads ~= Thread(firstPostID, getPostInfo(firstPostID), getPostInfo(lastPostID), count, getUnreadPostCount(firstPostID));

		void summarizeThread(string tid, PostInfo* info, bool isRead)
		{
			if (info)
				with (*info)
				{
					html.put(
					//	`<!-- Thread ID: ` ~ encodeEntities(threadID) ~ ` | First Post ID: ` ~ encodeEntities(id) ~ `-->` ~
						`<div class="truncated"><a class="forum-postsummary-subject `, (isRead ? "forum-read" : "forum-unread"), `" href="`), html.putEncodedEntities(idToUrl(tid, "thread")), html.put(`" title="`), html.putEncodedEntities(subject), html.put(`">`), html.putEncodedEntities(subject), html.put(`</a></div>`
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
						`<a class="forum-postsummary-time `, user.isRead(rowid) ? "forum-read" : "forum-unread", `" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`">`, summarizeTime(time), `</a>`
						`<div class="truncated">by <span class="forum-postsummary-author" title="`), html.putEncodedEntities(author), html.put(`">`), html.putEncodedEntities(author), html.put(`</span></div>`);
					return;
				}
			html.put(`<div class="forum-no-data">-</div>`);
		}

		void summarizePostCount(ref Thread thread)
		{
			if (thread.unreadPostCount == 0)
				html ~= formatNumber(thread.postCount-1);
			else
			if (thread.unreadPostCount == thread.postCount)
				html.put(`<b>`, formatNumber(thread.postCount-1), `</b>`);
			else
				html.put(
					`<b>`, formatNumber(thread.postCount-1), `</b>`
					`<br>(<a href="`, idToUrl(thread.id, "first-unread"), `">`, formatNumber(thread.unreadPostCount), ` new</a>)`);
		}

		html.put(
			`<table id="group-index" class="forum-table">`
			`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(3), `</tr>` // Fixed layout dummies
			`<tr class="group-index-header"><th colspan="3"><div class="header-with-tools">`), newPostButton(group), html.putEncodedEntities(group), html.put(`</div></th></tr>`
			`<tr class="subheader"><th>Thread / Thread Starter</th><th>Last Post</th><th>Replies</th>`);
		foreach (thread; threads)
			html.put(
				`<tr class="thread-row">`
					`<td class="group-index-col-first">`), summarizeThread(thread.id, thread.firstPost, thread.isRead), html.put(`</td>`
					`<td class="group-index-col-last">`), summarizeLastPost(thread.lastPost), html.put(`</td>`
					`<td class="number-column">`), summarizePostCount(thread), html.put(`</td>`
				`</tr>`);
		threadPager(group, page);
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
		enum OFFSET_WIDTH = 30f;
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

		bool reversed = user.get("groupviewmode", "basic") == "threaded";
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
					`<tr class="thread-post-row`, (post.info && post.info.id==selectedID ? ` focused selected` : ``), `">`
						`<td>`
							`<div style="padding-left: `, format("%1.1f", OFFSET_INIT + level * offsetIncrement), OFFSET_UNITS, `">`
								`<div class="thread-post-time">`, summarizeTime(post.info.time, true), `</div>`,
								`<a class="postlink `, (user.isRead(post.info.rowid) ? "forum-read" : "forum-unread" ), `" href="`), html.putEncodedEntities(idToUrl(post.info.id)), html.put(`">`, truncateString(post.info.author, narrow ? 17 : 50), `</a>`
							`</div>`
						`</td>`
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
						`<tr><td style="padding-left: `, offsetStr, `">`
						`<table class="thread-start">`
							`<tr><th>`), html.putEncodedEntities(post.subject), html.put(`</th></tr>`);
                    formatPost(post, 0);
					html.put(
						`</table>`
						`</td></tr>`);
				}
				else
					formatPost(post, level);
			}
		}

		formatPosts(posts[null].children, 0, null, true);
	}

	void discussionGroupThreaded(string group, int page, bool narrow = false)
	{
		enforce(page >= 1, "Invalid page");

		//foreach (string threadID; query!"SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?".iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
		//	foreach (string id, string parent, string author, string subject, long stdTime; query!"SELECT `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?".iterate(threadID))
		PostInfo*[] posts;
		enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` IN (SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?)";
		foreach (int rowid, string id, string parent, string author, string subject, long stdTime; query!ViewSQL.iterate(group, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
			posts ~= [PostInfo(rowid, id, null, parent, author, subject, SysTime(stdTime, UTC()))].ptr; // TODO: optimize?

		html.put(
			`<table id="group-index-threaded" class="forum-table group-wrapper viewmode-`), html.putEncodedEntities(user.get("groupviewmode", "basic")), html.put(`">`
			`<tr class="group-index-header"><th><div>`), newPostButton(group), html.putEncodedEntities(group), html.put(`</div></th></tr>`,
		//	`<tr class="group-index-captions"><th>Subject / Author</th><th>Time</th>`,
			`<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
		formatThreadedPosts(posts, narrow);
		html.put(`</table></div></td></tr>`);
		threadPager(group, page, narrow ? 25 : 50);
		html.put(`</table>`);
	}

	void discussionGroupSplit(string group, int page)
	{
		html.put(
			`<table id="group-split"><tr>`
			`<td id="group-split-list"><div>`);
		discussionGroupThreaded(group, page, true);
		html.put(
			`</div></td>`
			`<td id="group-split-message" class="group-split-message-none">`
				`Loading...`
				`<div class="nojs">Sorry, this view requires JavaScript.</div>`
			`</td>`
			`</tr></table>`);
	}

	void discussionGroupSplitFromPost(string id, out string group, out int page)
	{
		auto post = getPost(id);
		enforce(post, "Post not found");

		group = post.getGroup();
		page = getThreadPage(group, post.cachedThreadID);

		discussionGroupSplit(group, page);
	}

	int getThreadPage(string group, string thread)
	{
		int page = 0;

		foreach (long time; query!"SELECT `LastUpdated` FROM `Threads` WHERE `ID` = ? LIMIT 1".iterate(thread))
			foreach (int threadIndex; query!"SELECT COUNT(*) FROM `Threads` WHERE `Group` = ? AND `LastUpdated` > ? ORDER BY `LastUpdated` DESC".iterate(group, time))
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
								`<a href="` ~ encodeEntities(partUrl) ~ `" title="` ~ encodeEntities(mimeType) ~ `">` ~
								encodeEntities(name) ~
								(name && fileName ? " - " : "") ~
								encodeEntities(fileName) ~
								`</a>` ~
								(description ? ` (` ~ encodeEntities(description) ~ `)` : "")
							:
								`<a href="` ~ encodeEntities(partUrl) ~ `">` ~
								encodeEntities(mimeType) ~
								`</a> part` ~
								(description ? ` (` ~ encodeEntities(description) ~ `)` : "");
				}
			}
		}
		visitParts(post.parts, null);
		return partList;
	}

	string getGravatarHash(string email)
	{
		import std.digest.md;
		import std.ascii : LetterCase;
		return email.toLower().strip().md5Of().toHexString!(LetterCase.lower)().idup; // Issue 9279
	}

	string getUserSecret()
	{
		if ("secret" !in user)
			user["secret"] = randomString();
		return user["secret"];
	}

	enum maxPostActions = 3;

	void postActions(Rfc850Message msg)
	{
		auto id = msg.id;
		if (user.get("groupviewmode", "basic") == "basic")
			html.put(
				`<a class="actionlink permalink" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" `
					`title="Canonical link to this post. See &quot;Canonical links&quot; on the Help page for more information.">`
					`<img src="`, staticPath("/images/link.png"), `">Permalink`
				`</a>`);
		if (true)
			html.put(
				`<a class="actionlink replylink" href="`), html.putEncodedEntities(idToUrl(id, "reply")), html.put(`">`
					`<img src="`, staticPath("/images/reply.png"), `">Reply`
				`</a>`);
/*
		if (mailHide)
			html.put(
				`<a class="actionlink emaillink" href="`, mailHide.getUrl(msg.authorEmail), `" `
					`title="Solve a CAPTCHA to obtain this poster's email address.">`
					`<img src="`, staticPath("/images/email.png"), `">Email`
				`</a>`);
*/
		if (user.getLevel() >= User.Level.hasRawLink)
			html.put(
				`<a class="actionlink sourcelink" href="`), html.putEncodedEntities(idToUrl(id, "source")), html.put(`">`
					`<img src="`, staticPath("/images/source.png"), `">Source`
				`</a>`);
		if (user.getLevel() >= User.Level.canDeletePosts)
			html.put(
				`<a class="actionlink deletelink" href="`), html.putEncodedEntities(idToUrl(id, "delete")), html.put(`">`
					`<img src="`, staticPath("/images/delete.png"), `">Delete`
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
				return `<a href="` ~ encodeEntities(link) ~ `">` ~ encodeEntities(author) ~ `</a>`;
		}

		return null;
	}

	void formatPost(Rfc850Post post, Rfc850Post[string] knownPosts)
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
				`<a href="` ~ encodeEntities(idToThreadUrl(post.id, post.cachedThreadID)) ~ `">View in thread</a>`;

		string repliesTitle = `Replies to `~encodeEntities(post.author)~`'s post from `~encodeEntities(formatShortTime(post.time, false));

		with (post.msg)
		{
			html.put(
				`<div class="post-wrapper">`
				`<table class="post forum-table`, (post.children ? ` with-children` : ``), `" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">`
				`<tr class="table-fixed-dummy">`, `<td></td>`.replicate(2), `</tr>` // Fixed layout dummies
				`<tr class="post-header"><th colspan="2">`
					`<div class="post-time">`, summarizeTime(time), `</div>`
					`<a title="Permanent link to this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="`, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
						encodeEntities(rawSubject),
					`</a>`
				`</th></tr>`
				`<tr class="mini-post-info-cell">`
					`<td colspan="2">`
			); miniPostInfo(post, knownPosts); html.put(
					`</td>`
				`</tr>`
				`<tr>`
					`<td class="post-info">`
						`<div class="post-author">`), html.putEncodedEntities(author), html.put(`</div>`
						`<a href="http://www.gravatar.com/`, gravatarHash, `" title="`), html.putEncodedEntities(author), html.put(`'s Gravatar profile">`
							`<img alt="Gravatar" class="post-gravatar" width="80" height="80" src="http://www.gravatar.com/avatar/`, gravatarHash, `?d=identicon">`
						`</a><br>`);
			if (infoBits.length)
			{
				html.put(`<hr>`);
				foreach (b; infoBits)
					html.put(`<div class="post-info-bit">`, b, `</div>`);
			}
			else
				html.put(`<br>`);
			foreach (n; 0..maxPostActions)
				html.put(`<br>`); // guarantee space for the "toolbar"

			html.put(
						`<div class="post-actions">`), postActions(post.msg), html.put(`</div>`
					`</td>`
					`<td class="post-body">`
	//		); miniPostInfo(post, knownPosts); html.put(
						`<pre class="post-text">`), formatBody(post), html.put(`</pre>`,
						(error ? `<span class="post-error">` ~ encodeEntities(error) ~ `</span>` : ``),
					`</td>`
				`</tr>`
				`</table>`
				`</div>`);

			if (post.children)
			{
				html.put(
					`<table class="post-nester"><tr>`
					`<td class="post-nester-bar" title="`, /* for IE */ repliesTitle, `">`
						`<a href="#`), html.putEncodedEntities(idToFragment(id)), html.put(`" `
							`title="`, repliesTitle, `"></a>`
					`</td>`
					`<td>`);
				foreach (child; post.children)
					formatPost(child, knownPosts);
				html.put(`</td>`
					`</tr></table>`);
			}
		}

		user.setRead(post.rowid, true);
	}

	void miniPostInfo(Rfc850Post post, Rfc850Post[string] knownPosts)
	{
		string horizontalInfo;
		string gravatarHash = getGravatarHash(post.authorEmail);
		auto parentLink = getParentLink(post, knownPosts);
		with (post.msg)
		{
			html.put(
				`<table class="mini-post-info"><tr>`
					`<td class="mini-post-info-avatar">`
						`<a href="http://www.gravatar.com/`, gravatarHash, `" title="`), html.putEncodedEntities(author), html.put(`'s Gravatar profile">`
							`<img alt="Gravatar" class="post-gravatar" width="32" height="32" src="http://www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&s=32">`
						`</a>`
					`</td>`
					`<td>`
						`Posted by <b>`), html.putEncodedEntities(author), html.put(`</b>`,
						parentLink ? `<br>in reply to ` ~ parentLink : null,
					`</td>`
					`<td class="post-info-actions">`); postActions(post.msg); html.put(`</td>`
				`</tr></table>`
			);	
		}
	}

	string postLink(int rowid, string id, string author)
	{
		return
			`<a class="postlink ` ~ (user.isRead(rowid) ? "forum-read" : "forum-unread") ~ `" ` ~
				`href="`~ encodeEntities(idToUrl(id)) ~ `">` ~ encodeEntities(author) ~ `</a>`;
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

		infoRows ~= InfoRow("From", post.author);
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
				`<div class="post-wrapper">`
				`<table class="split-post forum-table" id="`), html.putEncodedEntities(idToFragment(id)), html.put(`">`
				`<tr class="post-header"><th>`
					`<div class="post-time">`, summarizeTime(time), `</div>`
					`<a title="Permanent link to this post" href="`), html.putEncodedEntities(idToUrl(id)), html.put(`" class="`, (user.isRead(post.rowid) ? "forum-read" : "forum-unread"), `">`,
						encodeEntities(rawSubject),
					`</a>`
				`</th></tr>`
				`<tr><td class="horizontal-post-info">`
					`<table><tr>`
						`<td class="post-info-avatar" rowspan="`, text(infoRows.length), `">`
							`<a href="http://www.gravatar.com/`, gravatarHash, `" title="`), html.putEncodedEntities(author), html.put(`'s Gravatar profile">`
								`<img alt="Gravatar" class="post-gravatar" width="48" height="48" src="http://www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&s=48">`
							`</a>`
						`</td>`
						`<td><table>`);
			foreach (a; infoRows)
				html.put(`<tr><td class="horizontal-post-info-name">`, a.name, `</td><td class="horizontal-post-info-value">`, a.value, `</td></tr>`);
			html.put(
						`</table></td>`
						`<td class="post-info-actions">`), postActions(post.msg), html.put(`</td>`
					`</tr></table>`
				`</td></tr>`
				`<tr><td class="post-body">`
					`<table class="post-layout"><tr class="post-layout-header"><td>`);
			miniPostInfo(post, null);
			html.put(
					`</td></tr>`
					`<tr class="post-layout-body"><td>`
						`<pre class="post-text">`), formatBody(post), html.put(`</pre>`,
						(error ? `<span class="post-error">` ~ encodeEntities(error) ~ `</span>` : ``),
					`</td></tr>`
					`<tr class="post-layout-footer"><td>`
						); postFooter(footerNav, infoRows[1..$]); html.put(
					`</td></tr></table>`
				`</td></tr>`
				`</table>`
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

	void discussionThread(string id, int page, out string group, out string title)
	{
		auto viewMode = user.get("threadviewmode", "flat"); // legacy
		bool nested = viewMode == "nested" || viewMode == "threaded";

		enforce(page >= 1, "Invalid page");
		auto postsPerPage = nested ? int.max : POSTS_PER_PAGE;
		if (nested) page = 1;

		Rfc850Post[] posts;
		foreach (int rowid, string postID, string message; query!"SELECT `ROWID`, `ID`, `Message` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC LIMIT ? OFFSET ?".iterate(id, postsPerPage, (page-1)*postsPerPage))
			posts ~= new Rfc850Post(message, postID, rowid, id);

		Rfc850Post[string] knownPosts;
		foreach (post; posts)
			knownPosts[post.id] = post;

		enforce(posts.length, "Thread not found");

		group = posts[0].getGroup();
		title = posts[0].subject;

		if (nested)
			posts = Rfc850Post.threadify(posts);

		foreach (post; posts)
			formatPost(post, knownPosts);

		if (!nested)
		{
			auto postCount = getPostCount(id);

			if (page > 1 || postCount > POSTS_PER_PAGE)
			{
				html.put(`<table class="forum-table post-pager">`);
				postPager(id, page, postCount);
				html.put(`</table>`);
			}
		}
	}

	void discussionThreadOverview(string threadID, string selectedID)
	{
		PostInfo*[] posts;
		enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?";
		foreach (int rowid, string id, string parent, string author, string subject, long stdTime; query!ViewSQL.iterate(threadID))
			posts ~= [PostInfo(rowid, id, null, parent, author, subject, SysTime(stdTime, UTC()))].ptr;

		html.put(
			`<table id="thread-index" class="forum-table group-wrapper viewmode-`), html.putEncodedEntities(user.get("groupviewmode", "basic")), html.put(`">`
			`<tr class="group-index-header"><th><div>Thread overview</div></th></tr>`,
			`<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
		formatThreadedPosts(posts, false, selectedID);
		html.put(`</table></div></td></tr></table>`);
	}

	void discussionSinglePost(string id, out string group, out string title)
	{
		auto post = getPost(id);
		enforce(post, "Post not found");
		group = post.getGroup();
		title = post.subject;

		formatSplitPost(post, false);
		discussionThreadOverview(post.cachedThreadID, id);
	}

	string discussionFirstUnread(string threadID)
	{
		foreach (int rowid, string id; query!"SELECT `ROWID`, `ID` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC".iterate(threadID))
			if (!user.isRead(rowid))
				return idToUrl(id);
		return idToUrl(threadID, "thread", getPageCount(getPostCount(threadID), POSTS_PER_PAGE));
	}

	// ***********************************************************************

	bool discussionPostForm(Rfc850Post postTemplate, bool showCaptcha=false, PostError error=PostError.init)
	{
		auto info = getGroupInfo(postTemplate.xref[0].group);
		if (!info)
			throw new Exception("Unknown group");
		if (info.postMessage)
		{
			html.put(
				`<table class="forum-table forum-error">`
					`<tr><th>Can't post to archive</th></tr>`
					`<tr><td class="forum-table-message">`
						~ info.postMessage.replace("%NAME%", info.name) ~
					`</td></tr>`
				`</table>`);
			return false;
		}

		html.put(`<form action="/send" method="post" class="forum-form post-form" id="postform">`);

		if (error.message)
			html.put(`<div class="form-error">`), html.putEncodedEntities(error.message), html.put(`</div>`);

		if (postTemplate.reply)
			html.put(`<input type="hidden" name="parent" value="`), html.putEncodedEntities(postTemplate.parentID), html.put(`">`);
		else
			html.put(`<input type="hidden" name="where" value="`), html.putEncodedEntities(postTemplate.where), html.put(`">`);

		html.put(
			`<div id="postform-info">`
				`Posting to <b>`), html.putEncodedEntities(postTemplate.where), html.put(`</b>`,
				(postTemplate.reply
					? ` in reply to ` ~ postLink(getPostInfo(postTemplate.parentID))
					: getGroupInfo(postTemplate.where)
						? `:<br>(<b>` ~ encodeEntities(getGroupInfo(postTemplate.where).description) ~ `</b>)`
						: ``),
			`</div>`
			`<input type="hidden" name="secret" value="`, getUserSecret(), `">`
			`<label for="postform-name">Your name:</label>`
			`<input id="postform-name" name="name" size="40" value="`), html.putEncodedEntities(user.get("name", "")), html.put(`">`
			`<label for="postform-email">Your email address (<a href="/help#email">?</a>):</label>`
			`<input id="postform-email" name="email" size="40" value="`), html.putEncodedEntities(user.get("email", "")), html.put(`">`
			`<label for="postform-subject">Subject:</label>`
			`<input id="postform-subject" name="subject" size="80" value="`), html.putEncodedEntities(postTemplate.subject), html.put(`">`
			`<label for="postform-text">Message:</label>`
			`<textarea id="postform-text" name="text" rows="25" cols="80" autofocus="autofocus">`), html.putEncodedEntities(postTemplate.getText()), html.put(`</textarea>`);

		if (showCaptcha)
			html.put(`<div id="postform-captcha">`, theCaptcha.getChallengeHtml(error.captchaError), `</div>`);

		html.put(
			`<input type="submit" value="Send">`
		`</form>`);
		return true;
	}

	SysTime[string] lastPostAttempt;

	PostProcess discussionSend(string[string] vars, string[string] headers)
	{
		Rfc850Post post = PostProcess.createPost(vars, headers, ip, id => getPost(id));

		try
		{
			if (vars.get("secret", "") != getUserSecret())
				throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

			user["name"] = aaGet(vars, "name");
			user["email"] = aaGet(vars, "email");

			auto now = Clock.currTime();

			if (ip in lastPostAttempt && now - lastPostAttempt[ip] < 15.seconds)
			{
				discussionPostForm(post, false, PostError("Your last post was less than 15 seconds ago. Please wait a few seconds before trying again."));
				return null;
			}

			bool captchaPresent = theCaptcha.isPresent(vars);
			if (!captchaPresent)
			{
				if (ip in lastPostAttempt && now - lastPostAttempt[ip] < 1.minutes)
				{
					discussionPostForm(post, true, PostError("Your last post was less than a minute ago. Please solve a CAPTCHA to continue."));
					return null;
				}
			}

			auto process = new PostProcess(post, vars, ip, headers);
			process.run();
			lastPostAttempt[ip] = Clock.currTime();
			return process;
		}
		catch (Exception e)
		{
			discussionPostForm(post, false, PostError(e.msg));
			return null;
		}
	}

	void discussionPostStatusMessage(string messageHtml)
	{
		html.put(
			`<table class="forum-table">`
				`<tr><th>Posting status</th></tr>`
				`<tr><td class="forum-table-message">`, messageHtml, `</th></tr>`
			`</table>`);
	}

	void discussionPostStatus(PostProcess process, out bool refresh, out string redirectTo, out bool form)
	{
		refresh = form = false;
		PostError error = process.error;
		switch (process.status)
		{
			case PostingStatus.spamCheck:
				discussionPostStatusMessage("Checking for spam...");
				refresh = true;
				return;
			case PostingStatus.captcha:
				discussionPostStatusMessage("Verifying reCAPTCHA...");
				refresh = true;
				return;
			case PostingStatus.connecting:
				discussionPostStatusMessage("Connecting to NNTP server...");
				refresh = true;
				return;
			case PostingStatus.posting:
				discussionPostStatusMessage("Sending message to NNTP server...");
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
				discussionPostForm(process.post, true, error);
				form = true;
				return;
			case PostingStatus.spamCheckFailed:
				error.message = format("%s. Please solve a CAPTCHA to continue.", error.message);
				discussionPostForm(process.post, true, error);
				form = true;
				return;
			case PostingStatus.nntpError:
				discussionPostForm(process.post, false, error);
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
				auto result = execute(["find", "logs", "-name", "*PostProcess-" ~ post ~ ".log"]); // This is MUCH faster than dirEntries.
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
			`<form action="/dodelete" method="post" class="forum-form delete-form" id="deleteform">`
			`<input type="hidden" name="id" value="`), html.putEncodedEntities(post.id), html.put(`">`
			`<div id="deleteform-info">`
				`Are you sure you want to delete this post from DFeed's database?`
			`</div>`
			`<input type="hidden" name="secret" value="`, getUserSecret(), `">`
			`<textarea id="deleteform-message" readonly="readonly" rows="25" cols="80">`), html.putEncodedEntities(post.message), html.put(`</textarea><br>`
			`Reason: <input name="reason" value="spam"></input><br>`,
			 findPostingLog(post.id)
				? `<input type="checkbox" name="ban" value="Yes" id="deleteform-ban"></input><label for="deleteform-ban">Also ban the poster from accessing the forum</label><br>`
				: ``,
			`<input type="submit" value="Delete"></input>`
		`</form>`);
	}

	void deletePost(string[string] vars)
	{
		if (vars.get("secret", "") != getUserSecret())
			throw new Exception("XSRF secret verification failed. Are your cookies enabled?");
		auto post = getPost(vars.get("id", ""));
		enforce(post, "Post not found");

		string reason = vars.get("reason", "");

		auto deletionLog = new FileLogger("Deleted");
		scope(exit) deletionLog.close();
		scope(failure) deletionLog("An error occurred");
		deletionLog("User %s is deleting post %s (%s)".format(user.getName(), post.id, reason));
		foreach (line; post.message.splitAsciiLines())
			deletionLog("> " ~ line);

		foreach (string[string] values; query!"SELECT * FROM `Posts` WHERE `ID` = ?".iterate(post.id))
			deletionLog("[Posts] row: " ~ values.toJson());
		foreach (string[string] values; query!"SELECT * FROM `Threads` WHERE `ID` = ?".iterate(post.id))
			deletionLog("[Threads] row: " ~ values.toJson());

		if (vars.get("ban", "No") == "Yes")
		{
			banPoster(user.getName(), post.id, reason);
			deletionLog("User was banned for this post.");
			html.put("User banned.<br>");
		}

		query!"DELETE FROM `Posts` WHERE `ID` = ?".exec(post.id);
		query!"DELETE FROM `Threads` WHERE `ID` = ?".exec(post.id);

		dbVersion++;
		html.put("Post deleted.");
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
		keys ~= pp.vars.get("secret", null);
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
		foreach (cookie; ("Cookie" in request.headers ? request.headers["Cookie"] : null).split("; "))
		{
			auto p = cookie.indexOf("=");
			if (p<0) continue;
			auto name = cookie[0..p];
			auto value = cookie[p+1..$];
			if (name == "dfeed_secret" || name == "dfeed_session")
				if (value.length)
					keys ~= value;
		}
		string secret = user.get("secret", null);
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

	// ***********************************************************************

	void discussionLoginForm(string[string] parameters, string errorMessage = null)
	{

		html.put(`<form action="/login" method="post" id="loginform" class="forum-form loginform">`
			`<table class="forum-table">`
				`<tr><th>Log in</th></tr>`
				`<tr><td class="loginform-cell">`);

		if ("url" in parameters)
			html.put(`<input type="hidden" name="url" value="`), html.putEncodedEntities(parameters["url"]), html.put(`">`);

		html.put(
				`<label for="loginform-username">Username:</label>`
				`<input id="loginform-username" name="username" value="`), html.putEncodedEntities(parameters.get("username", "")), html.put(`">`
				`<label for="loginform-password">Password:</label>`
				`<input id="loginform-password" type="password" name="password" value="`), html.putEncodedEntities(parameters.get("password", "")), html.put(`">`
				`<input type="submit" value="Log in">`
			`</td></tr>`);
		if (errorMessage)
			html.put(`<tr><td class="loginform-info"><div class="form-error loginform-error">`), html.putEncodedEntities(errorMessage), html.put(`</div></td></tr>`);
		else
			html.put(
				`<tr><td class="loginform-info">`
					`<a href="/registerform`,
						("url" in parameters ? `?url=` ~ encodeUrlParameter(parameters["url"]) : ``),
						`">Register</a> to keep your preferences<br>and read post history on the server.`
				`</td></tr>`);
		html.put(`</table></form>`);
	}

	void discussionLogin(string[string] parameters)
	{
		user.logIn(aaGet(parameters, "username"), aaGet(parameters, "password"));
	}

	void discussionRegisterForm(string[string] parameters, string errorMessage = null)
	{
		html.put(`<form action="/register" method="post" id="registerform" class="forum-form loginform">`
			`<table class="forum-table">`
				`<tr><th>Register</th></tr>`
				`<tr><td class="loginform-cell">`);

		if ("url" in parameters)
			html.put(`<input type="hidden" name="url" value="`), html.putEncodedEntities(parameters["url"]), html.put(`">`);

		html.put(
			`<label for="loginform-username">Username:</label>`
			`<input id="loginform-username" name="username" value="`), html.putEncodedEntities(parameters.get("username", "")), html.put(`">`
			`<label for="loginform-password">Password:</label>`
			`<input id="loginform-password" type="password" name="password" value="`), html.putEncodedEntities(parameters.get("password", "")), html.put(`">`
			`<label for="loginform-password2">Confirm:</label>`
			`<input id="loginform-password2" type="password" name="password2" value="`), html.putEncodedEntities(parameters.get("password2", "")), html.put(`">`
			`<input type="submit" value="Register">`
			`</td></tr>`);
		if (errorMessage)
			html.put(`<tr><td class="loginform-info"><div class="form-error loginform-error">`), html.putEncodedEntities(errorMessage), html.put(`</div></td></tr>`);
		else
			html.put(
				`<tr><td class="loginform-info">`
					`Please pick your password carefully.<br>There are no password recovery options.`
				`</td></tr>`);
		html.put(`</table></form>`);
	}

	void discussionRegister(string[string] parameters)
	{
		enforce(aaGet(parameters, "password") == aaGet(parameters, "password2"), "Passwords do not match");
		user.register(aaGet(parameters, "username"), aaGet(parameters, "password"));
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

	struct PostInfo { int rowid; string id, threadID, parentID, author, subject; SysTime time; }
	CachedSet!(string, PostInfo*) postInfoCache;

	PostInfo* getPostInfo(string id)
	{
		return postInfoCache(id, retrievePostInfo(id));
	}

	PostInfo* retrievePostInfo(string id)
	{
		if (id.startsWith('<') && id.endsWith('>'))
			foreach (int rowid, string threadID, string parentID, string author, string subject, long stdTime; query!"SELECT `ROWID`, `ThreadID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ID` = ?".iterate(id))
				return [PostInfo(rowid, id, threadID, parentID, author, subject, SysTime(stdTime, UTC()))].ptr;
		return null;
	}

	// ***********************************************************************

	static Regex!char reUrl;
	static this() { reUrl = regex(`\w+://[^<>\s]+[\w/\-=]`); }

	void formatBody(Rfc850Message post)
	{
		auto paragraphs = unwrapText(post.content, post.flowed, post.delsp);
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

			if (!quoteLevel && paragraph.text == "-- ")
			{
				html ~= `<span class="forum-signature">`;
				inSignature = true;
			}

			enum forceWrapThreshold = 30;
			enum forceWrapChunkSize = 10;

			import std.utf;
			bool needsWrap = paragraph.text.byChar.splitter(' ').map!(s => s.length).I!(r => reduce!max(size_t.init, r)) > forceWrapThreshold;

			auto hasURL = paragraph.text.contains("://");

			void processText(string s)
			{
				html.put(encodeEntities(s));
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
						html.put(`<span class="forcewrap">`);
						foreach (i; 0..segment.length/forceWrapChunkSize)
						{
							next(segment[i*forceWrapChunkSize..(i+1)*forceWrapChunkSize]);
							html.put(`</span><span class="forcewrap">`);
						}
						next(segment[$/forceWrapChunkSize*forceWrapChunkSize..$]);
						html.put(`</span>`);
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
				foreach (m; match(s, reUrl))
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
		return `<span style="` ~ style ~ `" title="` ~ encodeEntities(formatLongTime(time)) ~ `">` ~ encodeEntities(formatShortTime(time, shorter)) ~ `</span>`;
	}

	string formatShortTime(SysTime time, bool shorter)
	{
		if (!time.stdTime)
			return "-";

		string ago(long amount, string units)
		{
			assert(amount > 0);
			return format("%s %s%s ago", amount, units, amount==1 ? "" : "s");
		}

		auto now = Clock.currTime(UTC());
		auto duration = now - time;

		if (duration < dur!"seconds"(0))
			return "from the future";
		else
		if (duration < dur!"seconds"(1))
			return "just now";
		else
		if (duration < dur!"minutes"(1))
			return ago(duration.total!"seconds", "second");
		else
		if (duration < dur!"hours"(1))
			return ago(duration.total!"minutes", "minute");
		else
		if (duration < dur!"days"(1))
			return ago(duration.total!"hours", "hour");
		else
		/*if (duration < dur!"days"(2))
			return "yesterday";
		else
		if (duration < dur!"days"(6))
			return formatTime("l", time);
		else*/
		if (duration < dur!"days"(7))
			return ago(duration.total!"days", "day");
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
		auto encoded = encodeEntities(s8);
		return `<span class="truncated" style="max-width: ` ~ text(maxLength * 0.6) ~ `em" title="`~encoded~`">` ~ encoded ~ `</span>`;
	}

	static string encodeEntities(string s)
	{
		StringBuilder result;
		size_t start = 0;

		foreach (i, c; s)
			if (c=='<')
				result.put(s[start..i], "&lt;"),
				start = i+1;
			else
			if (c=='>')
				result.put(s[start..i], "&gt;"),
				start = i+1;
			else
			if (c=='&')
				result.put(s[start..i], "&amp;"),
				start = i+1;
			else
			if (c=='"')
				result.put(s[start..i], "&quot;"),
				start = i+1;

		if (!start)
			return s;

		result.put(s[start..$]);
		return result.get();
	}

	string viewModeTool(string[] modes, string what)
	{
		auto currentMode = user.get(what ~ "viewmode", modes[0]);
		return "View mode: " ~
			array(map!((string mode) {
				return mode == currentMode
					? `<span class="viewmode-active" title="Viewing in ` ~ mode ~ ` mode">` ~ mode ~ `</span>`
					: `<a title="Switch to ` ~ mode ~ ` ` ~ what ~ ` view mode" href="` ~ encodeEntities(setOptionLink(what ~ "viewmode", mode)) ~ `">` ~ mode ~ `</a>`;
			})(modes)).join(" / ");
	}

	/// Generate a link to set a user preference
	string setOptionLink(string name, string value)
	{
		return "/set?" ~ encodeUrlParameters([name : value, "url" : "__URL__", "secret" : getUserSecret()]);
	}

	// ***********************************************************************

	enum FEED_HOURS_DEFAULT = 24;
	enum FEED_HOURS_MAX = 72;

	CachedSet!(string, CachedResource) feedCache;

	CachedResource getFeed(string group, bool threadsOnly, int hours)
	{
		string feedUrl = "http://" ~ vhost ~ "/feed" ~
			(threadsOnly ? "/threads" : "/posts") ~
			(group ? "/" ~ group : "") ~
			(hours!=FEED_HOURS_DEFAULT ? "?hours=" ~ text(hours) : "");
		return feedCache(feedUrl, makeFeed(feedUrl, group, threadsOnly, hours));
	}

	CachedResource makeFeed(string feedUrl, string group, bool threadsOnly, int hours)
	{
		string PERF_SCOPE = "makeFeed(,%s,%s,%s)".format(group, threadsOnly, hours); mixin(MeasurePerformanceMixin);
		auto title = "Latest " ~ (threadsOnly ? "threads" : "posts") ~ (group ? " on " ~ group : "");

		AtomFeedWriter feed;
		feed.startFeed(feedUrl, title, Clock.currTime());

		auto since = (Clock.currTime() - dur!"hours"(hours)).stdTime;
		auto iterator =
			group ?
				threadsOnly ?
					query!"SELECT `Message` FROM `Posts` WHERE `ID` IN (SELECT `ID` FROM `Groups` WHERE `Time` > ? AND `Group` = ?) AND `ID` = `ThreadID`".iterate(since, group)
				:
					query!"SELECT `Message` FROM `Posts` WHERE `ID` IN (SELECT `ID` FROM `Groups` WHERE `Time` > ? AND `Group` = ?)".iterate(since, group)
			:
				threadsOnly ?
					query!"SELECT `Message` FROM `Posts` WHERE `Time` > ? AND `ID` = `ThreadID`".iterate(since)
				:
					query!"SELECT `Message` FROM `Posts` WHERE `Time` > ?".iterate(since)
			;

		foreach (string message; iterator)
		{
			auto post = new Rfc850Post(message);

			html.clear();
			html.put("<pre>");
			formatBody(post);
			html.put("</pre>");

			auto url = "http://" ~ vhost ~ idToUrl(post.id);
			auto title = post.rawSubject;
			if (!group)
				title = "[" ~ post.where ~ "] " ~ title;

			feed.putEntry(url, title, post.author, post.time, cast(string)html.get(), url);
		}
		feed.endFeed();

		return new CachedResource([Data(feed.xml.output.get())], "application/atom+xml");
	}
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
}
const Config config;

import ae.utils.sini;
shared static this() { config = loadIni!Config("config/web.ini"); }

module web;

import std.file;
import std.string;
import std.conv;
import std.exception;
import std.array, std.algorithm;
import std.datetime;
debug import std.stdio;

alias std.string.indexOf indexOf;

import ae.net.asockets;
import ae.net.http.server;
import ae.net.http.responseex;
import ae.sys.log;
import ae.utils.json;
import ae.utils.array;
import ae.utils.time;
import ae.utils.text;

import common;
import database;
import cache;
import rfc850;
import user;
import recaptcha;
import posting;

class WebUI
{
	Logger log;
	HttpServer server;
	User user;
	string ip;
	StringBuilder html;

	this()
	{
		log = createLogger("Web");

		auto port = to!ushort(readText("data/web.txt").splitLines()[0]);

		server = new HttpServer();
		server.handleRequest = &onRequest;
		server.listen(port);
		log(format("Listening on port %d", port));
	}

	string staticPath(string path)
	{
		return "/static/" ~ text(timeLastModified("web/static" ~ path).stdTime) ~ path;
	}

	string optimizedPath(string base, string path)
	{
		auto origPath = base ~ path;
		auto optiPath = base ~ path ~ "-opt";
		if (exists(origPath) && exists(optiPath) && timeLastModified(optiPath) >= timeLastModified(origPath))
			return path ~ "-opt";
		else
			return path;
	}

	enum JQUERY_URL = "http://ajax.googleapis.com/ajax/libs/jquery/1.7.1/jquery.min.js";

	HttpResponse onRequest(HttpRequest request, ClientSocket from)
	{
		StopWatch responseTime;
		responseTime.start();
		auto response = new HttpResponseEx();

		ip = from.remoteAddress;
		ip = ip[0..ip.lastIndexOf(':')];
		if ("X-Forwarded-For" in request.headers)
			ip = request.headers["X-Forwarded-For"];
		scope(exit) log(format("%s - %dms - %s", ip, responseTime.peek().msecs, request.resource));

		user = getUser("Cookie" in request.headers ? request.headers["Cookie"] : null);
		scope(success) foreach (cookie; user.save()) response.headers.add("Set-Cookie", cookie);

		string title, breadcrumb1, breadcrumb2;
		string bodyClass = "narrowdoc";
		html.clear();
		string[] tools, extraHeaders;

		auto splitViewHeaders = [
			`<script src="` ~ JQUERY_URL ~ `"></script>`,
			`<script src="` ~ staticPath("/js/dfeed-split.js") ~ `"></script>`,
		];

		try
		{
			auto pathStr = request.resource;
			enforce(pathStr.length > 1 && pathStr[0] == '/', "Invalid path");
			string[string] parameters;
			if (pathStr.indexOf('?') >= 0)
			{
				auto p = pathStr.indexOf('?');
				parameters = decodeUrlParameters(pathStr[p+1..$]);
				pathStr = pathStr[0..p];
			}
			auto path = pathStr[1..$].split("/");
			assert(path.length);

			switch (path[0])
			{
				case "discussion":
				{
					if (path.length == 1)
						return response.redirect("/dicussion/");
					switch (path[1])
					{
						case "":
							title = "Index";
							breadcrumb1 = `<a href="/discussion/">Forum Index</a>`;
							discussionIndex();
							break;
						case "group":
						{
							enforce(path.length > 2, "No group specified");
							string group = path[2];
							int page = to!int(aaGet(parameters, "page", "1"));
							string pageStr = page==1 ? "" : format(" (page %d)", page);
							title = group ~ " index" ~ pageStr;
							breadcrumb1 = `<a href="/discussion/group/`~encodeEntities(group)~`">` ~ encodeEntities(group) ~ `</a>` ~ pageStr;
							auto viewMode = user.get("groupviewmode", "basic");
							if (viewMode == "basic")
								discussionGroup(group, page);
							else
							if (viewMode == "threaded")
								discussionGroupThreaded(group, page);
							else
							{
								discussionGroupSplit(group, page);
								extraHeaders ~= splitViewHeaders;
							}
							//tools ~= viewModeTool(["basic", "threaded"], "group");
							tools ~= viewModeTool(["basic", "threaded", "horizontal-split"], "group");
							break;
						}
						case "thread":
						{
							enforce(path.length > 2, "No thread specified");
							int page = to!int(aaGet(parameters, "page", "1"));
							string threadID = '<' ~ urlDecode(path[2]) ~ '>';

							if (user.get("groupviewmode", "basic") == "basic")
							{
								string pageStr = page==1 ? "" : format(" (page %d)", page);
								string group, subject;
								discussionThread(threadID, page, group, subject);
								title = subject ~ pageStr;
								breadcrumb1 = `<a href="/discussion/group/` ~encodeEntities(group  )~`">` ~ encodeEntities(group  ) ~ `</a>`;
								breadcrumb2 = `<a href="/discussion/thread/`~encodeEntities(path[2])~`">` ~ encodeEntities(subject) ~ `</a>` ~ pageStr;
								//tools ~= viewModeTool(["flat", "nested"], "thread");
								tools ~= viewModeTool(["basic", "threaded", "horizontal-split"], "group");
							}
							else
								return response.redirect(idToUrl(getPostAtThreadIndex(threadID, getPageOffset(page, POSTS_PER_PAGE))));
							break;
						}
						case "post":
							enforce(path.length > 2, "No post specified");
							if (user.get("groupviewmode", "basic") == "basic")
								return response.redirect(resolvePostUrl('<' ~ urlDecode(path[2]) ~ '>'));
							else
							if (user.get("groupviewmode", "basic") == "threaded")
							{
								string group, subject;
								discussionSinglePost('<' ~ urlDecode(path[2]) ~ '>', group, subject);
								title = subject;
								breadcrumb1 = `<a href="/discussion/group/` ~encodeEntities(group  )~`">` ~ encodeEntities(group  ) ~ `</a>`;
								breadcrumb2 = `<a href="/discussion/thread/`~encodeEntities(path[2])~`">` ~ encodeEntities(subject) ~ `</a> (view single post)`;
								tools ~= viewModeTool(["basic", "threaded", "horizontal-split"], "group");
								break;
							}
							else
							{
								string group;
								int page;
								discussionGroupSplitFromPost('<' ~ urlDecode(path[2]) ~ '>', group, page);

								string pageStr = page==1 ? "" : format(" (page %d)", page);
								title = group ~ " index" ~ pageStr;
								breadcrumb1 = `<a href="/discussion/group/`~encodeEntities(group)~`">` ~ encodeEntities(group) ~ `</a>` ~ pageStr;
								extraHeaders ~= splitViewHeaders;
								tools ~= viewModeTool(["basic", "threaded", "horizontal-split"], "group");

								break;
							}
						case "raw":
						{
							enforce(path.length > 2, "Invalid URL");
							auto post = getPost('<' ~ urlDecode(path[2]) ~ '>', array(map!(to!uint)(path[3..$])));
							enforce(post, "Post not found");
							if (!post.data && post.error)
								throw new Exception(post.error);
							if (post.fileName)
								response.headers["Content-Disposition"] = `inline; filename="` ~ post.fileName ~ `"`;
							// TODO: is allowing text/html (others?) OK here?
							return response.serveData(Data(post.data), post.mimeType ? post.mimeType : "application/octet-stream");
						}
						case "split-post":
							enforce(path.length > 2, "No post specified");
							discussionSplitPost('<' ~ urlDecode(path[2]) ~ '>');
							return response.serveData(html.getString());
						case "set":
							foreach (name, value; parameters)
								if (name != "url")
									user[name] = value; // TODO: is this a good idea?
							if ("url" in parameters)
								return response.redirect(parameters["url"]);
							else
								return response.serveText("OK");
						case "mark-unread":
						{
							enforce(path.length > 2, "No post specified");
							auto post = getPostInfo('<' ~ urlDecode(path[2]) ~ '>');
							enforce(post, "Post not found");
							user.setRead(post.rowid, false);
							return response.serveText("OK");
						}
						case "first-unread":
						{
							enforce(path.length > 2, "No thread specified");
							return response.redirect(discussionFirstUnread('<' ~ urlDecode(path[2]) ~ '>'));
						}
						case "newpost":
						{
							enforce(path.length > 2, "No group specified");
							string group = path[2];
							title = "Posting to " ~ group;
							breadcrumb1 = `<a href="/discussion/group/`~encodeEntities(group)~`">` ~ encodeEntities(group) ~ `</a>`;
							breadcrumb2 = `<a href="/discussion/newpost/`~encodeEntities(group)~`">New thread</a>`;
							if (discussionPostForm(Rfc850Post.newPostTemplate(group)))
								bodyClass ~= " formdoc";
							break;
						}
						case "reply":
						{
							enforce(path.length > 2, "No post specified");
							auto post = getPost('<' ~ urlDecode(path[2]) ~ '>');
							enforce(post, "Post not found");
							title = `Replying to "` ~ post.subject ~ `"`;
							breadcrumb1 = `<a href="` ~ encodeEntities(idToUrl(post.id)) ~ `">` ~ encodeEntities(post.subject) ~ `</a>`;
							breadcrumb2 = `<a href="/discussion/reply/`~path[2]~`">Post reply</a>`;
							if (discussionPostForm(post.replyTemplate()))
								bodyClass ~= " formdoc";
							break;
						}
						case "send":
						{
							auto postVars = request.decodePostData();
							auto process = discussionSend(postVars, cast(string[string])request.headers);
							if (process)
								return response.redirect("/discussion/poststatus/" ~ process.pid);

							title = breadcrumb1 = `Posting error`;
							bodyClass ~= " formdoc";
							break;
						}
						case "poststatus":
						{
							enforce(path.length > 2, "No PID specified");
							auto pid = path[2];
							enforce(pid in postProcesses, "Sorry, this is not a post I know of.");
							bool refresh, form;
							discussionPostStatus(postProcesses[pid], refresh, form);
							if (refresh)
								response.setRefresh(1);
							if (form)
							{
								title = breadcrumb1 = `Posting error`;
								bodyClass ~= " formdoc";
							}
							else
								title = breadcrumb1 = `Posting status`;
							break;
						}
						case "loginform":
						{
							discussionLoginForm(parameters);
							title = breadcrumb1 = `Log in`;
							tools ~= `<a href="/discussion/registerform?url=__URL__">Register</a>`;
							break;
						}
						case "registerform":
						{
							discussionRegisterForm(parameters);
							title = breadcrumb1 = `Registration`;
							tools ~= `<a href="/discussion/registerform?url=__URL__">Register</a>`;
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
								tools ~= `<a href="/discussion/registerform?url=__URL__">Register</a>`;
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
								tools ~= `<a href="/discussion/registerform?url=__URL__">Register</a>`;
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
						default:
							throw new NotFoundException();
					}
					break;
				}
				case "js":
				case "css":
				case "images":
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
				breadcrumb1 = title = "Not Found";
			else
				breadcrumb1 = title = "Error";
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
			tools ~= `<a href="/discussion/logout?url=__URL__">Log out ` ~ encodeEntities(user.getName()) ~ `</a>`;
		else
			tools ~= `<a href="/discussion/loginform?url=__URL__">Log in</a>`;
		tools ~= `<a href="/discussion/help">Help</a>`;

		string toolStr = tools.join(" &middot; ");
		toolStr =
			toolStr.replace("__URL__",  encodeUrlParameter(request.resource)) ~
			`<script type="text/javascript">var toolsTemplate = ` ~ toJson(toolStr) ~ `;</script>`;

		string[string] vars = [
			"title" : encodeEntities(title),
			"content" : cast(string) html.data, // html contents will be overwritten on next request
			"breadcrumb1" : breadcrumb1,
			"breadcrumb2" : breadcrumb2,
			"extraheaders" : extraHeaders.join("\n"),
			"bodyclass" : bodyClass,
			"tools" : toolStr,
		];
		foreach (DirEntry de; dirEntries("web/static", SpanMode.depth))
			if (isFile(de.name))
			{
				auto path = de.name["web/static".length..$].replace(`\`, `/`);
				vars["static:" ~ path] = staticPath(path);
			}
		response.disableCache();
		response.serveData(HttpResponseEx.loadTemplate(optimizedPath(null, "web/skel.htt"), vars));
		response.setStatus(HttpStatusCode.OK);
		return response;
	}

	HttpResponseEx serveFile(HttpResponseEx response, string path)
	{
		response.cacheForever();
		return response.serveFile(optimizedPath("web/static/", path), "web/static/");
	}

	struct GroupInfo { bool isML; string name, description; }
	struct GroupSet { string name; GroupInfo[] groups; }

	/*const*/ GroupSet[] groupHierarchy = [
	{ "D Programming Language", [
		{ false,	"digitalmars.D",			"General discussion of the D programming language." },
		{ false,	"digitalmars.D.announce",	"Announcements for anything D related" },
		{ false,	"digitalmars.D.bugs",		"Bug reports for D compiler and library" },
		{ false,	"digitalmars.D.debugger",	"Debuggers for D" },
		{ false,	"digitalmars.D.dwt",		"Developing the D Widget Toolkit" },
		{ false,	"digitalmars.D.dtl",		"Developing the D Template Library" },
		{ false,	"digitalmars.D.ide",		"Integrated Debugging Environments for D" },
		{ false,	"digitalmars.D.learn",		"Questions about learning D" },
		{ false,	"D.gnu",					"GDC, the Gnu D Compiler " },
		{ true,		"dmd-beta",					"Notify of and discuss beta versions" },
		{ true,		"dmd-concurrency",			"Design of concurrency features in D and library" },
		{ true,		"dmd-internals",			"dmd compiler internal design and implementation" },
		{ true,		"phobos",					"Phobos standard library design and implementation" },
		{ true,		"D-runtime",				"Runtime library design and implementation" },
	]},
	{ "C and C++", [
		{ false,	"c++",						"General discussion of DMC++ compiler" },
		{ false,	"c++.announce",				"Announcements about C++" },
		{ false,	"c++.atl",					"Microsoft's Advanced Template Library" },
		{ false,	"c++.beta",					"Test versions of various C++ products" },
		{ false,	"c++.chat",					"Off topic discussions" },
		{ false,	"c++.command-line",			"Command line tools" },
		{ false,	"c++.dos",					"DMC++ and DOS" },
		{ false,	"c++.dos.16-bits",			"16 bit DOS topics" },
		{ false,	"c++.dos.32-bits",			"32 bit extended DOS topics" },
		{ false,	"c++.idde",					"The Digital Mars Integrated Development and Debugging Environment" },
		{ false,	"c++.mfc",					"Microsoft Foundation Classes" },
		{ false,	"c++.rtl",					"C++ Runtime Library" },
		{ false,	"c++.stl",					"Standard Template Library" },
		{ false,	"c++.stl.hp",				"HP's Standard Template Library" },
		{ false,	"c++.stl.port",				"STLPort Standard Template Library" },
		{ false,	"c++.stl.sgi",				"SGI's Standard Template Library" },
		{ false,	"c++.stlsoft",				"Stlsoft products" },
		{ false,	"c++.windows",				"Writing C++ code for Microsoft Windows" },
		{ false,	"c++.windows.16-bits",		"16 bit Windows topics" },
		{ false,	"c++.windows.32-bits",		"32 bit Windows topics" },
		{ false,	"c++.wxwindows",			"wxWindows" },
	]},
	{ "Other", [
		{ false,	"DMDScript",				"General discussion of DMDScript" },
		{ false,	"digitalmars.empire",		"General discussion of Empire, the Wargame of the Century" },
		{ false,	"D",						"Retired, use digitalmars.D instead" },
	]}];

	GroupInfo* getGroupInfo(string name)
	{
		foreach (set; groupHierarchy)
			foreach (ref group; set.groups)
				if (group.name == name)
					return &group;
		return null;
	}

	int[string] getThreadCounts()
	{
		int[string] threadCounts;
		foreach (string group, int count; query("SELECT `Group`, COUNT(*) FROM `Threads` GROUP BY `Group`").iterate())
			threadCounts[group] = count;
		return threadCounts;
	}

	int[string] getPostCounts()
	{
		int[string] postCounts;
		foreach (string group, int count; query("SELECT `Group`, COUNT(*) FROM `Groups`  GROUP BY `Group`").iterate())
			postCounts[group] = count;
		return postCounts;
	}

	string[string] getLastPosts()
	{
		string[string] lastPosts;
		foreach (set; groupHierarchy)
			foreach (group; set.groups)
				foreach (string id; query("SELECT `ID` FROM `Groups` WHERE `Group`=? ORDER BY `Time` DESC LIMIT 1").iterate(group.name))
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
						`<a class="forum-postsummary-subject ` ~ (user.isRead(rowid) ? "forum-read" : "forum-unread") ~ `" href="` ~ encodeEntities(idToUrl(id)) ~ `">` ~ truncateString(subject) ~ `</a><br>` ~
						`by <span class="forum-postsummary-author">` ~ truncateString(author) ~ `</span><br>` ~
						`<span class="forum-postsummary-time">` ~ summarizeTime(time) ~ `</span>`;

			return `<div class="forum-no-data">-</div>`;
		}

		html.put(`<table id="forum-index" class="forum-table">`);
		foreach (set; groupHierarchy)
		{
			html.put(
				`<tr><th colspan="4">`, encodeEntities(set.name), `</th></tr>`
				`<tr class="subheader"><th>Forum</th><th>Last Post</th><th>Threads</th><th>Posts</th>`);
			foreach (group; set.groups)
			{
				html.put(
					`<tr>`
						`<td class="forum-index-col-forum"><a href="/discussion/group/`, encodeEntities(group.name), `">`, encodeEntities(group.name), `</a>`
							`<div class="forum-index-description">`, encodeEntities(group.description), `</div>`
						`</td>`
						`<td class="forum-index-col-lastpost">`   , (group.name in lastPosts    ? summarizePost(lastPosts[group.name]) : `<div class="forum-no-data">-</div>`), `</td>`
						`<td class="number-column">`, (group.name in threadCounts ? formatNumber(threadCounts[group.name]) : `-`), `</td>`
						`<td class="number-column">`  , (group.name in postCounts   ? formatNumber(postCounts[group.name]) : `-`) , `</td>`
					`</tr>`,
				);
			}
		}
		html.put(`</table>`);
	}

	int[] getThreadPostIndexes(string id)
	{
		int[] result;
		foreach (int rowid; query("SELECT `ROWID` FROM `Posts` WHERE `ThreadID` = ?").iterate(id))
			result ~= rowid;
		return result;
	}

	CachedSet!(string, int[]) threadPostIndexCache;

	void newPostButton(string group)
	{
		html.put(
			`<form name="new-post-form" method="get" action="/discussion/newpost/`, encodeEntities(group), `">`
				`<div class="header-tools">`
					`<input type="submit" value="Create thread">`
				`</div>`
			`</form>`);
	}

	void pager(string base, int page, int pageCount, int radius = 4)
	{
		string linkOrNot(string text, int page, bool cond)
		{
			if (cond)
				return `<a href="` ~ encodeEntities(base) ~ `?page=` ~ .text(page) ~ `">` ~ text ~ `</a>`;
			else
				return `<span class="disabled-link">` ~ text ~ `</span>`;
		}

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

	void threadPager(string group, int page, int radius = 4)
	{
		auto threadCounts = threadCountCache(getThreadCounts());
		enforce(group in threadCounts, "Empty or unknown group");
		auto threadCount = threadCounts[group];
		auto pageCount = getPageCount(threadCount, THREADS_PER_PAGE);

		pager(`/discussion/group/` ~ group, page, pageCount, radius);
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

		foreach (string firstPostID, string lastPostID; query("SELECT `ID`, `LastPost` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?").iterate(group, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
			foreach (int count; query("SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?").iterate(firstPostID))
				threads ~= Thread(firstPostID, getPostInfo(firstPostID), getPostInfo(lastPostID), count, getUnreadPostCount(firstPostID));

		void summarizeThread(string tid, PostInfo* info, bool isRead)
		{
			if (info)
				with (*info)
					return html.put(
					//	`<!-- Thread ID: ` ~ encodeEntities(threadID) ~ ` | First Post ID: ` ~ encodeEntities(id) ~ `-->` ~
						`<a class="forum-postsummary-subject `, (isRead ? "forum-read" : "forum-unread"), `" href="`, encodeEntities(idToUrl(tid, "thread")), `">`, truncateString(subject, 100), `</a><br>`
						`by <span class="forum-postsummary-author">`, truncateString(author, 100), `</span><br>`);

			html.put(`<div class="forum-no-data">-</div>`);
		}

		void summarizeLastPost(PostInfo* info)
		{
			// TODO: link?
			if (info)
				with (*info)
					return html.put(
						`<span class="forum-postsummary-time">`, summarizeTime(time), `</span>`
						`by <span class="forum-postsummary-author">`, truncateString(author, 25), `</span><br>`);

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
			`<tr class="group-index-header"><th colspan="3"><div class="header-with-tools">`), newPostButton(group), html.put(encodeEntities(group), `</div></th></tr>`
			`<tr class="subheader"><th>Thread / Thread Starter</th><th>Last Post</th><th>Replies</th>`);
		foreach (thread; threads)
			html.put(
				`<tr>`
					`<td class="group-index-col-first">`), summarizeThread(thread.id, thread.firstPost, thread.isRead), html.put(`</td>`
					`<td class="group-index-col-last">`), summarizeLastPost(thread.lastPost), html.put(`</td>`
					`<td class="number-column">`), summarizePostCount(thread), html.put(`</td>`
				`</tr>`);
		threadPager(group, page);
		html.put(
			`</table>`
		);
	}

	string[][string] referenceCache; // invariant

	void formatThreadedPosts(PostInfo*[] postInfos, string selectedID = null)
	{
		enum OFFSET_INIT = 1f;
		enum OFFSET_MAX = 2f;
		enum OFFSET_WIDTH = 40f;
		enum OFFSET_UNITS = "%";

		struct Post
		{
			PostInfo* info;
			alias info this;

			SysTime maxTime;
			Post*[] children;
			int maxDepth;

			bool ghost; // dummy parent for orphans
			string ghostSubject;

			@property string subject() { return ghostSubject ? ghostSubject : info.subject; }

			void calcStats()
			{
				foreach (child; children)
					child.calcStats();

				if (info)
					maxTime = time;
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
			posts[info.id] = Post(info);

		posts[null] = Post();
		foreach (ref post; posts)
			if (post.info)
			{
				auto parent = post.parentID;
				if (parent !in posts) // mailing-list users
				{
					string[] references;
					if (post.id in referenceCache)
						references = referenceCache[post.id];
					else
						references = referenceCache[post.id] = getPost(post.id).references;

					parent = null;
					foreach_reverse (reference; references)
						if (reference in posts)
						{
							parent = reference;
							break;
						}

					if (!parent)
					{
						Post dummy;
						dummy.ghost = true;
						dummy.ghostSubject = post.subject; // HACK
						parent = references[0];
						posts[parent] = dummy;
						posts[null].children ~= parent in posts;
					}
				}
				posts[parent].children ~= &post;
			}

		foreach (ref post; posts)
		{
			post.calcStats();

			if (post.info || post.ghost)
				sort!"a.time < b.time"(post.children);
			else // sort threads by last-update
				sort!"a.maxTime < b.maxTime"(post.children);
		}

		float offsetIncrement; // = max(1f, min(OFFSET_MAX, OFFSET_WIDTH / posts[null].maxDepth));

		string normalizeSubject(string s)
		{
			return s
				.replace("New: ", "") // Bugzilla hack
				.replace("\t", " ")   // Apple Mail hack
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

		void formatPosts(Post*[] posts, int level, string parentSubject, bool topLevel)
		{
			void formatPost(Post* post, int level)
			{
				if (post.ghost)
					return formatPosts(post.children, level, post.subject, false);
				html.put(
					`<tr class="thread-post-row`, (post.info && post.id==selectedID ? ` thread-post-focused thread-post-selected` : ``), `">`
						`<td>`
							`<div style="padding-left: `, format("%1.1f", OFFSET_INIT + level * offsetIncrement), OFFSET_UNITS, `">`
								`<div class="thread-post-time">`, summarizeTime(post.time), `</div>`,
								`<a class="postlink `, (user.isRead(post.rowid) ? "forum-read" : "forum-unread" ), `" href="`, encodeEntities(idToUrl(post.id)), `">`, encodeEntities(post.author), `</a>`
							`</div>`
						`</td>`
					`</tr>`);
				formatPosts(post.children, level+1, post.subject, false);
			}

			auto offsetStr = format("%1.1f", OFFSET_INIT + level * offsetIncrement) ~ OFFSET_UNITS; // OPTLINK
			foreach (post; posts)
			{
				if (topLevel)
					offsetIncrement = min(OFFSET_MAX, OFFSET_WIDTH / post.maxDepth);

				if (topLevel || normalizeSubject(post.subject) != normalizeSubject(parentSubject))
				{
					html.put(
						`<tr><td style="padding-left: `, offsetStr, `">`
						`<table class="thread-start">`
							`<tr><th>`, encodeEntities(post.subject), `</th></tr>`);
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

		//foreach (string threadID; query("SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?").iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
		//	foreach (string id, string parent, string author, string subject, long stdTime; query("SELECT `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?").iterate(threadID))
		PostInfo*[] posts;
		enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` IN (SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?)";
		foreach (int rowid, string id, string parent, string author, string subject, long stdTime; query(ViewSQL).iterate(group, THREADS_PER_PAGE, getPageOffset(page, THREADS_PER_PAGE)))
			posts ~= [PostInfo(rowid, id, null, parent, author, subject, SysTime(stdTime, UTC()))].ptr; // TODO: optimize?

		html.put(
			`<table id="group-index" class="forum-table group-wrapper viewmode-`, encodeEntities(user.get("groupviewmode", "basic")), `">`
			`<tr class="group-index-header"><th><div>`), newPostButton(group), html.put(encodeEntities(group), `</div></th></tr>`, newline,
		//	`<tr class="group-index-captions"><th>Subject / Author</th><th>Time</th>`, newline,
			`<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
		formatThreadedPosts(posts);
		html.put(`</table></div></td></tr>`);
		threadPager(group, page, narrow ? 1 : 4);
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

		group = post.xref[0].group;
		page = getThreadPage(group, post.threadID);

		discussionGroupSplit(group, page);
	}

	int getThreadPage(string group, string thread)
	{
		int page = 0;

		foreach (long time; query("SELECT `LastUpdated` FROM `Threads` WHERE `ID` = ? LIMIT 1").iterate(thread))
			foreach (int threadIndex; query("SELECT COUNT(*) FROM `Threads` WHERE `Group` = ? AND `LastUpdated` > ? ORDER BY `LastUpdated` DESC").iterate(group, time))
				page = indexToPage(threadIndex, THREADS_PER_PAGE);

		enforce(page > 0, "Can't find thread's page");
		return page;
	}

	string[] formatPostParts(Rfc850Post post)
	{
		string[] partList;
		void visitParts(Rfc850Post[] parts, int[] path)
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
		import std.md5;
		return toLower(getDigestString(strip(toLower(email))));
	}

	string getUserSecret()
	{
		if ("secret" !in user)
			user["secret"] = randomString();
		return user["secret"];
	}

	void replyButton(string id)
	{
		html.put(
			`<a class="replylink" href="`, encodeEntities(idToUrl(id, "reply")), `">`
				`<img src="`, staticPath("/images/reply.png"), `">Reply`
			`</a>`);
	}

	void formatPost(Rfc850Post post, Rfc850Post[string] knownPosts)
	{
		string gravatarHash = getGravatarHash(post.authorEmail);

		string[] infoBits;

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
				infoBits ~= `Posted in reply to <a href="` ~ encodeEntities(link) ~ `">` ~ encodeEntities(author) ~ `</a>`;
		}

		auto partList = formatPostParts(post);
		if (partList.length)
			infoBits ~=
				`Attachments:<ul class="post-info-parts"><li>` ~ partList.join(`</li><li>`) ~ `</li></ul>`;

		if (knownPosts is null && post.threadID)
			infoBits ~=
				`<a href="` ~ encodeEntities(idToThreadUrl(post.id, post.threadID)) ~ `">View in thread</a>`;

		string repliesTitle = `Replies to `~encodeEntities(post.author)~`'s post from `~encodeEntities(formatShortTime(post.time));

		with (post)
		{
			html.put(
				`<div class="post-wrapper">`
				`<table class="post forum-table`, (children ? ` with-children` : ``), `" id="`, encodeEntities(idToFragment(id)), `">`
				`<tr class="post-header"><th colspan="2">`
					`<div class="post-time">`, summarizeTime(time), `</div>`
					`<a title="Permanent link to this post" href="`, encodeEntities(idToUrl(id)), `" class="`, (user.isRead(rowid) ? "forum-read" : "forum-unread"), `">`,
						encodeEntities(realSubject),
					`</a>`
				`</th></tr>`
				`<tr>`
					`<td class="post-info">`
						`<div class="post-author">`, encodeEntities(author), `</div>`
						`<a href="http://www.gravatar.com/`, gravatarHash, `" title="`, encodeEntities(author), `'s Gravatar profile">`
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
			html.put(
						`<br>` // guarantee space for the "toolbar"
						`<div class="post-toolbar">`), replyButton(id), html.put(`</div>`
					`</td>`
					`<td class="post-body">`
						`<div class="post-text">`), formatBody(content), html.put(`</div>`,
						(error ? `<span class="post-error">` ~ encodeEntities(error) ~ `</span>` : ``),
					`</td>`
				`</tr>`
				`</table>`
				`</div>`);

			if (children)
			{
				html.put(
					`<table class="post-nester"><tr>`
					`<td class="post-nester-bar" title="`, /* for IE */ repliesTitle, `">`
						`<a href="#`, encodeEntities(idToFragment(id)), `" `
							`title="`, repliesTitle, `"></a>`
					`</td>`
					`<td>`);
				foreach (child; children)
					formatPost(child, knownPosts);
				html.put(`</td>`
					`</tr></table>`);
			}
		}

		user.setRead(post.rowid, true);
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

	/// Alternative post formatting, with the meta-data header on top
	void formatSplitPost(Rfc850Post post)
	{
		scope(success) user.setRead(post.rowid, true);

		struct InfoRow { string name, value; }
		InfoRow[] infoRows;

		infoRows ~= InfoRow("From", post.author);
		infoRows ~= InfoRow("Date", format("%s (%s)", formatLongTime(post.time), formatShortTime(post.time)));

		if (post.parentID)
		{
			auto parent = getPostInfo(post.parentID);
			if (parent)
				infoRows ~= InfoRow("In reply to", postLink(parent.rowid, parent.id, parent.author));
		}

		string[] replies;
		foreach (int rowid, string id, string author; query("SELECT `ROWID`, `ID`, `Author` FROM `Posts` WHERE ParentID = ?").iterate(post.id))
			replies ~= postLink(rowid, id, author);
		if (replies.length)
			infoRows ~= InfoRow("Replies", replies.join(", "));

		auto partList = formatPostParts(post);
		if (partList.length)
			infoRows ~= InfoRow("Attachments", partList.join(", "));

		string gravatarHash = getGravatarHash(post.authorEmail);

		with (post)
		{
			html.put(
				`<div class="post-wrapper">`
				`<table class="split-post forum-table" id="`, encodeEntities(idToFragment(id)), `">`
				`<tr class="post-header"><th>`
					`<div class="post-time">`, summarizeTime(time), `</div>`
					`<a title="Permanent link to this post" href="`, encodeEntities(idToUrl(id)), `" class="`, (user.isRead(rowid) ? "forum-read" : "forum-unread"), `">`,
						encodeEntities(realSubject),
					`</a>`
				`</th></tr>`
				`<tr><td class="split-post-info">`
					`<table><tr>`, // yay 4x nested table layouts
						`<td class="split-post-avatar" rowspan="`, text(infoRows.length), `">`
							`<a href="http://www.gravatar.com/`, gravatarHash, `" title="`, encodeEntities(author), `'s Gravatar profile">`
								`<img alt="Gravatar" class="post-gravatar" width="48" height="48" src="http://www.gravatar.com/avatar/`, gravatarHash, `?d=identicon&s=48">`
							`</a>`
						`</td>`
						`<td><table>`);
			foreach (a; infoRows)
				html.put(`<tr><td class="split-post-info-name">`, a.name, `</td><td class="split-post-info-value">`, a.value, `</td></tr>`);
			html.put(
						`</table></td>`
						`<td class="split-post-reply">`), replyButton(id), html.put(`</td>`
					`</tr></table>`
				`</td></tr>`
				`<tr><td class="post-body">`
					`<div class="post-text">`), formatBody(content), html.put(`</div>`,
					(error ? `<span class="post-error">` ~ encodeEntities(error) ~ `</span>` : ``),
				`</td></tr>`
				`</table>`
				`</div>`);
		}
	}

	void discussionSplitPost(string id)
	{
		auto post = getPost(id);
		enforce(post, "Post not found");

		formatSplitPost(post);
	}

	void postPager(string threadID, int page, int postCount)
	{
		pager(idToUrl(threadID, "thread"), page, getPageCount(postCount, POSTS_PER_PAGE));
	}

	int getPostCount(string threadID)
	{
		foreach (int count; query("SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?").iterate(threadID))
			return count;
		assert(0);
	}

	int getPostThreadIndex(string threadID, SysTime postTime)
	{
		foreach (int index; query("SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ? AND `Time` < ? ORDER BY `Time` ASC").iterate(threadID, postTime.stdTime))
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
		foreach (string id; query("SELECT `ID` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC LIMIT 1 OFFSET ?").iterate(threadID, index))
			return id;
		throw new Exception(format("Post #%d of thread %s not found", index, threadID));
	}

	void discussionThread(string id, int page, out string group, out string title)
	{
		auto viewMode = user.get("threadviewmode", "flat"); // legacy
		bool nested = viewMode == "nested" || viewMode == "threaded";

		enforce(page >= 1, "Invalid page");
		auto postsPerPage = nested ? int.max : POSTS_PER_PAGE;
		if (nested) page = 1;

		Rfc850Post[] posts;
		foreach (int rowid, string postID, string message; query("SELECT `ROWID`, `ID`, `Message` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC LIMIT ? OFFSET ?").iterate(id, postsPerPage, (page-1)*postsPerPage))
			posts ~= new Rfc850Post(message, postID, rowid);

		Rfc850Post[string] knownPosts;
		foreach (post; posts)
			knownPosts[post.id] = post;

		enforce(posts.length, "Thread not found");

		group = posts[0].xref[0].group;
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
		foreach (int rowid, string id, string parent, string author, string subject, long stdTime; query(ViewSQL).iterate(threadID))
			posts ~= [PostInfo(rowid, id, null, parent, author, subject, SysTime(stdTime, UTC()))].ptr;

		html.put(
			`<table id="thread-index" class="forum-table group-wrapper viewmode-`, encodeEntities(user.get("groupviewmode", "basic")), `">`
			`<tr class="group-index-header"><th><div>Thread overview</div></th></tr>`,
			`<tr><td class="group-threads-cell"><div class="group-threads"><table>`);
		formatThreadedPosts(posts, selectedID);
		html.put(`</table></div></td></tr></table>`);
	}

	void discussionSinglePost(string id, out string group, out string title)
	{
		auto post = getPost(id);
		enforce(post, "Post not found");
		group = post.xref[0].group;
		title = post.subject;

		formatSplitPost(post);
		discussionThreadOverview(post.threadID, id);
	}

	string discussionFirstUnread(string threadID)
	{
		foreach (int rowid, string id; query("SELECT `ROWID`, `ID` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC").iterate(threadID))
			if (!user.isRead(rowid))
				return idToUrl(id);
		return idToUrl(threadID, "thread", getPageCount(getPostCount(threadID), POSTS_PER_PAGE));
	}

	// ***********************************************************************

	bool discussionPostForm(Rfc850Post postTemplate, bool showCaptcha=false, string errorMessage=null)
	{
	    auto info = getGroupInfo(postTemplate.xref[0].group);
	    if (!info)
	    	throw new Exception("Unknown group");
	    if (info.isML)
	    {
			html.put(
				`<table class="forum-table forum-error">`
					`<tr><th>Reply to mailing list</th></tr>`
					`<tr><td class="forum-table-message">`
						`You are viewing a mailing list archive.<br>`
						`For information about posting, visit `
							`<a href="http://lists.puremagic.com/cgi-bin/mailman/listinfo/` ~ info.name ~ `">` ~ info.name ~ `'s Mailman page</a>.`
					`</td></tr>`
				`</table>`);
	    	return false;
	    }
		
		html.put(`<form action="/discussion/send" method="post" class="forum-form" id="postform">`);

		string recaptchaError;
		if (errorMessage.startsWith(RecaptchaErrorPrefix))
		{
			recaptchaError = errorMessage[RecaptchaErrorPrefix.length..$];
			errorMessage = "reCAPTCHA error";
		}

		if (errorMessage)
			html.put(`<div class="form-error">` ~ encodeEntities(errorMessage) ~ `</div>`);

		if (postTemplate.reply)
			html.put(`<input type="hidden" name="parent" value="`, encodeEntities(postTemplate.parentID), `">`);
		else
			html.put(`<input type="hidden" name="where" value="`, encodeEntities(postTemplate.where), `">`);

		html.put(
			`<div id="postform-info">`
				`Posting to <b>`, encodeEntities(postTemplate.where), `</b>`, 
				(postTemplate.reply ? ` in reply to ` ~ postLink(getPostInfo(postTemplate.parentID)) : ``),
			`</div>`
			`<input type="hidden" name="secret" value="`, getUserSecret(), `">`
			`<label for="postform-name">Your name:</label>`
			`<input id="postform-name" name="name" size="40" value="`, encodeEntities(user.get("name", "")), `">`
			`<label for="postform-email">Your e-mail address:</label>`
			`<input id="postform-email" name="email" size="40" value="`, encodeEntities(user.get("email", "")), `">`
			`<label for="postform-subject">Subject:</label>`
			`<input id="postform-subject" name="subject" size="80" value="`, encodeEntities(postTemplate.subject), `">`
			`<label for="postform-text">Message:</label>`
			`<textarea id="postform-text" name="text" rows="25" cols="80">`, encodeEntities(postTemplate.content), `</textarea>`);

		if (showCaptcha)
			html.put(`<div id="postform-captcha">`, recaptchaChallengeHtml(recaptchaError), `</div>`);

		html.put(
			`<input type="submit" value="Send">`
		`</form>`);
		return true;
	}

	SysTime[string] lastPostAttempt;

	PostProcess discussionSend(string[string] vars, string[string] headers)
	{
		Rfc850Post post;
		if ("parent" in vars)
		{
			auto parent = getPost(vars["parent"]);
			enforce(parent, "Can't find post to reply to.");
			post = parent.replyTemplate();
		}
		else
		if ("where" in vars)
			post = Rfc850Post.newPostTemplate(vars["where"]);
		else
			throw new Exception("Sorry, were you saying something?");

		post.author = aaGet(vars, "name");
		post.authorEmail = aaGet(vars, "email");
		post.subject = aaGet(vars, "subject");
		post.setText(aaGet(vars, "text"));

		post.headers["X-Web-User-Agent"] = aaGet(headers, "User-Agent");
		post.headers["X-Web-Originating-IP"] = ip;

		try
		{
			if (aaGet(vars, "secret", "") != getUserSecret())
				throw new Exception("XSRF secret verification failed. Are your cookies enabled?");

			user["name"] = aaGet(vars, "name");
			user["email"] = aaGet(vars, "email");

			bool captchaPresent = recaptchaPresent(vars);

			auto now = Clock.currTime();
			if (!captchaPresent)
			{
				if (ip in lastPostAttempt && now - lastPostAttempt[ip] < dur!"minutes"(1))
				{
					discussionPostForm(post, true, "Your last post was less than a minute ago. Please solve a CAPTCHA to continue.");
					return null;
				}
			}

			auto process = new PostProcess(post, vars, ip, headers);
			lastPostAttempt[ip] = Clock.currTime();
			return process;
		}
		catch (Exception e)
		{
			discussionPostForm(post, false, e.msg);
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

	void discussionPostStatus(PostProcess process, out bool refresh, out bool form)
	{
		refresh = form = false;
		switch (process.status)
		{
			case PostingStatus.SpamCheck:
				discussionPostStatusMessage("Checking for spam...");
				refresh = true;
				return;
			case PostingStatus.Captcha:
				discussionPostStatusMessage("Verifying reCAPTCHA...");
				refresh = true;
				return;
			case PostingStatus.Connecting:
				discussionPostStatusMessage("Connecting to NNTP server...");
				refresh = true;
				return;
			case PostingStatus.Posting:
				discussionPostStatusMessage("Sending message to NNTP server...");
				refresh = true;
				return;
			case PostingStatus.Waiting:
				discussionPostStatusMessage("Message sent.<br>Waiting for message announcement...");
				refresh = true;
				return;

			case PostingStatus.Posted:
				discussionPostStatusMessage(`Message posted!<br><br><a class="forum-unread" href="` ~ encodeEntities(idToUrl(process.post.id)) ~ `">View message</a>`);
				return;

			case PostingStatus.CaptchaFailed:
				discussionPostForm(process.post, true, process.errorMessage);
				form = true;
				return;
			case PostingStatus.SpamCheckFailed:
				discussionPostForm(process.post, true, format("%s. Please solve a CAPTCHA to continue.", process.errorMessage));
				form = true;
				return;
			case PostingStatus.NntpError:
				discussionPostForm(process.post, false, process.errorMessage);
				form = true;
				return;

			default:
				discussionPostStatusMessage("???");
				refresh = true;
				return;
		}
	}

	// ***********************************************************************

	void discussionLoginForm(string[string] parameters, string errorMessage = null)
	{

		html.put(`<form action="/discussion/login" method="post" id="loginform" class="forum-form loginform">`
			`<table class="forum-table">`
				`<tr><th>Log in</th></tr>`
				`<tr><td class="loginform-cell">`);

		if ("url" in parameters)
			html.put(`<input type="hidden" name="url" value="`, encodeEntities(parameters["url"]), `">`);

		html.put(
				`<label for="loginform-username">Username:</label>`
				`<input id="loginform-username" name="username" value="`, encodeEntities(aaGet(parameters, "username", "")), `">`
				`<label for="loginform-password">Password:</label>`
				`<input id="loginform-password" type="password" name="password" value="`, encodeEntities(aaGet(parameters, "password", "")), `">`
				`<input type="submit" value="Log in">`
			`</td></tr>`);
		if (errorMessage)
			html.put(`<tr><td class="loginform-info"><div class="form-error loginform-error">`, encodeEntities(errorMessage), `</div></td></tr>`);
		else
			html.put(
				`<tr><td class="loginform-info">`
					`<a href="/discussion/registerform`,
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
		html.put(`<form action="/discussion/register" method="post" id="registerform" class="forum-form loginform">`
			`<table class="forum-table">`
				`<tr><th>Register</th></tr>`
				`<tr><td class="loginform-cell">`);

		if ("url" in parameters)
			html.put(`<input type="hidden" name="url" value="`, encodeEntities(parameters["url"]), `">`);

		html.put(
			`<label for="loginform-username">Username:</label>`
			`<input id="loginform-username" name="username" value="`, encodeEntities(aaGet(parameters, "username", "")), `">`
			`<label for="loginform-password">Password:</label>`
			`<input id="loginform-password" name="password" value="`, encodeEntities(aaGet(parameters, "password", "")), `">`
			`<input type="submit" value="Register">`
			`</td></tr>`
			`<tr><td class="loginform-info">`);
		if (errorMessage)
			html.put(`<tr><td class="loginform-info"><div class="form-error loginform-error">`, encodeEntities(errorMessage), `</div></td></tr>`);
		else
			html.put(
				`<tr><td class="loginform-info">`
					`Please pick your password carefully.<br>There are no password recovery options.`
				`</td></tr>`);
		html.put(`</table></form>`);
	}

	void discussionRegister(string[string] parameters)
	{
		user.register(aaGet(parameters, "username"), aaGet(parameters, "password"));
	}

	// ***********************************************************************

	string resolvePostUrl(string id)
	{
		foreach (string threadID; query("SELECT `ThreadID` FROM `Posts` WHERE `ID` = ?").iterate(id))
			return idToThreadUrl(id, threadID);

		throw new Exception("Post not found");
	}

	string idToThreadUrl(string id, string threadID)
	{
		return idToUrl(threadID, "thread", indexToPage(getPostThreadIndex(id), POSTS_PER_PAGE)) ~ "#" ~ idToFragment(id);
	}

	Rfc850Post getPost(string id, uint[] partPath = null)
	{
		foreach (int rowid, string message; query("SELECT `ROWID`, `Message` FROM `Posts` WHERE `ID` = ?").iterate(id))
		{
			auto post = new Rfc850Post(message, id, rowid);
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

	struct PostInfo { int rowid; string id, threadID, parentID, author, subject; SysTime time; }
	CachedSet!(string, PostInfo*) postInfoCache;

	PostInfo* getPostInfo(string id)
	{
		return postInfoCache(id, retrievePostInfo(id));
	}

	PostInfo* retrievePostInfo(string id)
	{
		if (id.startsWith('<') && id.endsWith('>'))
			foreach (int rowid, string threadID, string parentID, string author, string subject, long stdTime; query("SELECT `ROWID`, `ThreadID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ID` = ?").iterate(id))
				return [PostInfo(rowid, id, threadID, parentID, author, subject, SysTime(stdTime, UTC()))].ptr;
		return null;
	}

	// ***********************************************************************

	void formatBody(string s)
	{
		auto lines = s.strip().fastSplit('\n');
		bool wasQuoted = false, inSignature = false;
		foreach (line; lines)
		{
			if (line == "-- ")
				inSignature = true;
			auto isQuoted = inSignature || line.startsWith(">");
			if (isQuoted && !wasQuoted)
				html ~= `<span class="forum-quote">`;
			else
			if (!isQuoted && wasQuoted)
				html ~= `</span>`;
			wasQuoted = isQuoted;

			line = encodeEntities(line);
			if (line.contains("://"))
			{
				auto segments = line.segmentByWhitespace();
				foreach (ref segment; segments)
					if (segment.startsWith("http://") || segment.startsWith("https://") || segment.startsWith("ftp://"))
						segment = `<a rel="nofollow" href="` ~ segment ~ `">` ~ segment ~ `</a>`;
				line = segments.join();
			}
			html.put(line, '\n');
		}
		if (wasQuoted)
			html ~= `</span>`;
	}

	string summarizeTime(SysTime time)
	{
		if (!time.stdTime)
			return "-";

		return `<span title="` ~ encodeEntities(formatLongTime(time)) ~ `">` ~ encodeEntities(formatShortTime(time)) ~ `</span>`;
	}

	string formatShortTime(SysTime time)
	{
		if (!time.stdTime)
			return "-";

		string ago(long amount, string units)
		{
			assert(amount > 0);
			return format("%s %s%s ago", amount, units, amount==1 ? "" : "s");
		}

		auto now = Clock.currTime();
		auto duration = now - time;

		if (duration < dur!"seconds"(0))
			return "from the future";
		else
		if (duration < dur!"seconds"(1))
			return "just now";
		else
		if (duration < dur!"minutes"(1))
			return ago(duration.seconds, "second");
		else
		if (duration < dur!"hours"(1))
			return ago(duration.minutes, "minute");
		else
		if (duration < dur!"days"(1))
			return ago(duration.hours, "hour");
		else
		/*if (duration < dur!"days"(2))
			return "yesterday";
		else
		if (duration < dur!"days"(6))
			return formatTime("l", time);
		else*/
		if (duration < dur!"days"(30))
			return ago(duration.total!"days", "day");
		else
		{
			auto diffMonths = now.diffMonths(time);

			if (diffMonths < 12)
				return ago(diffMonths, "month");
			else
				return ago(diffMonths / 12, "year");
				//return time.toSimpleString();
		}
	}

	string formatLongTime(SysTime time)
	{
		return formatTime("l, d F Y, H:i:s e", time);
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

	string truncateString(string s, int maxLength = 30)
	{
		if (s.length <= maxLength)
			return encodeEntities(s);

		import std.ascii;
		int end = maxLength;
		foreach_reverse (p; maxLength-10..maxLength)
			if (isWhite(s[p]))
			{
				end = p+1;
				break;
			}

		return `<span title="`~encodeEntities(s)~`">` ~ encodeEntities(s[0..end] ~ "\&hellip;") ~ `</span>`;
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
		return result.getString();
	}

	private string urlEncode(string s, in char[] forbidden, char escape)
	{
		//  !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
		// " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
		string result;
		foreach (char c; s)
			if (c < 0x20 || c >= 0x7F || forbidden.indexOf(c) >= 0 || c == escape)
				result ~= format("%s%02X", escape, c);
			else
				result ~= c;
		return result;
	}

	private string urlDecode(string encoded)
	{
		string s;
		for (int i=0; i<encoded.length; i++)
			if (encoded[i] == '%')
			{
				s ~= cast(char)fromHex!ubyte(encoded[i+1..i+3]);
				i += 2;
			}
			else
				s ~= encoded[i];
		return s;
	}

	/// Encode a string to one suitable for an HTML anchor
	string encodeAnchor(string s)
	{
		//return encodeUrlParameter(s).replace("%", ".");
		// RFC 3986: " \"#%<>[\\]^`{|}"
		return urlEncode(s, " !\"#$%&'()*+,/;<=>?@[\\]^`{|}~", ':');
	}

	/// Get relative URL to a post ID.
	string idToUrl(string id, string action = "post", int page = 1)
	{
		enforce(id.startsWith('<') && id.endsWith('>'));

		// RFC 3986:
		// pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
		// sub-delims    = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
		// unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
		string path = "/discussion/" ~ action ~ "/" ~ urlEncode(id[1..$-1], " \"#%/<>?[\\]^`{|}", '%');

		assert(page >= 1);
		if (page > 1)
			path ~= "?page=" ~ text(page);

		return path;
	}

	/// Get URL fragment / anchor name for a post on the same page.
	string idToFragment(string id)
	{
		enforce(id.startsWith('<') && id.endsWith('>'));
		return "post-" ~ encodeAnchor(id[1..$-1]);
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
		// TODO: add XSRF security?
		return "/discussion/set?" ~ encodeUrlParameters([name : value, "url" : "__URL__"]);
	}
}

class NotFoundException : Exception
{
	this() { super("The specified resource cannot be found on this server."); }
}

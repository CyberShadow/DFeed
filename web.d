module web;

import std.file;
import std.string;
import std.conv;
import std.exception;
import std.array, std.algorithm;
import std.datetime;

alias std.string.indexOf indexOf;

import ae.net.asockets;
import ae.net.http.server;
import ae.net.http.responseex;
import ae.sys.log;
import ae.utils.xml;
import ae.utils.array;
import ae.utils.time;

import common;
import database;
import cache;
import rfc850;
import user;

class WebUI
{
	Logger log;
	HttpServer server;
	User user;

	this()
	{
		log = createLogger("Web");

		auto port = to!ushort(readText("data/web.txt"));

		server = new HttpServer();
		server.handleRequest = &onRequest;
		server.listen(port);
		log(format("Listening on port %d", port));
	}

	HttpResponse onRequest(HttpRequest request, ClientSocket from)
	{
		StopWatch responseTime;
		responseTime.start();
		scope(exit) log(format("%s - %dms - %s", from.remoteAddress, responseTime.peek().msecs, request.resource));
		auto response = new HttpResponseEx();

		user = User("Cookie" in request.headers ? request.headers["Cookie"] : null);
		scope(success) foreach (cookie; user.getCookies()) response.headers.add("Set-Cookie", cookie);

		string title, content, breadcrumb1, breadcrumb2;
		string[] tools;

		HttpStatusCode status = HttpStatusCode.OK;
		try
		{
			auto pathStr = request.resource;
			enforce(pathStr.length > 1 && pathStr[0] == '/', "Invalid path");
			string[string] parameters;
			if (pathStr.indexOf('?') >= 0)
			{
				int p = pathStr.indexOf('?');
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
							content = discussionIndex();
							break;
						case "group":
						{
							enforce(path.length > 2, "No group specified");
							string group = path[2];
							int page = to!int(aaGet(parameters, "page", "1"));
							string pageStr = page==1 ? "" : format(" (page %d)", page);
							title = group ~ " index" ~ pageStr;
							breadcrumb1 = `<a href="/discussion/group/`~encodeEntities(group)~`">` ~ encodeEntities(group) ~ `</a>` ~ pageStr;
							if (user.get("groupviewmode", "basic") == "basic")
								content = discussionGroup(group, page);
							else
								content = discussionGroupThreaded(group, page);
							//tools ~= viewModeTool(request.resource, ["basic", "threaded"], "group");
							tools ~=
								`<span id="group-view-mode-placeholder" title="` ~
								encodeEntities(viewModeTool(request.resource, ["basic", "vertical-split"], "group")) ~
								`"></span>`;
							break;
						}
						case "thread":
						{
							enforce(path.length > 2, "No thread specified");
							string group, subject;
							content = discussionThread('<' ~ decodeUrlParameter(path[2]) ~ '>', group, subject);
							title = subject;
							breadcrumb1 = `<a href="/discussion/group/` ~encodeEntities(group  )~`">` ~ encodeEntities(group  ) ~ `</a>`;
							breadcrumb2 = `<a href="/discussion/thread/`~encodeEntities(path[2])~`">` ~ encodeEntities(subject) ~ `</a>`;
							tools ~= viewModeTool(request.resource, ["flat", "threaded"], "thread");
							break;
						}
						case "post":
							enforce(path.length > 2, "No post specified");
							if (user.get("groupviewmode", "basic") == "threaded")
							{
								string group, subject;
								content = discussionSinglePost('<' ~ decodeUrlParameter(path[2]) ~ '>', group, subject);
								title = subject;
								breadcrumb1 = `<a href="/discussion/group/` ~encodeEntities(group  )~`">` ~ encodeEntities(group  ) ~ `</a>`;
								breadcrumb2 = `<a href="/discussion/thread/`~encodeEntities(path[2])~`">` ~ encodeEntities(subject) ~ `</a> (view single post)`;
								break;
							}
							else
								return response.redirect(resolvePostUrl('<' ~ decodeUrlParameter(path[2]) ~ '>'));
						case "raw":
						{
							enforce(path.length > 2, "Invalid URL");
							auto post = getPost('<' ~ decodeUrlParameter(path[2]) ~ '>', array(map!(to!uint)(path[3..$])));
							enforce(post, "Post not found");
							if (!post.data && post.error)
								throw new Exception(post.error);
							if (post.fileName)
								response.headers["Content-Disposition"] = `inline; filename="` ~ post.fileName ~ `"`;
							// TODO: is allowing text/html (others?) OK here?
							return response.serveData(Data(post.data), post.mimeType ? post.mimeType : "application/octet-stream");
						}
						case "set":
							foreach (name, value; parameters)
								if (name != "url")
									user[name] = value; // TODO: is this a good idea?
							if ("url" in parameters)
								return response.redirect(parameters["url"]);
							else
								return response.serveText("OK");
						default:
							throw new NotFoundException();
					}
					break;
				}
				default:
					//return response.writeError(HttpStatusCode.NotFound);
					response.cacheForever();
					return response.serveFile(pathStr[1..$], "web/static/");
			}
		}
		catch (Exception e)
		{
			//return response.writeError(HttpStatusCode.InternalServerError, "Unprocessed exception: " ~ e.msg);
			if (cast(NotFoundException) e)
				breadcrumb1 = title = "Not Found";
			else
				breadcrumb1 = title = "Error";
			auto text = encodeEntities(e.msg);
			debug text ~= `<pre>` ~ encodeEntities(e.toString()) ~ `</pre>`;
			content =
				`<table class="forum-table forum-error">` ~
					`<tr><th>` ~ encodeEntities(title) ~ `</th></tr>` ~
					`<tr><td class="forum-table-message">` ~ text ~ `</th></tr>` ~
				`</table>`;
		}

		assert(title && content);
		if (breadcrumb1) breadcrumb1 = "&rsaquo; " ~ breadcrumb1;
		if (breadcrumb2) breadcrumb2 = "&raquo; " ~ breadcrumb2;
		response.disableCache();
		response.serveData(HttpResponseEx.loadTemplate("web/skel.htt", [
			"title" : encodeEntities(title), 
			"content" : content,
			"breadcrumb1" : breadcrumb1,
			"breadcrumb2" : breadcrumb2,
			"tools" : tools.join(" &middot; "),
		]));
		response.setStatus(status);
		return response;
	}

	struct Group { string name, description; }
	struct GroupSet { string name; Group[] groups; }

	/*const*/ GroupSet[] groupHierarchy = [
	{ "D Programming Language", [
		{ "digitalmars.D",	"General discussion of the D programming language." },
		{ "digitalmars.D.announce",	"Announcements for anything D related" },
		{ "digitalmars.D.bugs",	"Bug reports for D compiler and library" },
		{ "digitalmars.D.debugger",	"Debuggers for D" },
		{ "digitalmars.D.dwt",	"Developing the D Widget Toolkit" },
		{ "digitalmars.D.dtl",	"Developing the D Template Library" },
		{ "digitalmars.D.ide",	"Integrated Debugging Environments for D" },
		{ "digitalmars.D.learn",	"Questions about learning D" },
		{ "D.gnu",	"GDC, the Gnu D Compiler " },
		{ "dmd-beta",	"Notify of and discuss beta versions" },
		{ "dmd-concurrency",	"Design of concurrency features in D and library" },
		{ "dmd-internals",	"dmd compiler internal design and implementation" },
		{ "phobos",	"Phobos runtime library design and implementation" },
	]},
	{ "C and C++", [
		{ "c++",	"General discussion of DMC++ compiler" },
		{ "c++.announce",	"Announcements about C++" },
		{ "c++.atl",	"Microsoft's Advanced Template Library" },
		{ "c++.beta",	"Test versions of various C++ products" },
		{ "c++.chat",	"Off topic discussions" },
		{ "c++.command-line",	"Command line tools" },
		{ "c++.dos",	"DMC++ and DOS" },
		{ "c++.dos.16-bits",	"16 bit DOS topics" },
		{ "c++.dos.32-bits",	"32 bit extended DOS topics" },
		{ "c++.idde",	"The Digital Mars Integrated Development and Debugging Environment" },
		{ "c++.mfc",	"Microsoft Foundation Classes" },
		{ "c++.rtl",	"C++ Runtime Library" },
		{ "c++.stl",	"Standard Template Library" },
		{ "c++.stl.hp",	"HP's Standard Template Library" },
		{ "c++.stl.port",	"STLPort Standard Template Librar" },
		{ "c++.stl.sgi",	"SGI's Standard Template Library" },
		{ "c++.stlsoft",	"Stlsoft products" },
		{ "c++.windows",	"Writing C++ code for Microsoft Windows" },
		{ "c++.windows.16-bits",	"16 bit Windows topics" },
		{ "c++.windows.32-bits",	"32 bit Windows topics" },
		{ "c++.wxwindows",	"wxWindows" },
	]},
	{ "Other", [
		{ "DMDScript",	"General discussion of DMDScript" },
		{ "digitalmars.empire",	"General discussion of Empire, the Wargame of the Century " },
		{ "D",	"Retired, use digitalmars.D instead" },
	]}];

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

	string discussionIndex()
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

		return
			`<table id="forum-index" class="forum-table">` ~
			join(array(map!(
				(GroupSet set) { return
					`<tr class="forum-index-set-header"><th colspan="4">` ~ encodeEntities(set.name) ~ `</th></tr>` ~ newline ~
					`<tr class="forum-index-set-captions"><th>Forum</th><th>Last Post</th><th>Threads</th><th>Posts</th>` ~ newline ~
					join(array(map!(
						(Group group) { return `<tr>` ~
							`<td class="forum-index-col-forum"><a href="/discussion/group/` ~ encodeEntities(group.name) ~ `">` ~ encodeEntities(group.name) ~ `</a>` ~
								`<div class="forum-index-description">` ~ encodeEntities(group.description) ~ `</div>` ~
							`</td>` ~
							`<td class="forum-index-col-lastpost">`    ~ (group.name in lastPosts    ? summarizePost(lastPosts[group.name]) : `<div class="forum-no-data">-</div>`) ~ `</td>` ~
							`<td class="forum-index-col-threadcount">` ~ (group.name in threadCounts ? formatNumber(threadCounts[group.name]) : `-`) ~ `</td>` ~
							`<td class="forum-index-col-postcount">`   ~ (group.name in postCounts   ? formatNumber(postCounts[group.name]) : `-`)  ~ `</td>` ~
							`</tr>` ~ newline;
						}
					)(set.groups)));
				}
			)(groupHierarchy))) ~
			`</table>`;
	}

	int[] getThreadPostIndexes(string id)
	{
		int[] result;
		foreach (int rowid; query("SELECT `ROWID` FROM `Posts` WHERE `ThreadID` = ?").iterate(id))
			result ~= rowid;
		return result;
	}

	CachedSet!(string, int[]) threadPostIndexCache;

	string newPostButton(string group)
	{
		return 
			`<form name="new-post-form" method="get" action="/discussion/compose">` ~
				`<div id="new-post-button">` ~
					`<input type="hidden" name="group" value="`~encodeEntities(group)~`">` ~
					`<input type="submit" value="Create thread">` ~
				`</div>` ~
			`</form>`;
	}

	string linkOrNot(string text, string url, bool cond)
	{
		return (cond ? `<a href="`~encodeEntities(url)~`">` : `<span class="disabled-link">`) ~ text ~ (cond ? `</a>` : `</span>`);
	}

	string threadPager(string group, int page)
	{
		auto threadCounts = threadCountCache(getThreadCounts());
		enforce(group in threadCounts, "Empty or unknown group");
		auto threadCount = threadCounts[group];
		auto pageCount = (threadCount + (THREADS_PER_PAGE-1)) / THREADS_PER_PAGE;
		enum PAGER_RADIUS = 4;
		int pagerStart = max(1, page - PAGER_RADIUS);
		int pagerEnd = min(pageCount, page + PAGER_RADIUS);
		string[] pager;
		if (pagerStart > 1)
			pager ~= "&hellip;";
		foreach (pagerPage; pagerStart..pagerEnd+1)
			if (pagerPage == page)
				pager ~= `<b>` ~ text(pagerPage) ~ `</b>`;
			else
				pager ~= `<a href="?page=` ~ text(pagerPage) ~ `">` ~ text(pagerPage) ~ `</a>`;
		if (pagerEnd < pageCount)
			pager ~= "&hellip;";

		return
			`<tr class="group-index-pager"><th colspan="3">` ~ 
				`<div class="pager-left">` ~
					linkOrNot("&laquo; First", "?page=1", page!=1) ~
					`&nbsp;&nbsp;&nbsp;` ~
					linkOrNot("&lsaquo; Prev", "?page=" ~ text(page-1), page>1) ~
				`</div>` ~
				`<div class="pager-right">` ~
					linkOrNot("Next &rsaquo;", "?page=" ~ text(page+1), page<pageCount) ~
					`&nbsp;&nbsp;&nbsp;` ~
					linkOrNot("Last &raquo; ", "?page=" ~ text(pageCount), page!=pageCount) ~
				`</div>` ~
				`<div class="pager-numbers">` ~ pager.join(` `) ~ `</div>` ~
			`</th></tr>`;
	}

	enum THREADS_PER_PAGE = 15;

	string discussionGroup(string group, int page)
	{
		enforce(page >= 1, "Invalid page");

		struct Thread
		{
			PostInfo* _firstPost, _lastPost;
			int postCount, unreadPostCount;

			/// Handle orphan posts
			@property PostInfo* thread() { return _firstPost ? _firstPost : _lastPost; }
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

		foreach (string firstPostID, string lastPostID; query("SELECT `ID`, `LastPost` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?").iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
			foreach (int count; query("SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?").iterate(firstPostID))
				threads ~= Thread(getPostInfo(firstPostID), getPostInfo(lastPostID), count, getUnreadPostCount(firstPostID));

		string summarizeThread(PostInfo* info, bool isRead)
		{
			if (info)
				with (*info)
					return
						`<a class="forum-postsummary-subject ` ~ (isRead ? "forum-read" : "forum-unread") ~ `" href="` ~ encodeEntities(idToUrl(id, "thread")) ~ `">` ~ truncateString(subject, 100) ~ `</a><br>` ~
						`by <span class="forum-postsummary-author">` ~ truncateString(author, 100) ~ `</span><br>`;

			return `<div class="forum-no-data">-</div>`;
		}

		string summarizeLastPost(PostInfo* info)
		{
			// TODO: link?
			if (info)
				with (*info)
					return
						`<span class="forum-postsummary-time">` ~ summarizeTime(time) ~ `</span>` ~
						`by <span class="forum-postsummary-author">` ~ truncateString(author) ~ `</span><br>`;

			return `<div class="forum-no-data">-</div>`;
		}

		string summarizePostCount(ref Thread thread)
		{
			if (thread.unreadPostCount == 0)
				return formatNumber(thread.postCount-1);
			else
			if (thread.unreadPostCount == thread.postCount)
				return `<b>` ~ formatNumber(thread.postCount-1) ~ `</b>`;
			else
				return
					`<b>` ~ formatNumber(thread.postCount-1) ~ `</b>` ~
					`<br>(` ~ formatNumber(thread.unreadPostCount) ~ ` new)`;
		}

		return
			`<table id="group-index" class="forum-table">` ~
			`<tr class="group-index-header"><th colspan="3"><div>` ~ newPostButton(group) ~ encodeEntities(group) ~ `</div></th></tr>` ~ newline ~
			`<tr class="group-index-captions"><th>Thread / Thread Starter</th><th>Last Post</th><th>Replies</th>` ~ newline ~
			join(array(map!(
				(Thread thread) { return `<tr>` ~
					`<td class="group-index-col-first">` ~ summarizeThread(thread.thread, thread.isRead) ~ `</td>` ~
					`<td class="group-index-col-last">`  ~ summarizeLastPost(thread.lastPost) ~ `</td>` ~
					`<td class="group-index-col-replies">`  ~ summarizePostCount(thread) ~ `</td>` ~
					`</tr>` ~ newline;
				}
			)(threads))) ~
			threadPager(group, page) ~
			`</table>`;
	}

	string[][string] referenceCache; // invariant

	string discussionGroupThreaded(string group, int page)
	{
		enum OFFSET_INIT = 4;
		enum OFFSET_QTY = 8;
		enum OFFSET_UNITS = "px";
		
		enforce(page >= 1, "Invalid page");

		struct Post
		{
			int rowid;
			string id, parent, author, subject;
			SysTime time;
			Post*[] children;
		}

		Post[string] posts;
		//foreach (string threadID; query("SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?").iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
		//	foreach (string id, string parent, string author, string subject, long stdTime; query("SELECT `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` = ?").iterate(threadID))
		enum ViewSQL = "SELECT `ROWID`, `ID`, `ParentID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ThreadID` IN (SELECT `ID` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?)";
		foreach (int rowid, string id, string parent, string author, string subject, long stdTime; query(ViewSQL).iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
			posts[id] = Post(rowid, id, parent, author, subject, SysTime(stdTime, UTC()));

		posts[null] = Post();
		foreach (ref post; posts)
			if (post.id)
			{
				auto parent = post.parent;
				if (parent !in posts) // mailing-list users
				{
					if (post.id !in referenceCache)
						referenceCache[post.id] = getPost(post.id).references;
					parent = null;
					foreach_reverse (reference; referenceCache[post.id])
						if (reference in posts)
						{
							parent = reference;
							break;
						}
				}
				posts[parent].children ~= &post;
			}

		foreach (ref post; posts)
			sort!"a.time < b.time"(post.children);

		string formatPosts(Post*[] posts, int level, string parentSubject)
		{
			string formatPost(Post* post, int level)
			{
				return
					`<tr><td style="padding-left: `~text(OFFSET_INIT + level * OFFSET_QTY)~OFFSET_UNITS~`">` ~
						`<a class="` ~ (user.isRead(post.rowid) ? "forum-read" : "forum-unread" ) ~ `" href="` ~ idToUrl(post.id) ~ `">` ~ encodeEntities(post.author) ~ `</a>` ~
					`</td><td>` ~ summarizeTime(post.time) ~ `</td></tr>` ~
					formatPosts(post.children, level+1, post.subject);
			}

			return
				array(map!((Post* post) {
					if (post.subject != parentSubject)
						return
							`<tr><td colspan="2" style="padding-left: `~text(OFFSET_INIT + level * OFFSET_QTY)~OFFSET_UNITS~`">` ~
							`<table class="thread-start">` ~
								`<tr><th colspan="2">` ~ encodeEntities(post.subject) ~ `</th></tr>` ~
								formatPost(post, 0) ~
							`</table>` ~
							`</td></tr>`;
					else
						return formatPost(post, level);
				})(posts)).join();
		}

		return
			`<table id="group-index" class="forum-table group-threads">` ~
			`<tr class="group-index-header"><th colspan="2"><div>` ~ newPostButton(group) ~ encodeEntities(group) ~ `</div></th></tr>` ~ newline ~
			//`<tr class="group-index-captions"><th>Subject / Author</th><th>Time</th>` ~ newline ~
			//`<tr><td colspan="2" id="group-threads">` ~
			formatPosts(posts[null].children, 0, "Root post\n") ~ // hack: force subject header for new posts (\n can't appear in a subject)
			//`</td></tr>` ~
			threadPager(group, page) ~
			`</table>`;
	}

	string formatPost(Rfc850Post post, Rfc850Post[string] knownPosts)
	{
		string replyButton =
			`<form name="reply-form" method="get" action="/discussion/reply">` ~
				`<div class="reply-button">` ~
					`<input type="hidden" name="parent" value="`~encodeEntities(post.id)~`">` ~
					`<input type="submit" value="Reply">` ~
				`</div>` ~
			`</form>`;

		import std.md5;
		string gravatarHash = toLower(getDigestString(strip(toLower(post.authorEmail))));

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
					link = `` ~ idToUrl(parent.id);
				}
			}

			if (author && link)
				infoBits ~= `Posted in reply to <a href="` ~ encodeEntities(link) ~ `">` ~ encodeEntities(author) ~ `</a>`;
		}

		string[] partList;
		void visitParts(Rfc850Post[] parts, int[] path)
		{
			foreach (i, part; parts)
			{
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
				visitParts(part.parts, path~i);
			}
		}
		visitParts(post.parts, null);
		if (partList.length)
			infoBits ~=
				`Attachments:<ul class="post-info-parts"><li>` ~ partList.join(`</li><li>`) ~ `</li></ul>`;

		if (knownPosts is null && post.threadID)
			infoBits ~=
				`<a href="` ~ encodeEntities(idToThreadUrl(post.id, post.threadID)) ~ `">View in thread</a>`;

		string repliesTitle = `Replies to `~encodeEntities(post.author)~`'s post from `~encodeEntities(formatShortTime(post.time));

		scope(success) user.setRead(post.rowid, true);

		with (post)
			return
				`<div class="post-wrapper">`
				`<table class="post forum-table` ~ (children ? ` with-children` : ``) ~ `" id="` ~ encodeEntities(idToFragment(id)) ~ `">` ~
				`<tr class="post-header"><th colspan="2">` ~ 
					`<div class="post-time">` ~ summarizeTime(time) ~ `</div>` ~
					`<a title="Permanent link to this post" href="` ~ idToUrl(id) ~ `" class="` ~ (user.isRead(rowid) ? "forum-read" : "forum-unread") ~ `">` ~
						encodeEntities(realSubject) ~
					`</a>` ~
				`</th></tr>` ~
				`<tr>` ~
					`<td class="post-info">` ~
						`<div class="post-author">` ~ encodeEntities(author) ~ `</div>` ~
						`<a href="http://www.gravatar.com/` ~ gravatarHash ~ `" title="` ~ encodeEntities(author) ~ `'s Gravatar profile">` ~
							`<img alt="Gravatar" class="post-gravatar" width="80" height="80" src="http://www.gravatar.com/avatar/` ~ gravatarHash ~ `?d=identicon">` ~
						`</a><br>` ~
						(infoBits.length ?
							`<hr>` ~
							array(map!q{ `<div class="post-info-bit">` ~ a ~ `</div>` }(infoBits)).join()
						: ``) ~
						`<br><br>` ~ // guarantee space for the "toolbar"
						`<div class="post-toolbar">` ~ replyButton ~ `</div>`
					`</td>` ~
					`<td class="post-body">` ~
						`<div>` ~ formatBody(content) ~ `</div>` ~
						(error ? `<span class="post-error">` ~ encodeEntities(error) ~ `</span>` : ``) ~
					`</td>` ~
				`</tr>` ~
				`</table>` ~
				`</div>` ~
				(children ?
					`<table class="post-nester"><tr>` ~
					`<td class="post-nester-bar" title="` ~ /* for IE */ repliesTitle ~ `">` ~
						`<a href="#` ~ encodeEntities(idToFragment(id)) ~ `" ` ~
							`title="` ~ repliesTitle ~ `"></a>` ~
					`</td>` ~
					`<td>` ~ join(array(map!((Rfc850Post post) { return formatPost(post, knownPosts); })(children))) ~ `</td>`
					`</tr></table>`
				: ``);
	}

	string discussionThread(string id, out string group, out string title)
	{
		// TODO: pages?
		Rfc850Post[] posts;
		foreach (int rowid, string postID, string message; query("SELECT `ROWID`, `ID`, `Message` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC").iterate(id))
			posts ~= new Rfc850Post(message, postID, rowid);

		Rfc850Post[string] knownPosts;
		foreach (post; posts)
			knownPosts[post.id] = post;

		enforce(posts.length, "Thread not found");

		group = posts[0].xref[0].group;
		title = posts[0].subject;
		bool threaded = user.get("threadviewmode", "flat") == "threaded";

		if (threaded)
			posts = Rfc850Post.threadify(posts);
		return
			`<div id="forum-posts">` ~
			join(array(map!((Rfc850Post post) { return formatPost(post, knownPosts); })(posts))) ~
			`</div>`;
	}

	string discussionSinglePost(string id, out string group, out string title)
	{
		auto post = getPost(id);
		enforce(post, "Post not found");
		group = post.xref[0].group;
		title = post.subject;

		return
			`<div id="forum-posts">` ~
			formatPost(post, null) ~
			`</div>`;
	}

	string resolvePostUrl(string id)
	{
		foreach (string threadID; query("SELECT `ThreadID` FROM `Posts` WHERE `ID` = ?").iterate(id))
			return idToThreadUrl(id, threadID);

		throw new Exception("Post not found");
	}

	string idToThreadUrl(string id, string threadID)
	{
		return idToUrl(threadID, "thread") ~ "#" ~ idToFragment(id);
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

	struct PostInfo { int rowid; string id, author, subject; SysTime time; }
	CachedSet!(string, PostInfo*) postInfoCache;

	PostInfo* getPostInfo(string id)
	{
		return postInfoCache(id, retrievePostInfo(id));
	}

	PostInfo* retrievePostInfo(string id)
	{
		if (id.startsWith('<') && id.endsWith('>'))
			foreach (int rowid, string author, string subject, long stdTime; query("SELECT `ROWID`, `Author`, `Subject`, `Time` FROM `Posts` WHERE `ID` = ?").iterate(id))
				return [PostInfo(rowid, id, author, subject, SysTime(stdTime, UTC()))].ptr;
		return null;
	}

	string formatBody(string text)
	{
		auto lines = text.strip().split("\n");
		bool wasQuoted = false, inSignature = false;
		text = null;
		foreach (i, line; lines)
		{
			if (line == "-- ")
				inSignature = true;
			auto isQuoted = (inSignature || line.startsWith(">")) && (i != lines.length-1);
			if (isQuoted && !wasQuoted)
				text ~= `<span class="forum-quote">`;
			else
			if (!isQuoted && wasQuoted)
				text ~= `</span>`;
			wasQuoted = isQuoted;
			text ~= encodeEntities(line) ~ "\n";
		}
		return text.chomp();
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
		auto diffMonths = now.diffMonths(time);

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
		if (diffMonths < 12)
			return ago(diffMonths, "month");
		else
			return ago(diffMonths / 12, "year");
			//return time.toSimpleString();
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

	/// &apos; is not a recognized entity in HTML 4 (even though it is in XML and XHTML).
	string encodeEntities(string s)
	{
		return ae.utils.xml.encodeEntities(s).replace("&apos;", "'");
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

	/// Encode a string to one suitable for an HTML anchor
	string encodeAnchor(string s)
	{
		//return encodeUrlParameter(s).replace("%", ".");
		// RFC 3986: " \"#%<>[\\]^`{|}"
		return urlEncode(s, " !\"#$%&'()*+,/;<=>?@[\\]^`{|}~", ':');
	}

	/// Get relative URL to a post ID.
	string idToUrl(string id, string action = "post")
	{
		enforce(id.startsWith('<') && id.endsWith('>'));

		// RFC 3986:
		// pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
		// sub-delims    = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
		// unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
		return "/discussion/" ~ action ~ "/" ~ urlEncode(id[1..$-1], " \"#%/<>?[\\]^`{|}", '%');
	}

	/// Get URL fragment / anchor name for a post on the same page.
	string idToFragment(string id)
	{
		enforce(id.startsWith('<') && id.endsWith('>'));
		return "post-" ~ encodeAnchor(id[1..$-1]);
	}

	string viewModeTool(string currentPath, string[] modes, string what)
	{
		auto currentMode = user.get(what ~ "viewmode", modes[0]);
		return "View mode: " ~
			array(map!((string mode) {
				return mode == currentMode
					? `<span class="viewmode-active" title="Viewing in ` ~ mode ~ ` mode">` ~ mode ~ `</span>`
					: `<a title="Switch to ` ~ mode ~ ` ` ~ what ~ ` view mode" href="` ~ encodeEntities(setOptionLink(what ~ "viewmode", mode, currentPath)) ~ `">` ~ mode ~ `</a>`;
			})(modes)).join(" / ");
	}

	/// Generate a link to set a user preference
	string setOptionLink(string name, string value, string currentPath)
	{
		// TODO: add XSRF security?
		return "/discussion/set?" ~ encodeUrlParameters([name : value, "url" : currentPath]);
	}
}

class NotFoundException : Exception
{
	this() { super("The specified resource cannot be found on this server."); }
}

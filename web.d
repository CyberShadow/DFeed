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
							content = discussionGroup(group, page);
							break;
						}
						case "thread":
						{
							enforce(path.length > 2, "No thread specified");
							string group, subject;
							content = discussionThread(decodeUrlParameter(path[2]), group, subject);
							title = subject;
							breadcrumb1 = `<a href="/discussion/group/` ~encodeEntities(group  )~`">` ~ encodeEntities(group  ) ~ `</a>`;
							breadcrumb2 = `<a href="/discussion/thread/`~encodeEntities(path[2])~`">` ~ encodeEntities(subject) ~ `</a>`;
							tools ~= viewModeTool(pathStr);
							break;
						}
						case "post":
							enforce(path.length > 2, "No post specified");
							return response.redirect(resolvePostUrl(decodeUrlParameter(path[2])));
						case "set":
							foreach (name, value; parameters)
								if (name != "url")
									user[name] = value; // TODO: is this a good idea?
							if ("url" in parameters)
								return response.redirect(parameters["url"]);
							else
								return response.serveText("OK");
						default:
							return response.writeError(HttpStatusCode.NotFound);
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
			content =
				`<table class="forum-table forum-error">` ~
					`<tr><th>` ~ encodeEntities(title) ~ `</th></tr>` ~
					`<tr><td class="forum-table-message">` ~ encodeEntities(e.msg) ~ `</th></tr>` ~
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
						`<a class="forum-postsummary-subject" href="/discussion/post/` ~ encodeEntities(encodeUrlParameter(id[1..$-1])) ~ `">` ~ truncateString(subject) ~ `</a><br>` ~
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

	string discussionGroup(string group, int page)
	{
		enum THREADS_PER_PAGE = 25;

		enforce(page >= 1, "Invalid page");

		struct Thread
		{
			PostInfo* _firstPost, _lastPost;
			int postCount;

			/// Handle orphan posts
			@property PostInfo* thread() { return _firstPost ? _firstPost : _lastPost; }
			@property PostInfo* lastPost() { return _lastPost; }
		}
		Thread[] threads;

		foreach (string firstPostID, string lastPostID; query("SELECT `ID`, `LastPost` FROM `Threads` WHERE `Group` = ? ORDER BY `LastUpdated` DESC LIMIT ? OFFSET ?").iterate(group, THREADS_PER_PAGE, (page-1)*THREADS_PER_PAGE))
			foreach (int count; query("SELECT COUNT(*) FROM `Posts` WHERE `ThreadID` = ?").iterate(firstPostID))
				threads ~= Thread(getPostInfo(firstPostID), getPostInfo(lastPostID), count);

		string summarizeThread(PostInfo* info)
		{
			if (info)
				with (*info)
					return
						`<a class="forum-postsummary-subject" href="/discussion/thread/` ~ encodeEntities(encodeUrlParameter(id[1..$-1])) ~ `">` ~ truncateString(subject, 100) ~ `</a><br>` ~
						`by <span class="forum-postsummary-author">` ~ truncateString(author, 100) ~ `</span><br>`;

			return `<div class="forum-no-data">-</div>`;
		}

		string summarizeLastPost(PostInfo* info)
		{
			if (info)
				with (*info)
					return
						`<span class="forum-postsummary-time">` ~ summarizeTime(time) ~ `</span>` ~
						`by <span class="forum-postsummary-author">` ~ truncateString(author) ~ `</span><br>`;

			return `<div class="forum-no-data">-</div>`;
		}

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

		string linkOrNot(string text, string url, bool cond)
		{
			return (cond ? `<a href="`~encodeEntities(url)~`">` : `<span class="disabled-link">`) ~ text ~ (cond ? `</a>` : `</span>`);
		}

		string newPostButton =
			`<form name="new-post-form" method="get" action="/discussion/compose">` ~
				`<div id="new-post-button">` ~
					`<input type="hidden" name="group" value="`~encodeEntities(group)~`">` ~
					`<input type="submit" value="Create thread">` ~
				`</div>` ~
			`</form>`;

		return
			`<table id="group-index" class="forum-table">` ~
			`<tr class="group-index-header"><th colspan="3"><div>` ~ newPostButton ~ encodeEntities(group) ~ `</div></th></tr>` ~ newline ~
			`<tr class="group-index-captions"><th>Thread / Thread Starter</th><th>Last Post</th><th>Replies</th>` ~ newline ~
			join(array(map!(
				(Thread thread) { return `<tr>` ~
					`<td class="group-index-col-first">` ~ summarizeThread(thread.thread) ~ `</td>` ~
					`<td class="group-index-col-last">`  ~ summarizeLastPost(thread.lastPost) ~ `</td>` ~
					`<td class="group-index-col-replies">`  ~ formatNumber(thread.postCount-1) ~ `</td>` ~
					`</tr>` ~ newline;
				}
			)(threads))) ~
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
			`</th></tr>` ~ newline ~
			`</table>`;
	}

	string discussionThread(string id, out string group, out string title)
	{
		id = `<` ~ id ~ `>`;

		// TODO: pages?
		Rfc850Post[] posts;
		foreach (string postID, string message; query("SELECT `ID`, `Message` FROM `Posts` WHERE `ThreadID` = ? ORDER BY `Time` ASC").iterate(id))
			posts ~= new Rfc850Post(message, postID);

		Rfc850Post[string] knownPosts;
		foreach (post; posts)
			knownPosts[post.id] = post;

		enforce(posts.length, "Thread not found");

		group = posts[0].xref[0].group;
		title = posts[0].subject;
		bool threaded = user.get("viewmode", "flat") == "threaded";

		string formatPost(Rfc850Post post)
		{
			string replyButton =
				`<form name="reply-form" method="get" action="/discussion/reply">` ~
					`<div id="reply-button">` ~
						`<input type="hidden" name="parent" value="`~encodeEntities(post.id)~`">` ~
						`<input type="submit" value="Reply">` ~
					`</div>` ~
				`</form>`;

			import std.md5;
			string gravatarHash = toLower(getDigestString(strip(toLower(post.authorEmail))));

			string inReplyTo;
			if (post.parentID)
			{
				string author, link;
				if (post.parentID in knownPosts)
				{
					auto parent = knownPosts[post.parentID];
					author = parent.author;
					link = `#post-` ~ encodeAnchor(parent.id[1..$-1]);
				}
				else
				{
					auto parent = getPostInfo(post.parentID);
					if (parent)
					{
						author = parent.author;
						link = `/discussion/post/` ~ encodeUrlParameter(parent.id[1..$-1]);
					}
				}

				if (author && link)
					inReplyTo = ` in reply to <a href="` ~ encodeEntities(link) ~ `">` ~ encodeEntities(author) ~ `</a>`;
			}

			with (post)
				return
					`<table class="post forum-table` ~ (children ? ` with-children` : ``) ~ `" id="post-`~encodeAnchor(id[1..$-1])~`">` ~
					`<tr class="post-header"><th colspan="2">` ~ 
						`<div class="post-time">` ~ summarizeTime(time) ~ `</div>` ~
						`<a title="Permanent link to this post" href="/discussion/post/` ~ encodeUrlParameter(id[1..$-1]) ~ `">` ~
							encodeEntities(realSubject) ~
						`</a>` ~
					`</th></tr>` ~
					`<tr>` ~
						`<td class="post-info">` ~
							`<div class="post-author">` ~ encodeEntities(author) ~ `</div>` ~
							`<a href="http://www.gravatar.com/` ~ gravatarHash ~ `">` ~
								`<img alt="Gravatar" class="post-gravatar" width="80" height="80" src="http://www.gravatar.com/avatar/` ~ gravatarHash ~ `?d=identicon">` ~
							`</a><br>` ~
							`<hr>` ~
							/*`Posted on ` ~ formatLongTime(time) ~ inReplyTo ~ `<br>` ~*/
							(inReplyTo ? `Posted` ~ inReplyTo ~ `<br>` : ``) ~
							`<br><br>` ~ // guarantee space for the "toolbar"
							`<div class="post-toolbar">` ~ replyButton ~ `</div>`
						`</td>` ~
						`<td class="post-body">` ~
							`<div>` ~ formatBody(content) ~ `</div>` ~
						`</td>` ~
					`</tr>` ~
					`</table>` ~
					(children ?
						`<table class="post-nester"><tr>` ~
						`<td class="post-nester-bar">` ~
							`<a href="#post-`~encodeAnchor(id[1..$-1])~`" ` ~
								`title="Replies to `~encodeEntities(author)~`'s post from `~encodeEntities(formatShortTime(time))~`"></a>` ~
						`</td>` ~
						`<td>` ~ join(array(map!formatPost(children))) ~ `</td>`
						`</tr></table>`
					: ``);
		}
		if (threaded)
			posts = Rfc850Post.threadify(posts);
		return
			`<div id="forum-posts">` ~
			join(array(map!formatPost(posts))) ~
			`</div>`;
	}

	string resolvePostUrl(string id)
	{
		foreach (string threadID; query("SELECT `ThreadID` FROM `Posts` WHERE `ID` = ?").iterate(`<` ~ id ~ `>`))
			return "/discussion/thread/" ~ encodeUrlParameter(threadID[1..$-1]) ~ "#post-" ~ encodeAnchor(id);

		throw new Exception("Post not found");
	}

	struct PostInfo { string id, author, subject; SysTime time; }
	CachedSet!(string, PostInfo*) postInfoCache;

	PostInfo* getPostInfo(string id)
	{
		return postInfoCache(id, retrievePostInfo(id));
	}

	PostInfo* retrievePostInfo(string id)
	{
		if (id.startsWith('<') && id.endsWith('>'))
			foreach (string author, string subject, long stdTime; query("SELECT `Author`, `Subject`, `Time` FROM `Posts` WHERE `ID` = ?").iterate(id))
				return [PostInfo(id, author, subject, SysTime(stdTime, UTC()))].ptr;
		return null;
	}

	string formatBody(string text)
	{
		auto lines = text.split("\n");
		bool wasQuoted = false, inSignature = false;
		text = null;
		foreach (line; lines)
		{
			if (line == "-- ")
				inSignature = true;
			auto isQuoted = inSignature || line.startsWith(">");
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

	/// Encode a string to one suitable for an HTML anchor
	string encodeAnchor(string s)
	{
		return encodeUrlParameter(s).replace("%", ".");
	}

	string viewModeTool(string currentPath)
	{
		enum modes = ["flat", "threaded"];
		auto currentMode = user.get("viewmode", modes[0]);
		return "View mode: " ~
			array(map!((string mode) {
				return mode == currentMode
					? `<span class="viewmode-active" title="Viewing in ` ~ mode ~ ` mode">` ~ mode ~ `</span>`
					: `<a title="Switch to ` ~ mode ~ ` view mode" href="` ~ encodeEntities(setOptionLink("viewmode", mode, currentPath)) ~ `">` ~ mode ~ `</a>`;
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

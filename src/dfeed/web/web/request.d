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

/// Handling/routing of HTTP requests and global HTML structure.
module dfeed.web.web.request;

import std.algorithm.iteration : map, filter, map;
import std.algorithm.searching : startsWith, canFind, skipOver, endsWith, findSplit;
import std.array : split, join, array, replace;
import std.conv : to, text;
import std.exception : enforce;
import std.file : readText;
import std.format : format;
import std.functional : not;
import std.uni : icmp, toLower;

import dfeed.common;
import dfeed.database : query;
import dfeed.groups : GroupInfo, groupHierarchy, getGroupInfoByUrl, getGroupInfo;
import dfeed.message : idToUrl, urlDecode, urlEncodeMessageUrl, getGroup;
import dfeed.sinks.messagedb : threadID, searchTerm;
import dfeed.sinks.subscriptions;
import dfeed.site : site;
import dfeed.sources.github;
import dfeed.web.list;
import dfeed.web.posting : postProcesses;
import dfeed.web.user : User, getUser;
import dfeed.web.web;
import dfeed.web.web.draft : getDraft, draftToPost, newPostDraft, newReplyDraft, autoSaveDraft;
import dfeed.web.web.part.gravatar;
import dfeed.web.web.part.pager : getPageOffset, POSTS_PER_PAGE;
import dfeed.web.web.posting : discussionPostForm, discussionSend, discussionPostStatus;
import dfeed.web.web.statics : optimizedPath, serveFile, makeBundle, staticPath, createBundles, createBundles;
import dfeed.web.web.user : user, userSettings;
import dfeed.web.web.view.index : discussionIndex;
import dfeed.web.web.view.login : discussionLoginForm, discussionRegisterForm, discussionLogin, discussionRegister;
import dfeed.web.web.view.group : discussionGroup, discussionGroupThreaded, discussionGroupSplit, discussionGroupVSplit, discussionGroupSplitFromPost, discussionGroupVSplitFromPost;
import dfeed.web.web.view.moderation : discussionDeleteForm, deletePost, deletePostApi, discussionFlagPage, discussionApprovePage;
import dfeed.web.web.view.widgets;
import dfeed.web.web.view.post : discussionSplitPost, discussionVSplitPost, discussionSinglePost;
import dfeed.web.web.view.settings : discussionSettings, discussionSubscriptionEdit;
import dfeed.web.web.view.subscription : discussionSubscriptionPosts, discussionSubscriptionUnsubscribe;
import dfeed.web.web.view.thread : getPostAtThreadIndex, discussionThread, discussionFirstUnread;

import ae.net.http.common : HttpRequest, HttpResponse, HttpStatusCode;
import ae.net.http.responseex : HttpResponseEx;
import ae.net.http.server : HttpServerConnection;
import ae.net.ietf.url : UrlParameters, decodeUrlParameters, encodeUrlParameter;
import ae.sys.data : Data;
import ae.utils.array;
import ae.utils.digest;
import ae.utils.exception;
import ae.utils.json : toJson;
import ae.utils.meta : I;
import ae.utils.regex : re;
import ae.utils.text : indexOf;
import ae.utils.text.html : encodeHtmlEntities;

HttpRequest currentRequest;
string ip;

void onRequest(HttpRequest request, HttpServerConnection conn)
{
	conn.sendResponse(handleRequest(request, conn));
}

HttpResponse handleRequest(HttpRequest request, HttpServerConnection conn)
{
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
	if (host != site.host && host != "localhost" && site.host != "localhost" && ip != "127.0.0.1" && !request.resource.startsWith("/.well-known/acme-challenge/"))
		return response.redirect(site.proto ~ "://" ~ site.host ~ request.resource, HttpStatusCode.MovedPermanently);

	// Redirect to HTTPS
	if (site.proto == "https" && request.headers.get("X-Scheme", "") == "http")
		return response.redirect("https://" ~ site.host ~ request.resource, HttpStatusCode.MovedPermanently);

	auto canonicalHeader =
		`<link rel="canonical" href="`~site.proto~`://`~site.host~request.resource~`"/>`;
	enum horizontalSplitHeaders =
		`<link rel="stylesheet" href="//fonts.googleapis.com/css?family=Open+Sans:400,600">`;

	void addMetadata(string description, string canonicalLocation, string image)
	{
		assert(title, "No title for metadata");

		if (!description)
			description = site.name;

		if (!image)
			image = "https://dlang.org/images/dlogo_opengraph.png";

		auto canonicalURL = site.proto ~ "://" ~ site.host ~ canonicalLocation;

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
				if (message is null)
				{
					auto slug = urlDecode(path[1]);
					if (slug.skipOver("draft-") && slug.endsWith("@" ~ site.host))
					{
						auto did = slug.skipUntil("@");
						auto draft = getDraft(did);
						auto post = draftToPost(draft);
						post.compile();
						message = post.message;
					}
				}
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
			case "approve-moderated-draft":
			{
				enforce(user.getLevel() >= User.Level.canApproveDrafts, "You can't approve moderated drafts");
				title = "Approving moderated draft";
				enforce(path.length == 2 || path.length == 3, "Wrong URL format"); // Backwards compatibility with old one-click URLs
				auto draftID = path[1];
				discussionApprovePage(draftID, request.method == "POST" ? request.decodePostData() : UrlParameters.init);
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
								case "about" : return site.about;
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

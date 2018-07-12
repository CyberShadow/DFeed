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

/// Post draft utility code.
module dfeed.web.web.draft;

import std.conv : to;
import std.datetime.systime : Clock;

import ae.net.ietf.headers : Headers;
import ae.net.ietf.url : UrlParameters;
import ae.utils.json : toJson, jsonParse;
import ae.utils.text : randomString;

import dfeed.database : query;
import dfeed.groups : GroupInfo;
import dfeed.message : Rfc850Post;
import dfeed.web.posting : PostDraft, PostProcess;
import dfeed.web.web.postinfo : getPost;
import dfeed.web.web.user : user, userSettings;

void createDraft(PostDraft draft)
{
	query!"INSERT INTO [Drafts] ([ID], [UserID], [Status], [ClientVars], [ServerVars], [Time]) VALUES (?, ?, ?, ?, ?, ?)"
		.exec(draft.clientVars["did"], userSettings.id, int(draft.status), draft.clientVars.toJson, draft.serverVars.toJson, Clock.currTime.stdTime);
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
		return PostDraft(status.to!(PostDraft.Status), jsonParseUrlParameters(clientVars), parse!(string[string])(serverVars));
	throw new Exception("Can't find this message draft");
}

void saveDraft(PostDraft draft)
{
	auto draftID = draft.clientVars.get("did", null);
	auto postID = draft.serverVars.get("pid", null);
	query!"UPDATE [Drafts] SET [PostID]=?, [ClientVars]=?, [ServerVars]=?, [Time]=?, [Status]=? WHERE [ID] == ?"
		.exec(postID, draft.clientVars.toJson, draft.serverVars.toJson, Clock.currTime.stdTime, int(draft.status), draftID);
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

Rfc850Post draftToPost(PostDraft draft, Headers headers = Headers.init, string ip = null)
{
	auto parent = "parent" in draft.serverVars ? getPost(draft.serverVars["parent"]) : null;
	return PostProcess.createPost(draft, headers, ip, parent);
}

﻿/*  Copyright (C) 2015, 2016, 2017, 2018  Vladimir Panteleev <vladimir@thecybershadow.net>
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

module dfeed.sinks.subscriptions;

import std.algorithm;
import std.ascii;
import std.exception;
import std.format;
import std.process;
import std.regex;
import std.string;
import std.typecons;
import std.typetuple;

import ae.net.ietf.url : UrlParameters;
import ae.sys.log;
import ae.sys.timing;
import ae.utils.array;
import ae.utils.json;
import ae.utils.meta;
import ae.utils.regex;
import ae.utils.text;
import ae.utils.textout;
import ae.utils.time;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.common;
import dfeed.database;
import dfeed.groups;
import dfeed.message;
import dfeed.site;
import dfeed.sinks.irc;
import dfeed.sinks.messagedb : threadID;
import dfeed.web.user;
import dfeed.web.web : getPost;

void log(string s)
{
	static Logger log;
	(log ? log : (log=createLogger("Subscription")))(s);
}

struct Subscription
{
	string userName, id;
	Trigger trigger;
	Action[] actions;

	this(string userName, UrlParameters data)
	{
		this.userName = userName;
		this.id = data.get("id", null);
		this.trigger = getTrigger(userName, data);
		this.actions = getActions(userName, data);
	}

	@property FormSection[] sections() { return cast(FormSection[])[trigger] ~ cast(FormSection[])actions; }

	void save()
	{
		assert(id, "No subscription ID");
		assert(userName, "No subscription username");

		foreach (section; sections)
			section.validate();

		UrlParameters data;
		data["id"] = id;
		data["trigger-type"] = trigger.type;

		foreach (section; sections)
			section.serialize(data);

		{
			mixin(DB_TRANSACTION);
			query!"INSERT OR REPLACE INTO [Subscriptions] ([ID], [Username], [Data]) VALUES (?, ?, ?)"
				.exec(id, userName, SubscriptionData(data).toJson());
			foreach (section; sections)
				section.save();
		}
	}

	void remove()
	{
		mixin(DB_TRANSACTION);
		foreach (section; sections)
			section.cleanup();
		query!`DELETE FROM [Subscriptions] WHERE [ID] = ?`.exec(id);
	}

	void unsubscribe()
	{
		foreach (action; actions)
			action.unsubscribe();
		save();
	}

	void runActions(Rfc850Post post)
	{
		log("Running subscription %s (%s trigger) actions for post %s".format(id, trigger.type, post.id));
		string name = getUserSetting(userName, "name");
		string email = getUserSetting(userName, "email");
		if ((name  && !icmp(name, post.author))
		 || (email && !icmp(email, post.authorEmail)))
		{
			log("Post created by author, ignoring");
			return;
		}

		foreach (action; actions)
			action.run(this, post);
	}

	int getUnreadCount()
	{
		auto user = new RegisteredUser(userName);
		int count = 0;
		foreach (int rowid; query!"SELECT [MessageRowID] FROM [SubscriptionPosts] WHERE [SubscriptionID] = ?".iterate(id))
			if (!user.isRead(rowid))
				count++;
		return count;
	}
}

/// POD serialization type to avoid depending on UrlParameters internals
struct SubscriptionData
{
	string[][string] items;
	this(UrlParameters parameters) { items = parameters.items; }
	@property UrlParameters data() { UrlParameters result; result.items = items; return result; }
}

bool subscriptionExists(string subscriptionID)
{
	return query!`SELECT COUNT(*) FROM [Subscriptions] WHERE [ID]=?`.iterate(subscriptionID).selectValue!int > 0;
}

Subscription getSubscription(string subscriptionID)
out(result) { assert(result.id == subscriptionID); }
body
{
	foreach (string userName, string data; query!`SELECT [Username], [Data] FROM [Subscriptions] WHERE [ID] = ?`.iterate(subscriptionID))
		return Subscription(userName, data.jsonParse!SubscriptionData.data);
	throw new Exception("No such subscription");
}

Subscription getUserSubscription(string userName, string subscriptionID)
out(result) { assert(result.id == subscriptionID && result.userName == userName); }
body
{
	enforce(userName.length, "Not logged in");
	foreach (string data; query!`SELECT [Data] FROM [Subscriptions] WHERE [Username] = ? AND [ID] = ?`.iterate(userName, subscriptionID))
		return Subscription(userName, data.jsonParse!SubscriptionData.data);
	throw new Exception("No such user subscription");
}

Subscription[] getUserSubscriptions(string userName)
{
	assert(userName);

	Subscription[] results;
	foreach (string data; query!`SELECT [Data] FROM [Subscriptions] WHERE [Username] = ?`.iterate(userName))
		results ~= Subscription(userName, data.jsonParse!SubscriptionData.data);
	return results;
}

void createReplySubscription(string userName)
{
	auto replySubscriptions = getUserSubscriptions(userName)
		.filter!(result => result.trigger.type == "reply");

	auto subscription = replySubscriptions.empty
		? createSubscription(userName, "reply")
		: replySubscriptions.front
	;
	subscription.save();
}

Subscription createSubscription(string userName, string triggerType, string[string] extraData = null)
{
	UrlParameters data = extraData;
	data["trigger-type"] = triggerType;

	Subscription subscription;
	subscription.userName = userName;
	subscription.id = data["id"] = randomString();
	subscription.trigger = getTrigger(userName, data);
	subscription.actions = getActions(userName, data);
	return subscription;
}

abstract class FormSection
{
	string userName, subscriptionID;

	this(string userName, UrlParameters data) { list(this.userName, this.subscriptionID) = tuple(userName, data.get("id", null)); }

	/// Output the form HTML to edit this trigger.
	abstract void putEditHTML(ref StringBuffer html);

	/// Serialize state to a key-value AA,
	/// with the same keys as form input names.
	abstract void serialize(ref UrlParameters data);

	/// Verify that the settings are valid.
	/// Throw an exception otherwise.
	abstract void validate();

	/// Create or update any persistent state
	/// (outside the [Subscriptions] table).
	abstract void save();

	/// Clean up any persistent state after deletion
	/// (outside the [Subscriptions] table).
	abstract void cleanup();
}

// ***********************************************************************

class Trigger : FormSection
{
	mixin GenerateConstructorProxies;

	/// TriggerType
	abstract @property string type() const;

	/// HTML description shown in the subscription list.
	abstract void putDescription(ref StringBuffer html);

	final string getDescription()
	{
		StringBuffer description;
		putDescription(description);
		return description.get().assumeUnique();
	}

	/// Text description shown in emails and feed titles.
	abstract string getTextDescription();

	/// Short description for IRC and email subjects.
	abstract string getShortPostDescription(Rfc850Post post);

	/// Longer description emails.
	abstract string getLongPostDescription(Rfc850Post post);
}

final class ReplyTrigger : Trigger
{
	mixin GenerateConstructorProxies;

	override @property string type() const { return "reply"; }

	override void putDescription(ref StringBuffer html) { html.put(getTextDescription()); }

	override string getTextDescription() { return "Replies to your posts"; }

	override string getShortPostDescription(Rfc850Post post)
	{
		return "%s replied to your post in the thread \"%s\"".format(post.author, post.subject);
	}

	override string getLongPostDescription(Rfc850Post post)
	{
		return "%s has just replied to your %s post in the thread titled \"%s\" in the %s group of %s.".format(
			post.author,
			post.time.formatTime!`F j`,
			post.subject,
			post.xref[0].group,
			site.host,
		);
	}

	override void putEditHTML(ref StringBuffer html)
	{
		html.put("When someone replies to your posts:");
	}

	override void serialize(ref UrlParameters data) {}

	override void validate() {}

	override void save()
	{
		string email = getUserSetting(userName, "email");
		if (email)
			query!`INSERT OR REPLACE INTO [ReplyTriggers] ([SubscriptionID], [Email]) VALUES (?, ?)`.exec(subscriptionID, email);
	}

	override void cleanup()
	{
		query!`DELETE FROM [ReplyTriggers] WHERE [SubscriptionID] = ?`.exec(subscriptionID);
	}
}

final class ThreadTrigger : Trigger
{
	string threadID;

	this(string userName, UrlParameters data)
	{
		super(userName, data);
		this.threadID = data.get("trigger-thread-id", null);
	}

	override @property string type() const { return "thread"; }

	final void putThreadName(ref StringBuffer html)
	{
		auto post = getPost(threadID);
		html.put(`<a href="`), html.putEncodedEntities(idToUrl(threadID)), html.put(`"><b>`),
		html.putEncodedEntities(post ? post.subject : threadID),
		html.put(`</b></a>`);
	}

	override void putDescription(ref StringBuffer html)
	{
		html.put(`Replies to the thread `), putThreadName(html);
	}

	override string getTextDescription()
	{
		auto post = getPost(threadID);
		return "Replies to the thread " ~ (post ? `"` ~ post.subject ~ `"` : threadID);
	}

	override string getShortPostDescription(Rfc850Post post)
	{
		return "%s replied to the thread \"%s\"".format(post.author, post.subject);
	}

	override string getLongPostDescription(Rfc850Post post)
	{
		return "%s has just replied to a thread you have subscribed to titled \"%s\" in the %s group of %s.".format(
			post.author,
			post.subject,
			post.xref[0].group,
			site.host,
		);
	}

	override void putEditHTML(ref StringBuffer html)
	{
		auto post = getPost(threadID);
		html.put(
			`<input type="hidden" name="trigger-thread-id" value="`), html.putEncodedEntities(threadID), html.put(`">` ~
			`When someone posts a reply to the thread `), putThreadName(html), html.put(`:`
		);
	}

	override void serialize(ref UrlParameters data)
	{
		data["trigger-thread-id"] = threadID;
	}

	override void validate()
	{
		enforce(getPost(threadID), "No such post");
	}

	override void save()
	{
		query!`INSERT OR REPLACE INTO [ThreadTriggers] ([SubscriptionID], [ThreadID]) VALUES (?, ?)`.exec(subscriptionID, threadID);
	}

	override void cleanup()
	{
		query!`DELETE FROM [ThreadTriggers] WHERE [SubscriptionID] = ?`.exec(subscriptionID);
	}
}

final class ContentTrigger : Trigger
{
	struct StringFilter
	{
		bool enabled;
		bool isRegex;
		bool caseSensitive;
		string str;
	}

	bool onlyNewThreads;
	bool onlyInGroups; string[] groups;
	StringFilter authorNameFilter, authorEmailFilter, subjectFilter, messageFilter;

	this(string userName, UrlParameters data)
	{
		super(userName, data);
		this.onlyNewThreads = data.get("trigger-content-message-type", null) == "threads";
		this.onlyInGroups = !!("trigger-content-only-in-groups" in data);
		this.groups = data.getAll("trigger-content-groups");

		void readStringFilter(string id, out StringFilter filter)
		{
			auto prefix = "trigger-content-" ~ id ~ "-";
			filter.enabled = !!((prefix ~ "enabled") in data);
			filter.isRegex = data.get(prefix ~ "match-type", null) == "regex";
			filter.caseSensitive = !!((prefix ~ "case-sensitive") in data);
			filter.str = data.get(prefix ~ "str", null);
		}

		readStringFilter("author-name", authorNameFilter);
		readStringFilter("author-email", authorEmailFilter);
		readStringFilter("subject", subjectFilter);
		readStringFilter("message", messageFilter);
	}

	override @property string type() const { return "content"; }

	override void putDescription(ref StringBuffer html)
	{
		html.put(onlyNewThreads ? `New threads` : `New posts`);
		if (onlyInGroups)
		{
			html.put(` in `);
			void putGroup(string group)
			{
				auto gi = getGroupInfo(group);
				html.put(`<b>`), html.putEncodedEntities(gi ? gi.publicName : group), html.put(`</b>`);
			}

			putGroup(groups[0]);
			if (groups.length==1)
				{}
			else
			if (groups.length==2)
				html.put(` and `), putGroup(groups[1]);
			else
			if (groups.length==3)
				html.put(`, `), putGroup(groups[1]), html.put(` and `), putGroup(groups[2]);
			else
				html.put(`, `), putGroup(groups[1]), html.put(`, (<b>%d</b> more)`.format(groups.length-2));
		}

		void putStringFilter(string preface, ref StringFilter filter)
		{
			if (filter.enabled)
				html.put(
					` `, preface, ` `,
					filter.isRegex ? `/` : ``,
					`<b>`), html.putEncodedEntities(filter.str), html.put(`</b>`,
					filter.isRegex ? `/` : ``,
					filter.isRegex && !filter.caseSensitive ? `i` : ``,
				);
		}

		putStringFilter("from", authorNameFilter);
		putStringFilter("from email", authorEmailFilter);
		putStringFilter("titled", subjectFilter);
		putStringFilter("containing", messageFilter);
	}

	override string getTextDescription() { return getDescription().replace(`<b>`, "\&ldquo;").replace(`</b>`, "\&rdquo;"); }

	override string getShortPostDescription(Rfc850Post post)
	{
		auto s = "%s %s thread \"%s\" in %s".format(
			post.author,
			post.references.length ? "replied to the" : "created",
			post.subject,
			post.xref[0].group,
		);
		string matchStr =
			authorNameFilter .enabled && authorNameFilter .str ? authorNameFilter .str :
			authorEmailFilter.enabled && authorEmailFilter.str ? authorEmailFilter.str :
			subjectFilter    .enabled && subjectFilter    .str ? subjectFilter    .str :
			messageFilter    .enabled && messageFilter    .str ? messageFilter    .str :
			null;
		if (matchStr)
			s = "%s matching %s".format(s, matchStr);
		return s;
	}

	override string getLongPostDescription(Rfc850Post post)
	{
		return "%s has just %s a thread titled \"%s\" in the %s group of %s.\n\nThis %s matches a content alert subscription you have created (%s).".format(
			post.author,
			post.references.length ? "replied to" : "created",
			post.subject,
			post.xref[0].group,
			site.host,
			post.references.length ? "post" : "thread",
			getTextDescription(),
		);
	}

	override void putEditHTML(ref StringBuffer html)
	{
		html.put(
			`<div id="trigger-content">` ~
			`When someone ` ~
			`<select name="trigger-content-message-type">` ~
				`<option value="posts"`  , onlyNewThreads ? `` : ` selected`, `>posts or replies to a thread</option>` ~
				`<option value="threads"`, onlyNewThreads ? ` selected` : ``, `>posts a new thread</option>` ~
			`</select>` ~
			`<table>` ~
			`<tr><td>` ~
				`<input type="checkbox" name="trigger-content-only-in-groups"`, onlyInGroups ? ` checked` : ``, `> only in the groups:` ~
			`</td><td>` ~
				`<select name="trigger-content-groups" multiple size="10">`
		);
		foreach (set; groupHierarchy)
		{
			if (!set.visible)
				continue;

			html.put(
				`<option disabled>`), html.putEncodedEntities(set.shortName), html.put(`</option>`
			);
			foreach (group; set.groups)
				html.put(
					`<option value="`), html.putEncodedEntities(group.internalName), html.put(`"`, groups.canFind(group.internalName) ? ` selected` : ``, `>` ~
						`&nbsp;&nbsp;&nbsp;`), html.putEncodedEntities(group.publicName), html.put(`</option>`
				);
		}
		html.put(
				`</select>` ~
			`</td></tr>`
		);

		void putStringFilter(string name, string id, ref StringFilter filter)
		{
			html.put(
				`<tr><td>` ~
					`<input type="checkbox" name="trigger-content-`, id, `-enabled"`, filter.enabled ? ` checked` : ``, `> ` ~
					`and when the `, name, ` ` ~
				`</td><td>` ~
					`<select name="trigger-content-`, id, `-match-type">` ~
						`<option value="substring"`, filter.isRegex ? `` : ` selected`, `>contains the string</option>` ~
						`<option value="regex"`    , filter.isRegex ? ` selected` : ``, `>matches the regular expression</option>` ~
					`</select> ` ~
					`<input name="trigger-content-`, id, `-str" value="`), html.putEncodedEntities(filter.str), html.put(`"> ` ~
					`(` ~
					`<input type="checkbox" name="trigger-content-`, id, `-case-sensitive"`, filter.caseSensitive ? ` checked` : ``, `>` ~
					` case sensitive )` ~
				`</td></tr>`
			);
		}

		putStringFilter("author name", "author-name", authorNameFilter);
		putStringFilter("author email", "author-email", authorEmailFilter);
		putStringFilter("subject", "subject", subjectFilter);
		putStringFilter("message", "message", messageFilter);
		html.put(`</table></div>`);
	}

	override void serialize(ref UrlParameters data) const
	{
		data["trigger-content-message-type"] = onlyNewThreads ? "threads" : "posts";
		if (onlyInGroups) data["trigger-content-only-in-groups"] = "on";
		foreach (group; groups)
			data.add("trigger-content-groups", group);

		void serializeStringFilter(string id, ref in StringFilter filter)
		{
			auto prefix = "trigger-content-" ~ id ~ "-";
			if (filter.enabled) data[prefix ~ "enabled"] = "on";
			data[prefix ~ "match-type"] = filter.isRegex ? "regex" : "substring";
			if (filter.caseSensitive) data[prefix ~ "case-sensitive"] = "on";
			data[prefix ~ "str"] = filter.str;
		}

		serializeStringFilter("author-name", authorNameFilter);
		serializeStringFilter("author-email", authorEmailFilter);
		serializeStringFilter("subject", subjectFilter);
		serializeStringFilter("message", messageFilter);
	}

	override void validate()
	{
		void validateFilter(string name, ref StringFilter filter)
		{
			if (filter.enabled)
			{
				enforce(filter.str.length, "No %s search term specified".format(name));
				try
					auto re = regex(filter.str);
				catch (Exception e)
					throw new Exception("Invalid %s regex `%s`: %s".format(name, filter.str, e.msg));
			}
		}

		validateFilter("author name", authorNameFilter);
		validateFilter("author email", authorEmailFilter);
		validateFilter("subject", subjectFilter);
		validateFilter("message", messageFilter);

		if (onlyInGroups)
			enforce(groups.length, "No groups selected");
	}

	override void save()
	{
		query!`INSERT OR REPLACE INTO [ContentTriggers] ([SubscriptionID]) VALUES (?)`.exec(subscriptionID);
	}

	override void cleanup()
	{
		query!`DELETE FROM [ContentTriggers] WHERE [SubscriptionID] = ?`.exec(subscriptionID);
	}

	bool checkPost(Rfc850Post post)
	{
		if (onlyNewThreads && post.references.length)
			return false;
		if (onlyInGroups && post.xref.all!(xref => !groups.canFind(xref.group)))
			return false;

		bool checkFilter(ref StringFilter filter, string field)
		{
			if (!filter.enabled)
				return true;
			if (filter.isRegex)
				return !!field.match(regex(filter.str, filter.caseSensitive ? "" : "i"));
			else
				return field.indexOf(filter.str, filter.caseSensitive ? CaseSensitive.yes : CaseSensitive.no) >= 0;
		}

		if (!checkFilter(authorNameFilter , post.author     )) return false;
		if (!checkFilter(authorEmailFilter, post.authorEmail)) return false;
		if (!checkFilter(subjectFilter    , post.subject    )) return false;
		if (!checkFilter(messageFilter    , post.newContent )) return false;

		return true;
	}
}

Trigger getTrigger(string userName, UrlParameters data)
out(result) { assert(result.type == data.get("trigger-type", null)); }
body
{
	auto triggerType = data.get("trigger-type", null);
	switch (triggerType)
	{
		case "reply":
			return new ReplyTrigger(userName, data);
		case "thread":
			return new ThreadTrigger(userName, data);
		case "content":
			return new ContentTrigger(userName, data);
		default:
			throw new Exception("Unknown subscription trigger type: " ~ triggerType);
	}
}

// ***********************************************************************

void checkPost(Rfc850Post post)
{
	// ReplyTrigger
	if (auto parentID = post.parentID())
		if (auto parent = getPost(parentID))
			foreach (string subscriptionID; query!"SELECT [SubscriptionID] FROM [ReplyTriggers] WHERE [Email] = ?".iterate(parent.authorEmail))
				getSubscription(subscriptionID).runActions(post);

	// ThreadTrigger
	foreach (string subscriptionID; query!"SELECT [SubscriptionID] FROM [ThreadTriggers] WHERE [ThreadID] = ?".iterate(post.threadID))
		getSubscription(subscriptionID).runActions(post);

	// ContentTrigger
	foreach (string subscriptionID; query!"SELECT [SubscriptionID] FROM [ContentTriggers]".iterate())
	{
		auto subscription = getSubscription(subscriptionID);
		if ((cast(ContentTrigger)subscription.trigger).checkPost(post))
			subscription.runActions(post);
	}
}

final class SubscriptionSink : NewsSink
{
protected:
	override void handlePost(Post post, Fresh fresh)
	{
		if (!fresh)
			return;

		auto message = cast(Rfc850Post)post;
		if (!message)
			return;

		log("Checking post " ~ message.id);
		try
			checkPost(message);
		catch (Exception e)
			foreach (line; e.toString().splitLines())
				log("* " ~ line);
	}
}

// ***********************************************************************

class Action : FormSection
{
	mixin GenerateConstructorProxies;

	/// Execute this action, if it is enabled.
	abstract void run(ref Subscription subscription, Rfc850Post post);

	/// Disable this action (used for one-click-unsubscribe in emails)
	abstract void unsubscribe();
}

final class IrcAction : Action
{
	bool enabled;
	string nick;
	string network;

	this(string userName, UrlParameters data)
	{
		super(userName, data);
		enabled = !!("saction-irc-enabled" in data);
		nick = data.get("saction-irc-nick", null);
		network = data.get("saction-irc-network", null);
	}

	override void putEditHTML(ref StringBuffer html)
	{
		html.put(
			`<p>` ~
				`<input type="checkbox" name="saction-irc-enabled"`, enabled ? ` checked` : ``, `> ` ~
				`Send a private message to <input name="saction-irc-nick" value="`), html.putEncodedEntities(nick), html.put(`"> on the ` ~
				`<select name="saction-irc-network">`);
		foreach (irc; services!IrcSink)
		{
			html.put(
					`<option value="`), html.putEncodedEntities(irc.network), html.put(`"`, network == irc.network ? ` selected` : ``, `>`),
						html.putEncodedEntities(irc.network),
					html.put(`</option>`);
		}
		html.put(
				`</select> IRC network` ~
			`</p>`
		);
	}

	override void serialize(ref UrlParameters data)
	{
		if (enabled) data["saction-irc-enabled"] = "on";
		data["saction-irc-nick"] = nick;
		data["saction-irc-network"] = network;
	}

	override void run(ref Subscription subscription, Rfc850Post post)
	{
		if (!enabled)
			return;

		// Queue messages to avoid sending more than 1 PM per message.

		static string[string][string] queue;
		static TimerTask queueTask;

		queue[network][nick] = subscription.trigger.getShortPostDescription(post) ~ ": " ~ post.url;
		if (!queueTask)
			queueTask = setTimeout({
				queueTask = null;
				scope(exit) queue = null;
				foreach (irc; services!IrcSink)
					foreach (nick, message; queue.get(irc.network, null))
						irc.sendMessage(nick, message);
			}, 1.msecs);
	}

	override void validate()
	{
		if (!enabled)
			return;
		enforce(nick.length, "No nickname indicated");
		foreach (c; nick)
			if (!(isAlphaNum(c) || c.isOneOf(r"-_|\[]{}`")))
				throw new Exception("Invalid character in nickname.");
	}

	override void save() {}

	override void cleanup() {}

	override void unsubscribe() { enabled = false; }
}

final class EmailAction : Action
{
	bool enabled;
	string address;

	this(string userName, UrlParameters data)
	{
		super(userName, data);
		enabled = !!("saction-email-enabled" in data);
		address = data.get("saction-email-address", getUserSetting(userName, "email"));
	}

	override void putEditHTML(ref StringBuffer html)
	{
		html.put(
			`<p>` ~
				`<input type="checkbox" name="saction-email-enabled"`, enabled ? ` checked` : ``, `> ` ~
				`Send an email to <input type="email" size="30" name="saction-email-address" value="`), html.putEncodedEntities(address), html.put(`">` ~
			`</p>`
		);
	}

	override void serialize(ref UrlParameters data)
	{
		if (enabled) data["saction-email-enabled"] = "on";
		data["saction-email-address"] = address;
	}

	string getUserRealName(string userName)
	{
		auto name = getUserSetting(userName, "name");
		if (!name)
		//	name = address.split("@")[0].capitalize();
			name = userName;
		return name;
	}

	override void run(ref Subscription subscription, Rfc850Post post)
	{
		if (!enabled)
			return;

		auto unreadCount = subscription.getUnreadCount();
		if (unreadCount)
		{
			log("User %s has %d unread messages in subscription %s - not emailing"
				.format(subscription.userName, unreadCount, subscription.id));
			return;
		}

		// Queue messages to avoid sending more than 1 email per message.
		static struct Email { string[] args; string content; }

		static Email[string] queue;
		static TimerTask queueTask;

		if (address in queue)
		{
			// TODO: Maybe add something to the content, to indicate that
			// a second subscription was triggered by the same message.
			return;
		}

		queue[address] = Email([
			"-s", subscription.trigger.getShortPostDescription(post),
			"-r", "%s <no-reply@%s>".format(site.host, site.host),
			address], formatMessage(subscription, post));

		if (!queueTask)
			queueTask = setTimeout({
				queueTask = null;
				scope(exit) queue = null;
				foreach (address, email; queue)
				{
					auto pipes = pipeProcess(["mail"] ~ email.args, Redirect.stdin);
					pipes.stdin.rawWrite(email.content);
					pipes.stdin.close();
					enforce(wait(pipes.pid) == 0, "mail program failed");
				}
			}, 1.msecs);
	}

	string formatMessage(ref Subscription subscription, Rfc850Post post)
	{
		return q"EOF
Howdy %s,

%s

This %s is located at:
%s

Here is the message that has just been posted:
----------------------------------------------
%-(%s
%)
----------------------------------------------

To reply to this message, please visit this page:
%s://%s%s

There may also be other messages matching your subscription, but you will not receive any more notifications for this subscription until you've read all messages matching this subscription:
%s://%s/subscription-posts/%s

All the best,
%s

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Unsubscription information:

To stop receiving emails for this subscription, please visit this page:
%s://%s/subscription-unsubscribe/%s

Or, visit your settings page to edit your subscriptions:
%s://%s/settings
.
EOF"
		.format(
			getUserRealName(userName).split(" ")[0],
			subscription.trigger.getLongPostDescription(post),
			post.references.length ? "post" : "thread",
			post.url,
			post.content.strip.splitAsciiLines.map!(line => line.startsWith('.') ? '.' ~ line : line),
			site.proto, site.host, idToUrl(post.id, "reply"),
			site.proto, site.host, subscription.id,
			site.name.length ? site.name : site.host,
			site.proto, site.host, subscription.id,
			site.proto, site.host,
		);
	}

	override void validate()
	{
		if (!enabled)
			return;
		enforce(address.match(re!(`^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}$`, "i")), "Invalid email address");
	}

	override void save() {}

	override void cleanup() {}

	override void unsubscribe() { enabled = false; }
}

final class DatabaseAction : Action
{
	mixin GenerateConstructorProxies;

	override void putEditHTML(ref StringBuffer html)
	{
		html.put(
			`<p>Additionally, you can <a href="/subscription-feed/`, subscriptionID, `">subscribe to an ATOM feed of matched posts</a>, ` ~
			`or <a href="/subscription-posts/`, subscriptionID, `">read them online</a>.</p>`
		);
	}

	override void serialize(ref UrlParameters data) {}

	override void run(ref Subscription subscription, Rfc850Post post)
	{
		assert(post.rowid, "No row ID for message " ~ post.id);
		query!"INSERT INTO [SubscriptionPosts] ([SubscriptionID], [MessageID], [MessageRowID], [Time]) VALUES (?, ?, ?, ?)"
			.exec(subscriptionID, post.id, post.rowid, post.time.stdTime);
		// TODO: trim old posts?
	}

	override void validate() {}

	override void save() {}

	override void cleanup() {} // Just leave the SubscriptionPosts alone, e.g. in case the user clicks undo

	override void unsubscribe() {}
}

Action[] getActions(string userName, UrlParameters data)
{
	Action[] result;
	foreach (ActionType; TypeTuple!(EmailAction, IrcAction, DatabaseAction))
		result ~= new ActionType(userName, data);
	return result;
}

// ***********************************************************************

private string getUserSetting(string userName, string setting)
{
	foreach (string value; query!`SELECT [Value] FROM [UserSettings] WHERE [User] = ? AND [Name] = ?`.iterate(userName, setting))
		return value;
	return null;
}

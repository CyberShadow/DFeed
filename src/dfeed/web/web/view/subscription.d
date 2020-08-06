/*  Copyright (C) 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
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

/// User subscriptions.
module dfeed.web.web.view.subscription;

import std.conv : text;

import ae.utils.xmllite : putEncodedEntities;

import dfeed.database : query, selectValue;
import dfeed.sinks.subscriptions;
import dfeed.web.web.page : html;
import dfeed.web.web.part.pager : POSTS_PER_PAGE, pager, getPageCount;
import dfeed.web.web.part.post : formatPost;
import dfeed.web.web.postinfo : getPost;
import dfeed.web.web.user;

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
		else
			query!"DELETE FROM [SubscriptionPosts] WHERE [SubscriptionID] = ? AND [MessageID] = ?".exec(subscriptionID, messageID);
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

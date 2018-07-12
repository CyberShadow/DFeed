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

/// User settings.
module dfeed.web.web.view.settings;

import std.algorithm.iteration;
import std.algorithm.searching;
import std.exception;

import dfeed.sinks.subscriptions;
import dfeed.web.web.request : Redirect, currentRequest, html;
import dfeed.web.web.user;

import ae.net.ietf.url;
import ae.utils.xmllite;

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

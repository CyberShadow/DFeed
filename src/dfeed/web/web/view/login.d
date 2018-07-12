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

/// Login and registration.
module dfeed.web.web.view.login;

import std.exception : enforce;

import ae.net.ietf.url : UrlParameters, encodeUrlParameter;
import ae.utils.aa : aaGet;
import ae.utils.xmllite : putEncodedEntities;

import dfeed.web.web : html;
import dfeed.web.web.request : user;

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

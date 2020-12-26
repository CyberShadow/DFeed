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

/// Paging.
module dfeed.web.web.part.pager;

import std.algorithm.comparison;
import std.algorithm.searching;
import std.array;
import std.conv;
import std.exception;

import ae.utils.text.html : encodeHtmlEntities;

import dfeed.groups : GroupInfo;
import dfeed.web.web.cache;
import dfeed.web.web.page : html;

/// pageCount==int.max indicates unknown number of pages
void pager(string base, int page, int pageCount, int maxWidth = 50)
{
	if (!pageCount)
		return html.put(`<tr class="pager"><th colspan="3">-</th></tr>`);

	string linkOrNot(string text, int page, bool cond)
	{
		if (cond)
			return `<a href="` ~ encodeHtmlEntities(base) ~ (base.canFind('?') ? `&` : `?`) ~ `page=` ~ .text(page) ~ `">` ~ text ~ `</a>`;
		else
			return `<span class="disabled-link">` ~ text ~ `</span>`;
	}

	// Try to make the pager as wide as it will fit in the alotted space

	int widthAt(int radius)
	{
		import std.math : log10;

		int pagerStart = max(1, page - radius);
		int pagerEnd = min(pageCount, page + radius);
		if (pageCount==int.max)
			pagerEnd = page + 1;

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
	if (pageCount==int.max)
		pagerEnd = page + 1;

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
		`<tr class="pager"><th colspan="3">` ~
			`<div class="pager-left">`,
				linkOrNot("&laquo; First", 1, page!=1),
				`&nbsp;&nbsp;&nbsp;`,
				linkOrNot("&lsaquo; Prev", page-1, page>1),
			`</div>` ~
			`<div class="pager-right">`,
				linkOrNot("Next &rsaquo;", page+1, page<pageCount),
				`&nbsp;&nbsp;&nbsp;`,
				linkOrNot("Last &raquo; ", pageCount, page!=pageCount && pageCount!=int.max),
			`</div>` ~
			`<div class="pager-numbers">`, pager.join(` `), `</div>` ~
		`</th></tr>`);
}

enum THREADS_PER_PAGE = 15;
enum POSTS_PER_PAGE = 10;

static int indexToPage(int index, int perPage)  { return index / perPage + 1; } // Return value is 1-based, index is 0-based
static int getPageCount(int count, int perPage) { return count ? indexToPage(count-1, perPage) : 0; }
static int getPageOffset(int page, int perPage) { return (page-1) * perPage; }

void threadPager(GroupInfo groupInfo, int page, int maxWidth = 40)
{
	auto threadCounts = threadCountCache(getThreadCounts());
	auto threadCount = threadCounts.get(groupInfo.internalName, 0);
	auto pageCount = getPageCount(threadCount, THREADS_PER_PAGE);

	pager(`/group/` ~ groupInfo.urlName, page, pageCount, maxWidth);
}

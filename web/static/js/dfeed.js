$(document).ready(function() {
	if ($('#group-split').length) {

		$('.postlink').live('click', function() {
			var path = $(this).attr('href');
			return !selectMessage(path);
		});
		$('tr.thread-post-row').live('mousedown', function(e) {
			if (e.which == 1)
				return selectRow($(this));
			return true;
		}).css('cursor', 'default');

		$(window).resize(onResize);
		updateSize();
		focusRow($('tr.thread-post-row').last());

		$(window).bind('popstate', onPopState);
		onPopState();

		$('#forum-tools-left').append(
			$('<a>')
			.attr('href', 'javascript:toggleNav()')
			.text('Toggle navigation')
		);

		showNav(localStorage.getItem('navhidden') == 'true');
	}

	if ($.browser.webkit) {
		// Chrome does not pass Ctrl+keys to keypress - but in many
		// other browsers keydown does not repeat
		$(document).keydown(onKeyPress);
	} else {
		$(document).keypress(onKeyPress);
	}
});

function toggleNav() {
	var hidden = localStorage.getItem('navhidden') == 'true';
	hidden = !hidden;
	localStorage.setItem('navhidden', hidden);
	showNav(hidden);
}

function showNav(hidden) {
	$('body').toggleClass('navhidden', hidden);
	updateSize();
}

function selectMessage(path) {
	var id = idFromPath(path);
	if (id && findInTree(path)) {
		window.history.replaceState(null, id, path);
		onPopState();
		return true;
	}
	return false;
}

function idFromPath(path) {
	if (path.substr(0, 6) == '/post/')
		return path.substr(6);
	return null;
}

function findInTree(path) {
	var a = $('.group-threads').find('a[href="'+path+'"]');
	if (a.length)
		return a.first().closest('tr.thread-post-row');
	else
		return null;
}

function getPath() {
	var path = window.location.pathname;

	// Work around Opera bug?
	if (path.substr(0, 6) == '/post/')
		path = path.substr(0, 6) + path.substr(6).replace(/\//g, '%2F');

	return path;
}

var currentRequest = null;
var currentID = null;

function onPopState() {
	var path = getPath();
	var id = idFromPath(path);
	var row = findInTree(path);

	if (id && id == currentID && row.find('.forum-unread').length==0)
		return;
	else
	if (id && row) {
		if (currentRequest) {
			currentRequest.abort();
			currentRequest = null;
		}

		$('.group-threads .selected').removeClass('selected');
		row.addClass('selected');
		focusRow(row, true);
		currentID = id;

		showText('Loading message\n<'+id+'> ...');

		currentRequest = $.get('/split-post/' + id, function(result) {
			currentRequest = null;
			row.find('.forum-unread').removeClass('forum-unread').addClass('forum-read');

			showPost(result);
		});
		currentRequest.error(function(jqXHR, textStatus, errorThrown) {
			currentRequest = null;
			showText('XHR ' + textStatus + (errorThrown ? ': ' + errorThrown : ''));
		});
	} else {
		if (window.history.pushState)
			showHtml(keyboardHelp);
		else
			showHtml('Your browser does not support HTML5 pushState.');
	}

	$('#forum-tools-right').html(toolsTemplate.replace(/__URL__/g, encodeURIComponent(document.location.href)));
}

function showPost(postHtml) {
	$('#group-split-message')
		.html(postHtml)
		.removeClass('group-split-message-none');
	updateSize();
}

function showText(text) {
	$('#group-split-message')
		.text(text)
		.addClass('group-split-message-none');
}

function showHtml(text) {
	$('#group-split-message')
		.html(text)
		.addClass('group-split-message-none');
}

// **************************************************************************

// This *might* be possible with just CSS, but so far all my attempts failed.

var resizeTimeout = null;

function updateSize() {
	resizeTimeout = null;

	var focused = $('.focused');
	var wasFocusedInView = false;
	if (focused.length)
		wasFocusedInView = isRowInView(focused);

	var resizees = [
		{ outer : $('#group-split-list    > div'), inner : $('.group-threads')},
		{ outer : $('#group-split-message > *'  ), inner : $('.split-post .post-body')},
	];

	var dummyHeight = 300;

	// Shrink content to a fixed height, so we can calculate how much space we have to grow.

	for (var i in resizees) {
		resizees[i].inner.height(dummyHeight);
	}

	var contentBottom = $('#content').position().top + $('#content').outerHeight(true);
	var usedWindowSpace  = contentBottom;
	if ($('#copyright:visible').length)
		usedWindowSpace += $('#copyright').position().top + $('#copyright').outerHeight(true) - contentBottom + 10 /*???*/;
	usedWindowSpace = Math.trunc(usedWindowSpace);
	var totalWindowSpace = $(window).height();
	var freeWindowSpace  = totalWindowSpace - usedWindowSpace;

	var resizeeOuterSizes = $.map(resizees, function(r) { return r.outer.outerHeight(true); });
//	resizeeOuterSizes[1] += 1; // HACK ??? border?
	var contentSize = Math.max.apply(null, resizeeOuterSizes);

	//console.log(JSON.stringify({contentBottom:contentBottom, usedWindowSpace:usedWindowSpace, totalWindowSpace:totalWindowSpace, freeWindowSpace:freeWindowSpace,resizeeOuterSizes:resizeeOuterSizes, contentSize:contentSize, }));

	for (var i in resizees) {
		var resizeeOuterSize = resizeeOuterSizes[i];
		var itemFreeSpace = dummyHeight;

		// Grow to fill content (this will be 0 for tallest resizee)
		itemFreeSpace += contentSize - resizeeOuterSize;

		// Grow to fill window
		itemFreeSpace += freeWindowSpace;

		resizees[i].inner.height(itemFreeSpace);

		// Correction
	//	console.log([contentSize, resizees[i].outer.height() - (freeWindowSpace)]);
	}

	//console.log($('#content').outerHeight(true));
	console.log([resizees[0].outer.outerHeight(true), resizees[1].outer.outerHeight(true)]);

	if (focused.length && wasFocusedInView)
		focusRow(focused, true);
}

function onResize() {
	if (resizeTimeout)
		clearTimeout(resizeTimeout);
	resizeTimeout = setTimeout(updateSize, 10);
}

// **************************************************************************

function nestedOffset(element, container) {
    if (element === document.body) element = window;
	if (element.offsetParent === container)
		return element.offsetTop;
	else
	if (element.offsetParent === container.offsetParent)
		return 0;
	else
		return element.offsetTop + nestedOffset(element.offsetParent, container);
}

function isInView(element, container) {
	var containerTop = $(container).scrollTop();
	var containerHeight = $(container).height();
	var containerBottom = containerTop + containerHeight;

	var elemTop = nestedOffset(element, container);
	var elemBottom = elemTop + $(element).height();

	return elemTop > containerTop && elemBottom < containerBottom;
}

function scrollIntoView(element, container, withMargin) {
	var containerTop = $(container).scrollTop();
	var containerHeight = $(container).height();
	var containerBottom = containerTop + containerHeight;
	//var elemTop = element.offsetTop;
	var elemTop = nestedOffset(element, container);
	var elemBottom = elemTop + $(element).height();
	var scrollMargin = withMargin ? containerHeight/4 : 10;
	if (elemTop < containerTop) {
		$(container).scrollTop(Math.max(0, elemTop - scrollMargin));
		//$(container).scrollTo(elemTop, 200)
	} else if (elemBottom > containerBottom) {
		$(container).scrollTop(elemBottom - containerHeight + scrollMargin);
		//$(container).scrollTo(elemBottom - $(container).height(), 200)
	}
}

// **************************************************************************

function isRowInView(row) {
	return isInView(row[0], getSelectablesContainer());
}

function focusRow(row, withMargin) {
	$('.focused').removeClass('focused');
	row.addClass('focused');
	scrollIntoView(row[0], getSelectablesContainer(), withMargin);
}

function selectRow(row) {
	return getSelectableLink(row)[0].click();
}

function getSelectables() {
	if ($('#group-split').length) {
		return $('tr.thread-post-row');
	} else if ($('#forum-index').length) {
		return $('#forum-index > tbody > tr.group-row');
	} else {
		return [];
	}
}

function getSelectablesContainer() {
	if ($('#group-split').length) {
		return $('.group-threads')[0];
	} else if ($('#forum-index').length) {
		return window;
	}
}

function getSelectableLink(row) {
	if ($('#group-split').length) {
		return row.find('a.postlink');
	} else {
		return row.find('a').first();
	}
}

function focusNext(offset, onlyUnread) {
	if (typeof onlyUnread == 'undefined')
		onlyUnread = false;

	var all = getSelectables();
	var count = all.length;
	var current = $('.focused');
	var index;
	if (current.length == 0) {
		index = offset>0 ? offset-1 : count-offset;
	} else if (Math.abs(offset) == Infinity) {
		index = offset>0 ? count-1 : 0;
	} else {
		index = all.index(current);
		if (index < 0)
			index = 0;
		else
		if (!onlyUnread)
			index = (index + offset + count) % count;
	}

	for (var i=0; i<count; i++) {
		var row = all.eq(index);
		var isUnread = row.find('.forum-unread').length > 0;
		if (!onlyUnread || isUnread) {
			//row.mousedown();
			focusRow(row, false);
			return true;
		}

		index = (index + offset + count) % count;
	}

	return false;
}

function selectFocused() {
	var focused = $('.focused');
	if (focused.length) {
		selectRow(focused);
		return true;
	}
	return false;
}

function markUnread() {
	var focused = $('.focused');
	if (focused.length && focused.find('.forum-read').length > 0) {
		var path = focused.find('a.postlink').attr('href').replace("/post/", "/mark-unread/");
		$.get(path, function(result) {
			if (result == "OK")
				focused.find('.forum-read').removeClass('forum-read').addClass('forum-unread');
		});
		return true;
	}
	return false;
}

var keyboardHelp =
	'<table id="keyboardhelp">' +
		'<tr><td><kbd>j</kbd> / <kbd>Ctrl</kbd><kbd title="Down Arrow">&darr;</kbd></td><td>Select next message</td></tr>' +
		'<tr><td><kbd>k</kbd> / <kbd>Ctrl</kbd><kbd title="Up Arrow">&uarr;</kbd></td><td>Select previous message</td></tr>' +
		'<tr><td><kbd title="Enter / Return">&crarr;</kbd></td><td>Open selected message</td></tr>' +
		'<tr><td><kbd>r</kbd></td><td>Reply</td></tr>' +
		'<tr><td><kbd>u</kbd></td><td>Mark as unread</td></tr>' +
		'<tr><td><kbd title="Space Bar" style="width: 70px">&nbsp;</kbd></td><td>Scroll message / Open next unread message</td></tr>' +
	'</table>';

function onKeyPress(e) {
	var c = String.fromCharCode(e.which);
	if ($.browser.webkit) c = c.toLowerCase();
	var pageSize = $('.group-threads').height() / $('.thread-post-row').eq(0).height();

	if (!e.ctrlKey && !e.shiftKey && !e.altKey) {
		switch (c) {
			case 'j':
				return !focusNext(+1);
			case 'k':
				return !focusNext(-1);
			case '\x0D':
				return !selectFocused();
			case ' ':
			{
				var p = $('.post-body');
				if (!p.length) return true;
				var dest = p.scrollTop()+p.height();
				if (dest < p[0].scrollHeight) {
					p.animate({scrollTop : dest}, 200);
					return false;
				}
				return !(focusNext(+1, true) && selectFocused());
			}
			case 'r':
			{
				var replyLink = $('a.replylink');
				if (replyLink.length) {
					document.location.href = replyLink.attr('href');
					return false;
				}
				return true;
			}
			case 'u':
				return !markUnread();
		}
	}

	if (!e.ctrlKey && e.shiftKey && !e.altKey) {
		switch (c) {
			case 'J':
				return !(focusNext(+1) && selectFocused());
			case 'K':
				return !(focusNext(-1) && selectFocused());
		}
	}

	if (e.ctrlKey && !e.shiftKey && !e.altKey) {
		switch (e.keyCode) {
			case 13: // ctrl+enter == enter
				return !selectFocused();
			case 38: // up arrow
				return !focusNext(-1);
			case 40: // down arrow
				return !focusNext(+1);
			case 33: // page up
				return !focusNext(-pageSize);
			case 34: // page down
				return !focusNext(+pageSize);
			case 36: // home
				return !focusNext(-Infinity);
			case 35: // end
				return !focusNext(+Infinity);
		}
	}

	return true; // event handlers return "false" if the event was handled
}

/* These are linked to in responsive horizontal-split post footer */
function navPrev() { focusNext(-1) && selectFocused(); }
function navNext() { focusNext(+1) && selectFocused(); }

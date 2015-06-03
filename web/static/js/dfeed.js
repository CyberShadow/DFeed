var cssmenu_no_js = 1;

$(document).ready(function() {
	if (enableKeyNav) {
		if ($.browser.webkit) {
			// Chrome does not pass Ctrl+keys to keypress - but in many
			// other browsers keydown does not repeat
			$(document).keydown(onKeyPress);
		} else {
			$(document).keypress(onKeyPress);
		}
	}

	if ($('#group-split').length || $('#group-vsplit').length)
		initSplitView();

	if ($('#postform').length)
		initPosting();

	if ('localStorage' in window && localStorage.getItem('usingKeyNav')) {
		initKeyNav();
		localStorage.removeItem('usingKeyNav');
	}
});

// **************************************************************************
// Split view

function initSplitView() {
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

	toolsTemplate =
		$('<a>')
		.attr('href', 'javascript:toggleNav()')
		.text('Toggle navigation')
		[0].outerHTML
		+ ' &middot; '
		+ toolsTemplate;
	updateTools();

	showNav(localStorage.getItem('navhidden') == 'true');
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

		//var resource = $('#group-vsplit').length ? '/vsplit-post/' : '/split-post/';
		var resource = '/split-post/';
		currentRequest = $.get(resource + id, function(result) {
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

	updateTools();
}

function updateTools() {
	$('#forum-tools-right').html(toolsTemplate.replace(/__URL__/g, encodeURIComponent(document.location.href)));
}

function showPost(postHtml) {
	$('#group-split-message')
		.html(postHtml)
		.removeClass('group-split-message-none');
	updateSize();
	addLinkNavigation();
}

function showText(text) {
	$('#group-split-message')
	.addClass('group-split-message-none')
	.html(
		$('<span>')
			.text(text)
	);
	updateSize();
}

function showHtml(text) {
	$('#group-split-message')
		.html(text)
		.addClass('group-split-message-none');
}

// **************************************************************************
// Navigation toggle

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

// **************************************************************************
// Resizing

// This *might* be possible with just CSS, but so far all my attempts failed.

var resizeTimeout = null;

function updateSize() {
	resizeTimeout = null;

	var focused = $('.focused');
	var wasFocusedInView = false;
	if (focused.length)
		wasFocusedInView = isRowInView(focused);

	var vertical = $('#group-vsplit').length;

	var resizees =
		vertical
		?	[
				{ $outer : $('#group-vsplit-list   > div'), $inner : $('.group-threads')},
				{ $outer : $('#group-split-message'      ), $inner : $('.split-post .post-body, .group-split-message-none')},
			]
		:	[
				{ $outer : $('#group-split-list    > div'), $inner : $('.group-threads')},
				{ $outer : $('#group-split-message > *'  ), $inner : $('.split-post .post-body')},
			]
		;

	for (var i in resizees)
		resizees[i].$outer.css('height', '');

	function getFreeSpace() {
		var $bottommost = $('#copyright:visible').length ? $('#copyright') : $('#content');
		var usedWindowSpace = $bottommost.position().top + $bottommost.outerHeight(true);
		usedWindowSpace = Math.floor(usedWindowSpace);

		var totalWindowSpace = $(window).height();
		var freeWindowSpace  = totalWindowSpace - usedWindowSpace;
		return freeWindowSpace - 1;
	}

	function getFreeSpaceFor(showFun) {
		for (var i in resizees)
			if (showFun(i))
				resizees[i].$inner.height(dummyHeight);
			else
				resizees[i].$outer.hide();
		var freeSpace = getFreeSpace();
		for (var i in resizees)
			resizees[i].$outer.show();
		return freeSpace;
	}

	var dummyHeight = 300;

	// Shrink content to a fixed height, so we can calculate how much space we have to grow.

	var growSpace = [];
	for (var i in resizees)
		growSpace.push(getFreeSpaceFor(function(j) { return i==j; }));
	var growSpaceAll  = getFreeSpaceFor(function(j) { return true; });
	var growSpaceNone = getFreeSpaceFor(function(j) { return false; });
	var growSpaceMin  = Math.min.apply(null, growSpace);
	var growSpaceMax  = Math.max.apply(null, growSpace);
	var heights = [];
	for (var i in resizees)
		heights.push(growSpaceNone - growSpace[i]);

	//var obj = {}; ['growSpace', 'heights', 'growSpaceAll', 'growSpaceNone', 'growSpaceMax', 'growSpaceMax'].forEach(function(n) { obj[n]=eval(n); }); console.log(JSON.stringify(obj));

	for (var i in resizees) {
		var newHeight = dummyHeight;

		if (vertical)
		{
			newHeight = growSpaceNone / resizees.length - heights[i] + dummyHeight;
		}
		else
			newHeight += growSpace[i];

		resizees[i].$inner.height(newHeight);
		//console.log(i, ':', newHeight);
	}

	if (focused.length && wasFocusedInView)
		focusRow(focused, true);
}

function onResize() {
	if (resizeTimeout)
		clearTimeout(resizeTimeout);
	resizeTimeout = setTimeout(updateSize, 10);
}

// **************************************************************************
// Utility

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
// Keyboard navigation

function isRowInView(row) {
	return isInView(row[0], getSelectablesContainer());
}

function focusRow(row, withMargin) {
	$('.focused').removeClass('focused');
	row.addClass('focused');
	scrollIntoView(row[0], getSelectablesContainer(), withMargin);

	if ($('#group-split').length == 0 && $('#group-vsplit').length == 0)
		addLinkNavigation();
}

function selectRow(row) {
	return getSelectableLink(row)[0].click();
}

function getSelectables() {
	if ($('#group-split').length || $('#group-vsplit').length) {
		return $('tr.thread-post-row');
	} else if ($('#forum-index').length) {
		return $('#forum-index > tbody > tr.group-row');
	} else if ($('#group-index').length) {
		return $('#group-index > tbody > tr.thread-row');
	} else if ($('#group-index-threaded').length) {
		return $('#group-index-threaded tr.thread-post-row');
	} else if ($('#thread-index').length) {
		return $('#thread-index tr.thread-post-row');
	} else if ($('.post').length) {
		return $('.post');
	} else {
		return [];
	}
}

function getSelectedPost() {
	if ($('.split-post').length) {
		return $('.split-post pre.post-text');
	} else if ($('.focused.post').length) {
		return $('.focused.post pre.post-text');
	} else {
		return null;
	}
}

function getSelectablesContainer() {
	if ($('#group-split').length || $('#group-vsplit').length) {
		return $('.group-threads')[0];
	} else /*if ($('#forum-index').length)*/ {
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

function getReplyLink() {
	if ($('#group-split').length || $('#group-vsplit').length || $('.viewmode-threaded').length) {
		return $('a.replylink');
	} else {
		return $('.focused a.replylink');
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
		var path = focused.find('a.postlink, a.permalink').attr('href').replace("/post/", "/mark-unread/");
		$.get(path, function(result) {
			if (result == "OK")
				focused.find('.forum-read').removeClass('forum-read').addClass('forum-unread');
		});
		return true;
	}
	return false;
}

// Show keyboard navigation UI immediately if we got to this page via keynav
function initKeyNav() {
	addLinkNavigation();
	if ($('.focused').length == 0)
		focusNext(+1);
}

function addLinkNavigation() {
	$post = getSelectedPost();
	if (!$post)
		return;

	$('.linknav').remove();
	var counter = 1;
	$post.find('a').each(function() {
		if (counter > 9) return;
		$(this).after(
			$('<span>')
			.addClass('linknav')
			.attr('data-num', counter++)
		);
	});
}

function followLink(n) {
	var url = $('.linknav[data-num='+n+']').prev('a').attr('href');
	if (url) {
		window.open(url, '_blank');
		return true;
	}
	return false;
}

var keyboardHelp =
	'<table class="keyboardhelp">' +
		'<tr><th colspan="2">Keyboard shortcuts</th></tr>' +
		'<tr><td><kbd>j</kbd> / <kbd>Ctrl</kbd><kbd title="Down Arrow">&darr;</kbd></td><td>Select next message</td></tr>' +
		'<tr><td><kbd>k</kbd> / <kbd>Ctrl</kbd><kbd title="Up Arrow">&uarr;</kbd></td><td>Select previous message</td></tr>' +
		'<tr><td><kbd title="Enter / Return">&crarr;</kbd></td><td>Open selected message</td></tr>' +
		'<tr><td><kbd>n</kbd></td><td>Create thread</td></tr>' +
		'<tr><td><kbd>r</kbd></td><td>Reply</td></tr>' +
		'<tr><td><kbd>u</kbd></td><td>Mark as unread</td></tr>' +
		'<tr><td><kbd>1</kbd> &middot;&middot;&middot; <kbd>9</kbd></td><td>Open link [1] &hellip; [9]</td></tr>' +
		'<tr><td><kbd title="Space Bar" style="width: 70px">&nbsp;</kbd></td><td>Scroll message / Open next unread message</td></tr>' +
	'</table>';

function showHelp() {
	$('<div class="keyboardhelp-popup">')
		.html(keyboardHelp)
		.click(closeHelp)
		.appendTo($('body'))
		.hide()
		.fadeIn();
	return true;
}

function closeHelp() {
	$('.keyboardhelp-popup').fadeOut(function() { $('.keyboardhelp-popup').remove(); });
}

function onKeyPress(e) {
	var result = onKeyPressImpl(e);
	if (result && 'localStorage' in window)
		localStorage.setItem('usingKeyNav', 'true');
	return !result; // event handlers return "false" if the event was handled
}

// Return true if the event was handled,
// and false if it wasn't and it should be processed by the browser.
function onKeyPressImpl(e) {
	if ($(e.target).is('input, textarea')) {
		return false;
	}

	if ($('.keyboardhelp-popup').length) {
		closeHelp();
		return true;
	}

	var c = String.fromCharCode(e.which);
	if ($.browser.webkit) c = c.toLowerCase();
	var pageSize = $('.group-threads').height() / $('.thread-post-row').eq(0).height();

	if (!e.ctrlKey && !e.shiftKey && !e.altKey) {
		switch (c) {
			case 'j':
				return focusNext(+1);
			case 'k':
				return focusNext(-1);
			case '\x0D':
				return selectFocused();
			case ' ':
			{
				var p = $('.post-body');
				if (!p.length) return false;
				var dest = p.scrollTop()+p.height();
				if (dest < p[0].scrollHeight) {
					p.animate({scrollTop : dest}, 200);
					return true;
				}
				return focusNext(+1, true) && selectFocused();
			}
			case 'n':
			{
				var $form = $('form[name=new-post-form]');
				$form.submit();
				return $form.length > 0;
			}
			case 'r':
			{
				var replyLink = getReplyLink();
				if (replyLink.length) {
					document.location.href = replyLink.attr('href');
					return true;
				}
				return false;
			}
			case 'u':
				return markUnread();
			case '1':
			case '2':
			case '3':
			case '4':
			case '5':
			case '6':
			case '7':
			case '8':
			case '9':
				return followLink(c);
		}
	}

	if (!e.ctrlKey && e.shiftKey && !e.altKey) {
		switch (c) {
			case 'J':
				return focusNext(+1) && selectFocused();
			case 'K':
				return focusNext(-1) && selectFocused();
			case '?':
				return showHelp();
		}
	}

	if (e.ctrlKey && !e.shiftKey && !e.altKey) {
		switch (e.keyCode) {
			case 13: // ctrl+enter == enter
				return selectFocused();
			case 38: // up arrow
				return focusNext(-1);
			case 40: // down arrow
				return focusNext(+1);
			case 33: // page up
				return focusNext(-pageSize);
			case 34: // page down
				return focusNext(+pageSize);
			case 36: // home
				return focusNext(-Infinity);
			case 35: // end
				return focusNext(+Infinity);
		}
	}

	return false;
}

/* These are linked to in responsive horizontal-split post footer */
function navPrev() { focusNext(-1) && selectFocused(); }
function navNext() { focusNext(+1) && selectFocused(); }

// **************************************************************************
// Posting

// http://stackoverflow.com/a/4716021/21501
function moveCaretToEnd(el) {
	el.focus();
	if (typeof el.selectionStart == "number") {
		el.selectionStart = el.selectionEnd = el.value.length;
	} else if (typeof el.createTextRange != "undefined") {
		var range = el.createTextRange();
		range.collapse(false);
		range.select();
	}
}

function initPosting() {
	initAutoSave();
	moveCaretToEnd($('#postform textarea')[0]);
}

function initAutoSave() {
	var autoSaveCooldown = 2500;

	var $textarea = $('#postform textarea');
	var oldValue = $textarea.val();
	var timer = 0;

	function autoSave() {
		timer = 0;
		$('.autosave-notice').remove();
		$.post('/auto-save', $('#postform').serialize(), function(data, status, xhr) {
			$('<span>')
				.text(xhr.status == 200 ? 'Draft saved.' : 'Error auto-saving draft.')
				.addClass('autosave-notice')
				.insertAfter($('#postform input[name=action-save]'))
				.fadeOut(autoSaveCooldown)
		});
	}

	$textarea.bind('input propertychange', function() {
		var value = $textarea.val();
		if (value != oldValue) {
			oldValue = value;
			$('.autosave-notice').remove();
			if (timer)
				clearTimeout(timer);
			timer = setTimeout(autoSave, autoSaveCooldown);
		}
	});
}

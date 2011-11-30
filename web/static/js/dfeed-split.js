$(document).ready(function() {
	$('body').addClass('widedoc');

	$('.postlink').live('click', function() {
		var path = $(this).attr('href');
		return !selectMessage(path);
	});
	$('tr.thread-post-row').live('mousedown', function() {
		return $(this).find('a.postlink').click();
	}).css('cursor', 'default');

	$(document).keypress(onKeyPress);

	$(window).resize(onResize);
	updateSize();
	$('.group-threads').scrollTop(1000000);

	$(window).bind('popstate', onPopState);
	onPopState();
});

function selectMessage(path) {
	var id = idFromPath(path);
	if (id && findInTree(path)) {
		window.history.pushState(null, null, path);
		onPopState();
		return true;
	}
	return false;
}

function idFromPath(path) {
	if (path.substr(0, 17) == '/discussion/post/')
		return path.substr(17);
	return null;
}

function findInTree(path) {
	var a = $('.group-threads').find('a[href="'+path+'"]');
	if (a.length)
		return a.first().closest('tr.thread-post-row');
	else
		return null;
}

var currentRequest = null;
var currentID = null;

function onPopState() {
	var path = window.location.pathname;
	var id = idFromPath(path);
	var row = findInTree(path);
	if (id && id == currentID)
		return;
	else
	if (id && row) {
		if (currentRequest) {
			currentRequest.abort();
			currentRequest = null;
		}

		$('.group-threads .thread-post-selected').removeClass('thread-post-selected');
		row.addClass('thread-post-selected');
		focusRow(row, true);
		currentID = id;

		showText('Loading message\n<'+id+'> ...');

		currentRequest = $.get('/discussion/split-post/' + id, function(result) {
			currentRequest = null;
			row.find('.forum-unread').removeClass('forum-unread').addClass('forum-read');

			showPost(result);
		});
		currentRequest.error(function(jqXHR, textStatus, errorThrown) {
			currentRequest = null;
			showText('XHR error: ' + textStatus);
		});
	} else {
		showText('No message selected.');
	}

	$('#group-view-mode-placeholder').html(viewModeTemplate.replace('__URL__', location.pathname));
}

function showPost(postHtml) {
	$('#group-split-message')
		.html(postHtml)
		.removeClass('group-split-message-none');
}

function showText(text) {
	$('#group-split-message')
		.text(text)
		.addClass('group-split-message-none');
}

// **************************************************************************

// This hack could probably be achieved using CSS and 100% html/body height.

var resizeTimeout = null;

function updateSize() {
	resizeTimeout = null;

	$('body').attr('style', ''); // WTF, Google Translate?!

	var oldHeight = $('body').height();
	var diff = $(window).height() - oldHeight;
	if (diff != 0) {
		var obj = $('.group-threads');
		if (obj.height() + diff > 0) {
			obj.css('height', obj.height() + diff);
			var newHeight = $('body').height();
			var changed = oldHeight - newHeight;
			obj.css('height', obj.height() - (diff + changed));
		}
	}
}

function onResize() {
	if (resizeTimeout)
		clearTimeout(resizeTimeout);
	resizeTimeout = setTimeout(updateSize, 100);
}

// **************************************************************************

function nestedOffset(element, container) {
	if (element.offsetParent === container)
		return element.offsetTop;
	else
	if (element.offsetParent === container.offsetParent)
		return 0;
	else
		return element.offsetTop + nestedOffset(element.offsetParent, container);
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

function focusRow(row, withMargin) {
	$('.group-threads .thread-post-focused').removeClass('thread-post-focused');
	row.addClass('thread-post-focused');
	scrollIntoView(row[0], $('.group-threads')[0], withMargin);
}

function focusNext(offset, onlyUnread) {
	if (typeof onlyUnread == 'undefined')
		onlyUnread = false;

	var all = $('tr.thread-post-row');
	var count = all.length;
	var current = $('.thread-post-focused');
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
	var focused = $('.thread-post-focused');
	if (focused.length) {
		focused.mousedown();
		return true;
	}
	return false;
}

function onKeyPress(e) {
	var c = String.fromCharCode(e.which);
	var pageSize = $('.group-threads').height() / $('.thread-post-row').eq(0).height();

	switch (c) {
		case 'j':
			return !focusNext(+1);
		case 'k':
			return !focusNext(-1);
		case '\x0D':
			return !selectFocused();
		case ' ':
			return !(focusNext(+1, true) && selectFocused());
	}

	if (e.ctrlKey) {
		switch (e.keyCode) {
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

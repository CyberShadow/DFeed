$(document).ready(function() {
	$('body').addClass('widedoc');

	$('.postlink').live('click', function() {
		var path = $(this).attr('href');
		var id = idFromPath(path);
		if (id && findInTree(path)) {
			window.history.pushState(null, null, path);
			onPopState();
			return false;
		}
		return true;
	});
	$('.thread-post-row').live('mousedown', function() {
		return $(this).find('a.postlink').click();
	}).css('cursor', 'default');

	$(window).resize(onResize);
	updateSize();
	$('.group-threads').scrollTop(1000000);

	$(window).bind('popstate', onPopState);
	onPopState();
});

function idFromPath(path) {
	if (path.substr(0, 17) == '/discussion/post/')
		return path.substr(17);
	return null;
}

function findInTree(path) {
	var a = $('.group-threads').find('a[href="'+path+'"]');
	if (a.length)
		return a.first().closest('tr');
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
		currentID = id;

		showText('Loading message\n<'+id+'> ...');

		scrollIntoView(row[0], $('.group-threads')[0]);

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

function scrollIntoView(element, container) {
	var containerTop = $(container).scrollTop();
	var containerHeight = $(container).height();
	var containerBottom = containerTop + containerHeight;
	//var elemTop = element.offsetTop;
	var elemTop = nestedOffset(element, container);
	var elemBottom = elemTop + $(element).height();	
	if (elemTop < containerTop) {
		$(container).scrollTop(Math.max(0, elemTop - containerHeight/4));
		//$(container).scrollTo(elemTop, 200)
	} else if (elemBottom > containerBottom) {
		$(container).scrollTop(elemBottom - containerHeight + containerHeight/4);
		//$(container).scrollTo(elemBottom - $(container).height(), 200)
	}
}

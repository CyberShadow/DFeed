$(document).ready(function() {
	setInterval(updateSize, 10);
});

function updateSize() {
	var diff = $(window).height() - $('body').height();
	if (diff != 0) {
		var obj = $('.group-threads');
		obj.css('height', obj.height() + diff);
	}
}

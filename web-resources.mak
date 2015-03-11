HTMLTOOL=java -jar ~/htmlcompressor-*.jar --compress-js --compress-css
JSTOOL=java -jar ~/yuicompressor-*.jar --type js
CSSTOOL=java -jar ~/yuicompressor-*.jar --type css

TARGETS : \
	web/skel.htt-opt \
	web/help.htt-opt \
	web/static/css/dfeed.css-opt \
	web/static/js/dfeed-split.js-opt

%.htt-opt : %.htt
	$(HTMLTOOL) < $^ > $@

%.js-opt : %.js
	$(JSTOOL) < $^ > $@

%.css-opt : %.css
	$(CSSTOOL) < $^ > $@

web/skel.htt : dlang.org/forum-template.html
	cp $^ $@

dlang.org/forum-template.html : dlang.org/forum-template.dd
	# cd dlang.org && make --debug -f posix.mak forum-template.html DMD=$(shell which dmd) LATEST=latest DOC_OUTPUT_DIR=.
	dmd -o- -c -D dlang.org/macros.ddoc dlang.org/html.ddoc dlang.org/dlang.org.ddoc dlang.org/windows.ddoc dlang.org/doc.ddoc $^ -Df$@

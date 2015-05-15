HTMLCOMPRESSOR=htmlcompressor-1.5.3.jar
YUICOMPRESSOR=yuicompressor-2.4.8.jar

HTMLTOOL=java -jar $(HTMLCOMPRESSOR) --compress-css
JSTOOL=java -jar $(YUICOMPRESSOR) --type js
CSSTOOL=java -jar $(YUICOMPRESSOR) --type css

TARGETS : \
	web/skel.htt-opt \
	web/help.htt-opt \
	web/static/css/dfeed.css-opt \
	web/static/js/dfeed.js-opt \
	dlang.org/css/cssmenu.css

%.htt-opt : %.htt $(HTMLCOMPRESSOR) $(YUICOMPRESSOR)
	$(HTMLTOOL) < $< > $@.tmp
	mv $@.tmp $@

%.js-opt : %.js $(YUICOMPRESSOR)
	$(JSTOOL) < $< > $@.tmp
	mv $@.tmp $@

%.css-opt : %.css $(YUICOMPRESSOR)
	$(CSSTOOL) < $< > $@.tmp
	mv $@.tmp $@

web/skel.htt : dlang.org/forum-template.html
	cp $^ $@

dlang.org/forum-template.html : dlang.org/forum-template.dd
	# cd dlang.org && make --debug -f posix.mak forum-template.html DMD=$(shell which dmd) LATEST=latest DOC_OUTPUT_DIR=.
	dmd -o- -c -D dlang.org/macros.ddoc dlang.org/html.ddoc dlang.org/dlang.org.ddoc dlang.org/windows.ddoc dlang.org/doc.ddoc $^ -Df$@

dlang.org/css/cssmenu.css : dlang.org/css/cssmenu.css.dd
	dmd -o- -D $^ -Df$@

$(HTMLCOMPRESSOR) :
	wget http://htmlcompressor.googlecode.com/files/$(HTMLCOMPRESSOR)

$(YUICOMPRESSOR) :
	wget https://github.com/yui/yuicompressor/releases/download/v2.4.8/$(YUICOMPRESSOR)

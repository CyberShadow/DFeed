HTMLCOMPRESSOR=htmlcompressor-1.5.3.jar
YUICOMPRESSOR=yuicompressor-2.4.8.jar

HTMLTOOL=java -jar $(HTMLCOMPRESSOR) --compress-css
JSTOOL=java -jar $(YUICOMPRESSOR) --type js
CSSTOOL=java -jar $(YUICOMPRESSOR) --type css

DLANG=web/static/dlang.org

TARGETS : \
	web/skel.min.htt \
	web/help.min.htt \
	web/static/css/dfeed.min.css \
	web/static/js/dfeed.min.js \
	$(DLANG)/css/cssmenu.css

%.min.htt : %.htt $(HTMLCOMPRESSOR) $(YUICOMPRESSOR)
	$(HTMLTOOL) < $< > $@.tmp
	mv $@.tmp $@

%.min.js : %.js $(YUICOMPRESSOR)
	$(JSTOOL) < $< > $@.tmp
	mv $@.tmp $@

%.min.css : %.css $(YUICOMPRESSOR)
	$(CSSTOOL) < $< > $@.tmp
	mv $@.tmp $@

web/skel.htt : $(DLANG)/forum-template.html
	cp $^ $@

$(DLANG)/forum-template.html : $(DLANG)/forum-template.dd
	# cd $(DLANG) && make --debug -f posix.mak forum-template.html DMD=$(shell which dmd) LATEST=latest DOC_OUTPUT_DIR=.
	dmd -o- -c -D $(DLANG)/macros.ddoc $(DLANG)/html.ddoc $(DLANG)/dlang.org.ddoc $(DLANG)/windows.ddoc $(DLANG)/doc.ddoc $^ -Df$@

$(DLANG)/css/cssmenu.css : $(DLANG)/css/cssmenu.css.dd
	dmd -o- -D $^ -Df$@

$(HTMLCOMPRESSOR) :
	wget http://htmlcompressor.googlecode.com/files/$(HTMLCOMPRESSOR)

$(YUICOMPRESSOR) :
	wget https://github.com/yui/yuicompressor/releases/download/v2.4.8/$(YUICOMPRESSOR)

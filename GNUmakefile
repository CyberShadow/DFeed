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
	$(patsubst %.css,%.min.css,$(filter-out $(wildcard $(DLANG)/css/*.min.css), $(wildcard $(DLANG)/css/*.css))) \
	$(patsubst %.js, %.min.js, $(filter-out $(wildcard $(DLANG)/js/*.min.js  ), $(wildcard $(DLANG)/js/*.js  ))) \
	$(DLANG)/css/cssmenu.min.css \
	config/groups.ini

%.min.htt : %.htt $(HTMLCOMPRESSOR) $(YUICOMPRESSOR)
	$(HTMLTOOL) < $< > $@

%.min.js : %.js $(YUICOMPRESSOR)
	$(JSTOOL) < $< > $@

%.min.css : %.css $(YUICOMPRESSOR)
	$(CSSTOOL) < $< > $@

web/skel.htt : $(DLANG)/forum-template.html
	cp $^ $@

DDOC=$(DLANG)/macros.ddoc $(DLANG)/html.ddoc $(DLANG)/dlang.org.ddoc $(DLANG)/windows.ddoc $(DLANG)/doc.ddoc

$(DLANG)/forum-template.html : $(DLANG)/forum-template.dd $(DDOC)
	@# cd $(DLANG) && make --debug -f posix.mak forum-template.html DMD=$(shell which dmd) LATEST=latest DOC_OUTPUT_DIR=.
	dmd -o- -c -D $(DDOC) $^ -Df$@

$(DLANG)/css/cssmenu.css : $(DLANG)/css/cssmenu.css.dd
	dmd -o- -D $^ -Df$@

$(HTMLCOMPRESSOR) :
	wget http://htmlcompressor.googlecode.com/files/$(HTMLCOMPRESSOR)

$(YUICOMPRESSOR) :
	wget https://github.com/yui/yuicompressor/releases/download/v2.4.8/$(YUICOMPRESSOR)

config/groups.ini : config/gengroups.d
	cd config && rdmd -I.. gengroups

.DELETE_ON_ERROR:

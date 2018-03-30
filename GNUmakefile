# Compile resources

HTMLCOMPRESSOR_VERSION=1.5.3
YUICOMPRESSOR_VERSION=2.4.8

HTMLCOMPRESSOR=htmlcompressor-$(HTMLCOMPRESSOR_VERSION).jar
YUICOMPRESSOR=yuicompressor-$(YUICOMPRESSOR_VERSION).jar

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

$(HTMLCOMPRESSOR) :
	wget https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/htmlcompressor/$(HTMLCOMPRESSOR)

$(YUICOMPRESSOR) :
	wget https://github.com/yui/yuicompressor/releases/download/v$(YUICOMPRESSOR_VERSION)/$(YUICOMPRESSOR)

config/groups.ini : config/gengroups.d
	cd config && rdmd gengroups

# Create junction on Windows, in lieu of Git/Windows symlink support
lib/deimos/openssl/ssl.d : lib/deimos-openssl/deimos/openssl/ssl.d
	rm -f lib/deimos/openssl
	cmd /C mklink /J lib/deimos\openssl lib/deimos-openssl\deimos\openssl

.DELETE_ON_ERROR:

HTMLTOOL=java -jar ~/htmlcompressor-*.jar --compress-js --compress-css
JSTOOL=java -jar ~/yuicompressor-*.jar --type js
CSSTOOL=java -jar ~/yuicompressor-*.jar --type css

TARGETS : \
	web/skel.htt-opt \
	web/help.htt-opt \
	web/static/css/dfeed.css-opt \
	web/static/css/style.css-opt \
	web/static/js/dfeed-split.js-opt

%.htt-opt : %.htt
	$(HTMLTOOL) < $^ > $@

%.js-opt : %.js
	$(JSTOOL) < $^ > $@

%.css-opt : %.css
	$(CSSTOOL) < $^ > $@

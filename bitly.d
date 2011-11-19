module bitly;

import std.uri;
import std.file;
import std.string;

import ae.net.http.client;

void shortenURL(string url, void delegate(string) handler)
{
	if (std.file.exists("data/bitly.txt"))
		httpGet(
			format(
				"http://api.bitly.com/v3/shorten?%s&longUrl=%s&format=txt&domain=j.mp",
				readText("data/bitly.txt"),
				std.uri.encodeComponent(url)
			), (string shortened) {
				handler(strip(shortened));
			}, (string error) {
				handler(url);
			});
	else
		handler(url);
}

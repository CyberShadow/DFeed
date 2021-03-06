DFeed
=====

DFeed is:

- an NNTP client
- a mailing list archive
- a forum-like web interface
- an ATOM aggregator
- an IRC bot

DFeed is running on [forum.dlang.org](https://forum.dlang.org/)
and the [#d channel on Libera.Chat](irc://irc.libera.chat/d).

Quick start guide:

```bash
git clone --recursive https://github.com/CyberShadow/DFeed.git
cd DFeed
make
echo "host = news.digitalmars.com" > config/sources/nntp/digitalmars.ini
echo "listen.port = 8080" > config/web.ini
./rebuild # or: dub build
```

On first start, DFeed will download messages from the NNTP server
and save them in the DB. This will need to be done once.
If you don't want to download the entire archive, stop DFeed at any time
and delete the `digitalmars.ini` configuration file.

After starting `dfeed`, you should be able to access the web
interface at http://localhost:8080/.

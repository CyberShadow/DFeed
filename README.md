DFeed
=====

DFeed is:

- an NNTP client
- a mailing list archive
- a forum-like web interface
- an ATOM aggregator
- an IRC bot

DFeed is running on [forum.dlang.org](http://forum.dlang.org/)
and the [#d channel on FreeNode](irc://chat.freenode.net/d).

Quick start guide:

    git clone --recursive git://github.com/CyberShadow/DFeed.git
    cd DFeed
    make
    echo "host = news.digitalmars.com" > config/sources/nntp/digitalmars.ini
    rdmd dfeed

On first start, DFeed will download messages from the NNTP server
and save them in the DB. This will need to be done once.
If you don't want to download the entire archive, stop DFeed at any time
and delete the `digitalmars.ini` configuration file.

After starting `dfeed`, you should be able to access the web
interface at http://localhost/.

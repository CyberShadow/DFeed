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

Currently, many things are specific to forum.dlang.org,
but work is being done to move them out into configuration.

Quick start guide:

    git clone --recursive git://github.com/CyberShadow/DFeed.git
    cd DFeed
    echo "host = news.digitalmars.com" > config/sources/nntp/digitalmars.ini
    rdmd dfeed

On first start, DFeed will download messages from the NNTP server
and save them in the DB. This will need to be done once.
After starting `dfeed`, you should be able to access the web
interface at http://localhost/.

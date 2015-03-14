Proper documentation will come later.
For now, to hack on the web interface:

    git clone --recursive git://github.com/CyberShadow/DFeed.git
    cd DFeed
    rdmd nntpdownload
    rdmd dfeed_web

`nntpdownload` will download messages from the NNTP server and save
them in the DB. This will need to be done once.
After starting `dfeed_web`, you should be able to access the web
interface on http://localhost/.

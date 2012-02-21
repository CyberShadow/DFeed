Proper documentation will come later.
For now, to hack on the web interface:

    git clone git@github.com:CyberShadow/DFeed.git
    cd DFeed
    mkdir data
    sqlite3 data/dfeed.s3db < schema.sql
    echo 80>data/web.txt
    echo localhost>>data/web.txt
    rdmd dfeed_web

It will start downloading NNTP messages and save them in the DB.
This will need to be done once.
You should be able to access the web interface on http://localhost/.

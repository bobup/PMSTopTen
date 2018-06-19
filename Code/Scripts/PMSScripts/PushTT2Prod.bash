#!/bin/bash

# PushTT2Prod.bash - push top ten generated files from dev to production
#	Push generated files from the dev points page to production.
#   BUT, only push the files if they appear "sane" - tests below.
#
# This script assumes that this host can talk to production using its public key.  If that isn't
# true then the user of this script will have to supply the password to production multiple times!!!
#
# PASSED:
#   $1 - the season, e.g. 2017
#

STANDINGSDIR=standings-$1
STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
EMAIL_NOTICE=bobup@acm.org
SIMPLE_SCRIPT_NAME=`basename $0`
DESTINATION_DIR=/usr/home/pacmasters/public_html/pacificmasters.org/sites/default/files/comp/points/$STANDINGSDIR
DESTINATION_URL=https://pacificmasters.org/points/standings-2018/TTStats.html
SERVER_TTSTATS=/tmp/TTStats.$$      # a copy of TTStats from the server prior to the push

# details of what we're pushing:
TARBALL=TT_`date +'%d%b%Y'`.zip
STANDINGSDIRARCHIVE=${STANDINGSDIR}_`date +'%d%b%Y'`.zip
TARDIR=~/Automation/TTPushes
SOURCE_POINTS_DIR=/usr/home/caroline/public_html/pacific-masters.org/sites/default/files/comp/points/
SOURCE_DIR=/usr/home/caroline/public_html/pacific-masters.org/sites/default/files/comp/points/$STANDINGSDIR
SOURCE_TTSTATS=$SOURCE_DIR/TTStats.html

#
# LogMessage - generate a log message to various devices:  email, stdout, and a script
#   log file.
#
# PASSED:
#   $1 - the subject of the log message.
#   $2 - the log message
#   $3 - more message for the email  (can be empty or missing)
#
LogMessage() {
    echo "$1"
    echo "$2"
    /usr/sbin/sendmail -f $EMAIL_NOTICE $EMAIL_NOTICE <<- BUpLM
		Subject: $1
		$2
        $3
		BUpLM
} # end of LogMessage()


#
# DoThePush - do the actual push of the Top Ten files from our dev server (the machine
#   on which this script is running) to our production server.
#
DoThePush() {
    cd $SOURCE_POINTS_DIR > /dev/null
    tar czf $TARBALL $STANDINGSDIR
    mv $TARBALL $TARDIR
    cd $TARDIR >/dev/null
    # push tarball to production
    scp -p $TARBALL pacmasters@pacmasters.pairserver.com:~/public_html/pacificmasters.org/sites/default/files/comp/points
    # archive old production top ten standings and untar the new one in its place
    # Also clean out old tar files.
    ssh pacmasters@pacmasters.pairserver.com \
        "( cd ~/public_html/pacificmasters.org/sites/default/files/comp/points; tar zcf Attic/$STANDINGSDIRARCHIVE $STANDINGSDIR; rm -rf $STANDINGSDIR; tar xf $TARBALL; mv $TARBALL Attic; cd Attic; ls -tp | grep -v '/$' | grep $STANDINGSDIR | tail -n +21 | xargs -I {} rm -- {}; ls -tp | grep -v '/$' | grep TT_ | tail -n +21 | xargs -I {} rm -- {} )"
    
    # clean up old tarballs keeping only the most recent 60
    cd $TARDIR >/dev/null
    ls -tp | grep -v '/$' | tail -n +61 | xargs -I {} rm -- {}
    
    LogMessage "Top Ten standings pushed to PRODUCTION by $SIMPLE_SCRIPT_NAME on `hostname`" \
        "$(cat <<- BUp9
Destination Directory: $DESTINATION_DIR
(STARTed on $STARTDATE, FINISHed on $(date +'%a, %b %d %G at %l:%M:%S %p %Z'))
diff $SERVER_TTSTATS $SOURCE_TTSTATS:
< lines: PRODUCTION server
> lines: DEV server
$(diff $SERVER_TTSTATS $SOURCE_TTSTATS)
BUp9
)"
} # end of DoThePush()

#
# DontDoThePush - this function is called when we decide to NOT do the push.  Instead
#   we'll log and email a message explaining the problem(s) found.
#
DontDoThePush() {
    LogMessage "$1" "The SERVER was NOT updated!
        $2" "diff $SERVER_TTSTATS $SOURCE_TTSTATS:
        < lines: PRODUCTION server
        > lines: DEV server
        $(diff $SERVER_TTSTATS $SOURCE_TTSTATS)"
    exit 1;
} # end of DontDoThePush()

##########################################################################################


# Get to work!

if [ ."$1" = . ]  ; then
    echo "$SIMPLE_SCRIPT_NAME: Missing season on `hostname` - ABORT!"
    exit 1
fi

echo ""; echo '******************** Begin' "$0"

# handle the edge case:  the production version of the TT files does NOT contain the TTStats file
curl -f $DESTINATION_URL >$SERVER_TTSTATS 2>/dev/null
STATUS=$?
if [ "$STATUS" -eq 22 ] ; then
    echo "There is no '$DESTINATION_URL'"
    # do the push!
    DoThePush
else
    SERVER_TOTAL_POINTS=`grep <$SERVER_TTSTATS "E1" | sed -e ' s/^....:[^0-9]*//'`
    DEV_TOTAL_POINTS=`grep <$SOURCE_TTSTATS "E1" | sed -e ' s/^....:[^0-9]*//'`
    
    if [ -z "$SERVER_TOTAL_POINTS" -o -z "$DEV_TOTAL_POINTS" ] ; then
        DontDoThePush "Invalid Total Points - one of them is '0'" \
            "SERVER Total Points is '$SERVER_TOTAL_POINTS', DEV Total Points is '$DEV_TOTAL_POINTS'"
    else
        if [ "$DEV_TOTAL_POINTS" -lt "$SERVER_TOTAL_POINTS" ] ; then
            DontDoThePush "Unexpected Total Points on Dev - it's less than what's on the SERVER" \
                "SERVER Total Points is $SERVER_TOTAL_POINTS, DEV Total Points is $DEV_TOTAL_POINTS"
        fi
    fi
    
    SERVER_OW_SPLASHES=`grep <$SERVER_TTSTATS "G1" | sed -e ' s/^....:[^0-9]*//'`
    DEV_OW_SPLASHES=`grep <$SOURCE_TTSTATS "G1" | sed -e ' s/^....:[^0-9]*//'`
    if [ "$DEV_OW_SPLASHES" -lt "$SERVER_OW_SPLASHES" ] ; then
        DontDoThePush "Unexpected OW Splashes on Dev - it's less than what's on the SERVER" \
            "SERVER OW Splashes is $SERVER_OW_SPLASHES, DEV OW Splashes is $DEV_OW_SPLASHES"
    fi
    
    SERVER_OW_SWIMMERS=`grep <$SERVER_TTSTATS "H1" | sed -e ' s/^....:[^0-9]*//'`
    DEV_OW_SWIMMERS=`grep <$SOURCE_TTSTATS "H1" | sed -e ' s/^....:[^0-9]*//'`
    if [ "$DEV_OW_SWIMMERS" -lt "$SERVER_OW_SWIMMERS" ] ; then
        DontDoThePush "Unexpected OW Swimmers on Dev - it's less than what's on the SERVER" \
            "SERVER OW Swimmers is $SERVER_OW_SWIMMERS, DEV OW Swimmers is $DEV_OW_SWIMMERS"
    fi

    echo The results on DEV look sane - do the push!
    DoThePush    
fi

echo ""; echo '******************** Done!'

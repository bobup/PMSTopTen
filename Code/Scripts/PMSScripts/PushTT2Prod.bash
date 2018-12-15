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
#	$2 - (optional) if passed, and equal to 'y', then do the push even if results don't appear 'sane'
#

SEASON=$1
FORCE_PUSH=$2
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

# temp diff:
TTSTATS_DIFF=/tmp/TTStatsDiff.$$

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
    ssh pacmasters@pacmasters.pairserver.com \
        "( cd ~/public_html/pacificmasters.org/sites/default/files/comp/points; tar zcf Attic/$STANDINGSDIRARCHIVE $STANDINGSDIR; rm -rf $STANDINGSDIR; tar xf $TARBALL; mv $TARBALL Attic; cd Attic; ls -tp | grep -v '/$' | grep $STANDINGSDIR | tail -n +21 | xargs -I {} rm -- {}; ls -tp | grep -v '/$' | grep TT_ | tail -n +21 | xargs -I {} rm -- {} )"
    
    # clean up old tarballs keeping only the most recent 60
    cd $TARDIR >/dev/null
    ls -tp | grep -v '/$' | tail -n +61 | xargs -I {} rm -- {}
    
    LogMessage "$SEASON Top Ten standings pushed to PRODUCTION by $SIMPLE_SCRIPT_NAME on `hostname`" \
        "$(cat <<- BUp9
Destination Directory: $DESTINATION_DIR
(STARTed on $STARTDATE, FINISHed on $(date +'%a, %b %d %G at %l:%M:%S %p %Z'))
diff $SERVER_TTSTATS $SOURCE_TTSTATS :
< lines: PRODUCTION server, > lines: DEV server
$(cat $TTSTATS_DIFF)
BUp9
)"
} # end of DoThePush()

#
# DontDoThePush - this function is called when we decide to NOT do the push.  Instead
#   we'll log and email a message explaining the problem(s) found.
#
DontDoThePush() {
	if [ .$FORCE_PUSH == .y ] ; then
		LogMessage "$1" "The SERVER was FORCE updated! 
			$2"
		DoThePush
	else
		LogMessage "$1" "The SERVER was NOT updated!
			$2" "diff $SERVER_TTSTATS
				$SOURCE_TTSTATS :
			< lines: PRODUCTION server, > lines: DEV server
			$(cat $TTSTATS_DIFF)"
	fi		
    exit 1;
} # end of DontDoThePush()

##########################################################################################

# Get to work!

if [ ."$1" = . ]  ; then
    echo "$SIMPLE_SCRIPT_NAME: Missing season on `hostname` - ABORT!"
    exit 1
fi

# compute the full path name of the directory holding this script:
SCRIPT_DIR=$(dirname $0)
# see if our semaphore exists (put there by DoFetchAndProcessTopten) - if it does we're 
# going to refuse to do anything!
GENERATED_DIR=$SCRIPT_DIR/../../../GeneratedFiles/Generated-$1
SEMAPHORE=$GENERATED_DIR/DoFetchAndProcessTopten_Semaphore
if [ -f $SEMAPHORE ] ; then
    echo "$SIMPLE_SCRIPT_NAME: $SEMAPHORE has existed since $(cat $SEMAPHORE) - ABORT!"
    exit 1
fi

echo ""; echo '******************** Begin' "$0"

# handle the edge case:  the production version of the TT files does NOT contain the TTStats file
curl -f $DESTINATION_URL >$SERVER_TTSTATS 2>/dev/null
STATUS=$?
if [ "$STATUS" -eq 22 ] ; then
    echo "There is no '$DESTINATION_URL'" | tee >$TTSTATS_DIFF
    # do the push!
    DoThePush
else
    # before we do anything first compare the current Production TTStats with the newly generated TTStats on dev
    diff $SERVER_TTSTATS $SOURCE_TTSTATS >$TTSTATS_DIFF
    
    SERVER_TOTAL_POINTS=`grep <$SERVER_TTSTATS "E1" | sed -e ' s/^....:[^0-9]*//'`
    SERVER_ADJUSTED_POINTS=$[SERVER_TOTAL_POINTS-$[SERVER_TOTAL_POINTS/20]]
    DEV_TOTAL_POINTS=`grep <$SOURCE_TTSTATS "E1" | sed -e ' s/^....:[^0-9]*//'`
    
    if [ -z "$SERVER_TOTAL_POINTS" -o -z "$DEV_TOTAL_POINTS" ] ; then
        DontDoThePush "$SEASON: Invalid Total Points - one of them is '0'" \
            "SERVER Total Points is '$SERVER_TOTAL_POINTS', DEV Total Points is '$DEV_TOTAL_POINTS'"
    else
        if [ "$DEV_TOTAL_POINTS" -lt "$SERVER_ADJUSTED_POINTS" ] ; then
            DontDoThePush "$SEASON: Unexpected Total Points on Dev - it's less than 95% of what's on the SERVER" \
                "SERVER Total Points is $SERVER_TOTAL_POINTS (95%=$SERVER_ADJUSTED_POINTS), DEV Total Points is $DEV_TOTAL_POINTS"
        fi
    fi
    
    SERVER_OW_SPLASHES=`grep <$SERVER_TTSTATS "G1" | sed -e ' s/^....:[^0-9]*//'`
    SERVER_ADJUSTED_OW_SPLASHES=$[SERVER_OW_SPLASHES-$[SERVER_OW_SPLASHES/20]]
    DEV_OW_SPLASHES=`grep <$SOURCE_TTSTATS "G1" | sed -e ' s/^....:[^0-9]*//'`
    if [ "$DEV_OW_SPLASHES" -lt "$SERVER_ADJUSTED_OW_SPLASHES" ] ; then
        DontDoThePush "$SEASON: Unexpected OW Splashes on Dev - it's less than 95% of what's on the SERVER" \
            "SERVER OW Splashes is $SERVER_OW_SPLASHES (95%=$SERVER_ADJUSTED_OW_SPLASHES), DEV OW Splashes is $DEV_OW_SPLASHES"
    fi
    
    SERVER_OW_SWIMMERS=`grep <$SERVER_TTSTATS "H1" | sed -e ' s/^....:[^0-9]*//'`
    SERVER_ADJUSTED_OW_SWIMMERS=$[SERVER_OW_SWIMMERS-$[SERVER_OW_SWIMMERS/20]]
    DEV_OW_SWIMMERS=`grep <$SOURCE_TTSTATS "H1" | sed -e ' s/^....:[^0-9]*//'`
    if [ "$DEV_OW_SWIMMERS" -lt "$SERVER_ADJUSTED_OW_SWIMMERS" ] ; then
        DontDoThePush "$SEASON: Unexpected OW Swimmers on Dev - it's less than 95% of what's on the SERVER" \
            "SERVER OW Swimmers is $SERVER_OW_SWIMMERS (95%=$SERVER_ADJUSTED_OW_SWIMMERS), DEV OW Swimmers is $DEV_OW_SWIMMERS"
    fi

    echo The results on DEV look sane - do the push!
    DoThePush    
fi

echo ""; echo '******************** Done!'


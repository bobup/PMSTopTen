#!/bin/bash

# ProdPushTT.bash - push top ten generated files from dev to production
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
# Copyright (c) 2017 Bob Upshaw.  This software is covered under the Open Source MIT License 


SEASON=$1
FORCE_PUSH=$2
STANDINGSDIR=standings-$SEASON
STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
EMAIL_NOTICE=bobup@acm.org
SIMPLE_SCRIPT_NAME=`basename $0`
DESTINATION_DIR=/usr/home/pacmasters/public_html/pacificmasters.org/sites/default/files/comp/points/$STANDINGSDIR
DESTINATION_BASE_URL=https://data.pacificmasters.org/points/standings-$SEASON
DESTINATION_URL=https://data.pacificmasters.org/points/standings-$SEASON/TTStats.html
DESTINATION_URL=$DESTINATION_BASE_URL/TTStats.html
SERVER_TTSTATS=/tmp/TTStats.$$      # a copy of TTStats from the server prior to the push
# compute the full path name of the directory holding this script.  We'll find the
# other scripts using this path:
SCRIPT_DIR=$(dirname $0)
# from the SCRIPT_DIR compute the full path name of the directory holding our Code:
CODE_DIR=$SCRIPT_DIR/../..
USERHOST=$USER" on "`hostname`


# details of what we're pushing:
TARBALL=TT-$SEASON_`date +'%d%b%Y'`.zip
STANDINGSDIRARCHIVE=${STANDINGSDIR}_`date +'%d%b%Y'`.zip
TARDIR=~/Automation/TTPushes
# make sure out TARDIR exists:
mkdir -p $TARDIR
SOURCE_POINTS_DIR=/usr/home/pacdev/public_html/pacmdev.org/sites/default/files/comp/points/
SOURCE_DIR=/usr/home/pacdev/public_html/pacmdev.org/sites/default/files/comp/points/$STANDINGSDIR
SOURCE_TTSTATS=$SOURCE_DIR/TTStats.html

# temp diff:
TTSTATS_DIFF=/tmp/TTStatsDiff.$$
TTSTATS_DIFF2=/tmp/TTStatsDiff-2.$$

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
        "( cd ~/public_html/pacificmasters.org/sites/default/files/comp/points; tar zcf Attic/$STANDINGSDIRARCHIVE $STANDINGSDIR; rm -rf $STANDINGSDIR; tar xf $TARBALL; mv $TARBALL Attic; cd Attic; ls -tp | grep -v '/$' | grep $STANDINGSDIR | tail -n +21 | xargs -I {} rm -- {}; ls -tp | grep -v '/$' | grep TT- | tail -n +21 | xargs -I {} rm -- {} )"
    
    # clean up old tarballs keeping only the most recent 60
    cd $TARDIR >/dev/null
    ls -tp | grep -v '/$' | tail -n +61 | xargs -I {} rm -- {}
    
    LogMessage "$SEASON Top Ten standings pushed to PRODUCTION by $SIMPLE_SCRIPT_NAME on $USERHOST" \
        "$(cat <<- BUp9
Source Directory (dev points dir): $SOURCE_DIR
Destination Directory: $DESTINATION_DIR
Destination URL: $DESTINATION_BASE_URL
(STARTed on $STARTDATE, FINISHed on $(date +'%a, %b %d %G at %l:%M:%S %p %Z'))
diff $SERVER_TTSTATS $SOURCE_TTSTATS :
$(cat $TTSTATS_DIFF2)
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
			$(cat $TTSTATS_DIFF2)"
	fi		
    exit 1;
} # end of DontDoThePush()

##########################################################################################

# Get to work!

if [ ."$1" = . ]  ; then
    echo "$SIMPLE_SCRIPT_NAME: Missing season on $USERHOST - ABORT!"
    exit 1
fi

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
    echo "There is no '$DESTINATION_URL'" | tee >$TTSTATS_DIFF2
    # do the push!
    DoThePush
else
    # before we do anything first compare the current Production TTStats with the newly generated TTStats on dev
    diff $SERVER_TTSTATS $SOURCE_TTSTATS >$TTSTATS_DIFF
    # augment the diff output to indicate what lines come from what server, and to prepend every '<' 
    # and '>' line with a dot ('.') to avoid a problem with sendmail turning '>' into '|':
    $CODE_DIR/TTStatsDiffFilter.pl $TTSTATS_DIFF >$TTSTATS_DIFF2
    
    SERVER_TOTAL_POINTS=`grep <$SERVER_TTSTATS "E1" | sed -e ' s/^....:[^0-9]*//'`
    SERVER_ADJUSTED_POINTS=$[SERVER_TOTAL_POINTS-$[SERVER_TOTAL_POINTS/20]]
    DEV_TOTAL_POINTS=`grep <$SOURCE_TTSTATS "E1" | sed -e ' s/^....:[^0-9]*//'`
    
#    if [ -z "$SERVER_TOTAL_POINTS" -o -z "$DEV_TOTAL_POINTS" ] ; then
# NOTE: the above 'if' was replaced with the 'if' below on 3Jan2023 (bup). It was originally intended to catch problems
# reading the TTStats file from the production server, but when a season starts it's possible it starts with 0 Points
# as it did for the 2023 season. So we're going to ignore trying to detect problems reading the server since if such
# a problem exists it's likely we won't be able to do the push, and if we do we can always manually fix a bad push.
    if [ -z "$DEV_TOTAL_POINTS" ] ; then
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

# clean up:
rm -f $SERVER_TTSTATS $TTSTATS_DIFF $TTSTATS_DIFF2

echo ""; echo '******************** End' "$0"


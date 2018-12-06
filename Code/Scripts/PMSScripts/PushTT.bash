#!/bin/bash


# PushTT.bash - push top ten generated files from the build directory to dev, and
#   if successful then to production
#
# This script uses other scripts to do the work, so it is those scripts that dictate the rules.
#
# PASSED:
#   $1 - the season, e.g. 2017
#	$2 - (optional) if passed, and equal to 'y', then do the push even if results don't appear 'sane'
#		(Used for production push only)
#

SIMPLE_SCRIPT_NAME=`basename $0`
# compute the full path name of the directory holding this script.  We'll find the
# other scripts using this path:
SCRIPT_DIR=$(dirname $0)

# Get to work!

if [ ."$1" = . ]  ; then
    echo "$SIMPLE_SCRIPT_NAME: Missing season on `hostname` - ABORT!"
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
$SCRIPT_DIR/PushTT2Dev.bash $1
PUSH_DEV_STATUS=$?
if [ "$PUSH_DEV_STATUS" -eq 0 ] ; then
    # push to dev was successful - push to production if appropriate
    $SCRIPT_DIR/PushTT2Prod.bash $1 $2
else
    echo "Push to dev failed, so no auto push to production."
fi

echo ""; echo '******************** Done! with' "$0"


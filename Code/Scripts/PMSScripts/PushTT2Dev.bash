#!/bin/bash


# PushTT2Dev.bash - this script is intended to be executed on the PMS Dev machine ONLY.  
#	It will push the top ten generated files to the Dev points page, e.g.:
#			http://www.pacific-masters.org/points/standings-$1/
#	ONLY IF the index.html file exists in the "Generated files" directory.
#
# PASSED:
#	$1 - the season, e.g. 2017
#	$2 - ignored, but must be supplied if $3 is supplied
#	$3 - (optional) if passed, and equal to 'y', then don't send an email if we don't do the push because
#		the index.html file can't be found.
#
# NOTES:
#	The location of the "Generated files" directory is derived from the location of this script.
#	This script is assumed to be located in the Top Ten Scripts directory.
#

STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
EMAIL_NOTICE=bobup@acm.org
SIMPLE_SCRIPT_NAME=`basename $0`
DESTINATION_DIR=/usr/home/caroline/public_html/pacific-masters.org/sites/default/files/comp/points/standings-$1
NOEMAIL=$3

# FINAL_EXIT_STATUS is 0 if we successfully push to dev, or 1 if not
FINAL_EXIT_STATUS=0

#
# LogMessage - generate a log message to various devices:  email, stdout, and a script 
#	log file.
#
# PASSED:
#	$1 - the subject of the log message.
#	$2 - the log message
#
LogMessage() {
	MSG=""
	echo "$2"
	if [ .$NOEMAIL != '.y' ] ; then
		/usr/sbin/sendmail -f $EMAIL_NOTICE $EMAIL_NOTICE <<- BUpLM
			Subject: $1
			$2
			$MSG
			BUpLM
	else
		echo "(No email sent.)"
	fi
} # end of LogMessage()

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

# compute the full path name of the directory holding this script.  We'll find the
# Generated files directory relative to this directory:
script_dir=$(dirname $0)
# Next compute the full path name of the directory into which the generated files are placed:
pushd $script_dir/../../../GeneratedFiles >/dev/null; 
GENERATED_DIR=`pwd -P`/Generated-$1
# make sure the GENERATED_DIR exists
mkdir -p $GENERATED_DIR
cd $GENERATED_DIR
# do we have the generated files that we want to push?
if [ -e "index.html" ] ; then
	# yes!  get to work:
	mkdir -p $DESTINATION_DIR
	cp -r *  $DESTINATION_DIR
	NOEMAIL=			# always send an email
	LogMessage "$1 Top Ten standings pushed to dev by $SIMPLE_SCRIPT_NAME on `hostname`" \
		"$(cat <<- BUp9 
		Destination Directory: $DESTINATION_DIR
		(STARTed on $STARTDATE, FINISHed on $(date +'%a, %b %d %G at %l:%M:%S %p %Z'))
		BUp9
		)"
else
	# NO!  Nothing to push:
	LogMessage "$1 Top Ten standings NOT pushed to dev by $SIMPLE_SCRIPT_NAME on `hostname`" \
		"$(cat <<- BUp9 
		The file
        '$GENERATED_DIR/index.html'
        does not exist thus was not created.  Either there was an error or
        (more likely) there were no changes detected so no Top Ten results were generated.
		BUp9
		)"
    FINAL_EXIT_STATUS=1;
fi

popd >/dev/null
echo ""; echo '******************** End of ' "$0"

exit $FINAL_EXIT_STATUS;

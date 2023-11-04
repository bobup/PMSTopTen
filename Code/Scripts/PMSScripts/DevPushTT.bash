#!/bin/bash


# DevPushTT.bash - this script is intended to be executed on the PMS Dev machine ONLY.  
#	It will push the top ten generated files to the Dev points page, e.g.:
#			http://www.pacmdev.org/points/standings-$1/
#	ONLY IF the index.html file exists in the "Generated files" directory.
#
# PASSED:
#	$1 - the season, e.g. 2017
#	$2 - One of:
#		-gGenSubDir - the sub directory of the default directory from which files are pushed.
#			Also used as the sub directory of the default directory to which the files are pushed.
#		xxx - something else, in which case it's ignored. Only necessary if you want to pass
#		a value for $3
#	$3 - (optional) if passed, and equal to 'y', then don't send an email if we don't do the push when
#		the index.html file can't be found.
#
# NOTES:
#	The location of the "Generated files" directory is derived from the location of this script.
#	This script is assumed to be located in the Top Ten PMSScripts directory.
#	NOTE: prior to pushing files to the Dev points directory all existing files/directories in that
#		directory will be removed EXCEPT:
#			- The Support directory (probably a link)
#			- Any file or directory in the Dev points directory whose name ends with "test" in 
#				any case.
#	NOTE: the Support directory (usually pointed to by a link in the standings page to the real
#	Support directory located in the Dev points page) is NOT updated by this script.
#
# Copyright (c) 2017 Bob Upshaw.  This software is covered under the Open Source MIT License 


STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
EMAIL_NOTICE=bobup@acm.org
SIMPLE_SCRIPT_NAME=`basename $0`
DESTINATION_DIR=/usr/home/pacdev/public_html/pacmdev.org/sites/default/files/comp/points/standings-$1
ARG2=$2
NOEMAIL=$3
USERHOST=$USER" at "`hostname`

# FINAL_EXIT_STATUS is 0 if we successfully push to dev, or 1 if not
FINAL_EXIT_STATUS=0

# do we have a GenSubDir?
genSubDir=""
if [ .$ARG2 != . ] ; then
	flag=`echo $ARG2 | cut -c 1-2`
	if [ .$flag = .-g ] ; then
		genSubDir=`echo $ARG2 | cut -c 3-`
		DESTINATION_DIR=$DESTINATION_DIR/$genSubDir
	fi
fi

#
# LogMessage - generate a log message to various devices:  email and stdout
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
	echo "$SIMPLE_SCRIPT_NAME: Missing season on $USERHOST - ABORT!"
	exit 1
fi

# compute the full path name of the directory holding this script.  We'll find the
# Generated files directory relative to this directory:
SCRIPT_DIR=$(dirname $0)
# see if our semaphore exists (put there by DoFetchAndProcessTopten) - if it does we're 
# going to refuse to do anything!
DEFAULT_GENERATED_DIR=$SCRIPT_DIR/../../../GeneratedFiles/Generated-$1
SEMAPHORE=$DEFAULT_GENERATED_DIR/DoFetchAndProcessTopten_Semaphore
if [ -f $SEMAPHORE ] ; then
    echo "$SIMPLE_SCRIPT_NAME: $SEMAPHORE has existed since $(cat $SEMAPHORE) - ABORT!"
    exit 1
fi


echo ""; echo '******************** Begin' "$0"

# Next compute the full path name of the directory into which the generated files were placed
# and from which we'll push to the dev points page
GENERATED_DIR=$SCRIPT_DIR/../../../GeneratedFiles/Generated-$1/$genSubDir
# make sure the GENERATED_DIR exists
mkdir -p $GENERATED_DIR		# should never happen!
cd $GENERATED_DIR
# do we have the generated files that we want to push?
if [ -e "index.html" ] ; then
	# yes!  get to work:
	mkdir -p $DESTINATION_DIR
	# remove old files from DESTINATION_DIR
	shopt -s nocasematch
	for filename in $DESTINATION_DIR/* ; do
		if [[ $filename != *"Support" ]] ; then
			if [[ $filename != *"test" ]] ; then
				#echo "remove '$filename'"
				rm -rf $filename
			fi
		fi
	done
	shopt -u nocasematch
	# now, do the push:	
	cp -p -r *  $DESTINATION_DIR
	NOEMAIL=			# always send an email
	LogMessage "$1 Top Ten standings pushed to dev by $SIMPLE_SCRIPT_NAME on $USERHOST" \
		"$(cat <<- BUp9 
		Generated Directory: $GENERATED_DIR
		Destination Directory: $DESTINATION_DIR
		(STARTed on $STARTDATE, FINISHed on $(date +'%a, %b %d %G at %l:%M:%S %p %Z'))
		BUp9
		)"
else
	# NO!  Nothing to push:
	LogMessage "$1 Top Ten standings NOT pushed to dev by $SIMPLE_SCRIPT_NAME on $USERHOST" \
		"$(cat <<- BUp9 
		The file
        '$GENERATED_DIR/index.html'
        does not exist thus was not created.  Either there was an error or
        (more likely) there were no changes detected so no Top Ten results were generated.
		BUp9
		)"
    FINAL_EXIT_STATUS=1;
fi

echo ""; echo '******************** End of ' "$0"

exit $FINAL_EXIT_STATUS;

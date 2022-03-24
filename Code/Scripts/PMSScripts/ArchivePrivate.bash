#!/bin/bash

# ArchivePrivate - construct an archive of all private data files that cannot otherwise
#	be stored in a public-visible source code system.
# This script is PMSTopten specific.
#
# It is assumed that this script is located in the Scripts/PMSScripts directory.
# To execute just run this script with no arguments. Your CWD can be anywhere, since
#	it will use the location of the script to find the root of the PMSTopten tree.
#

STARTDATE=`date +'%a, %b %d %G at %l:%M:%S %p %Z'`
SIMPLE_SCRIPT_NAME=`basename $0`
TARBALL_SIMPLE_NAME=PrivateTTData-`date +%d%b%Y`.tar
SCRIPT_DIR=$(dirname $0)
pushd $SCRIPT_DIR >/dev/null ; SCRIPT_DIR_FULL_NAME=`pwd -P` ; popd >/dev/null
ARCHIVE_DIR=$SCRIPT_DIR_FULL_NAME/../../../../Private/TTPrivateArchives
mkdir -p $ARCHIVE_DIR
pushd $ARCHIVE_DIR >/dev/null ; TARBALL_DIR=`pwd -P` ; popd >/dev/null
TARBALL_FULL_NAME=$TARBALL_DIR/$TARBALL_SIMPLE_NAME

pushd $SCRIPT_DIR_FULL_NAME/../../../  >/dev/null

tar cvf $TARBALL_FULL_NAME \
			SeasonData/Season-*/PMSSwimmerData/*RSIND*.csv \
			SeasonData/Season-*/properties_DB-*.txt

echo "$SIMPLE_SCRIPT_NAME: Done constructing $TARBALL_FULL_NAME"


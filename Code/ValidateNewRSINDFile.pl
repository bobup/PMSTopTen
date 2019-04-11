#!/usr/bin/perl -w


# ValidateNewRSINDFile.pl - a program that is used to run validation checks on an RSIND file
#	prior to installing for use by our programs.
#
# This program is executed with two required arguments:
#   $1:  the (full path) name of the RSIND file to analyze
#   $2:  the year being processed


my $debug = 1;

use diagnostics;
use strict;
use warnings;
 
use POSIX qw(strftime);
use File::Basename;
use File::Path qw(make_path remove_tree);
use Cwd 'abs_path';
use Spreadsheet::Read;


my $appProgName;	# name of this program
my $appDirName;     # directory containing the application we're running
my $appRootDir;		# directory containing the appDirName directory
my $sourceData;		# full path of directory containing the "source data" which we process to create the generated files


BEGIN {
	# Get the name of the program we're running:
	$appProgName = basename( $0 );
	die( "Can't determine the name of the program being run - did you use/require 'File::Basename' and its prerequisites?")
		if( (!defined $appProgName) || ($appProgName eq "") );
	print "Starting $appProgName...\n";
	
	# The program we're running is in a directory we call the "appDirName".  The files we
	# generate are all located in directories relative to the
	# appDirName directory.
	#
	$appDirName = dirname( $0 );     # directory containing the application we're running, e.g.
									# e.g. /Users/bobup/Documents/workspace/TopTen-2016
										# or ./Code/
	die( "${appProgName}:: Can't determine our running directory - did you use 'File::Basename' and its prerequisites?")
		if( (!defined $appDirName) || ($appDirName eq "") );
	# convert our application directory into a full path:
	$appDirName = abs_path( $appDirName );		# now we're sure it's a full path name that begins with a '/'

	# The 'appRootDir' is the parent directory of the appDirName:
	$appRootDir = dirname($appDirName);		# e.g. /Users/bobup/Development/PacificMasters/PMSOWPoints/
	die( "${appProgName}:: The parent directory of '$appDirName' is not a directory! (A permission problem?)" )
		if( !-d $appRootDir );
	print "  ...with the app dir name '$appDirName' and app root of '$appRootDir'...\n";
	
	# initialize our source data directory name:
#	$sourceData = "$appRootDir/SeasonData";	
}

my $UsageString = <<bup
Usage:  
	$appProgName full-path-RSIND year-being-processed
where:
	full-path-RSIND - the RSIND file to analyze
	year-being-processed - the year to process, e.g. 2016.  
bup
;

use lib "$appDirName/TTPerlModules";
#require TT_Util;
require TT_SheetSupport;
#require TT_Struct;
require TT_Logging;

use FindBin;
use File::Spec;
use lib File::Spec->catdir( $FindBin::Bin, '..', '..', 'PMSPerlModules' );
require PMS_ImportPMSData;
require PMSLogging;

# the date of executation, in the form 24Mar16
my $dateString = strftime( "%d%b%g", localtime() );
# ... and in the form March 24, 2016
my $generationDate = strftime( "%B %e, %G", localtime() );
PMSStruct::GetMacrosRef()->{"GenerationDate"} = $generationDate;
# ... and in the form Tue Mar 27 2018 - 09:34:17 PM EST
my $generationTimeDate = strftime( "%a %b %d %G - %r %Z", localtime() );
PMSStruct::GetMacrosRef()->{"GenerationTimeDate"} = $generationTimeDate;
# ... and in MySql format (yyyy-mm-dd):
my $mysqlDate = strftime( "%F", localtime() );
PMSStruct::GetMacrosRef()->{"MySqlDate"} = $mysqlDate;

############################################################################################################
# get to work - initialize the program
############################################################################################################

# get the arguments:
my $yearBeingProcessed ="";
my $FullRSINDFileName = "";

my $arg;
my $argNum = 0;
my $numErrors = 0;
while( defined( $arg = shift ) ) {
	$argNum++;
	my $value = PMSUtil::trim($arg);
	# switch( $argNum ) {  --- I sure wish I had a switch statement...
	if( $argNum == 1 ) {
		$FullRSINDFileName = $value;
	} elsif( $argNum == 2 ) {
		$yearBeingProcessed = $value;
	} else {
		print "${appProgName}:: ERROR:  Invalid argument (#$argNum): '$arg'\n";
		$numErrors++;
	}
} # end of while - done getting command line args

if( $yearBeingProcessed eq "" ) {
	# no year to process - abort!
	die "$appProgName: no year to process - Abort!";
} elsif( $FullRSINDFileName eq "" ) {
	die "$appProgName: no RSIND file to process - Abort!";
}

# Output file/directories:
my $generatedDirName = "$appRootDir/GeneratedFiles/Generated-$yearBeingProcessed/";
# does this directory exist?
if( ! -e $generatedDirName ) {
	# neither file nor directory with this name exists - create it
	my $count = File::Path::make_path( $generatedDirName );
	if( $count == 0 ) {
		die "Attempting to create '$generatedDirName' failed to create any directories.";
	}
} elsif( ! -d $generatedDirName ) {
	die "A file with the name '$generatedDirName' exists - it must be a directory.  Abort.";
} elsif( ! -w $generatedDirName ) {
	die "The directory '$generatedDirName' is not writable.  Abort.";
}

###
### Initialalize log file
###
my $logFileName = $generatedDirName . "ValidateNewRSINDFile-$yearBeingProcessed.txt";
# open the log file so we can log errors and debugging info:
if( my $tmp = PMSLogging::InitLogging( $logFileName )) { die $tmp; }
print "Log File: $logFileName\n";
PMSLogging::PrintLog( "", "", "Log file created on $generationTimeDate; Year being analyzed: $yearBeingProcessed" );

###
### Analyze the RSIND file
###

PMSLogging::PrintLog( "", "", "Using the RSIDN file '$FullRSINDFileName", 1 );

# get some info about this spreadsheet (e.g. # sheets, # rows and columns in first sheet, etc)
my $g_ref = ReadData( $FullRSINDFileName );
# $g_ref is an array reference
# $g_ref->[0] is a reference to a hashtable:  the "control hash"
my $numSheets = $g_ref->[0]{sheets};        # number of sheets, including empty sheets
print "\nfile $FullRSINDFileName:\n  Number of sheets:  $numSheets.\n  Names of non-empty sheets:\n" 
	if( $debug > 0);
my $sheetNames_ref = $g_ref->[0]{sheet};  # reference to a hashtable containing names of non-empty sheets.  key = sheet
										  # name, value = monotonically increasing integer starting at 1 
my %tmp = % { $sheetNames_ref } ;         # hashtable of sheet names (above)
my ($sheetName);
foreach $sheetName( sort { $tmp{$a} <=> $tmp{$b} } keys %tmp ) {
	print "    $sheetName\n" if( $debug > 0 );
}

# get the first sheet
my $g_sheet1_ref = $g_ref->[1];         # reference to the hashtable representing the sheet
my $numRowsInSpreadsheet = $g_sheet1_ref->{maxrow};	# number of rows in RSIDN file
my $numColumnsInSpreadsheet = $g_sheet1_ref->{maxcol};
print "numRows=$numRowsInSpreadsheet, numCols=$numColumnsInSpreadsheet\n" if( $debug > 0 );

# pass through the sheet looking at each row:
my $rowNum;
my $rowRef = {};
for( $rowNum = 2; $rowNum <= $numRowsInSpreadsheet; $rowNum++ ) {
	if( ($rowNum % 1000) == 0 ) {
		print "...working on row $rowNum...\n";
	}

	PMS_ImportPMSData::GetRSINDRow( $rowRef, $rowNum, $g_sheet1_ref, $yearBeingProcessed, $FullRSINDFileName );

}
$rowNum--;
PMSLogging::PrintLog( "", "", "$appProgName: analysis of $rowNum rows from \n" .
	"    $FullRSINDFileName\n" .
	"    complete." , 1 );




# end of ValidateNewRSINDFile.pl



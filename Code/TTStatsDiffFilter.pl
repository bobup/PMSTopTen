#!/usr/bin/perl
#
# TTStatsDiffFilter - process the file produced by diff showing the difference between AGSOTY on dev with
#	AGSOTY on prod.  This filter will make the diff file a bit more human friendly.
#

use strict;
use lib '/Users/bobup/Development/PacificMasters/PMSPerlModules';
use DateTime::Format::Strptime;
use POSIX 'strftime';
use File::Basename;
use Cwd 'abs_path';


require PMSUtil;




my $debug = 0;

# define the full path name of the diff file to be processed:
my $TTSTATS_DIFF;


my $appProgName;	# name of this program
my $appDirName;     # directory containing the application we're running
my $appRootDir;		# directory containing the appDirName directory
my $sourceData;		# full path of directory containing the "source data" which we process to create the generated files

BEGIN {
	# Get the name of the program we're running:
	$appProgName = basename( $0 );
	die( "Can't determine the name of the program being run - did you use/require 'File::Basename' and its prerequisites?")
		if( (!defined $appProgName) || ($appProgName eq "") );
	if( $debug ) {
		print "Starting $appProgName...\n";
	}
	
	# The program we're running is in a directory we call the "appDirName".
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
	if( $debug ) {
		print "  ...with the app dir name '$appDirName' and app root of '$appRootDir'...\n";
	}
	
	# initialize our source data directory name:
	$sourceData = "$appRootDir/SeasonData";	
}

my $UsageString = <<bup
Usage:  
	$appProgName -h StatsDiff
where:
	-h - produce this message
	StatsDiff - the full path name of the file containing a diff between two AGSOTYs
	Example:
	------
		76,77c76,77
		< [C5]:    352              30-34           F
		< [C6]:    444              30-34           M
		---
		> [C5]:    355              30-34           F
		> [C6]:    445              30-34           M
		146c146
		< [E1]:    101529
		---
		> [E1]:    101683
		156,157c156,157
		< [F4]:    276              25-29:30-34
		< [F5]:    6386             30-34
		...........etc.........
	------
	The goal of this program is to turn the diff into this:
	------
		NOTE:  .< lines: PRODUCTION server, .> lines: DEV server

		[C]: Number of splashes per age group and gender:
		76,77c76,77											<- diff change line
		.< [C5]:    352              30-34           F		<- diff row
		.< [C6]:    444              30-34           M
		---
		.> [C5]:    355              30-34           F
		.> [C6]:    445              30-34           M

		[E]: Number of total points earned (some points may be counted twice for a swimmer who swam
      		in two age groups):
		146c146
		.< [E1]:    101529
		---
		.> [E1]:    101683
		156,157c156,157
		
		[F]: Number of points earned by each age group (includes "combined" age groups):
		156,157c156,157
		.< [F4]:    276              25-29:30-34
		.< [F5]:    6386             30-34
		...........etc.........
	------
bup
;


# descriptions of each diff row:
my %row;
$row{'A'} = "[A]: Number of swimmers who swam in exactly one age group (with and without points) by gender";
$row{'B'} = "[B]: Number of swimmers who swam in two age groups (with and without points) by gender";
$row{'C'} = "[C]: Number of splashes per age group and gender";
$row{'D'} = "[D]: Number of swimmers who earned points by gender and age group.  Some swimmers may be " . 
            "counted twice if they earned points in two age groups";
$row{'E'} = "[E]: Number of total points earned (some points may be counted twice for a swimmer who swam " .
            "in two age groups";
$row{'F'} = "[F]: Number of points earned by each age group (includes \"combined\" age groups)";
$row{'G'} = "[G]: Number of Open Water splashes (with and without points)";
$row{'H'} = "[H]: Number of swimmers who swam at least one Open Water event (with and without points)";

my $previousDescriptionType = "@";		# set to letter of the last description we output


###  get the program arguments
my $arg;
my $numErrors = 0;
while( defined( $arg = shift ) ) {
	my $flag = $arg;
	my $value = PMSUtil::trim($arg);
	if( $value =~ m/^-/ ) {
		# we have a flag with possible arg
		$flag =~ s/(-.).*$/$1/;		# e.g. '-t'
		$value =~ s/^-.//;			# e.g. '/a/b/c/d/Propertyfile.xtx'
		SWITCH: {
	        if( $flag =~ m/^-h$/ ) {
	        	print $UsageString . "\n";
	        	exit;
				last SWITCH;
	        }
			print "${appProgName}:: ERROR:  Invalid flag: '$arg'\n";
			$numErrors++;
		}
	} else {
		# we have the file name only
		if( $value ne "" ) {
			$TTSTATS_DIFF = $value;
		}
	}
} # end of while - done getting command line args

if( !defined $TTSTATS_DIFF ) {
	print "Missing full path name of diff file to process:\n";
	print $UsageString . "\n";
	exit;
}

# State machine states:
my $INITIALSTATE = 0;
my $LOOKINGFOR_NEWROW = 1;


# get to work!
open( DIFFFILE, "< $TTSTATS_DIFF" ) || die( "TTStatsDiffFilter.pl:  Can't open $TTSTATS_DIFF: $!" );
my $lineNum = 0;
my $state = $INITIALSTATE;
my $previousDiffChangeLine = "";
print "\nNOTE:  .< lines: PRODUCTION server, .> lines: DEV server\n";
while( my $line = <DIFFFILE> ) {
	my $value = "";
	$lineNum++;
	chomp( $line );
	#print "Line #$lineNum: '$line'\n";
	# remove comments:
	$line =~ s/\s*#.*$//;
	next if( $line eq "" );
	# 
	# look for a diff change line - something like "156,157c156,157"
	if( $line =~ m/^\d/ ) {
		$previousDiffChangeLine = $line;
		$state = $LOOKINGFOR_NEWROW;
		next;
	}
	if( $state == $LOOKINGFOR_NEWROW ) {
		# this line is a diff row - something like   < [F4]:    276              25-29:30-34
		$state = $INITIALSTATE;
		# get the type of the diff row
		my $type = $line;
		$type =~ s/^.*\[//;
		$type =~ s/\d.*$//;
		if( ord($type) > ord($previousDescriptionType) ) {
			# we haven't seen this diff type before
			$previousDescriptionType = $type;
			if( defined $row{$type} ) {
				print "\n" . $row{$type} . "\n";
			} else {
				print "UNDEFINED description for type '$type'.\n";
			}
		}
		print $previousDiffChangeLine . "\n";
	}
	# preceed '<' and '>' with a '.' to get around a display problem in email...
	if( ($line =~ m/^</) || ($line =~ m/^>/) ) {
		$line = "." . $line;
	}
	print $line . "\n";
}


# end of TTStatsDiffFilter.pl

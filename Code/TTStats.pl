#!/usr/bin/perl -w


# TTStats.pl - a program to generate statistics about the current Top Ten data in the database.
#	See Topten2.pl (or it's current name if it changed) for details on how those data are generated. 
#
# OUTPUT:  This program will produce its results as single html file (.html)
#
#

use strict;
use sigtrap;
use warnings;
use POSIX qw(strftime);
use File::Basename;
use File::Path qw(make_path remove_tree);
use Cwd 'abs_path';
use HTTP::Tiny;

my $appProgName;	# name of this program
my $appDirName;     # directory containing the application we're running
my $appRootDir;		# directory containing the appDirName directory

BEGIN {
	# Get the name of the program we're running:
	$appProgName = basename( $0 );
	die( "Can't determine the name of the program being run - did you use/require 'File::Basename' and its prerequisites?")
		if( (!defined $appProgName) || ($appProgName eq "") );
	print "Starting $appProgName...\n";
	
	# The program we're running is in a directory we call the "appDirName".  The file we
	# generate are located in directories relative to the
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
}

my $UsageString = <<bup
Usage:  
	$appProgName year
			[-tPROPERTYFILE]
where:
	year - the year to process, e.g. 2016.  
	-tPROPERTYFILE - the FULL PATH NAME of the property.txt file.  The default is 
		appDirName/Code/properties.txt, where
		'appDirName' is the directory holding this script, and
		'properties.txt' is the name of the properties files for this script.
bup
;

use lib "$appDirName/TTPerlModules";

require TT_MySqlSupport;
require TT_Util;
require TT_SheetSupport;
require TT_Struct;
require TT_Logging;
require TT_USMSDirectory;
require TT_Template;


use FindBin;
use File::Spec;
use lib File::Spec->catdir( $FindBin::Bin, '..', '..', '..', 'PMSPerlModules' );
require PMS_ImportPMSData;
require PMSMacros;
require PMSLogging;


sub GenerateHTMLStats( $ );


###




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


my %hashOfLongNames = (
	'PAC' => "Pacific Masters",
	'USMS' => "USMS",
	'SCY' => "Short Course Yards",
	'SCM' => "Short Course Meters",
	'LCM' => "Long Course Meters",
	'OW' => "Open Water",
	'SCY Records' => "Short Course Yards Records",
	'SCM Records' => "Short Course Meters Records",
	'LCM Records' => "Long Course Meters Records",
	);
						
# initialize property file details:
my $propertiesDir = $appDirName;		# Directory holding the properties.txt file.
my $propertiesFileName = "properties.txt";

# We also use the AppDirName in the properties file (it can't change)
PMSStruct::GetMacrosRef()->{"AppDirName"} = $appDirName;	# directory containing the application we're running

############################################################################################################
# get to work - initialize the program
############################################################################################################

# get the arguments:
my $yearBeingProcessed ="";

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
	        if( $flag =~ m/^-t$/ ) {
				$propertiesDir = dirname($value);
				$propertiesFileName = basename($value);
				last SWITCH;
	        }
			print "${appProgName}:: ERROR:  Invalid flag: '$arg'\n";
			$numErrors++;
		}
	} else {
		# we have the date only
		if( $value ne "" ) {
			$yearBeingProcessed = $value;
		}
	}
} # end of while - done getting command line args

if( $yearBeingProcessed eq "" ) {
	# no year to process - abort!
	die "$appProgName: no year to process - Abort!";
} else {
	# we store the year to process as a macro so we've got it handy
	PMSStruct::GetMacrosRef()->{"YearBeingProcessed"} = $yearBeingProcessed;
}

print "  ...and with the propertiesDir='$propertiesDir', and propertiesFilename='$propertiesFileName'\n";

# properties file:
# Read the properties.txt file and set the necessary properties by setting name/values in 
# the %macros hash which is accessed by the reference returned by PMSStruct::GetMacrosRef().  For example,
# if the macro "numSwimsToConsider" is set in the properties file, then it's value is retrieved by 
#	my $numSwimsWeWillConsider = PMSStruct::GetMacrosRef()->{"numSwimsToConsider"};
# after the following call to GetProperties();
# Note that the full path name of the properties file is set above to its default value when
# $propertiesDir and $propertiesFileName are initialized above.
PMSMacros::GetProperties( $propertiesDir, $propertiesFileName, $yearBeingProcessed );			

# at this point we INSIST that $yearBeingProcessed is a reasonable year:
if( ($yearBeingProcessed !~ m/^\d\d\d\d$/) ||
	( ($yearBeingProcessed < 2008) || ($yearBeingProcessed > 2030) ) ) {
	die( "${appProgName}::  The year being processed ('$yearBeingProcessed') is invalid - ABORT!");
}

PMSStruct::GetMacrosRef()->{"YearBeingProcessedPlusOne"} = $yearBeingProcessed+1;
print "  ...Year being analyzed: $yearBeingProcessed\n";

###
### file names
###
# Input data directory for the season we're processing 
my $seasonData = "$appRootDir/SeasonData/Season-$yearBeingProcessed";
# template directory:
my $templateDir = "$appDirName/Templates/Stats";
# swimmer data (not race results) directory
my $PMSSwimmerData = "$seasonData/PMSSwimmerData/";

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

# define the directories and files to which we write our HTML output 
my $generatedHTMLFileDir = $generatedDirName;
# the .html file we'll generate:
my $generatedHTMLStatSimpleName = "TTStats.html";
my $generatedHTMLStatsFullName = "$generatedHTMLFileDir/$generatedHTMLStatSimpleName";


# since we're generating an HTML file then we're going to first remove it (if it exists) so
# it's clear that whatever we generate is the most up-to-date:
unlink $generatedHTMLStatsFullName;


###
### Initialalize log file
###
my $logFileName = $generatedDirName . "TTStatsLog-$yearBeingProcessed.txt";
# open the log file so we can log errors and debugging info:
if( my $tmp = PMSLogging::InitLogging( $logFileName )) { die $tmp; }
PMSLogging::PrintLog( "", "", "Log file created on $generationTimeDate; Year being analyzed: $yearBeingProcessed" );

###
### initialize database
###
# Initialize the database parameters:
PMS_MySqlSupport::SetSqlParameters( 'default',
	PMSStruct::GetMacrosRef()->{"dbHost"},
	PMSStruct::GetMacrosRef()->{"dbName"},
	PMSStruct::GetMacrosRef()->{"dbUser"},
	PMSStruct::GetMacrosRef()->{"dbPass"} );
	

#####################################################
################ PROCESSING #########################
#####################################################

GenerateHTMLStats( $generatedHTMLStatsFullName );
	

###
### Done!
###

my $logLinesOnly = PMSLogging::GetLogOnlyLines();
my $completionTimeDate = strftime( "%a %b %d %G - %X", localtime() );

PMSLogging::PrintLog( "", "", "\nDone at $completionTimeDate.\n  See the $logLinesOnly lines (beginning with '+') logged ONLY to the log file.", 1 );
exit(0);



#####################################################
############### WORKER ROUTINES #####################
#####################################################

sub GenerateHTMLStats( $ ) {
	my $generatedHTMLStatsFullName = $_[0];
	
	my $templateStats = "$templateDir/TTStatsTemplate.txt";
	my $query;
	my ($sth, $rv);
	my $resultHash;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $macroValue = "";
	my $rowNum = 0;

###
### A:
###
	# Number of swimmers who swam in exactly one age group (with and without points) by gender:
	$query = "SELECT COUNT(SwimmerId) AS Count, AgeGroup1, Gender " .
		"FROM Swimmer WHERE AgeGroup2='' " .
		"GROUP BY AgeGroup1, Gender " .
		"ORDER BY AgeGroup1, Gender";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$macroValue = "";
	$rowNum = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $count = $resultHash->{'Count'};
		my $ageGroup1 = $resultHash->{'AgeGroup1'};
		my $gender = $resultHash->{'Gender'};
		$rowNum++;
		$macroValue .= "[A$rowNum]:";
		$macroValue .= AddSpaces( 5 - length( $rowNum ) );
		$macroValue .= $count;
		$macroValue .= AddSpaces( 15 - length($count) + 2 );
		$macroValue .= $ageGroup1;
		$macroValue .= AddSpaces( 11 );
		$macroValue .= $gender;
		$macroValue .= "\n";
	}
	PMSStruct::GetMacrosRef()->{"NumSwimmersOneAgeGroup"} = $macroValue;


###
### B:
###
	# Number of swimmers who swam in two age groups (with and without points) by gender:
	$query = "SELECT COUNT(SwimmerId) AS Count, AgeGroup2, Gender " .
		"FROM Swimmer WHERE AgeGroup2!='' " .
		"GROUP BY AgeGroup2, Gender " .
		"ORDER BY AgeGroup2, Gender";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$macroValue = "";
	$rowNum = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $count = $resultHash->{'Count'};
		my $ageGroup2 = $resultHash->{'AgeGroup2'};
		my $gender = $resultHash->{'Gender'};
		$rowNum++;
		$macroValue .= "[B$rowNum]:";
		$macroValue .= AddSpaces( 5 - length( $rowNum ) );
		$macroValue .= $count;
		$macroValue .= AddSpaces( 15 - length($count) + 2 );
		$macroValue .= $ageGroup2;
		$macroValue .= AddSpaces( 11 );
		$macroValue .= $gender;
		$macroValue .= "\n";
	}
	PMSStruct::GetMacrosRef()->{"NumSwimmersTwoAgeGroups"} = $macroValue;
	

###
### C:
###
	# Number of splashes per age group and gender:
	$query = "SELECT COUNT(AgeGroup) AS Count, AgeGroup, Gender " .
		"FROM Splash GROUP BY AgeGroup, Gender " .
		"ORDER BY AgeGroup, Gender";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$macroValue = "";
	$rowNum = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $count = $resultHash->{'Count'};
		my $ageGroup = $resultHash->{'AgeGroup'};
		my $gender = $resultHash->{'Gender'};
		$rowNum++;
		$macroValue .= "[C$rowNum]:";
		$macroValue .= AddSpaces( 5 - length( $rowNum ) );
		$macroValue .= $count;
		$macroValue .= AddSpaces( 15 - length($count) + 2 );
		$macroValue .= $ageGroup;
		$macroValue .= AddSpaces( 11 );
		$macroValue .= $gender;
		$macroValue .= "\n";
	}
	PMSStruct::GetMacrosRef()->{"NumSplashes"} = $macroValue;
	
###
### D:
###
	# Number of swimmers who earned points by gender and age group.  Some swimmers may be 
	# counted twice if they earned points in two age groups:
	$query = "SELECT COUNT(DISTINCT(Points.SwimmerId)) AS Count, AgeGroup, Gender FROM Points JOIN Swimmer " .
		"WHERE Points.SwimmerId = Swimmer.SwimmerId " .
		"AND AgeGroup NOT LIKE '%:%' " .
		"GROUP BY AgeGroup, Gender ORDER BY AgeGroup, Gender";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$macroValue = "";
	$rowNum = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $count = $resultHash->{'Count'};
		my $ageGroup = $resultHash->{'AgeGroup'};
		my $gender = $resultHash->{'Gender'};
		$rowNum++;
		$macroValue .= "[D$rowNum]:";
		$macroValue .= AddSpaces( 5 - length( $rowNum ) );
		$macroValue .= $count;
		$macroValue .= AddSpaces( 15 - length($count) + 2 );
		$macroValue .= $ageGroup;
		$macroValue .= AddSpaces( 11 );
		$macroValue .= $gender;
		$macroValue .= "\n";
	}
	PMSStruct::GetMacrosRef()->{"NumSwimmersEarningPoints"} = $macroValue;
	
###
### E:
###
	# number of total points earned (includes combined age groups, which means some points are counted 
	# twice for a swimmer who competes in two age groups)	
	$query = "SELECT SUM(TotalPoints) as TotalPoints from Points";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$macroValue = "";
	$rowNum = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $totalPoints = $resultHash->{'TotalPoints'};
		$rowNum++;
		$macroValue .= "[E$rowNum]:";
		$macroValue .= AddSpaces( 5 - length( $rowNum ) );
		$macroValue .= $totalPoints;
		$macroValue .= "\n";
	}
	PMSStruct::GetMacrosRef()->{"TotalPoints"} = $macroValue;
	
	
	
###
### F:
###
	# number of total points earned by each age group (includes combined age groups, which means some points are counted 
	# twice for a swimmer who competes in two age groups)	
	$query = "SELECT SUM(TotalPoints) AS TotalPoints, AgeGroup FROM Points GROUP by AgeGroup ORDER BY AgeGroup";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$macroValue = "";
	$rowNum = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $totalPoints = $resultHash->{'TotalPoints'};
		my $ageGroup = $resultHash->{'AgeGroup'};
		$rowNum++;
		$macroValue .= "[F$rowNum]:";
		$macroValue .= AddSpaces( 5 - length( $rowNum ) );
		$macroValue .= $totalPoints;
		$macroValue .= AddSpaces( 17 - length( $totalPoints ) );
		$macroValue .= $ageGroup;
		$macroValue .= "\n";
	}
	PMSStruct::GetMacrosRef()->{"TotalPointsPerAgeGroup"} = $macroValue;
	
	
	
###
### G:
###
	# number of Open Water splashes
	$query = "SELECT COUNT(*) AS Count FROM Splash WHERE Course = 'OW'";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$macroValue = "";
	$rowNum = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $count = $resultHash->{'Count'};
		$rowNum++;
		$macroValue .= "[G$rowNum]:";
		$macroValue .= AddSpaces( 5 - length( $rowNum ) );
		$macroValue .= $count;
		$macroValue .= "\n";
	}
	PMSStruct::GetMacrosRef()->{"NumberOWSplashes"} = $macroValue;
	
	
###
### H:
###
	# number of Open Water swimmers who swam at least one OW event (with our without points)
	$query = "SELECT COUNT(distinct(SwimmerId)) AS Count from Splash WHERE Course = 'OW'";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$macroValue = "";
	$rowNum = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $count = $resultHash->{'Count'};
		$rowNum++;
		$macroValue .= "[H$rowNum]:";
		$macroValue .= AddSpaces( 5 - length( $rowNum ) );
		$macroValue .= $count;
		$macroValue .= "\n";
	}
	PMSStruct::GetMacrosRef()->{"NumberOWSwimmers"} = $macroValue;

###
### GetResults statistics:
###
	$sth = TT_MySqlSupport::GetLastRequestStats( $dbh, $yearBeingProcessed );
	# did we find exactly one row?
	my $numRows = $sth->rows();
	if( $numRows >= 1 ) {
		# yes!  get the data
		my $resultHash = $sth->fetchrow_hashref;
		my $LinesRead = $resultHash->{LinesRead};
		my $MeetsSeen = $resultHash->{MeetsSeen};
		my $ResultsSeen = $resultHash->{ResultsSeen};
		my $FilesSeen = $resultHash->{FilesSeen};
		my $RaceLines = $resultHash->{RaceLines};
		my $DateTime = $resultHash->{Date};
		PMSStruct::GetMacrosRef()->{"numLinesRead"} = $LinesRead;
		PMSStruct::GetMacrosRef()->{"numDifferentMeetsSeen"} = $MeetsSeen;
		PMSStruct::GetMacrosRef()->{"numDifferentResultsSeen"} = $ResultsSeen;
		PMSStruct::GetMacrosRef()->{"numDifferentFiles"} = $FilesSeen;
		PMSStruct::GetMacrosRef()->{"raceLines"} = $RaceLines;
		PMSStruct::GetMacrosRef()->{"prevDateTime"} = $DateTime;
		PMSStruct::GetMacrosRef()->{"extraNote"} = "";
		if( $numRows > 1 ) {
			PMSStruct::GetMacrosRef()->{"extraNote"} = "(WARNING: Found $numRows rows for season $yearBeingProcessed " .
				"in the FetchStats table. Above data is ambiguious!)";
		}
	} else {
		# this isn't right!
		PMSStruct::GetMacrosRef()->{"numLinesRead"} = "?";
		PMSStruct::GetMacrosRef()->{"numDifferentMeetsSeen"} = "?";
		PMSStruct::GetMacrosRef()->{"numDifferentResultsSeen"} = "?";
		PMSStruct::GetMacrosRef()->{"numDifferentFiles"} = "?";
		PMSStruct::GetMacrosRef()->{"raceLines"} = "?";
		PMSStruct::GetMacrosRef()->{"prevDateTime"} = "?";
		PMSStruct::GetMacrosRef()->{"extraNote"} = "(WARNING: No rows for season $yearBeingProcessed " .
			"in the FetchStats table. Above data is missing!)";
	}

	# we've got all the data - create the stats file:
	
	open( my $masterGeneratedHTMLFileHandle, ">", $generatedHTMLStatsFullName ) or
		die( "Can't open $generatedHTMLStatsFullName: $!" );
	TT_Template::ProcessHTMLTemplate( $templateStats, $masterGeneratedHTMLFileHandle );
	close( $masterGeneratedHTMLFileHandle );
} # GenerateHTMLStats()


# 		$macroValue .= AddSpaces( 7 );
sub AddSpaces( $ ) {
	my $numSpaces = $_[0];
	my $result = "";
	return $result if( $numSpaces < 0 );
	while( $numSpaces-- ) {
		$result .= " ";
	}
	return $result;
} # end of AddSpaces()



# end of TTStats.pl

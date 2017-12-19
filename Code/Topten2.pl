#!/usr/bin/perl -w


# Topten2.pl - a program to process official USMS and PAC results in order to generate 
#	PAC swimmer standings in two forms:
#	- an Excel spreadsheet containing a list of "top 10" PAC swimmers for each gender 
#		and age group.  (We actually list ALL PAC swimmers who earned points for the year, 
#		not just the top 10.)  In addition we will list the top N male and female point earners
#		for the year.  See the setting of $TT_Struct::NumHighPoints below for 'N'.
#	- a web page containing a list of all swimmers who earned points during the processed year,
#		divided by gender and age group.  Swimmers are ordered by points, thus clearly indicating
#		the top 10 swimmers for each gender/age group.  The web page is designed to be available
#		on the PAC web site, thus giving PAC swimmers a way to track their progress throughout
#		the year. 
#
# See GenerationOfTopTenSwimmers.docx for more technical details.
#
# UNFORTUNATELY:  at the time of this writing (February, 2016) we cannot depend on USMS (and,
#	in some instances, PAC) to generate the official results in the same format every year.
#	They DEFINATELY don't use the same format for different types of results (e.g. USMS SCM
#	results vs. USMS records.)  This means that if you are using this program you'll probably
#	have to adjust the code slightly as necessary to accomidate changes in formats.
#
# ANOTHER UNFORTUNATELY:  the format usually used by the various reporting groups (e.g. USMS) is
#	not the best.  They usually combine the first, middle, and last names in one field, making it
#	difficult to determine a swimmer's EXACT name.  For example, in order to look up a swimmer in
#	the PAC database (RSIDN file) we need to know the swimmer's last name.  So, please tell me
#	the last names of the following two (real PAC) swimmers:
#			Ann Michelle Ongerth
#			Katie Bracco Comfort
#	Answer:  "Ongerth" and "Bracco Comfort"
#	For this reason we have special code using heuristics to deduce the correct name for each swimmer.
#	As any experenced programmer knows, "special code" and "heuristics" means it's not guaranteed 
#	to always work.  For example, it's possible we'll find a swimmer who we can't find in the PAC
#	database so we'll leave them out of the top 10 results, when in fact there is a slight mistake
#	in the spelling of the name that we could have caught if we were told their first, middle, and 
#	last names, even if slightly misspelled.
#	To complicate this problem it's common for some results to NOT contain the USMS reg number (or
#	swimmer id) of the swimmers in the results.  This makes it even more unlikely we'll match all the
#	swimmer's to their identity in the PAC member database.
#
# OUTPUT:  This program will produce its results as a .xlsx file and a set of html files.  
#	The generation of the web page (the set of html files) is controlled by a variable declared below 
#	named $WRITE_HTML_FILES.  
#	The generation of the Excel file is controlled by a variable declared below 
#	named $WRITE_EXCEL_FILES.
#
# MYSQL:  This program processes result files from USMS and PAC and stores all "interesting" data into
#	a number of tables of a MySql database.  It's assumed that the mysql server is running.  See the
#	modules TT_MySqlSupport and PMS_MySqlSupport and the call to PMS_MySqlSupport::SetSqlParameters below.
#

use strict;
use sigtrap;
use warnings;
use POSIX qw(strftime);
use File::Basename;
use File::Path qw(make_path remove_tree);
use Cwd 'abs_path';


# do we write the HTML output files?  0 means "No", anything else means "Yes"
my $WRITE_HTML_FILES = 1;

# do we write EXCEL output files? 0 means "No", anything else means "Yes"
my $WRITE_EXCEL_FILES = 1;

# Do we generate results for "split age groups"?  If a swimmer changes age groups in the middle of a season
# (which happens for every one of us once every 5 years, since a season spans more than 1 calendar year) we
# generate split age groups if such a swimmer accumulates points in their two age groups.  This means they have
# two entries in the AGSOTY, one entry for their younger age group, and another for their older age group.
my $GENERATE_SPLIT_AGE_GROUPS = 1;

# Do we generate results for "combined age groups"?  If a swimmer changes age groups in the middle of a 
# season (which happens for every one of us once every 5 years, since a season spans more than 1 calendar year) we
# generate only one AGSOTY entry - for their older age group.  We do this by combining all points they earned
# in their younger age group with the points they earned while in their older age group, eliminating duplicate
# events (if a swimmer is ranked 2nd in the 100 free SCY in their younger age group, and then swims the
# same event in their older age group and gets ranked 1st, they only get points for the higher ranked place,
# which, in this case, is 1st.)
# NOTE!!  ON AND AFTER THE 2018 SEASON THIS SHOULD ALWAYS BE '1'!
my $GENERATE_COMBINED_AGE_GROUPS = 1;

# This is the number of SOTY swimmers for each gender we'll show in the generated HTML and Excel files.
$TT_Struct::NumHighPoints=3;


# $RESULT_FILES_TO_READ is used to dictate what result files to read.  If 0 we will read no result
# files and only use what we find in the database.  If non-zero we'll clear the database and then
# read whatever result files $RESULT_FILES_TO_READ tells us to read, which is specified by a single
# bit in $RESULT_FILES_TO_READ.  The only reason to specify a value other than the default (0b11111) is to
# help with debugging.
#   - if ($RESULT_FILES_TO_READ & 0b1)		!= 0 then process PMS Top Ten result files
#   - if ($RESULT_FILES_TO_READ & 0b10)		!= 0 then process USMS Top Ten result files
#   - if ($RESULT_FILES_TO_READ & 0b100)	!= 0 then process PMS records
#   - if ($RESULT_FILES_TO_READ & 0b1000)	!= 0 then process USMS records
#   - if ($RESULT_FILES_TO_READ & 0b10000)	!= 0 then process PMS Open Water
#   - if ($RESULT_FILES_TO_READ & 0b100000)	!= 0 then process "fake splashes"
my $RESULT_FILES_TO_READ = 	0b111111;			# process all result files (default)
#my $RESULT_FILES_TO_READ = 0b011110;			# process all but Top Ten result files
#$RESULT_FILES_TO_READ = 	0b001111; 			# process all but OW
#$RESULT_FILES_TO_READ = 	0;					# process none of the result files (use DB only)
#$RESULT_FILES_TO_READ = 	0b010000;			# ow only
#$RESULT_FILES_TO_READ = 	0b000001;			# PMS Top Ten result files only
#$RESULT_FILES_TO_READ = 	0b000100;			# PMS records only
#$RESULT_FILES_TO_READ = 	0b001000;			# USMS records only
#$RESULT_FILES_TO_READ = 	0b000010;			# USMS Top Ten result files only
#$RESULT_FILES_TO_READ = 	0b001110;			# USMS Top Ten result files, USMS records, and PMS records only
#$RESULT_FILES_TO_READ = 	0b110000;			# fake splashes + OW only




# Do we compute the points for each swimmer using the data in the database, or do we just use
# what already exists?  If $RESULT_FILES_TO_READ is non-zero then we have to
# compute their points since we're reading new result files into a clean database.  However,
# if $RESULT_FILES_TO_READ is zero then we're not reading result files, and instead relying 
# on data already in our database, in which case we probably don't need to re-compute the
# swimmers' points since they have probably already been computed.
my $COMPUTE_POINTS = ($RESULT_FILES_TO_READ != 0);
#$COMPUTE_POINTS = 1;			# override above

# Do we compute the place for every swimmer?  If we don't compute their points (above) there
# isn't much reason to compute the place for every swimmer since their place shouldn't have changed.
my $COMPUTE_PLACE = $COMPUTE_POINTS;		# always compute places if we compute points.
#$COMPUTE_PLACE = 1;				# override above

# do we only show the top 10 for each gender / age group in Excel file?  or more?  or less?
# Set to 0 if we show all, otherwise set to the limit.  This applies to the "full" excel file,
# not the top 'N' excel file used to give out awards.
my $TOP_NUMBER_OF_PLACES_TO_SHOW_EXCEL = 0;
# we will generate another excel file known as the "top N excel file" which is used to show
# the top 'N' (usually 3) swimmers getting AGSOTY awards.  Setting to 0 or negative is stupid!
my $TOP_N_PLACES_TO_SHOW_EXCEL = 3;

# set this to non-zero if we want to track and display the number of PMS swims for every swimmer
# who earns points:
my $trackPMSSwims = 1;
# if a swimmer swam less than $minMeetsForConsideration PMS sancioned meets or open water events
# then we'll flag them in the spreadsheet
my $minMeetsForConsideration = 3;
# BUT...we only flag them if they've had a chance to swim in that many PMS swim meets.  We'll claim
# they've had a chance once this many PMS sanctioned meets (including OW) have been used in our results:
#my $minPMSMeetsToStartTracking = 12; ---  OOPS - not used!
# OR... we'll use a date in the season to start checking the number of PMS meets they have swum:
my $dateToStartTrackingPMSMeets = "";		# defined below


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
	# use for input and the files we generate are all located in directories relative to the
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
	$sourceData = "$appRootDir/SeasonData";	
}

my $UsageString = <<bup
Usage:  
	$appProgName year
where:
	year - the year to process, e.g. 2016.  
bup
;

use lib "$appDirName/TTPerlModules";

require TT_MySqlSupport;
require TT_Util;
require TT_SheetSupport;
require TT_Struct;
require TT_Logging;
require TT_USMSDirectory;

use FindBin;
use File::Spec;
use lib File::Spec->catdir( $FindBin::Bin, '..', '..', '..', 'PMSPerlModules' );
require PMS_ImportPMSData;
require PMSMacros;
require PMSLogging;

PMSStruct::GetMacrosRef()->{"RESULT_FILES_TO_READ"} = $RESULT_FILES_TO_READ;
PMSStruct::GetMacrosRef()->{"COMPUTE_POINTS"} = $COMPUTE_POINTS;

if( $WRITE_EXCEL_FILES ) {
	require Excel::Writer::XLSX;
}

sub ValidateAge($$);
sub GetSwimmerDetailsFromPMS_DB($$$$);
sub PMSProcessResults($);
sub USMSProcessResults($);
sub USMSProcessRecords($);
sub PMSProcessOpenWater($);
sub ProcessFakeSplashes($);
sub CalculatePointsForSwimmers($);
sub PrintResultsExcel($$$$$);
sub InitializeMissingResults();
sub PMSProcessRecords($);
sub ComputePointsForAllSwimmers();
sub ComputePlaceForAllSwimmers();
sub PrintResultsHTML($$$);
sub ComputeTopPoints($$);

###




# the date of executation, in the form 24Mar16
my $dateString = strftime( "%d%b%g", localtime() );
# ... and in the form March 24, 2016
my $generationDate = strftime( "%B %e, %G", localtime() );
PMSStruct::GetMacrosRef()->{"GenerationDate"} = $generationDate;
# ... and in the form Fri Sep 30 16:29:04 2016
my $generationTimeDate = strftime( "%a %b %d %G - %X", localtime() );
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
#
# If we don't find all the results we expect we want to make that obvious in the
# top 10 results we produce:
my %missingResults;		# $missingResults{org-course} is 1 IFF
						#   there are no top 10 result files for that combination,
						#   0 otherwise.
						#   org:  @PMSConstants::arrOfOrg
						#	course: @PMSConstants::arrOfCourse
						
# We initialize a structure that is used to track exactly what result files we process.
# We do this so that our results make it clear some results were not processed if
# that's the case.
if( $RESULT_FILES_TO_READ != 0 ) {
	InitializeMissingResults();
}

# get the arguments:
my $yearBeingProcessed ="";

my $arg;
my $numErrors = 0;
while( defined( $arg = shift ) ) {
	my $value = PMSUtil::trim($arg);
	if( $value ne "" ) {
		$yearBeingProcessed = $value;
	}
} # end of while - done getting command line args

if( $yearBeingProcessed eq "" ) {
	# no year to process - abort!
	die "$appProgName: no year to process - Abort!";
} else {
	# we store the year to process as a macro so we've got it handy
	PMSStruct::GetMacrosRef()->{"YearBeingProcessed"} = $yearBeingProcessed;
}


# various input files:
# properties file:
my $propertiesDir = $appDirName;		# Directory holding the properties.txt file.
my $propertiesFileName = "properties.txt";
# Read the properties.txt file and set the necessary properties by setting name/values in 
# the %macros hash which is accessed by the reference returned by PMSStruct::GetMacrosRef().  For example,
# if the macro "numSwimsToConsider" is set in the properties file, then it's value is retrieved by 
#	my $numSwimsWeWillConsider = PMSStruct::GetMacrosRef()->{"numSwimsToConsider"};
# after the following call to GetProperties();
# Note that the full path name of the properties file is set above to its default value when
# $propertiesDir and $propertiesFileName are initialized above.
PMSMacros::GetProperties( $propertiesDir, $propertiesFileName, $yearBeingProcessed );			

PMSStruct::GetMacrosRef()->{"YearBeingProcessedPlusOne"} = $yearBeingProcessed+1;
print "Starting $appProgName : Year being analyzed: $yearBeingProcessed\n";

# define the date beyond which we will flag swimmers who haven't swum enough PMS events:
$dateToStartTrackingPMSMeets = "$yearBeingProcessed-10-01";		# Oct 1 of the year being processed.
#$dateToStartTrackingPMSMeets = "$yearBeingProcessed-07-01";		# testing...
if( $mysqlDate ge $dateToStartTrackingPMSMeets ) {
	print " ...we are going to carefully count each high placed swimmer's PAC-sanctioned swims.\n"
}
###
### file names
###
# Input data directory for the season we're processing 
my $seasonData = "$appRootDir/SeasonData/Season-$yearBeingProcessed";
# directory holding result files that we process for points:
my $sourceDataDir = "$seasonData/SourceData-$yearBeingProcessed";
# template directory:
my $templateDir = "$appDirName/Templates";

# location of the RSIDN file that we'll use
my $swimmerDataFile = "$seasonData/PMSSwimmerData/" .
	PMSStruct::GetMacrosRef()->{"RSIDNFileName"};

# the input result files that we process:
my %PMSResultFiles = split /[;:]/, PMSStruct::GetMacrosRef()->{"PMSResultFiles"};
my %USMSResultFiles = split /[;:]/, PMSStruct::GetMacrosRef()->{"USMSResultFiles"};
my %PMSRecordsFiles = split /[;:]/, PMSStruct::GetMacrosRef()->{"PMSRecordsFiles"};
my %USMSRecordsFiles = split /[;:]/, PMSStruct::GetMacrosRef()->{"USMSRecordsFiles"};
my $PMSOpenWaterResultFile = PMSStruct::GetMacrosRef()->{"PMSOpenWaterResultFile"};
my $FakeSplashDataFile = PMSStruct::GetMacrosRef()->{"FakeSplashDataFile"};
######


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

# Excel file support
# use these for the "full" excel file
my $Top10ExcelResults;
my $workbook;
my $worksheet;
# use these for the top 'N' excel file - (usually 3 - see $TOP_N_PLACES_TO_SHOW_EXCEL)
my $TopNExcelResults;
my $workbookTopN;
my $worksheetTopN;
my $Top10ExcelResultsCAG;		# combine age groups
my $TopNExcelResultsCAG;		# combine age groups
if( $WRITE_EXCEL_FILES ) {
	$Top10ExcelResults =  $generatedDirName . "Top10ExcelResults.xlsx";
	$TopNExcelResults =  $generatedDirName . "Top_" . $TOP_N_PLACES_TO_SHOW_EXCEL .
		"_ExcelResults.xlsx" if($TOP_N_PLACES_TO_SHOW_EXCEL > 0);
	$Top10ExcelResultsCAG = $Top10ExcelResults;
	$Top10ExcelResultsCAG =~ s/.xlsx/cag.xlsx/;
	$TopNExcelResultsCAG = $TopNExcelResults;
	$TopNExcelResultsCAG =~ s/.xlsx/cag.xlsx/;
	# remove our excel files so we know they are up-to-date
	unlink $Top10ExcelResults, $TopNExcelResults, $Top10ExcelResultsCAG, $TopNExcelResultsCAG;
}

# define the directories and files to which we write our HTML output 
my $generatedHTMLFileDir = $generatedDirName;
my $generatedHTMLFileSubDir = "$generatedHTMLFileDir/HTMLVSupport";		# this will be modified before used

# full path name of the split age group master HTML file we're generating:
my $masterGeneratedSAGHTMLFileName;
# full path name of the combined age group master HTML file we're generating:
my $masterGeneratedCAGHTMLFileName;

# THIS DEPENDS ON WHAT SEASON WE'RE GENERATING!!
if( $yearBeingProcessed >= 2018 ) {
#if( $yearBeingProcessed >= 2017 ) {		# testing...
	# on/after 2018 we default to combining split age groups
	$masterGeneratedSAGHTMLFileName = "$generatedHTMLFileDir/index-sag.html";
	$masterGeneratedCAGHTMLFileName =$masterGeneratedSAGHTMLFileName;
	$masterGeneratedCAGHTMLFileName =~ s/-sag.html/.html/;		# index.html
} else {
	# on/before 2017 we default to split age groups
	$masterGeneratedSAGHTMLFileName = "$generatedHTMLFileDir/index.html";
	$masterGeneratedCAGHTMLFileName =$masterGeneratedSAGHTMLFileName;
	$masterGeneratedCAGHTMLFileName =~ s/\.html/_cag.html/;		# index-cag.html
}

# if we're generating HTML files then we're going to remove them (if they exist) so
# it's clear that whatever we generate is the most up-to-date:
if( $WRITE_HTML_FILES ) {
	unlink $masterGeneratedSAGHTMLFileName, $masterGeneratedCAGHTMLFileName;
}

my $virtualGeneratedHTMLFileHandle;		# defined when needed

###
### Initialalize log file
###
my $logFileName = $generatedDirName . "TopTenLog-$yearBeingProcessed.txt";
# open the log file so we can log errors and debugging info:
if( my $tmp = PMSLogging::InitLogging( $logFileName )) { die $tmp; }
PMSLogging::PrintLog( "", "", "Log file created on $generationTimeDate; Year being analyzed: $yearBeingProcessed" );
#print "logFileName=$logFileName\n";

###
### initialize database
###
# Initialize the database parameters:
PMS_MySqlSupport::SetSqlParameters( 'default',
	PMSStruct::GetMacrosRef()->{"dbHost"},
	PMSStruct::GetMacrosRef()->{"dbName"},
	PMSStruct::GetMacrosRef()->{"dbUser"},
	PMSStruct::GetMacrosRef()->{"dbPass"} );
if( $RESULT_FILES_TO_READ != 0 ) {
	TT_MySqlSupport::DropTTTables ();
	my $dbh = TT_MySqlSupport::InitializeTopTenDB();
	# Get the PMS-supplied data about every PMS member	
	PMS_ImportPMSData::ReadPMS_RSIDNData( $swimmerDataFile, $yearBeingProcessed );
	# Get the data we've accumulated about swim meets seen in results
#	my $racesDataFile = "$sourceDataDir/races.txt";
	# Read info about all the swim meets we know about:
	TT_MySqlSupport::ReadSwimMeetData( "$sourceDataDir/" . PMSStruct::GetMacrosRef()->{"RacesDataFile"} );
	# get our "fake" data that allows us to handle special cases:
	my $fakeMeetDataFile = PMSStruct::GetMacrosRef()->{"FakeMeetDataFile"};
	if( (defined $fakeMeetDataFile) && ($fakeMeetDataFile ne "" ) ) {
		# we have some "fake" meets to handle
		PMSLogging::PrintLog( "", "", "We have a FakeMeetDataFile to process ($fakeMeetDataFile)", 1 );
		TT_MySqlSupport::ReadSwimMeetData( "$sourceDataDir/" . PMSStruct::GetMacrosRef()->{"FakeMeetDataFile"} );
	} else {
		PMSLogging::PrintLog( "", "", "FakeMeetDataFile is either not defined or is empty, so no fake meets", 1 );
	}
} else {
	# since we didn't drop any of our DB tables we need these special cases to handle the situation
	# where we are going to re-compute every swimmer's points and/or place.
	if( $COMPUTE_POINTS ) {
		# we always need to start with a clean Points table:
		TT_MySqlSupport::DropTable( "Points" );
		TT_MySqlSupport::DropTable( "USMSDirectory" );
	}
	if( $COMPUTE_PLACE ) {
		# we always need to start with a clean FinalPlace table:
		TT_MySqlSupport::DropTable( "FinalPlaceSAG" );
		TT_MySqlSupport::DropTable( "FinalPlaceCAG" );
	}
	# since we didn't drop our tables (except maybe the Points and FinalPlace tables) 
	# the following call will only
	# initialze those tables (unless, of course, something else dropped our tables outside
	# this program, in which case the following call will re-create the other missing tables, which 
	# is a good thing.)
	my $dbh = TT_MySqlSupport::InitializeTopTenDB();
}


#####################################################
################ PROCESSING #########################
#####################################################

if( ($RESULT_FILES_TO_READ & 0b1) != 0 ) {
	###
	### Process PMS Top Ten results
	###
	PMSProcessResults( \%PMSResultFiles );
}

if( ($RESULT_FILES_TO_READ & 0b10) != 0 ) {
	###
	### Process USMS Top Ten results
	###
	USMSProcessResults( \%USMSResultFiles );
}

if( ($RESULT_FILES_TO_READ & 0b100) != 0 ) {
	###
	### Process PMS records
	###
	PMSProcessRecords( \%PMSRecordsFiles );
}
	
if( ($RESULT_FILES_TO_READ & 0b1000) != 0 ) {
	###
	### Process USMS records
	###
	USMSProcessRecords( \%USMSRecordsFiles );
}
	
if( ($RESULT_FILES_TO_READ & 0b10000) != 0 ) {
	###
	### Process PMS Open Water points
	###
	PMSProcessOpenWater( $PMSOpenWaterResultFile );
}

if( ($RESULT_FILES_TO_READ & 0b100000) != 0 ) {
	###
	### Process 'fake data'
	###
	if( (defined $FakeSplashDataFile) && ($FakeSplashDataFile ne "") ) {
		# we have some 'fake' splashes to process
		PMSLogging::PrintLog( "", "", "We have a FakeSplashDataFile to process ($FakeSplashDataFile)", 1 );
		ProcessFakeSplashes( $FakeSplashDataFile );
	} else {
		PMSLogging::PrintLog( "", "", "FakeSplashDataFile is either not defined or is empty, so no fake splashes", 1 );
	}
}


###
### Compute points for all swimmers
###
if( $COMPUTE_POINTS ) {
	ComputePointsForAllSwimmers();
}


###
### Compute the place for all swimmers
###
if( $COMPUTE_PLACE ) {
	ComputePlaceForAllSwimmers();
}

if($WRITE_HTML_FILES) {
	# full path name of the master HTML file we're generating:
	if( $GENERATE_SPLIT_AGE_GROUPS ) {
		PrintResultsHTML( "FinalPlaceSAG", $masterGeneratedSAGHTMLFileName, $generatedHTMLFileSubDir . "-SAG" );
	}

	if( $GENERATE_COMBINED_AGE_GROUPS ) {
		PrintResultsHTML( "FinalPlaceCAG", $masterGeneratedCAGHTMLFileName, $generatedHTMLFileSubDir . "-CAG" );
	}
} # end of if($WRITE_HTML_FILES...


if( $WRITE_EXCEL_FILES ) {
	if( $GENERATE_SPLIT_AGE_GROUPS ) {
		###
		###initialize split agegroup Excel output file
		###
	    # Create a new Excel workbook for the full excel file
	    $workbook = Excel::Writer::XLSX->new( $Top10ExcelResults );
	    # Add a worksheet
	    $worksheet = $workbook->add_worksheet();
	
	    # Create a new Excel workbook for the top 'N' excel file
	    $workbookTopN = Excel::Writer::XLSX->new( $TopNExcelResults );
	    # Add a worksheet
	    $worksheetTopN = $workbookTopN->add_worksheet();
	
	    # generate the files
		PrintResultsExcel( $workbook, $worksheet, $workbookTopN, $worksheetTopN, 1 );
	}
	
	if( $GENERATE_COMBINED_AGE_GROUPS ) {
		###
		###initialize combined age groups Excel output file
		###
	    # Create a new Excel workbook for the full excel file
	    $workbook = Excel::Writer::XLSX->new( $Top10ExcelResultsCAG );
	    # Add a worksheet
	    $worksheet = $workbook->add_worksheet();
	
	    # Create a new Excel workbook for the top 'N' excel file
	    $workbookTopN = Excel::Writer::XLSX->new( $TopNExcelResultsCAG );
	    # Add a worksheet
	    $worksheetTopN = $workbookTopN->add_worksheet();
	
	    # generate the files
		PrintResultsExcel( $workbook, $worksheet, $workbookTopN, $worksheetTopN, 0 );
	}

} # end of if( $WRITE_EXCEL_FILES...


# generate an HTML file giving details of all the swimmers who have split age groups during
# this season.
TT_MySqlSupport::DumpStatsFor2GroupSwimmers( "$generatedHTMLFileDir/cag.html", $generationDate );

###
### Done!
###

# Log details of all errors related to problems finding a swimmer in the PAC database.
# These details are important as they may help us identify swimmers who otherwise
# won't get points they deserve, and also possibly help us identify swimmers who are
# getting points they don't deserve (thus taking away points from swimmers who deserve them.)
TT_MySqlSupport::DumpErrorsWithSwimmerNames();
	
my $logLinesOnly = PMSLogging::GetLogOnlyLines();
my $completionTimeDate = strftime( "%a %b %d %G - %X", localtime() );

PMSLogging::PrintLog( "", "", "\nDone at $completionTimeDate.\n  See the $logLinesOnly lines (beginning with '+') logged ONLY to the log file.", 1 );
exit(0);


###################################################################################
#### PMS ##########################################################################
###################################################################################

# PMSProcessResults - Process the PMS Top 10 result files.  Example :
#    Women 	18-24	800	Freestyle	1	9:36.75	 Mackenzie M Leake	F23	STAN	386C-08D15		The Olympic Club 1500 Meter Swim Meet
#
#
# NOTE: The above is likely WRONG because the format of these files changes during the year.
#	Hopefully this will stop and we can standardize, but for now when the format changes we
#	just change the code to match it.  Ugh!
#
# PASSED:
#	$resultFilesRef - reference to an hash holding the full path file names of all 
#		PMS result files and, for each file, the org and course.
#
# NOTES:
#	The files processed by this function come from USMS:
#		1) Go to www.usms.org > Events & Results > Top 10
#		2) Fill in the fields:  Year, Course (short course yards, etc), LMSC (Pacific)
#			[[ Leave Zone and Club Abbreviation empty ]]
#		3) Click "Go!"
#	It is ASSUMED that every swimmer in these result files is (or was at the time of the event)
#	 a PMS swimmer, so if we don't find their regnum in the RSIDN file we don't let us stop
#	 accumulating their points.
#
sub PMSProcessResults($) {
	my $resultFilesRef = $_[0];
	my @placeToPoints = (0, 11, 9, 8, 7, 6, 5, 4, 3, 2, 1);
	my $simpleFileName;
	my $debug = 0;
	my $debugMeetTitle = "xxxxx";

	foreach $simpleFileName ( sort keys %{$resultFilesRef} ) {
		# open the top N file
		my $fileName = "$sourceDataDir/" . $simpleFileName;
		# compute the Org (PMS or USMS) and the course (SCY, etc) of the results to query
		my $course;
		my $org;
		my $org_course = $resultFilesRef->{$simpleFileName};
		$course = $org_course;
		$course =~ s/^.*-//;		# one of SCY, SCM, LCM
		$org = $org_course;
		$org =~ s/-.*$//;
		my $units = "Meter";		# assume event is meters
		$units = "Yard" if( $course eq "SCY" );
		$missingResults{$org_course} = 0;
		PMSLogging::PrintLog( "", "", "" );
		
		# does this file exist?
		if( ! ( -e -f -r $fileName ) ) {
			# can't find/open this file - just skip it with a warning:
			PMSLogging::DumpWarning( "", "", "!! Topten::PMSProcessResults(): UNABLE TO PROCESS $org_course (file " .
				"does not exist or is not readable) - INGORE THIS FILE:\n   '$fileName'", 1 );
			next;
		}
		# get to work
		PMSLogging::DumpNote( "", "", "** Topten::PMSProcessResults(): Begin processing $org_course:\n   '$fileName'", 1 );
		my %sheetHandle = TT_SheetSupport::OpenSheetFile($fileName);
		my $lineNum = 0;
		my $numResultLines = 0;
		my $numNotInSeason = 0;		# number of results that were out of season
		my $emptyDateSeen = 0;
		while( 1 ) {
			my @row = TT_SheetSupport::ReadSheetRow(\%sheetHandle);
			my $rowAsString = PMSUtil::ConvertArrayIntoString( \@row );
			my $length = scalar(@row);
			if( $length ) {
				# we've got a new row of of something (may be all spaces or a heading or something else)
				$lineNum++;
				
				if( ($lineNum % 1000) == 0 ) {
					print "...line $lineNum...\n";
				}
				
				if( $debug ) {
					print "$simpleFileName: line $lineNum: ";
					for( my $i=0; $i < scalar(@row); $i++ ) {
						print "col $i: '$row[$i]', ";
					}
					print "\n";
				} # end debug
				my ($currentGender, $currentAgeGroup, $currentEventId);
				$currentGender = $row[0];
				if( ($currentGender ne "Women") && ($currentGender ne "Men") ) {
					PMSLogging::DumpNote( "", "", "Topten::PMSProcessResults(): Line $lineNum of $simpleFileName: " .
						"Illegal line IGNORED:\n   $rowAsString" );
					next;		# not a result line
				}
				$numResultLines++;
				#
				# we have a row with the following columns (2016):
				# 0: Sex  (Women or Men)
				# 1: Age Group (e.g. '45-49')
				# 2: Distance (e.g. '100')
				# 3: Stroke (e.g. 'Freestyle')
				# 4: Rank (e.g. 1, 2, ...)
				# 5: Time (e.g. '1:38.41')
				# 6: Name (e.g. 'Elizabeth Pelton')
				# 7: Age (e.g. 'F23' or 'M28')
				# 8: Club (e.g. 'USF')
				# 9: Reg Number (e.g. '386W-0AETB')
				#10: Date (e.g. '07-23-2016')  [may be empty, e.g. 2017]
				#11: Meet (e.g. '2016 U.S. Olympic Trials')

				# get the age group
				$currentAgeGroup = $row[1];
				# get the event name
				# Add this event to our Event table:
				$currentEventId = TT_MySqlSupport::AddNewEventIfNecessary( $row[2], $units, 
					PMSUtil::CanonicalStroke( $row[3] ) );
				my ($place, $time, $firstName, $middleInitial, $lastName, $gender, $age, $team, $regNum, 
					$eventName, $meetTitle, $date);
				# these values come from the RSIDN file:
				my ($RSIDNFirstName, $RSIDNMiddleInitial, $RSIDNLastName, $RSIDNTeam);
				$place = $row[4];
				$time = $row[5];		# e.g. '1:38.41'
				$time = TT_Util::GenerateCanonicalDurationForDB( $time, $fileName, $lineNum );
				my $fullName = $row[6];
				$team = $row[8];
				$regNum = $row[9];
				$date = $row[10];
				$meetTitle = $row[11];
				$meetTitle = "(unknown meet name)" if( !defined( $meetTitle ) );

				# convert the date to the conanical form 'yyyy-mm-dd'
				my $convertedDateIsValid = 1;		# assume the passed $date is OK
				my $convertedDate = PMSUtil::ConvertDateToISO( $date );
				# handle empty or invalid dates
				if( $convertedDate eq $PMSConstants::INVALID_DOB ) {
					$convertedDateIsValid = 0;		# oops - something wrong with the passed $date
					if( $date eq "" ) {
						# minor problem - don't show this error more than once per file:
						if( ! $emptyDateSeen ) {
							# this is bad data if we have an empty date - we should get this fixed!
							PMSLogging::DumpWarning( "", "", "Topten::PMSProcessResults(): Line $lineNum of $simpleFileName:  " .
								"Missing date (this message will not be repeated for this file):" .
								"\n     $rowAsString" .
								"\n   WE WILL USE A FAKE BUT VALID DATE AND ATTEMPT TO PROCESS THIS ROW.", 0);
							$emptyDateSeen = 1;
						}
						# use a fake, but valid date:
						$convertedDate = "$yearBeingProcessed-01-01";	# legal date part of the season for every course
					} else {
						# we had a badly formatted date - ignore this entry
						PMSLogging::DumpError( "", "", "Topten::PMSProcessResults(): Line $lineNum of $simpleFileName: Invalid date " .
							"('$date') - (line ignored):\n   $rowAsString", 1 );
						next;
					}
				} else {
					# $convertedDate is a valid date in the correct format
				}
				
				# start analysis of data.  First, make sure this result falls within the season of
				# interest:
				my $dateAnalysis = PMSUtil::ValidateDateWithinSeason( $convertedDate, $course, $yearBeingProcessed );
				if( $dateAnalysis ne "" ) {
					# this result is outside the season we're processing!  Ignore it...
					PMSLogging::DumpError( "", "", "Topten::PMSProcessResults(): Line $lineNum of $simpleFileName: The result in " .
						"'$simpleFileName' is not part of the season we are processing ($yearBeingProcessed).\n" .
						"   [$dateAnalysis] - THIS ROW WILL BE IGNORED!". 1 );
					$numNotInSeason++;
					next;
				}
				
				if( $convertedDateIsValid ) {
					$date = $convertedDate;
				} else {
					$date = $PMSConstants::DEFAULT_MISSING_DATE;
				}

				
				# get name and team from our PMS db (if we can):
				($RSIDNFirstName, $RSIDNMiddleInitial, $RSIDNLastName,$RSIDNTeam) = 
					GetSwimmerDetailsFromPMS_DB(  $fileName, $lineNum, $regNum, "non-fatal" );
				# if we found them in the RSIDN file then we're using the data we found.  Otherwise,
				# we use what we got from the result file.
				# NOTE:  if this swimmer's first name is an empty string this means we couldn't find their reg number in our
				# own db (the RSIDN file).  
				if( $RSIDNFirstName ne "" ) {
					# we found this swimmer in the RSIDN file.  Get their name and team from the RSIDN
					$firstName = $RSIDNFirstName;
					$middleInitial = $RSIDNMiddleInitial;
					$lastName = $RSIDNLastName;
					$team = $RSIDNTeam;
				} else {
					# didn't find this regnum - produce error message if we haven't done so before
					# for this regNum.
					my $count = $TT_Struct::hashOfInvalidRegNums{"$regNum:$fullName"};
					if( !defined $count ) {
						$count = 0;
						PMSLogging::DumpWarning( "", "", "Topten::PMSProcessResults(): Line $lineNum of $simpleFileName: " .
							"\n   Couldn't find regNum " .
							"($regNum) in RSIDN_$yearBeingProcessed.  (FATAL - This Top 10 result will be " .
							"IGNORED since we can't confirm that this swimmer is a PAC swimmer).  Result line:" .
							"\n     $rowAsString" );
					}
					$TT_Struct::hashOfInvalidRegNums{"$regNum:$fullName"} = $count+1;
					# remember the org and course we're seeing this problem in.  
					# $TT_Struct::hashOfInvalidRegNums{"$regNum:$fullName:OrgCourse"} is of the form:
					#    org:course[,org:course:...]
					if( !defined $TT_Struct::hashOfInvalidRegNums{"$regNum:$fullName:OrgCourse"} ) {
						$TT_Struct::hashOfInvalidRegNums{"$regNum:$fullName:OrgCourse"} = "$currentAgeGroup;$org:$course";
					} elsif( $TT_Struct::hashOfInvalidRegNums{"$regNum:$fullName:OrgCourse"} !~ m/$org:$course/ ) {
						$TT_Struct::hashOfInvalidRegNums{"$regNum:$fullName:OrgCourse"} .= ",$org:course";
					}
	next;	# don't give points to this swimmer
					# use the first, middle, last name from the results.
					# break the $fullName into first, middle, and last names
					my @arrOfBrokenNames = TT_MySqlSupport::BreakFullNameIntoBrokenNames( $fileName, $lineNum, $fullName );
					# we're going to take the first name combination it found.
					my $hashRef = $arrOfBrokenNames[0];
					$firstName = $hashRef->{'first'};
					$middleInitial = $hashRef->{'middle'};
					$lastName = $hashRef->{'last'};
					}
				$gender = PMSUtil::GenerateCanonicalGender( $fileName, $lineNum, $currentGender );	# single letter
				$age = $row[7];
				$age =~ s/^.//;		# remove leading gender from age
				#print "PMSProcessResults(): Line #$lineNum: place: $place, time=$time, name=$fullName " .
				#	"['$firstName' '$middleInitial' '$lastName'] " .
				#	", genderage=$genderAge ['$gender',$age], team=$team, regNum=$regNum\n";
				# perform some sanity checks:
				if( ! ValidateAge( $age, $currentAgeGroup ) ) {
					PMSLogging::DumpError( "", "", "Topten::PMSProcessResults(): Line $lineNum of $simpleFileName: Age error: " .
						"('$fileName') Age is $age but event is for agegroup '$currentAgeGroup'", 1 );
				}
				
				#compute the points they get for this swim:
				my $points = 0;
				if( ($place >= 1) && ($place <= 10) ) {
					$points = $placeToPoints[$place];
				}
				
				# add this swimmer to our DB if necessary
				my $swimmerId = TT_MySqlSupport::AddNewSwimmerIfNecessary( $fileName, $lineNum, 
					$firstName, $middleInitial, $lastName,
					$gender, $regNum, $age, $currentAgeGroup, $team );
				
				# add this meet to our DB if necessary
				
				if( lc($debugMeetTitle) eq lc($meetTitle) ) {
					print "PMSProcessResults(): MeetTitle='$meetTitle', filename='$fileName', linenum='$lineNum'\n";
				}
				my $meetId = TT_MySqlSupport::AddNewMeetIfNecessary( $fileName, $lineNum, $meetTitle,
					"(none)", $org, $course, $date, $date, 1 );
				
				TT_MySqlSupport::AddNewSplash( $fileName, $lineNum, $currentAgeGroup, $currentGender, 
					$place, $points, $swimmerId, $currentEventId, $org, $course, $meetId, $time, $date );
	
			} else # end of if( $length...
			{
				# TT_SheetSupport::ReadSheetRow() returned a 0 length row - end of file
				TT_SheetSupport::CloseSheet( \%sheetHandle );
				my $msg = "* Topten::PMSProcessResults(): Done with '$simpleFileName' - $lineNum lines read, $numResultLines lines " .
					"stored.";
				if( $numNotInSeason ) {
					$msg .= "  ($numNotInSeason lines ignored: out of season.)";
				}
				PMSLogging::PrintLog( "", "", $msg, 1 );
				last;
			}
		} # end of while(1)...
	} # end of foreach my $fileName...	
} # end of PMSProcessResults()





###################################################################################
#### USMS #########################################################################
###################################################################################

# USMSProcessResults( \%USMSResultFiles );
#
# USMSProcessResults - Process the USMS result files.  
# Example "result line":
#	2,W18-24,50 Free,Sara E Delay,23,WCM,Pacific,23.69Y
#
# NOTE: The above is likely WRONG because the format of these files changes during the year.
#	Hopefully this will stop and we can standardize, but for now when the format changes we
#	just change the code to match it.  Ugh!
#
# PASSED:
#	$resultFilesRef - reference to an hash holding the full path file names of all 
#		USMS result files and, for each file, the org and course.
#
# NOTE:
#	The USMS results do not have swim meet details, so we can't record meet information
#	to go along with the results.
#

sub USMSProcessResults($) {
	my $resultFilesRef = $_[0];
	my @placeToPoints = (0, 22, 18, 16, 14, 12, 10, 8, 6, 4, 2);
	my $debugLastName = "xxxxxxxx";
	my $simpleFileName;
	my $debug = 0;

	foreach $simpleFileName ( sort keys %{$resultFilesRef} ) {
		# open the top N file
		my $fileName = "$sourceDataDir/" .  $simpleFileName;
		# compute org and course
		my $course;
		my $org;
		my $org_course = $resultFilesRef->{$simpleFileName};
		$course = $org_course;
		$course =~ s/^.*-//;
		$org = $org_course;
		$org =~ s/-.*$//;
		$missingResults{$org_course} = 0;
		PMSLogging::PrintLog( "", "", "" );

		# does this file exist?
		if( ! ( -e -f -r $fileName ) ) {
			# can't find/open this file - just skip it with a warning:
			PMSLogging::DumpWarning( "", "", "!! Topten::USMSProcessResults(): UNABLE TO PROCESS $org_course (file " .
				"does not exist or is not readable) - INGORE THIS FILE:\n   '$fileName'", 1 );
			next;
		}
		# get to work
		PMSLogging::DumpNote( "", "", "** Topten::USMSProcessResults(): Begin processing $org_course:\n   '$fileName'", 1 );
		my %sheetHandle = TT_SheetSupport::OpenSheetFile($fileName);
		my $eventId;
		my $lineNum = 0;
		my $numResultLines = 0;
		my $numPMSResultLines = 0;
		my $numNotInSeason = 0;		# number of results that were out of season - not used - data doesn't contain date!
		my $emptyDateSeen = 0;		# not used - data doesn't contain date!
		while( 1 ) {
			my @row = TT_SheetSupport::ReadSheetRow(\%sheetHandle);
			my $rowAsString = PMSUtil::ConvertArrayIntoString( \@row );
			my $length = scalar(@row);
			if( $length ) {
				# we've got a new row of of something (may be all spaces or a heading or something else)
				$lineNum++;
				if( $debug ) {
					print "$simpleFileName: line $lineNum: ";
					for( my $i=0; $i < scalar(@row); $i++ ) {
						print "col $i: '$row[$i]', ";
					}
					print "\n";
				} # end debug
				my $place = $row[0];
				if( $place !~ m/^\d+$/ ) {
					PMSLogging::DumpNote( "", "", "Topten::USMSProcessResults(): Line $lineNum of $simpleFileName: " .
						"Illegal line IGNORED:\n   $rowAsString" );
					next;		# not a result line
				}
				$numResultLines++;
				#
				# we have a row with the following columns (2016):
				# 0: Place  (e.g. 1, 2, ...)
				# 1: Gender/Age Group (e.g. 'W45-49' or 'M45-49')
				# 2: Event (e.g. '500 Free')
				# 3: Name (e.g. 'Allison A Arnold')
				# 4: Age (e.g. '23')
				# 5: Club (e.g. 'USF')
				# 6: LMSC ('Pacific')
				# 7: Time (e.g. '1:38.41Y')
				#
				# found a top N line - extract all the data
				my ($time, $firstName, $middleInitial, $lastName, $gender, $age, $team, $regNum, 
					$ageGroup, $eventName, $fullName, $LMSC, $units);
				
				my $genderAgeGroup = $row[1];
				$eventName = $row[2];
				$fullName = $row[3];
				$age = $row[4];
				$team = $row[5];
				$LMSC = $row[6];
				$time = $row[7];	# (e.g. '1:38.41Y')
				$units = $time;		# (e.g. '1:38.41Y')
				$time =~ s/\w$//;	# (e.g. '1:38.41')
				$time = TT_Util::GenerateCanonicalDurationForDB( $time, $fileName, $lineNum );
				$units =~ s/^[\d:.]+//;		# (e.g. 'Y') Y or M for yards or meters....?
				if( $units eq "Y" ) {
					$units = "Yard";
				} else {
					$units = "Meter";
				}
				
				# break the $genderAgeGroup into gender and ageGroup:
				$genderAgeGroup =~ m/^(.)(.+)$/;
				$gender = PMSUtil::GenerateCanonicalGender( $fileName, $lineNum, $1 );	# M or F
				$ageGroup = $2;
				# modify the eventName to include the course
				$eventName =~ s/ / $units /;
				# Add this event to our Event table:
				my( $distance, $stroke ) = PMSUtil::GetDistanceAndStroke( $row[2] );
				$eventId = TT_MySqlSupport::AddNewEventIfNecessary( $distance, $units, $stroke );
				
				if( $fullName =~ m/$debugLastName/ ) {
					print "found her\n";
				}
				
				# look up this swimmer by trying to parse their full name and then find them in our
				# RSIDN table:
				$regNum = "";		# just in case we can't deduce the swimmer's names
				my $teamInitials = "";
				($regNum, $teamInitials, $firstName, $middleInitial, $lastName) = 
										TT_MySqlSupport::GetDetailsFromFullName( $fileName, $lineNum, $fullName,
										$team, $ageGroup, $org, $course, "Error if not found" );
				if( $regNum eq "" ) {
					# we couldn't figure out who this swimmer is, or didn't find them in the RSIDN table.
					# go on to the next swimmer;
					next;
				}

				if(0) {
				print "USMSProcessResults():  Line #$lineNum: place: $place, time=$time, name=$fullName ['$firstName' '$middleInitial' '$lastName']" .
					", gender='$gender', age=$age, ageGroup = '$ageGroup', team=$team, regNum=$regNum, " .
					"eventName='$eventName'\n";
				}
				# perform some sanity checks:
				if( ! ValidateAge( $age, $ageGroup ) ) {
					PMSLogging::DumpWarning( "", "", "Topten::USMSProcessResults(): Line $lineNum of $simpleFileName: " .
						"Age is $age but event is for agegroup '$ageGroup' (line NOT ignored):\n   '$fileName'" .
						"\n    $rowAsString", 1 );
				}
				
				#compute the points they get for this swim:
				my $points = 0;
				if( ($place >= 1) && ($place <= 10) ) {
					$points = $placeToPoints[$place];
				}
				
				# add this swimmer to our DB if necessary
				# NOTE:  if this swimmer's regNum is an empty string this means we couldn't find their reg number in our
				# own db (the RSIDN file).  In this case we will NOT add this swimmer to our db.
				if( $regNum ne "" ) {
					$numPMSResultLines++;
					my $swimmerId = TT_MySqlSupport::AddNewSwimmerIfNecessary( $fileName, $lineNum, $firstName, $middleInitial, $lastName,
						$gender, $regNum, $age, $ageGroup, $team );
					TT_MySqlSupport::AddNewSplash( $fileName, $lineNum, $ageGroup, $gender, $place, $points, $swimmerId, 
						$eventId, $org, $course, $TT_MySqlSupport::DEFAULT_MISSING_MEET_ID, $time,
						$PMSConstants::DEFAULT_MISSING_DATE );
				}
			} else # end of if( $length...
			{
				# TT_SheetSupport::ReadSheetRow() returned a 0 length row - end of file
				TT_SheetSupport::CloseSheet( \%sheetHandle );
				my $msg = "* Topten::PMSProcessResults(): Done with '$simpleFileName' - $lineNum lines read, $numResultLines lines " .
					"stored.";
				if( $numNotInSeason ) {
					$msg .= "  ($numNotInSeason lines ignored: out of season.)";
				}
				PMSLogging::PrintLog( "", "", $msg, 1 );
				last;
			}
		} # end of while(1)...
	} # end of foreach my $fileName...	
	
} # end of USMSProcessResults()



###################################################################################
#### USMS Records #################################################################
###################################################################################

# USMSProcessRecords( \%USMSRecordsFiles );
# USMSProcessRecords - Process the USMS records files.  
# Example "result line": (yards)
#    M18-24,50 Y Free,Josh Schneider,04-28-12,19.36Y
#
# if a tie:
#    ,,Frederick Bousquet,02-13-10,18.67Y
#
# LCM:
#    M18-24,50 M Free,Josh Schneider,07-01-12,21.78L
# SCM:
#    W18-24,50 M Free,Jennifer K Beckberger,11-20-10,25.58S
#
# NOTE: The above is likely WRONG because the format of these files changes during the year.
#	Hopefully this will stop and we can standardize, but for now when the format changes we
#	just change the code to match it.  Ugh!
# NOTE on Feb 5, 2016:  format changed for 2015, too!  Ugh!!!!
#
# PASSED:
#	$resultFilesRef - reference to an hash holding the full path file names of all 
#		USMS record files and, for each file, the org and course.
#
# NOTES:  the USMS records files do not have any meet information in them, so we can't
#	record the meet in which each record was set.
#
my $emptyDateSeen = 0;		# used to limit an error message to once per result file max
my $numNotInSeason = 0;		# number of results that were out of season per result file
my $numNonPMSResultLinesInSeason = 0;	# number of USMS records this season that were NOT PMS owned (per file)
my $numPMSResultLines = 0;	# number of USMS records this season owned by PMS (per file)

sub USMSProcessRecords($) {
	my $resultFilesRef = $_[0];
	# get our year
	my $simpleFileName;
	my $debug = 0;
	
	foreach $simpleFileName ( sort keys %{$resultFilesRef} ) {
		# open the record file
		my $fileName = "$sourceDataDir/" .  $simpleFileName;
		# compute the org and course (org must be USMS)
		my $course;
		my $org;
		my $org_course = $resultFilesRef->{$simpleFileName};
		$org_course =~ s/@.*$//;			# remove the trailing '@M' or '@W' which is used to fetch the result files
		$course = $org_course;
		$course =~ s/^.*-//;
		$course .= " Records";
		$org = $org_course;
		$org =~ s/-.*$//;
		die( "USMSProcessRecords(): invalid 'org' ($org)" ) if( $org ne "USMS");
		$missingResults{"$org-$course"} = 0;
		PMSLogging::PrintLog( "", "", "" );

		# does this file exist?
		if( ! ( -e -f -r $fileName ) ) {
			# can't find/open this file - just skip it with a warning:
			PMSLogging::DumpNote( "", "", "!! Topten::USMSProcessRecords(): UNABLE TO PROCESS $org_course (file " .
				"does not exist or is not readable) - INGORE THIS FILE:\n   '$fileName'", 1 );
			next;
		}		
		# get to work
		$emptyDateSeen = 0;
		$numNotInSeason = 0;
		$numNonPMSResultLinesInSeason = 0;
		$numPMSResultLines = 0;
		PMSLogging::DumpNote( "", "", "** Topten::USMSProcessRecords(): Begin processing $org_course:\n   '$fileName'", 1 );
		my %sheetHandle = TT_SheetSupport::OpenSheetFile($fileName);
		my $lineNum = 0;
		my $numResultLines = 0;
		my $previousGenderAgeGroup = "";		# used for ties
		my $previousEventName = "";				# used for ties
		while( 1 ) {
			my @row = TT_SheetSupport::ReadSheetRow(\%sheetHandle);
			my $rowAsString = PMSUtil::ConvertArrayIntoString( \@row );
			my $length = scalar(@row);
			if( $length ) {
				# we've got a new row of of something (may be all spaces or a heading or something else)
				$lineNum++;
				if( $debug ) {
					PMSLogging::DumpNote( "", "", "Topten::USMSProcessRecords()[debug]: Line $lineNum of $simpleFileName: " .
						"    $rowAsString", 1 );
				}
				my $genderAgeGroup = $row[0];
				my $eventName = $row[1];
				
				# if the genderAgeGroup and the eventName are both empty we have a tie (or empty line).
				if( ((defined $genderAgeGroup) && ($genderAgeGroup ne "")) &&
					((defined $eventName) && ($eventName ne "")) ) {
					# if this is really a gender/age group then we have a real data row
					if( $genderAgeGroup !~ m/^\w\d+-\d+$/) {
						PMSLogging::DumpNote( "", "", "Topten::USMSProcessRecords(): Line $lineNum of $simpleFileName: " .
						"Illegal line IGNORED:\n   $rowAsString" );
						next;		# not a result line
					}
					# as of this writing there are NO blank lines!
					$numResultLines++;
					# prepare for the possibility that the following line is a tie with this one:
					$previousGenderAgeGroup = $genderAgeGroup;
					$previousEventName = $eventName;
					#
					# we have a row with the following columns (2016):
					# 0: Gender/Age Group (e.g. 'W45-49' or 'M45-49')
					# 1: Event (e.g. '500 Free')
					# 2: Name (e.g. 'Allison A Arnold')
					# 3: Date (e.g. '07-23-16')
					# 4: Time (e.g. '1:38.41L' where 'L' is either 'L', 'S', or 'Y')
					#
					USMSProcessRecordRow( \@row, $rowAsString, $simpleFileName, $lineNum, $org, $course );					
				} else {
					# found a tie or blank line or heading taking only one column
					# todo
					# WARNING!!!!!!!!!!!!!!!!!!!!!
					# We need to handle ties!
					# How to handle ties:
					#	This line has no gender/age group field and no event field.  If it has a name field then
					#		that means it's a tie with the previous line.  So, in this case:
					#	- if the date in this row is in the current season, AND
					#	- if the name is different from any previous name for this gender/age group and event, THEN:
					#		- Record this row using the previous row's gender/age group and event
					#  		- $numResultLines++;
					if( (defined $row[2]) && ($row[2] ne "") ) {
						# this row represents a tie
						$row[0] = $previousGenderAgeGroup;
						$row[1] = $previousEventName;
						$rowAsString = PMSUtil::ConvertArrayIntoString( \@row );
						USMSProcessRecordRow( \@row, $rowAsString, $simpleFileName, $lineNum, $org, $course );
					} else {
						# assume blank or header line for now...
						PMSLogging::DumpWarning( "", "", "Topten::USMSProcessRecords(): Line $lineNum of $simpleFileName: " .
							"ILLEGAL line (one or all of the first three columns are missing) ignored:\n   $rowAsString" );
					}
					
				}
			} else # end of if( $length...
			{
				# ReadSheetRow() returned a 0 length row - end of file
				TT_SheetSupport::CloseSheet( \%sheetHandle );
				my $msg = "* Topten::USMSProcessRecords(): Done with '$simpleFileName' - " .
					"$lineNum lines read, $numResultLines records analyzed\n" .
					"    $numNonPMSResultLinesInSeason non-PMS records for this season, " .
					"$numPMSResultLines PMS records stored.";
				if( $numNotInSeason ) {
					$msg .= "  ($numNotInSeason lines ignored: out of season.)"
				}
				PMSLogging::PrintLog( "", "", $msg, 1 );
				last;
			}
		} # end of while(1)...
	} # end of foreach my $fileName...	
	
} # end of USMSProcessRecords()



# USMSProcessRecordRow - Process a USMS record row
#
# PASSED:
#	$rowRef - reference to a row representing a USMS record
#	$rowAsString - the row as a string (for printing)
#	$simpleFileName - the name of the file from which the row was read
#	$lineNum - the line number of the row in the file
#	$org - 'USMS Record'
#	$course - the course of the swim ("SCY Records", etc)
#
# RETURNED:
#	n/a
#
# NOTES:
#	If the passed record belongs to a PAC swimmer and was set in the current season and it's not a
#	duplicate then it's entered into the Splash table.
#
sub USMSProcessRecordRow( $$$$$$ ) {
	my ($rowRef, $rowAsString, $simpleFileName, $lineNum, $org, $course) = @_;
	my $debug = 0;
	my $units = "Meter";
	$units = "Yard" if( $course =~ m/^SCY/ );
	
	# we have a row with the following columns (2016):
	# 0: Gender/Age Group (e.g. 'W45-49' or 'M45-49')
	# 1: Event (e.g. '500 Free')
	# 2: Name (e.g. 'Allison A Arnold')
	# 3: Date (e.g. '07-23-16')
	# 4: Time (e.g. '1:38.41L' where 'L' is either 'L', 'S', or 'Y')

	my $eventId;
	my ($time, $firstName, $middleInitial, $lastName, $gender, $regNum, 
		$ageGroup, $fullName, $date);
	$gender = $rowRef->[0];			# W50-54
	$ageGroup = $gender;		# W50-54
	my $eventName = $rowRef->[1];
	$fullName = $rowRef->[2];
	$date = $rowRef->[3];			# 05-18-14
	$time = $rowRef->[4];			# '1:38.41L'
	$time =~ s/.$//;			# '1:38.41'
	$time = TT_Util::GenerateCanonicalDurationForDB( $time, $simpleFileName, $lineNum );
	$gender =~ s/^(.).*$/$1/;	# W
	$gender = PMSUtil::GenerateCanonicalGender( $simpleFileName, $lineNum, $gender );	# M or F
	$ageGroup =~ s/^.//;		# 50-54

	# convert the date to the conanical form 'yyyy-mm-dd'
	my $convertedDate = PMSUtil::ConvertDateToISO( $date );
	# handle empty or invalid dates
	# TODO - this is bad data if we have an empty date - we should get this fixed!
	if( $convertedDate eq $PMSConstants::INVALID_DOB ) {
		if( $date eq "" ) {
			# don't show this error more than once per file:
			if( ! $emptyDateSeen ) {
				# this is bad data if we have an empty date - we should get this fixed!
				PMSLogging::DumpWarning( "", "", "Topten::USMSProcessRecordRow(): Line $lineNum of $simpleFileName: " .
					"Missing date (this message will not be repeated for this file):" .
					"\n   $rowAsString" .
					"\n   WE WILL USE A FAKE BUT VALID DATE AND ATTEMPT TO PROCESS THIS ROW.");
				$emptyDateSeen = 1;
			}
			# use a fake, but valid date:
			$convertedDate = "$yearBeingProcessed-01-01";	# legal date part of the season for every course
		} else {
			# we had a badly formatted date - ignore this entry
			PMSLogging::DumpError( "", "", "Topten::USMSProcessRecordRow(): Line $lineNum of $simpleFileName: " .
				"Invalid date ('$date') (line IGNORED):" .
				"\n   $rowAsString" );
			return;
		}
	}
	$date = $convertedDate;
	
	# valid date - is it a date in the season being processed? If not, skip this record
	my $dateAnalysis = PMSUtil::ValidateDateWithinSeason( $date, $course, $yearBeingProcessed );
	if( $dateAnalysis ne "" ) {
		# this record is outside the season we're processing so we'll ignore it...
		if( $debug )  {
			PMSLogging::DumpNote( "", "", "Topten::USMSProcessRecordRow(): Line $lineNum of $simpleFileName: " .
				"Out of season with date '$date' (line IGNORED):" .
				"\n   $rowAsString" );
		}
		$numNotInSeason++;
		return;
	}
	
	# break the $fullName into first, middle, and last names
	# (If the middle initial is not supplied then use "")
	# Name may be empty, so if that's the case we'll ignore it the result
	if( $fullName eq "" ) {
		PMSLogging::DumpError( "", "", "Topten::USMSProcessRecordRow(): Line $lineNum of $simpleFileName: " .
			"This record is missing the swimmer's name.  Line ignored" .
			"\n   $rowAsString", 1 );
		return;
	}

	# look up this swimmer by trying to parse their full name and then find them in our
	# RSIDN table:
	$regNum = "";		# just in case we can't deduce the swimmer's names
	my $teamInitials = "";
	($regNum, $teamInitials, $firstName, $middleInitial, $lastName) = 
							TT_MySqlSupport::GetDetailsFromFullName( $simpleFileName, $lineNum, $fullName,
							"", $ageGroup, $org, $course, "" );

	# did we eventually find a regnum?  If not we MUST assume they are NOT a PAC swimmer, since
	# the query used to get the data did not allow us to limit the data to PAC swimmers only.
	# If we don't find the swimmer by name in the RSIDN file we have no choice but to assume
	# they are NOT PAC.
	if( $regNum eq "" ) {
		PMSLogging::DumpWarning( "", "", "Topten::USMSProcessRecordRow(): Line $lineNum of $simpleFileName: " .
			"Disregard swimmer '$fullName' because we couldn't find them in our RSIDN_$yearBeingProcessed " .
			"file (ASSUME NOT a PAC swimmer.)", 0 );
		$numNonPMSResultLinesInSeason++;
		return;
	}
	# yes, we found a regnum - they are a PMS swimmer and this record is for the year being processed
	PMSLogging::DumpNote( "", "", "Topten::USMSProcessRecordRow(): Line $lineNum of $simpleFileName: " .
		"Swimmer '$fullName' is a PAC swimmer who set a national record this year." );

	# Add this event to our Event table:
	my( $distance, $stroke ) = PMSUtil::GetDistanceAndStroke( $eventName );
	$eventId = TT_MySqlSupport::AddNewEventIfNecessary( $distance, $units, $stroke );
	

	# one last test:  did this swimmer already get credit for this record?  This is mostly for the case when a
	# swimmer ties with him/her self.  I know, that is stupid.  Feel free to discuss with USMS - here is a real
	# example:
	#	W55-59,100 M Free,Laura B Val,08-16-08,1:02.02L
	#	,,Laura B Val,08-13-07,1:02.02L
	# In what world does this make sense???  Whatever - we'll catch it and NOT give Laura (or anyone else) points
	# for setting the same record two or more times with the same time.  (Jeez....)
	my $splashId = TT_MySqlSupport::LookUpRecord( $course, $org, $eventId, $gender, $ageGroup );
	if( $splashId ) {
		# this is a duplicate record...
		PMSLogging::DumpNote( "", "", "Topten::USMSProcessRecordRow(): '$fullName' has duplicate $org $course " .
			"for event id $eventId ($gender $ageGroup). - IGNORING duplicates!" );
		return;
	}

	$numPMSResultLines++;
	
	# found a pms swimmer setting a usms record:
	if(0) {
	print "USMSProcessRecordRow(): Line #$lineNum: time=$time, name=$fullName ['$firstName' '$middleInitial' '$lastName']" .
		", gender='$gender', ageGroup = '$ageGroup', regNum=$regNum, " .
		"eventName='$eventName'\n";
	}
	# add this swimmer to our DB if necessary
	my $swimmerId = TT_MySqlSupport::AddNewSwimmerIfNecessary( $simpleFileName, $lineNum, $firstName, $middleInitial, $lastName,
		$gender, $regNum, 0, $ageGroup, $teamInitials );
	TT_MySqlSupport::AddNewRecordSplash( $simpleFileName, $lineNum, $course, $org, $eventId, $gender,
		$ageGroup, 1, $swimmerId, 0, 50, $TT_MySqlSupport::DEFAULT_MISSING_MEET_ID, $date, $time );
						
} # end of USMSProcessRecordRow()
						
						



###################################################################################
#### PMS Records #################################################################
###################################################################################

# PMSProcessRecords( \%PMSRecordsFiles );
# PMSProcessRecords - Process the PMS records files.  
# Example "result line":
#	F,60-64,100,I.M.,Laura Val,5/17/15,01:07.1
#
# NOTE: The above is likely WRONG because the format of these files changes during the year.
#	Hopefully this will stop and we can standardize, but for now when the format changes we
#	just change the code to match it.  Ugh!
# NOTE on Feb 5, 2016:  format changed for 2015, too!  Ugh!!!!
#
# PASSED:
#	$resultFilesRef - reference to an hash holding the full path file names of all 
#		PMS record files and, for each file, the org and course.
#
#
# NOTES:  the PMS records files do not have any meet information in them, so we can't
#	record the meet in which each record was set.
sub PMSProcessRecords($) {
	my $resultFilesRef = $_[0];
	my $simpleFileName;
	my $debug = 0;
	
	foreach $simpleFileName ( sort keys %{$resultFilesRef} ) {
		# open the record file
		my $fileName = "$sourceDataDir/" .  $simpleFileName;
		# compute the org and course (org must be PAC)
		my $course;
		my $org;
		my $org_course = $resultFilesRef->{$simpleFileName};
		$course = $org_course;
		$course =~ s/^.*-//;
		$course .= " Records";
		$org = $org_course;
		$org =~ s/-.*$//;
		die( "PMSProcessRecords(): invalid 'org' ($org)" ) if( $org ne "PAC");
		my $units = "Meter";
		$units = "Yard" if( $course =~ m/^SCY/ );
		$missingResults{"$org-$course"} = 0;
		PMSLogging::PrintLog( "", "", "" );

		# does this file exist?
		if( ! ( -e -f -r $fileName ) ) {
			# can't find/open this file - just skip it with a warning:
			PMSLogging::DumpNote( "", "", "!! Topten::PMSProcessRecords(): UNABLE TO PROCESS $org_course (file " .
				"does not exist or is not readable) - INGORE THIS FILE:\n   '$fileName'", 1 );
			next;
		}		
		# get to work
		PMSLogging::DumpNote( "", "", "** Topten::PMSProcessRecords(): Begin processing $org_course:\n   '$fileName'", 1 );
		my %sheetHandle = TT_SheetSupport::OpenSheetFile($fileName);
		my $eventId;
		my $lineNum = 0;
		my $numResultLines = 0;
		my $numNotInSeason = 0;		# number of results that were out of season
		my $emptyDateSeen = 0;
		while( 1 ) {
			my @row = TT_SheetSupport::ReadSheetRow(\%sheetHandle);
			my $rowAsString = PMSUtil::ConvertArrayIntoString( \@row );
			my $length = scalar(@row);
			if( $length ) {
				# we've got a new row of of something (may be all spaces or a heading or something else)
				$lineNum++;
				if( $debug ) {
					print "$simpleFileName: line $lineNum: ";
					for( my $i=0; $i < scalar(@row); $i++ ) {
						print "col $i: '$row[$i]', ";
					}
					print "\n";
				}
				my $gender = PMSUtil::GenerateCanonicalGender( $fileName, $lineNum, $row[0] );	# M or F
				if( $row[0] !~ m/^\w$/ ) {
					PMSLogging::DumpNote( "", "", "Topten::PMSProcessRecords(): Line $lineNum of $simpleFileName: " .
						"Illegal line IGNORED:\n   $rowAsString" );
					next;		# not a result line
				}
				#
				# we have a row with the following columns (2016):
				# 0: Gender  ('F' or 'M')
				# 1: Age Group (e.g. '45-49')
				# 2: Distance (e.g. '100')
				# 3: Stroke (e.g. 'Freestyle')
				# 4: Swimmer (e.g. 'Elizabeth Pelton')
				# 5: Date (e.g. '1/30/16')
				# 6: Time (e.g. '1:38.41')
				#

				# found a record line - extract all the data
				my ($time, $firstName, $middleInitial, $lastName, $regNum, 
					$ageGroup, $eventName, $fullName, $date);
				
				$ageGroup = $row[1];
				$eventName = $row[2] . " " . $row[3];
				$fullName = $row[4];
				$date = $row[5];		# of the form '1/30/16'
				$time = TT_Util::GenerateCanonicalDurationForDB( $row[6], $simpleFileName, $lineNum );

				# assume the date is in ISO format, but confirm it anyway:
				if( !PMSUtil::ValidateISODate( $date ) ) {
					# nope!  give up on this line!
					PMSLogging::DumpError( "", "", "Topten::PMSProcessRecords(): Line $lineNum of $simpleFileName: " .
						"Invalid date ('$date') (Assumed to be ISO - line IGNORED):" .
						"\n     $rowAsString" );
					next;
				}

				# valid date - is it a date in the season being processed? If not, skip this record
				my $dateAnalysis = PMSUtil::ValidateDateWithinSeason( $date, $course, $yearBeingProcessed );
				if( $dateAnalysis ne "" ) {
					# this record is outside the season we're processing and it shouldn't be!  Ignore it...
					PMSLogging::DumpError( "", "", "Topten::PMSProcessRecords(): Line $lineNum of $simpleFileName: " .
						"This result is not part of the season we are processing " .
						"($yearBeingProcessed)." .
						"\n    [$dateAnalysis]   THIS ROW WILL BE IGNORED!", 1 );
					$numNotInSeason++;
					next;
				}
				
				# break the $fullName into first, middle, and last names
				# (If the middle initial is not supplied then use "")
				# Name may be empty, so if that's the case we'll ignore it the result
				if( $fullName eq "" ) {
					PMSLogging::DumpError( "", "", "Topten::PMSProcessRecords(): Line $lineNum of $simpleFileName: " .
						"This record is missing the swimmer's name.  Line IGNORED." .
						"\n    $rowAsString", 1 );
					next;
				}
				
				# look up this swimmer by trying to parse their full name and then find them in our
				# RSIDN table:
				$regNum = "";		# just in case we can't deduce the swimmer's names
				my $teamInitials = "";
				($regNum, $teamInitials, $firstName, $middleInitial, $lastName) = 
										TT_MySqlSupport::GetDetailsFromFullName( $fileName, $lineNum, $fullName,
										"", $ageGroup, $org, $course, "Error if not found" );
				if( $regNum eq "" ) {
					# we couldn't figure out who this swimmer is, or didn't find them in the RSIDN table.
					# go on to the next swimmer;
					next;
				}

				$numResultLines++;

				# Add this event to our Event table:
				$eventId = TT_MySqlSupport::AddNewEventIfNecessary( $row[2], $units, 
					PMSUtil::CanonicalStroke( $row[3] ) );
				
				if(0) {
				print "Topten::PMSProcessRecords(): Line #$lineNum: time=$time($row[6]), name=$fullName ['$firstName' '$middleInitial' '$lastName']" .
					", gender='$gender', ageGroup = '$ageGroup', regNum=$regNum, " .
					"eventName='$eventName'\n";
				}
				# add this swimmer to our DB if necessary
				my $swimmerId = TT_MySqlSupport::AddNewSwimmerIfNecessary( $fileName, $lineNum, $firstName, $middleInitial, $lastName,
					$gender, $regNum, 0, $ageGroup, $teamInitials );
				TT_MySqlSupport::AddNewRecordSplash( $fileName, $lineNum, $course, $org, $eventId, $gender,
					$ageGroup, 1, $swimmerId, 0, 25, $TT_MySqlSupport::DEFAULT_MISSING_MEET_ID, $date, $time );
		
			} else # end of if( $length...
			{
				# ReadSheetRow() returned a 0 length row - end of file
				TT_SheetSupport::CloseSheet( \%sheetHandle );
				my $msg = "* Topten::PMSProcessRecords(): Done with '$simpleFileName' - $lineNum lines read, $numResultLines lines " .
					"stored.";
				if( $numNotInSeason ) {
					$msg .= "  ($numNotInSeason lines ignored: out of season.)"
				}
				PMSLogging::PrintLog( "", "", $msg, 1 );
				last;
			}
		} # end of while(1)...
	} # end of foreach my $fileName...	
	
} # end of PMSProcessRecords()



###################################################################################
#### PMS OPEN WATER ###############################################################
###################################################################################

# PMSProcessOpenWater( $PMSOpenWaterResultFile );
# PMSProcessOpenWater - 
#
# Example "result line":
# Gender,Age Group,Place,Points,Last Name,First Name,Middle,Regnum,Event Name,Event Date,Duration
# W	18-24	1	22	Arnold	Allison	A	386G-09827	1.000 Mile Open Water	Spring Lake 1 Mile	5/21/16#
# PASSED:
#	$PMSOpenWaterResultFile - the simple file name of the file holding open water points 
#
# NOTES:  Every place is considered a unique swim (thus unique swim meet) for the standings, 
#	so the PMSOpenWaterResultFile will list "all" of the open water events swum by PMS swimmers
#	(limited to the number of events which count for open water points, which can change every year.)
#	This means two things:
#		- a row in this file may contain '0' for the points earned by an open water swim.  This
#			represents a swim which finished 11th or slower in their gender/age group.
#		- a swimmer will have no more than "numSwimsToConsider" rows, where "numSwimsToConsider"
#			is the number of swims we consider for open water points.  If a swimmer earned points
#			in more than "numSwimsToConsider" events the PMSOpenWaterResultsFile will only 
#			report the top "numSwimsToConsider" point-earning swims.
#
sub PMSProcessOpenWater($) {
	my $simpleFileName = $_[0];
	my $debugRegNum = "xxxxx";
	my $debug = 0;

	my $course = "OW";
	my $org = "PAC";
	$missingResults{"$org-$course"} = 0;
	
	my $fileName = "$sourceDataDir/" .  $simpleFileName;
	# does this file exist?
	if( ! ( -e -f -r $fileName ) ) {
		# can't find/open this file - just skip it with a warning:
		PMSLogging::DumpNote( "", "", "!! Topten::PMSProcessOpenWater(): UNABLE TO PROCESS $org-$course (file " .
			"does not exist or is not readable) - INGORE THIS FILE:\n   '$fileName'", 1 );
	} else {
		# get to work
		PMSLogging::DumpNote( "", "", "** Topten::PMSProcessOpenWater(): Begin processing $org $course:\n   '$fileName'", 1 );
		my %sheetHandle = TT_SheetSupport::OpenSheetFile($fileName);
		my $lineNum = 0;
		my $numResultLines = 0;
		while( 1 ) {
			my @row = TT_SheetSupport::ReadSheetRow(\%sheetHandle);
			my $rowAsString = PMSUtil::ConvertArrayIntoString( \@row );
			my $length = scalar(@row);
			if( $length > 0 ) {
				$lineNum++;
				# we've got a new row of of something (may be all spaces or a heading or something else) BUT
				# we know it's not an end-of-file
				if( (defined($row[0])) && (defined($row[1])) && (defined($row[2])) ) {
					# we've got a new row of of something (may be heading or data - anything else won't define
					# row[2])
					if( $debug ) {
						PMSLogging::PrintLog( "", "", "  Topten::PMSProcessOpenWater(): Line $lineNum: " .
							"$simpleFileName: ");
						for( my $i=0; $i < scalar(@row); $i++ ) {
							PMSLogging::PrintLogNoNL( "", "", "    col $i: '$row[$i]', ");
						}
						PMSLogging::PrintLog( "", "", "" );
					}
					# look for a header line:
					if( $row[0] eq "Gender" ) {
						# header line - skip it
						if( $debug ) {
							PMSLogging::PrintLog( "", "", "    (Skipping line $lineNum)");
						}
						next;
					}
					my $gender = PMSUtil::GenerateCanonicalGender( $fileName, $lineNum, $row[0] );	# M or F
					if( $row[0] !~ m/^\w$/ ) {
						PMSLogging::PrintLog( "", "", "Topten::PMSProcessOpenWater(): Line $lineNum of $simpleFileName: " .
							"Illegal line (bad gender) found in '$fileName':" .
							"\n    $rowAsString", 1 );
						next;		# not a result line
					}
					
					# We've decided that this is a row containing a result that we need to use
					$numResultLines++;
					
					#
					# we have a row with the following columns (2016):
					# 0: Gender	
					# 1: Age Group	
					# 2: Place	
					# 3: Points	
					# 4: Last Name	
					# 5: First Name	
					# 6: Middle	
					# 7: Regnum	
					# 8: Meet Name e.g. Spring Lake
					# 9: Event Name	e.g. Spring Lake 1 Mile
					# 10: Event Date
					# 11: Duration
			
					my ($x, $ageGroup, $place, $points, $lastName, $firstName, $middleInitial, $regNum, 
						$meetName, $eventName, $eventDate, $duration) = @row;
		
					# this date is assumed to be in the form 'yyyy-mm-dd'
					my $convertedDate = $eventDate;
					# handle empty or invalid dates (we don't expect any of these since we have control over
					# this result file)
					if( $convertedDate eq $PMSConstants::INVALID_DOB ) {
						PMSLogging::DumpError( "", "", "Topten::PMSProcessOpenWater(): Line $lineNum of $simpleFileName: " .
							"Invalid date ('$eventDate') FATAL - Ignoring this row:" .
							"\n    $rowAsString", 1 );
						next;
					} else {
						$eventDate = $convertedDate;
					}
					
					# convert the duration into an int (hundredths of a second)
					$duration = TT_Util::GenerateCanonicalDurationForDB( $duration, $fileName, $lineNum );
		
					if( $debugRegNum eq $regNum ) {
						print "PMSProcessOpenWater(): Line #$lineNum: gender=$gender, ageGroup=$ageGroup, " .
							"regNum='$regNum', firstName=$firstName, middleInitial='$middleInitial', " .
							"lastName='$lastName', meetDate='$eventDate'";
					}
					
					# Add this event to our Event table:
					# $eventName is in the form "Lake Berryessa 1.3 Mile" or "Keller Cove 1/2 Mile"
					$eventName =~ m,^(\D+)([\d./]+)\s*(\D+)$,;
					my $distance = $2;		# e.g. "1.3"
					my $eventCourse = $3;		# e.g. "Mile"
					$eventCourse = PMSUtil::CanonicalOWCourse( $eventCourse );
					my $stroke = $1;		# e.g. "Lake Berryessa "
					$stroke =~ s/\s*$//;		# e.g. "Lake Berryessa"
					my $eventId = TT_MySqlSupport::AddNewEventIfNecessary( $distance, $eventCourse,
						$stroke, $eventName );
					# add this swimmer to our DB if necessary
					# (NOTE: we assume the passed name and regnum are valid)
					my $swimmerId = TT_MySqlSupport::AddNewSwimmerIfNecessary( $fileName, $lineNum, 
						$firstName, $middleInitial, $lastName,
						$gender, $regNum, 0, $ageGroup, "" );
					# add this meet to our DB if necessary
	
					# filename, linenum, meetitle, meetlink, meetorg, meetcourse, meetbegindate, meetenddate, 
					# ... meetispms (1 or 0)
					# NOTE:  we are supplying the event name for the meet name since each OW event is counted as
					# a separate "meet" - swimming 3 OW events is the same as swimming in 3 PAC events.
					my $meetId = TT_MySqlSupport::AddNewMeetIfNecessary( $fileName, $lineNum, $eventName, 
						"http://pacificmasters.org/content/open-water-swims", $org, $course, 
						$eventDate, $eventDate, 1 );
						
					# compute the number of Top10 points they get from all of their OW places:
					# the points they get for SOTY is the same as the OW points they were awarded.
#					TT_MySqlSupport::AddNewOWSplash( $fileName, $lineNum, $ageGroup, $gender, $place,
#						$points, $swimmerId, $eventId, $org, $course, $meetId, $eventDate, $duration );


					TT_MySqlSupport::AddNewSplash( $fileName, $lineNum, $ageGroup, $gender, $place, 
						$points, $swimmerId, $eventId, $org, $course, $meetId, $duration, $eventDate );


				} # end of if( (defined($row[0])...
			} else # end of if( $length...
				{
					# ReadSheetRow() returned a 0 length row - end of file
					TT_SheetSupport::CloseSheet( \%sheetHandle );
					PMSLogging::DumpNote( "", "", "*  Topten::PMSProcessOpenWater(): Done with '$simpleFileName' " .
						"- $lineNum lines read, $numResultLines lines stored." );
					last;
				}
		} # end of while
	}
	
} # end of PMSProcessOpenWater()


###################################################################################
#### FAKE SPLASHES ###############################################################
###################################################################################



# ProcessFakeSplashes( $FakeSplashDataFile );
# ProcessFakeSplashes - 
#
# Example "result line":
# we have rows with the following columns (2016):
# REQUIRED:
#	1: Last Name
#	2: First Name
#	3: Middle Initial
# 	4: Reg Number (e.g. '386W-0AETB')
#	5: Meet (e.g. '2016 U.S. Olympic Trials')
#	6: MeetIsPMS (1 if PMS sanctioned, 0 otherwise)
# 	7: Distance (e.g. '100')
#	8: Units (e.g. "Yard", "Meter", "Mile", or "K")
# 	9: Stroke (e.g. 'Freestyle')
# 	10: Rank (e.g. 1, 2, ...)
#	11: Points (depends on what we're trying to fake, e.g. top 10 pms or top 10 USMS)
# 	12: Duration (e.g. '1:38.41')
#
# OPTIONAL:
#	13: MeetLink (link to meet description - use "(none)" if none) [default:  "(none)"]
# 	14: Gender  (Women or Men)  [default: Gender from RSIDN file]
# 	15: Age Group (e.g. '45-49')  [default: younger age group seen for this swimmer]
# 	16: Age (e.g. 'F23' or 'M28')  [not used]
# 	17: Club (e.g. 'USF')  [not used]
#	18: Date (e.g. '07-23-2016')  [default:  $PMSConstants::DEFAULT_MISSING_DATE]
#
# PASSED:
#	$FakeSplashDataFile - the simple file name of the file holding the fake splashes 
#
# NOTES:  This "hack" allows us to supply a file containing swimmers who we will "pretend" swam
#	a specific event at a specific meet.  This file is usually accompanied by a "FakeMeetDataFile"
#	that, if supplied, has already been processed.  Usually we associate the fake splash with a
#	"fake meet" but that's not necessary as we could use this to give a swimmer a splash in a real
#	swim meet (maybe they really swam and placed but for some reason it didn't show up in the
#	results).
#	For simplicity we will NOT add a new swimmer just to give them a fake splash.  If a swimmer
#	does not exist (has no real splashes) by the time this routine is called, and that swimmer 
#	is supposed to be given a fake splash they will be ignored.  If a swimmer doesn't have any
#	real swims will a fake swim be useful to them?   
#
sub ProcessFakeSplashes($) {
	my $simpleFileName = $_[0];
	my $debugRegNum = "xxxxx";
	my $debug = 0;

	# the org and course should probably come from the fake splash data file, but I'm not sure
	# at this point if it matters so I'm going to fake it here.
	my $course = "SCY";
	my $org = "PAC";
	
	my $fileName = "$sourceDataDir/" .  $simpleFileName;
	# does this file exist?
		
		# get to work
		PMSLogging::DumpNote( "", "", "** Topten::ProcessFakeSplashes(): Begin processing:\n   '$fileName'", 1 );
		my %sheetHandle = TT_SheetSupport::OpenSheetFile($fileName);
		my $lineNum = 0;
		my $numResultLines = 0;
		while( 1 ) {
			my @row = TT_SheetSupport::ReadSheetRow(\%sheetHandle);
			my $rowAsString = PMSUtil::ConvertArrayIntoString( \@row );
			my $length = scalar(@row);
			if( $length > 0 ) {
				$lineNum++;
				# we've got a new row of of something (may be all spaces or a heading or something else) BUT
				# we know it's not an end-of-file
				if( $row[0] =~ m/\s*#/ ) {
					# found a comment...
					next;
				}
				if( (defined($row[0])) && (defined($row[1])) && (defined($row[2])) ) {
					# we've got a new row of of something (may be heading or data - anything else won't define
					# row[2])
					if( $debug ) {
						PMSLogging::PrintLog( $rowAsString, $lineNum, 
							"  Topten::ProcessFakeSplashes($simpleFileName): ");
						for( my $i=0; $i < scalar(@row); $i++ ) {
							PMSLogging::PrintLogNoNL( "", "", "    col $i: '$row[$i]', ");
						}
						PMSLogging::PrintLog( "", "", "" );
					}
					# some of the following fields are optional so we be setting the corresponding
					# variables to undefined.
					my ($lastName, $firstName, $middleInitial, $regNum, $meetTitle, $meetIsPMS,
						$distance, $units, $stroke, $rank, $points, $duration, 
						# the following are optional but we'll get them if supplied:
						$meetLink, $gender, $ageGroup, $age, $club, $date
					   ) = @row;
						
					# convert the duration into an int (hundredths of a second)
					$duration = TT_Util::GenerateCanonicalDurationForDB( $duration, $fileName, $lineNum );
		
					if( $debugRegNum eq $regNum ) {
						print "ProcessFakeSplashes(): Line #$lineNum: " .
							"regNum='$regNum', firstName=$firstName, middleInitial='$middleInitial', " .
							"lastName='$lastName'";
					}
					
					# WE DO NOT add this swimmer to our DB if necessary - if they are not in our DB
					# we are ignoring this row!
					# (NOTE: we assume the passed name and regnum are valid)
					# get ready to use our database:
					my $dbh = PMS_MySqlSupport::GetMySqlHandle();
					# Get the USMS Swimmer id, e.g. regnum 384x-abcde gives us 'abcde'
					my $regNumRt = PMSUtil::GetUSMSSwimmerIdFromRegNum( $regNum );
					my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
						"SELECT SwimmerId,FirstName,MiddleInitial,LastName,Gender,AgeGroup1,AgeGroup2,RegisteredTeamInitials " .
						"FROM Swimmer WHERE RegNum LIKE \"38%-$regNumRt\"", "" );
					my $resultHash = $sth->fetchrow_hashref;
					if( ! defined($resultHash) ) {
						# this swimmer isn't known to us so don't give them the fake splash
						PMSLogging::PrintLog( $rowAsString, $lineNum, 
							"  Topten::ProcessFakeSplashes($simpleFileName): " .
							"$firstName $middleInitial $lastName ($regNum) has no real splashes so they " .
							"are not being given any fake splashes.");
						next;
					}

					# We've decided that this is a row containing a result that we need to use
					$numResultLines++;
					
					my $swimmerId = $resultHash->{'SwimmerId'};
					$ageGroup = $resultHash->{'AgeGroup1'} if( (!defined $ageGroup) || ("" eq $ageGroup) );
					$gender = $resultHash->{'Gender'} if( (!defined $gender) || ("" eq $gender) );
					$date = $PMSConstants::DEFAULT_MISSING_DATE if( (!defined $date) || ("" eq $date) );
					$meetLink = "(none)" if( (!defined $meetLink) || ("" eq $meetLink) );

					### NOTE: WE ASSUME THIS MEET EXISTS IN OUR DB (if nothing else it was created as 
					###		a "fake" meet.)

					# Add this event to our Event table:
					my $eventId = TT_MySqlSupport::AddNewEventIfNecessary( $distance, $units, 
						PMSUtil::CanonicalStroke( $stroke ) );

					my $meetId = TT_MySqlSupport::AddNewMeetIfNecessary( $fileName, $lineNum, $meetTitle,
						$meetLink, $org, $course, $date, $date, $meetIsPMS );

					TT_MySqlSupport::AddNewSplash( $fileName, $lineNum, $ageGroup, $gender, $rank, 
						$points, $swimmerId, $eventId, $org, $course, $meetId, $duration, $date );
				} # end of if( (defined($row[0])...
				else {
					# this row has less than 3 fields - ignore the line
					if( $debug ) {
						PMSLogging::PrintLog( $rowAsString, $lineNum, 
							"  Topten::ProcessFakeSplashes($simpleFileName): " .
							"this row is EMPTY (contains less than 3 columns)");
					}
				}
			} # end of if( $length...
			else {
					# ReadSheetRow() returned a 0 length row - end of file
					TT_SheetSupport::CloseSheet( \%sheetHandle );
					PMSLogging::DumpNote( "", "", "*  Topten::ProcessFakeSplashes($simpleFileName): " .
						"Done with '$simpleFileName' " .
						"- $lineNum lines read, $numResultLines lines stored." );
					last;
			}
		} # end of while
	
	
} # end of ProcessFakeSplashes()



###################################################################################
#### Compute points for all swimmers ##############################################
###################################################################################



# ComputePointsForAllSwimmers - process the data in our DB and compute the total number
#	of points for every swimmer.
#
# Updates various database tables, including ....
# Once all the swimmer's points are computed the ComputeTopPoints() routine can be invoked to
#	compute the top 'N' point earners for each gender.
#

sub ComputePointsForAllSwimmers() { 
	my( $firstName, $middleInitial, $lastName, $gender, $swimmerId, $ageGroup1, $ageGroup2 );
	my( $totalPoints, $totalResultsCounted, $totalResultsAnalyzed );
	my( $sth, $rv );
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $countSwimmers = 0;

	PMSLogging::PrintLog( "", "", "\n** Begin ComputePointsForAllSwimmers", 1 );
	
	# Get the points for each swimmer, broken down by org and course and age group:
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"SELECT FirstName,MiddleInitial,LastName,Gender,SwimmerId,AgeGroup1,AgeGroup2 " .
		"FROM Swimmer" );
	while( defined(my $resultHash = $sth->fetchrow_hashref) ) {
		$countSwimmers++;
		$firstName = $resultHash->{'FirstName'};
		$middleInitial = $resultHash->{'MiddleInitial'};
		$lastName = $resultHash->{'LastName'};
		$gender = $resultHash->{'Gender'};
		$swimmerId = $resultHash->{'SwimmerId'};
		$ageGroup1 = $resultHash->{'AgeGroup1'};
		$ageGroup2 = $resultHash->{'AgeGroup2'};
		
		if( ($countSwimmers % 500) == 0) {
			print "  ...$countSwimmers...\n";
		}
		
		# compute points for each age group separately:
		( $totalPoints, $totalResultsCounted, $totalResultsAnalyzed ) = 
			TT_MySqlSupport::ComputePointsForSwimmer( $swimmerId, $ageGroup1 );
		$TT_Struct::numInGroup{"$gender:$ageGroup1%split"}++ if( $totalPoints > 0 );
		if( $ageGroup2 ne "" ) {
			( $totalPoints, $totalResultsCounted, $totalResultsAnalyzed ) = 
				TT_MySqlSupport::ComputePointsForSwimmer( $swimmerId, $ageGroup2 );
			$TT_Struct::numInGroup{"$gender:$ageGroup2%split"}++ if( $totalPoints > 0 );
		}
		
		# swimmers in two age groups have their age groups "merged":
		if( $ageGroup2 ne "" ) {
			( $totalPoints, $totalResultsCounted, $totalResultsAnalyzed ) = 
				TT_MySqlSupport::ComputePointsForSwimmer( $swimmerId, "$ageGroup1:$ageGroup2" );
			$TT_Struct::numInGroup{"$gender:$ageGroup2%combined"}++ if( $totalPoints > 0 );
		} else {
			$TT_Struct::numInGroup{"$gender:$ageGroup1%combined"}++ if( $totalPoints > 0 );
		}
	} # end of while...
	
	# load the 'numInGroup' data into our database
	foreach my $key (keys %TT_Struct::numInGroup) {
		$key =~ m/^(.):(.*)%(.*)$/;
		my $gender = $1;
		my $ageGroup = $2;
		my $splitAgeGroupTag = $3;
		my $query = "INSERT INTO NumSwimmers (Gender,AgeGroup,SplitAgeGroupTag,NumSwimmers) " .
			"VALUES ('$gender','$ageGroup','$splitAgeGroupTag','$TT_Struct::numInGroup{$key}')";
		my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
		# get the NumSwimmersId for the place we just entered just to make sure there were no errors
	    my $NumSwimmersId = $dbh->last_insert_id(undef, undef, "NumSwimmers", "NumSwimmersId");
	    die "Failed to insert data into NumSwimmers for gender=$gender, ageGroup='$ageGroup' " .
	    	" in ComputePointsForAllSwimmers()" if( !defined( $NumSwimmersId ) );
	}
	
	PMSLogging::PrintLog( "", "", "** END ComputePointsForAllSwimmers ($countSwimmers swimmers)", 1 );

} # end of ComputePointsForAllSwimmers()



# 					GetNumSwimmersInGenderAgeGroup( $thisGenderAgegroup, $splitAgeGroups );
# PASSED:
#	$splitAgeGroups = true if we score points for a swimmer in two age groups separately.
sub GetNumSwimmersInGenderAgeGroup($$) {
	my ($genAgeGroup, $splitAgeGroups) = @_;
	my $splitAgeGroupTag = "combined";
	$splitAgeGroupTag = "split" if( $splitAgeGroups);
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	$genAgeGroup =~ m/^(.):(.*)$/;
	my $gender = $1;
	my $ageGroup = $2;
	my $numSwimmers = 0;
	my $query = "SELECT NumSwimmers FROM NumSwimmers WHERE " .
		"Gender='$gender' AND AgeGroup='$ageGroup' AND SplitAgeGroupTag='$splitAgeGroupTag'";
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query, "" );
 	if( defined(my $resultHash = $sth->fetchrow_hashref) ) {
 		$numSwimmers = $resultHash->{'NumSwimmers'};
 	}
 	return $numSwimmers;
} # end of GetNumSwimmersInGenderAgeGroup()




# ComputeTopPoints - pass over the Points table
#	for every swimmer and store the top $TT_Struct::NumHighPoints male and female swimmers.
#
# PASSED:
#	$gender - 
#	$splitAgeGroups - 1 if we are scoring swimmers in two age groups as two swimmers (one in each
#		age group), or 0 if we are combining such swimmers into one age group. 
#
# RETURNED:
#	$sth - statement handle from which the hash of results can be accessed.
#
#
sub ComputeTopPoints($$) {
	my ($gender, $splitAgeGroups) = @_;
	my $resultHash;
	my( $sth, $rv );
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $query;
	
	# we only care about the top $TT_Struct::NumHighPoints point getters for each gender, so there
	# is no reason to fetch the points for ALL swimmers!  We'll get a few more than $TT_Struct::NumHighPoints
	# swimmers just in case of a tie.  If we really should have fetched more than 3 times this many
	# top swimmers then either it's early in the season and everyone is in a tie so far, or ... Oh Well...
	my $limit = $TT_Struct::NumHighPoints * 3;

	PMSLogging::PrintLog( "", "", "  ** Begin ComputeTopPoints for $gender", 1 );

	if( $splitAgeGroups ) {
		$query = "SELECT Points.SwimmerId,Points.AgeGroup,SUM(Points.TotalPoints) as TotalPoints," .
			"FirstName,MiddleInitial,LastName FROM Points JOIN Swimmer " .
			"WHERE Points.swimmerid = Swimmer.swimmerid " .
			"AND AgeGroup NOT LIKE '%:%' " .
			"AND ((Points.AgeGroup = Swimmer.AgeGroup1) OR (Points.AgeGroup=Swimmer.AgeGroup2)) " .
			"AND Gender = '$gender' " .
			"GROUP BY Swimmer.SwimmerId,Points.AgeGroup ORDER BY TotalPoints DESC,Swimmer.LastName " .
			"LIMIT $limit";
	} else {
		$query = "SELECT Points.SwimmerId, " .
			"(IF(Swimmer.AgeGroup2='',Swimmer.AgeGroup1,Swimmer.AgeGroup2)) as AgeGroup, " .
			"SUM(Points.TotalPoints) as TotalPoints,FirstName,MiddleInitial,LastName  " .
			"FROM (FinalPlaceCAG JOIN Swimmer) JOIN Points WHERE " .
			"Swimmer.SwimmerId=FinalPlaceCAG.SwimmerId AND Points.SwimmerId=Swimmer.SwimmerId " .
			"AND Points.AgeGroup=FinalPlaceCAG.AgeGroup " .
			"AND Points.AgeGroup=(IF(Swimmer.AgeGroup2='',Swimmer.AgeGroup1,CONCAT(Swimmer.AgeGroup1,':',Swimmer.AgeGroup2))) " .
			"AND Gender='$gender' " .
			"GROUP BY Swimmer.SwimmerId,FinalPlaceCAG.AgeGroup,Points.AgeGroup " .
			"ORDER BY TotalPoints DESC,Swimmer.LastName " .
			"LIMIT $limit";
	}

	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );

	PMSLogging::PrintLog( "", "", "  ** End ComputeTopPoints for $gender", 1 );
	
	return $sth;
} # end of ComputeTopPoints()



# InsertSOTY - insert a new swimmer into our %SwimmersOfTheYear{} / %PointsForSwimmerOfTheYear{}, removing
#	swimmers with fewer points in the arrays if necessary.
#
# PASSED:
#	$gender - the gender of the new swimmer
#	$index - index into the %SwimmersOfTheYear{} / %PointsForSwimmerOfTheYear{} arrays of a swimmer
#		that has less than of the same points as the passed new swimmer.
#	$points - the points for the new swimmer
#	$swimmerId - the swimmerID of the new swimmer
#	$ageGroup - the age group for this swimmer's points, in the form "18-25" or "35-39"
#
# RETURNED:
#	n/a
#
# NOTES:
#	Uses and updates $TT_Struct variables.
#	It is guaranteed that $TT_Struct::NumSwimmersOfTheYear{$gender} is at least 1 (which means that
#	there is at least one element in both of the %SwimmersOfTheYear{} / %PointsForSwimmerOfTheYear{}
#	arrays.)
#
sub InsertSOTY( $$$$ ) {
	my ($gender, $index, $points, $swimmerId, $ageGroup) = @_;
	my $i;
	my $debugSwimmerId = -1;
	
	if( $swimmerId == $debugSwimmerId ) {
		print "In InsertSOTY with swimmerId $swimmerId, points=$points\n";
	}
	# slide everyone down in our %SwimmersOfTheYear{} / %PointsForSwimmerOfTheYear{} arrays starting 
	# with the 'index-th' person on...
	my $lastIndex = $TT_Struct::NumSwimmersOfTheYear{$gender}-1;
	for( $i = $lastIndex; $i >= $index; $i-- ) {
		$TT_Struct::SwimmersOfTheYear{$gender}[$i+1] = $TT_Struct::SwimmersOfTheYear{$gender}[$i];
		$TT_Struct::PointsForSwimmerOfTheYear{$gender}[$i+1] = $TT_Struct::PointsForSwimmerOfTheYear{$gender}[$i];
	}
	# insert our new swimmer
	$TT_Struct::SwimmersOfTheYear{$gender}[$index] = "$swimmerId|$ageGroup";
	$TT_Struct::PointsForSwimmerOfTheYear{$gender}[$index] = $points;
	$TT_Struct::NumSwimmersOfTheYear{$gender}++;
	
	# If we've got too many swimmers in our %SwimmersOfTheYear{} / %PointsForSwimmerOfTheYear{} arrays
	# we'll remove some UNLESS ties keep them in our array.  First, see if we have more swimmers in
	# our arrays than we want:
	if( $TT_Struct::NumSwimmersOfTheYear{$gender} > $TT_Struct::NumHighPoints ) {
		# yep - remove some if possible
		my $lastPlacePoints = $TT_Struct::PointsForSwimmerOfTheYear{$gender}[$TT_Struct::NumHighPoints-1];
		# remove all swimmers with fewer points than $lastPlacePoints
		$lastIndex++;
		for( $i = $lastIndex; $i > $TT_Struct::NumHighPoints-1; $i-- ) {
			if( $TT_Struct::PointsForSwimmerOfTheYear{$gender}[$i] == $lastPlacePoints ) {
				last;
			}
		}
		# remove all entries from $i through the end of the %SwimmersOfTheYear{} / 
		# %PointsForSwimmerOfTheYear{} arrays
		$TT_Struct::NumSwimmersOfTheYear{$gender} = $i+1;
	}
} # end of InsertSOTY()




###################################################################################
#### Compute place for all swimmers ##############################################
###################################################################################



sub ComputePlaceForAllSwimmers() {
	my( $firstName, $middleInitial, $lastName, $swimmerId, $totalPoints );
	my( $sth, $rv );
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $countSwimmers = 0;
	my $query;

	PMSLogging::PrintLog( "", "", "** Begin ComputePlaceForAllSwimmers (FinalPlaceSAG)", 1 );

	# Compute the place for each swimmer, where we DO NOT combine split age groups.  This means
	# that a swimmer whose age group changes during a season will accumulate points in two 
	# age groups, and have a place in those two age groups:
	foreach my $gender ( ('M', 'F') ) {
		foreach my $ageGroup( @PMSConstants::AGEGROUPS_MASTERS ) {
			my $order = 0;		# order of swimmer in results (1st place rank = 1st place order)
			my $rank = 0;		# the swimmer's placing - two swimmers can have the same rank if tied.
			my $previousPoints = -1;
			$query = "SELECT Points.SwimmerId,SUM(Points.TotalPoints) as TotalPoints, " .
				"FirstName,MiddleInitial,LastName,RegNum " .
				"FROM Points JOIN Swimmer " .
				"WHERE Points.swimmerid = Swimmer.swimmerid " . 
				"AND Points.AgeGroup='$ageGroup' " .
				"AND Swimmer.Gender='$gender' " .
				"GROUP BY Swimmer.SwimmerId ORDER BY TotalPoints DESC,LastName ASC, RegNum ASC";
			($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
			while( defined(my $resultHash = $sth->fetchrow_hashref) ) {
				$countSwimmers++;
				$firstName = $resultHash->{'FirstName'};
				$middleInitial = $resultHash->{'MiddleInitial'};
				$lastName = $resultHash->{'LastName'};
				$swimmerId = $resultHash->{'SwimmerId'};
				$totalPoints = $resultHash->{'TotalPoints'};
				
				if( ($countSwimmers % 500) == 0) {
					print "  ...$countSwimmers ($gender $ageGroup)...\n";
				}
				$order++;		# we have another swimmer, so they are the next in order
				if( $totalPoints == $previousPoints ) {
					# tie - don't increase their rank
				} else {
					$rank = $order;
				}
				$previousPoints = $totalPoints;
				$query = "INSERT INTO FinalPlaceSAG (SwimmerId,AgeGroup,ListOrder,Rank) " .
					"VALUES ('$swimmerId','$ageGroup','$order','$rank')";
				my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );


				# get the FinalPlaceSAGId for the place we just entered just to make sure there were no errors
			    my $finalPlaceSAGId = $dbh->last_insert_id(undef, undef, "FinalPlaceSAG", "FinalPlaceSAGId");
			    die "Failed to insert place into FinalPlaceSAG for swimmerId=$swimmerId in ComputePlaceForAllSwimmers()" 
			    	if( !defined( $finalPlaceSAGId ) );
			} # end of while()
		} # end of foreach my $ageGroup...
	} # end of foreach my $gender...

	PMSLogging::PrintLog( "", "", "** END ComputePlaceForAllSwimmers (FinalPlaceSAG) ($countSwimmers swimmers)", 1 );
	PMSLogging::PrintLog( "", "", "** Begin ComputePlaceForAllSwimmers (FinalPlaceCAG)", 1 );


	# Compute the place for each swimmer, where we combine split age groups.  This means
	# that a swimmer whose age group changes during a season will accumulate points in both
	# age groups but have the points from the younger age group merged into their
	# oldest age group:
	$countSwimmers = 0;
	foreach my $gender ( ('M', 'F') ) {
		foreach my $ageGroup( @PMSConstants::AGEGROUPS_MASTERS ) {
			my $order = 0;		# order of swimmer in results (1st place rank = 1st place order)
			my $rank = 0;		# the swimmer's placing - two swimmers can have the same rank if tied.
			my $previousPoints = -1;
			$query = "SELECT Points.SwimmerId,SUM(Points.TotalPoints) as TotalPoints," .
				"FirstName,MiddleInitial,LastName,AgeGroup " .
				"FROM Points JOIN Swimmer " .
				"WHERE Points.swimmerid = Swimmer.swimmerid " .
				"AND " .
					"((Points.AgeGroup='$ageGroup' AND Swimmer.AgeGroup1='$ageGroup' AND Swimmer.AgeGroup2='') " .
					"OR " .
					"(Swimmer.AgeGroup2='$ageGroup' AND Points.AgeGroup LIKE '%:$ageGroup')) " .
				"AND Swimmer.Gender='$gender' " .
				"GROUP BY Swimmer.SwimmerId,Points.AgeGroup ORDER BY TotalPoints DESC,LastName ASC,RegNum ASC";
			($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
			while( defined(my $resultHash = $sth->fetchrow_hashref) ) {
				$countSwimmers++;
				$firstName = $resultHash->{'FirstName'};
				$middleInitial = $resultHash->{'MiddleInitial'};	
				$lastName = $resultHash->{'LastName'};
				$swimmerId = $resultHash->{'SwimmerId'};
				$totalPoints = $resultHash->{'TotalPoints'};
				my $ageGroupSelected = $resultHash->{'AgeGroup'};
				
				if( ($countSwimmers % 500) == 0) {
					print "  ...$countSwimmers ($gender $ageGroup)...\n";
				}
				$order++;		# we have another swimmer, so they are the next in order
				if( $totalPoints == $previousPoints ) {
					# tie - don't increase their rank
				} else {
					$rank = $order;
				}
				$previousPoints = $totalPoints;
				$query = "INSERT INTO FinalPlaceCAG (SwimmerId,AgeGroup,ListOrder,Rank) " .
					"VALUES ('$swimmerId','$ageGroupSelected','$order','$rank')";
				my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );

				# get the FinalPlaceCAGId for the place we just entered just to make sure there were no errors
			    my $finalPlaceCAGId = $dbh->last_insert_id(undef, undef, "FinalPlaceCAG", "FinalPlaceCAGId");
			    die "Failed to insert place into FinalPlaceCAG for swimmerId=$swimmerId in ComputePlaceForAllSwimmers()" 
			    	if( !defined( $finalPlaceCAGId ) );
			} # end of while()
		} # end of foreach my $ageGroup...
	} # end of foreach my $gender...
	
	PMSLogging::PrintLog( "", "", "** END ComputePlaceForAllSwimmers (FinalPlaceCAG) ($countSwimmers swimmers)", 1 );

} # end of ComputePlaceForAllSwimmers()
	
	
	



# template order:
#	AGSOTY-StartHead.html
#		AGSOTY-StartGenAgeGrp.html
#			AGSOTY-StartPersonRow.html
#				AGSOTY-StartDetails.html
#					AGSOTY-StartCourseDetails.html
#						AGSOTY-SingleEvent-PMSTop10.html
#							or
#						AGSOTY-SingleEvent-USMSTop10.html
#							or
#						AGSOTY-SingleEvent-Records.html
#					AGSOTY-EndCourseDetails.html
#				AGSOTY-EndDetails.html
#			AGSOTY-EndPersonRow.html
#		AGSOTY-EndGenAgeGrp.html
#	AGSOTY-EndHead.html
#
# Macros (not a complete list):
#	StartHead:  {YearBeingProcessed}  2016
#	StartHead:  {GenerationDate}  March 16, 2017
#	StartGenAgeGrp:  {GenderAgeGroup}   W/18-24
#   StartGenAgeGrp:  {NumSwimmersInGenAgeGrp}    4
#   StartPersonRow, StartCourseDetails, StartSingleCourse:  {UniquePersonId}  W-18-24-1-5   (category   rowNum)
#	StartPersonRow:  {SwimmersPlace}   5
#	StartDetails:  {SwimmersAgeGroups}  18-24, 25-29
#	StartDetails:  {SwimmersTeams}  TOX, SCAM
#	StartCourseDetails:  {OrgCourse}   Pacific Masters Short Course Yards
#	StartCourseDetails:  {CoursePoints}   28
#	StartCourseDetails:  {PointsWord}   "points" or "point"
#	StartCourseDetails:  {CourseNum}   1, 2, 3...
#	SingleEvent_PMSTop10:   {EventName}    50 Freestyle
#	SingleEvent_PMSTop10:   {Duration}    2:35.07
#	SingleEvent_PMSTop10:  {Rank}   1, 2, 3, ...
#	SingleEvent_PMSTop10:  {EventPoints}   12
#	SingleEvent_PMSTop10:  {PointsWord}   "points" or "point"
#	SingleEvent_PMSTop10:  {CourseNum}   1, 2, 3...
#	SingleEvent_PMSTop10:  {UniqueSplashId}   1, 2, 3...
#	SingleEvent_PMSTop10:  {MeetName}   Pacific Masters Short Course Championships
#	SingleEvent_PMSTop10:  {EventDate}   2016-3-22

#	SingleEvent_USMSTop10:   {EventName}    50 Freestyle
#	SingleEvent_USMSTop10:   {Duration}    2:35.07
#	SingleEvent_USMSTop10:  {Rank}   1, 2, 3, ...
#	SingleEvent_USMSTop10:  {EventPoints}   12
#	SingleEvent_USMSTop10:  {PointsWord}   "points" or "point"
#	SingleEvent_USMSTop10:  {CourseNum}   1, 2, 3...
#	SingleEvent_USMSTop10:  {UniqueSplashId}   1, 2, 3...
#	SingleEvent_USMSTop10:  {MeetName}   Pacific Masters Short Course Championships
#	SingleEvent_USMSTop10:  {EventDate}   2016-3-22

#	SingleEvent_Records:   {EventName}    50 Freestyle
#	SingleEvent_Records:   {Duration}    2:35.07
#	SingleEvent_Records:  {SwimDate}   2016-3-24
#	SingleEvent_Records:  {CoursePoints}   28
#	SingleEvent_Records:  {PointsWord}   "points" or "point"
#	SingleEvent_Records:  {CourseNum}   1, 2, 3...

#	SingleEvent_OW:  {EventName}   Spring Lake 1 Mile
#	SingleEvent_OW:  {Duration}    22:35.07
#	SingleEvent_OW:  {Rank}   1, 2, 3, ...
#	SingleEvent_OW:  {SwimDate}   2016-3-24
#	SingleEvent_OW:  {CoursePoints}   28
#	SingleEvent_OW:  {PointsWord}   "points" or "point"
#	SingleEvent_OW:  {EventDate}   2016-3-22

#	EndPersonRow:  {USMSSwimmerId}    386-B0BUP
#	EndHead:	  {GenerationTimeDate}    Tue Aug  9 17:50:43 2016


# GenerateHTMLResults - main driver for the generation of the HTML pages 
#
# PASSED:
#	$finalPlaceTableName - 
#	$masterGeneratedHTMLFileName - 
#	$generatedHTMLFileSubDir
#	AND we use data from the database
#
# RETURNED:
#	n/a
#
# SIDE EFFECTS:
#	Various files are written to:
#		$generatedHTMLFileDir - the master file directory
#		$generatedHTMLFileSubDir - the "virtual" HTML files directory
#
sub PrintResultsHTML($$$) {
	my ( $finalPlaceTableName, $masterGeneratedHTMLFileName, $generatedHTMLFileSubDir ) = @_;
	my $templateStartHead = "$templateDir/AGSOTY-StartHead.html";
	my $templateStartGenAgeGrp = "$templateDir/AGSOTY-StartGenAgeGrp.html";
	my $templateStartPersonRow = "$templateDir/AGSOTY-StartPersonRow.html";
	my $templateStartDetails = "$templateDir/AGSOTY-StartDetails.html";
	my $templateStartCourseDetails = "$templateDir/AGSOTY-StartCourseDetails.html";
	my $templateSingleEvent_PMSTop10 = "$templateDir/AGSOTY-SingleEvent_PMSTop10.html";
	my $templateSingleEvent_USMSTop10 = "$templateDir/AGSOTY-SingleEvent_USMSTop10.html";
	my $templateSingleEvent_Records = "$templateDir/AGSOTY-SingleEvent_Records.html";
	my $templateSingleEvent_OW = "$templateDir/AGSOTY-SingleEvent_OW.html";
	my $templateEndCourseDetails = "$templateDir/AGSOTY-EndCourseDetails.html";
	my $templateEndDetails = "$templateDir/AGSOTY-EndDetails.html";
	my $templateEndPersonRow = "$templateDir/AGSOTY-EndPersonRow.html";
	my $templateEndGenAgeGrp = "$templateDir/AGSOTY-EndGenAgeGrp.html";
	my $templateEndHead = "$templateDir/AGSOTY-EndHead.html";
	my $templateMoreThan10 = "$templateDir/AGSOTY-MoreThan10.html";
	my $templateSOTY = "$templateDir/AGSOTY-soty.html";
	my $query;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	
	my $debugLastName = "xxxxx";

	my $category = 1;		# we only consider Cat 1 swims
	my $personBackgroundColor = "WHITE";		# background color for each row (computed below)
		
	#	$splitAgeGroups - 1 if we are scoring swimmers in two age groups as two swimmers (one in each
	#		age group), or 0 if we are combining such swimmers into one age group. 
	my $splitAgeGroups;
	if( $finalPlaceTableName eq "FinalPlaceCAG" ) {
		# combine age groups
		$splitAgeGroups = 0;
		PMSStruct::GetMacrosRef()->{"HTMLVSupportDir"} = "HTMLVSupport-CAG";		# ...
	} else {
		# split age groups
		$splitAgeGroups = 1;
		PMSStruct::GetMacrosRef()->{"HTMLVSupportDir"} = "HTMLVSupport-SAG";		# ...
	}
	
	# make sure our subdirectory of HTML snippets exists:
	if( ! -e $generatedHTMLFileSubDir ) {
		# nope - create it
		mkdir $generatedHTMLFileSubDir;
	}

	####################
	# Begin processing our templates, generating our accumulated result file in the process
	####################
	print "PrintResultsHTML(): starting (using table $finalPlaceTableName) ...\n";
	
	open( my $masterGeneratedHTMLFileHandle, ">", $masterGeneratedHTMLFileName ) or
		die( "Can't open $masterGeneratedHTMLFileName: $!" );
	# full path name of a "virtual" HTML file we are going to generate (we'll generate lots
	# of them!)
	my $virtualGeneratedHTMLFileName;

	# first, the initial part of the master HTML file
	ProcessHTMLTemplate( $templateStartHead, $masterGeneratedHTMLFileHandle );

	# Since we have already computed the points and places for every swimmer we are going to 
	# print them out in order of gender and age group, ordered highest to lowest points 
	# (lowest to highest place) for each gender / age group:
	# The query we use to get the place for every swimmer depends on what rule we're following:
	# are we considering a swimmer with a split age group as two swimmers (one in each age group)
	# or are we combining the two age groups, thus the swimmer is placed in the older age group?
	# We use the name of the FinalPlace table to tell us what to do:
	$query = GetPlaceOrderedSwimmersQuery( $splitAgeGroups );
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	# we've got the list of swimmers ...
	my $previousGenderAgegroup = "";
	my $previousGender = "";
	my $numSwimmersSeenSoFar = 0;	# used to assign a unique ID in the html
	# pass through the list in order of gender, agegroup, and list order:
	while( defined(my $resultHash = $sth->fetchrow_hashref) ) {
			my $firstName = $resultHash->{'FirstName'};
			my $middleInitial = $resultHash->{'MiddleInitial'};
			my $lastName = $resultHash->{'LastName'};
			my $team = $resultHash->{'RegisteredTeamInitials'};
			my $ageGroup = $resultHash->{'AgeGroup'};			# of the form 18-24 or 18-24:25-29
			my $rank = $resultHash->{'Rank'};
			my $points = $resultHash->{'Points'};
			my $listOrder = $resultHash->{'ListOrder'};
			my $ageGroupCAG = $resultHash->{'AgeGroupCAG'};		# of the form 18-24
			my $gender = $resultHash->{'Gender'};
			my $swimmerId = $resultHash->{'SwimmerId'};
			my $regNum = $resultHash->{'RegNum'};
			my $thisGenderAgegroup = "$gender:$ageGroupCAG";

			if( lc($lastName) eq $debugLastName) {
				print "\nPrintResultsHTML(): found $debugLastName: ageGroup=$ageGroup, ageGroupCAG=$ageGroupCAG, $previousGenderAgegroup, $thisGenderAgegroup\n";
			}
			# are we starting a new gender and/or age group?
			if( $previousGenderAgegroup ne $thisGenderAgegroup ) {
				# YES - new gender/age group.  BUT FIRST, close the previous gender/age group
				# if there was one:
				if( $previousGenderAgegroup ne "" ) {
					# every age group ends with a hidden "Click here for more..."
					PMSStruct::GetMacrosRef()->{"DisplayForMoreThan10"} = "none";		# ...
					ProcessHTMLTemplate( $templateMoreThan10, $virtualGeneratedHTMLFileHandle );
					# now end the age group
					ProcessHTMLTemplate( $templateEndGenAgeGrp, $masterGeneratedHTMLFileHandle );
					ProcessHTMLTemplate( $templateEndGenAgeGrp, $virtualGeneratedHTMLFileHandle );
					close($virtualGeneratedHTMLFileHandle);
				}
				$previousGenderAgegroup = $thisGenderAgegroup;
				$numSwimmersSeenSoFar = 0;		# used to assign a unique ID in the html
			
				# start a new gender/age group
				PMSStruct::GetMacrosRef()->{"GenderAgeGroup"} = $thisGenderAgegroup;
				PMSStruct::GetMacrosRef()->{"NumSwimmersInGenAgeGrp"} = 
					GetNumSwimmersInGenderAgeGroup( $thisGenderAgegroup, $splitAgeGroups );
				
				### a little logging to stdout to keep us informed...
				if( $previousGender eq "" ) {
					$previousGender = $gender;
					print "   ...";
				} elsif( $previousGender ne $gender ) {
					print "\n   ...";
					$previousGender = $gender;
				}
				print " $thisGenderAgegroup";
				###
				
				# initialize details of the "virtual" page we're going to create
				my $virtualFileName = $thisGenderAgegroup;		# of the form 'F:18-24' or 'M:50-54'
				$virtualFileName =~ s,[:/],-,g;		# '/' and ':' are special in some filesystems, so
					# now $virtualFileName is of the form 'F-18-24' or 'M-50-54'
				PMSStruct::GetMacrosRef()->{"VirtualFileName"} = $virtualFileName;
				$virtualGeneratedHTMLFileName = "$generatedHTMLFileSubDir/$virtualFileName.html";
				# also, create the "virtual HTML page" for this gender/age group only
				open( $virtualGeneratedHTMLFileHandle, ">", $virtualGeneratedHTMLFileName ) or
					die( "Can't open $virtualGeneratedHTMLFileName: $!" );
				# now begin generation of this new gender/age group:
				ProcessHTMLTemplate( $templateStartGenAgeGrp, $masterGeneratedHTMLFileHandle );
				ProcessHTMLTemplate( $templateStartGenAgeGrp, $virtualGeneratedHTMLFileHandle );
			} # end of are we starting a new gender and/or age group?
			# set the age group(s) for the swimmer we're now working on:
			PMSStruct::GetMacrosRef()->{"SwimmersAgeGroups"} = $ageGroup;
			PMSStruct::GetMacrosRef()->{"SwimmersAgeGroups"} =~ s/:/, /;		# make it look better
			# increment the number of swimmers we've seen in this gender/age group so far:
			$numSwimmersSeenSoFar++;
			# if this is the first place swimmer in this gender / age group then color their row
			# top female:  light yellow
			# top male: light gray
			if( $rank == 1 ) {
				if( $gender eq 'M' ) {
					$personBackgroundColor = "LightCyan";
				} else {
					$personBackgroundColor = "LightPink";
				}
			} else {
				if( $personBackgroundColor eq "White" ) {
					$personBackgroundColor = "#D9D9D9";
				} else {
					$personBackgroundColor = "White";
				}
			}
			PMSStruct::GetMacrosRef()->{"PersonBackgroundColor"} = $personBackgroundColor;
			
			# get points for this swimmer:
			my ( $countPoints, $countPMSPoints, $countHidden, $countPMSHidden) = GetSwimmerMeetDetails($swimmerId);
			
			
			# if this swimmer swam less than 2 meets then we'll flag them
			my $minSwimMeetsFlag = "";
			# NO!  REMOVED THIS FEATURE FROM HTML AS REQUESTED BY BOB A.
			#$minSwimMeetsFlag = "*" if( $countPMS < 2 );

			# display this swimmer's name and points
			my $uniquePersonId = $thisGenderAgegroup;
			$uniquePersonId =~ s,/,-,;		# now in the form "W-18-24"
			$uniquePersonId .= "-$category-$numSwimmersSeenSoFar";		# now in the form "W-18-24-1-5"
			PMSStruct::GetMacrosRef()->{"UniquePersonId"} = $uniquePersonId;
			PMSStruct::GetMacrosRef()->{"SwimmersPlace"} = $rank;
			PMSStruct::GetMacrosRef()->{"SwimmersPoints"} = 
				"$minSwimMeetsFlag$points$minSwimMeetsFlag";
			PMSStruct::GetMacrosRef()->{"SwimmersName"} = 
				"$firstName $middleInitial $lastName";
			PMSStruct::GetMacrosRef()->{"ClassCollapse"} = 
				"class='$thisGenderAgegroup-Collapse'";		# default collapse swimmers >= 11
			if( $numSwimmersSeenSoFar <= 10 ) {
				# the master html file only shows the top 10 swimmers
				ProcessHTMLTemplate( $templateStartPersonRow, $masterGeneratedHTMLFileHandle );
				PMSStruct::GetMacrosRef()->{"Collapse"} = "DontCollapse";	# don't remove this swimmer when collapsing
				PMSStruct::GetMacrosRef()->{"ClassCollapse"} = "";		# don't allow collapse of swimmers <= 10
				PMSStruct::GetMacrosRef()->{"LessThan11"} = "xx";	# see MoreThan10.html
			} elsif( $numSwimmersSeenSoFar == 11 ) {
				# the master html file will show a link allowing the user to view swimmers
				# past #10 if there are 11 or more swimmers in this gender/age group
				PMSStruct::GetMacrosRef()->{"DisplayForMoreThan10"} = "";		# ...
				ProcessHTMLTemplate( $templateMoreThan10, $masterGeneratedHTMLFileHandle );
				PMSStruct::GetMacrosRef()->{"ClassCollapse"} = "class='$thisGenderAgegroup-Collapse'";		# ...
				PMSStruct::GetMacrosRef()->{"LessThan11"} = "";		# see MoreThan10.html
			}
			ProcessHTMLTemplate( $templateStartPersonRow, $virtualGeneratedHTMLFileHandle );

			# now generate the details of this swimmer's swims
			PMSStruct::GetMacrosRef()->{"NumSwimmersMeets"} = $countPoints+$countHidden;
			PMSStruct::GetMacrosRef()->{"NumSwimmersMeetsDetails"} = "$countPoints scoring meets, " .
				"$countHidden hidden meets";
			PMSStruct::GetMacrosRef()->{"NumSwimmersPACMeets"} = $countPMSPoints+$countPMSHidden;
			PMSStruct::GetMacrosRef()->{"NumSwimmersPACMeetsDetails"} = "$countPMSPoints PAC scoring " .
				"meets, $countPMSHidden PAC hidden meets";
				
			# get the list of meets that this swimmer swam in that earned points:
			my $query = "SELECT DISTINCT(Splash.MeetId),Meet.MeetTitle,Meet.MeetLink," .
				"Meet.MeetIsPMS,Meet.MeetBeginDate " .
				"FROM Splash JOIN Meet WHERE " .
				"Splash.MeetId = Meet.MeetId AND " .
				"Splash.MeetId != 1 AND " .
				"Splash.SwimmerId = $swimmerId ORDER by Meet.MeetBeginDate";
			my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
			my $swimmersMeetDetails = "";
			while( defined(my $resultHash = $sth->fetchrow_hashref) ) {
				my $meetId = $resultHash->{'MeetId'};
				my $meetTitle = $resultHash->{'MeetTitle'};
				my $meetLink = $resultHash->{'MeetLink'};
				if( $meetLink eq "(none)" ) {
					# special case:  we don't have a link for this meet, so don't generate an href
					$meetLink = "";
				}
				my $meetIsPMS = $resultHash->{'MeetIsPMS'};
				my $sanction = $meetIsPMS ? "PAC" : "Non PAC";
				# get the sum of all points earned at this meet
				my $query2 = "SELECT SUM(Points) AS Points from Splash WHERE " .
					"Splash.MeetId = $meetId AND Splash.SwimmerId = $swimmerId";
				my ($sth2, $rv2) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query2 );
				my $resultHash2 = $sth2->fetchrow_hashref;
				my $points = $resultHash2->{'Points'};
				my $swimmersMeetDetailsLink = $meetTitle;		# assume no link to meet details
				if( $meetLink ne "" ) {
					# we have meet details - create a link to them
					$swimmersMeetDetailsLink = "<a href='$meetLink'>$meetTitle</a>";
				}
				$swimmersMeetDetails .= "<tr>\n" .
					"  <td>$swimmersMeetDetailsLink</td>\n" .
					"  <td>$sanction</td>\n" .
					"  <td>$points</td>\n" .
					"</tr>\n";
			}
			# next, get get the list of hidden meets
			$query = "SELECT USMSDirectory.MeetId,Meet.MeetTitle,Meet.MeetLink,Meet.MeetIsPMS from USMSDirectory JOIN Meet WHERE " .
				"USMSDirectory.MeetId = Meet.MeetId AND " .
				"USMSDirectory.MeetId != 1 AND " .
				"USMSDirectory.SwimmerId = $swimmerId ORDER by Meet.MeetBeginDate";
			($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
			while( defined(my $resultHash = $sth->fetchrow_hashref) ) {
				my $meetId = $resultHash->{'MeetId'};
				my $meetTitle = $resultHash->{'MeetTitle'};
				my $meetLink = $resultHash->{'MeetLink'};
				my $meetIsPMS = $resultHash->{'MeetIsPMS'};
				my $sanction = $meetIsPMS ? "PAC" : "Non PAC";
				$swimmersMeetDetails .= "<tr>\n" .
					"  <td><a href='$meetLink'>$meetTitle</a></td>\n" .
					"  <td>$sanction</td>\n" .
					"  <td>H</td>\n" .
					"</tr>\n";
			}				
			PMSStruct::GetMacrosRef()->{"SwimmersMeetDetails"} = $swimmersMeetDetails;
			PMSStruct::GetMacrosRef()->{"SwimmersTeams"} = $team;

			ProcessHTMLTemplate( $templateStartDetails, $virtualGeneratedHTMLFileHandle );
			my $courseNum = 0;
			foreach my $org( @PMSConstants::arrOfOrg ) {
				foreach my $course( @PMSConstants::arrOfCourse ) {
					# there is no such thing as "USMS-OW"
					next if( ($org eq "USMS") && ($course eq "OW") );
					# if we did NOT read any results for this org and course then we skip this
					# org/course combination (e.g. we are generating this page during the 
					# long course season, so we don't have any USMS long course data.)
					next if( $missingResults{"$org-$course"} );

					if( lc($lastName) eq $debugLastName) {
						print "\nPrintResultsHTML(): found $debugLastName again\n";
					}

					my @details = ();
					my $detailsRef = \@details;
					my ($detailsNum, $totalPoints, $resultsCounted) = 
						TT_MySqlSupport::GetSwimmersSwimDetails2( $swimmerId, $org, $course, $ageGroup, $detailsRef );
					# if we don't have any points
					# for this org-course for this swimmer we set the value to 0.
					# (e.g. the swimmer has results for short course PMS, but
					# no results for long course PMS)
					next if( $totalPoints == 0 );
					# we've got an org/course to show:
					$courseNum++;
					PMSStruct::GetMacrosRef()->{"OrgCourse"} = $hashOfLongNames{$org} . " " .
						$hashOfLongNames{$course};
					PMSStruct::GetMacrosRef()->{"CourseNum"} = $courseNum;
					PMSStruct::GetMacrosRef()->{"CoursePoints"} = $totalPoints;
					PMSStruct::GetMacrosRef()->{"PointsWord"} = "points";
					PMSStruct::GetMacrosRef()->{"PointsWord"} = "point" if( PMSStruct::GetMacrosRef()->{"CoursePoints"} == 1 );
					ProcessHTMLTemplate( $templateStartCourseDetails, $virtualGeneratedHTMLFileHandle );

					# now generate the details for this org-course (multiple rows, each row represents
					# a single point-earning swim for this org-course).  The rows are in order of points earned
					# in decending order.
					# First, get the correct template file:
					my $templateSingleEvent;
					if( $course eq "OW" ) {
						$templateSingleEvent = $templateSingleEvent_OW;
					} elsif( $course =~ m/^.*Records$/ ) {
						$templateSingleEvent = $templateSingleEvent_Records;
					} elsif( $org eq "PAC" ) {
						$templateSingleEvent = $templateSingleEvent_PMSTop10;
					} else {
						$templateSingleEvent = $templateSingleEvent_USMSTop10;
					}
					# next, the details...
					my $uniqueSplashId = 0;
					for( my $i = 1; $i <= $detailsNum; $i++ ) {
						my $resultHashRef = \($detailsRef->[$i]);
						# We've got details on one splash that earned points for this swimmer in this
						# org and course:
						$uniqueSplashId++;
						PMSStruct::GetMacrosRef()->{"EventName"} = $detailsRef->[$i]{'EventName'};
						PMSStruct::GetMacrosRef()->{"Duration"} = 
							PMSUtil::GenerateDurationStringFromHundredths( $detailsRef->[$i]{'Duration'} );
						
						my $eventPlace = $detailsRef->[$i]{'Place'};
						if( $eventPlace == 1 ) {
							$eventPlace = $eventPlace . "st";
						} elsif( $eventPlace == 2 ) {
							$eventPlace = $eventPlace . "nd";
						} elsif( $eventPlace == 3 ) {
							$eventPlace = $eventPlace . "rd";
						} else {
							$eventPlace = $eventPlace . "th";
						}
						PMSStruct::GetMacrosRef()->{"Rank"} = $eventPlace;
						PMSStruct::GetMacrosRef()->{"place_word"} = " place ";
						PMSStruct::GetMacrosRef()->{"EventPoints"} = $detailsRef->[$i]{'Points'};
						PMSStruct::GetMacrosRef()->{"PointsWord"} = "points";
						PMSStruct::GetMacrosRef()->{"PointsWord"} = "point" if( $detailsRef->[$i]{'Points'} == 1 );
						PMSStruct::GetMacrosRef()->{"UniqueSplashId"} = $uniqueSplashId;
						PMSStruct::GetMacrosRef()->{"MeetName"} = $detailsRef->[$i]{'MeetTitle'};
						# show the date IF we have one:
						my $date = $detailsRef->[$i]{'Date'};
						if( (!defined $date) || ($date eq $PMSConstants::DEFAULT_MISSING_DATE) ) {
							$date = "";
						} else {
							$date = "on $date";
						}
						PMSStruct::GetMacrosRef()->{"EventDate"} = $date;

						# this is normally just a sanity check, but we actually have two reasons
						# for the following.  We're going to check to make sure this swimmer didn't
						# get points two or more times for the same event (e.g. points for PAC top 10
						# 100 free SCY for 3rd place and 5th place.) Normally this shouldn't be possible,
						# but we'll check anyway just in case the results have a bug.  But this can happen
						# (correctly) if a swimmer is in a split age group and we combine their points into
						# a single age group.  The swimmer can get 5th in the younger age group and
						# swim it again in the older age group and get 2nd.  If we combine points from
						# the two age groups we need to be careful to NOT give them points for both the
						# 5th and 2nd places.  Instead only the higher points are awarded (2nd place)
						if( PMSStruct::GetMacrosRef()->{"EventPoints"} == -1 ) {
							# duplicate event earning points (probably in a different age group)
							my $detailsAgeGroup = $detailsRef->[$i]{'AgeGroup'};
							# assume we're dealing with a split age group that we're combining into one...
							$ageGroup =~ m/^(.*):(.*)$/;
							my $lowerAgeGroup = $1;
							my $upperAgeGroup = $2;
							my $pointsStartString = "- upgraded in other age group";
							if( !defined $lowerAgeGroup ) {
								# oops - not a split age group...weird...
								PMSLogging::DumpError( "", "", "PrintResultsHTML: Found a swimmer " .
									"who placed top 10 in the same event twice.  SwimmerId=" .
									"$swimmerId, $org, $course, event='" . $detailsRef->[$i]{'EventName'} .
									"'", 1 );
							} else {
								if( $detailsAgeGroup = $lowerAgeGroup ) {
									$pointsStartString = "- using points earned in $upperAgeGroup";
								} else {
									$pointsStartString = "- using points earned in $lowerAgeGroup";
								}
							}
							PMSStruct::GetMacrosRef()->{"PointsStart"} = "$pointsStartString<!-- ";
							PMSStruct::GetMacrosRef()->{"PointsEnd"} = " -->";
						} elsif( PMSStruct::GetMacrosRef()->{"EventPoints"} == 0 ) {
							# they had more than 8 point-awarding places so we'll show what they got
							# but not show their points since they didn't earn any.
							PMSStruct::GetMacrosRef()->{"PointsStart"} = "<!-- ";
							PMSStruct::GetMacrosRef()->{"PointsEnd"} = " -->";
						} else {
							# this is one of the top 8 results
							PMSStruct::GetMacrosRef()->{"PointsStart"} = "";
							PMSStruct::GetMacrosRef()->{"PointsEnd"} = "";
						}

						ProcessHTMLTemplate( $templateSingleEvent, $virtualGeneratedHTMLFileHandle );
					} # end of for( my $i = 1; $i <= $detailsNum; ...
					ProcessHTMLTemplate( $templateEndCourseDetails, $virtualGeneratedHTMLFileHandle );
				}
			}
			ProcessHTMLTemplate( $templateEndDetails, $virtualGeneratedHTMLFileHandle );

			# all done with this person...
			if( $numSwimmersSeenSoFar <=10 ) {
				ProcessHTMLTemplate( $templateEndPersonRow, $masterGeneratedHTMLFileHandle );
			}
			ProcessHTMLTemplate( $templateEndPersonRow, $virtualGeneratedHTMLFileHandle );
		} # end of while( defined(my $resultHash...

	# All Done!  finish the currently generating GenAgeGrp (if one, which there is if we have
	# any data at all!) :
	if( $previousGenderAgegroup ne "" ) {
		ProcessHTMLTemplate( $templateEndGenAgeGrp, $masterGeneratedHTMLFileHandle );
		ProcessHTMLTemplate( $templateEndGenAgeGrp, $virtualGeneratedHTMLFileHandle );
		# every age group ends with a hidden "Click here for more..."
		close($virtualGeneratedHTMLFileHandle);
	}
	
	# next, finish the master HTML file and then close it:
	ProcessHTMLTemplate( $templateEndHead, $masterGeneratedHTMLFileHandle );
	close( $masterGeneratedHTMLFileHandle );
	print("\n");
	
	###
	# lastly, generate the SOTY html file used only if the web page is requested correctly
	my $virtualSotyFileName = "$generatedHTMLFileSubDir/soty.html";
	open( my $sotyGeneratedHTMLFileHandle, ">", $virtualSotyFileName ) or
		die( "Can't open $virtualSotyFileName: $!" );
	my $sotyList = "";
	
	# work on the top females first:
	$sth = ComputeTopPoints( 'F', $splitAgeGroups );
	my $previousPoints = -1;
	my $numTopPoints=0;
	while( $numTopPoints <= $TT_Struct::NumHighPoints ) {
		my $resultHash = $sth->fetchrow_hashref;
		if( !defined $resultHash ) {
			PMSLogging::DumpError( "", "", "Ran out of top female point getters!", 1 );
			last;
		}
		my $firstName = $resultHash->{"FirstName"};
		my $middleInitial = $resultHash->{"MiddleInitial"};
		my $lastName = $resultHash->{"LastName"};
		my $totalPoints = $resultHash->{"TotalPoints"};
		my $ageGroup = $resultHash->{'AgeGroup'};
		$numTopPoints++ if( $previousPoints != $totalPoints );
		$previousPoints = $totalPoints;
		if( $numTopPoints <= $TT_Struct::NumHighPoints ) {
			$sotyList .= "<a href=\"#F-$ageGroup-GenAgeDiv\" style=\"color:red\">" .
				"$firstName $middleInitial $lastName: $totalPoints points</a><br>\n";
		}
	}
	if( $numTopPoints > 1 ) {
		PMSStruct::GetMacrosRef()->{"FemaleSOTYtie1"} = "s";
	} else {
		PMSStruct::GetMacrosRef()->{"FemaleSOTYtie1"} = "";
	}
	PMSStruct::GetMacrosRef()->{"FemaleSOTY"} = $sotyList;
	
	# now top males:
	$sotyList = "";
	$sth = ComputeTopPoints( 'M', $splitAgeGroups );
	$numTopPoints=0;
	while( $numTopPoints <= $TT_Struct::NumHighPoints ) {
		my $resultHash = $sth->fetchrow_hashref;
		if( !defined $resultHash ) {
			PMSLogging::DumpError( "", "", "Ran out of top male point getters!", 1 );
			last;
		}
		my $firstName = $resultHash->{"FirstName"};
		my $middleInitial = $resultHash->{"MiddleInitial"};
		my $lastName = $resultHash->{"LastName"};
		my $totalPoints = $resultHash->{"TotalPoints"};
if(!defined $totalPoints) {
	my $swimmerid=$resultHash->{"SwimmerId"};
	print "PrintResultsHTML():  undefined totalpoints for swimmerid $swimmerid\n";
}
		my $ageGroup = $resultHash->{'AgeGroup'};
		$numTopPoints++ if( $previousPoints != $totalPoints );
		$previousPoints = $totalPoints;
		if( $numTopPoints <= $TT_Struct::NumHighPoints ) {
			$sotyList .= "<a href=\"#M-$ageGroup-GenAgeDiv\">" .
				"$firstName $middleInitial $lastName: $totalPoints points</a><br>\n";
		}
	}
	if( $numTopPoints > 1 ) {
		PMSStruct::GetMacrosRef()->{"MaleSOTYtie1"} = "s";
	} else {
		PMSStruct::GetMacrosRef()->{"MaleSOTYtie1"} = "";
	}
	PMSStruct::GetMacrosRef()->{"MaleSOTY"} = $sotyList;

	# now for more details
	my $meetList = "";
	my ($ListOfMeetsStatementHandle, $numPoolMeets, $numOWMeets, $numPMSMeets) = TT_MySqlSupport::GetListOfMeets( );
	PMSStruct::GetMacrosRef()->{'NumberOfPoolMeets'} = $numPoolMeets;
	PMSStruct::GetMacrosRef()->{'NumberOfOWMeets'} = $numOWMeets;	
	PMSStruct::GetMacrosRef()->{'NumberOfPMSMeets'} = $numPMSMeets;	
	my $meetCount = 0;
	while( defined(my $resultHash = $ListOfMeetsStatementHandle->fetchrow_hashref) ) {
		$meetCount++;
		my $isPMS = "No";
		$isPMS = "<b>YES</b>" if( $resultHash->{'MeetIsPMS'} );
		my $date = $resultHash->{'MeetBeginDate'};
		$date .= " - " . $resultHash->{'MeetEndDate'} if( $resultHash->{'MeetEndDate'} ne $date );
		$date = "(unknown)" if( $date eq $PMSConstants::DEFAULT_MISSING_DATE);
		my ($numSplash, $numSwimmers) = TT_MySqlSupport::GetSplashesForMeet( $resultHash->{'MeetId'} );
		my $meetLink = $resultHash->{'MeetLink'};
		$meetLink = "http://pacificmasters.org" if( ($meetLink eq "") || ($meetLink eq "(none)") );		# default value...
		$meetList .= "    <tr><td>$meetCount</td>\n" .
					 "        <td>" . $resultHash->{'MeetTitle'} . " (" . $resultHash->{'MeetCourse'} . ")</td>\n" .
					 "        <td style=\"text-align:center\">" . $date . "</td>\n" .
					 "        <td style=\"text-align:center\">" . $isPMS . "</td>\n" .
					 "        <td style=\"text-align:center\"><a href='" . $meetLink . "'>Meet Info</a></td>\n" .
					 "        <td style=\"text-align:center\">$numSplash</td>\n" .
					 "        <td style=\"text-align:center\">$numSwimmers</td></tr>\n";
	}
	
	PMSStruct::GetMacrosRef()->{"ListOfMeets"} = $meetList;
	my($num, $numWithPoints) = TT_MySqlSupport::GetNumberOfSwimmers();
	PMSStruct::GetMacrosRef()->{"NumberOfCompetingSwimmers"} = $num;
	PMSStruct::GetMacrosRef()->{"NumberOfSwimmersEarnedPoints"} = $numWithPoints;
	ProcessHTMLTemplate( $templateSOTY, $sotyGeneratedHTMLFileHandle );
	
	print "PrintResultsHTML(): Done (using table $finalPlaceTableName) ...\n";
	
} # end of PrintResultsHTML()




# GetPlaceOrderedSwimmersQuery - construct a SQL query to generate a list of ALL swimmers in order
#	of gender, age group, and place suitable for display.
#
# PASSED:
#	$splitAgeGroups - if true we'll keep swimmers who are in split age groups in those groups.  
#		For example, if Fred is 18-24 during the 2016 season and then ages up to 25-29 during the
#		same season, we'll compute points/place for Fred in the two age groups separately.  If 
#		false we'll combine his points into the 24-29 age groups (removing points for 
#		duplicate events.)
#
# RETURNED:
#	$query - the query ready to be used against our mySql database.
#
sub GetPlaceOrderedSwimmersQuery( $ ) {
	my $splitAgeGroups = $_[0];
	my $query;
	if( $splitAgeGroups ) {
		# keep split age groups
		$query =
			"SELECT FirstName,MiddleInitial,LastName,RegisteredTeamInitials,FinalPlaceSAG.AgeGroup as AgeGroup, " .
				"Rank,ListOrder,SUM(TotalPoints) as Points,FinalPlaceSAG.AgeGroup AS AgeGroupCAG, " .
				"Swimmer.Gender as Gender,Swimmer.SwimmerId as SwimmerId, Swimmer.RegNum as RegNum " .
				"FROM (FinalPlaceSAG JOIN Swimmer) JOIN Points WHERE " .
				"Swimmer.SwimmerId=FinalPlaceSAG.SwimmerId AND Points.SwimmerId=Swimmer.SwimmerId " .
				"AND Points.AgeGroup=FinalPlaceSAG.AgeGroup " .
				"GROUP BY Swimmer.SwimmerId,FinalPlaceSAG.AgeGroup,FinalPlaceSAG.Rank,FinalPlaceSAG.ListOrder " .
				"ORDER BY Gender ASC,FinalPlaceSAG.AgeGroup ASC,ListOrder ASC";
	} else {
		# combine age groups
		$query =
			"SELECT FirstName,MiddleInitial,LastName,RegisteredTeamInitials," .
				"(IF(Swimmer.AgeGroup2='',Swimmer.AgeGroup1,Swimmer.AgeGroup2)) as AgeGroupCAG, " .
				"Rank,ListOrder,SUM(TotalPoints) AS Points,FinalPlaceCAG.AgeGroup AS AgeGroup, " .
				"Swimmer.Gender as Gender,Swimmer.SwimmerId as SwimmerId, Swimmer.RegNum as RegNum " .
				"FROM (FinalPlaceCAG JOIN Swimmer) JOIN Points WHERE " .
				"Swimmer.SwimmerId=FinalPlaceCAG.SwimmerId AND Points.SwimmerId=Swimmer.SwimmerId " .
				"AND Points.AgeGroup=FinalPlaceCAG.AgeGroup " .
				"AND Points.AgeGroup=(IF(Swimmer.AgeGroup2='',Swimmer.AgeGroup1,CONCAT(Swimmer.AgeGroup1,':',Swimmer.AgeGroup2))) " .
				"GROUP BY Swimmer.SwimmerId,FinalPlaceCAG.AgeGroup,FinalPlaceCAG.Rank,FinalPlaceCAG.ListOrder " .
				"ORDER BY Gender ASC,AgeGroupCAG ASC,ListOrder ASC";
	}
	return $query;
} # end of GetPlaceOrderedSwimmersQuery()




# ProcessHTMLTemplate - process the passed template by substituting macro values for the macro
#	names found in the template file.
#
# PASSED:
#	$templateFileName - the name of the file we need to process
#	$outputFH - File Handle of the output file we write to
#
# RETURNED:
#	n/a
#
# SIDE EFFECTS
#	The file pointed to by the global file handle GENERATEDFILE is written.
#
sub ProcessHTMLTemplate( $$ ) {
	my $templateFileName = $_[0];
	my $outputFH = $_[1];
	my $fd;
	open( $fd, "< $templateFileName" ) || die( "${appProgName}::ProcessHTMLTemplate():  Can't open $templateFileName: $!" );
	PMSMacros::SetTemplateName( $templateFileName );
	ProcessFile( $fd, $outputFH );
	close( $fd );
} # end of ProcessHTMLTemplate()



# ProcessFile - process the passed template file (does the work for ProcessHTMLTemplate() above.)
#
# PASSED:
#	$fd - handle to the template file
#	$outputFH - File Handle of the output file we write to
#
# RETURNED:
#	n/a
#
# SIDE EFFECTS:
#
sub ProcessFile( $$ ) {	
	my $fd = $_[0];
	my $outputFH = $_[1];
	my $line;
	my $lineNum = 0;
	
	while( ($line = <$fd>) ) {
		chomp $line;
		$lineNum++;
		$line = PMSMacros::ProcessMacros( $line, $lineNum );
		print $outputFH "$line\n";
	}
} # end of ProcessFile()

	
	
	
# PrintResultsExcel - generate the Excel file with our results.
#
# PASSED:
#	$workbook - a Excel::Writer::XLSX workbook.
#	$worksheet - a Excel::Writer::XLSX worksheet.
#	$workbookTopN, $worksheetTopN
#
#
# doc:  http://search.cpan.org/~jmcnamara/Excel-Writer-XLSX/lib/Excel/Writer/XLSX.pm
#
sub PrintResultsExcel($$$$$) {
	my ($workbook, $worksheet, $workbookTopN, $worksheetTopN, $splitAgeGroups) = @_;
	my( $firstName, $middleInitial, $lastName, $regNum );
	my $resultHash;
#	my $pointsRef = TT_Struct::GetPointsRef();
	my $query;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my ($sth, $rv);

	PMSLogging::PrintLog( "", "", "\n** Begin PrintResultsExcel (" . 
		($splitAgeGroups == 1 ? "Split Age Groups" : "Combine Age Groups") . ")", 1 );

	####
	#### READY TO PRINT THE TOP 'N' RESULTS
	####
	# title format for this excel file
	my $titleFormatTopN = $workbookTopN->add_format();		# initialize a null format
	$titleFormatTopN->set_size( 20 );
	$titleFormatTopN->set_center_across();
	# Next, some headings
	my $columnTopN = 0;
	my $rowTopN = 0;
	my $dataCellFormatTopN = $workbookTopN->add_format();				# format for (almost all) non-points data cells (not centered)
   	$dataCellFormatTopN->set_text_wrap();
	$worksheetTopN->merge_range( "A1:G2", "Pacific Masters Top $TOP_N_PLACES_TO_SHOW_EXCEL Swimmers for each Age Group for $yearBeingProcessed", $titleFormatTopN  );

	####
	#### READY TO PRINT THE TOP 10 RESULTS
	####
	# title format for this excel file
	my $titleFormat = $workbook->add_format();		# initialize a null format
	$titleFormat->set_size( 20 );
	$titleFormat->set_center_across();
	# Next, some headings
	my $column = 0;
	my $row = 0;
	my $format = $workbook->add_format();		# initialize a null default format
	my $LIGHT_YELLOW = '#FFF380';
	my $LIGHT_GRAY = '#D1D0CE';
	my $LIGHT_RED = '#FF99CC';
	my $LIGHT_BLUE = '#CCFFFF';
	
	my $dataCellFormat = $workbook->add_format();				# format for (almost all) non-points data cells (not centered)
	my $data1stFemaleCellFormat = $workbook->add_format();		# format for non-points data cells 1st place female
	my $data1stMaleCellFormat = $workbook->add_format();		# format for non-points data cells 1st place male
	my $pointsFormat = $workbook->add_format();					# for cells displaying points LABELS
	my $pointsDataFormat = $workbook->add_format();				# for cells displaying points DATA for all others
	my $pointsDataFormat1stFemale = $workbook->add_format();	# for cells displaying points DATA 1st place females
	my $pointsDataFormat1stMale = $workbook->add_format();		# for cells displaying points DATA 1st place males
    $worksheet->set_landscape();    # Landscape mode when printing
    $worksheet->repeat_rows( 7 ); 	# top of each printed page past 1st page will have the column headings
    $worksheet->hide_gridlines(0);	# don't hide gridlines on screen or printed paper
   	$format->set_text_wrap();
   	$dataCellFormat->set_text_wrap();
   	$data1stFemaleCellFormat->set_text_wrap();
   	$data1stFemaleCellFormat->set_bg_color( $LIGHT_RED );		
   	$data1stMaleCellFormat->set_text_wrap();
   	$data1stMaleCellFormat->set_bg_color( $LIGHT_BLUE );	
   	$pointsFormat->set_text_wrap();
   	$pointsFormat->set_align( 'center' );
   	$pointsDataFormat1stFemale->set_text_wrap();
   	$pointsDataFormat->set_text_wrap();
   	$pointsDataFormat1stFemale->set_align( 'center' );
   	$pointsDataFormat1stMale->set_align( 'center' );
   	$pointsDataFormat1stFemale->set_bg_color( $LIGHT_RED );		# 
   	$pointsDataFormat1stMale->set_text_wrap();
   	$pointsDataFormat1stMale->set_bg_color( $LIGHT_BLUE );			# 
   	$pointsDataFormat->set_align( 'center' );

	$worksheet->merge_range( "A1:S2", "Pacific Masters Top 10 Swimmers of the Year for $yearBeingProcessed", $titleFormat  );
	$row++;
	my $subTitleFormat = $workbook->add_format();		# initialize a null format
	$subTitleFormat->set_size( 10 );
	$subTitleFormat->set_center_across();
	$worksheet->merge_range( "A3:S3", "Generated on $generationTimeDate by BUp", $subTitleFormat  );
	$row++;

	# now display the top point-winning Swimmers of the Year:
	my $SOTY_TitleFormatF = $workbook->add_format();	
	$SOTY_TitleFormatF->set_size(14);
	$SOTY_TitleFormatF->set_bold();
	$SOTY_TitleFormatF->set_color( 'pink' );
	$worksheet->merge_range( "A4:C4", "Female with the most points:", $SOTY_TitleFormatF  );
	$row = 3;
	$column = 4;
	my $formatTotalPoints = $workbook->add_format();
	my $minSwimMeetsFlag;

	# work on the top females first:
	$sth = ComputeTopPoints( 'F', $splitAgeGroups );
	my $previousPoints = -1;
	my $numTopPoints=0;
	while( $numTopPoints <= $TT_Struct::NumHighPoints ) {
		my $resultHash = $sth->fetchrow_hashref;
		if( !defined $resultHash ) {
			PMSLogging::DumpError( "", "", "PrintResultsExcel(): Ran out of top female point getters!", 1 );
			last;
		}
		my $firstName = $resultHash->{"FirstName"};
		my $middleInitial = $resultHash->{"MiddleInitial"};
		my $lastName = $resultHash->{"LastName"};
		my $totalPoints = $resultHash->{"TotalPoints"};
		my $ageGroup = $resultHash->{'AgeGroup'};
		my $swimmerId = $resultHash->{'SwimmerId'};
		# get points for this swimmer:
		my ( $countPoints, $countPMSPoints, $countHidden, $countPMSHidden) = GetSwimmerMeetDetails($swimmerId);

		$numTopPoints++ if( $previousPoints != $totalPoints );
		$previousPoints = $totalPoints;
		if( $numTopPoints <= $TT_Struct::NumHighPoints ) {
			$worksheet->write( $row, $column++, $firstName, $SOTY_TitleFormatF );
			$worksheet->write( $row, $column++, $middleInitial, $SOTY_TitleFormatF );
			$worksheet->write( $row, $column++, $lastName, $SOTY_TitleFormatF );
			$column++;
			if( $trackPMSSwims && 
				(($countPMSPoints + $countPMSHidden) < $minMeetsForConsideration) && 
				($mysqlDate ge $dateToStartTrackingPMSMeets) ) {
				$minSwimMeetsFlag = "*";
			} else {
				$minSwimMeetsFlag = "";
			}
			$worksheet->write( $row, $column++, "(".$totalPoints.")$minSwimMeetsFlag", 
				$formatTotalPoints );
			$worksheet->write( $row, $column++, "PAC: $countPMSPoints" . "+" . $countPMSHidden, $formatTotalPoints ) 
				if( $trackPMSSwims );
			$row++;
			$column = 4;
		}
	}
	print( "  - There were $numTopPoints female top point-winning swimmers of the year\n" );

	# next, work on the top males:
	my $SOTY_TitleFormatM = $workbook->add_format();	
	$SOTY_TitleFormatM->set_size(14);
	$SOTY_TitleFormatM->set_bold();
	$SOTY_TitleFormatM->set_color( 'blue' );
	$worksheet->merge_range( "A".($row+1).":C".($row+1), "Male with the most points:", $SOTY_TitleFormatM  );
	$column = 4;
	$sth = ComputeTopPoints( 'M', $splitAgeGroups );
	$previousPoints = -1;
	$numTopPoints=0;
	while( $numTopPoints <= $TT_Struct::NumHighPoints ) {
		my $resultHash = $sth->fetchrow_hashref;
		if( !defined $resultHash ) {
			PMSLogging::DumpError( "", "", "PrintResultsExcel(): Ran out of top male point getters!", 1 );
			last;
		}
		my $firstName = $resultHash->{"FirstName"};
		my $middleInitial = $resultHash->{"MiddleInitial"};
		my $lastName = $resultHash->{"LastName"};
		my $totalPoints = $resultHash->{"TotalPoints"};
		my $ageGroup = $resultHash->{'AgeGroup'};
		my $swimmerId = $resultHash->{'SwimmerId'};
		# get points for this swimmer:
		my ( $countPoints, $countPMSPoints, $countHidden, $countPMSHidden) = GetSwimmerMeetDetails($swimmerId);

		$numTopPoints++ if( $previousPoints != $totalPoints );
		$previousPoints = $totalPoints;
		if( $numTopPoints <= $TT_Struct::NumHighPoints ) {
			$worksheet->write( $row, $column++, $firstName, $SOTY_TitleFormatM );
			$worksheet->write( $row, $column++, $middleInitial, $SOTY_TitleFormatM );
			$worksheet->write( $row, $column++, $lastName, $SOTY_TitleFormatM );
			$column++;
			if( $trackPMSSwims && 
				(($countPMSPoints + $countPMSHidden) < $minMeetsForConsideration) && 
				($mysqlDate ge $dateToStartTrackingPMSMeets) ) {
				$minSwimMeetsFlag = "*";
			} else {
				$minSwimMeetsFlag = "";
			}
			$worksheet->write( $row, $column++, "(".$totalPoints.")$minSwimMeetsFlag", 
				$formatTotalPoints );
			$worksheet->write( $row, $column++, "PAC: $countPMSPoints" . "+" . $countPMSHidden, $formatTotalPoints ) 
				if( $trackPMSSwims );
			$row++;
			$column = 4;
		}
		
	}
	print( "  - There were $numTopPoints male top point-winning swimmers of the year\n" );

	# show a key to our display
	if(1 && ($mysqlDate ge $dateToStartTrackingPMSMeets)) {
		my $formatKeyTitle = $workbook->add_format();
		$formatKeyTitle->set_size(14);
		$formatKeyTitle->set_bold();
	   	$formatKeyTitle->set_text_wrap();
		$worksheet->merge_range( "K4:M4", "Key for table below:", $formatKeyTitle );
		
		my $formatKey = $workbook->add_format();
	   	$formatKey->set_text_wrap();
	   	$formatKey->set_align( 'left' );
	   	$formatKey->set_align( 'top' );
		$worksheet->merge_range( "K5:S6", "* indicates a swimmer who has not swum the " .
			"minimum number of events to be considered for Top 10.", $formatKey );
	
	}

	# now for the complete list of swimmers and their points
	$row += 2;
	$worksheet->freeze_panes( $row+1, 0 );

	# print the heading line in the generated top N result file:
	$columnTopN = 0;
	$rowTopN+=3;		# blank lines between title and heading line
	$worksheetTopN->freeze_panes( $rowTopN+1, 0 );
	$worksheetTopN->set_column( 0, 18, 15 );
	$worksheetTopN->write( $rowTopN, $columnTopN++, "Gender:AG", $dataCellFormatTopN );
	$worksheetTopN->set_column( 1, 1, 8 );
	$worksheetTopN->write( $rowTopN, $columnTopN++, "Rank", $dataCellFormatTopN );
	$worksheetTopN->set_column( 2, 2, 20 );
	$worksheetTopN->write( $rowTopN, $columnTopN++, "First Name", $dataCellFormatTopN );
	$worksheetTopN->set_column( 3, 3, 5 );
	$worksheetTopN->write( $rowTopN, $columnTopN++, "MI", $dataCellFormatTopN );
	$worksheetTopN->set_column( 4, 4, 20 );
	$worksheetTopN->write( $rowTopN, $columnTopN++, "Last Name", $dataCellFormatTopN );
	$worksheetTopN->write( $rowTopN, $columnTopN++, "# PAC Swims", $dataCellFormatTopN );
	$rowTopN++;


	# print the heading line in the generated top 10 result file:
	$column = 0;
	$worksheet->set_column( 0, 18, 10 );
	$worksheet->write( $row, $column++, "Gender:AG\nor Rank", $format );
	$worksheet->set_column( 1, 1, 11 );
	$worksheet->write( $row, $column++, "RegNum\n(team)", $format );
	$worksheet->write( $row, $column++, "First Name", $format );
	$worksheet->set_column( 3, 3, 3 );
	$worksheet->write( $row, $column++, "MI", $format );
	$worksheet->write( $row, $column++, "Last Name", $format );
	
	$worksheet->set_column( 5, 8, 8 );
	$worksheet->set_column( 9, 11, 10 );		# wrap
	$worksheet->set_column( 12, 14, 9 );
	$worksheet->set_column( 15, 17, 10 );		# wrap
	$worksheet->set_column( 18, 18, 10 );
	foreach my $org( @PMSConstants::arrOfOrg ) {
		foreach my $course( @PMSConstants::arrOfCourse ) {
			my $heading;
			# there is no such thing as "USMS-OW"
			next if( ($org eq "USMS") && ($course eq "OW") );
			# ugh!  special case for special formatting...
			if( $course =~ m/Record/ ) {
				$heading = "$org\n$course";
			} else {
				$heading = "$org $course";
			}
			$worksheet->write( $row, $column++, $heading, $pointsFormat );
		}
	}
	$worksheet->write( $row, $column++, "Total Points", $pointsFormat );
	$worksheet->write( $row, $column++, "# PAC Swims", $pointsFormat ) if( $trackPMSSwims );

	# Since we have already computed the points and places for every swimmer we are going to 
	# print them out in order of gender and age group, ordered highest to lowest points 
	# (lowest to highest place) for each gender / age group:
	# The query we use to get the place for every swimmer depends on what rule we're following:
	# are we considering a swimmer with a split age group as two swimmers (one in each age group)
	# or are we combining the two age groups, thus the swimmer is placed in the older age group?
	# The passed $splitAgeGroups tells us what to do:
	$query = GetPlaceOrderedSwimmersQuery( $splitAgeGroups );
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	# we've got the list of swimmers in order of:
	#   Gender   AgeGroup   ListOrder
	my $previousGenderAgegroup = "";
	my $previousGender = "";
	my $numSwimmersSeenSoFar = 0;
	#
	my $topN_NumRowsInGenderAgegroup;		# number of rows (1 - K) in the top N file for current
	# gender age group.  If there are no ties, then K will be 'N', i.e. $TOP_N_PLACES_TO_SHOW_EXCEL (e.g. '3')
	# but this may not include the top '3' point earners, because one (or more) may not have swum
	# the minimum number of PAC meets.  If there are ties K could be larger (if the tie includes what
	# would be the 'N' row and one or more following)
	my $topN_LastPlaceWritten = 0;			# The rank of the swimmer last written to the topN file.
		# Used to recognize a tie allowing us to write more than 
		# $TOP_N_PLACES_TO_SHOW_EXCEL (e.g. '3') rows when the tie occurs with would would normally
		# be with the last row and the one (or more) following.
	# pass through the list in order of gender, agegroup, and list order:
	while( defined(my $resultHash = $sth->fetchrow_hashref) ) {
			my $firstName = $resultHash->{'FirstName'};
			my $middleInitial = $resultHash->{'MiddleInitial'};
			my $lastName = $resultHash->{'LastName'};
			my $team = $resultHash->{'RegisteredTeamInitials'};
			my $ageGroup = $resultHash->{'AgeGroup'};
			my $rank = $resultHash->{'Rank'};
			my $points = $resultHash->{'Points'};
			my $listOrder = $resultHash->{'ListOrder'};
			my $ageGroupCAG = $resultHash->{'AgeGroupCAG'};
			my $gender = $resultHash->{'Gender'};
			my $swimmerId = $resultHash->{'SwimmerId'};
			my $regNum = $resultHash->{'RegNum'};
			my $thisGenderAgegroup = "$gender:$ageGroupCAG";

			$row++;
			$column = 0;
			### we need to do some reference magic here to easily use the correct format for the row
			### we're about to write out:
			my $pointsDataFormatRef = \$pointsDataFormat;
			my $dataCellFormatRef =  \$dataCellFormat;
			# are we starting a new gender and/or age group?
			if( $previousGenderAgegroup ne $thisGenderAgegroup ) {
				# YES - new gender/age group.
				# Display gender:age group since it's the first time for this gender/age group:
				#... topN sheet:
				$topN_NumRowsInGenderAgegroup = 0;
				$topN_LastPlaceWritten = 0;		# bogus rank:  we haven't written any rows for this gender/age group yet
				$columnTopN = 0;
				$rowTopN++;		# blank line between different gender/age groups
				$worksheetTopN->write( $rowTopN, $columnTopN++, $thisGenderAgegroup, $dataCellFormatTopN );
				#... full sheet:
				$row++;		# blank line between different gender/age groups
				$worksheet->write( $row, $column++, $thisGenderAgegroup, $$dataCellFormatRef );
				### a little logging to stdout to keep us informed...
				if( $previousGender eq "" ) {
					$previousGender = $gender;
					print "  ...";
				} elsif( $previousGender ne $gender ) {
					print "\n  ...";
					$previousGender = $gender;
				}
				print " $thisGenderAgegroup";
				###
			} else {
				#... full sheet:
				$worksheet->write( $row, $column++, "# $rank", $$dataCellFormatRef );
			}
				
			# increment the number of swimmers we've seen in this gender/age group so far:
			$numSwimmersSeenSoFar++;
			# if this is the first place swimmer in this gender / age group then color their row
			# top female:  light yellow
			# top male: light gray
			if( $rank == 1 ) {
				if( $gender eq 'M' ) {
					$pointsDataFormatRef = \$pointsDataFormat1stMale;
					$dataCellFormatRef =  \$data1stMaleCellFormat;
				} else {
					$pointsDataFormatRef = \$pointsDataFormat1stFemale;
					$dataCellFormatRef =  \$data1stFemaleCellFormat;
				}
			}
			
			# get points for this swimmer:
			my ( $countPoints, $countPMSPoints, $countHidden, $countPMSHidden) = GetSwimmerMeetDetails($swimmerId);
			# if this swimmer swam less than $minMeetsForConsideration meets then we'll flag them
			if( $trackPMSSwims && 
				(($countPMSPoints+$countPMSHidden) < $minMeetsForConsideration) && 
				($mysqlDate ge $dateToStartTrackingPMSMeets) ) {
				$minSwimMeetsFlag = "*";
			} else {
				$minSwimMeetsFlag = "";
			}

			if( $rank == 1 ) {
				$worksheet->write( $row, $column++, "$regNum\n($team)", $$dataCellFormatRef );
			} else {
				$worksheet->write( $row, $column++, $regNum, $$dataCellFormatRef );
			}
			$worksheet->write( $row, $column++, "$minSwimMeetsFlag$firstName", $$dataCellFormatRef );
			$worksheet->write( $row, $column++, $middleInitial, $$dataCellFormatRef );
			$worksheet->write( $row, $column++, $lastName, $$dataCellFormatRef );


			# do we write out a row in our top 'N' excel file?  Yes if we haven't written out
			# 'N' (or more in case of ties) rows for the current gender/age group AND if 
			# we have a row that represents a swimmer who has swum at least $minMeetsForConsideration
			# PAC meets:
			if( (($rank == $topN_LastPlaceWritten) ||
				($topN_NumRowsInGenderAgegroup < $TOP_N_PLACES_TO_SHOW_EXCEL)) &&
				(($countPMSPoints+$countPMSHidden) >= $minMeetsForConsideration) ) {
				# this swimmer is a top 'N' swimmer in their age group
				# add this swimmer to the top 'N' excel file
				$worksheetTopN->write( $rowTopN, $columnTopN++, "# $rank", $dataCellFormatTopN );
				$worksheetTopN->write( $rowTopN, $columnTopN++, $firstName, $dataCellFormatTopN );
				$worksheetTopN->write( $rowTopN, $columnTopN++, $middleInitial, $dataCellFormatTopN );
				$worksheetTopN->write( $rowTopN, $columnTopN++, $lastName, $dataCellFormatTopN );
				$worksheetTopN->write( $rowTopN, $columnTopN++, $countPMSPoints . "+" . $countPMSHidden, $dataCellFormatTopN );
				# increment the number of rows we've added to the top 'N' file for this
				# gender/age group.  We stop when we've written out the max for the age group AND
				# there are no more ties with would would have been the last row.
				$topN_NumRowsInGenderAgegroup++;
				$topN_LastPlaceWritten = $rank;
				$rowTopN++;
				$columnTopN = 1;
			}

			$previousGenderAgegroup = $thisGenderAgegroup;

			foreach my $org( @PMSConstants::arrOfOrg ) {
				foreach my $course( @PMSConstants::arrOfCourse ) {
					# there is no such thing as "USMS-OW"
					next if( ($org eq "USMS") && ($course eq "OW") );
					my( $detailsNum, $pointsForThisOrgCourse, $resultsCounted, $resultsAnalyzed );


					# if we did NOT read any results for this org and course then we set
					# the value for this swimmer to '-' (should never happen when we've
					# got all the data.)  Otherwise if we don't have a defined value
					# for this org-course for this swimmer we set the value to 0.
					if( $missingResults{"$org-$course"} ) {
						$pointsForThisOrgCourse = "-";
					} else {
						( $detailsNum, $pointsForThisOrgCourse, $resultsCounted ) = 
							TT_MySqlSupport::GetSwimmersSwimDetails2( $swimmerId, $org, $course, $ageGroup );
					}
					$worksheet->write( $row, $column++, $pointsForThisOrgCourse, $$pointsDataFormatRef );
				}
			}
			# write out the total points for this swimmer, along with the "not enough events" flag
			$worksheet->write( $row, $column++, "$minSwimMeetsFlag$points$minSwimMeetsFlag", 
				$$pointsDataFormatRef );
			$worksheet->write( $row, $column++, $countPMSPoints . "+" . $countPMSHidden, $$pointsDataFormatRef );			
		} # end of while( defined(my $resultHash....


	$row += 5;
	# now for more details
	$worksheet->merge_range( "A$row:M$row", "List of results processed:", $format );
	$row++;
	my $meetList = "";
	my ($statementHandle, $numPoolMeets, $numOWMeets, $numPMSMeets) = TT_MySqlSupport::GetListOfMeets( );
	my $meetCount = 0;
	while( defined(my $resultHash = $statementHandle->fetchrow_hashref) ) {
		$meetCount++;
		$meetList .= "    $meetCount:   " . $resultHash->{'MeetTitle'} . "\n";
	}
	my $row2 = $row+$meetCount;
	$worksheet->merge_range( "A$row:M$row2", $meetList, $format );
	
	my($num, $numWithPoints) = TT_MySqlSupport::GetNumberOfSwimmers();
	$row = $row2+1;
	$worksheet->merge_range( "A$row:M$row", "Number of Competing Swimmers:  $num", $format );
	$row++;
	$worksheet->merge_range( "A$row:M$row", "Number of Swimmers who earned points:  $numWithPoints", $format );
	
	$workbook->close();
	$workbookTopN->close();

	PMSLogging::PrintLog( "", "", "\n** End PrintResultsExcel (" . 
		($splitAgeGroups == 1 ? "Split Age Groups" : "Combine Age Groups") . ")", 1 );

} # end of PrintResultsExcel()


# my ( $countPoints, $countPMSPoints, $countHidden, $countPMSHidden) = GetSwimmerMeetDetails($swimmerId);
# GetSwimmerMeetDetails - get details on the number of meets this swimmer swam in.
#
# PASSED:
#	$swimmerId - the swimmerID of the passed swimmer.
#
# RETURNED:
#	$countPoints - the count of the number of meets (includes OW events) this swimmer has earned points in
#	$countPMSPoints - the number of PMS sanctioned meets earning points (includes OW events earning points)
#	$countHidden - the number of POOL meets USMS says this swimmer has swum in but we didn't
#		detect when processing results.
#	$countPMSHidden - the number of PMS sanctioned POOL meets USMS says this swimmer has swum in but we didn't
#		detect when processing results.
#
# DEFINE "earned points" - points earned due to a time in the top 8 or 10 or whatever.  HOWEVER, the swimmer
#	will not necessarily be AWARDED those points if they have already been awarded their limit of places.
#
my %GotUSMSDirectoryInfo;		# $GotUSMSDirectoryInfo{swimmerid} = 1 if we have the info already
sub GetSwimmerMeetDetails( $ ) {
	my $swimmerId = $_[0];
	my $countPoints = 0;		# the number of meets (includes OW events) this swimmer has earned points in
	my $countPMSPoints = 0;		# the number of PMS sanctioned meets earning points (includes OW events earning points)
	my $countHidden = 0;		# the number of POOL meets USMS says this swimmer has swum in but we didn't
								# detect when processing results.
	my $countPMSHidden = 0;		# the number of PMS sanctioned POOL meets USMS says this swimmer has swum in but we didn't
								# detect when processing results.
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $debug = 0;
	my $resultHash;
	my ($sth, $rv);
	my $query;
	my %listOfPointMeets;
		
	if( ! defined( $GotUSMSDirectoryInfo{$swimmerId} ) )  {
		# dig into this swimmer's USMS Directory looking for hidden meets:
		TT_USMSDirectory::GetUSMSDirectoryInfo( $swimmerId );
		$GotUSMSDirectoryInfo{$swimmerId} = 1;
		if(0) {
			$query = "UPDATE Swimmer SET GotUSMSDirectoryInfo = 1 WHERE SwimmerId = $swimmerId";
			my $rowsAffected = $dbh->do( $query );
			if( $rowsAffected == 0 ) {
				# update failed - 
				PMSLogging::DumpError( "", "", "Topten::GetSwimmerMeetDetails(): Update of Swimmer $swimmerId failed!!", 1 ) if( $debug > 0);
			}
		}
	}
		
	# get the list of different meets this swimmer earned points in (each OW event is a "swim meet")
	# and count the number of such meets and such meets sanctioned by PMS.
	$query = "SELECT DISTINCT(Splash.MeetId),Meet.MeetIsPMS FROM Splash JOIN Meet " .
				"WHERE Splash.MeetId != 1 " .
				"AND Splash.MeetId = Meet.MeetId " .
				"AND SwimmerId = \"$swimmerId\"";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$countPoints=0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $meetId = $resultHash->{'MeetId'};
		my $isPMS = $resultHash->{'MeetIsPMS'};
		$listOfPointMeets{$meetId} = 1;
		$countPoints++;
		$countPMSPoints++ if( $isPMS );
	}
					
	# do we have pool swim meet details from the USMS Membership Directory?
	$query = "SELECT USMSDirectory.MeetId,Meet.MeetIsPMS FROM USMSDirectory JOIN Meet " .
				"WHERE Meet.MeetId = USMSDirectory.MeetId " .
				"AND SwimmerId = \"$swimmerId\"";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	$countHidden = 0;
	$countPMSHidden = 0;
	while( defined($resultHash = $sth->fetchrow_hashref) ) {
		my $meetId = $resultHash->{'MeetId'};
		my $isPMS = $resultHash->{'MeetIsPMS'};
		if( !defined( $listOfPointMeets{$meetId} ) ) {
			# this meet earned no points so we don't know about it except thru USMS
			$countHidden++;
			$countPMSHidden++ if( $isPMS );
		}
	}
	
	if( $countHidden || $countPMSHidden ) {
		PMSLogging::PrintLog( "", "", "Topten::GetSwimmerMeetDetails(): SwimmerId $swimmerId: " .
			"countPoints=$countPoints and countHidden=$countHidden, " .
			"countPMSPoints=$countPMSPoints and countPMSHidden=$countPMSHidden", 1 ) if( $debug > 0);
	}
	
	return ( $countPoints, $countPMSPoints, $countHidden, $countPMSHidden);

} # end of GetSwimmerMeetDetails





###################################################################################
#### SUPPORT ######################################################################
###################################################################################



# PlaceToPoints - convert the passed place (1-N) into points.
#
# PASSED:
#	$org - either PMS or USMS.  Used to determine the max place we'll consider:
#			PMS:  1-3
#			USMS: 1-10
#		Also used to determine the number of points per place
#$ranke - the place used to determine the number of points	
#	
#
sub PlaceToPoints_old($$) {
	my $org = $_[0];
	my $place = $_[1];
	my $result = 0;
	my @points = (0,10,8,6);		# assume PMS
	my $maxPlace = 3;
	if( $org eq "USMS" ) {
		@points = (0,20,18,16,14,12,10,8,6,4,2);
		$maxPlace = 10;
	}
	if( ($place >= 1) || ($place <= $maxPlace) ) {
		$result = $points[$place];
	}
	return $result;
} # end of PlaceToPoints()



#		if( ! ValidateAge( $age, $ageGroup ) ) 
# ValidateAge - return true if the passed age is contained in the passed ageGroup.  False otherwise.
#	The passed ageGroup is of the form '95-99'
#
# PASSED:
#	$age - the age we are going to compare with an age group
#	$ageGroup - the age group
#
# RETURNED:
#	$result = 1 if the age is inside the age group, 0 if not.
#
sub ValidateAge($$) {
	my ($age, $ageGroup) = @_;
	my $result = 0;				# assume the worse
	$ageGroup =~ m/^(\d+)-(\d+)$/;
	my $lowerAge = $1;
	my $upperAge = $2;
	if( ($lowerAge eq "") || ($upperAge eq "") ||
		($lowerAge >= $upperAge) || 
		(($lowerAge == 18)&&($upperAge != 24)) ||
		(($lowerAge > 18)&&(($lowerAge+5)<$upperAge)) ) {
		PMSLogging::PrintLog( "", "", "Invalid ageGroup passed to ValidateAge():  '$ageGroup' (lowerAge=$lowerAge, " .
			"upperAge=$upperAge)", 1 );
	}
		
	$result = 1 if( ($lowerAge <= $age) && ($upperAge >= $age) );
} # end of ValidateAge()


# GetSwimmerDetailsFromPMS_DB - get swimmer name and team from RSIDN file
#
# PASSED:
#	$fileName - the file we're currently processing (used in error messages) (not used)
#	$lineNum - the line being processed (used in error messages) (not used)
#	$regNum - the key used to look up the swimmer
#	$fatalMsg - the error message we'll use if error (used in error messages) (not used)
#
# RETURNED:
#	$firstName -
#	$middleInitial -
#	$lastName -
#	$team -
#
sub GetSwimmerDetailsFromPMS_DB($$$$) {
	my $fileName = $_[0];
	my $lineNum = $_[1];
	my $regNum = $_[2];
	my $fatalMsg = $_[3];
	my $firstName = "";
	my $middleInitial = "";
	my $lastName = "";
	my $team = "";
	my $resultHash;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	
	# Get the USMS Swimmer id, e.g. regnum 384x-abcde gives us 'abcde'
	my $regNumRt = PMSUtil::GetUSMSSwimmerIdFromRegNum( $regNum );

	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"SELECT FirstName,MiddleInitial,LastName,RegisteredTeamInitialsStr FROM RSIDN_$yearBeingProcessed " .
	#	"WHERE RegNum = \"$regNum\"" );
		"WHERE RegNum LIKE \"38%-$regNumRt\"" );
		
	if( defined($resultHash = $sth->fetchrow_hashref) ) {
		# this swimmer exists in our RSIDN file - get the particulars
		$firstName = $resultHash->{'FirstName'};
		$middleInitial = $resultHash->{'MiddleInitial'};
		$lastName = $resultHash->{'LastName'};
		$team = $resultHash->{'RegisteredTeamInitialsStr'};
	} else {
		# regnum not found = return "" for the firstName
	}
		
	return( $firstName, $middleInitial, $lastName,$team);
} # end of GetSwimmerDetailsFromPMS_DB()






# InitializeMissingResults - initialize the %missingResults hash to the state that implies that
#	we haven't found any result files.
#
sub InitializeMissingResults() {
	foreach my $org( @PMSConstants::arrOfOrg ) {
		foreach my $course( @PMSConstants::arrOfCourse ) {
			my $pointsHashKey = "$org-$course";
			$missingResults{$pointsHashKey} = 1;
		}
	}

} # end of InitializeMissingResults()



# end of Topten.pl

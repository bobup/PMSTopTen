#!/usr/bin/perl -w
# TT_MySqlSupport.pm - support routines and values used by the MySQL based code.
#
# Copyright (c) 2017 Bob Upshaw.  This software is covered under the Open Source MIT License 

package TT_MySqlSupport;

use strict;
use sigtrap;
use warnings;

use DBI;
#use Data::Dumper;

use FindBin;
use File::Spec;
use File::Basename;
use lib File::Spec->catdir( $FindBin::Bin, '..',  '..', 'PMSPerlModules' );
require PMSUtil;
require PMS_MySqlSupport;
require PMSLogging;
require PMSStruct;
require PMS_ImportPMSData;

# keep track of the number of swimmers who are split across two different age groups:
my $total2AgeGroups = 0;

# define the MeetId of a default meet inserted in the Meet table when the table is created.
# We'll use this meet as the meet where points were earned if we don't have any other meet to
# record. 
our $DEFAULT_MISSING_MEET_ID = 1;



# list of tables that we expect in our db:
my $ttTableListInitialized = 0;		# set to 1 when we've initialized the %tableList with existing tables
my %ttTableList = (
	'Meta' => 0,
	'Splash' => 0,
	'Event' => 0,
	'Points' => 0,
	'FinalPlaceSAG' => 0,
	'FinalPlaceCAG' => 0,
	'Swimmer' => 0,
	'NumSwimmers' => 0,
	'Meet' => 0,
	'FetchStats' => 0,
	'USMSDirectory' => 0,
	'PMSTeams' => 0,
	# results tables:
	'FetchStats' => 0,
);
# list of tables that we never drop - in order to regenerate them they must be dropped by hand.
my @ttTableListNotDropped = (
	"Meta",
	"RSIDN_.*\$",
	'PMSTeams' => 0,
	# results tables are never automatically dropped:
	'FetchStats',
	);


# We'll use this hash to keep track of all swimmer's full names that we can't find in the RSIDN table.
#	$UnableToFindInRSIDN{"$fullName"} = # times the swimmer with full name
#		$fullName was seen in the results.
#	$UnableToFindInRSIDN{"$fullName":OrgCourse} = a list of 1 or more "$org:$course" strings which
#		denote the result file we can find this swimmer in.
my %UnableToFindInRSIDN = ();


# We'll use this hash to keep track of all swimmer's full names that we can't find in the RSIDN table BUT
# for which this is only a WARNING:
#	$UnableToFindInRSIDN_WARNING{"$fullName"} = # times the swimmer with full name
#		$fullName was seen in the results.
#	$UnableToFindInRSIDN_WARNING{"$fullName":OrgCourse} = a list of 1 or more "$org:$course" strings which
#		denote the result file we can find this swimmer in.
my %UnableToFindInRSIDN_WARNING = ();

# We'll use this hash to keep track of all swimmer's full names that occur in results and also more 
#	than once in the RSIDN table.  This is a problem because we don't know exactly who to give
#	points to if the results identify the swimmer by name only:
#	$DuplicateNames{"$fullName"} = # times the swimmer with full name
#		$fullName was seen in the results.
#	$DuplicateNames{"$fullName":OrgCourse} = a list of 1 or more "$org:$course" strings which
#		denote the result file we can find this swimmer in.
my %DuplicateNames = ();

# We'll use this hash to keep track of all swimmer's full names that occur more than once 
# in the RSIDN table but we dis-ambiguate using their DOB and team:
#	$DuplicateNamesCorrected{"$fullName"} = # times the swimmer with full name
#		$fullName was seen in the results.
#	$DuplicateNamesCorrected{"$fullName":OrgCourse} = a list of 1 or more "$org:$course" strings which
#		denote the result file we can find this swimmer in.
my %DuplicateNamesCorrected = ();

# We'll use this hash to keep track of all swimmers who belong to two age groups for the season
#	$MultiAgeGroups{$swimmerId} = ageGroup1:ageGroup2:gender;		# e.g. "25-29:30-34:M"
#	$MultiAgeGroups{$swimmerId-$ag1-points} = points for this age group, where $ag1 is one of their age groups;
#	$MultiAgeGroups{$swimmerId-$ag2-points} = points for this age group, where $ag2 is the other of their age groups;
#	$MultiAgeGroups{$swimmerId-$ag1-place} = place for this age group, where $ag1 is one of their age groups;
#	$MultiAgeGroups{$swimmerId-$ag2-place} = place for this age group, where $ag2 is the other of their age groups;
#	$MultiAgeGroups{$swimmerId-combined-points} = points for this swimmer if we combine points for both age groups.
#	$MultiAgeGroups{$swimmerId-combined-place} = place for this swimmer if we combine points for both age groups.
my %MultiAgeGroups = ();

sub GetMultiAgeGroupsRef() {
	return \%MultiAgeGroups;
}
#***************************************************************************************************
#****************************** Top Ten MySql Support Routines *************************************
#***************************************************************************************************

#*******





# InitializeTopTenDB - get handle to our db; create tables if they are not there.
#
# Call this before trying to use the database.
# Before calling this be sure to drop any tables you'd want created fresh before a run, and
#	call PMS_MySqlSupport::SetSqlParameters() to establish the database parameters.
#
sub InitializeTopTenDB() {
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $sth;
	my $rv;
	my $yearBeingProcessed = PMSStruct::GetMacrosRef()->{"YearBeingProcessed"};
	my $xxx = $PMSConstants::MAX_LENGTH_TEAM_ABBREVIATION;		# avoid compiler warning
	
	if( $dbh ) {
		# get our database parameters
		PMS_MySqlSupport::GetTableList( \%ttTableList, \$ttTableListInitialized );
    	foreach my $tableName (keys %ttTableList) {
    		if( ! $ttTableList{$tableName} ) {
    			print "Table '$tableName' does not exist - creating it.\n";

### Meta
    			if( $tableName eq "Meta" ) {
    				# --- RSIDNFileName : simple name of the file from which the RSIDN table was populated
		    		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
    		    		"CREATE TABLE Meta (MetaId INT AUTO_INCREMENT PRIMARY KEY, " .
    		    		"Year Char(4), " .
    		    		"RSIDNFileName Varchar(255) DEFAULT '(none)', " .
    		    		"TeamsFileName Varchar(255) DEFAULT '(none)', " .
    		    		"MergedMemberFileName Varchar(255) DEFAULT '(none)')" );
    		
### Splash
    			} elsif( $tableName eq "Splash" ) {
    				### Used to record every splash (swim swum by a recognized PMS swimmer)
    				# Note that we record EVERY splash of a PMS swimmer, even those that
    				# do not earn points, and even those splashes whose points will not
    				# be used in top 10 calculations.  
    				# Note that a single swim can be represented in the table up to 4 times:
    				#	- where the Course is one of SCY, SCM, or LCM and the Org is PAC.  This is the case
    				#		where the swim was a top 'N' swim for that course in Pacific Masters.
    				#	- where the Course is one of SCY, SCM, or LCM and the Org is USMS.  This is the case
    				#		where the swim was a top 'N' swim for that course in USMS.
    				#	- where the Course is one of SCY Records, SCM Records, or LCM Records and the Org is PAC.
    				#		This is the case where the swim is a PAC record in that course.
    				#	- where the Course is one of SCY Records, SCM Records, or LCM Records and the Org is USMS.
    				#		This is the case where the swim is a USMS record in that course.
    				#	- where the Course is ePostal and the Org is USMS.
    				#		This is the case where the swim is a USMS ePostal swim.
    				# In most cases (there has been one exception that I know about) if a single swim sets a USMS
    				# record that swim will be a top PAC swim, a top USMS swim, and a PAC record.  Thus that swim
    				# will be represented by 4 rows in this table.
					# We'll then analyze all of these splashes to populate the Points table.
    				# --- SplashId : primary key
    				# --- Course : one of SCY, SCM, LCM, SCY Records, SCM Records, LCM Records, OW, or ePostal
    				#		- SCY, SCM, LCM:  this represents the swim in that length of pool
    				#		- SCY Records, SCM Records, LCM Records: this represents the swim that set a record.
    				#			Obviously, such a swim has another record in this table with the Course of
    				#			SCY, SCM, or LCM as appropriate.  See the Note above.
    				#		- OW: this represents an OW swim.
    				#		- ePostal: this represents an ePostal swim
    				# --- Org : orginazation, one of PAC or USMS
    				#		- PAC: this represents a top 'N' Pacific Masters swim.  Also includes open water swims.
    				#		- USMS: this represents a top 'N' USMS swim.  Obviously if a swim is represented as a
    				#			USMS swim in this table there is another row for that same swim representating 
    				#			a PAC swim. Also included ePostal swims.
    				# --- EventId : reference to the exact event (e.g. '50 y freestyle') 
    				# --- Gender - one of M or F
				  	# --- AgeGroup - their age group on the day of the swim, of the form 18-24, 25-29, etc.
    				# --- Category : 1 or 2 (but only splashes of cat 1 earn AGSOTY points)
    				# --- View : link to results containing this event (not supplied)
    				# --- Date : the date of this swim (not always supplied)
    				# --- MeetId : references the meet in which this swim was swum (if not known it will be 0)
    				# --- SwimmerId - the swimmer who swam this swim
    				# --- Duration - the time of the swim in hundredths of a second, or the distance for an
    				#		ePostal set time swim, depending on DurationType
    				# --- DurationType - 1 if the above Duration is time (hundredths of a second), or 2 if Duration
    				#		is really a distance. Note that the default is 1.
    				# --- Place : 1 - N
    				# --- Points: 1 - N Depends on Place
    				# --- UsePoints: 1 or 0. 1 if the points for this splash are to be used to compute the
    				#		swimmer's AGSOTY points, 0 if not. (example: a cat2 OW swim, or more than max swims
    				#		for a particular org/course.)
    				# --- Reason: NULL if UsePoints is 1, a string if 0. The reason we don't use these points.
		    		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
    		    		"CREATE TABLE Splash (SplashId INT AUTO_INCREMENT PRIMARY KEY, " .
    		    		"Course Varchar(15), " .
    		    		"Org Varchar(5), " .
  						"EventId INT References Event(EventId), " .
		    			"Gender Char(1), " .
		    			"AgeGroup Varchar(10), " .
		    			"Category INT, " .
		    			"View Varchar(255), " .
		    			"Date DATE, " .
		    			"MeetId INT References Meet(MeetId), " .
		    			"SwimmerId INT References Swimmer(SwimmerId), " .
		    			"Duration INT DEFAULT 0, " .
		    			"DurationType INT DEFAULT 1, " .
		    			"Place Int, " .
		    			"Points Int, " .
		    			"UsePoints INT DEFAULT 1, " .
		    			"Reason Varchar(64)" .
		    			")" );


### Meet
    			} elsif( $tableName eq "Meet" ) {
    				### Used to record every swim meet recognized by PMS or USMS that we see when
    				#	analyzing points earned by a PMS swimmer.
    				# --- MeetId : primary key
    				# --- USMSMeetId : a unique USMS identification for this meet
    				# --- MeetTitle : the title of the meet, e.g. 2014 Nationwide U.S. Masters 
    				#		Swimming Spring National Championship
    				# --- MeetLink : link to meet info
    				# --- MeetOrg : the organization recording this meet in its top 10.  The same meet
    				#		can have races recorded by both PAC and USMS, so the one here is the
    				#		first occurance we see.
    				# --- MeetCourse : the course, e.g. SCY, SCM, or LCM, OW, or ePo (ePostal truncated to 3 chars)
    				# --- MeetBeginDate : the date of the first day of the meet.
    				# --- MeetEndDate : the date of the last day of the meet.  Can be the same as MeetBeginDate
    				# --- MeetIsPMS : 1 if this meet is sanctioned by PMS, 0 otherwise.
    				# *** Note that there is an entry for "unknown meet" - it is the first
    				#		entry so has the id of 1.
		    		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
    		    		"CREATE TABLE Meet (MeetId INT AUTO_INCREMENT PRIMARY KEY" .
    		    		", USMSMeetId Varchar(50)" .
    		    		", MeetTitle Varchar(255)" .
    		    		", MeetLink Varchar(255) DEFAULT NULL" .
    		    		", MeetOrg Varchar(15) DEFAULT NULL" .
    		    		", MeetCourse Varchar(15) DEFAULT NULL" .
    		    		", MeetBeginDate DATE DEFAULT NULL" .
    		    		", MeetEndDate DATE DEFAULT NULL" .
    		    		", MeetIsPMS TINYINT(1) DEFAULT NULL" .
		    			")" );

					($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
						"INSERT INTO Meet " .
							"(MeetId, MeetTitle, MeetIsPMS) " .
							"VALUES ($DEFAULT_MISSING_MEET_ID, " .
							"\"(unknown meet)\", \"0\")") ;

### USMSDirectory
    			} elsif( $tableName eq "USMSDirectory" ) {
    				### Used to record details of a swimmer from the USMS Membership Directory.  Only recorded
    				#	for PMS swimmer.  When a swimmer and meet are associated in this table that means
    				#	that the meet is a "hidden" meet for this swimmer.
    				# --- USMSDirectoryId : primary key
				  	# --- SwimmerId : their id in the Swimmer table
				  	# --- USMSSwimmerId : their USMS swimmer id (part of their reg num - a string)
				  	# --- MeetId : Identifies the meet in the Meet table.  We will record both PMS sanctioned
				  	#		and non-PMS sanctioned meets.
		    		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
    		    		"CREATE TABLE USMSDirectory (USMSDirectoryId INT AUTO_INCREMENT PRIMARY KEY" .
		    			", SwimmerId INT References Swimmer(SwimmerId)" .
		    			", USMSSwimmerId Varchar(10)" .
		    			", MeetId INT References Meet(MeetId)" .
		    			")" );

### Event
    			} elsif( $tableName eq "Event" ) {
    				# --- Distance : of the form "50" for the 50 yard freestyle. For ePostals it's a
    				#		bit different: "distance" will EITHER be:
    				#			- a distance, which is a non-zero integer, or
    				#			- a time of the swim, in which case it's a non-zero value containing at
    				#				least one non-digit
					# --- Units : one of "Yard", "Meter", "Mile", or "K" (kilometer).
					#		"Yard" and "Meter" are usually only used for pool meets and records.
					#		"Mile" and "K" are usually only used for open water events.
    				# --- Stroke : one of "Freestyle", "Backstroke", "Breaststroke", "Butterfly", 
    				#		"Individual Medley", or "Medley" for
    				#		pool meets ("Medley" is used for relays, "Individual Medley" is used for 
    				#		individual events).  
    				#		Open Water: The name of the host for open water, e.g. "Spring Lake".
    				#		ePostal: always "Free"
    				# --- EventName : The name of the event found in the results.  
    				#		For non-ePostals: This name will
    				#		exactly match the event name when Distance, Course, and Stroke are combined
    				#		into the full event name.  An event name in the results is parsed to create
    				#		the valid values for Distance, Course, and Stroke.  For example, the event
    				#		"100 Y IM" will be represented in this table as:
    				#			Distance:  100
    				#			Course: Yard
    				#			Stroke: IM
    				#		Another example, the event "100 Free" will be represented correctly, 
    				#		where the Course is derived from the course of the results.
		    		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
    		    		"CREATE TABLE Event (EventId INT AUTO_INCREMENT PRIMARY KEY" .
    		    		", Distance Varchar(64)" .
    		    		", Units Varchar(20)" .
    		    		", Stroke Varchar(100)" .
		    			", EventName Varchar(200) )");
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"INSERT INTO Event VALUES (0, 0, 'Yard', 'Freestyle', '<fake event>')");
#		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
#		    			"INSERT INTO Event VALUES (-1, 0, 'Yard', 'Freestyle', 'ePostal')");

### RSIDN_year
    			} elsif( $tableName eq "RSIDN_$yearBeingProcessed" ) {
					# --- PMS Database (generated from RSIDN file)
    				# --- FirstName - their first name, put into cononical form
    				# --- MiddleInitial - their middle initial (single letter) or empty
    				# --- LastName - their last name, put into cona=onical form
    				# --- RegNum - in correct form (e.g. 384C-B0BUP)
    				# --- USMSSwimmerId - in correct form (e.g. B0BUP)
    				# --- RegisteredTeamInitialsStr - e.g. WCM
    				# --- Gender - one of M or F
    				# --- DateOfBirth - e.g. 1949-11-25
    				# --- RegDate - e.g. 1949-11-25
    				# --- Email - 
    				# --- Address1 - 
    				# --- City - 
    				# --- State - 2 leter abbreviation
    				# --- Zip - 
    				# --- Country - 2 letter abbrevation
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"CREATE TABLE RSIDN_$yearBeingProcessed( RSIDNId INT AUTO_INCREMENT PRIMARY KEY, " .
		    			"FirstName Varchar(100), " .
		    			"MiddleInitial Varchar(10), " .
		    			"LastName Varchar(100), " .
		    			"RegNum Varchar(32), " .
		    			"USMSSwimmerId Varchar(10), " .
		    			"RegisteredTeamInitialsStr Varchar($PMSConstants::MAX_LENGTH_TEAM_ABBREVIATION), " .
		    			"Gender Varchar(1), " .
		    			"DateOfBirth DATE, " .
		    			"RegDate DATE, " .
		    			"Email Varchar(255),  " .
		    			"Address1 Varchar(255), " .
		    			"City Varchar(255), " .
		    			"State Varchar(2), " .
		    			"Zip Varchar(20), " .
		    			"Country Varchar(20) " .
		    			") CHARACTER SET utf8 COLLATE utf8_general_ci" );
### Points
    			} elsif( $tableName eq "Points" ) {
    				# --- SwimmerId - the swimmer who earned these points
	   				# --- Course - the course in which they earned these points  
    				# ---   (SCY, SCM, LCM, OW, SCY Records, SCM Records, LCM Records)
    				# --- Org - the organization which awarded the points (PAC, USMS)
    				# --- AgeGroup - the age group the swimmer was in when earning these points.
    				#		Can be of the form "18-25:25-29" if we combine age groups for 
    				#		a swimmer who swims the season in two age groups.
    				# --- TotalPoints - the points they earned in this org, course, age group(s)
    				# --- ResultsCounted - the number of results that were counted to get TotalPoints.
    				#		Subject to limits (e.g. SCY is 8)
    				# --- ResultsAnalyzed - the number of results that were available for this swimmer
    				#		in this org, course, and age group(s).
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"CREATE TABLE Points ( PointsId INT AUTO_INCREMENT PRIMARY KEY, " .
		    			"SwimmerId INT, " .
    		    		"Course Varchar(15), " .
    		    		"Org Varchar(5), " .
		    			"AgeGroup Varchar(15), " .
		    			"TotalPoints INT DEFAULT 0, " .
		    			"ResultsCounted INT DEFAULT 0, " .
		    			"ResultsAnalyzed INT DEFAULT 0 " .
		    			")" );

### FinalPlaceSAG  (Split Age Groups)
    			} elsif( $tableName eq "FinalPlaceSAG" ) {
    				# --- SwimmerId - the swimmer who earned these points
    				# --- AgeGroup - the age group the swimmer was in when earning these points.
    				#		Will be of the form "18-25", even for swimmers with split age groups.
    				# --- ListOrder - the order this swimmer appears in the reslts.  Would normally be the
    				#		same as Rank (below) but there can be ties, so it doesn't have to be the same.
    				#		This allows us to list the names in a deterministic order even if there 
    				#		are ties.
    				# --- Rank - the swimmer's ranking in their gender/age group, e.g. 1 = 1st, 3=3rd, etc.
    				#		It's possible for two or more swimmers to have the same rank (it's a tie)
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"CREATE TABLE FinalPlaceSAG ( FinalPlaceSAGId INT AUTO_INCREMENT PRIMARY KEY, " .
		    			"SwimmerId INT, " .
		    			"AgeGroup Varchar(15), " .
		    			"ListOrder INT, " .
		    			"Rank INT " .
		    			")" );
		    			
### FinalPlaceCAG  (Combined Age Groups)
    			} elsif( $tableName eq "FinalPlaceCAG" ) {
    				# --- SwimmerId - the swimmer who earned these points
    				# --- AgeGroup - the age group the swimmer was in when earning these points.
    				#		Can be of the form "18-25" for swimmers who do not have split age groups,
    				#		or "18-25:25-29" if we combine age groups for 
    				#		a swimmer who swims the season in two age groups.
    				# --- ListOrder - the order this swimmer appears in the reslts.  Would normally be the
    				#		same as Rank (below) but there can be ties, so it doesn't have to be the same.
    				#		This allows us to list the names in a deterministic order even if there 
    				#		are ties.
    				# --- Rank - the swimmer's ranking in their gender/age group, e.g. 1 = 1st, 3=3rd, etc.
    				#		It's possible for two or more swimmers to have the same rank (it's a tie)
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"CREATE TABLE FinalPlaceCAG ( FinalPlaceCAGID INT AUTO_INCREMENT PRIMARY KEY, " .
		    			"SwimmerId INT, " .
		    			"AgeGroup Varchar(15), " .
		    			"ListOrder INT, " .
		    			"Rank INT " .
		    			")" );
		    			
### Swimmer
    			} elsif( $tableName eq "Swimmer" ) {
    				# --- FirstName - their first name, put into cononical form
    				# --- MiddleInitial - their middle initial (single letter) or empty
    				# --- LastName - their last name, put into cona=onical form
    				# --- Gender - one of M or F
				  	# --- RegNum: their USMS reg num (a string)
				  	# --- Age1 - their age at their first recorded top N of the season
				  	# --- Age2 - their age at their last recorded top N of the season
				  	# --- AgeGroup1 - their age group during first event we found them in.
				  	# --- AgeGroup2 - "", or a second age group we found them in.
				  	# --- RegisteredTeamInitials:  (what if more than one?  Use the first one found)
				  	# --- Sector: one of NULL, A, B, C, or D.  See the RankSectors package for the meaning of a Sector.
				  	#		If NULL the sector for this swimmer was not computed.
				  	# --- SectorReason: a string that explains the reason for the assigned Sector, or
				  	#		NULL if no reason.
				  	# --- GotUSMSDirectoryInfo: 1 if we've dug into their USMS Directory data and derived all
				  	#		their hidden meets, 0 otherwise.
				  	#
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"CREATE TABLE Swimmer (SwimmerId INT AUTO_INCREMENT PRIMARY KEY, " .
		    			"FirstName Varchar(100), " .
		    			"MiddleInitial Varchar(10), " .
		    			"LastName Varchar(100), " .
		    			"Gender Char(1), " .
		    			"RegNum Varchar(20), " .
		    			"Age1 INT, " .
		    			"Age2 INT, " .
		    			"AgeGroup1 Varchar(10), " .
		    			"AgeGroup2 Varchar(10) DEFAULT '', " .
		    			"RegisteredTeamInitials Varchar(10), " .
		    			"Sector Char(1) DEFAULT NULL, " .
		    			"SectorReason Varchar(512) DEFAULT NULL, " .
		    			"GotUSMSDirectoryInfo TINYINT(1) DEFAULT 0 " .
		    			" ) CHARACTER SET utf8 COLLATE utf8_general_ci" );
    			
### NumSwimmers
    			} elsif( $tableName eq "NumSwimmers" ) {
    				# --- Gender - one of M or F
				  	# --- AgeGroup - their age group.
				  	# --- SplitAgeGroupTag - one of "split" or "combined".  "split" means that this is the number of swimmers
				  	#		who competed and accumulated points in two different age groups, and this is the older of the age groups.
				  	#		"combined" means that this is the number of swimmers who competed in two different age groups but
				  	#		accumulated their points in the older age group (this age group)
				  	# --- NumSwimmers - number of swimmers who earned points in this gender
				  	#		and age group.
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"CREATE TABLE NumSwimmers (NumSwimmersId INT AUTO_INCREMENT PRIMARY KEY, " .
		    			"Gender Char(1), " .
		    			"AgeGroup Varchar(15), " .
		    			"SplitAgeGroupTag Varchar(10), " .
		    			"NumSwimmers INT DEFAULT 0 " .
		    			" )" );
		    			    			
### PMSTeams
    			} elsif( $tableName eq "PMSTeams" ) {
    				# --- Table of PMS teams - legal PMS teams only.
    				#		See the table 'ReferencedTeams' for a list of teams referenced in race
    				#		entries, along with the swimmer referencing the team.
    				# --- TeamAbbr = WCM or CALM - always capitalized.
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"CREATE TABLE PMSTeams (PMSTeamsId INT AUTO_INCREMENT PRIMARY KEY, " .
		    			"TeamAbbr VARCHAR($PMSConstants::MAX_LENGTH_TEAM_ABBREVIATION) UNIQUE, " .
		    			"FullTeamName VARCHAR(200) )" );
# results tables:
### FetchStats
    			} elsif( $tableName eq "FetchStats" ) {
    				# NOTE: IF YOU ADD A COLUMN TO THIS TABLE YOU PROBABLY NEED TO ADD THE SAME
    				#	FIELD TO THE %fetchStats HASH (see TT_Struct.pm)
    				# ALSO: Since this table isn't automatically dropped and re-created if you
    				#	modify this table (add/delete a row, etc) you'll need to do that by hand.
    				#	e.g. mysql -u USER -h HOST -p DBName
    				#			alter table FetchStats add FS_ePostalPointEarners INT DEFAULT 0;
				  	# --- Season - The season for which the data were fetched, e.g. 2016
				  	# --- FS_NumLinesRead - number of lines read when fetching the data
				  	# --- FS_NumDifferentMeetsSeen - number of different meets seen
				  	# --- FS_NumDifferentResultsSeen - number of results seen when fetching the data
				  	# --- FS_NumDifferentFiles - number of files read when fetching the data
				  	# --- FS_NumRaceLines - number of lines written to the races.txt file
				  	# --- FS_CurrentSCYRecords - the number of "current "records for this course that earned 
				  	#		points for a swimmer during this season.  A "current" record is a record that
				  	#		is currently the record (vs a "historical" record.)
				  	# --- FS_CurrentSCMRecords - (ditto)
				  	# --- FS_CurrentLCMRecords - (ditto)
				  	# --- FS_HistoricalSCYRecords - the number of "historical" records for this course that earned 
				  	#		points for a swimmer during this season.  A "historical" record is a 
				  	#		record that was set during the season but then broken after the end
				  	#		of the season.  Thus the record is no longer the "current" one, but the swimmer
				  	#		still deserves points for the record since she/he set it during the season.
				  	# --- FS_HistoricalSCMRecords - (ditto)
				  	# --- FS_HistoricalLCMRecords - (ditto)
				  	# --- FS_ePostalPointEarners - number of ePostal splashes which earned PMS points
				  	# --- Date - the date and time this row was written/updated
				  	# 
		    		($sth,$rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		    			"CREATE TABLE FetchStats (FetchStatsId INT AUTO_INCREMENT PRIMARY KEY, " .
		    			"Season Varchar(4) NOT NULL UNIQUE, " .
		    			"Date DATETIME, " .
		    			"FS_NumLinesRead INT DEFAULT 0, " .
		    			"FS_NumDifferentMeetsSeen INT DEFAULT 0, " .
		    			"FS_NumDifferentResultsSeen INT DEFAULT 0, " .
		    			"FS_NumDifferentFiles INT DEFAULT 0, " .
		    			"FS_NumRaceLines INT DEFAULT 0, " .
		    			"FS_CurrentSCYRecords INT DEFAULT 0, " .
		    			"FS_CurrentSCMRecords INT DEFAULT 0, " .
		    			"FS_CurrentLCMRecords INT DEFAULT 0, " .
		    			"FS_HistoricalSCYRecords INT DEFAULT 0, " .
		    			"FS_HistoricalSCMRecords INT DEFAULT 0, " .
		    			"FS_HistoricalLCMRecords INT DEFAULT 0, " .
		    			"FS_ePostalPointEarners INT DEFAULT 0 " .
		    			" )" );
    			}
			}
    	}
	} # end of foreach(...)
	return $dbh;
} # end of InitializeTopTenDB()





# DropTTTables - drop (almost) all (existing) Top10 tables in our db
#
sub DropTTTables() {
	PMS_MySqlSupport::GetTableList( \%ttTableList, \$ttTableListInitialized );
	PMS_MySqlSupport::DropTables( \%ttTableList, \@ttTableListNotDropped);
} # end of DropTTTables()



# TT_MySqlSupport::DropTable( $tableName );
# DropTable - drop the passed table in our db
#
sub DropTable( $ ) {
	my $tableName = $_[0];
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $qry;
	my $gotTableToDrop = 0;
	
	# construct the DROP TABLES query:
	PMS_MySqlSupport::GetTableList( \%ttTableList, \$ttTableListInitialized );
	if( $ttTableList{$tableName} ) {
		print "Table '$tableName' exists - dropping it.\n";
		$qry = "DROP table $tableName";
		$gotTableToDrop = 1;
		# update our cache to show that this table doesn't exist
		$ttTableList{$tableName} = 0;
	}
	
	if( $gotTableToDrop ) {
		# Execute the DROP query
		my $sth = $dbh->prepare( $qry ) or 
	    	die "Can't prepare in DropTable(): '$qry'\n";
	    my $rv;
	    $rv = $sth->execute or 
	    	die "Can't execute in DropTable(): '$qry'\n"; 
	}   
} # end of DropTable()


# my $eventId = TT_MySqlSupport::AddNewEventIfNecessary( $distance, $units,
#	$stroke, $eventName );
# AddNewEventIfNecessary - look up the passed event in the Event table.  If not found
#	then add the event.  In all cases return the EventId.
#
# PASSED:
#	$distance
#	$units - Yard or Meter
#	$stroke -
#	$eventName - (optional)
#
# RETURNED:
#	$eventId -
#
sub AddNewEventIfNecessary($$$) {
	my ($distance, $units, $stroke, $eventName) = @_;
# handle old case (temp)
if( !defined $units ) {
	$eventName = $distance;
	$units = "xxx";
	$stroke = $distance;
	$distance="xxx";
}
	if( !defined $eventName ) {
		$eventName = "$distance $units $stroke";
	}
	my $eventId = 0;
	my $resultHash;
	
	# get ready to use our database:
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	
	# populate the Event table with this event if it's not already there...
	# is this event already in our db?  If so don't try to put it in again
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"SELECT EventId FROM Event WHERE Distance='$distance' AND Units='$units' " .
		"AND Stroke='$stroke'" );
	if( defined($resultHash = $sth->fetchrow_hashref) ) {
		# this event is already in our DB - get the db id
		$eventId = $resultHash->{'EventId'};
	} else {
		# insert this event
		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
			"INSERT INTO Event " .
				"(Distance,Units,Stroke,EventName) " .
				"VALUES ('$distance','$units','$stroke','$eventName')") ;
				
		# get the EventId of the event we just entered into our db
    	$eventId = $dbh->last_insert_id(undef, undef, "Event", "EventId");
    	die "Can't determine EventId of newly inserted Event" if( !defined( $eventId ) );
	}
	
	return $eventId;
} # end of AddNewEventIfNecessary()



# AddNewSwimmerIfNecessary - look up the passed swimmer in the Swimmer table.  If not found
#	then add the swimmer.  If found update the ageGroup2 field if necessary.
#	In all cases return the SwimmerId.
#
# We look up the swimmer by reg num.
#
# If the swimmer is found then do the following checks:
#	- first, middle, and last names match
#	- gender in db match passed gender
#	- ageGroup1 or ageGroup2 in db matches passed $ageGroup or is one age group away.
#	- team matches
#
# hack:
sub AddNewSwimmerIfNecessary( $$$$$$$$$$ ){
	my($fileName, $lineNum, $firstName, $middleInitial, $lastName, $gender, $regNum, $age, 
		$ageGroup, $team) = @_;
	my $swimmerId = 0;
	my $resultHash;
	my $ageGroup1 = "";
	my $ageGroup2 = "";
	
	my $debugLastName = "xxxxx";
	
	# make sure the gender is either M or F
	$gender = PMSUtil::GenerateCanonicalGender( $fileName, $lineNum, $gender );
	
	# get ready to use our database:
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	
	# Get the USMS Swimmer id, e.g. regnum 384x-abcde gives us 'abcde'
	my $regNumRt = PMSUtil::GetUSMSSwimmerIdFromRegNum( $regNum );
	
	# populate the Swimmer table with this swimmer if it's not already there...
	# is this swimmer already in our db?  If so don't try to put it in again
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"SELECT SwimmerId,FirstName,MiddleInitial,LastName,Gender,AgeGroup1,AgeGroup2,RegisteredTeamInitials " .
		"FROM Swimmer WHERE RegNum LIKE \"38%-$regNumRt\"", 
		$debugLastName eq $lastName ? "Looking For > $firstName $lastName":"" );
	$resultHash = $sth->fetchrow_hashref;
	if( $debugLastName eq $lastName ) {
		if( defined($resultHash) ) {
			PMSLogging::PrintLog( "", "", "$debugLastName found with $regNumRt\n", 1 );
		} else {
			PMSLogging::PrintLog( "", "", "$debugLastName NOT found with $regNumRt\n", 1 );
		}
	}
	if( defined($resultHash) ) {
		# this swimmer is already in our DB - get the db id
		$swimmerId = $resultHash->{'SwimmerId'};
		# validate db data
		# first, the age groups for this swimmer is a special case...they can be in 2 age groups for the year
		$ageGroup1 = $resultHash->{'AgeGroup1'};
		$ageGroup2 = $resultHash->{'AgeGroup2'};	# can be empty string
		if( $ageGroup ne $ageGroup1 ) {
			# the passed ageGroup is not the same as the first age group we saw for this swimmer -
			# Do they have a second age group in the DB, and, if so, is it the same as the passed age group?
			if( $ageGroup2 ne "" ) {
				if( $ageGroup ne $ageGroup2 ) {
					PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewSwimmerIfNecessary(): ('$fileName', $lineNum): " .
						"AgeGroup in results ($ageGroup) != db (\"$ageGroup1\", \"$ageGroup2\") " .
						"for regNum $regNum", 1 );
				} else {
					# the passed age group = ageGroup2 for this swimmer.  Good.
				}
			} else {
				# this swimmer doesn't have a second age group in the DB - make sure the one passed is one
				# age group above or below the current one in the db, and if it is, make it their second
				# age group in the db.
				if( AgeGroupsClose( $ageGroup, $ageGroup1 ) ) {
					# update this swimmer by adding their ageGroup2
					my ($sth2, $rv2) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
						"UPDATE Swimmer SET AgeGroup2 = '$ageGroup' " .
						"WHERE SwimmerId = $swimmerId" );
					$total2AgeGroups++;
					$MultiAgeGroups{$swimmerId} = "$ageGroup1:$ageGroup:$gender";
				} else {
					# the second age group for this swimmer isn't right - display error
					# and don't add it to the db:
					PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewSwimmerIfNecessary(): ('$fileName', $lineNum): " .
						"AgeGroup in results ($ageGroup) is not near the ageGroup1 in the db " .
						"(\"$ageGroup1\") " .
						"for regNum $regNum", 1 );
				}
			}
		}

		PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewSwimmerIfNecessary(): ('$fileName', $lineNum): " .
			"Firstname in results ('$firstName') != db (Swimmer table) ('$resultHash->{'FirstName'}') for regNum $regNum. " .
			"(non-fatal)\n" ) 
			if( lc($firstName) ne lc($resultHash->{'FirstName'}) );
		PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewSwimmerIfNecessary(): ('$fileName', $lineNum): " .
			"MiddleInitial in results ($middleInitial) != db (Swimmer table) ($resultHash->{'MiddleInitial'}) for regNum $regNum. " .
			"(non-fatal)\n" )
			if( (lc($middleInitial) ne lc($resultHash->{'MiddleInitial'})) && 
				($middleInitial ne "") );
		PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewSwimmerIfNecessary(): ('$fileName', $lineNum): " .
			"LastName in results (\"$lastName\") != db (Swimmer table) (\"$resultHash->{'LastName'}\") for regNum $regNum. " .
			"(non-fatal)\n" )
			if( lc($lastName) ne lc($resultHash->{'LastName'}) );
		PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewSwimmerIfNecessary(): ('$fileName', $lineNum): " .
			"Gender in results ($gender) != db (Swimmer table) ($resultHash->{'Gender'}) for regNum $regNum. " .
			"(non-fatal)\n" )
			if( lc($gender) ne lc($resultHash->{'Gender'}) );
			
		PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewSwimmerIfNecessary(): ('$fileName', $lineNum): " .
			"Team in results ($team) != db (Swimmer table) ($resultHash->{'RegisteredTeamInitials'}) for regNum $regNum. " .
			"(non-fatal)\n" )
			if( ($team ne "") && (lc($team) ne lc($resultHash->{'RegisteredTeamInitials'})) );
	} else {
		if( 1 ) {
			# see if we have a situation where we have two completely different reg numbers for the
			# same person (a "normal" reg number and one or more vanity reg numbers)
			($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
				"SELECT SwimmerId,FirstName,MiddleInitial,LastName,Gender,AgeGroup1,AgeGroup2," .
				"RegisteredTeamInitials,RegNum " .
				"FROM Swimmer WHERE LastName=\"$lastName\" AND FirstName=\"$firstName\"" );
			while( defined($resultHash = $sth->fetchrow_hashref) ) {
				# this swimmer appears to already in our DB - get the db id
				$swimmerId = $resultHash->{'SwimmerId'};
				$ageGroup1 = $resultHash->{'AgeGroup1'};
				$ageGroup2 = $resultHash->{'AgeGroup2'};	# can be empty string
				my $dbFirstName = $resultHash->{'FirstName'};
				my $dbMiddleInitial = $resultHash->{'MiddleInitial'};
				my $gender = $resultHash->{'Gender'};
				my $regTeam = $resultHash->{'RegisteredTeamInitials'};
				my $dbRegNum = $resultHash->{'RegNum'};
				PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewSwimmerIfNecessary(): Possible multiple RegNums:\n" .
					"  Can't find '$firstName' '$middleInitial' '$lastName' with regnum '$regNum'," .
					" gender=$gender, ageGroup=$ageGroup, team=$regTeam in the SWIMMER table " .
					"\n  However, found: '$dbFirstName' '$dbMiddleInitial' " .
					"'$lastName' with regnum '$dbRegNum'," .
					" gender=$gender, swimmerId=$swimmerId, ageGroup1=$ageGroup1, ageGroup2=$ageGroup2, " .
					"team=$regTeam in the SWIMMER table." .
					"\n  '$firstName' '$middleInitial' '$lastName' with regnum '$regNum' will be inserted.");
			}
		}
		# Carry on...add this swimmer to our db (even if it's a possible duplicate since we can't
		# know for sure)
		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
			"INSERT INTO Swimmer " .
				"(FirstName,MiddleInitial,LastName,Gender,RegNum,Age1,Age2,AgeGroup1,RegisteredTeamInitials) " .
				"VALUES (\"$firstName\",\"$middleInitial\",\"$lastName\",\"$gender\",\"$regNum\"," .
				"\"$age\",\"$age\",\"$ageGroup\",\"$team\")") ;
				
		# get the SwimmerId of the swimmer we just entered into our db
    	$swimmerId = $dbh->last_insert_id(undef, undef, "Swimmer", "SwimmerId");
    	die "Can't determine SwimmerId of newly inserted Swimmer" if( !defined( $swimmerId ) );
	}
	
	return $swimmerId;
	
} # end of AddNewSwimmerIfNecessary()



# TT_MySqlSupport::AddNewSplash( $fileName, $lineNum, $currentAgeGroup, $currentGender, 
#	$place, $points, $swimmerId, $currentEventId, $org, $course, $meetId, $time, $date, $category );

# AddNewSplash - Add an entry in the Splash table representing the passed top N finish
#
# PASSED:
#	$fileName - the file containing the result this splash represents.  Used for messages only.
#	$lineNum - the line number in the file.  Used for messages only.
#	$ageGroup - age group of the swimmer who made the splash.
#	$gender - gender of the swimmer who made the splash.
#	$place - the place the swimmer took with this splash.
#	$points - the number of points the swimmer got from this splash
#	$swimmerId - the swimmer
#	$eventId - the event the swimmer was swimming in (e.g. 50 M free), or -1 if ePostal
#	$org - PAC or USMS
#	$course - SCY, LCM, SCM, OW, ePostal
#	$meetId - the meet the swimmer was swimming in.  Could be $TT_MySqlSupport::DEFAULT_MISSING_MEET_ID
#	$time - the duration of the swim
#	$date - the date of the swim.  Of the form yyyy-mm-dd.  Could be $PMSConstants::DEFAULT_MISSING_DATE.
#	$durationType (optional, but must be supplied if $category is supplied) - 1 (or missing) if the passed 
#		$time is a time, 2 if it's really a distance
#	$category (optional) - if supplied must be 1 or 2. If not supplied then default to 1.
#
sub AddNewSplash {
	my ($fileName, $lineNum, $ageGroup, $gender, $place, $points, $swimmerId, $eventId, $org, 
		$course, $meetId, $time, $date, $durationType, $category) = @_;
	if( !defined $category ) {
		$category = 1;
	}

	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	
	if( !defined( $durationType ) ) {
		$durationType = 1;			# default...
	}
	
	# sanity check
	if( ($org ne "PAC") && ($org ne "USMS") ) {
		PMSLogging::DumpWarning( "", "", "AddNewSplash(): $fileName, line $lineNum: the passed 'org' " .
			"is invalid (not fatal): '$org'", 1 );
	}
	if( ($course ne "SCY") && ($course ne "SCM") && ($course ne "LCM") && ($course ne 'OW') && ($course ne 'ePostal') ) {
		PMSLogging::DumpWarning( "", "", "AddNewSplash(): $fileName, line $lineNum: the passed 'course' ".
			"is invalid (not fatal): '$course'", 1 );
	}
	
	# make sure the gender is either M or F
	$gender = PMSUtil::GenerateCanonicalGender( $fileName, $lineNum, $gender );
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		"INSERT INTO Splash " .
			"(Course, Org, EventId, Gender, AgeGroup, Category, Date, MeetId, SwimmerId, Duration, " .
			"Place, Points, DurationType) " .
			"VALUES (\"$course\",\"$org\",\"$eventId\",\"$gender\",\"$ageGroup\",\"$category\"," .
			"\"$date\",\"$meetId\",\"$swimmerId\",\"$time\"," .
			"\"$place\", \"$points\", \"$durationType\")") ;
			
} # end of AddNewSplash()


# my $meetId = TT_MySqlSupport::AddNewMeetIfNecessary( filename, linenum, meetitle, meetlink, 
#		meetorg, meetcourse, meetbegindate, meetenddate, meetispms (1 or 0)  )
#
# AddNewMeetIfNecessary - Add an entry in the Meet table representing the passed swim meet
#
# PASSED:
#	$fileName - (not used - available for messages)
#	$lineNum - (not used - available for messages)
#	$meetTitle - 
#	$meetLink - link to meet info on USMS site (if available - may be "none" or something if unknown)
#	$meetOrg - PAC or USMS
#	$meetCourse - SCY, SCM, LCM
#	$meetBeginDate - date of first day of meet.  Of the form yyyy-mm-dd.  Could be $PMSConstants::DEFAULT_MISSING_DATE.
#	$meetEndDate - date of last day.  May be the same as $meetBeginDate
#	$meetIsPMS - 1 if this is a PMS sanctioned meet, 0 otherwise.
#
# NOTES:  duplicates are never allowed.
#
sub AddNewMeetIfNecessary($$$$$$$$$) {
	my ($fileName, $lineNum, $meetTitle, $meetLink, $meetOrg, $meetCourse, $meetBeginDate,
		$meetEndDate, $meetIsPMS) = @_;
	my $meetId;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();

	$meetTitle =  MySqlEscape($meetTitle);

	# is this meet already in our db?
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"SELECT MeetId " .
		"FROM Meet WHERE MeetTitle = \"$meetTitle\"" );
	if( defined(my $resultHash = $sth->fetchrow_hashref) ) {
		# this meet is already in our DB - get the meet id
		$meetId = $resultHash->{'MeetId'};
	} else {
		if( $meetLink eq "(none)" ) {
			PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewMeetIfNecessary(): " .
				"Found null meetlink: meetTitle='$meetTitle', stack:", 1 );
			PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::AddNewMeetIfNecessary(): " .
				PMSUtil::GetStackTrace(), 1 );
		}
		# this meet isn't in our db - add it
		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
			"INSERT INTO Meet " .
				"(MeetTitle, MeetLink, MeetOrg, MeetCourse, MeetBeginDate, MeetEndDate, MeetIsPMS) " .
				"VALUES ( " .
				"\"" . MySqlEscape($meetTitle) . "\"," .
				"\"" . MySqlEscape($meetLink) . "\"," .
				"\"" . $meetOrg . "\"," .
				"\"" . $meetCourse . "\"," .
				"\"" . $meetBeginDate . "\"," .
				"\"" . $meetEndDate . "\"," .
				"\"" . $meetIsPMS . "\" )", "");
		# get the MeetId of the meet we just entered into our db
    	$meetId = $dbh->last_insert_id(undef, undef, "Meet", "MeetId");
	}
	return $meetId;

} # end of AddNewMeetIfNecessary()


# TT_MySqlSupport::AddNewRecordSplash( $fileName, $lineNum, $course, $org, $eventId, $gender,
# 	$ageGroup, $category, $swimmerId, $place, $points, $meetId, date, duration );

# AddNewRecordSplash - Add an entry in the Splash table representing the passed record finish
#
# PASSED:
#	$fileName - used for messages only
#	$lineNum - used for messages only
#	$course - SCY, SCM, LCM
#	$org - PAC or USMS
#	$eventId - the event the record is for
#	$gender - the gender of the swimmer setting the record
#	$ageGroup - the age group of the swimmer setting the record
#	$cat - category of the swim.  Always 1
#	$swimmerId - the swimmer setting the record
#	$place - always 0
#	$points - will always be 25 for a PMS record or 50 for a USMS record
#	$meetId - the meet swum when the record was set
#	$date - the date the record was set
#	$duration - the record time (duration)
#	$durationType (optional) - 1 (or missing) if the passed $duration is a time, 2 if it's really a distance
#
sub AddNewRecordSplash ($$$$$$$$$$$$$$) {
	my ($fileName, $lineNum, $course, $org, $eventId, $gender, $ageGroup, $cat, 
		$swimmerId, $place, $points, $meetId, $date, $duration, $durationType) = @_;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	
	# $durationType is optional, so supply default if missing:
	if( !defined $durationType ) {
		$durationType = 1;
	}
		
	# make sure the gender is either M or F
	$gender = PMSUtil::GenerateCanonicalGender( $fileName, $lineNum, $gender );

	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, 
		"INSERT INTO Splash " .
			"(Course, Org, EventId, Gender, AgeGroup, Category, Date, MeetId, SwimmerId, Duration, " .
			"Place, Points, DurationType) " .
			"VALUES (\"$course\",\"$org\",\"$eventId\",\"$gender\",\"$ageGroup\",\"$cat\"," .
			"\"$date\",\"$meetId\",\"$swimmerId\",\"$duration\"," .
			"\"$place\", \"$points\", \"$durationType\")" ) ;
			
} # end of AddNewRecordSplash()



#	my $splashId = TT_MySqlSupport::LookUpRecord( $course, $org, $eventId, $gender, $ageGroup );
#
# LookUpRecord - look up a specific record and return the corresponding splash.
#
# PASSED:
#	$course - SCY, SCM, LCM
#	$org - USMS or PAC
#	$eventId - the event of the record
#	$gender - gender of the swimmer
#	$ageGroup - age group of the swimmer
#
# RETURNED:
#	$splashId - the splash that earned the record
#
sub LookUpRecord( $$$$$ ) {
	my ($course, $org, $eventId, $gender, $ageGroup) = @_;
	my $splashId = 0;
	
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $query = "SELECT SplashId FROM Splash WHERE " .
		"Course='$course' AND Org='$org' AND EventId='$eventId' AND " .
		"Gender='$gender' AND AgeGroup='$ageGroup'";
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	if( defined(my $resultHash = $sth->fetchrow_hashref) ) {
		# this splash is already in our DB
		$splashId = $resultHash->{'SplashId'};
		$splashId = 0 if( !defined $splashId );
	}
	
	return $splashId;
	
} # end of LookUpRecord()




# my ( $resultsAnalyzed, $totalPoints, $resultsCounted ) = 
#		TT_MySqlSupport::GetSwimmersSwimDetails2( $swimmerId, $org, $course, $ageGroup, $resultRef );
#
# GetSwimmersSwimDetails2 - Get the details on all swims (point earning or not) performed by this swimmer
#		in this org and course.
#
# PASSED:
#	$swimmerId -
#	$org -
#	$course -
#	$ageGroup - either of the form '18-24' or '18-24:25-29'.
#	$resultRef - (optional) a reference to an array that returns holding 0 or more hashes containing the
#		details.  If undefined then the details are not returned.
#
# RETURNED:
#	$resultsAnalyzed - The number of splashes for the passed
#		org and course.  For example, a swimmer may compete by swimming 20 different SCY events,
#		where 15 of them resulted in a PAC top 10 time.  However, if the limit of top 10 PAC times
#		we consider for AGSOTY is 8 then we'll only consider the best 8 times.  The value of
#		$resultsAnalyzed will be 20.  If the passed $resultRef is defined, it will reference 
#		an array containing $resultsAnalyzed elements (each element is a hash.)
#	$totalPoints - The total number of points we'll consider towards their AGSOTY total.  Using the
#		example above, it's the total number of points earned by the best 8 times.
#	$resultsCounted - The number of splashes we'll actually use to compute $totalPoints.  Using the
#		example above, this value will be 8.
#
# NOTE: as of March, 2022 we are storing OW results for both cat1 and cat2. For that reason this
#	routine will CONSIDER all cat2 splashes but those are not used to compute AGSOTY points.
#
sub GetSwimmersSwimDetails2($$$$) {
	my ($swimmerId, $org, $course, $ageGroup, $resultRef) = @_;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my @arrOfResultHashRef = ();
	my( $totalPoints, $resultsCounted, $resultsAnalyzed ) = (0,0,0);

	my $ageGroupQuery = "";
	if( $ageGroup !~ m/:/ ) {
		# single age group
		$ageGroupQuery = " AND Splash.AgeGroup = '$ageGroup' ";
	}

	my $query = "SELECT Splash.EventId, Splash.MeetId, Splash.Place, Splash.Points, Splash.Category, " .
		"Event.EventName, Event.Distance, Event.Units, Meet.MeetTitle, Splash.Date, Splash.Duration, " .
		"Splash.UsePoints, Splash.Reason, " .
		"Splash.DurationType, Splash.AgeGroup " .
		"FROM (Splash join Event) join Meet  " .
		"WHERE Splash.SwimmerId = $swimmerId " .
		"AND Splash.Course = '$course'  " .
		"AND Splash.Org = '$org'  " .
		"AND Splash.EventId = Event.EventId  " .
		"AND Splash.MeetId = Meet.MeetId  " .
		$ageGroupQuery .
		"ORDER BY UsePoints DESC, Points DESC,Date DESC";
	
	my $debugQuery = "";
	$debugQuery = "GetSwimmersSwimDetails2: Val" if( $swimmerId == -1 );
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query, "$debugQuery" );
	
	my %hashOfEvents = ();		# used to remove duplicates
	# $hashOfEvents{eventId-$course} = points : the swimmer swam in event # 'eventId' 
	# and course $course and earned 'points' points.  E.g. event "100 M free" LCM, 
	# earning 8 points.  Note they can also earn points in event "100 M free" SCM.
	
	while( my $resultHash = $sth->fetchrow_hashref ) {
		$resultsAnalyzed++;
		my $points = $resultHash->{'Points'};
		my $eventId = $resultHash->{'EventId'};
		my $usePoints = $resultHash->{'UsePoints'};
		my $reason = $resultHash->{'Reason'};
		
		if( !defined $reason ) {
			$reason = "";
		}
		
		if( $usePoints ) {
			$resultsCounted++;
			$totalPoints += $points;
		} else {
			$points = 0;
		}
		
		if( defined $resultRef ) {
			$resultRef->[$resultsAnalyzed]{'EventName'} = $resultHash->{'EventName'};
			$resultRef->[$resultsAnalyzed]{'EventDistance'} = $resultHash->{'Distance'};
			$resultRef->[$resultsAnalyzed]{'EventUnits'} = $resultHash->{'Units'};
			$resultRef->[$resultsAnalyzed]{'SplashDuration'} = $resultHash->{'Duration'};
			$resultRef->[$resultsAnalyzed]{'SplashDurationType'} = $resultHash->{'DurationType'};
			$resultRef->[$resultsAnalyzed]{'SplashPlace'} = $resultHash->{'Place'};
			$resultRef->[$resultsAnalyzed]{'SplashPoints'} = $points;
			$resultRef->[$resultsAnalyzed]{'UsePoints'} = $usePoints;
			$resultRef->[$resultsAnalyzed]{'Reason'} = $reason;
			$resultRef->[$resultsAnalyzed]{'MeetTitle'} = $resultHash->{'MeetTitle'};
			$resultRef->[$resultsAnalyzed]{'SplashDate'} = $resultHash->{'Date'};
			$resultRef->[$resultsAnalyzed]{'AgeGroup'} = $resultHash->{'AgeGroup'};
		}
		
	} # end of while()...
	return ( $resultsAnalyzed, $totalPoints, $resultsCounted );
} # end of GetSwimmersSwimDetails2()



#	($ListOfMeetsStatementHandle, $numPoolMeets, $numOWMeets, $numPMSMeets) = TT_MySqlSupport::GetListOfMeets( );
#
# GetListOfMeets - return a list of meets that we saw while analyzing the results and digging into each swimmer's
#	swim history.
#
#	PASSED:
#		n/a
#
#	RETURNED:
#		$sth - statement handle which is used by the caller to get the details of all the meets.  Details include:
#				MeetId,MeetTitle,MeetLink,MeetOrg,MeetCourse,MeetBeginDate,MeetEndDate,MeetIsPMS
#			The meets are returned in order of beginning meet date, oldest meet first.
#		$numPoolMeets -
#		$numOWMeets -
#		$numPMSMeets - # of meets that are PMS sanctioned.
#
#	
sub GetListOfMeets() {
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my ($numPoolMeets, $numOWMeets, $numPMSMeets) = (0,0, 0);
	
	my $query = "SELECT Count(*) as count " .
		"FROM Meet " .
		"WHERE MeetId != 1 AND MeetCourse = 'OW'";
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query, "" );
	my $resultHash = $sth->fetchrow_hashref;
	$numOWMeets = $resultHash->{'count'};
	
	$query = "SELECT Count(*) as count " .
		"FROM Meet " .
		"WHERE MeetId != 1 AND MeetCourse != 'OW'";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query, "" );
	$resultHash = $sth->fetchrow_hashref;
	$numPoolMeets = $resultHash->{'count'};

	$query = "SELECT Count(*) as count " .
		"FROM Meet " .
		"WHERE MeetId != 1 AND MeetCourse != 'OW' AND MeetIsPMS=1";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query, "" );
	$resultHash = $sth->fetchrow_hashref;
	$numPMSMeets = $resultHash->{'count'};		# pms pool meets 

	$query = "SELECT MeetId,MeetTitle,MeetLink,MeetOrg,MeetCourse,MeetBeginDate,MeetEndDate,MeetIsPMS " .
		"FROM Meet " .
		"WHERE MeetId != 1 " .
		"ORDER BY MeetBeginDate";
	
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query, "" );
	return ($sth, $numPoolMeets, $numOWMeets, $numPMSMeets);
} # end of GetListOfMeets()


# GetSplashesForMeet - return the stats for a specific meet
#
# PASSED:
#	$meetId - the meet we're interested in
# 
# RETURNED:
#	$numSplash - # of PAC swimmer splashes at this meet that earned top 10 PMS or USMS points.  If one
#		PAC swimmer swims in 3 races and earnes points in 2 of them then this number will be 2.
#	$numSwimmers - # of unique PAC swimmers who earned points at this meet.  In the above example
#		this number will be 1.
#
sub GetSplashesForMeet( $ ) {
	my $meetId = $_[0];
	my ($numSplash, $numSwimmers) = (0,0);
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();

	my $query = "SELECT COUNT(DISTINCT(SwimmerId)) AS Swimmers, " .
				"COUNT(SwimmerId) AS Splashes FROM Splash WHERE MeetId=$meetId";
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query, "" );
	if( defined(my $resultHash = $sth->fetchrow_hashref) ) {
		$numSplash = $resultHash->{'Splashes'};
		$numSwimmers = $resultHash->{'Swimmers'};
	} else {
		PMSLogging::DumpError( "", "", "TT_MySqlSupport::GetSplashesForMeet(): Unable to get data for meet id $meetId", 1 );
	}
	return ($numSplash, $numSwimmers);	
} # end of GetSplashesForMeet()


# GetNumberOfSwimmers - get some stats on the swimmers we saw
#
# PASSED:
#	n/a
#
# RETURNED:
#	$num - number of PMS swimmers we saw
#	$numWithPoints - number of PMS swimmers we saw that earned points.
#
sub GetNumberOfSwimmers() {
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $query1 = "Select Count(*) as count from Swimmer";
	my $query2 = "Select Count(Distinct SwimmerId) as count from Points " .
		"Where TotalPoints > 0";
	my ($num, $numWithPoints);

	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query1, "" );
	$num = $sth->fetchrow_hashref->{'count'};
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query2, "" );
	$numWithPoints = $sth->fetchrow_hashref->{'count'};

	return ($num, $numWithPoints);
} # end of GetNumberOfSwimmers()


#	if( AgeGroupsClose( $ageGroup, $ageGroup1 ) ) {
# AgeGroupsClose - return true if the two passed age groups are next to each other (or the same),
#	false otherwise.
#
# PASSED:
#	$ageGroup1 - in the form "18-24"
#	$ageGroup2 -
#	
# RETURNED:
#	0 if the age groups are not close, 1 if they are.
#
sub AgeGroupsClose($$) {
	 my($ageGroup1,$ageGroup2) = @_;
	 my $result = 0;		# assume the two ageGroups are NOT next to each other
	 
	 if( $ageGroup1 eq $ageGroup2 ) {
	 	$result = 1;
	 } else{
	 	my $high1 = $ageGroup1;
	 	$high1 =~ s/^.*-//;
	 	my $high2 = $ageGroup2;
	 	$high2 =~ s/^.*-//;
	 	if( ($high1+5 == $high2) || ($high1-5 == $high2) ) {
	 		$result = 1;
	 	}
	 return $result;
	 }
} # end of AgeGroupsClose()




#  MySqlEscape( $string )
# MySqlEscape - escape imbedded quotes in the passed string making the returned
#	string acceptable as a value in a SQL INSERT statement
sub MySqlEscape( $ ) {
	my $string = $_[0];
	$string =~ s/"/\\"/g;
	$string =~ s/\\/\\/g;
	return $string;
} # end of MySqlEscape()




# ($regNum, $teamInitials, $firstName, $middleInitial, $lastName) = 
#						TT_MySqlSupport::GetDetailsFromFullName( $fileName, $lineNum, $fullName,
#						$team, $ageGroup, "Error if not found" );
# GetDetailsFromFullName - get some swimmer details (regnum, etc) using their full name.
#
# PASSED:
#	$fileName - the result file from which we got their full name
#	$lineNum - the line number of the line containing their full name
#	$fullName - their full name
#	$team - the team initials of the team they swam for (in results), or "" if not known.
#	$ageGroup - their age group
#	$org - PAC or USMS
#	$course - SCY, SCM, LCM
#	$errorFlag - TRUE if we flag an error if we can't find the swimmer; FALSE otherwise.
#
# RETURNED:
#	$regNum - the swimmer's reg num, or "" if the swimmer is not found
#	$teamInitials - the team the swimmer is registered with, or "" if the swimmer is not found
#	$firstName - 
#	$middleInitial -
#	$lastName -
#
# NOTES:
#	There are a few problems we deal with:
#	1) parsing a full name into their first, middle initial, and last names is a heuristic.  
#		EXAMPLES (from real data):  
#			Sarah Jane Sapiano  :	first: "Sarah Jane"   Last: "Sapiano"
#			Miek Mc Cubbin		:	first: "Miek"		  Last: "Mc Cubbin"
#	2) what do we do if we find the same name twice in the RSIDN table?
#
sub GetDetailsFromFullName( $$$$$$$$ ) {
	my ($fileName, $lineNum, $fullName, $team, $ageGroup, $org, $course, $errorFlag) =  @_;
	my @regNum = ();
	my @teamInitials = ();
	my @DOB = ();		# in the form yyyy-mm-dd, e.g. 1979-09-08
	my @firstName = ();
	my @middleInitial = ();
	my @lastName = ();
	my ($returnedFirstName, $returnedMiddleInitial, $returnedLastName) = ("","","");
	my ($returnedRegNum, $returnedTeamInitials) = ("", "");
	my $yearBeingProcessed = PMSStruct::GetMacrosRef()->{"YearBeingProcessed"};
	
	# break the $fullName into first, middle, and last names
	my @arrOfBrokenNames = BreakFullNameIntoBrokenNames( $fileName, $lineNum, $fullName );
	
	# now march through the various name possibilities and see if we can find this swimmer in the RSIDN
	for( my $nameIndex = 0; $nameIndex < scalar @arrOfBrokenNames; $nameIndex++ ) {
		my $hashRef = $arrOfBrokenNames[$nameIndex];
		# see if this set of first/middle/last names matches a name in our RSIDN table
		TT_MySqlSupport::GetRegnumFromName( $fileName, $lineNum, 
			$hashRef->{'first'}, $hashRef->{'middle'}, $hashRef->{'last'}, "ignore empty middle initial",
			\@regNum, \@teamInitials, \@DOB, \@firstName, \@middleInitial, \@lastName );
	}
	
	# we're done trying all the different possibilities for this swimmer's name.  If we have exactly one 
	# match in the RSIDN table then we're good.  If we have 0 then this swimmer isn't a PAC swimmer.
	# If we have more than one match then the full name is ambiguous and matches more than one PAC
	# swimmer, thus we don't know who to award points to.  In that case we're going to try another
	# heuristic.
	if( scalar @regNum > 0 ) {
		# we've found a PMS name!
		if( scalar @regNum > 1 ) {
			# we've got more than one swimmer with this name!  See if we can narrow it down to one
			# swimmer.  This may not be correct but it usually is...
			# What we'll do is try to find this swimmer in the RSIDN file by comparing not only their
			# name but also their team (team in results == team in RSIDN) and age group (age group in
			# the results == age group based on DOB in RSIDN).  Complications:
			#	- their team may not be in the results!
			#	- their age (thus age group) in results may not be their age computed based on the DOB
			#		in RSIDN because we're computing age group based on TODAY.  We should fix this and compute
			#		based on date of result if available. 
			for( my $i = 0; $i < scalar @regNum; $i++ ) {
				my $registeredAgeGroup = ComputeAgeGroupFromDOB( $DOB[$i] );
				if( (($team && ($teamInitials[$i] eq $team)) || (!$team)) && # team in results == team in RSIND, OR no team in results
					(AgeGroupsClose( $ageGroup, $registeredAgeGroup )) ) {
					# we're going to assume that this swimmer is the swimmer we're looking for, because
					# not only does the name match, but also the team (if one was supplied in the results)
					# and age group matches.
					if( $returnedRegNum ne "" ) {
						# oops!!! we've actually got 2 or more instances of the same name and team and
						# age group!  We STILL don't know who gets the points!
						#### UPDATED 10DEC2021: If these 2 (or more instances) have the same SwimmerId, then
						# we can assume they are the same person. This happens near the end of the year, 
						# when we have 2 registrations for the same person (e.g. registered 5jan2021 for 2021, 
						# and also 25Nov2021 for 2022. We have to merge the RSIND file for 2021 with that containing
						# registrations for 2022 since the latter has members who are now 2021 and 2022 members), 
						# so multiple people with the same SwimmerId are the same person.
						my $swimmerId_I = $regNum[$i];
						$swimmerId_I =~ s/^.*-//;
						my $swimmerIdReg = $returnedRegNum;
						$swimmerIdReg =~ s/^.*-//;
						if( $swimmerId_I eq $swimmerIdReg ) {
							# So far these "two" swimmers appear to be the same ... keep going
						} else {
							($returnedFirstName, $returnedMiddleInitial, $returnedLastName) = ("","","");
							($returnedRegNum, $returnedTeamInitials) = ("", "");
							last;
						}
					}
					$returnedRegNum = $regNum[$i];
					$returnedTeamInitials = $teamInitials[$i];
					$returnedFirstName = $firstName[$i];
					$returnedMiddleInitial = $middleInitial[$i];
					$returnedLastName = $lastName[$i];

					# we're going to log and remember this, but it's only a warning now...
					my $count = $DuplicateNamesCorrected{$fullName};
					if( !defined $count ) {
						$count = 0;
						PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::GetDetailsFromFullName(): " .
							"Found multiple swimmers (" .
							scalar @regNum . ") with the name '$fullName'" .
							"\n    BUT resolved using team in results [$team] vs team via RSIDN_$yearBeingProcessed " .
							"[$teamInitials[$i]] ".
							"and age group in results [$ageGroup] vs age group via RSIDN_$yearBeingProcessed " .
							"[$registeredAgeGroup, age=$DOB[$i]].  " .
							"\n    Example result:  File: '$fileName', line: '$lineNum'" .
							"\n    This is a WARNING only, which means that this swimmer will get points " .
							"for this swim even though it's possible that our assumption is wrong." .
							"\n    Returned RegNum=$returnedRegNum, name=$returnedFirstName " .
							"$returnedMiddleInitial $returnedLastName", 1 );
					}
					$DuplicateNamesCorrected{$fullName} = $count+1;
					# remember the org and course we're seeing this problem in.  
					# $DuplicateNamesCorrected{"$fullName:OrgCourse"} is of the form:
					#    org:course[,org:course:...]
					if( !defined $DuplicateNamesCorrected{"$fullName:OrgCourse"} ) {
						$DuplicateNamesCorrected{"$fullName:OrgCourse"} = "$ageGroup;$org:$course";
					} elsif( $DuplicateNamesCorrected{"$fullName:OrgCourse"} !~ m/$org:$course/ ) {
						$DuplicateNamesCorrected{"$fullName:OrgCourse"} .= ",$org:course";
					}
				}
			}
			# at this point we've either resolved the ambiguity and have exactly one reg num, etc, or we
			# haven't, and have no regNum to return.
			if( $returnedRegNum eq "" ) {
				# Only log this error once per person, but keep track of the number of errors this person
				# has caused:
				my $count = $DuplicateNames{$fullName};
				if( !defined $count ) {
					$count = 0;
					PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::GetDetailsFromFullName(): Found multiple swimmers (" .
						scalar @regNum . ") with " .
						"the name '$fullName'.  " .
						"\n    Example result:  File: '$fileName', line: '$lineNum'" .
						"\n    This is FATAL, which means that this swimmer will NOT get any points " .
						"for this swim and any other swims attributed to a " .
						"\n    swimmer with this name UNLESS we get their Swimmer ID.", 1 );
				}
				$DuplicateNames{$fullName} = $count+1;
				# remember the org and course we're seeing this problem in.  
				# $DuplicateNames{"$fullName:OrgCourse"} is of the form:
				#    org:course[,org:course:...]
				if( !defined $DuplicateNames{"$fullName:OrgCourse"} ) {
					$DuplicateNames{"$fullName:OrgCourse"} = "$ageGroup;$org:$course";
				} elsif( $DuplicateNames{"$fullName:OrgCourse"} !~ m/$org:$course/ ) {
					$DuplicateNames{"$fullName:OrgCourse"} .= ",$org:$course";
				}
			}
		} # scalar @regNum > 1
		else {
			# scalar @regNum == 1
			$returnedRegNum = $regNum[0];
			$returnedTeamInitials = $teamInitials[0];
			$returnedFirstName = $firstName[0];
			$returnedMiddleInitial = $middleInitial[0];
			$returnedLastName = $lastName[0];
		}
	} # scalar @regNum > 0
	else {
		# scalar @regNum == 0
		# this name wasn't found at all - no regNum to return, ...
		if( ! $errorFlag ) {
			# We are going to keep track of these people, but the caller does not consider this an error,
			# so we won't log an error.
			my $count = $UnableToFindInRSIDN_WARNING{$fullName};
			$count = 0 if( !defined $count );
			$UnableToFindInRSIDN_WARNING{$fullName} = $count+1;
			# remember the org and course we're seeing this problem in.  
			# $UnableToFindInRSIDN_WARNING{"$fullName:OrgCourse"} is of the form:
			#    org:course[,org:course:...]
			if( !defined $UnableToFindInRSIDN_WARNING{"$fullName:OrgCourse"} ) {
				$UnableToFindInRSIDN_WARNING{"$fullName:OrgCourse"} = "$ageGroup;$org:$course";
			} elsif( $UnableToFindInRSIDN_WARNING{"$fullName:OrgCourse"} !~ m/$org:$course/ ) {
				$UnableToFindInRSIDN_WARNING{"$fullName:OrgCourse"} .= ",$org:$course";
			}
		} else {
			# The caller considers this an error so we'll log it.
			# However, only log this error once per person, but keep track of the number of errors this person
			# has caused:
			my $count = $UnableToFindInRSIDN{$fullName};
			if( !defined $count ) {
				$count = 0;
				PMSLogging::DumpError( "", "", "TT_MySqlSupport::GetDetailsFromFullName(): Can't find regnum for swimmer '$fullName'.  " .
					"File: '$fileName', line: '$lineNum'" .
					"\n    This is FATAL, which means that this swimmer will NOT get any points " .
					"for this swim.", 1 );
			}
			$UnableToFindInRSIDN{$fullName} = $count+1;
			# remember the org and course we're seeing this problem in.  
			# $UnableToFindInRSIDN{"$fullName:OrgCourse"} is of the form:
			#    org:course[,org:course:...]
			if( !defined $UnableToFindInRSIDN{"$fullName:OrgCourse"} ) {
				$UnableToFindInRSIDN{"$fullName:OrgCourse"} = "$ageGroup;$org:$course";
			} elsif( $UnableToFindInRSIDN{"$fullName:OrgCourse"} !~ m/$org:$course/ ) {
				$UnableToFindInRSIDN{"$fullName:OrgCourse"} .= ",$org:$course";
			}
		}
	}
	
	return ($returnedRegNum, $returnedTeamInitials, $returnedFirstName, $returnedMiddleInitial, $returnedLastName);
} # end of GetDetailsFromFullName()





# TT_MySqlSupport::GetRegnumFromName( $fileName, $lineNum, 
#	$hashRef->{'first'}, $hashRef->{'middle'}, $hashRef->{'last'}, 1,
#		\@regNum, \@teamInitials, \@DOB, \@firstName, \@middleInitial, \@lastName );

# GetRegnumFromName - get the swimmer's regnum using their name to look them up in the RSIDN table.
#
# PASSED:
#	$fileName - the full path file name of the result file being processed
#	$lineNum - the line number of the line being processed
#	$firstName - swimmer's first name
#	$middleInitial - swimmer's middle initial, or an empty string ("")
#	$lastName - swimmer's last name
#	$optionalMiddle - if true then the middle initial in
#		the RSIDN file doesn't have to match the passed $middleInitial IF the passed
#		$middleInitial is ""
#	$regNumArrRef - reference to an array into which is added any reg nums found for this swimmer.
#	$teamInitialsArrRef - reference to an array into which is added any teams found for this swimmer.
#	$DOBArrRef - reference to an array into which is added any birthdates found for this swimmer.
#	$firstNameArrRef - 
#	$middleInitialArrRef -
#	$lastNameArrRef -
#
# RETURNED:
#	The arrays referenced by *ArrRef may be updated by this 
#	routine if one or more swimmers are found with the passed name.
#
# NOTES:
#	If the passed name is found more than once in the RSIDN table then we have an ambiguous situation.
#	In that case we'll return the data for ALL swimmers who have the matching name and let the
#	caller decide what to do.
#
sub GetRegnumFromName() {
	my($fileName, $lineNum, $firstName, $middleInitial, $lastName,$optionalMiddle,
		$regNumArrRef, $teamInitialsArrRef, $DOBArrRef, $firstNameArrRef, $middleInitialArrRef,
		$lastNameArrRef) = @_;
	my $regNum = "";
	my $teamInitials = "";
	my $resultHash;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $middleSql = "AND MiddleInitial = \"$middleInitial\"";
	my $yearBeingProcessed = PMSStruct::GetMacrosRef()->{"YearBeingProcessed"};

	if( $optionalMiddle && ($middleInitial eq "") ) {
		# query does NOT depend on middle initial
		$middleSql = "";
	}
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"SELECT RegNum,RegisteredTeamInitialsStr,DateOfBirth " .
		"FROM RSIDN_$yearBeingProcessed " .
		"WHERE FirstName = \"$firstName\" $middleSql AND LastName = \"$lastName\"" );
	my $numSwimmers = $sth->rows();
	# did we find one or more rows in the RSIDN table that could represent the swimmer we're looking for?
	if( $numSwimmers > 0 ) {
		# yes!  Add to the passed arrays.
		while( $resultHash = $sth->fetchrow_hashref ) {
			push @$regNumArrRef, $resultHash->{'RegNum'};
			push @$teamInitialsArrRef, $resultHash->{'RegisteredTeamInitialsStr'};
			push @$DOBArrRef, $resultHash->{'DateOfBirth'};
			push @$firstNameArrRef, $firstName;
			push @$middleInitialArrRef, $middleInitial;
			push @$lastNameArrRef, $lastName;
		}
	}
} # end of GetRegnumFromName()


# 				my $registeredAgeGroup = ComputeAgeGroupFromDOB( $DOB[$i] );
# ComputeAgeGroupFromDOB - the name says it all
#
# PASSED:
#	$dob - in the form yyyy-mm-dd
#
# RETURNED:
#	$ageGroup - in the form 18-24
#
sub ComputeAgeGroupFromDOB( $ ) {
	my $ageGroup = "";
	my $dob = $_[0];		# in the form yyyy-mm-dd
	my $yearOfBirth = $dob;
	$yearOfBirth =~ s/-.*$//;
	my $yearBeingProcessed = PMSStruct::GetMacrosRef()->{"YearBeingProcessed"};
	my $yearDiff = $yearBeingProcessed - $yearOfBirth + 1;
	if( ($yearDiff >= 18) && ($yearDiff <= 24) ) {
		$ageGroup = "18-24";
	} else {
		my $temp = int($yearDiff/5);
		my $lower = $temp*5;
		my $upper = $lower+4;
		$ageGroup = "$lower-$upper";
	}
	return $ageGroup;	
} # end of ComputeAgeGroupFromDOB()



# my @arrOfBrokenNames = BreakFullNameIntoBrokenNames( $fullName );
# BreakFullNameIntoBrokenNames - break the $fullName into first, middle, and last names
#	(If the middle initial is not supplied then use "")
#
# Passed:
#	$fileName - the name of the file being processed (for error messages)
#	$lineNum - the line of the file being processed (for error messages)
#	$fullName - a string of the form "name1 name2 name3....nameN" where N is 1 or greater.
#
# Return an array of hashes:
#	arr[n]->{'first'} is a possible first name
#	arr[n]->{'middle'} is the matching possible middle initial
#	arr[n]->{'last'} is the matching possible last name
#	arr[n+1]->{'first'} is another possible first name
#	arr[n+1]->{'middle'} is the matching possible middle initial
#	arr[n+1]->{'last'} is the matching possible last name
#	
# Return an empty array upon error.
#
sub BreakFullNameIntoBrokenNames($$$) {
	my ($fileName, $lineNum, $fullName) = @_;
	my @arrOfNames = split( /\s+/, $fullName );
	my @result = ();
	my $namesRef;		# reference to hash of names
	
	if( scalar(@arrOfNames) == 2 ) {
		# assume first and last name (only)
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0];
		$namesRef->{'middle'} = "";
		$namesRef->{'last'} =  $arrOfNames[1];
		$result[0] = $namesRef;
	} elsif( scalar(@arrOfNames) == 3 ) {
		# assume first, middle, last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0];
		$namesRef->{'middle'} =  $arrOfNames[1];
		# make sure middle initial is only 1 char
		$namesRef->{'middle'} =~ s/^(.).*$/$1/;
		$namesRef->{'last'} =  $arrOfNames[2];
		$result[0] = $namesRef;
		# assume first first, last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0] . " " . $arrOfNames[1];
		$namesRef->{'middle'} = "";
		$namesRef->{'last'} =  $arrOfNames[2];
		$result[1] = $namesRef;
		# assume first, last last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0];
		$namesRef->{'middle'} = "";
		$namesRef->{'last'} =   $arrOfNames[1] . " " . $arrOfNames[2];
		$result[2] = $namesRef;
	} elsif( scalar(@arrOfNames) == 4 ) {
		# assume first, middle, last last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0];
		$namesRef->{'middle'} =  $arrOfNames[1];
		# make sure middle initial is only 1 char
		$namesRef->{'middle'} =~ s/^(.).*$/$1/;
		$namesRef->{'last'} =  $arrOfNames[2] . " " . $arrOfNames[3];
		$result[0] = $namesRef;
		# assume first first, middle, last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0] . " " . $arrOfNames[1];
		$namesRef->{'middle'} =  $arrOfNames[2];
		# make sure middle initial is only 1 char
		$namesRef->{'middle'} =~ s/^(.).*$/$1/;
		$namesRef->{'last'} =  $arrOfNames[3];
		$result[1] = $namesRef;
		# assume first first first, last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0] . " " . $arrOfNames[1] . " " . $arrOfNames[2];
		$namesRef->{'middle'} =  "";
		$namesRef->{'last'} =  $arrOfNames[3];
		$result[2] = $namesRef;
		# assume first, last last last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0];
		$namesRef->{'middle'} =  "";
		$namesRef->{'last'} =  $arrOfNames[1] . " " . $arrOfNames[2] . " " . $arrOfNames[3];
		$result[3] = $namesRef;
	} elsif( scalar(@arrOfNames) == 5 ) {
		# assume first, middle, last last last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0];
		$namesRef->{'middle'} =  $arrOfNames[1];
		# make sure middle initial is only 1 char
		$namesRef->{'middle'} =~ s/^(.).*$/$1/;
		$namesRef->{'last'} =  $arrOfNames[2] . " " . $arrOfNames[3] . " " . $arrOfNames[4];
		$result[0] = $namesRef;
		# assume first first, middle, last, last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0] . " " . $arrOfNames[1];
		$namesRef->{'middle'} =  $arrOfNames[2];
		# make sure middle initial is only 1 char
		$namesRef->{'middle'} =~ s/^(.).*$/$1/;
		$namesRef->{'last'} =  $arrOfNames[3] . " " . $arrOfNames[4];
		$result[1] = $namesRef;
		# assume first first first, last, last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0] . " " . $arrOfNames[1] . " " . $arrOfNames[2];
		$namesRef->{'middle'} =  "";
		$namesRef->{'last'} =  $arrOfNames[3] . " " . $arrOfNames[4];
		$result[2] = $namesRef;
		# assume first, first, last last last
		$namesRef = {};
		$namesRef->{'first'} =  $arrOfNames[0] . " " . $arrOfNames[1];
		$namesRef->{'middle'} =  "";
		$namesRef->{'last'} =  $arrOfNames[2] . " " . $arrOfNames[3] . " " . $arrOfNames[4];
		$result[3] = $namesRef;
		# there are more....
	} else {
		# the name supplied wasn't empty but also didn't look like what we expected...
		# Generate an error so we investigate.
		PMSLogging::DumpWarning( "", "", "BreakFullNameIntoBrokenNames(): Unrecognized format for the full name ['$fullName']. " .
			" File: '$fileName', line num: $lineNum", 1 );
	}

	return @result;

} # end of BreakFullNameIntoBrokenNames()




# DumpErrorsWithSwimmerNames - log various errors we discovered while processing results.
#
# NOTES:
#	Uses various module-scoped hash tables to store the different kinds of errors we discovered.
#
sub DumpErrorsWithSwimmerNames() {
	my $yearBeingProcessed = PMSStruct::GetMacrosRef()->{"YearBeingProcessed"};
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();

	PMSLogging::PrintLog( "", "", "** Begin DumpErrorsWithSwimmerNames", 1 );

	if( my $size = scalar keys %UnableToFindInRSIDN ) {
		$size /= 2;		# divide size by two since a hash has 2 elememts per swimmer (key and value)
		# dump out the names of all swimmers that we think we should have found in the RSIDN that we didn't find
		PMSLogging::PrintLog( "", "", "\nTT_MySqlSupport::DumpErrorsWithSwimmerNames(): The following $size " .
			"swimmers SHOULD be PAC swimmers but are not in our RSIDN_$yearBeingProcessed table.\n" .
			"    They did not get any points:" );
		foreach my $key (keys %UnableToFindInRSIDN) {
			next if( $key =~ m/OrgCourse/ );
			PMSLogging::PrintLog( "", "", "    '$key' (appeared in " . $UnableToFindInRSIDN{$key} . 
				" results [" . $UnableToFindInRSIDN{"$key:OrgCourse"} . "])" );
		}
	}

	if( my $size = scalar keys %DuplicateNames ) {
		$size /= 2;		# divide size by two since a hash has 2 elememts per swimmer (key and value)
		# dump out the names of all swimmers that we found in the results but when looking them up we
		# found that their name matched 2 or more swimmers, thus we didn't know who to give the point to.
		PMSLogging::PrintLog( "", "", "\nTT_MySqlSupport::DumpErrorsWithSwimmerNames(): The following $size " .
			"swimmers appeared by name more than once in our RSIDN_$yearBeingProcessed table,\n" .
			"    thus we didn't know who to award points to (points were NOT awarded in these cases):" );
		foreach my $key (keys %DuplicateNames) {
			next if( $key =~ m/OrgCourse/ );
			PMSLogging::PrintLog( "", "", "    '$key' (appeared in " . $DuplicateNames{$key} . 
				" results [" . $DuplicateNames{"$key:OrgCourse"} . "])" );
		}
	}

	if( my $size = scalar keys %DuplicateNamesCorrected ) {
		$size /= 2;		# divide size by two since a hash has 2 elememts per swimmer (key and value)
		# dump out the names of all swimmers that we found in the results but when looking them up we
		# found that their name matched 2 or more swimmers, although we dis-ambiguated their names.
		PMSLogging::PrintLog( "", "", "\nTT_MySqlSupport::DumpErrorsWithSwimmerNames(): The following $size " .
			"swimmers appeared by name more than once in our RSIDN_$yearBeingProcessed table,\n" .
			"    but we narrowed them down to one swimmer using their DOB and team and gave them points:" );
		foreach my $key (keys %DuplicateNamesCorrected) {
			next if( $key =~ m/OrgCourse/ );
			PMSLogging::PrintLog( "", "", "    '$key' (appeared in " . $DuplicateNamesCorrected{$key} . 
				" results [" . $DuplicateNamesCorrected{"$key:OrgCourse"} . "])" );
		}
	}
	
	if( my $size = scalar keys %UnableToFindInRSIDN_WARNING ) {
		$size /= 2;		# divide size by two since a hash has 2 elememts per swimmer (key and value)
		# dump out the names of all swimmers that we didn't find in the RSIDN table but handled as a warning only
		PMSLogging::PrintLog( "", "", "\nTT_MySqlSupport::DumpErrorsWithSwimmerNames(): The following $size " .
			"swimmers were not in our RSIDN_$yearBeingProcessed table\n" .
			"but this is only a WARNING " .
			"since we don't know if they are supposed to be PAC swimmers.\n" .
			"They did NOT get points:" );
		foreach my $key (keys %UnableToFindInRSIDN_WARNING) {
			next if( $key =~ m/OrgCourse/ );
			PMSLogging::PrintLog( "", "", "    '$key' (appeared in " . $UnableToFindInRSIDN_WARNING{$key} . 
				" results [" . $UnableToFindInRSIDN_WARNING{"$key:OrgCourse"} . "])" );
		}
	}
	
	if( my $size = (scalar keys %TT_Struct::hashOfInvalidRegNums) ) {
		$size /= 2;		# divide size by two since a hash has 2 elememts per swimmer (key and value)
		# When analyzing a PMS top ten result we got from that result the swimmer's name and their 
		# reg num.  We then looked up their swimmer id in the RSIDN table to make sure the name
		# was correct, but if we couldn't find a swimmer with that swimmer id with a PMS reg num
		# then we remembered it.  We'll log it here.  This is fatal - the swimmer DID NOT get points.
		PMSLogging::PrintLog( "", "", "\nTT_MySqlSupport::DumpErrorsWithSwimmerNames(): The following $size " .
			"reg numbers were not in our RSIDN_$yearBeingProcessed table\n" .
			"but were used to identify " .
			"a swimmer in the PMS Top Ten results.\n" .
			"This is FATAL - the swimmer DID NOT get any points." );
		foreach my $key (keys %TT_Struct::hashOfInvalidRegNums) {
			next if( $key =~ m/OrgCourse/ );
			PMSLogging::PrintLog( "", "", "    '$key' (appeared in " . $TT_Struct::hashOfInvalidRegNums{$key} . 
				" results [" . $TT_Struct::hashOfInvalidRegNums{"$key:OrgCourse"} . "])" );
		}
	}
	
	PMSLogging::PrintLog( "", "", "** End DumpErrorsWithSwimmerNames", 1 );
	
} # end of DumpErrorsWithSwimmerNames()


# DumpStatsFor2GroupSwimmers - generate a HTML file giving stats for every swimmer who is in two
#		different age groups during this season.
#
# PASSED:
#	$fullFileName - the name of the HTML file we're construct.
#
# NOTE:  POINTS AND PLACE MUST HAVE BEEN ALREADY COMPUTED!!
#
sub DumpStatsFor2GroupSwimmers( $ ) {
	my( $fullFileName, $generationDate ) = @_;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	# html colors we're using:
	my $CagIsBest = '33ff40';
	my $CagIsBestOrEqual = '33d7ff';
	my $CagIsntBest = 'fffe33';
	my $numCagIsBest = 0;
	my $numCagIsBestOrEqual = 0;
	my $numCagIsntBest = 0;

	PMSLogging::PrintLog( "", "", "** Begin DumpStatsFor2GroupSwimmers", 1 );

	# open/create the CAG file:
	open( my $fileHandle, ">", $fullFileName ) or
		die( "Can't open $fullFileName: $!" );
		
	# add the initial HTML stuff to the CAG file:
	print $fileHandle <<"BUp1";
<html>
<head>
	<title>Split Age Groups</title>
	<link rel="stylesheet" type="text/css" href="Support/Standings.css">
	<script type="text/javascript" src="Support/jquery-1.11.3.min.js"></script> 
	<script type="text/javascript" src="Support/jquery.floatThead.min.js"></script>
	<script type="text/javascript" src="Support/Standings.js"></script>

<style>
	table,th,td {
		border: 1px solid black;
		width: 5em;
	}
</style>
</head>
<body>
<div id="MainContentDiv" align="left"> <!-- Main Content div -->
<center>
<a href="/"><img src="Support/horizontal-logo.jpg" height="134" border="0" width="320"></a>
</center>
<p>&nbsp;</p>
<h1 style="text-align:center">Split Age Groups</h1>
<h2 style="text-align:center">Bob Upshaw</h2>
<h2 style="text-align:center">Generated on $generationDate</h2>

<h2>Key:</h2>
<blockquote>
	<span style='background-color: $CagIsBest'>Swimmers who place HIGHER when combining age groups</span>
	<br><span style='background-color: $CagIsBestOrEqual'>Swimmers who place HIGHER or the SAME when combining age groups</span>
	<br><span style='background-color: $CagIsntBest'>Swimmers who place LOWER when combining age groups</span>
</blockquote>
<table class='Category' style='table-layout:fixed'>
	<thead>
	<tr>
		<th style='text-align:center;width:2em'>No.</th>
		<th style='width:10em'>Name</th>
		<th style='width:4em'>Gender</th>
		<th>Age Group 1</th>
		<th style='width:4em'>Points</th>
		<th style='width:4em'>Place</th>
		<th># Results Used</th>
		<th># Results Analyzed</th>
		<th>Age Group 2</th>
		<th style='width:4em'>Points</th>
		<th style='width:4em'>Place</th>
		<th># Results Used</th>
		<th># Results Analyzed</th>
		<th>CAG</th>
		<th>Combined Points</th>
		<th>Combined Place</th>
		<th># Results Used</th>
		<th># Results Analyzed</th>
		<th style='width:4em'>Sid</th>
	</tr>
	</thead>
BUp1

	# Now, get all swimmers in split age groups and compute the stats:
	my $query = "SELECT SwimmerId, AgeGroup1, AgeGroup2, FirstName, MiddleInitial, LastName, Gender " .
		"FROM  Swimmer WHERE Swimmer.AgeGroup2 != '' ORDER BY SwimmerId";
	my($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	my $numSwimmers = $sth->rows();
	
	my( $swimmerId, $firstName, $middleInitial, $lastName, $fullName, $gender, $ageGroup1, $ageGroup2 );
	my( $points1, $points2, $place1, $place2, $combinedPoints, $combinedPlace );
	my( $numResults1, $numResults2, $numResultsCombined );
	my( $totalResultsAnalyzed1, $totalResultsAnalyzed2, $totalResultsAnalyzedCombined );

	# dump out the names and stats of all swimmers that were in 2 age groups
	my $num = 0;
	while( my $resultHash = $sth->fetchrow_hashref ) {
		$num++;
		$swimmerId = $resultHash->{'SwimmerId'};
		$firstName = $resultHash->{'FirstName'};
		$middleInitial = $resultHash->{'MiddleInitial'};
			$middleInitial .= " " if( $middleInitial ne "" );
		$lastName = $resultHash->{'LastName'};
		$fullName = "$firstName ${middleInitial}$lastName";
		my $gender = $resultHash->{'Gender'};
		my $ageGroup1 = $resultHash->{'AgeGroup1'};
		my $ageGroup2 = $resultHash->{'AgeGroup2'};
		
		# get all the points for this swimmer in all org and course, for only $ageGroup1
		($points1, $numResults1, $totalResultsAnalyzed1) = 
			GetPointsForSwimmer( $swimmerId, $ageGroup1 );
		$place1 = GetPlaceForSwimmer( $swimmerId, $ageGroup1 );
		
		# get all the points for this swimmer in all org and course, for only $ageGroup2
		($points2, $numResults2, $totalResultsAnalyzed2) = 
			GetPointsForSwimmer( $swimmerId, $ageGroup2 );
		$place2 = GetPlaceForSwimmer( $swimmerId, $ageGroup2 );
		
		# get all the points for this swimmer in all org and course, for both age groups combined
		($combinedPoints, $numResultsCombined, $totalResultsAnalyzedCombined) = 
			GetPointsForSwimmer( $swimmerId, "$ageGroup1:$ageGroup2" );
		$combinedPlace = GetPlaceForSwimmer( $swimmerId, "$ageGroup1:$ageGroup2" );

		# we've got our stats for this single swimmer - help with some formatting:
		my $color = 'FFFFFF';		# white
		if( ($combinedPlace < $place1) && ($combinedPlace < $place2) ) {
			$color = $CagIsBest;
			$numCagIsBest++;
		} elsif( ($combinedPlace <= $place1) && ($combinedPlace <= $place2) ) {
			$color = $CagIsBestOrEqual;
			$numCagIsBestOrEqual++;
		} elsif( ($combinedPlace > $place1) || ($combinedPlace > $place2) ) {
			$color = $CagIsntBest;
			$numCagIsntBest++;
		}
		$place1 = '-' if( $place1 == 9999 );
		$place2 = '-' if( $place2 == 9999 );
		$combinedPlace = '-' if( $combinedPlace == 9999 );
		
		# Now we generate the stats in HTML for this swimmer:
		print $fileHandle <<"BUp2";
	<tr style='background-color: $color'>
		<td style='text-align:center'>$num</td>
		<td style='width:10em'>$fullName</td>
		<td style='text-align:center'>$gender</td>
		<td style='text-align:center'>$ageGroup1</td>
		<td style='text-align:center'>$points1</td>
		<td style='text-align:center;background-color:ff7b33'>$place1</td>
		<td style='text-align:center'>$numResults1</td>
		<td style='text-align:center'>$totalResultsAnalyzed1</td>
		<td style='text-align:center'>$ageGroup2</td>
		<td style='text-align:center'>$points2</td>
		<td style='text-align:center;background-color:ff7b33''>$place2</td>
		<td style='text-align:center'>$numResults2</td>
		<td style='text-align:center'>$totalResultsAnalyzed2</td>
		<td style='text-align:center'>$ageGroup1:$ageGroup2</td>
		<td style='text-align:center'>$combinedPoints</td>
		<td style='text-align:center;background-color:ff7b33''>$combinedPlace</td>
		<td style='text-align:center'>$numResultsCombined</td>
		<td style='text-align:center'>$totalResultsAnalyzedCombined</td>
		<td style='text-align:center'>$swimmerId</td>
	</tr>

BUp2
	} # end of while( my $resultHash = $sth->fetchrow_hashref...

	# Finish up our HTML file:
	print $fileHandle "</table>\n<p>\n";
	print $fileHandle "<br><span style='background-color: $CagIsBest'># of Swimmers who place HIGHER when combining age groups: $numCagIsBest</span>\n";
	print $fileHandle "<br><span style='background-color: $CagIsBestOrEqual'># of Swimmers who place HIGHER or the SAME when combining age groups: $numCagIsBestOrEqual\n";
	print $fileHandle "<br><span style='background-color: $CagIsntBest'># of Swimmers who place LOWER when combining age groups: $numCagIsntBest\n";
	print $fileHandle "</body>\n</html>\n";
	close $fileHandle;

	PMSLogging::PrintLog( "", "", "** End DumpStatsFor2GroupSwimmers", 1 );
} # end of DumpStatsFor2GroupSwimmers()




#		($points, $numResults, $totalResultsAnalyzed) = GetPointsForSwimmer( $swimmerId, $ageGroup );
# GetPointsForSwimmer - return the points and other stats for the passed swimmer when in the passed
#	age group.
#
# PASSED:
#	$swimmerId - the swimmer
#	$ageGroup - of the form "18-24" or "18-24:25-29".  In the latter case we combine the swimmer's
#		points from the two age groups, eliminating points for duplicate events.
#
# RETURNED:
#	$points -
#	$numResults - number of results used to derive the returned $points
#	$totalResultsAnalyzed - number of results read (but not necessarily used) when computing the
#		returned $points.
#
# NOTE:  POINTS MUST HAVE BEEN ALREADY COMPUTED!!
sub GetPointsForSwimmer( $$ ) {
	my( $swimmerId, $ageGroup ) = @_;
	my( $points, $numResults, $totalResultsAnalyzed ) = (0,0,0);
	my $query = "SELECT SUM(TotalPoints) AS Points," .
		"SUM(ResultsCounted) AS ResultsCounted," .
		"SUM(ResultsAnalyzed) AS ResultsAnalyzed " .
		"FROM Points WHERE SwimmerId=$swimmerId and AgeGroup='$ageGroup'";
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	if( my $resultHash = $sth->fetchrow_hashref ) {
		$points = $resultHash->{'Points'};
		$points = 0 if( !defined $points );
		$numResults = $resultHash->{'ResultsCounted'};
		$numResults = 0 if( !defined $numResults );
		$totalResultsAnalyzed = $resultHash->{'ResultsAnalyzed'};
		$totalResultsAnalyzed = 0 if( !defined $totalResultsAnalyzed );
	} else {
		PMSLogging::DumpError( "", "", "TT_MySqlSupport::GetPointsForSwimmer(): " .
			"Failed to get Points for swimmer $swimmerId in agegroup '$ageGroup'", 1 );
	}
	return( $points, $numResults, $totalResultsAnalyzed );

} # end of GetPointsForSwimmer()





# 		$combinedPlace = GetPlaceForSwimmer( $swimmerId, "$ageGroup1:$ageGroup2" );
# GetPlaceForSwimmer - return the final AGSOTY place for the passed swimmer when in the passed
#	age group.
#
# PASSED:
#	$swimmerId - the swimmer
#	$ageGroup - of the form "18-24" or "18-24:25-29".  In the latter case we return the swimmer's
#		place for the older age group after combining their points in the two age groups, eliminating 
#		points for duplicate events.  Return 9999 if no place in the passed age group.
#	
# NOTE:  EVERY SWIMMER'S PLACE MUST HAVE BEEN ALREADY COMPUTED!!
sub GetPlaceForSwimmer( $$ ) {
	my( $swimmerId, $ageGroup ) = @_;
	my $place = 9999;
	my $finalPlaceTable = "FinalPlaceSAG";
	$finalPlaceTable = "FinalPlaceCAG" if( $ageGroup =~ m/:/ );
	my $query = "SELECT Rank FROM $finalPlaceTable WHERE SwimmerId=$swimmerId AND AgeGroup='$ageGroup'";
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query, "" );
	if( my $resultHash = $sth->fetchrow_hashref ) {
		$place = $resultHash->{'Rank'};
	}
	return $place;
	
} # end of GetPlaceForSwimmer()



# 		$points = ComputePointsForSwimmer( $swimmerId, $ageGroup );
# PASSED:
#	$swimmerId - the swimmer for whom we'll fetch their points
#	$ageGroup - Either a single age group in the form "18-24", in which case it is the age group 
#		we'll limit the points to.  Or two age groups in the form "18-24:25-29", in which case we'll
#		get the points for all age groups the swimmer competed in.
#	$displaySwimmersWithZeroPoints - 0 if we ignore swimmers who earned zero points, 1 otherwise.
#
# RETURNED:
#	$totalPoints - the total number of points this swimmer earned, taking into account the
#		various limits (e.g. no more than 8 SCY top 10 events, using the highest scores, and
#		never award points for the same event/course - if more than one always use the highest
#		points earned.)
#	$totalResultsCounted - the total number of results we used to award points
#	$totalResultsAnalyzed - the total number of results we considered but not necessarily 
# 		used (because they may have more than the limit)
#
sub ComputePointsForSwimmer( $$$ ) {
	my( $swimmerId, $ageGroup, $displaySwimmersWithZeroPoints ) = @_;
	my $query;
	my $ageGroupQuery = "";
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $totalPoints = 0;			# the total number of points this swimmer earned
	my $totalResultsCounted = 0;	# the total number of results we used to award points
	my $totalResultsAnalyzed = 0;	# the total number of results we considered but not necessarily 
									# used (because they may have more than the limit)
	if( $ageGroup !~ m/:/ ) {
		# single age group
		$ageGroupQuery = " AND Splash.AgeGroup = '$ageGroup' ";
	}
	my $debugSwimmerId = -1;
	
	# eliminage bogus messages:
	my $tempxxx1 = $PMSConstants::arrOfOrg[0];
	my $tempxxx2 = $PMSConstants::arrOfCourse[0];

	# get all the splashes for this swimmer (in the single age group supplied, if a single age
	# group was supplied) allowing us to calculate points for 
	# all swims (including open water, and pms and usms records).  We will impose the required
	# limits (e.g. no more than 8 top 10 for a particular course.)
	foreach my $org( @PMSConstants::arrOfOrg ) {
		foreach my $course( @PMSConstants::arrOfCourse ) {
			my $countOfResults = 0;		# used to check for limits (e.g. <= 8 SCY results)
			my $subTotalPoints = 0;		# of points in this org/course (and age group)
			my $subTotalResultsCounted = 0;	# of results in this org/course (and age group) used for points
			my $subTotalResultsAnalyzed = 0;# of results in this org/course (and age group) analyzed
			my %hashOfEvents = ();		# used to remove duplicates
			# $hashOfEvents{eventId-$course} = points : the swimmer swam in event # 'eventId' 
			# and course $course and earned 'points' points.  E.g. event "100 M free" LCM, 
			# earning 8 points.  Note they can also earn points in event "100 M free" SCM.
			$query = "SELECT EventId, Points, Category FROM Splash " .
				"WHERE Splash.SwimmerId = $swimmerId " .
				"AND Splash.Org = '$org' " .
				"AND Splash.Course = '$course' " .
				"AND Splash.Points > 0  " .
				$ageGroupQuery .
				"ORDER BY Points DESC";
			my($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
			while( my $resultHash = $sth->fetchrow_hashref ) {
				$subTotalResultsAnalyzed++;
				my $points = $resultHash->{'Points'};
				my $eventId = $resultHash->{'EventId'};
				my $category = $resultHash->{'Category'};
				if( $points == 0 ) {
					# the place for this swim didn't earn any points so move on...
					DontUseThesePoints( $swimmerId, $org, $course, $eventId, "(zero points)" );
					$countOfResults++;
					next;
					}
				# we have a splash that earned points - is it for an event for which they have already 
				# earned points?  If so they get the higher points
				my $previousPoints = $hashOfEvents{"$eventId-$course"};
				if( defined $previousPoints ) {
					# they earned points in this event before - if in a single age group we have a bug!
					if( $ageGroup !~ m/:/ ) {
						# single age group
						PMSLogging::DumpError( "", "", "TT_MySqlSupport::ComputePointsForSwimmer(): " .
							"Found points for the same event twice: event $eventId, course $course, " .
							"age group $ageGroup, swimmerId $swimmerId", 1 );
						# we'll ignore these POINTS
						DontUseThesePoints( $swimmerId, $org, $course, $eventId, "(Dup event-course in single age group)" );
						next;
					}
					# they earned points in this event before, and since our query returned the
					# higher points first we know that these points shouldn't be counted because
					# they are less than (or equal) to what we've already counted for this event
					# and course.
					DontUseThesePoints( $swimmerId, $org, $course, $eventId, "(Dup event-course)" );
				} elsif( ($course eq "OW") && ($category == 2) ) {
					# we don't count cat 2 OW swims
					DontUseThesePoints( $swimmerId, $org, $course, $eventId, "(Cat 2)" );
				} else {
					# we have not seen points for this event and course
					# remember these previous points:
					$countOfResults++;
					$hashOfEvents{"$eventId-$course"} = $points;
					# Now, give this swimmer these points IF we don't exceed the maximum:
					# currently limit to 8 for EVERY possible course (except records and OW and ePostal):
					if( $course eq 'OW' ) {
						if( $countOfResults <= PMSStruct::GetMacrosRef()->{"numSwimsToConsider"} ) {
							# yep - they get points for this OW splash
							$subTotalPoints += $points;
							$subTotalResultsCounted++;
						} else {
							# else they don't get points for this OW swim because they've hit the max
							# set this splash as non-point earning:
							DontUseThesePoints( $swimmerId, $org, $course, $eventId, "(Max OW scored swims)" );							
						}
					} elsif( ($course eq 'SCY Records') || 
						($course eq 'SCM Records') ||
						($course eq 'LCM Records') ||
						($course eq 'ePostal Records') ||
						($course eq 'ePostal') ) {
						# there is no limit on points for these courses:
						# increment number of points for this swimmer 
						$subTotalPoints += $points;
						$subTotalResultsCounted++;
					} else {
						# this course has a limit...
						if( $countOfResults <= 8 ) {
							# increment number of points for this swimmer 
							$subTotalPoints += $points;
							$subTotalResultsCounted++;
						} else {
							DontUseThesePoints( $swimmerId, $org, $course, $eventId, "(Max scored swims)" );							
						}
					}
				}
			} # end of while()...
			if( $displaySwimmersWithZeroPoints || ($subTotalPoints > 0) ) {
				StorePointsForSwimmer( $swimmerId, $ageGroup, $course, $org, $subTotalPoints,
					$subTotalResultsCounted, $subTotalResultsAnalyzed );
				$totalPoints += $subTotalPoints;			# the total number of points this swimmer earned
			}
		$totalResultsCounted += $subTotalResultsCounted;
		$totalResultsAnalyzed += $subTotalResultsAnalyzed;
		} # end of foreach my $course
		
	} # end of foreach my $org

	return( $totalPoints, $totalResultsCounted, $totalResultsAnalyzed );	

} # end of ComputePointsForSwimmer()



#		DontUseThesePoints( $swimmerId, $org, $course, $eventId, "(Max scored swims)" );
# DontUseThesePoints - mark the splash for the passed $org and $course and $eventId as a non-scoring
#		swim. We'll still remember the points that would have been earned.
#
# PASSED:
#	$swimmerId -
#	$org -
#	$course -
#	$eventId -
#	$reason - the reason this splash is not a scoring swim.
#
# RETURNED:
#	n/a
#
# NOTES:
#	The entry for this swim in the Splash table will be updated with the passed reason, setting
#		the UsePoints column to 0.
#
sub DontUseThesePoints( $$$$$ ) {
	my( $swimmerId, $org, $course, $eventId, $reason ) = @_;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $query = "SELECT SplashId, UsePoints FROM Splash WHERE " .
		"SwimmerId=$swimmerId AND Org='$org' AND Course='$course' AND EventId='$eventId'";
		
	my ($sth, $rv, $status) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	if( $status ne "" ) {
		PMSLogging::DumpError( "", "", "TT_MySqlSupport::DontUseThesePoints(): Failed to get splash " .
			"to update: : status='$status', org=$org, course=$course, eventId=$eventId, passed reason='$reason'.", 1);
	} elsif( defined(my $resultHash = $sth->fetchrow_hashref) ) {
		my $splashId = $resultHash->{"SplashId"};
		my $usePoints = $resultHash->{"UsePoints"};
		if( $usePoints == 0 ) {
			# this is odd....report it but ignore it.
			PMSLogging::DumpWarning( "", "", "TT_MySqlSupport::DontUseThesePoints(): UsePoints already set " .
				"to 0: swimmerId=$swimmerId, org=$org, course=$course, eventId=$eventId, passed reason='$reason'.", 1);
		}
		$query = "UPDATE Splash SET UsePoints = 0, Reason = '$reason' WHERE SplashId=$splashId";
		($sth, $rv, $status) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
		if( $status ne "" ) {
			PMSLogging::DumpError( "", "", "TT_MySqlSupport::DontUseThesePoints(): Failed to UPDATE " .
				"Splash: status='$status', swimmerId=$swimmerId, org=$org, course=$course, eventId=$eventId, passed reason='$reason'.", 1);
		}
	} else {
		PMSLogging::DumpError( "", "", "TT_MySqlSupport::DontUseThesePoints(): Failed to get splash " .
			"to update: empty result: org=$org, course=$course, eventId=$eventId, passed reason='$reason'.", 1);
	}

} # end of DontUseThesePoints()





# 	StorePointsForSwimmer( $swimmerId, $ageGroup, $course, $org, $subTotalPoints,
#				$subTotalResultsCounted, $subTotalResultsAnalyzed );
# StorePointsForSwimmer - update the passed swimmer's points for the passed course (SCM, etc)
#	and org (PMS or USMS) and ageGroup
#
# Passed:
#	$swimmerId - the swimmer being awarded the points
#	$ageGroup - the age group of the swimmer when they earned these points.  
#		Either a single age group in the form "18-24", in which case this must be
#		an age group the swimmer swam in (they can swim in two different age groups
#		in a single season).  Or two age groups in the form "18-24:25-29", in which
#		case they must have swum in two different age groups during the season
#		and this represents both.
#	$course - SCY, LCM, SCM
#	$org - PMS or USMS
#	$numPoints - the number of points
#	$resultsCounted - the number of results used to accumulated those points
#	$resultsAnalyzed - the number of results analyzed for points.  It's possible not all
#		were actually counted (part of $resultsCounted) if limits were reached (e.g. no more
#		than 8 SCY results can be used.)
#
# RETURNED:
#	n/a
#
sub StorePointsForSwimmer($$$$$$$) {
	my( $swimmerId, $ageGroup, $course, $org, $numPoints, $resultsCounted, $resultsAnalyzed ) = @_;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $ageGroup1 = $ageGroup;
	my $ageGroup2 = $ageGroup;
	
	if( $ageGroup =~ m/:/ ) {
		# two age groups
		$ageGroup1 =~ s/:.*$//;
		$ageGroup2 =~ s/^.*://;
	}
	
	# todo:   make sure there are no entries for this
	# swimmer, org, course.

	# confirm that the passed ageGroup is either the AgeGroup1 or AgeGroup2 of this swimmer.
	my ($sth2, $rv2) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"SELECT AgeGroup1,AgeGroup2 from Swimmer " .
		"WHERE SwimmerId = $swimmerId" );
	if( defined(my $resultHash2 = $sth2->fetchrow_hashref) ) {
		if( $ageGroup =~ m/:/ ) {
			# two age groups
			if( ($resultHash2->{'AgeGroup1'} eq $ageGroup1) &&
				($resultHash2->{'AgeGroup2'} eq $ageGroup2) ) {
				# the passed ageGroup(s) is good
			} else {
				PMSLogging::DumpError( "", "", "StorePointsForSwimmer: got invalid double ageGroup [$ageGroup] " .
					"for swimmer id=$swimmerId", 1 );
			}
		} else {
			# single age group
			if( ($resultHash2->{'AgeGroup1'} eq $ageGroup) ||
				($resultHash2->{'AgeGroup2'} eq $ageGroup) ) {
				# the passed ageGroup is good	
			} else {
				PMSLogging::DumpError( "", "", "StorePointsForSwimmer: got invalid single ageGroup [$ageGroup] " .
					"for swimmer id=$swimmerId.", 1 );
			}
		}
	} else {
		die "StorePointsForSwimmer(): failed to get AgeGroup1,2 for swimmer id $swimmerId\n";
	}

	# update this swimmer by adding their points for the appropriate age group
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"INSERT INTO Points (SwimmerId,Course,Org,AgeGroup,TotalPoints,ResultsCounted,ResultsAnalyzed) " .
		"VALUES (\"$swimmerId\",\"$course\",\"$org\",\"$ageGroup\",\"$numPoints\"," .
		"'$resultsCounted','$resultsAnalyzed')" );
	# get the PointsId for the points we just entered just to make sure there were no errors
    my $pointsId = $dbh->last_insert_id(undef, undef, "Points", "PointsId");
    die "Failed to insert points for swimmerId=$swimmerId in StorePointsForSwimmer()" if( !defined( $pointsId ) );
} # end of StorePointsForSwimmer()




# 	TT_MySqlSupport::ReadSwimMeetData( $racesDataFile );
# ReadSwimMeetData - read and store the data in our "races data file"
#
# PASSED:
#	$fileName - the full path name of the "races data file".
#
# RETURNED:
#	n/a
#
# NOTES:
# The races data file has lines of the form:
#	Rocky Mountain Senior Games Swim Meet	(NOT a PAC sanctioned meet)	PAC	SCY	2016-6-11 - 2016-6-12	20160611SrGameY	http://www.usms.org/comp/meets/meet.php?MeetID=20160611SrGameY
# or
#	Sonoma Wine Country Games Swim Meet	(IS a PAC sanctioned meet)	PAC	SCY	2016-6-18	20160618SSG-1Y	http://www.usms.org/comp/meets/meet.php?MeetID=20160618SSG-1Y
# or
#	...an empty or a line that begins with '#' which is ignored.  Leading space is removed.
# where a tab character separates each field.  There are 7 fields:
#	- Meet title (e.g. "Rocky Mountain Senior Games Swim Meet")
#	- IsPMS (e.g. "(NOT a PAC sanctioned meet)" or "(IS a PAC sanctioned meet)")
#	- Organization (e.g. "PAC")
#	- Course (e.g. "SCY")
#	- Date (one day meet, e.g. "2016-6-18") or Date range (multi-day meet, e.g. 2016-6-11 - 2016-6-12).  
#		Always in the form yyyy-mm-dd, where mm and dd can be a single digit.
#	- The uniquie USMS meet id (e.g. "20160618SSG-1Y")
#	- Link - a link to meet information, e.g. "http://www.usms.org/comp/meets/meet.php?MeetID=20160618SSG-1Y"
#
sub ReadSwimMeetData( $ ) {
	my $fileName = $_[0];
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	
	open( my $meetFD, "< $fileName" ) || die( "Can't open $fileName: $!" );
	while( my $line = <$meetFD> ) {
		$line = PMSUtil::trim($line);
		next if( $line eq "" );		# ignore empty lines
		next if( $line =~ m/^\s*#/ );	# ignore comment lines
		my @lineArr = split( "\t", $line );
		my $meetTitle = $lineArr[0];
		$meetTitle =  MySqlEscape($meetTitle);
		my $date = $lineArr[4];
		my @dateArr = split / - /, $date;		# 1 or 2 fields
		$dateArr[1] = $dateArr[0] if( !defined $dateArr[1] );
		my $isPMS = 0;				# assume not
		$isPMS = 1 if( $lineArr[1] =~ m/IS a PAC sanctioned meet/ );
		my $query = "INSERT INTO Meet " .
				"(USMSMeetId, MeetTitle, MeetLink, MeetOrg, MeetCourse, MeetBeginDate, MeetEndDate, MeetIsPMS) " .
				"VALUES (\"$lineArr[5]\",\"$meetTitle\",\"$lineArr[6]\",\"$lineArr[2]\",\"$lineArr[3]\",\"$dateArr[0]\"," .
				"\"$dateArr[1]\",\"$isPMS\")";
		my($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
		
		# get the MeetId of the meet we just entered into our db just to make sure it worked
    	my $meetId = $dbh->last_insert_id(undef, undef, "Meet", "MeetId");
    	die "TT_MySqlSupport::ReadSwimMeetData(): Insert of meet into DB failed.  Meet is:\n" .
    		"    $line" if( !defined( $meetId ) );

#print "ReadSwimMeetData(): MeetTitle='$meetTitle', meetid=$meetId\n";

	}

} # end of ReadSwimMeetData()
	
	
	
	
	
#	$sth = GetLastRequestStats( $dbh );
# GetLastRequestStats - get the statistics we generated when fetching the last request data
#
# PASSED:
#	$dbh -
#	$season -
#
# RETURNED:
#	$count - the number of different rows found for the passed season.  Should be 1 (or 0 if no stats
#		for that season.)
#	$resultHash - the result hash for the (hopefully) single row returned.  If $count = 0 then
#		$resultHash will be 0.  If $count > 1 then only the first row in the result set will be returned.

#	$sth - mysql statement handle from which our statistics can be fetched.  0 if there were no 
#		rows to return.  If $count > 1 then there will likely be multiple values for each column
#		so the caller should check for that and handle it accordingly.
#
sub GetLastRequestStats( $$ ) { 
	my $dbh = $_[0];
	my $season = $_[1];
	my $status = "x";		# initialize to any non-empty value
	my ($sth, $rv) = (0, 0);
	my ($resultHash, $count) = (0, 0);
	
	# first, make sure we have the FetchStats table:
	my $exists = DoesTableExist( "FetchStats" );
	
	if( $exists ) {
		my $query1 = "SELECT COUNT(*) as Count FROM FetchStats WHERE Season = \"$season\"";
		($sth, $rv, $status) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query1, "" );
		$resultHash = $sth->fetchrow_hashref;
		$count = $resultHash->{"Count"};
	
		if( $count >= 1 ) {
			my $query = 
				"SELECT * FROM FetchStats WHERE Season = \"$season\"";
			($sth, $rv, $status) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
			$resultHash = $sth->fetchrow_hashref;
		}
	} else { 
		PMSLogging::DumpError( 0, 0, "TT_MySqlSupport::GetLastRequestStats(): The " .
			"'FetchStats' table doesn't exist - we will treat this as though there are no " .
			"statistics for $season", 1 );
	}

	return ($count, $resultHash);

} # end of GetLastRequestStats()



sub DoesTableExist( $ ) {
	my $tableName = uc($_[0]);
	my $exists = 0;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my ($sth, $rv, $status) = PMS_MySqlSupport::PrepareAndExecute( $dbh, "SHOW TABLES" );
	while( defined(my $resulArrRef = $sth->fetchrow_arrayref) ) {
		my $existingTableName = $resulArrRef->[0];
		if( uc($existingTableName) eq $tableName ) {
			$exists = 1;
			last;
		}
	}
    return $exists;
} # end of DoesTableExist()



	
#TT_MySqlSupport::DidWeGetDifferentData( $yearBeingProcessed, $raceLines, $PMSSwimmerData );
# DidWeGetDifferentData - (Used by GetResults) see if the results we just fetched are different from
#	the results we last fetched.
#
# PASSED:
#	$season -
#	$numLinesRead -
#	$numDifferentMeetsSeen -
#	$numDifferentResultsSeen -
#	$numDifferentFiles -
#	$raceLines -
#	$PMSSwimmerData
#
# RETURNED:
#	n/a
#
# NOTES:
#	Instead of returing a value, this routine will log its results. If the log we generate
#	contains the string "Results have changed" then programs looking at this log will know
#	that further processing of the results is warranted.
#

# $numLinesRead, $numDifferentMeetsSeen, 
#		$numDifferentResultsSeen, $numDifferentFiles
		
		
sub DidWeGetDifferentData( $$$ ) {
	my( $season, $raceLines, $PMSSwimmerData ) = @_;
	my ($sth, $rv, $numRows) = (0, 0, 0);
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	my $resultsHaveChanged = 0;			# set to 1 if we think results have "changed" (and we log it)

	# get the statistics generated by this run of GetResults:
	my $numLinesRead = TT_Struct::GetFetchStat("FS_NumLinesRead");

	# get the request statistics from the last time we got request data:
	my $resultHash;
	($numRows, $resultHash) = GetLastRequestStats( $dbh, $season );
	# did we find exactly one row?
	if( $numRows == 1 ) {
		# yes!  Compare with passed data.
		my $prevLinesRead = $resultHash->{FS_NumLinesRead};
		my $prevDateTime = $resultHash->{Date};
		if( my $numDiffs = TT_Struct::HashesAreDifferent( TT_Struct::GetFetchStatRef(), $resultHash ) ) {
			# looks like the results we just fetched are different from the last time we
			# fetched results.  
			# Next, log the fact that we found different results, which USUALLY means we need to 
			# regenerate top ten results.  But not so! ...
			# We will only log that there were differences IF the number of lines read this time is
			# "substantially" different from the number of lines read last time, OR there were
			# other differences.  Otherwise (if the only difference was with the number of lines
			# read and that difference is very minor) we will
			# NOT log that any differences exist (thus we will likely not bother computing new
			# top ten points.  We do this because we've seen differences of 1 line with no other
			# differences and it's anoying being told that there are new top ten results when there
			# really arn't!)
			if( 
				( (abs($prevLinesRead - $numLinesRead)) > 3 ) ||	# There was a significant 
																	# difference in the total number of lines seen
				( $prevLinesRead == $numLinesRead ) ||				# The total number of lines seen isn't
																	# different so there must be other differences
				( (abs($prevLinesRead - $numLinesRead) <= 3 ) && ($numDiffs >= 2) )	# There was an
																	# INSIGNIFICANT difference in the number of
																	# lines seen, but there were other differences
																	# for which we must recalculate top ten.
				) {
				# We must recalculate top ten - summarize the differences in the log:
				PMSLogging::PrintLog( "", "", "Results appear to have changed ($numDiffs changes) " .
					"since the last time we got results on $prevDateTime:", 1 );
				TT_Struct::PrintStats( "Previous", $resultHash, 1 );
				$resultsHaveChanged = 1;
			} else {
				# We don't need to recalculate top ten EVEN THOUGH we found slight differences in the results
				PMSLogging::PrintLog( "", "", "NOTE:  there appears to be no change in results " .
					"since $prevDateTime", 1 );
				PMSLogging::PrintLog( "", "", "    (HOWEVER: Previous line read: $prevLinesRead, new lines read: " .
					"$numLinesRead - difference ignored.)", 1 );
			}
		} 
		
		# Even if we think results have changed we're going to see if
		# we have a new RSIND file to process. If so we'll pretend that results have changed because
		# the new RSIND file may give us new swimmers who deserve points that didn't get points
		# before.  We will NOT USE the RSIND file here - just see if it's different from the last
		# one used by Topten2.pl.
		# In either case we log the RSIND file we think should be used next.
		# Get the full path name to the PMS member file (the "RSIND" file)
		# that contains PMS supplied swimmer data (e.g. name, regnum, team, etc.).  
		# First, we need to get the pattern that we'll use to find the file:
		my $fileNamePattern = PMSStruct::GetMacrosRef()->{"RSIDNFileNamePattern"};
		my $swimmerDataFile = PMSUtil::GetFullFileNameFromPattern( $fileNamePattern, $PMSSwimmerData, 
			"RSIND", 1 );
		if( defined $swimmerDataFile ) {
			# we have a RSIND file - is it newer than the last one?  should Topten use it?  We'll decide here:
			my( $simpleName, $dirs, $suffix ) = fileparse( $swimmerDataFile );		# get last simple name in filename
			my ($refreshRSIDNFile, $lastRSIDNFileName) = 
				PMS_ImportPMSData::RSINDFileIsNew( $simpleName, $season);
			# $refreshRSIDNFile == 1 means that it's different, 0 means that it is not
			if( $refreshRSIDNFile == 1 ) {
				my $tag = "have not";
				if( $resultsHaveChanged ) {
					$tag = "have";
				}
				PMSLogging::PrintLog( "", "", "It appears that there $tag been changes to the results " .
				"since the last time we got results on $prevDateTime...\n    BUT it looks like we " .
				" need to process a new RSIND file, so...\n    we'll act as though Results " .
				"have changed. The new RSIND file is:\n   $simpleName ", 1 );
				$resultsHaveChanged = 1;
			} else {
				PMSLogging::PrintLog( "", "", "NOTE:  there appears to be no change in the RSIND file " .
					"since $prevDateTime. The current RSIND file is:\n   $simpleName", 1 );
			}
		} else {
			# we can't find any RSIND file, so don't bother saying that anything has changed!
			PMSLogging::PrintLog( "", "", "NOTE:  There is no RSIND file available, so we're going to" .
				" act as though there are no changes since we can't run TopTen processing anyway.", 1 );
			$resultsHaveChanged = 0;
		}

		if( $resultsHaveChanged ) {
			# so far it appears that results have changed but we may not commit to that if any errors
			# occurred during processing.
			if( PMSLogging::GetNumErrorsLogged() == 0 ) {
				# no errors occurred - now update this row with the new values
				UpdateFetchStats( $season, TT_Struct::GetFetchStatRef(), 
					PMSStruct::GetMacrosRef()->{"MySqlDateTime"}, 1 );
			} else {
				# we had errors so don't trust that results didn't change:
				my $tag = "have not";
				if( $resultsHaveChanged ) {
					$tag = "have";
				}
				PMSLogging::PrintLog( "", "", "It appears that results $tag changed " .
					"since the last time we got results on $prevDateTime...\n    BUT errors were detected, so " .
					"we don't really trust this.\n    Regardless, we'll act as though results DID NOT change.", 1 );
				$resultsHaveChanged = 0;
			}
		}

	} elsif( $numRows > 1 ) {
		PMSLogging::PrintLog( "", "", "TT_MySqlSupport::DidWeGetDifferentData(): Found $numRows rows for season $season " .
			"in the FetchStats table.  This must be investigated since we determine whether or not " .
			"results have changed (and we're not updating the FetchStats table even if we should)!", 1 );
	} else { # ($numRows == 0)...
		# first time we've gathered results for this year?  Act as though results have changed
		# so we generate a new standings page:
		PMSLogging::PrintLog( "", "", "Results have changed because this is the first time we've seen results " .
		"for $season. ($numRows)", 1 );
		$resultsHaveChanged = 1;
		# no rows.  Add this one
		UpdateFetchStats( $season, TT_Struct::GetFetchStatRef(), 
			PMSStruct::GetMacrosRef()->{"MySqlDateTime"}, 0 );
	}
} # end of DidWeGetDifferentData()






# 	UpdateFetchStats( $season, TT_Struct::GetFetchStatRef(), 
#	PMSStruct::GetMacrosRef()->{"MySqlDateTime"}, 1 );
# UpdateFetchStats - update the FetchStats database table
#
# PASSED:
#	$season - the season being processed, e.g. "2019"
#	$hashRef - a reference to a hashtable containing the data to be used to update the db table
#	$date - the date that is used to set the Date field in the db table.
#	$update - TRUE if we perform an UPDATE, false if instead we need to perform in INSERT.
#
# RETURNED:
#	n/a
#
# NOTES:
#	If there are any errors they are logged but otherwise ignored.
#
sub UpdateFetchStats( $$$$ ) {
	my ($season, $hashRef, $date, $update) = @_;
	my $query = "";
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();

	if( $update ) {
		# construct an UPDATE query:
		$query = "UPDATE FetchStats SET Season = '$season', Date = '$date'";
		foreach my $key (keys %{$hashRef}) {
			if( $key !~ m/^.*_Desc/ ) {
				$query .= ", $key = '" . $hashRef->{$key} . "'";
			}
		}
		$query .= "WHERE Season = '$season'";
	} else {
		# construct an INSERT query:
		$query = "INSERT INTO FetchStats (Season,Date";
		my $values = "VALUES ('$season','$date'";
		foreach my $key (keys %{$hashRef}) {
			if( $key !~ m/^.*_Desc/ ) {
				$query .= ", $key";
				$values .= ", '" . $hashRef->{$key} . "'";
			}
		}
		$query .= ") $values)";
	}
	
	# execute the query:
	my ($sth, $rv, $status) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	if( $update ) {
		# did the UPDATE go OK?
		if( $status ) {
			# update failed - ERROR!
			PMSLogging::DumpError( 0, 0, "TT_MySqlSupport::UpdateFetchStats(): " .
				"UPDATE of FetchStats failed (season=$season, err='$status', query='$query')", 1 );
		}
	} else {
		# did the INSERT go OK?
		# get the FetchStatsId of the row we just entered into our db just to make sure it worked
    	my $fetchStatsId = $dbh->last_insert_id(undef, undef, "FetchStats", "FetchStatsId");
    	if( !defined( $fetchStatsId ) ) {
    		# insert failed - ERROR!
	    	PMSLogging::DumpError( 0, 0, "TT_MySqlSupport::UpdateFetchStats(): Insert of row for " .
	    		"season $season into FetchStats " .
	    		"failed (season=$season, query='$query')" );
    	}
	}
} # end of UpdateFetchStats()
				
			

1;  # end of module

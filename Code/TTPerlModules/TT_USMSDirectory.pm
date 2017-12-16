#!/usr/bin/perl -w
# TT_USMSDirectory.pm - support accessing the USMS Directory.  The "USMS Directory" (why that name???  I dunno...)
#	contains information about every USMS swimmer.  The information we're interested in is the swim meets
#	swum by individual swimmers during the current season.  This module is used to get a list of every
#	swim meet for the current season for a specific swimmer.  In addition, we'll look up each of those meets
#	to see if they are a PMS sanctioned meet.  This information is important since we use it to determine
#	whether or not a prospective SOTY has swum the minumum number of PMS meets.

package TT_USMSDirectory;

use strict;
use sigtrap;
use warnings;
require TT_Logging;
use HTTP::Tiny;

use FindBin;
use File::Spec;
use lib File::Spec->catdir( $FindBin::Bin, '..', '..', '..', 'PMSPerlModules' );
require PMS_MySqlSupport;



# 		GetUSMSDirectoryInfo( $swimmerId );
# GetUSMSDirectoryInfo - update our database with information from the "USMS Directory" page for
#		the passed swimmer.
#
# PASSED:
#	$swimmerId - our swimmerId of the swimmer in our swimmer table.
#
# RETURNED:
#	n/a
#
# SIDE-EFFECTS:
#	The Meet and USMSDirectory tables are updated with the information gleened from USMS.
#

my $debug;
sub GetUSMSDirectoryInfo( $ ) {
	my $swimmerId = $_[0];
	my $resultHash;
	my( $firstName, $middleInitial, $lastName, $regNum ) = ("?", "?", "?", "?");
	my $usmsSwimmerId;			# the right-most 5 digits of the USMS registration number for the swimmer.
	my $query;
	my %listOfMeetsForThisSwimmer;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	$debug = 0;

	# if we're not reading any result files then we didn't clear any database tables, so in that case
	# we don't need to get the directory info for any swimmers:
	if( (PMSStruct::GetMacrosRef()->{"RESULT_FILES_TO_READ"} == 0) &&
		(PMSStruct::GetMacrosRef()->{"COMPUTE_POINTS"} == 0) ) {
		return;
	}

	# initialize our HTTP class:
	my $tinyHttp = HTTP::Tiny->new();
	my $httpResponse;
	
	# get some details about the swimmer we're working with:
	my ($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh,
		"SELECT FirstName,MiddleInitial,LastName,RegNum " .
		"FROM Swimmer WHERE SwimmerId = \"$swimmerId\"" );
	if( defined($resultHash = $sth->fetchrow_hashref) ) {
		# got swimmer details...get to work on their meets
		$firstName = $resultHash->{'FirstName'};
		$middleInitial = $resultHash->{'MiddleInitial'};
		$lastName = $resultHash->{'LastName'};
		$regNum = $resultHash->{'RegNum'};
		# Get the USMS Swimmer id, e.g. regnum 384x-abcde gives us 'abcde'
		$usmsSwimmerId = PMSUtil::GetUSMSSwimmerIdFromRegNum( $regNum );
		
		# get the page that has a list of all events swum by this swimmer, which includes the meets they
		# were swum in:
		my $link = "http://www.usms.org/comp/meets/indresults.php?SwimmerID=$usmsSwimmerId";

		PMSLogging::PrintLogNoNL( "", "", "Topten::GetUSMSDirectoryInfo(): GET from '$link' for " .
			"'$firstName $middleInitial $lastName' ...", 1 ) if( $debug > 1 );
		$httpResponse = $tinyHttp->get( $link );
		if( !$httpResponse->{success} ) {
			# failure - display message and give up on this one
			PMSLogging::PrintLog( "", "", "FAILED!!", 1 ) if( $debug > 1 );
			TT_Logging::HandleHTTPFailure( $link, "?", "?", $httpResponse );
			return;
		}

		# begin our state machine, processing each line in the human-readable results:
		my @lines = split('\n', $httpResponse->{content});
		PMSLogging::PrintLog( "", "", "(" . scalar @lines . " lines)...", 1 ) if( $debug > 1 );
		my $course = "";
		my $state = "";
		my $lineNum = 0;
		foreach my $line ( @lines ) {
			$lineNum++;
			if( $line =~ m/<h3 style="margin-top:15px;">/ ) {
				# the next line tells us the course of the meet we're about to find
				$state = "LookingForCourse";
			} elsif( $state eq "LookingForCourse" ) {
				if( $line =~ m/^<a name="(...)">/ ) {
					$course = $1;			# one of SCY, SCM, LCM
				} else {
					PMSLogging::DumpError( "", "", "Expected line with course but not found!  Abort this swimmer!", 1 ) if( $debug > 1 );
					return;
				}
				$state = "LookingForMeet";
			} elsif( $state eq "LookingForMeet" ) {
				if( $line =~ m/<a href="meet.php\?MeetID/ ) {
					# we found a meet for this swimmer...record it in our database if not already there
					AddMeetForSwimmer( $swimmerId, $usmsSwimmerId, $line, $course, $tinyHttp, \%listOfMeetsForThisSwimmer );
				}
			}
		} # end of foreach my $line ( @lines...
	} # end of getting swimmer details
	else {
		# failed to get swimmer details
		PMSLogging::DumpError( "", "", "Topten::GetUSMSDirectoryInfo(): Failed to get swimmer details " .
			"for swimmerId='$swimmerId' - give up on this swimmer!", 1 ) if( $debug > 1 );
	}
	
} # end of GetUSMSDirectoryInfo()
					
					
					
# 	AddMeetForSwimmer( $swimmerId, $usmsSwimmerId, $line, $course, $tinyHttp, $listOfMeetsForThisSwimmerRef );
# AddMeetForSwimmer - Add the following meet to our database and associate it with the passed swimmer.
#
# PASSED:
#	$swimmerId - identifies the swimmer in our database
#	$usmsSwimmerId - the usms reg num for the swimmer
#	$line - the HTML line taken from the swimmer's USMS page containing details of a meet (date
#		and meetId).
#	$course - SCY, SCM, LCM
#	$tinyHttp - the HTTP class that we use to get more info about the meet
#	$listOfMeetsForThisSwimmerRef - reference to a hash that we populate as we analyze meets
#		for this swimmer.  We use this to make sure we don't bother analyzing the same meet
#		more than once for a swimmer, since this analysis is expensive.
#
# RETURNED:
#	n/a
#
# NOTES:
#	This routine will add the passed meet into the Meet table IFF the meet doesn't yet exist in our 
#	meet table.  If the passed swimmer didn't score any points in this meet then this meet
#	is associated with the swimmer in the USMSDirectory table as a "hidden meet".
#
sub AddMeetForSwimmer() {
	my($swimmerId, $usmsSwimmerId, $line, $course, $tinyHttp, $listOfMeetsForThisSwimmerRef) = @_;
	my $yearBeingProcessed = PMSStruct::GetMacrosRef()->{"YearBeingProcessed"};

	# get the date and the USMSMeetId
	$line =~ m/^<td>&nbsp;(\d\d\d\d-\d\d-\d\d).*meet.php\?MeetID=([^"]+)"/;
	my $date = $1;
	my $USMSMeetId = $2;
	if( defined( $listOfMeetsForThisSwimmerRef->{$USMSMeetId}) ) {
		# we've processed this meet already - no need to do it again
		return;
	}
	$listOfMeetsForThisSwimmerRef->{$USMSMeetId} = 1;
	PMSLogging::PrintLogNoNL( "", "", "    - Found meet with USMSMeetId '$USMSMeetId', course $course, date='$date'...", 1 ) if( $debug > 1 );

	my $dateAnalysis = PMSUtil::ValidateDateWithinSeason( $date, $course, $yearBeingProcessed );
	# is this entry within the season we're processing?
	if( $dateAnalysis eq "" ) {
		PMSLogging::PrintLog( "", "", "...this is within the season we're processing!", 1 ) if( $debug > 1 );
		# yes! do we already know about this meet?  If not update our database as necessary
		my $meetId = AddHiddenMeetIfNecessary( $USMSMeetId, $swimmerId, $usmsSwimmerId );
		# if the returned $meetId is non-zero then it's the MeetId of a newly create meet entry
		# in our Meet table.  But we don't know much about the meet, so now we have to get the
		# details of this meet.
		if( $meetId ) {
			PMSLogging::PrintLog( "", "", "    - We added this meet to our Meet table, and now need to update details.", 1 ) if( $debug > 1 );
			PopulateDetailsOfHiddenMeet( $meetId, $USMSMeetId, $course, $tinyHttp );
		}
	} else {
		PMSLogging::PrintLog( "", "", "...this is OUTSIDE the season we're processing!", 1 ) if( $debug > 1 );
	}
} # end of AddMeetForSwimmer()

#
# AddHiddenMeetIfNecessary - Add the passed meet to our Meet table and USMSDirectory table
#	and associate it with the passed swimmer, if necessary.
#
# PASSED:
#	$USMSMeetId - the USMS assigned meet id of the meet
#	$swimmerId - identifies the swimmer in our database
#	$usmsSwimmerId - the USMS swimmer id
#
# RETURNED:
#	$meetId - the meetId of the meet added to our Meet table, or 0
#		if it wasn't necessary to add the Meet table.
#
# NOTES:
#	The Meet table may be updated by this routine, and also the USMSDirectory table is updated
#	if the user isn't yet associated with this (hidden) meet.
#
sub AddHiddenMeetIfNecessary() {
	my ($USMSMeetId, $swimmerId, $usmsSwimmerId) = @_;
	my $query;
	my ($sth, $rv, $resultHash);
	my $meetId;
	my $result = 0;
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();

	# is this meet in our meet table?
	$query = "SELECT MeetId from Meet " .
		"WHERE Meet.USMSMeetId = '$USMSMeetId'";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	if( defined($resultHash = $sth->fetchrow_hashref) ) {
		# this meet is in our Meet table...
		PMSLogging::PrintLog( "", "", "        -[Topten::AddHiddenMeetIfNecessary():] This meet is already " .
			"in our Meet table.", 1 ) if( $debug > 1 );
		# Is it a meet that our swimmer scored points in?
		$meetId = $resultHash->{'MeetId'};
		$query = "SELECT SplashId FROM Splash " .
					"WHERE MeetId = $meetId " .
					"AND SwimmerId = \"$swimmerId\"";
		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
		if( defined($resultHash = $sth->fetchrow_hashref) ) {
			PMSLogging::PrintLog( "", "", "        - Furthermore, this swimmer scored points at it.", 1 ) if( $debug > 1 );
			# Yes, this swimmer scored points at this meet, thus we already know about 
			# this meet and it's association with this swimmer - no need to
			# add this meet as a Hidden meet.
			return 0;
		}
		# Is it a meet that is a "Hidden" meet for this swimmer?
		$query = "SELECT USMSDirectoryId FROM USMSDirectory " .
					"WHERE MeetId = $meetId " .
					"AND SwimmerId = \"$swimmerId\"";
		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
		if( defined($resultHash = $sth->fetchrow_hashref) ) {
			PMSLogging::PrintLog( "", "", "        - Furthermore, this is a Hidden meet we already know about.", 1 ) if( $debug > 1 );
			# Yes, this swimmer is already associated with this hidden meet - no need to
			# add this meet as a Hidden meet again.
			return 0;
		}
		# else this meet is in our Meet table because someone else scored points at it and it's not yet
		# associated with the current swimmer.  We'll make it a "Hidden" meet for our current swimmer below.
	} else {
		# this meet is not in our Meet table.  We are going to consider it a Hidden meet and add it
		# to our Meet table and associate it with our current swimmer.
		# First, we need to put this meet into our meet table.  We don't know 
		# anything about the meet, yet - we'll fill it in later...
		PMSLogging::PrintLog( "", "", "        -[Topten::AddHiddenMeetIfNecessary():] This meet is unknown to " .
			"us - add it to our Meet table.", 1 ) if( $debug > 1 );
		$query = "INSERT INTO Meet (USMSMeetId) " .
			"VALUES ('$USMSMeetId')";
		($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
		# get the MeetId of the meet we just entered into our db
    	$meetId = $dbh->last_insert_id(undef, undef, "Meet", "MeetId");
    	if( !defined( $meetId ) ) {
			PMSLogging::DumpError( "", "", "Failed to INSERT new meet!", 1 )  if( $debug > 1 );
			return 0;
    	}
    	$result = $meetId;
	}
	###
	### NOW, MAKE THIS A HIDDEN MEET FOR THE CURRENT SWIMMER
	###
	PMSLogging::PrintLog( "", "", "        - We are making meet $meetId a new Hidden meet for swimmer $swimmerId.", 1 ) if( $debug >= 1 ) ;
	$query = "INSERT INTO USMSDirectory (SwimmerId,USMSSwimmerId,MeetId) " .
		"VALUES ('$swimmerId','$usmsSwimmerId','$meetId')";
	($sth, $rv) = PMS_MySqlSupport::PrepareAndExecute( $dbh, $query );
	# get the USMSDirectoryId of the USMSDirectory entry we just entered into our db
	my $USMSDirectoryId = $dbh->last_insert_id(undef, undef, "USMSDirectory", "USMSDirectoryId");
	if( !defined( $USMSDirectoryId ) ) {
		PMSLogging::PrintLog( "", "", "Failed to INSERT new USMSDirectory!", 1 ) if( $debug > 1 ) ;
		return;
	}
	return $result;
			
} # end of AddHiddenMeetIfNecessary();



#
# PopulateDetailsOfHiddenMeet - Update the meet in our Meet table with info gleened from the
#	USMS web page describing the meet.
#
# PASSED:
#	$meetId - the internal meet id for this meet (it's already in our Meet table)
#	$USMSMeetId - the USMS meet id (we use that to find its web page)
#	$meetCourse - SCY, SCM, LCM
#	$tinyHttp - the HTTP class that we use to get the meet's web page
#
# RETURNED:
#	n/a
#
sub PopulateDetailsOfHiddenMeet( $$$$ ) {
	my ($meetId, $USMSMeetId, $meetCourse, $tinyHttp) = @_;
	my $meetLink = "http://www.usms.org/comp/meets/meet.php?MeetID=$USMSMeetId";	
	my $dbh = PMS_MySqlSupport::GetMySqlHandle();
	
	PMSLogging::PrintLogNoNL( "", "", "        -[Topten::PopulateDetailsOfHiddenMeet():] GET from '$meetLink' " .
		"to get details for meet MeetId=$meetId, course=$meetCourse ...", 1 ) if( $debug > 1 );

	my $httpResponse = $tinyHttp->get( $meetLink );
	if( !$httpResponse->{success} ) {
		# failure - display message and give up on this one
		PMSLogging::PrintLog( "", "", "FAILED!!", 1 ) if( $debug > 1 );
		TT_Logging::HandleHTTPFailure( $meetLink, "?", "?", $httpResponse );
		return;
	}

	# begin our state machine, processing each line in the human-readable results:
	my @lines = split('\n', $httpResponse->{content});
	PMSLogging::PrintLog( "", "", "(" . scalar @lines . " lines)...", 1 ) if( $debug > 1 );
	my $lineNum = 0;
	# details we need to get:
	my $meetTitle = "";
	# $meetLink defined above
	my $meetOrg = "";		# this won't get defined for this meet...
	# $meetCourse defined above
	my $meetBeginDate = "(unknown date)";
	my $meetEndDate = "(unknown date)";
	my $meetIsPMS = 0;
	# get to work...
	my $state = "General State";
	foreach my $line ( @lines ) {
		$lineNum++;
		#print "line $lineNum: $line\n";
		if( $state eq "Looking for Title" ) {
			# this line contains the title
			$line =~ m,<h3>(.*)</h3>,;
			$meetTitle = TT_MySqlSupport::MySqlEscape($1);
			$state = "General State";
		}elsif( $line =~ m/<!-- CONTENT START -->/ ) {
			$state = "Looking for Title";
		} elsif( $line =~ m/Date: / ) {
			# found the date of the meet
			$line =~ s,^.*<td>,,;
			$line =~ s,</td>.*$,,;
			my $date = PMSUtil::ConvertDateRangeToISO( $line );
			if( $date eq "" ) {
				$date = "2000-01-01";			# invalid date (msg already generated)
			}
			# now convert the $date into two dates:  beginning and ending date:
			my @dateArr = split / - /, $date;		# 1 or 2 fields
			$dateArr[1] = $dateArr[0] if( !defined $dateArr[1] );
			$meetBeginDate = $dateArr[0];
			$meetEndDate = $dateArr[1];
		} elsif( $line =~ m/Sanction.*Status: / ) {
			# found the sanctioning
			if( $line =~ m/Sanctioned.*>Pacific LMSC</ ) {
				$meetIsPMS = 1;
			}
			last;		# assume sanctioning is last interesting detail we care about
		}
	} # end of foreach my $line...
	# save these details
	my $query = "UPDATE Meet SET MeetTitle = \"$meetTitle\"," .
								"MeetLink = '$meetLink'," .
								"MeetOrg = '$meetOrg'," .
								"MeetCourse = '$meetCourse'," .
								"MeetBeginDate = '$meetBeginDate'," .
								"MeetEndDate = '$meetEndDate'," .
								"MeetIsPMS = $meetIsPMS " .
								"WHERE MeetId=$meetId";
	PMS_MySqlSupport::DBIErrorPrep( "Topten::PopulateDetailsOfHiddenMeet(): $query" );
	my $rowsAffected = $dbh->do( $query );
	PMS_MySqlSupport::DBIErrorPrep( "" );
	if( $rowsAffected == 0 ) {
		# update failed - 
		PMSLogging::PrintLog( "", "", "Topten::PopulateDetailsOfHiddenMeet(): Update of meet $meetId failed!!", 1 ) if( $debug > 1 );
	}
} # end of PopulateDetailsOfHiddenMeet()
				




1;  # end of module

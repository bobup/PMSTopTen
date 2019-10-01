#!/usr/bin/perl -w
# TT_Struct.pm - support data structures.

package TT_Struct;

use strict;
use sigtrap;
use warnings;


###
### General Structures used by our modules
###

# we use %hashOfInvalidRegNums just so we don't report the same invalid reg num more than once.
# Currently populated when processing PMS top 10 only (other results either don't include reg numbers or
# are trusted to always have correct reg nums.)
our %hashOfInvalidRegNums = ();		# {regnum} = ""; if we don't find the regnum
									# in the RSIDN file.

our %numInGroup;			# $numInGroup{gender:ageGroup} = number of swimmers in this gender/age group

# fetchStats - mirriors the table of the same name (field names of the FetchStats table must be
#	match exactly the key names in this hash table)  IF YOU ADD A FIELD HERE YOU PROBABLY SHOULD
# 	ADD THE SAME COLUMN IN THE TABLE (see TT_MySqlSupport.pm)
our %fetchStats = (
	FS_NumLinesRead						=> 0,
		FS_NumLinesRead_Desc			=> "number of lines read",
	FS_NumDifferentMeetsSeen			=> 0,
		FS_NumDifferentMeetsSeen_Desc	=> "number of meets discovered",
	FS_NumDifferentResultsSeen			=> 0,
		FS_NumDifferentResultsSeen_Desc	=> "number of results found",
	FS_NumDifferentFiles				=> 0,
		FS_NumDifferentFiles_Desc		=> "number of files processed",
	FS_NumRaceLines						=> 0,
		FS_NumRaceLines_Desc			=> "number of meets written to races.txt",
	FS_CurrentSCYRecords				=> 0,
		FS_CurrentSCYRecords_Desc		=> "number of Current SCY Records",
	FS_CurrentSCMRecords				=> 0,
		FS_CurrentSCMRecords_Desc		=> "number of Current SCM Records",
	FS_CurrentLCMRecords				=> 0,
		FS_CurrentLCMRecords_Desc		=> "number of Current LCM Records",
	FS_HistoricalSCYRecords				=> 0,
		FS_HistoricalSCYRecords_Desc	=> "number of Historical SCY Records",
	FS_HistoricalSCMRecords				=> 0,
		FS_HistoricalSCMRecords_Desc	=> "number of Historical SCM Records",
	FS_HistoricalLCMRecords				=> 0,
		FS_HistoricalLCMRecords_Desc	=> "number of Historical LCM Records",
);
# $fetchStats{'NumLinesRead'} = total number of lines read from the web pages that we process
#		to get the result files that we'll process to compute points.  PLUS, the number of lines in the
#		open water file that we process.
# $fetchStats{'NumDifferentMeetsSeen'} = total number of UNIQUE meets we see in the web pages we process, 
#		PLUS the number of open water events.
# $fetchStats{'NumDifferentResultsSeen'} = total number of result lines we see when processing the web 
#		pages and OW results.  Should be less than NumLinesRead since some lines 
#		read are not result lines.
# $fetchStats{'NumDifferentFiles'} = number of different result files we find while analyzing the web pages,
#		PLUS 1 for the OW results.  This number will increase throughout the season as more result files
#		become available.
# $fetchStats{'CurrentSCYRecords'} = the number of "current "records for this course that earned points
# $fetchStats{'CurrentSCMRecords'} = (ditto)
# $fetchStats{'CurrentLCMRecords'} = (ditto)
# $fetchStats{'HistoricalSCYRecords'} = the number of "historical "records for this course that earned points
# $fetchStats{'HistoricalSCMRecords'} = (ditto)
# $fetchStats{'HistoricalLCMRecords'} = (ditto)

my @fetchStatsOrder = (
	"FS_NumLinesRead",
	"FS_NumDifferentMeetsSeen",
	"FS_NumDifferentResultsSeen",
	"FS_NumDifferentFiles",
	"FS_NumRaceLines",
	"FS_CurrentSCYRecords",
	"FS_CurrentSCMRecords",
	"FS_CurrentLCMRecords",
	"FS_HistoricalSCYRecords",
	"FS_HistoricalSCMRecords",
	"FS_HistoricalLCMRecords",
	);

sub SetFetchStat( $$ ) {
	$fetchStats{$_[0]} = $_[1];
} # end of SetFetchStat()

sub IncreaseFetchStat( $$ ) {
	$fetchStats{$_[0]} += $_[1];
} # end of IncreaseFetchStat()


sub GetFetchStat( $ ) {
	return $fetchStats{$_[0]};
} # end of GetFetchStat()

sub GetFetchStatRef() {
	return \%fetchStats;
} # end of GetFetchStatRef()

sub PopulatePMSMacrosWithFetchStat() {
	foreach my $key ( keys %fetchStats ) {
		PMSStruct::GetMacrosRef()->{$key} = $fetchStats{$key};
	}
} # end of PopulatePMSMacrosWithFetchStat()

# 		if( HashesAreDifferent( TT_Struct::GetFetchStatRef(), $prevResultsHash ) ) {
# RETURNED:
#	$result - >0 if the two hashes are different, which means at least one of the following is true:
#		- there exists a key in $masterRef that does not exist in $copyRef, or
#		- there exists a key/value in $masterRef where the value for the corresponding key
#			in $copyRef is different.
#		The value of $result is the number of differences found.
#
# NOTES:
#	If a key exists in $copyRef that does NOT exist in $masterRef we just ignore it.
#
sub HashesAreDifferent( $$ ) {
	my ($masterRef, $copyRef) = @_;
	my $result = 0;		# assume the two hashes are identical
	
	foreach my $key ( keys %{$masterRef} ) {
		if( ($key !~ m/_Desc/) && ($key =~ m/^FS_/) ) {
			if( (!defined $copyRef->{$key}) ||
				($masterRef->{$key} ne $copyRef->{$key}) ) {
				# found a difference!
	if(1) {
	if( (!defined ($copyRef->{$key})) ) {
		print "key '$key' not defined\n";
	} else {
		print "key $key is different: $masterRef->{$key} ne $copyRef->{$key}\n";
	}
	}
				$result++;
			}
		}
	}
	return $result;
} # end of HashesAreDifferent()

#PMSLogging::PrintLog( "", "", "    Total number of lines read: " . TT_Struct::GetFetchStat("NumLinesRead"), 1);

# TT_Struct::PrintStats( "Total", TT_Struct::GetStruct(), $console );
sub PrintStats( $$$ ) {
	my ($heading, $hashRef, $console) = @_;
	foreach my $key (@fetchStatsOrder) {
		my $desc = $fetchStats{$key . "_Desc"};
		my $value = $hashRef->{$key};
		PMSLogging::PrintLog( "", "", "    $heading $desc: $value", $console);
	}
} # end of PrintStats()

# my $string = TT_Struct::PrintStatsString( "Total", TT_Struct::GetStruct() );
sub PrintStatsString( $$ ) {
	my ($heading, $hashRef) = @_;
	my $str = "";
	foreach my $key (@fetchStatsOrder) {
		my $desc = $fetchStats{$key . "_Desc"};
		my $value = $hashRef->{$key};
		$str .= "    $heading $desc: $value\n";
	}
	return $str;
} # end of PrintStatsString()



#  ------  Swimmer(s) Of The Year  --------
# Originally we (PAC) would recognize ONE female and ONE male SOTY (Swimmer of the Year).  A SOTY is 
# choosen by the PAC committee (I don't know the details - perhaps the full board?) and was USUALLY
# the high-point earners of each gender (although it didn't have to be.)
# There are some complications:
#	- the female SOTY award is now named the Laura Val award; Laura is not eligable but can still 
#		earn the most female points.
#	- the above doesn't consider ties, which is OK since the committee can break the ties IF THEY KNOW
#		A TIE EXISTS.
#	- a swimmer cannot be considered unless they have swum in at least 3 PAC sanctioned meets during
#		the season.
# We will help the committee and compute for them the high point earners.  We'll give them enough data
# to recognize ties when they happen, and also help them if Laura is the high-point female.  We'll do this
# by tracking and displaying a number of high-points for each gender, that number specified by
# $NumHighPoints.  For example, consider the case where we sort the points earned by women PAC swimmers
# from highest to lowest and we look at them:
#	Points			Name
#	1002			Jane
#	1002			Laura
#	1000			Suzi
#	994				Linda
#	992				Carrie
# ...etc.  Note that Jane and Laura tie for high point.  Presumably the committee would pick one of them
# or maybe not.  With the list above they have enough information to choose someone else with fewer points
# if they want.  If we set $NumHighPoints to 3 we'd display Jane, Laura, Suzi, and Linda, because they
# encompass the top 3 most points earned.


# used in html, excel:
my $NumHighPoints;

# $SwimmersOfTheYear{'F'} = array of FEMALE SwimmerIds of the Swimmers of the Year.  Usually only
# has $NumHighPoints swimmers but could be more if there is a tie.
# Array element 0 is the top SOTY, etc.  For example, $swimmersOfTheYear{'F'}[0] is the top scoring female SOTY,
# $swimmersOfTheYear{'F'}[1] is the second scoring female SOTY, etc.
# Each element of this array is of the form "SID|AG", where
#	SID - a swimmer id
#	|   - a virtical bar
#	AG  - an age group of the form "18-25" or "35-39"
# Same idea for $SwimmersOfTheYear{'M'} except for MALE
my %SwimmersOfTheYear = ();

# $NumSwimmersOfTheYear{'F'} = the number of FEMALE Swimmers of the Year.  Usually > 0.  
# If > $NumHighPoints then we have a tie.
# Same idea for $NumSwimmersOfTheYear{'M'} except for MALE
my %NumSwimmersOfTheYear = ();

# $PointsForSwimmerOfTheYear{'F'} = the number of points the FEMALE Swimmer(s) of the Year have.
# It's an array that contains the points for each person in the corresponding SwimmersOfTheYear array.
# Ordered highest points to lowest points (e.g. $PointsForSwimmerOfTheYear{'F'}[0] = 1002, 
# $PointsForSwimmerOfTheYear{'F'}[1] = 1002, $PointsForSwimmerOfTheYear{'F'}[2] = 1000, etc...)
# Same idea for $PointsForSwimmerOfTheYear{'M'} except for MALE
my %PointsForSwimmerOfTheYear = ();



1;  # end of module

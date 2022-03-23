#!/usr/bin/perl -w
# TT_Struct.pm - support data structures.
#
# Copyright (c) 2017 Bob Upshaw.  This software is covered under the Open Source MIT License 

package TT_Struct;

use strict;
use sigtrap;
use warnings;


###
### General Structures used by our modules
###



# $G_RESULT_FILES_TO_READ is used to dictate what result files to read.  If 0 we will read no result
# files and only use what we find in the database.  If non-zero we'll clear the database and then
# read whatever result files $G_RESULT_FILES_TO_READ tells us to read, which is specified by a single
# bit in $G_RESULT_FILES_TO_READ.  The only reason to specify a value other than the default (0b11111) is to
# help with debugging.
#   - if ($G_RESULT_FILES_TO_READ & 0b1)		!= 0 then process PMS Top Ten result files
#   - if ($G_RESULT_FILES_TO_READ & 0b10)		!= 0 then process USMS Top Ten result files
#   - if ($G_RESULT_FILES_TO_READ & 0b100)	!= 0 then process PMS records
#   - if ($G_RESULT_FILES_TO_READ & 0b1000)	!= 0 then process USMS records
#   - if ($G_RESULT_FILES_TO_READ & 0b10000)	!= 0 then process PMS Open Water
#   - if ($G_RESULT_FILES_TO_READ & 0b100000)	!= 0 then process "fake splashes"
#   - if ($G_RESULT_FILES_TO_READ & 0b1000000)	!= 0 then process ePostals
our $G_RESULT_FILES_TO_READ = 	0b1111111;		# process all result files including ePostal (not default yet)
#$G_RESULT_FILES_TO_READ = 0b011110;			# process all but Top Ten result files
#$G_RESULT_FILES_TO_READ = 	0b001111; 			# process all but OW
#$G_RESULT_FILES_TO_READ = 	0;					# process none of the result files (use DB only)
#$G_RESULT_FILES_TO_READ = 	0b010000;			# ow only
#$G_RESULT_FILES_TO_READ = 	0b000001;			# PMS Top Ten result files only
#$G_RESULT_FILES_TO_READ = 	0b000100;			# PMS records only
#$G_RESULT_FILES_TO_READ = 	0b001000;			# USMS records only
#$G_RESULT_FILES_TO_READ = 	0b000010;			# USMS Top Ten result files only
#$G_RESULT_FILES_TO_READ = 	0b001110;			# USMS Top Ten result files, USMS records, and PMS records only
#$G_RESULT_FILES_TO_READ = 	0b110000;			# fake splashes + OW only
#$G_RESULT_FILES_TO_READ = 	0b1000000;			# process  ePostal only
$G_RESULT_FILES_TO_READ = 	0b0111111;			# process all result files except ePostal (default)




# we use %hashOfInvalidRegNums just so we don't report the same invalid reg num more than once.
# Currently populated when processing PMS top 10 and epostals only (other results either don't include reg numbers or
# are trusted to always have correct reg nums.)
our %hashOfInvalidRegNums = ();		# {$regnum:$fullName} = count of number of times we saw this
	# invalid regnum.
	# {$regNum:$fullName:OrgCourse} = "$currentAgeGroup,$org:$course"

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
	FS_ePostalPointEarners				=>	0,
		FS_ePostalPointEarners_Desc		=> "number of PMS swimmers who earned ePostal points",
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
# $fetchStats{'ePostalPointEarners'} = the number of PMS ePostal results that earned points

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
	"FS_ePostalPointEarners",
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
	if(0) {
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


# TT_Struct::PrintStats( "Total", TT_Struct::GetStruct(), $console );
sub PrintStats( $$$ ) {
	my ($heading, $hashRef, $console) = @_;
	foreach my $key (@fetchStatsOrder) {
		my $desc = $fetchStats{$key . "_Desc"};
		my $value = $hashRef->{$key};
		if( defined $value ) {
			PMSLogging::PrintLog( "", "", "    $heading $desc: $value", $console);
		} else {
			PMSLogging::PrintLog( "", "", "    $heading $desc: (undefined)", $console);
		}
	}
} # end of PrintStats()

# my $string = TT_Struct::PrintStatsString( "Total", TT_Struct::GetStruct() );
sub PrintStatsString( $$ ) {
	my ($heading, $hashRef) = @_;
	my $str = "";
	foreach my $key (@fetchStatsOrder) {
		my $desc = $fetchStats{$key . "_Desc"};
		my $value = $hashRef->{$key};
		if( defined $value ) {
			$str .= "    $heading $desc: $value\n";
		} else {
			$str .= "    $heading $desc: (undefined)\n";
		}
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

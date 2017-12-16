#!/usr/bin/perl -w
# TT_Struct.pm - support data structures.

package TT_Struct;

use strict;
use sigtrap;
use warnings;


###
### General Structures used by our modules
###

#my $resultHash;

# we use %hashOfInvalidRegNums just so we don't report the same invalid reg num more than once.
# Currently populated when processing PMS top 10 only (other results either don't include reg numbers or
# are trusted to always have correct reg nums.)
our %hashOfInvalidRegNums = ();		# {regnum} = ""; if we don't find the regnum
									# in the RSIDN file.

# used in excel
#our %results;			# $results{gender:ageGroup-org-course}{swimmerId} = points for PMS SCY, etc...
						# $results{gender:ageGroup-org-course-COUNT}{swimmerId} = count of # times this
						#	swimmer scored points in a org-course event.  E.g. if they scored points
						#	5 times in a PAC-SCM event then all 5 of those scores will be used to
						#	calculate their points; but if they scored 9 times only the best 8
						#	scores will count (if the rules say only count the best 8)
						


# used in excel
#our %points;			# $points{gender:ageGroup}{SwimmerId} = total top 10 points for this swimmer
#sub GetPointsRef() {
#	return \%points;
#}

#used in excel:
#our %team;				# $team{$swimmerId} = the team for the swimmer




our %numInGroup;			# $numInGroup{gender:ageGroup} = number of swimmers in this gender/age group

#our %place;				# $place{gender:ageGroup}[SwimmerId] = their place in this gender/age group.
#our %place;				# $place{gender:ageGroup}[order] = points:rank:SwimmerId = their points and place
						# in this gender/age 
						# group and the swimmer's internal swimmerId.  E.g. "123:3:234" which means that
						# the swimmer with the swimmerId of "234" is 3rd in their gender/age group with 123 points.
						# Note that multiple swimmers could have the same place if there is a tie but
						# their order will be different and consistent across executions of this program.
						# 'order' begins with 0.
#sub GetPlaceRef() {
#	return \%place;
#}


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

#!/usr/bin/perl -w
# TT_Util.pm - support utility routines.

package TT_Util;

use strict;
use sigtrap;
use warnings;



# GenerateCanonicalDurationForDB - convert the passed text representation of a time duration into
#	an integer representing the duration in hundredths of a second.
#
# PASSED:
#	$passedDuration - the duration in text form, e.g. 1:03:33.09 (1 hour, 3 minutes, 33 seconds, 9 hundredths
#		of a second)
#	$fileName - result file name
#	$lineNum - the number of the result row in the result file
#
# RETURNED:
#	$returnedDuration - the equivalent duration as an integer in hundredths of a second.
#
# NOTES:
# 	Possible formats:
#	- THE CORRECT FORMAT:  [[hh:]mm:]ss.t[h] e.g.
#		1:19:51.50 - 1*60*60*100 + 19*60*100 + 51*100 + 50
#		19:51.50 - 19*60*100 + 51*100 + 50
#		51.50 - 51*100 + 50
#
#	Allow one of '.,;:' in place of ":" and "."
#
sub GenerateCanonicalDurationForDB($$$) {
	my ($passedDuration, $fileName, $lineNum) = @_;
	my $convertedTime = $passedDuration;

	if( !defined $convertedTime ) {
		PMSLogging::DumpError( "", "", "TT_Util::GenerateCanonicalDurationForDB(): undefined time " .
			"- use \"9:59:59.00\".  File: '$fileName', line $lineNum" );
		$convertedTime = "9:59:59.00";
	}
	my $returnedDuration = 0;
	# remove leading and trailing blanks
	$convertedTime =~ s/^\s+//;
	$convertedTime =~ s/\s+$//;
	my( $hr, $min, $sec, $hundredths );
	
	if( $convertedTime =~ m/^(\d+)[.,;:](\d+)[.,;:](\d+)[.,;:](\d+)$/ ) {
		# h:m:s.th
		$hr = $1;
		$min = $2;
		$sec = $3;
		$hundredths = $4;
	} elsif( $convertedTime =~ m/^(\d+)[.,;:](\d+)[.,;:](\d+)$/ ) {
		# m:s.th
		$hr = 0;
		$min = $1;
		$sec = $2;
		$hundredths = $3;
	} elsif( $convertedTime =~ m/^(\d+)[.,;:](\d+)$/ ) {
		# s.th
		$hr = 0;
		$min = 0;
		$sec = $1;
		$hundredths = $2;
	} elsif( $convertedTime =~ m/^(\d+)$/ ) {
		# s.th
		$hr = 0;
		$min = 0;
		$sec = 0;
		$hundredths = $1;
	} else {
		# there is something wrong....
		PMSLogging::DumpError( "", "", "TT_Util::GenerateCanonicalDurationForDB(): invalid time " .
			"in GenerateCanonicalDurationForDB: '$passedDuration' " .
			" - use \"9:59:59.00\".  File: '$fileName', line $lineNum" );
		$hr = 9; $min = 59; $sec = 59; $hundredths = 00;
	}
    # convert ".5" to ".50"
    $hundredths .= "0" if( length( $hundredths ) == 1 );
	$convertedTime = "$hr:$min:$sec.$hundredths";
	$returnedDuration = $hr*60*60*100 + $min*60*100 + $sec*100 + $hundredths;
	return $returnedDuration;
} # end of GenerateCanonicalDurationForDB()




1;  # end of module

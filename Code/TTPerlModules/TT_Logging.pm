#!/usr/bin/perl -w
# TT_Logging.pm - support utility routines.

package TT_Logging;

use strict;
use sigtrap;
use warnings;


# 		HandleHTTPFailure( $linkToResults, $org, $course, $httpResponse ) 
# HandleHTTPFailure - print out an error message after an HTTP error
#
# PASSED:
#	$linkToResults -
#	$org -
#	$course -
#	$httpResponse -
#
#
sub HandleHTTPFailure( $$$$ ) {
	my ($linkToResults, $org, $course, $httpResponse) = @_;
	PMSLogging::PrintLog( "", "", "GetResults::HandleHTTPFailure(): HTTP Request to '$linkToResults' " .
		"(org:'$org', course:'$course') failed.  " .
		"status: '$httpResponse->{status}', reason: '$httpResponse->{reason}'", 1 );
} # end of HandleHTTPFailure()




1;  # end of module

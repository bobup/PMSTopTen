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
	my ($linkToResults, $org, $course, $httpResponse, $extraNote ) = @_;
	if( !defined $extraNote ) {
		$extraNote = "";
	} else {
		$extraNote = " ($extraNote)";
	}
	my $success = $httpResponse->{"success"};
	$success = "(undefined)" if( !defined( $success ) );
	my $content=$httpResponse->{"content"};
	$content =~ s/\s+$//;
	PMSLogging::PrintLog( "", "", "HandleHTTPFailure(): HTTP Request to '$linkToResults'\n" .
		"    (org:'$org', course:'$course') failed. {success}: $success, " .
		"{status}: '$httpResponse->{status}', {reason}: '$httpResponse->{reason}',\n" .
		"    Text of Exception ({content}): '$content',\n" .
		"    {url}: '$httpResponse->{url}$extraNote'\n", 1 );
} # end of HandleHTTPFailure()




1;  # end of module

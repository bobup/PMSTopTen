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
		$extraNote = "\n    ($extraNote)";
	}
	my $success = $httpResponse->{"success"};
	$success = "(undefined)" if( !defined( $success ) );
	my $content=$httpResponse->{"content"};
	$content =~ s/\s+$//;
	my $status = $httpResponse->{"status"};
	my $textOfException = "";
	if( ($status == 599) || ($status == 99999) ) {
		$textOfException = "    Text of Exception (http $status) ({content}): '$content',\n";
	}
	PMSLogging::PrintLog( "", "", "HandleHTTPFailure(): HTTP Request to '$linkToResults'\n" .
		"    (org:'$org', course:'$course') failed. {success}: $success, " .
		"{status}: '$status', {reason}: '$httpResponse->{reason}',\n" .
		"$textOfException" .
		"    {url}: '$httpResponse->{url}$extraNote'\n", 1 );
} # end of HandleHTTPFailure()




1;  # end of module

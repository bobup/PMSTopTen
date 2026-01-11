#!/usr/bin/perl -w
# TT_Logging.pm - support utility routines.

# Copyright (c) 2017 Bob Upshaw.  This software is covered under the Open Source MIT License 

package TT_Logging;

use strict;
use sigtrap;
use warnings;
require Devel::StackTrace;



# 		HandleHTTPFailure( $linkToResults, $org, $course, $httpResponse ) 
# HandleHTTPFailure - print out an error message after an HTTP error
#
# PASSED:
#	$linkToResults -
#	$org -
#	$course -
#	$httpResponse -
#	$extraNote -
#
#
sub HandleHTTPFailure( $$$$$ ) {
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
	
	my $stackTraceAsString = PMSUtil::GetStackTrace();
	my $lengthOfContent = 80;
	PMSLogging::PrintLog( "", "", "\nHandleHTTPFailure(): HTTP Request to '$linkToResults'\n" .
		"    (org:'$org', course:'$course') failed. httpResponse->{success}='$success', " .
		"httpResponse->{status}='$status',\n" .
		"    httpResponse->{reason}='$httpResponse->{reason}', " .
		"First $lengthOfContent chars of httpResponse->{content}='" . 
			substr( $content, 0, $lengthOfContent ) . "'\n" .
		"    httpResponse->{url}='$httpResponse->{url}'$extraNote'", 1 );

	PMSLogging::PrintLog( "", "", "HandleHTTPFailure() Stack trace: $stackTraceAsString", 0 );

} # end of HandleHTTPFailure()




1;  # end of module

#!/usr/bin/perl -w
# TT_SheetSupport.pm - support routines for Excel files.
#
# Copyright (c) 2017 Bob Upshaw.  This software is covered under the Open Source MIT License 

package TT_SheetSupport;


use Spreadsheet::Read;
use Text::CSV_XS;

use strict;
use sigtrap;
use warnings;

my $debug = 1;	# set >0 to turn on debugging

# OpenSheetFile - open an excel (.xlsx or .csv) file for reading
#
# PASSED:
#	$fileName - the full path name of the file we're going to open
#
# RETURNED:
#	%ssHandle - a hash whose fields define the opened file.  Fields:
#		fileRef - file reference used to read the file
#		csv - 0 if this file is an Excel (.xlsx) file, otherwise it's a csv or other txt file.
#		separator - 0 if this file is an Excel (.xlsx) file, otherwise it will be either ',' for
#			a csv file or '\t' for a .txt file.
#		nextRow - row # of first row (1)
#		numRows - if > 0 this is the number of rows in the .xlsx file; otherwise it's not a .xlsx file.
#		numCols - if > 0 this is the number of columns in the .xlsx file; otherwise it's not a .xlsx file.
#
sub OpenSheetFile($) {
	my $fileName = $_[0];
	my %ssHandle = (
		"fileName" => "",		# will contain file name if the file was opened correctly
		"fileRef" => 0,			# 0 -> unused/closed handle
		"csv" => 0,				# 0 -> excel file, otherwise txt or csv file
		"separator" => 0,		# 0 -> excel file, otherwise txt or csv file
		"nextRow"	=> 1,
		"numRows" => 0,			# 0 -> txt or csv file, otherwise excel file
		"numCols" => 0,			# 0 -> txt or csv file, otherwise excel file
	);
	
    # what kind of file is this?  Use the file extension to tell us:
    my $ext = $fileName;
    $ext =~ s/^.*\.//;
    $ext = lc( $ext );

    # Now, get to work!
    if( ! $ext ) {
    	# no extension?  give up
		PMSLogging::DumpError( "", "", "  TT_SheetSupport::OpenSheetFile(): file '$fileName': No extension - " .
			"SKIPPING THIS FILE", 1 );
    } elsif( ($ext eq "txt") || ($ext eq "csv") ) {
    	# csv or tab-seperated file
    	my $separator = "\t";
    	$separator = "," if( $ext eq "csv" );
        my @rows;
 #       my $csv = Text::CSV_XS->new ({ binary => 1, sep_char => $separator, keep_meta_info => 1 }) or
        my $csv = Text::CSV_XS->new ({ binary => 1, sep_char => $separator }) or
             die "Cannot use CSV: ".Text::CSV_XS->error_diag ();
#        open my $fh, "<:encoding(utf8)", "$fileName" or die "TT_SheetSupport::OpenSheetFile(): " .
        open my $fh, "<:encoding(iso-8859-1)", "$fileName" or die "TT_SheetSupport::OpenSheetFile(): " .
         	"ABORT: Can't open '$fileName': $!";
		PMSLogging::PrintLog( "", "", "  TT_SheetSupport::OpenSheetFile(): file $fileName: Number of sheets:  1 (it's a " .
        	( $separator eq "," ? "comma-separated" : "tab-separated" ) . " .$ext file).", 1 ) if( $debug >= 1);
		$ssHandle{"fileRef"} = $fh;
		$ssHandle{"csv"} = $csv;
		$ssHandle{"separator"} = $separator;
		$ssHandle{"fileName"} = $fileName;		
    } elsif( $ext eq "xlsx") {
    	my $result = 0;
	    # read the spreadsheet
	    my $g_ref = ReadData( $fileName );
	    # NOTE:  if the file doesn't exist the above returns a null or empty (?) ref which causes errors below
	    # $g_ref is an array reference
	    # $g_ref->[0] is a reference to a hashtable:  the "control hash"
	    my $numSheets = $g_ref->[0]{sheets};        # number of sheets, including empty sheets
		if( ! defined( $numSheets ) ) {
			PMSLogging::DumpWarning( "", "", "  TT_SheetSupport::OpenSheetFile(): file $fileName: Number of sheets is undefined\n" .
				"    - Assume this file does not exist - SKIPPING THIS FILE", 1 );
		} else {
		    PMSLogging::DumpNote( "", "", "  TT_SheetSupport::OpenSheetFile(): file $fileName: Number of sheets:  $numSheets. " .
		    	"Non-empty sheets follow:", 1 ) if( $debug > 0);
		    my $sheetNames_ref = $g_ref->[0]{sheet};  # reference to a hashtable containing names of non-empty sheets.  key = sheet
		                                              # name, value = monotonically increasing integer starting at 1 
		    my %tmp = % { $sheetNames_ref } ;         # hashtable of sheet names (above)
		    my ($sheetName);
		    foreach $sheetName( sort { $tmp{$a} <=> $tmp{$b} } keys %tmp ) {
		        PMSLogging::DumpNote( "", "", "  TT_SheetSupport::OpenSheetFile():   Non-empty sheet name: $sheetName", 1 ) if( $debug > 0 );
		    }
		    # get the first sheet
		    my $g_sheet1_ref = $g_ref->[1];         # reference to the hashtable representing the sheet
		    my $numRows = $g_sheet1_ref->{maxrow};
		    my $numColumns = $g_sheet1_ref->{maxcol};
			PMSLogging::DumpNote( "", "", "  TT_SheetSupport::OpenSheetFile(): First sheet: numRows=$numRows, " .
		    	"numCols=$numColumns", 1 ) if( $debug > 0 );
			$ssHandle{"fileRef"} = $g_sheet1_ref;
			$ssHandle{"numRows"} = $numRows;
			$ssHandle{"numCols"} = $numColumns;
			$ssHandle{"fileName"} = $fileName;		
		}

    } else {
    	# don't recognize the extension
		PMSLogging::DumpError( "", "", "  TT_SheetSupport::OpenSheetFile(): file '$fileName': Unrecognized extension - " .
			"SKIPPING THIS FILE", 1 );
    }
	return %ssHandle;
	
} # end of OpenSheetFile()


# ReadSheetRow - return array of fields, with whitespace trimmed from both ends.
#
# PASSED:
#	$ssHandleRef - reference to a ssHandle hash.  See OpenSheetFile() for a definition of a ssHandle hash.
#
# RETURNED:
#	@row - an array of fields representing the row just read.
#
sub ReadSheetRow($) {
	my $ssHandleRef = $_[0];
	my @row = ();
	my $currentRowNumber = $ssHandleRef->{'nextRow'}++;
	my $sheetRef = $ssHandleRef->{'fileRef'};
	
	if( $ssHandleRef->{'numRows'} == 0 ) {
		# this is a txt/csv file - get the next line from the file
		my $rowRef = $ssHandleRef->{'csv'}->getline($sheetRef);
		if( defined $rowRef ) {
			my $rowLen = scalar( @{$rowRef} );
			for( my $i=0; $i < $rowLen; $i++ ) {
				$row[$i] = PMSUtil::trim( $rowRef->[$i] );
			}
		}
	} else {
		# this is an excel file
		if( $currentRowNumber <= $ssHandleRef->{'numRows'} ) {
			for( my $colNum = 1; $colNum <= $ssHandleRef->{"numCols"}; $colNum++ ) {
		    	my $field = PMSUtil::trim( $sheetRef->{cell}[$colNum][$currentRowNumber] );
		    	$row[$colNum-1] = $field;
			}
		}
	}
	
	return @row;
} # end of ReadSheetRow()


# 	TT_SheetSupport::CloseSheet( \%sheetHandle );
# CloseSheet - close the file represented by the passed sheet handle
#
# PASSED:
#	$ssHandleRef - reference to the %ssHandle the represents the file to be closed
#
# RETURNED:
#	n/a
#
# NOTES:
#	The passed %ssHandle is modified by setting its 'fileRef' field to 0, representing 
#	an unused %ssHandle.
#
sub CloseSheet($) {
	my $ssHandleRef = $_[0];
	if( $ssHandleRef->{'fileRef'} == 0 ) {
		# handle already closed
		PMSLogging::DumpError( "", "", "TT_SheetSupport::CloseSheet(): Called on already closed handle" );
	} elsif( $ssHandleRef->{'separator'} ne 0 ) {
		# a text/csv file - close it
		close( $ssHandleRef->{'fileRef'} );
	}
	# mark handle as closed
	$ssHandleRef->{'fileRef'} = 0;
} # end of CloseSheet()



1;  # end of module

#!/usr/bin/perl

use strict;
use lib '/Users/bobup/Development/PacificMasters/PMSPerlModules';
use DateTime::Format::Strptime;
use POSIX 'strftime';

require PMSUtil;




my $debug = 0;

# define the directory holding the log files to be processed:
my $rootDir = "/Users/bobup/Development/PacificMasters/AnalyzeAccessLogs/siteStats/4nov2018Generated-original";
my $simpleFileName = xxxx;
my $totalNumRows = 0;
	my $filename = "$rootDir/$simpleFileName";

	my $seperator = ",";
	my $lineNum = 0;
	open( PROPERTYFILE, "< $filename" ) || die( "TTStatsDiffFilter.pl:  Can't open $filename: $!" );
	while( my $line = <PROPERTYFILE> ) {
		
		
		
		
		my $value = "";
		$lineNum++;
		chomp( $line );
		#print "Line #$lineNum: '$line'\n";
		# remove comments:
		$line =~ s/\s*#.*$//;
		next if( $line eq "" );
		# split on commas
 
 
	my $numRows = ProcessResultFile( $RootDir, $file );
	$totalNumRows += $numRows;
	if( $debug > 1 ) {
		print "Processing $file.  Number of page hits: $numRows\n";
	}
}
if( $debug > 1 ) {
	print "Total page hits:  $totalNumRows\n";
}

foreach my $ip( keys %AccessCounts ) {
	# looking for ip's only
	next if( $ip =~ m/-/ );
	$TotalDiffIPs++;
	my $totalHits = $AccessCounts{$ip};
	print "Total number of hits for ip '$ip': $totalHits\n" if( $debug > 1);
	$TotalHitsPerIP[$totalHits]++;
	foreach my $monNum( 1,2,3,4,5,6,7,8,9,10,11,12) {
		my $numHits = $AccessCounts{"$ip-$monNum"};
		if( (defined $numHits) && ($numHits > 0) ) {
			$SwimmersPerMonth[$monNum]++;
			$HitsPerMonth[$monNum] += $numHits;
			print "  Number of hits in " . $numToMonHash{$monNum} . ": $numHits\n" if( $debug > 1 );
		}
	}
}
print "Total different number of IPs seen: $TotalDiffIPs\n\n" if( $debug > 1 );

# how many months are we considering?
my $samplePeriod = 0;
foreach my $monNum (1..12) {
	next if( (!defined $SwimmersPerMonth[$monNum]) || ($SwimmersPerMonth[$monNum] == 0) );
	$samplePeriod++;
}

if( $debug > 1 ) {
	print "\n# Swimmers Per Page Hit (considering $samplePeriod months of $currentYear):\n";
}
my $totDiffSwimmers = 0;

# $averageSwimmersPerMonth[i] = number of swimmers who hit the AGSOTY page at least 'i' times a month on average
# $averageSwimmersPerMonth[0] = number of swimmers who hit the AGSOTY page less than once a month on average
# (e.g. if a swimmer hits the AGSOTY page 15 times in a 6 month sample then that swimmer averaged 2 hits per month)
my @averageSwimmersPerMonth;

# $mostActiveSwimmerHits is the number of times the most active swimmer hit the AGSOTY pages during
# our sample period.
my $mostActiveSwimmerHits = scalar @TotalHitsPerIP - 1;
for my $i (1..$mostActiveSwimmerHits) {
	if( defined $TotalHitsPerIP[$i] ) {
		my $swimmer_s = "s";
		my $time_s = "s";
		my $tot = $TotalHitsPerIP[$i];
		$totDiffSwimmers+=$tot;
		$swimmer_s = "" if( $tot == 1 );
		$time_s = "" if( $i == 1 );
		if( $debug > 1 ) {
			print "  $tot swimmer$swimmer_s hit the AGSOTY Points page exactly $i time$time_s\n";
		}
		my $averageHitsPerMonth = int($i/$samplePeriod);
		$averageSwimmersPerMonth[$averageHitsPerMonth] += $tot;
	}
}
if( $debug > 1 ) {
	print "(That's a total of $totDiffSwimmers different swimmers.)\n\n";
}

print "After analyzing our logs covering $samplePeriod months of $currentYear here is what we found:\n";
# compute the average hits per month made by the most active swimmer:
my $mostActiveTimesPerMonth = int($mostActiveSwimmerHits / $samplePeriod);
if( $debug ) {
	print "mostActiveSwimmerHits=$mostActiveSwimmerHits, mostActiveTimesPerMonth=$mostActiveTimesPerMonth\n";
}
my $lastNumSwimmers = -1;
for my $timesPerMonth (reverse(0 .. $mostActiveTimesPerMonth)) {
	my $totalHits = 0;
	# how many total page hits does a swimmer have to make to average $timesPerMonth hits per month?
	my $numHitsSameAverage = $timesPerMonth * $samplePeriod;
	# compute the number of swimmers who averaged this many hits per month
	my $numSwimmers = 0;
	my $i = $mostActiveSwimmerHits;
	
	while( $i >= $numHitsSameAverage) {
		if( defined $TotalHitsPerIP[$i] ) {
			$numSwimmers += $TotalHitsPerIP[$i];
			$totalHits += ($i * $TotalHitsPerIP[$i]);
		}
		if( $debug ) {
			print ("i=$i, numSwimmers=$numSwimmers, totalHits=$totalHits\n");
		}
		$i--;
	}
	if( $debug ) {
		print "timePerMonth=$timesPerMonth, numHitsSameAverage=$numHitsSameAverage, numSwimmers=$numSwimmers\n";
	}
	if( $numSwimmers != $lastNumSwimmers ) {
		if( $timesPerMonth < 1 ) {
			print "  A total of $numSwimmers swimmers hit the AGSOTY page at least once. Total hits: $totalHits\n";
		} else {
			print "  $numSwimmers swimmers averaged $timesPerMonth or more hits of the AGSOTY page per month." .
				"  Total hits: $totalHits\n";
		}
		$lastNumSwimmers = $numSwimmers;
	}
}

if(0) {
	for my $i (0..scalar @averageSwimmersPerMonth) {
		my $xxx = "(undefined)";
		$xxx = $averageSwimmersPerMonth[$i] if( defined $averageSwimmersPerMonth[$i] );
		print "averageSwimmersPerMonth[$i] = $xxx\n";
	}
}


$totDiffSwimmers = 0;
print "\n# Swimmers Hitting our AGSOTY Page Each Month (considering $samplePeriod months of $currentYear):\n";
foreach my $monNum (1..12) {
	next if( (!defined $SwimmersPerMonth[$monNum]) || ($SwimmersPerMonth[$monNum] == 0) );
	$totDiffSwimmers += $SwimmersPerMonth[$monNum];
	print "  " . $numToMonHash{$monNum} . ": $SwimmersPerMonth[$monNum]  ($HitsPerMonth[$monNum] hits)\n";
}
print "Total page hits:  $totalNumRows\n";

# get the date/time we're starting:
my $dateTimeFormat = '%a %b %d %Y %Z %I:%M:%S %p';
my $currentDateTime = strftime $dateTimeFormat, localtime();
#print "currentDateTime=$currentDateTime, localtime=" . scalar localtime . "\n";
print "\nAnalysis completed on $currentDateTime\n\n";

### END


#         if( DuplicateRow( $ip, $date, $time ) ) {
sub DuplicateRow( $$$ ) {
	my ($ip, $date, $time) = @_;
	my $result = 0;
	my $key = "$ip-$date-$time";
	if( defined( $AccessCounts{$key} ) ) {
		$result = 1;
	} else {
		my $dateTimeStr = $date . "T" . $time;
		my $strp = DateTime::Format::Strptime->new(
    		pattern   => '%d/%b/%YT%T',
    	);
    	my $dt = $strp->parse_datetime( $dateTimeStr );
    	my $dtStr = $strp->format_datetime( $dt );
#    	print "'$dateTimeStr' == '$dtStr'....";
		# have we already seen a hit 1 second prior to this hit?  If so consider it a duplicate:
    	my $previousSecond = $dt - DateTime::Duration->new( seconds => 1 );
    	my $previousSecondStr = $strp->format_datetime( $previousSecond );
#    	print "'$previousSecondStr'\n";
    	my $previousSecondTime = $previousSecondStr;
    	$previousSecondTime =~ s/^.*T//;
    	my $previousSecondKey = "$ip-$date-$previousSecondTime";
#    	print "key='$key', previousSecondKey='$previousSecondKey'\n";
		if( defined( $AccessCounts{$previousSecondKey} ) ) {
			$result = 1;
		}
		# have we already seen a hit 1 second later than this hit?  If so consider it a duplicate:
    	my $followingSecond = $dt + DateTime::Duration->new( seconds => 1 );
    	my $followingSecondStr = $strp->format_datetime( $followingSecond );
#    	print "'$followingSecond'\n";
    	my $followingSecondTime = $followingSecond;
    	$followingSecondTime =~ s/^.*T//;
    	my $followingSecondKey = "$ip-$date-$followingSecondTime";
#    	print "key='$key', $followingSecondKey='$followingSecondKey'\n";
		if( defined( $AccessCounts{$followingSecondKey} ) ) {
			$result = 1;
		}

	}
	return $result;
} # end of DuplicateRow()

		
# column order:  IP address, date dd/mmm/yyyy, time, referrer url, browser
sub ProcessResultFile( $$ ) {
	my( $rootDir, $simpleFileName ) = @_;
    my $numUsedRows = 0;
	my $filename = "$rootDir/$simpleFileName";

	my $seperator = ",";
	my $lineNum = 0;
#	local $/ = "\r";
	open( PROPERTYFILE, "< $filename" ) || die( "ProcessResultFile():  Can't open $filename: $!" );
	while( my $line = <PROPERTYFILE> ) {
		my $value = "";
		$lineNum++;
		chomp( $line );
		#print "Line #$lineNum: '$line'\n";
		# remove comments:
		$line =~ s/\s*#.*$//;
		next if( $line eq "" );
		# split on commas
		# the 'browser' field may have commas...
		my @fields = split( $seperator, $line, 5 );
		my ($abbr, $fullName) = @fields;
        my $ip = PMSUtil::trim(lc($fields[0]));
        my $date = PMSUtil::trim(lc($fields[1]));
        my $time = PMSUtil::trim(lc($fields[2]));
        my $url = PMSUtil::trim(lc($fields[3]));
        # is this an empty row?
        if( (!defined $ip) || ($ip eq "") ) {
        	next;
        }
        # is this a log entry we care about?
        if( DuplicateRow( $ip, $date, $time ) ) {
        	# we don't want this row - it's a duplicate
		    if( $debug > 1 ) {
		        print "IGNORE DUPLICATE: $lineNum: IP is '$ip', date='$date', time='$time', url='$url'\n";
		    }
        	next;
        } else {
        	# yes, we care about this row!
	        if( $debug > 1 ) {
	        	print "Use this: $lineNum: IP is '$ip', date='$date', time='$time', url='$url'\n";
	        }
	        $numUsedRows++;
	        my $monthNum = GetMonthNum( $date );
	        $AccessCounts{$ip}++;
	        $AccessCounts{"$ip-$monthNum"}++;
	        $AccessCounts{"$ip-$date-$time"} = 1;
        }
	} # end of while(...

    return $numUsedRows;

} # end of ProcessResultFile()
		


    
    

# 	        my $monthNum = GetMonthNum( $date );
sub GetMonthNum( $ ) {
	my $result = 0;
	my $month = $_[0];
	my %monToNumHash = qw (
		jan 1
		feb 2
		mar 3
		apr 4  
		may 5  
		jun 6
  		jul 7  
  		aug 8  
  		sep 9  
  		oct 10 
  		nov 11 
  		dec 12
	);
	$month =~ s,^[^-/]+[/-],,;
	$month =~ s,[/-].*$,,;
	$result = $monToNumHash{ $month };
	return $result;
} # end of GetMonthNum()




# TimeCloseToPreviousTime( $time, $previousTime ) ) {
sub TimeCloseToPreviousTime( $$ ) {
	my $result = 0;
	my( $time, $previousTime ) =  @_;
	
	# temporary solution...
	$result = $time eq $previousTime;
	return $result;
	
} # end of TimeCloseToPreviousTime()

	
	
	
	
	
	
	
	
exit;
# =======================================================================================
sub ProcessResultFile_old( $$ ) {
	my( $rootDir, $simpleFileName ) = @_;
    my $numUsedRows = 0;
	my $filename = "$rootDir/$simpleFileName";
my @requiredURLs = ("laura-val-swimmer-year-awards", "pacificmasters.org/points/standings-2018/");

    # get some info about this spreadsheet (e.g. # sheets, # rows and columns in first sheet, etc)
    my $g_ref = ReadData( $filename );
    # $g_ref is an array reference
    # $g_ref->[0] is a reference to a hashtable:  the "control hash"
    my $numSheets = $g_ref->[0]{sheets};        # number of sheets, including empty sheets
    print "\nfile $filename:\n  Number of sheets:  $numSheets.\n  Names of non-empty sheets:\n" 
    	if( $debug > 1);
    my $sheetNames_ref = $g_ref->[0]{sheet};  # reference to a hashtable containing names of non-empty sheets.  key = sheet
                                              # name, value = monotonically increasing integer starting at 1 
    my %tmp = % { $sheetNames_ref } ;         # hashtable of sheet names (above)
    my ($sheetName);
    if( $debug > 1 ) {
	    foreach $sheetName( sort { $tmp{$a} <=> $tmp{$b} } keys %tmp ) {
	        print "    $sheetName\n" ;
	    }
    }
    
    # get the first sheet
    my $g_sheet1_ref = $g_ref->[1];         # reference to the hashtable representing the sheet
    my $numRowsInSpreadsheet = $g_sheet1_ref->{maxrow};	# number of rows in spreadsheet file
    my $numColumnsInSpreadsheet = $g_sheet1_ref->{maxcol};
    print "numRows=$numRowsInSpreadsheet, numCols=$numColumnsInSpreadsheet\n" if( $debug > 1 );

    # Now, pass through the sheet collecting data on the interesting log data:
    my $rowNum;
    my $previousDate = "";
    my $previousTime = "";
    for( $rowNum = 1; $rowNum <= $numRowsInSpreadsheet; $rowNum++ ) {
    	if( ($rowNum % 1000) == 0 ) {
    		print "...working on row $rowNum...\n";
    	}
        my $ip = PMSUtil::trim(lc($g_sheet1_ref->{"A$rowNum"}));
        my $date = PMSUtil::trim(lc($g_sheet1_ref->{"B$rowNum"}));
        my $time = PMSUtil::trim(lc($g_sheet1_ref->{"C$rowNum"}));
        my $url = PMSUtil::trim(lc($g_sheet1_ref->{"D$rowNum"}));
        # is this an empty row?
        if( (!defined $ip) || ($ip eq "") ) {
        	next;
        }
        # is this a log entry we care about?
        my $weCareAboutThisRow = 0;
        foreach my $requiredURL (@requiredURLs) {
        	if( index( $url, $requiredURL ) != -1 ) {
        		# yes!
        		$weCareAboutThisRow = 1;
        		last;
        	}
        }
        if( $weCareAboutThisRow ) {
        	# yes, we care about this row! But is it a duplicate?
        	if( ($date eq $previousDate) && TimeCloseToPreviousTime( $time, $previousTime ) ) {
        		# yes, duplicate - ignore this row
		        if( $debug > 1 ) {
		        	print "IGNORE DUPLICATE: $rowNum: IP is '$ip', date='$date', time='$time', url='$url'\n";
		        }
        		next;
        	}
	        if( $debug > 1 ) {
	        	print "Use this: $rowNum: IP is '$ip', date='$date', time='$time', url='$url'\n";
	        }
	        $numUsedRows++;
	        my $monthNum = GetMonthNum( $date );
	        $AccessCounts{$ip}++;
	        $AccessCounts{"$ip-$monthNum"}++;
        } else {
        	# no...
	        if( $debug > 1 ) {
	        	print "IGNORE this: $rowNum: IP is '$ip', date='$date', time='$time', url='$url'\n";
	        }
        }
    } # end of for( ...
    
    return $numUsedRows;
    
} # end of ProcessResultFile()
   
   
  # 		my $tot = SumArray( \@averageSwimmersPerMonth, $i );
sub SumArray( $$$ ) {
	my( $arrRef, $index, $maxIndex ) = @_;
	my $total = 0;
	for my $i (1..$maxIndex-1) {
		if( defined( $arrRef->[$i] ) ) {
			$total += $arrRef->[$i];
		}
	}
	return $total;
} # end of SumArray()


# =======================================================================================
    
    
  # end of AnalyzeAccessLogs.pl

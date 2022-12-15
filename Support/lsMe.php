<?php

// lsMe.php - dump the names of the files in the current directory, or the 
//	directory passed as the last GET parameter. If a GET parameter is passed then
//	only the key is used as the directory to ls. If there is an associated value to
//	that key it is ignored UNLESS it is the word "Please", in which case the full path
//	name of the directory is also displayed.

$dir = ".";
unset( $value );
$dumpDirName = 0;

foreach ($_GET as $key => $value ) {
	$dumpDirName = 0;
	$dir = htmlspecialchars( $key );
	$dir = str_replace( "_", ".", $dir );
	if( ! empty( $value ) ) {
		if( $value == "Please" ) $dumpDirName = 1;
	}
}

$path = realpath( $dir );
if( $dumpDirName ) {
	print "$path:<br>";
} 

$arrFiles = scandir( $dir );
foreach( $arrFiles as $fileName ) {
	$fullPathName = $path . "/" . $fileName;
	$modDate = date ("F d Y H:i:s.", filemtime($fullPathName));
	print "$modDate &nbsp;&nbsp;&nbsp; $fileName<br>";
}
?>



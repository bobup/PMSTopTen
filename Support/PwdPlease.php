<?php
/*
 * PwdPlease.php - display the contents of the parent directory of the
 *	directory holding this script.
 */

$cwdName = getcwd();
$dirSimpleName = basename( dirname( $cwdName ) );
?>
<html>
<head>
<title><?php
echo "Contents of $dirSimpleName";
?></title>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1">
</head>
<body>
<?php
echo "<h2>Contents of $dirSimpleName</h2>\n";
$files = scandir( ".." );
foreach( $files as $file ) {
	if( substr( $file, 0, 1 ) === '.' ) continue;
	$dir = "";
	if( is_dir( $file ) ) $dir = '/';
	echo "<br>$file$dir\n";
}

echo "<h2>Contents of $cwdName</h2>\n";
$files = scandir( "." );
foreach( $files as $file ) {
	if( substr( $file, 0, 1 ) === '.' ) continue;
	$dir = "";
	if( is_dir( $file ) ) $dir = '/';
	echo "<br>$file$dir\n";
}

?>
</body>
</html>


<html>
<head>
</head>
<body>
<?php 
echo "The date \n";
//echo strtotime("-3 month"), "\n";
$d = new DateTime( 'sunday last week' );
echo $d->format( 'Y-m-d' ), "<p>\n";
$d->modify( 'monday this week' );
echo $d->format( 'Y-m-d' ), "\n";
echo "End\n";
?>
</body>
</html>

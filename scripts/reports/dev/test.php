<?php 

  // create an array of values for the chart. These values 
  // could come from anywhere, POST, GET, database etc. 
  $values = array(23,32,35,57,12,3,36,54,32,15,43,24,30); 

  // now we get the number of values in the array. this will 
  // tell us how many columns to plot 
    $columns  = count($values); 

  // set the height and width of the graph image 

    $width = 300; 
    $height = 200; 

  // Set the amount of space between each column 
    $padding = 5; 

  // Get the width of 1 column 
    $column_width = $width / $columns ; 

  // set the graph color variables 
    $im        = imagecreate($width,$height); 
    $gray      = imagecolorallocate ($im,0xcc,0xcc,0xcc); 
    $gray_lite = imagecolorallocate ($im,0xee,0xee,0xee); 
    $gray_dark = imagecolorallocate ($im,0x7f,0x7f,0x7f); 
    $white     = imagecolorallocate ($im,0xff,0xff,0xff); 

  // set the background color of the graph 
    imagefilledrectangle($im,0,0,$width,$height,$white); 


  // Calculate the maximum value we are going to plot 
  $max_value = max($values);

  // loop over the array of columns 
    for($i=0;$i<$columns;$i++) 
        {
    // set the column hieght for each value 
        $column_height = ($height / 100) * (( $values[$i] / $max_value) *100); 
    // now the coords
        $x1 = $i*$column_width; 
        $y1 = $height-$column_height; 
        $x2 = (($i+1)*$column_width)-$padding; 
        $y2 = $height; 

        // write the columns over the background 
        imagefilledrectangle($im,$x1,$y1,$x2,$y2,$gray); 

        // This gives the columns a little 3d effect 
        imageline($im,$x1,$y1,$x1,$y2,$gray_lite); 
        imageline($im,$x1,$y2,$x2,$y2,$gray_lite); 
        imageline($im,$x2,$y1,$x2,$y2,$gray_dark); 
        } 

   // set the correct png headers 
   header ("Content-type: image/png"); 
  // spit the image out the other end 
  imagepng($im); 
?>





<?php
/*
 * Chart data
 */
$data = [
    'Jan' => 103,
    'Feb' => 24,
    'Mar' => 44,
    'Apr' => 14,
    'May' => 89,
    'Jun' => 147,
    'Jul' => 181,
    'Aug' => 172,
    'Sep' => 52,
    'Oct' => 106,
    'Nov' => 121,
    'Dec' => 76,
];
/*
 * Chart settings and create image
 */
// Image dimensions
$imageWidth = 700;
$imageHeight = 400;
// Grid dimensions and placement within image
$gridTop = 40;
$gridLeft = 50;
$gridBottom = 340;
$gridRight = 650;
$gridHeight = $gridBottom - $gridTop;
$gridWidth = $gridRight - $gridLeft;
// Bar and line width
$lineWidth = 1;
$barWidth = 20;
// Font settings
$font = 'OpenSans-Regular.ttf';
$fontSize = 10;
// Margin between label and axis
$labelMargin = 8;
// Max value on y-axis
$yMaxValue = 200;
// Distance between grid lines on y-axis
$yLabelSpan = 40;
// Init image
$chart = imagecreate($imageWidth, $imageHeight);
// Setup colors
$backgroundColor = imagecolorallocate($chart, 255, 255, 255);
$axisColor = imagecolorallocate($chart, 85, 85, 85);
$labelColor = $axisColor;
$gridColor = imagecolorallocate($chart, 212, 212, 212);
$barColor = imagecolorallocate($chart, 47, 133, 217);
imagefill($chart, 0, 0, $backgroundColor);
imagesetthickness($chart, $lineWidth);
/*
 * Print grid lines bottom up
 */
for($i = 0; $i <= $yMaxValue; $i += $yLabelSpan) {
    $y = $gridBottom - $i * $gridHeight / $yMaxValue;
    // draw the line
    imageline($chart, $gridLeft, $y, $gridRight, $y, $gridColor);
    // draw right aligned label
    $labelBox = imagettfbbox($fontSize, 0, $font, strval($i));
    $labelWidth = $labelBox[4] - $labelBox[0];
    $labelX = $gridLeft - $labelWidth - $labelMargin;
    $labelY = $y + $fontSize / 2;
    imagettftext($chart, $fontSize, 0, $labelX, $labelY, $labelColor, $font, strval($i));
}
/*
 * Draw x- and y-axis
 */
imageline($chart, $gridLeft, $gridTop, $gridLeft, $gridBottom, $axisColor);
imageline($chart, $gridLeft, $gridBottom, $gridRight, $gridBottom, $axisColor);
/*
 * Draw the bars with labels
 */
$barSpacing = $gridWidth / count($data);
$itemX = $gridLeft + $barSpacing / 2;
foreach($data as $key => $value) {
    // Draw the bar
    $x1 = $itemX - $barWidth / 2;
    $y1 = $gridBottom - $value / $yMaxValue * $gridHeight;
    $x2 = $itemX + $barWidth / 2;
    $y2 = $gridBottom - 1;
    imagefilledrectangle($chart, $x1, $y1, $x2, $y2, $barColor);
    // Draw the label
    $labelBox = imagettfbbox($fontSize, 0, $font, $key);
    $labelWidth = $labelBox[4] - $labelBox[0];
    $labelX = $itemX - $labelWidth / 2;
    $labelY = $gridBottom + $labelMargin + $fontSize;
    imagettftext($chart, $fontSize, 0, $labelX, $labelY, $labelColor, $font, $key);
    $itemX += $barSpacing;
}
/*
 * Output image to browser
 */
header('Content-Type: image/png');
imagepng($chart);

?>
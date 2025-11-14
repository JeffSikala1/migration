<?php

// Author: Madhav.Kundala@usda.gov
// Date Created: 10/25/2019
// Date Modified:
// plot sla bar.

header("Content-type:image/png");

printbar($_GET["sla"]);

function printbar($sla) {

    $width = 201;  // 2x size like 200%
    $height = 18;

    $im = imagecreatetruecolor($width,$height);

    $green = imagecolorallocate($im, 0, 255, 0);
    
    $red = imagecolorallocate($im, 255, 0, 0);
    imagefilledrectangle ($im,0,0,$width - 1,$height,$red);
    imagefilledrectangle ($im,0,0,$sla * 2,$height,$green);


    // sla slaim
    $slaim = imagecreatetruecolor($width, $height);
    imagefilledrectangle ($slaim,0,0,$width - 1,$height,$red);
    imagefilledrectangle ($slaim,0,0,$sla * 2,$height,$green);
    //$trans = imagecolorallocatealpha($slaim, 0, 0, 0, 127);
    //imagefill($slaim, 0, 0, $trans);
    //$grey = imagecolorallocate($slaim, 255, 244, 79);
    //$grey = imagecolorallocate($slaim, 255, 255, 255);
    $grey = imagecolorallocate($slaim, 0,0,0);	
    $str = sprintf("        %.2f%%",$sla);

    imagestring($slaim, 5, 0, 0, $str, $grey);
    
    // Copy the slaim image onto our photo using the margin offsets and the photo 
    // width to calculate positioning of the slaim. 
    imagecopymerge($im, $slaim, imagesx($im) - imagesx($slaim),imagesy($im) - imagesy($slaim), 0, 0, imagesx($slaim), imagesy($slaim), 100);


    // Merge the slaim onto our photo with an opacity of 50%
    //imagecopy($im, $slaim, imagesx($im), imagesx($im), 1, 1, imagesx($slaim), imagesy($slaim), 0);
    

    imagepng($im);
    imagedestroy($im);

}

?>

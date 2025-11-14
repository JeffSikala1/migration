<?php
// Author: Madhav.Kundala@usda.gov
// Date Creatd: 09/07/2019
// Date Modified:
// Get SLA report, parse and then display

header("Content-type:text/html");
?>
<html>
<head>
</head>
<body>

<?php

//Initial curl options

function set curlopts () {

  $curl_data = "";
  $curlopts = array(
    CURLOPT_NETRC => true,
    CURLOPT_NETRC_FILE => "/etc/httpd/conf.d/.netrc",
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 30,
    CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
    CURLOPT_CUSTOMREQUEST => "GET",
    CURLOPT_HTTPHEADER => array(
      "cache-control: no-cache"
    ),
    CURLOPT_POST            => 1,            // i am sending post data
    CURLOPT_POSTFIELDS     => $curl_data,    // this are my post vars
    CURLOPT_SSL_VERIFYHOST => 0,            // don't verify ssl
    CURLOPT_SSL_VERIFYPEER => false,        //
    CURLOPT_VERBOSE        => 1,                // 
  );

  return $curlopts;

}


//Start search job

function start_report($curlurl) {
  $retval = "";
  $curl = curl_init();
  $curlopts = setcurlopts();
  $curlopts{CURLOPT_URL} = $curlurl;
  curl_setopt_array($curl, $curlopts);
  $response = curl_exec($curl);
  $err = curl_error($curl);

  $response = json_decode($response, true); //because of true, it's in an array

  if (empty($err)) {
     $retval = $response;
  } else {
     $retval = $err;
  }
  curl_close($curl);
  return $retval;
     
}

CURLOPT_URL => "https://icingaweb2.conexus-project.org:8443/thruk/cgi-bin/avail.cgi?show_log_entries=&servicegroup=all&timeperiod=last7days&smon=10&sday=06&syear=2019&shour=0&smin=0&ssec=0&emon=10&eday=07&eyear=2019&ehour=24&emin=0&esec=0&rpttimeperiod=&assumeinitialstates=yes&assumestateretention=yes&assumestatesduringnotrunning=yes&includesoftstates=no&initialassumedhoststate=3&initialassumedservicestate=6&view_mode=json"

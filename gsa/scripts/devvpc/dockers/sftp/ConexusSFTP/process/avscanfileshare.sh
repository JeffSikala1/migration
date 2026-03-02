#!/bin/bash

#Anti Virus
avprog="/usr/bin/clamscan"
infdest=" --move=/NSFS_NAS/fail_scan"
#miscopts=" --SUMMARY --VERBOSE "
miscopts=" --quiet"
avtag="ConexusSFTP_AVScan";

for src in ATT BTFederal Centurylink CoreTech GraniteTelcom HarrisCorp Level3 ManhattanTelco MicroTech Verizon
do
  avreport=$(timeout --signal=9 1200 ${avprog} ${avdat} ${infdest} ${miscopts} "/NSFS_NAS/chroot/$src/fileshare" 2>&1);
  echo "${avreport}" | ts "%d/%M/%Y:%H:%M:%S %z ${avtag}"
done


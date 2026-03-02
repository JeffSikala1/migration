#!/bin/bash

echo "Checking gsansfs0052:/NSFS_NAS/database/taxfiles/" |ts "%d/%M/%Y:%H:%M:%S %z ConexusSFTP_PRODTAX"
#Double precaution cd first
cd /NSFS_NAS/database/taxfiles

#
var=$(/usr/bin/rsync -av -e '/usr/bin/ssh -i /home/pkundm01/.ssh/id_rsa -l pkundm01' --remove-source-files gsansfs0052.edc.ds1.usda.gov:/NSFS_NAS/database/taxfiles/NATAX* /NSFS_NAS/database/taxfiles/ 2>/dev/null)
echo "NATAX: $var" |ts "%d/%M/%Y:%H:%M:%S %z ConexusSFTP_PRODTAX"
var=$(/usr/bin/rsync -av -e '/usr/bin/ssh -i /home/pkundm01/.ssh/id_rsa -l pkundm01' --remove-source-files gsansfs0052.edc.ds1.usda.gov:/NSFS_NAS/database/taxfiles/ALLTAX* /NSFS_NAS/database/taxfiles/ 2>/dev/null)
echo "ALLTAX: $var" |ts "%d/%M/%Y:%H:%M:%S %z ConexusSFTP_PRODTAX"


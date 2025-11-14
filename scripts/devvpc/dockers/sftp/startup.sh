#!/bin/bash

/usr/sbin/crond

/app/ConexusSFTP/process/scannmovewrapper &

wait -n

exit

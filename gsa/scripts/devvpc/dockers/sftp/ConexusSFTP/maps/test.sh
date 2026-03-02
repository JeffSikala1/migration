#!/bin/bash

delcode=1
delattemptcount=0
while [[ "$delcode" -eq "1" && "$delattemptcount" -lt "15" ]] # Try 15 times
                do
                    #delout=$(${sqlite} -init <(echo .timeout 5000) -separator '||' ${db} "delete from copiedfiles where srcfile = \"$delline\"" 2>&1);
                    delcode="1"

                    if [ "$delcode" -eq "0" ]
                    then
                       echo "Deleted $delline record from copiedfiles table"
                    else
                        echo "Deleting from copiedfiles FAILED: $delcode $delout \"$delline\"" 
                    fi
                    sleep 2; # Try again in 2 secs
                    delattemptcount=$[delattemptcount + 1]
		    echo "count is $delattemptcount"
                done


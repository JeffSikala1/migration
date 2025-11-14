#!/bin/bash                                                                                                 

#This file should be under AppRoot/functions/                                                               

source $(dirname $0)/../conf.d/scannmove.conf.${SFTPENV};

declare -a children;

function checkChildren() { #Count how many children are alive                                               
    #echo "Children left: ${#children[@]}";                                                                 
    #echo "Children: ${children[*]}";
    if [ "${#children[@]}" -ne "0" ]
    then

        local count=0; # array index                                                                        
        while [ "$count" -lt "$maxchildren" ]
        do
            if ! kill -0 ${children[$count]} 2>/dev/null #check if child is still alive                     
            then
                unset children[$count]
            fi

            count=$(expr $count + 1) # increment array index for next child                                 
        done
        children=("${children[@]}")  #get rid of children that are done from children array                 
    fi

}

function addChild() { #Add child to the children array                                                      
    local childid="$1";
    children=(${children[@]} $childid);

}

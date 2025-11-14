#!/bin/bash

#This file should be under AppRoot/functions/

source $(dirname $0)/../conf.d/scannmove.conf.${SFTPENV};


function avscan() {
    local src="$1";
    local retval=0;
        
    avreport=$(timeout --signal=9 1200 ${avprog} ${avdat} ${infdest} ${miscopts} "$src" 2>&1);
    if [ "$?" -ne 0 ]
    then
	retval=$?; #Problem found
    else
	retval=0;
    fi
    echo "$avreport";
    return $retval;
    
}


function checkfiletype() {

    local srcfile="$2";
    local outflag="$1";
    local filetype=$(file -b --mime-type "$srcfile");
    local retval=1;
    local retstr="$filetype";
    local mimetypes=(${allowedmimetypes[@]});

    if [ "$outflag" = "yes" ]
    then
	mimetypes=(${allowedmimetypesout[@]});
    fi  
  
    for i in "${mimetypes[@]}"
    do
	echo "$filetype" |grep "$i";
	if [ "$?" -eq 0 ]
	then
	    retval=0;
	    echo "Mime type for $srcfile is $i" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
	    break;
	fi
    done

    echo "$retstr";
    return $retval;
	    
} # End checkfiletype()

function movefile() {

    local srcfile="$1";
    local destpath="$2";
    local destappend="$3";
    local retval=0;
    local retstr="";
    local mvout="";
    local destfilename=$(basename "$srcfile");
    destpath="$(echo -e "${destpath}" | sed -e 's/[[:space:]]*$//')"
    
    if [ "$destpath" = "" ]
    then
	
	retval=1;
	retstr="Destination path $destpath is empty";
	
    else
	
	mvout=$(mv "$srcfile" "$destpath"/"$destfilename""$destappend" 2>&1);
	if [ "$?" -eq 0 ]
	then
	    echo "Moved $srcfile to $destpath/$destfilename$destappend" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
	else
	    retval=1;
	    retstr="$mvout";
	fi
	
    fi
    
    echo "$retstr";
    return $retval;

} #End movefile()

function copyfile() {

    local srcfile="$1";
    local destpath="$2";
    local destappend="$3";
    local retval=0;
    local retstr="";
    local destfilename=$(basename "$srcfile");
    local cpout="";
    destpath="$(echo -e "${destpath}" | sed -e 's/[[:space:]]*$//')"

    if [ "$destpath" = "" ]
    then

	retval=1;
	retstr="Destination path $destpath is empty";

    else

	cpout=$(cp "$srcfile" "$destpath"/"$destfilename""$destappend" 2>&1);
	if [ "$?" -eq 0 ]
	then
            echo "Copied $srcfile to $destpath/$destfilename$destappend" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
	else #FAILED to copy
            retval=1;
	    retstr="$cpout";
	    echo "Copy FAILED $srcfile to $destpath/$destfilename$destappend" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
	fi
	
    fi

    echo "$retstr";
    return $retval;

}

#As of now archiving is delete
function markforarchive() {  #push the filenamenpath into copiedfiles array.
    
    local srcpathnfile="$1";
    local found="1";
    #local linere='(.*)\|\|(.*)';
    while read -r fileline
    do
	if [[ "$fileline" = "$srcpathnfile" ]]
	then
	    #Already exists
	    found="0";
	    echo "Ignore: $fileline already exists in copiedfiles table" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
	    break;
	fi
	
    done  < <(${sqlite} -init <(echo .timeout 20000) -separator '||' ${db} "${copiedqry}")

    if [ "$found" -ne "0" ]
    then
	#Insert into copiedfiles table
	insout=$(${sqlite} -init <(echo .timeout 20000) -separator '||' ${db} "insert into copiedfiles values(\"$srcpathnfile\")" 2>&1);
	inscode="$?"
	if [[ "$inscode" -ne "0"  &&  "$inscode" -ne "19" ]]
	then
	    #Problem
	    echo "Inserting into copiedfiles FAILED: $inscode $insout" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag")| ${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - cp archiving FAILED" "${tomail}";
	else
	    echo "Inserted $srcpathnfile into copiedfiles table" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
	fi
	
	found=0;
	
    fi
    
    return $found;
    
} #End of markfor archive

function unmarkforarchive() { #pop(remove) the filenamenpath from copiedfiles array.
    
    local srcpathnfile="$1";
    local found="1"; 
    while read -r filerecline
    do
        if [[ "$filerecline" = "$srcpathnfile" ]]
        then
            #Does exist
            found="0";
	    break;
        fi

    done  < <(${sqlite} -init <(echo .timeout 20000) -separator '||' ${db} "${copiedqry}")
    if [ "$found" -eq "0" ]
    then
        #Insert into copiedfiles table                  
        delout=$(${sqlite} -init <(echo .timeout 20000) -separator '||' ${db} "delete from copiedfiles where srcfile = \"$srcpathnfile\"" 2>&1);
        if [[ "$?" -ne "0" ]]
        then
	    
	    #Problem
            echo "Deleting from copiedfiles FAILED: $delout" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag")| ${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - cp archiving FAILED" "${tomail}";
	else
	    echo "Deleted $delout from copiedfiles" |ts "%d/%M/%Y:%H:%M:%S %z $transfertag"
        fi
	       
    fi
    
    return $found;

} #End of unmarkforarchive()

function chownmode() { #Changed owner and mode at destination folder
    
    local dest="$1";
    local downer="$2";
    local dgroup="$3";
    local retval="1";
    local retstr="";

    if [[ "$dest" != "" ]]
    then
	#Change owner and mode
	if [[ -d $dest ]]; then
	    retstr=$(chown $downer:$dgroup "$dest"/* 2>&1);
	    if [ "$?" -eq "0" ]; then retval=0; fi
	    retstr+=$(chmod 644 "$dest"/* 2>&1);
	else
	    retstr=$(chown $downer:$dgroup "$dest" 2>&1);
	    if [ "$?" -eq "0" ]; then retval=0; fi
	    retstr+=$(chmod 644 "$dest" 2>&1);
	fi
	
	if [ "$?" -eq "0" ]
	then
	    if [ "$retval" -eq "0" ]; then retval=0; fi #if chown is good then only chmod is good
	fi

    else
	retstr="Destination path is empty: $dest";
    fi
        
    echo "$retstr";
    return $retval;
    
} #End chownmode()

function writetoreadme() {

    local srcfile="$1";
    local destpath="$2";
    local readmefilenpath="$3";
    local retval=0;
    local retstr="";
    local srcfilename=$(basename "$srcfile");
    local readmepath=$(dirname "$readmefilenpath");   # "${readmefilenpath%/*}"; # 

    destpath="$(echo -e "${destpath}" | sed -e 's/[[:space:]]*$//')";
    
    if [[ "$srcfile" == *$readmepath* ]]; then
	srcfile=${srcfile/$readmepath/};
	if [[ "$destpath" == *eis_pmo* ]]; then
	    destpath="EIS_PMO";
	else
	    destpath="Conexus";
	fi
    else
	destpath=${destpath/$readmepath/};
	destpath="${destpath}/${srcfilename}";
	srcfile="Conexus";
    fi

    if [[ "$readmefilenpath" != "" ]]; then
	echo $(date "+%x %X %Z")::$srcfile ">" $destpath >> ${readmefilenpath};
    else
	retstr="Readme file and path not set";
	retval=1;
    fi
    
    echo "$retstr";
    return $retval;    
    
} #End writetoreadme()

function transfer() {
    
    #    echo "ChildID: $BASHPID Scanning $1 Moving into $2";
    local srcpath="$1";
    local rawdest="$2";
    local vaemail="$3"; #Vendor/Agency emails
    local transfertype="$4"; # copy or move
    local destowner="$5";
    local destgroup="$6";
    local mapfiledestfileappendstr="$(date +${7})"; #filename will be different at destination as per config set in map file
    local destfileappendstr="";
    local readmefilenpath="$8";
    local outflag="$9";

    declare -a foundfilelist=("${!10}"); #Found files list
    local emailflag=1; #We won't email unless somethin was transferred
    local filelist="";

    #Remove trailing white space; else mv would do nasty things
    dest="$(echo -e "${rawdest}" | sed -e 's/[[:space:]]*$//')";

    #-----------Main loop ---------------------
    #For each file in the passed found file list
    for afilenamenpath in "${foundfilelist[@]}"  
    do

	srcfilename=$(basename "$afilenamenpath"); #Extract the name of the file
        retfilecheck=$(checkfiletype "$outflag" "$afilenamenpath");
	if [ "$?" -eq "0" ] #Mime type is good
	then

	    echo "Mime type for $afilenamenpath is good"|ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
	    
	    #if destfileappendstr is set and filetype is not txt or gzip then empty out destfileappendstr
            #-------
	    renameflag="0"
	    destfileappendstr="${mapfiledestfileappendstr}"

            if [ "$destfileappendstr" != "" ]
            then
		
		#Iterate through each file type defined in conf.d as being eligible for renaming
		#------
		for i in "${filerenametypes[@]}"
		do

		    echo "$retfilecheck" |grep "$i";
		    if [ "$?" -eq "0" ]
	            then

		        renameflag="1";
	                echo "$afilenamenpath is $i type, thus good for filename appending" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
                        break;

	            fi
         	done
		#------

		#If renameflag is still 0 then the file type is not text or gzip etc.
		#------
		if [ "$renameflag" -eq "0" ]
		then
		    destfileappendstr=""		    
		fi
		#-----
            fi
	    #-------

	    #Move file
	    if [ "$transfertype" = "mv" ]
	    then
		moveretstr=$(movefile "$afilenamenpath" "$dest" "$destfileappendstr");
		if [ "$?" -eq 0 ] 
		then
		    emailflag=0;
		    filelist="${filelist}\n ${dest}/${srcfilename}${destfileappendstr}"
		    #echo "Moved $afilenamenpath  to $dest with $destfileappendstr appended" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag"
		else #Moving FAILED
		    
		    echo -e "FAILED to move $afilenamenpath  to $dest with $destfileappendstr appended\n $moveretstr"|tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag")| ${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - Move FAILED" "${tomail}"
		    
		fi
	    #Copy file
	    elif [ "$transfertype" = "cp" ]
            then

                copyretstr=$(copyfile "$afilenamenpath" "$dest" "$destfileappendstr");
		if [ "$?" -eq "0" ]    #copy return string
                then
		    
		    emailflag=0;
		    filelist="${filelist}\n ${dest}/${srcfilename}${destfileappendstr}"
		    markout=$(markforarchive "$afilenamenpath");
		    echo "Marked for Archive:$afilenamenpath $markout"|ts "%d/%M/%Y:%H:%M:%S %z $transfertag" ;
		    if [ "$readmefilenpath" != "" ]; then
			readmeout=$(writetoreadme "$afilenamenpath" "$dest" "$readmefilenpath");
			
			if [ "$?" -ne "0" ]; then
			    echo "FAILED to update transaction log file $readmeout"|tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") |${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv update of transaction log file FAILED" "${tomail}";
			else
			    echo "Updated transaction log $afilenamenpath -- $dest -- $readmefilenpath" | ts "%d/%M/%Y:%H:%M:%S %z $transfertag"
			fi
		    fi
		    
		    
		else #Copy FAILED
		    
		    unmarkout=$(unmarkforarchive "$afilenamenpath");
		    echo -e "FAILED to copy, Error:$unmarkout;\n $afilenamenpath  to $dest with $destfileappendstr appended\n $copyretstr"|tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") | ${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - Copy FAILED" "${tomail}"
		    
                fi
		
	    else
		
		echo "FAILED: Transfertype is missing $transfertype for $afilenamenpath"|tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") |${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - Transfertype missing" "${tomail}";
		
	    fi # End if [ "$transfertype"


	else # Mime Check else of if [ "$?" -eq "0" ]  #Mime check 
	    #Mime check failed
	    echo -e "FAILED File Type: $retfilecheck \n File: $afilenamenpath \n Allowed mimes: ${allowedmimetypes[@]}" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") | ${mailx} -r "${frommail}" -c "${tomail}" -s "ConexusSFTP $sftpenv Files - File type FAILED" "${vaemail}";
	    markout=$(markforarchive "$afilenamenpath");
            echo "Marked for Archive, Failed file type check :$afilenamenpath $markout"|ts "%d/%M/%Y:%H:%M:%S %z $transfertag" ;
	    
	fi #End if [ "$?" -eq "0" ] #Mime type is good
	
	sleep 0.2;
	
    done #End for afilenamenpath in "${foundfilelist[@]}"
    

#------End Main loop -----------------------------
    
    #Copy or Move is complete

    # Done with the found files loop, lets email the vendor/agency => vaemail
    if [ "$emailflag" -eq 0 ] #if flag is set some files were moved/copied
    then
	echo "Files available for pickup at $dest"|ts "%d/%M/%Y:%H:%M:%S %z $transfertag"
	echo -e "$vamailtext $dest \n $filelist"|${mailx} -r "${frommail}" -s "$vamailsubj" -c "${tomail}" "${vaemail}"

	#Change owner and mode
	chownret=$(chownmode "$dest" "$destowner" "$destgroup");
	if [ "$?" -ne 0 ] # chownmode ret value
	then
	    echo "FAILED to set owner/mode $chownret" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") |${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Owner/mode setting FAILED" "${tomail}";
	fi # End of chown ret value if
	
	sleep 1s; #Give some time for email to be sent and avoid getting DDoS blacklisted
    fi #End of emailflag check - if [ "$emailflag" -eq 0 ]
    

} #End of function transfer()



function processcopiedfiles() {

    subfolder=$(date +%Y/%m/%d);
    timestamp=$(date +%Y%m%d_%H%M%S);
    cparchive="${cparchive}"/"${subfolder}";
    if [[ "$cparchive" != ""  && ! -d "$cparchive" ]]; then
        mkdirout=$(mkdir -p "$cparchive" 2>&1);
        if [ "$?" -ne "0" ]; then
           echo "Archive Copy Directory making FAILED: $mkdirout \n $cparchive/" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") | ${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - Archive Copy FAILED" "${tomail}";
        fi
    fi

    declare -A delsrcs;
    delsrcre='(.*)\|\|(.*)';

    #Get all the records from DB and store into various hash arrays
    #RowID is the key for all the hash arrays

    while read -r delrec
    do
        [[ $delrec =~ $delsrcre ]] || continue
        delrowid="${BASH_REMATCH[1]}";
        delsrc="${BASH_REMATCH[2]}";
        delsrcs["$delrowid"]="$delsrc";    #Array of source folder paths from copiedtable
	
    done < <(${sqlite} -init <(echo .timeout 20000) -separator '||' ${db} "${copiedqry}")
    
    for delkey in "${!delsrcs[@]}"
    do
	
        if [[ "$cparchive" != "" ]]
        then
	    
	    
            delpathnname="$(echo -e "${delsrcs[$delkey]}" | sed -e 's/\//_/g')";
            mvout=$(mv "${delsrcs[$delkey]}" "$cparchive"/"${delpathnname}_${timestamp}" 2>&1);
            if [ "$?" -ne "0" ]
            then
		
		echo "Archive Copy FAILED: $mvout \n ${delsrcs[$delkey]} $cparchive/" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag")
                # Let splunk alert instead | ${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - Archive Copy FAILED" "${tomail}";
		
            else
		echo "Copied to archive: ${delsrcs[$delkey]} $cparchive/" |ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
		
		# Now try to delete from copiedfiles table 
		delcode=1
		delattemptcount=0
		
		while [[ "$delcode" -eq "1" && "$delattemptcount" -lt "15" ]] # Try 15 times 
		do
		    delout=$(${sqlite} -init <(echo .timeout 5000) -separator '||' ${db} "delete from copiedfiles where srcfile = \"${delsrcs[$delkey]}\"" 2>&1);
	            delcode="$?"
		    
		    if [ "$delcode" -eq "0" ]
		    then
			echo "Deleted ${delsrcs[$delkey]} record from copiedfiles table"|ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
                    else 
			echo "Deleting from copiedfiles FAILED: $delcode $delout \"${delsrcs[$delkey]}\"" |ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
			sleep 2; # Try again in 2 secs
		    fi
		    delattemptcount=$[delattemptcount + 1]	
		    
		done
		
		if [ "$delcode" -ne "0" ] 
	        then
		    echo "Deleting from copiedfiles FAILED: $delcode $delout" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") | ${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - archiving Success but failed to maintain the status table: copiedfiles, entry: \"${delsrcs[$delkey]}\"" "${tomail}";    
	            sleep 2m; # We failed too many time to update the copiedfiles table, so lets sleep
		fi
		
            fi  # end if [ "$?" -ne "0" ]
	    
	else
	    
            echo "FAILED: Copy archive path $cparchive is empty" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") | ${mailx} -r "${frommail}" -s "ConexusSFTP $sftpenv Files - Archive Copy FAILED" "${tomail}";
	    
	fi # end if [[ "$cparchive" != "" ]]
	
    done # end for delkey in "${!delsrcs[@]}"
    
} # End function processcopiedfiles()



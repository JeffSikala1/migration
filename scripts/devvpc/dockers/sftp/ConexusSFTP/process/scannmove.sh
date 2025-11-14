#!/usr/bin/bash

###############################
# Name: scannmove
#
# Created: 09/27/2018 - Madhav Das Kundala
#
# Description: Get all folders listed in sqlite3 pathways/srcdest table.
# Create some children for scanning and moving files.
# 
###############################

source $(dirname $0)/../conf.d/scannmove.conf.${SFTPENV};

#Prevent Duplicates

if [ -e ${lockfile} ] && kill -0 $(cat $lockfile)
then
    echo "Already Running"
    exit
fi

#On interrupt remove lock file
trap "trap - SIGTERM && rm -f $lockfile; exit" SIGINT SIGTERM EXIT

#Create the lock file
echo $$ > $lockfile


    
declare -A uniqsrcs; #key:rowid path; value:src path - For main loop
declare -A srcs; #key:rowid path; value:src path - For secondary transfer loop
declare -A dests; #key:rowid path; value:dest path
declare -A emails; #key:rowid path; value:vaemail
declare -A ttypes; #key:rowid path; value:transfer_type
declare -A dfiles; #key:rowid path; value:destfilename
declare -A destowners; #key:rowid path; value:destowner
declare -A destgroups; #key:rowid path; value:destgroup
declare -A readmefilenpaths; #key:rowid path; value:readmefilenpath
declare -A modtimes; #key:rowid path; value:timeold - For main loop
declare -A timeolds; #key:rowid path; value:timeold
declare -A outflags; #key:rowid path; value: v_conexus_out

source $(dirname $0)/../functions/scannmovefunc.sh;
source $(dirname $0)/../functions/threadcontrolfunc.sh;

#Thread control
maxchildren=10

#column separator is '||'; so we match for path||path||email
uniqlinere='(.*)\|\|(.*)\|\|(.*)';


#Get all the records from DB and store into various hash arrays
#RowID is the key for all the hash arrays
#-------------------
while read -r uniqline
do
    [[ $uniqline =~ $uniqlinere ]] || continue
    rowid="${BASH_REMATCH[1]}";
    src="${BASH_REMATCH[2]}";
    modtime="${BASH_REMATCH[3]}";
    uniqsrcs["$rowid"]="$src";    #source folder paths
    modtimes["$rowid"]="+$modtime";
done  < <(${sqlite} -init <(echo .timeout 20000) -separator '||' ${db} "${selqry}")  
#-------------------



#Process each record; create a thread for each.
#------------
for uniqkey in "${!uniqsrcs[@]}"
do

    #sleep untill we have more than 9 children
    while [[ "${#children[@]}" -ge "$maxchildren" ]]
    do
	sleep 1s;
	checkChildren;
    done

    #Check if any files older than ${modtimes[$uniqkey]}(5 min) exist, then scan for virus
    #--------------
    findcount="0"

    findout=$(find "${uniqsrcs[$uniqkey]}" -maxdepth 1 ! -name 'errors_*' -mmin "${modtimes[$uniqkey]}" -type f 2>&1)
    if [ "$?" -ne "0" ]
    then

	echo "Find command FAILED: At Check if any files($uniqkey) older than +${modtimes[$uniqkey]}(5 min) exist, then scan for virus: $findout" |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag")| ${mailx} -r "${frommail}" -s "ConexusSFTP Files - Find command pre AVscan command FAILED" "${tomail}";
    
    else

	findcount=$(echo "${findout}"|wc -w)	

    fi
    #------------

    #If files are present then AVscan
    #------------
    if [ "$findcount" -ge "1" ] 
    then
	
	#Do not background avscan; we must wait for avscan to complete
	avout=$(avscan "${uniqsrcs[$uniqkey]}");
	if [ "$?" -ne "0" ]
	then
	    echo "${avout}" | ${mailx} -r "${frommail}" -s "Report - AV scan problem found" "${tomail}";
	    ts "%d/%M/%Y:%H:%M:%S %z $avtag" "AV scan problem found for ${uniqsrcs[$uniqkey]} \n $avout";
	else
	    ts "%d/%M/%Y:%H:%M:%S %z $avtag" "File Count: $findcount; Files in ${uniqsrcs[$uniqkey]} are clean";
	fi

    fi
    #-------------

    # Are there files(+5mins) in src folders, if yes put then into an array
    #----------------
    foundflag=0;
    declare -a filesarr;
    filesarr=();

    while read -r -d '' srcfilenamenpath
    do
	filesarr+=("$srcfilenamenpath");
	foundflag=1;
    done < <(find "${uniqsrcs[$uniqkey]}" -maxdepth 1 ! -name 'errors_*' -mmin "${modtimes[$uniqkey]}" -type f -print0)
    
    if [ "$foundflag" = "1" ]
    then

	#found files, now get all records which have the same source(src)
	unset srcs; #key:rowid path; value:src path - For secondary transfer loop
	unset dests; #key:rowid path; value:dest path
	unset emails; #key:rowid path; value:vaemail
	unset ttypes; #key:rowid path; value:transfer_type
	unset dfiles; #key:rowid path; value:destfilename
	unset destowners; #key:rowid path; value:destowner
	unset destgroups; #key:rowid path; value:destgroup
	unset readmefilenpaths; #key:rowid path; value:readmefilenpath
        unset timeolds; #key:rowid path; value:timeold
	unset outflags; #key:rowid path; value:v_conexus_out

	transferquery=$(echo -e "select rowid,src,dest,vaemail,transfer_type,destfilename,destowner,destgroup,readmefilenpath,timeold,v_conexus_out from srcdest where src = \x27${uniqsrcs[$uniqkey]}\x27 order by rowid")

	linere='(.*)\|\|(.*)\|\|(.*)\|\|(.*)\|\|(.*)\|\|(.*)\|\|(.*)\|\|(.*)\|\|(.*)\|\|(.*)\|\|(.*)';
	while read -r line
	do

	    [[ $line =~ $linere ]] || continue
	    rowid="${BASH_REMATCH[1]}";
	    src="${BASH_REMATCH[2]}";
	    dest="${BASH_REMATCH[3]}";
	    email="${BASH_REMATCH[4]}";
	    transfertype="${BASH_REMATCH[5]}";
	    destfilename="${BASH_REMATCH[6]}";
	    destowner="${BASH_REMATCH[7]}";
	    destgroup="${BASH_REMATCH[8]}";
	    readmefilenpath="${BASH_REMATCH[9]}";
	    timeold="${BASH_REMATCH[10]}";
            outflag="${BASH_REMATCH[11]}";

            srcs["$rowid"]="$src";    #source folder paths
	    dests["$rowid"]="$dest";  #dest folder paths
	    emails["$rowid"]="$email";
	    ttypes["$rowid"]="$transfertype"; #transfer types
	    dfiles["$rowid"]="$destfilename"; #strings to append to filenames
	    destowners["$rowid"]="$destowner"; #folder owners
	    destgroups["$rowid"]="$destgroup"; #folder group owners
	    readmefilenpaths["$rowid"]="$readmefilenpath"; #Readme file location
	    timeolds["$rowid"]="+$timeold"; #File age; modification time
            outflags["$rowid"]="$outflag"; #If files are going out from Conexus(yes/no)

	done  < <(${sqlite} -init <(echo .timeout 20000) -separator '||' ${db} "$transferquery")  

	# for same sources found in the above query call transfer fucntion on each(pass the found files array too)
        #------------
	for key in "${!srcs[@]}"
	do
	    
	    #Do the work and add child to tracking
	    echo "Processing $key ${srcs[$key]} -> ${dests[$key]}"| ts "%d/%M/%Y:%H:%M:%S %z $transfertag";

	    if [ -d "${srcs[$key]}" ] && [ -d "${dests[$key]}" ]
	    then
		transfer "${srcs[$key]}" "${dests[$key]}" "${emails[$key]}" "${ttypes[$key]}" "${destowners[$key]}" "${destgroups[$key]}" "${dfiles[$key]}" "${readmefilenpaths[$key]}" "${outflags[$key]}" filesarr[@] &
	    else
		#Folders missing, email
		local msg="";
		if [ ! -d "${srcs[$key]}" ]
		then
		    msg="Record number: $key Source: ${srcs[$key]} does not exist";
		fi
		if [ ! -d "${dests[$key]}" ]
		then
		    msg="$msg \nRecord number: $key Destination: ${dests[$key]} does not exist";
		fi
	    
		echo -e "Following folder(s) could not be found \n $msg"  |tee >(ts "%d/%M/%Y:%H:%M:%S %z $transfertag") | ${mailx} -r "${frommail}" -s "ConexusSFTP Files" "${tomail}";
		
	    fi #end of if [ -d "${srcs[$key]}" ] && [ -d "${dests[$key]}" ]
       
	    childid=$!;
	    scannmovestatus=$?
	    addChild $childid;
	    
	done #end for key in "${!srcs[@]}"
        #-----------

    else

	#For logging purpose only
	str+="${uniqkey}:${uniqsrcs[$uniqkey]:15:7}..${uniqsrcs[$uniqkey]:30:7}-"	

    fi #end of if [ "$foundflag" = ....
    #------------    

done #for uniqkey in "${!uniqsrcs[@]}"
#-----------

#if there are folders where no new files were found then print the folder names(short) into syslog
#---------
if [ "$str" != "" ]
then
    echo -e "No files found at ${str}." |ts "%d/%M/%Y:%H:%M:%S %z $transfertag"
fi
#---------

# Wait for all children to finish
#--------
while [[ "${#children[@]}" -gt "0" ]]
do
    sleep 1s;
    checkChildren;
    echo "Children left: ${#children[@]}"| ts "%d/%M/%Y:%H:%M:%S %z $transfertag";
done
#--------

#Lets remove the copied files
processcopiedfiles;

# Remove the lock file
rm -f $lockfile

exit 0


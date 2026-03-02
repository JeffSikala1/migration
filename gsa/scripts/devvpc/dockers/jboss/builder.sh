#!/bin/bash

usage() { echo "Usage: $0 -s portal|jms|webservice|brms|reporting>" 1>&2; exit 1; }

while getopts ":s:" opt; do
    case "${opt}" in
        s)
            s=${OPTARG}
            ((s == portal || s == jms || s == webservice || s == brms || s == reporting )) || usage
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${s}" ] ; then
    usage
fi

echo "s = ${s}"

PROGDIR=$(dirname ${BASH_SOURCE})
echo "${PROGDIR}"
cd ${PROGDIR}
baseimagename="339713019047.dkr.ecr.us-east-1.amazonaws.com/conexus-jboss"
basejbossversion="8.0.8"

if [[ "${s}" == "portal" ]]
then
    uiwar=$(ls -t ui-war-*|head -n 1)
    uiwarver=$(echo "${uiwar}" | sed -nE 's/^ui-war-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    restear=$(ls -t rest-ear-*|head -n 1)
    restearver=$(echo "${restear}" | sed -nE 's/^rest-ear-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    if [[ ! -z "${uiwar}" && ! -z "${uiwarver}" && ! -z "${restear}" && ! -z "${restearver}"  ]]
    then
	docker build -t ${baseimagename}-portal:${basejbossversion}-ui${uiwarver}-rest${restearver} --build-arg=UIWAR=${uiwar} --build-arg=RESTEAR=${restear} -f PortalDockerfile .
    else
	echo "Check file names ${uiwar} ${uiwarver}"
	echo "                 ${restear} ${restearver}"
    fi
elif [[ "${s}" == "jms" ]]
then
    taskear=$(ls -t task-ear-*|head -n 1)
    taskearver=$(echo "${taskear}" | sed -nE 's/^task-ear-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    if [[ ! -z "${taskear}" && ! -z "${taskearver}" ]]
    then
	docker build -t ${baseimagename}-jms:${basejbossversion}-task${taskearver} --build-arg=TASKEAR=${taskear} -f JmsDockerfile .
    else
	echo "Check file names ${taskear} ${taskearver}"
    fi
elif [[ "${s}" == "webservice" ]]
then
    wsear=$(ls -t ws-services-ear*|head -n 1)
    wsearver=$(echo "${wsear}" | sed -nE 's/^ws-services-ear-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    cnxsear=$(ls -t cnxs-ws-ear-*|head -n 1)
    cnxsearver=$(echo "${cnxsear}" | sed -nE 's/^cnxs-ws-ear-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    dpaear=$(ls -t dpa-ear-*|head -n 1)
    dpaearver=$(echo "${dpaear}" | sed -nE 's/^dpa-ear-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    if [[ ! -z "${wsear}" && ! -z "${wsearver}" && ! -z "${cnxsear}" && ! -z "${cnxsearver}" && ! -z "${dpaear}" && ! -z "${dpaearver}" ]]
    then
	docker build -t ${baseimagename}-webservice:${basejbossversion}-ws${wsearver}-cnxs${cnxsearver}-dpa${dpaearver} --build-arg=WSEAR=${wsear} --build-arg=CNXSEAR=${cnxsear} --build-arg=DPAEAR=${dpaear} -f WebserviceDockerfile .
    else
	echo "Check file names ${wsear} ${wsearver}"
	echo "                 ${cnxsear} ${cnxsearver}"
	echo "                 ${dpaear} ${dpaearver}"
    fi
elif [[ "${s}" == "brms" ]]
then
    reconwar=$(ls -t reconciliation-war-*|head -n 1)
    reconwarver=$(echo "${reconwar}" | sed -nE 's/^reconciliation-war-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    cmodwar=$(ls -t contract-mod-war-*|head -n 1)
    cmodwarver=$(echo "${cmodwar}" | sed -nE 's/^contract-mod-war-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    swagwar=$(ls -t vendor-emulator-war-*|head -n 1)   
    swagwarver=$(echo "${swagwar}" | sed -nE 's/^vendor-emulator-war-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    if [[ ! -z "${reconwar}" && ! -z "${reconwarver}" && ! -z "${cmodwar}" && ! -z "${cmodwarver}" && ! -z "${swagwar}" && ! -z "${swagwarver}" ]]
    then
	docker build -t ${baseimagename}-brms:${basejbossversion}-recon${reconwarver}-cmod${cmodwarver}-swag${swagwarver} --build-arg=RECONWAR=${reconwar} --build-arg=CMODWAR=${cmodwar} --build-arg=SWAGWAR=${swagwar} -f BrmsDockerfile .
    else
	echo "Check file names ${reconwar} ${reconwarver}"
	echo "                 ${cmodwar} ${cmodwarver}"
    fi
elif [[ "${s}" == "reporting" ]]
then
    repowar=$(ls -t reporting-war-*|head -n 1)
    repowarver=$(echo "${repowar}" | sed -nE 's/^reporting-war-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    vendear=$(ls -t vendor-emulator-ear-*|head -n 1)   
    vendearver=$(echo "${vendear}" | sed -nE 's/^vendor-emulator-ear-01.00.000.([0-9]+|[0-9]+.[0-9]+)-.*/\1/p')
    if [[ ! -z "${repowar}" && ! -z "${repowarver}" && ! -z "${vendear}" && ! -z "${vendearver}" ]] 
    then
	docker build -t ${baseimagename}-reporting:${basejbossversion}-repo${repowarver}-vend${vendearver} --build-arg=REPOWAR=${repowar} --build-arg=VENDEAR=${vendear} -f ReportingDockerfile .
    else
	echo "Check file names ${reconwar} ${reconwarver}"
	echo "                 ${vendear} ${vendearver}"
	echo "                 ${swagwar} ${swagwarver}"
    fi
fi

    
	
    

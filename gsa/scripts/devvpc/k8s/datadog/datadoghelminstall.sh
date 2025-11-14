#!/bin/bash


usage() { echo "Usage: $0 -e <dev|test|cert|prod>" 1>&2; exit 1; }

while getopts ":e:" opt; do
    case "${opt}" in
        e)
            e=${OPTARG}
            ((e == dev || e == test || e == cert || e == prod)) || usage
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${e}" ] ; then
    usage
fi

echo "e = ${e}"


echo
read -p "Upgrade(u) or Install(I): " -n1 uori
INSTALLTYPE="install" 
if [[ $uori =~ [uU] ]]; then
    echo "Upgrading"
    INSTALLTYPE="upgrade"
    exit;
fi



helm repo add datadog https://helm.datadoghq.com
helm repo update

#Get API Key and App Key From Datadog Organization Settings section:
#https://app.ddog-gov.com/organization-settings/api-keys
#https://app.ddog-gov.com/organization-settings/application-keys

#Create secrets files:
#vi [ENV]vpc-apikey.txt
#vi [ENV]vpc-appkey.txt

#Perl command to remove end new line characters:
perl -pi -e "s:\s+::g" ${e}vpc-apikey.txt ${e}vpc-appkey.txt

#Create the secrets entry in Kubernetes:
kubectl create secret generic ${e}vpc-ddog --save-config --dry-run=client --from-file=api-key=${e}vpc-apikey.txt --from-file=app-key=${e}vpc-appkey.txt -o yaml | kubectl apply -f - -n ingress-nginx

# see code block below for example contents of testvpc-values.yaml #
# environment values files are in AWS Bitbucket repo in devvpc/k8s
helm ${INSTALLTYPE} ${e}vpc-datadog-agent -f ${e}vpc-values.yaml datadog/datadog

# updates to the configuration can be made by editing the ${e}vpc-values.yaml file accordingly, then running a helm upgrade:
#helm upgrade ${e}vpc-datadog-agent -f ${e}vpc-values.yaml datadog/datadog

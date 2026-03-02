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

PROGDIR=$(dirname ${BASH_SOURCE})
echo "${PROGDIR}"


echo "Sourcing ${e}vpc.bashenv"
source ${PROGDIR}/${e}vpc.bashenv
# Cilium
echo "Env substituting $service_subnet_tag at"
echo "   ${PROGDIR}/cilium/cni-config-${e}.yaml "
envsubst '$service_subnet_tag' <${PROGDIR}/cilium/cni-config.yaml > ${PROGDIR}/cilium/cni-config-${e}.yaml 

#echo "Env substituting $env at"
#echo "  ${PROGDIR}/karpenter/karpenternodes-${e}.yaml "
#envsubst '$env' <${PROGDIR}/karpenter/karpenternodes.yaml > ${PROGDIR}/karpenter/karpenternodes-${e}.yaml

#echo "Env substituting $nlb_subnetids $nlbname at"
#echo "  ${PROGDIR}/nlb/deployenvsubst-${e}.yaml "
#envsubst '$nlb_subnetids $nlbname' <${PROGDIR}/nlb/deploy.yaml > ${PROGDIR}/nlb/deployenvsubst-${e}.yaml

#echo "Env substituting $cluster_name at"
#echo " ${PROGDIR}/alb/v2_13_0_full-${e}.yaml "
#envsubst '$cluster_name' <${PROGDIR}/alb/v2_13_2_full.yaml > ${PROGDIR}/alb/v2_13_2_full-${e}.yaml 

# Swagger
echo "Env substituting $swaggeroidc_provider_url $swaggeroidc_client_id $swaggeroidc_redirect_uri $swaggeroidc_loggedout_url $swaggeroidc_default_url at "
echo "  ${PROGDIR}/swaggerapache/swagger-apache-config-${e}.yaml"
envsubst '$swaggerurl $swaggeroidc_provider_url $swaggeroidc_client_id $swaggeroidc_redirect_uri $swaggeroidc_loggedout_url $swaggeroidc_default_url' <${PROGDIR}/swaggerapache/swagger-apache-config.yaml > ${PROGDIR}/swaggerapache/swagger-apache-config-${e}.yaml

# Apache
echo "Env substituting $uiurl $oidc_provider_url $oidc_client_id $oidc_redirect_uri $oidc_loggedout_url $oidc_default_url at"
echo "  ${PROGDIR}/apache/apache-config-${e}.yaml"
envsubst '$uiurl $oidc_provider_url $oidc_client_id $oidc_redirect_uri $oidc_loggedout_url $oidc_default_url' <${PROGDIR}/apache/apache-config.yaml > ${PROGDIR}/apache/apache-config-${e}.yaml
# Antivirus Apache
echo "Env substituting $uiurl at"
echo "  ${PROGDIR}/avapache/avapache-config-${e}.yaml"
envsubst '$uiurl' <${PROGDIR}/avapache/avapache-config.yaml > ${PROGDIR}/avapache/avapache-config-${e}.yaml
# Micro Integration API
echo "Env substituting $miurl at"
echo "  ${PROGDIR}/wso2/wso2mi-config-${e}.yaml"
envsubst '$miurl $uiurl' <${PROGDIR}/wso2/wso2mi-config.yaml > ${PROGDIR}/wso2/wso2mi-config-${e}.yaml

#jdbc:postgresql://cnxsdev2-cluster.cluster-cpm0wo2a8fu7.us-east-1.rds.amazonaws.com:5432/pgtemp01
# Jboss
echo "Env substituting "
echo "  $db_endpoint $db_user $db_user_mod $smtp_host $env at ${PROGDIR}/jboss/jboss-config-${e}.yaml"
envsubst '$db_endpoint $db_user $db_user_mod $smtp_host $env' <${PROGDIR}/jboss/jboss-config.yaml > ${PROGDIR}/jboss/jboss-config-${e}.yaml

# Ingresses
#echo "Env substituting $intnlb_subnetids $uiurl $env $certname at"
#echo "  ${PROGDIR}/apache/httpd-ingress-${e}.yaml"
#envsubst '$intnlb_subnetids $uiurl $env $certname' <${PROGDIR}/apache/httpd-ingress.yaml > ${PROGDIR}/apache/httpd-ingress-${e}.yaml

#echo "Env substituting $intnlb_subnetids $apiurl $uiurl $env $certname at"
#echo "  ${PROGDIR}/nginx/nginx-ingress-${e}.yaml "
#envsubst '$intnlb_subnetids $apiurl $uiurl $env $certname' <${PROGDIR}/nginx/nginx-ingress.yaml > ${PROGDIR}/nginx/nginx-ingress-${e}.yaml

# Micro Integrator - API - Proxy nginx
echo "Env substituting $env $certname at"
echo "  ${PROGDIR}/nginx/proxy-nginx-${e}.yaml "
envsubst '$env $certname' <${PROGDIR}/nginx/proxy-nginx.yaml > ${PROGDIR}/nginx/proxy-nginx-${e}.yaml

# GatewayAPI UI URL
echo "Env substituting $nlb_subnetids $uiurl $env $certname at"
echo "  ${PROGDIR}/gatewayapi/gatewayapi-uiingress-${e}.yaml "
envsubst '$nlb_subnetids $uiurl $env $certname' <${PROGDIR}/gatewayapi/gatewayapi-uiingress.yaml > ${PROGDIR}/gatewayapi/gatewayapi-uiingress-${e}.yaml
# GatewayAPI API URL
echo "Env substituting $nlb_subnetids $apiurl $env $certname at"
echo "  ${PROGDIR}/gatewayapi/gatewayapi-ingress-${e}.yaml "
envsubst '$nlb_subnetids $apiurl $env $certname' <${PROGDIR}/gatewayapi/gatewayapi-ingress.yaml > ${PROGDIR}/gatewayapi/gatewayapi-ingress-${e}.yaml
# GatewayAPI Swagger URL
echo "Env substituting $nlb_subnetids $swaggerurl $env $certname at"
echo "  ${PROGDIR}/gatewayapi/gatewayapi-swaggerbrms-${e}.yaml "
envsubst '$nlb_subnetids $swaggerurl $env $certname' <${PROGDIR}/gatewayapi/gatewayapi-swaggerbrms.yaml > ${PROGDIR}/gatewayapi/gatewayapi-swaggerbrms-${e}.yaml

#echo "Env substituting $miurl $env at"
#echo "  ${PROGDIR}/wso2/wso2mi-ingress-${e}.yaml"
#envsubst '$miurl $env $apicertname' <${PROGDIR}/wso2/wso2mi-ingress.yaml > ${PROGDIR}/wso2/wso2mi-ingress-${e}.yaml

# EFS
echo "Env substituing $fs_attachments $fs_data $fs_reject $fs_database $fs_reports at"
echo "  ${PROGDIR}/efs_mounts/efs-attachmentsVolumeNClaim.yaml"
envsubst '$fs_attachments' <${PROGDIR}/efs_mounts/efs-attachmentsVolumeNClaim.yaml > ${PROGDIR}/efs_mounts/efs-attachmentsVolumeNClaim-${e}.yaml
echo "  ${PROGDIR}/efs_mounts/efs-dataVolumeNClaim.yaml"
envsubst '$fs_data' <${PROGDIR}/efs_mounts/efs-dataVolumeNClaim.yaml > ${PROGDIR}/efs_mounts/efs-dataVolumeNClaim-${e}.yaml
echo "  ${PROGDIR}/efs_mounts/efs-rejectVolumeNClaim.yaml"
envsubst '$fs_reject' <${PROGDIR}/efs_mounts/efs-rejectVolumeNClaim.yaml > ${PROGDIR}/efs_mounts/efs-rejectVolumeNClaim-${e}.yaml
echo "  ${PROGDIR}/efs_mounts/efs-reportsVolumeNClaim.yaml"
envsubst '$fs_reports' <${PROGDIR}/efs_mounts/efs-reportsVolumeNClaim.yaml > ${PROGDIR}/efs_mounts/efs-reportsVolumeNClaim-${e}.yaml
echo "  ${PROGDIR}/efs_mounts/efs-databaseVolumeNClaim.yaml"
envsubst '$fs_database' <${PROGDIR}/efs_mounts/efs-databaseVolumeNClaim.yaml > ${PROGDIR}/efs_mounts/efs-databaseVolumeNClaim-${e}.yaml


# Jboss standalone-full.xml configmaps
echo "Generating k8s manifests jboss-servertype-config-env.yaml"
for srvtype in portal jms webservice brms reporting
do
    echo " ${PROGDIR}/jboss/standalone-full.xml.${srvtype}8"
    kubectl create configmap jboss-${srvtype}-config --save-config --dry-run=client -o yaml --namespace=ingress-nginx --from-file=standalone-full.xml=${PROGDIR}/jboss/standalone-full.xml.${srvtype}8 > ${PROGDIR}/jboss/jboss-${srvtype}-config-${e}.yaml
done
# BRMS custom config
echo "Generating customconfig.properties for Brms"
kubectl create configmap jboss-brms-custom-config --save-config --dry-run=client -o yaml --namespace=ingress-nginx --from-file=customconfig.properties=${PROGDIR}/jboss/customconfig.properties-${e} > ${PROGDIR}/jboss/jboss-brms-custom-config-${e}.yaml

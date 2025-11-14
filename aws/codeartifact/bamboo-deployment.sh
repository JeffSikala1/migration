#!/usr/bin/env bash

pip3 install requests -i  https://conexus-artifactory.edc.ds1.usda.gov/artifactory/api/pypi/pypi-local/simple --trusted-host conexus-artifactory.edc.ds1.usda.gov
# In the bamboo deploy task for BUILD PLANS use the following in the "Argument" section:
# '${bamboo.maven.version}' '${bamboo.inject.latestVersion}' '${bamboo.deploy.environment}' '${bamboo.deploy.project}' '${bamboo.planRepository.name}' '${bamboo.saltApiPassword}' '${bamboo.saltApiUser}' '${bamboo.buildKey}'
# In the bamboo deploy task for DEPLOY PLANS use the following in the "Argument" section:
# '${bamboo.maven.version}' '${bamboo.deploy.version}' '${bamboo.deploy.environment}' '${bamboo.deploy.project}' '${bamboo.planRepository.name}' '${bamboo.saltApiPassword}' '${bamboo.saltApiUser}' '${bamboo.buildKey}'

# The bamboo variables map to the following in this script
#bamboo_maven_version='${bamboo.maven.version}'
#bamboo_deploy_version='${bamboo.inject.latestVersion}'
#bamboo_deploy_environment='${bamboo.deploy.environment}'
#bamboo_deploy_project='${bamboo.deploy.project}'
#bamboo_planRepository_name='${bamboo.planRepository.name}'
#bamboo_saltApiPassword='${bamboo.saltApiPassword}'
#bamboo_saltApiUser='${bamboo.saltApiUser}'
#bamboo_buildKey='${bamboo.buildKey}'

## Get variables from Bamboo
bamboo_maven_version=$1
bamboo_deploy_version=$2
bamboo_deploy_environment=$3
bamboo_deploy_project=$4
bamboo_planRepository_name=$5
bamboo_saltApiPassword=$6
bamboo_saltApiUser=$7
bamboo_repoName=$8

echo -e "Starting the fun..."

python3 ./bamboo-deployment.py "${bamboo_maven_version}" \
                              "${bamboo_deploy_version}" \
                              "${bamboo_deploy_environment}" \
                              "${bamboo_deploy_project}" \
                              "${bamboo_planRepository_name}" \
                              "${bamboo_saltApiPassword}" \
                              "${bamboo_saltApiUser}" \
                              "${bamboo_repoName}" 

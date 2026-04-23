#!/usr/bin/env bash

artifactoryRepositoryUrl="https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/api/repositories"

longLivedPrefix="ll-"
BranchName="$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2)"

RepositoryBaseUrl="https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/"

# Set from global Bamboo variables
# Bamboo exposes secret variables to scripts with dots replaced by underscores
access_token="${bamboo_artifactory_access_token_secret}"

## Check to see if this is a long lived branch child
if [[ "${BranchName:0:3}" = "${longLivedPrefix}" ]]; then
    echo "This is a long lived branch"
    # Split the parent and child branch name
    ParentBranchName=$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2 | cut -d'+' -f1)
    ChildBranchName=$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2 | cut -d'+' -f2 -s)

    # Set the plugin repo to conexus-ll-plugin-repository
    # Set the branch repo to the parent branch
    echo "BranchName=${ParentBranchName}" >> file.properties
    echo "ChildBranchName=${ChildBranchName}" >> file.properties
    pluginRepositoryUrl="${RepositoryBaseUrl}conexus-ll-plugin-repository/"
    mavenFeatureRepositoryUrl="${RepositoryBaseUrl}${ParentBranchName}/"
    echo "pluginRepositoryUrl=${pluginRepositoryUrl}" >> file.properties
    echo "mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}" >> file.properties

    # Check that the long lived parent maven repo exists - if it doesn't create it
    mavenRepoExists=$(curl -s \
      -H "Authorization: Bearer ${access_token}" \
      -X GET "${artifactoryRepositoryUrl}?type=local&packageType=maven" \
      | grep "${BranchName}" | head -n1)

    echo "Checking if repo exists"
    if [[ -z "${mavenRepoExists}" ]]; then
        echo "Repo does not exist. Creating Maven repo: ${BranchName}"
        curl -s -X PUT \
          -H "Content-type: application/json" \
          -H "Authorization: Bearer ${access_token}" \
          "${artifactoryRepositoryUrl}/${BranchName}" \
          -d '{ "key": "'${BranchName}'", "rclass" : "local", "packageType": "maven", "repoLayoutRef" : "maven-2-default", "snapshotVersionBehavior": "unique"}'

        echo "Updating permissions on new repo"
        # Getting the anon_read_only permission model, add new repo name, and push changes
        curl -s -X GET \
          -H "Authorization: Bearer ${access_token}" \
          "https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/api/v2/security/permissions/anon_read_only" \
          | jq ".repo.repositories += [\"${BranchName}\"]" \
          | curl -s -X PUT \
              -H "Authorization: Bearer ${access_token}" \
              -H "Content-Type: application/json" \
              "https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/api/v2/security/permissions/anon_read_only" \
              -d@-

        # Getting the uploadOnly permission model, add new repo name, and push changes
        curl -s -X GET \
          -H "Authorization: Bearer ${access_token}" \
          "https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/api/v2/security/permissions/uploadOnly" \
          | jq ".repo.repositories += [\"${BranchName}\"]" \
          | curl -s -X PUT \
              -H "Authorization: Bearer ${access_token}" \
              -H "Content-Type: application/json" \
              "https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/api/v2/security/permissions/uploadOnly" \
              -d@-
    else
        echo "Repo does exist"
    fi

elif [[ ! "${BranchName:0:3}" = "${longLivedPrefix}" ]]; then
    echo "Not a long lived branch"
    # Not a long lived branch
    BranchName=$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2)

    # Set the plugin repo to conexus-plugin-repository
    # Set the feature repo to conexus-snapshot-local for SNAPSHOT artifact storage
    echo "BranchName=${BranchName}" >> file.properties
    pluginRepositoryUrl="${RepositoryBaseUrl}conexus-plugin-repository/"
    mavenFeatureRepositoryUrl="${RepositoryBaseUrl}conexus-snapshot-local/"
    echo "pluginRepositoryUrl=${pluginRepositoryUrl}" >> file.properties
    echo "mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}" >> file.properties

else
    echo "Cannot determine parent branch"
    exit 1
fi
#!/usr/bin/env bash

# Determine if a deploy is needed
# This variant deploys to Artifactory but does NOT create a Bamboo version
# (no latestVersion query, no bamboo version file entry)

longLivedPrefix="ll-"
BranchName="$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2)"

RepositoryBaseUrl="https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/"
MVN_SETTINGS="settings-artifactory.xml"
MVN_BIN="/usr/share/maven/bin/mvn"

## Check to see if this is a long lived branch child
if [ "${BranchName:0:3}" = "${longLivedPrefix}" ]; then
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

    # Determine if this is a long lived parent or child branch
    if [ -z "${ChildBranchName}" ]; then
        echo "This is a parent long-lived branch"
        ${MVN_BIN} deploy -DskipTests=true -U \
          -s ${MVN_SETTINGS} \
          -Djava.io.tmpdir=/tmp/BT-REC-JOB1 \
          -Dbamboo.inject.BranchName=${BranchName} \
          -Dbamboo.inject.mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl} \
          -Dbamboo.inject.pluginRepositoryUrl=${pluginRepositoryUrl} \
          -DaltDeploymentRepository=artifactory::${mavenFeatureRepositoryUrl}
    else
        echo "This is a child long-lived branch. Not deploying to Artifactory"
    fi

elif [ ! "${BranchName:0:3}" = "${longLivedPrefix}" ]; then
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

    if [ "$BranchName" == "develop" ]; then
        echo "This is a development branch. Deploying to Artifactory"
        ${MVN_BIN} deploy -DskipTests=true -U \
          -s ${MVN_SETTINGS} \
          -Djava.io.tmpdir=/tmp/BT-REC-JOB1 \
          -Dbamboo.inject.BranchName=${BranchName} \
          -Dbamboo.inject.mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl} \
          -Dbamboo.inject.pluginRepositoryUrl=${pluginRepositoryUrl} \
          -DaltDeploymentRepository=artifactory::${mavenFeatureRepositoryUrl}
    else
        echo "This is a child (feature) development branch. Not deploying to Artifactory"
    fi

else
    echo "Cannot determine parent branch"
    exit 1
fi
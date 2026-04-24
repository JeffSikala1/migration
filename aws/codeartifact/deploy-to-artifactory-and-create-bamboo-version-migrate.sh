#!/usr/bin/env bash

set -euo pipefail

# Determine if a deploy is needed

longLivedPrefix="ll-"
BranchName="$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2)"

RepositoryBaseUrl="https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/"
MVN_SETTINGS="settings-artifactory.xml"
MVN_BIN="/usr/share/maven/bin/mvn"
POM_PATH="${deployablePomPath:-war/pom.xml}"

# Derive mavenVersion from POM internally
# Replaces the Variable Extractor task that provided mavenVersion in legacy
# buildVersionQueryArtifact and buildVersionQueryGroup are still passed in
# from the plan as environment variables, consistent with legacy behavior
MVN_VERSION=$(${MVN_BIN} -f ${POM_PATH} -s ${MVN_SETTINGS} -q -DforceStdout \
  help:evaluate -Dexpression=project.version \
  | sed '/^\[/d' | grep -v '^$' | tail -1)

[ -n "${MVN_VERSION}" ] || { echo "ERROR: could not determine Maven version from POM"; exit 1; }

mavenVersion="${MVN_VERSION}"

echo "Resolved mavenVersion=${mavenVersion}"

## Check to see if this is a long lived branch child
if [ "${BranchName:0:3}" = "${longLivedPrefix}" ]; then
    echo "This is a long lived branch"
    ParentBranchName=$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2 | cut -d'+' -f1)
    ChildBranchName=$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2 | cut -d'+' -f2 -s)

    pluginRepositoryUrl="${RepositoryBaseUrl}conexus-ll-plugin-repository/"
    mavenFeatureRepositoryUrl="${RepositoryBaseUrl}${ParentBranchName}/"
    echo "BranchName=${ParentBranchName}" >> file.properties
    echo "ChildBranchName=${ChildBranchName}" >> file.properties
    echo "pluginRepositoryUrl=${pluginRepositoryUrl}" >> file.properties
    echo "mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}" >> file.properties

    if [ -z "${ChildBranchName}" ]; then
        echo "This is a parent long-lived branch"
        echo "buildVersionQueryArtifact=${buildVersionQueryArtifact}"
        echo "buildVersionQueryGroup=${buildVersionQueryGroup}"
        echo "mavenVersion=${mavenVersion}"

        ${MVN_BIN} deploy -DskipTests=true -U \
          -s ${MVN_SETTINGS} \
          -Dbamboo.inject.BranchName=${BranchName} \
          -Dbamboo.inject.mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl} \
          -Dbamboo.inject.pluginRepositoryUrl=${pluginRepositoryUrl} \
          -DaltDeploymentRepository=artifactory::${mavenFeatureRepositoryUrl}

        echo "https://${RepositoryBaseUrl}api/search/latestVersion?g=${buildVersionQueryGroup}&a=${buildVersionQueryArtifact}&v=${mavenVersion}&repos=${ParentBranchName}"
        echo -e "latestVersion=$(curl -k -s \
          -H "Authorization: Bearer ${bamboo_artifactory_access_token_secret}" \
          "${RepositoryBaseUrl}api/search/latestVersion?g=${buildVersionQueryGroup}&a=${buildVersionQueryArtifact}&v=${mavenVersion}&repos=${ParentBranchName}")" >> file.properties
    else
        echo "This is a child long-lived branch. Not deploying to Artifactory"
    fi

elif [ ! "${BranchName:0:3}" = "${longLivedPrefix}" ]; then
    echo "Not a long lived branch"
    BranchName=$(git rev-parse --abbrev-ref HEAD | cut -d'/' -f2)

    pluginRepositoryUrl="${RepositoryBaseUrl}conexus-plugin-repository/"
    mavenFeatureRepositoryUrl="${RepositoryBaseUrl}conexus-snapshot-local/"
    echo "BranchName=${BranchName}" >> file.properties
    echo "pluginRepositoryUrl=${pluginRepositoryUrl}" >> file.properties
    echo "mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl}" >> file.properties

    if [ "$BranchName" == "develop" ]; then
        echo "This is a development branch"
    else
        echo "This is not a develop branch but may be a feature branch"
    fi

    # Both develop and feature branches deploy and query latestVersion
    ${MVN_BIN} deploy -DskipTests=true -U \
      -s ${MVN_SETTINGS} \
      -Dbamboo.inject.BranchName=${BranchName} \
      -Dbamboo.inject.mavenFeatureRepositoryUrl=${mavenFeatureRepositoryUrl} \
      -Dbamboo.inject.pluginRepositoryUrl=${pluginRepositoryUrl} \
      -DaltDeploymentRepository=artifactory::${mavenFeatureRepositoryUrl}

    echo "buildVersionQueryArtifact=${buildVersionQueryArtifact}"
    echo "buildVersionQueryGroup=${buildVersionQueryGroup}"
    echo "mavenVersion=${mavenVersion}"

    echo -e "latestVersion=$(curl -k -s \
      -H "Authorization: Bearer ${bamboo_artifactory_access_token_secret}" \
      "${RepositoryBaseUrl}api/search/latestVersion?g=${buildVersionQueryGroup}&a=${buildVersionQueryArtifact}&v=${mavenVersion}&repos=conexus-snapshot-local")" >> file.properties

else
    echo "Cannot determine parent branch"
    exit 1
fi

echo "contents of file.properties"
echo " "
cat file.properties
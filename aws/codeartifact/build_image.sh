#!/usr/bin/env bash

source ./common.sh

function downloadFile() {
  downloadUrl=$1
  targetPathWithFileName=$2
  exitCode=0

  # -C is "continue at" for resuming download from a specified byte position
  # NOTE: the dash AFTER the -C (-C -) has meaning. This means curl should automatically figure out where to resume from based on the on-disk file being downloaded
  # -o {filename} write response to a file with the provided path/name
  echo "downloading $downloadUrl"
  httpStatusCode=$(curl -L -u "$ARTIFACTORY_USER:$ARTIFACTORY_TOKEN" "$downloadUrl" -C - -o $targetPathWithFileName -w "%{http_code}" --progress-bar ) || exitCode="$?"

  # just give up if we get http status over 200 but ignoring 416 which happens with -C if you are trying to resume on a file that is already fully downloaded
  # NOTE: This error handling is similar to how the --fail flag works in curl but I found this easier than dealing with exit codes which can sometimes be set to non-zero
  # in cases where the downloaded content is fine (like the http 416 resume case or the 206 partial content returned case)
  if [[ "$httpStatusCode" -gt 200 && "$httpStatusCode" -ne 416 && "$httpStatusCode" -ne 206 ]] ;
  then
    echo "Download of $downloadUrl failed with http status $httpStatusCode"
    exit 1
  fi

  # these curl downloads are configured to allow downloads to pick up where they left off if a file was partially downloaded earlier
  # occasionally the response code will be 200 even though there was an exit code of 18 which means the transfer closed with outstanding read data remaining
  # this depends on certain responses from artifactory which sometimes return unexpected results if the server returns an unexpected byte length
  # we need to bail out here and not continue since the file on disk is most likely incomplete even though the http response code was 200
  # restarting the script/download again is the correct and safe thing to do if this happens
  # normally I've only seen this on really large files
  if [[ "$exitCode" -eq 18 ]] ;
  then
    echo "Download of $downloadUrl failed due to a closed transfer. Just re-run the script again."
    exit 1
  fi
}

function cacheArtifacts() {
  echo "############################ Caching JBoss Installer and Patch ##############################################"
  ARTIFACTORY_BASE=https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/file-local

  downloadFile $ARTIFACTORY_BASE/jboss/$JBOSS_VER/$JBOSS_INSTALL_ZIP $JBOSS_INSTALL_ZIP_PATH
  downloadFile $ARTIFACTORY_BASE/jboss/$JBOSS_VER/patches/$JBOSS_ZIPPED_PATCH_MAVEN_REPO_FILENAME $JBOSS_PATCH_ZIP_PATH

  # deleting the driver as a precaution and since it's fast to download it
  rm $DRIVER_HOME/ojdbc8.jar
  rm $DRIVER_HOME/postgresql-42.7.8.jar
#  downloadFile $ARTIFACTORY_BASE/oracle/ojdbc/19c/ojdbc8.jar $DRIVER_HOME/ojdbc8.jar
  downloadFile https://artifactory.mgmt.cnxs.vpcaas.fcs.gsa.gov/artifactory/conexus-plugin-repository/org/postgresql/postgresql/42.7.8/postgresql-42.7.8.jar $DRIVER_HOME/postgresql-42.7.8.jar

  # For JasperReports in /reporting WAR
  downloadFile $ARTIFACTORY_BASE/fonts/$DEJAVU_FONT $FONTS_HOME/$DEJAVU_FONT
}

function testImage() {
  echo "############################ Test ###################################################"
  TEST_ALIAS=jboss-test
  JBOSS_HOME=/app/jboss-eap-$JBOSS_VER
  DEPLOYMENTS_DIR=$JBOSS_HOME/standalone/deployments

  cd test_war && zip -r ../tmp/test_war.war . && cd ../

  # Stop and remove the test container just in case the test did not finish cleanly the prior run.
  echo "If the following command fails, it's safe to continue"
  docker stop $TEST_ALIAS

  echo "If the following command fails, it's safe to continue"
  docker rm $TEST_ALIAS

  echo "Starting $TEST_ALIAS"

  docker run -d -p 8080:8080 --name=$TEST_ALIAS $JBOSS_TMP_NAME
  docker cp tmp/test_war.war $TEST_ALIAS:$DEPLOYMENTS_DIR/test_war.war
  docker exec -it $TEST_ALIAS chmod 644 $DEPLOYMENTS_DIR/test_war.war

  until `docker exec -it $TEST_ALIAS /app/jboss-eap-$JBOSS_VER/bin/jboss-cli.sh -c ":read-attribute(name=server-state)" 2> /dev/null | grep -q "running"`; do
    echo "Waiting for JBoss to start"
    sleep 1
  done

  echo "Waiting for deployment scanner to pick up WAR"
  until docker exec -it $TEST_ALIAS test -f $DEPLOYMENTS_DIR/test_war.war.deployed; do
    if docker exec -it $TEST_ALIAS test -f $DEPLOYMENTS_DIR/test_war.war.failed; then
      echo "JBoss deployment scanner reported a failed deployment"
      docker exec -it $TEST_ALIAS cat $DEPLOYMENTS_DIR/test_war.war.failed
      exit 1
    fi

    echo "Waiting for test_war.war deployment"
    sleep 1
  done

  curl http://localhost:8080/test_war/index.jsp

  docker stop $TEST_ALIAS
  docker rm $TEST_ALIAS
}

function buildImage() {
  echo "############################ Building Jboss ubi8-minimal Docker Image ##############################################"

  docker build \
  --force-rm --pull --allow network.host --progress=plain \
  --build-arg JBOSS_VER=$JBOSS_VER \
  --build-arg JBOSS_ZIP=$JBOSS_INSTALL_ZIP_PATH \
  --build-arg JBOSS_PATCH_ZIP=$JBOSS_PATCH_ZIP_PATH \
  --build-arg DEJAVU_FONT_TARBALL=$FONTS_HOME/$DEJAVU_FONT \
  -t $JBOSS_TMP_NAME --file dockerfiles/jboss.ubi8-minimal.Dockerfile .

  if [ $? -ne 0 ];
  then
    echo "docker build command failed"
    exit 1
  fi
}

function tagImage() {
  echo "############################ Tag ubi8 Docker Image ###################################################"
  docker tag $JBOSS_TMP_NAME $DOCKER_USER/$DOCKER_FULL_IMAGE_NAME:$DOCKER_TAG_NAME

  if [ $? -ne 0 ];
  then
    echo "docker tag command failed"
    exit 1
  fi
}

function createTempDirectories() {
  mkdir -p $INSTALLERS_HOME
  mkdir -p $PATCHES_HOME
  mkdir -p $DRIVER_HOME
  mkdir -p $FONTS_HOME
}

createTempDirectories
cacheArtifacts
buildImage
tagImage
testImage

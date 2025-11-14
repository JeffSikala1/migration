#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install_fortify_client.sh – non-interactive install of Fortify SCA 24.4
# -----------------------------------------------------------------------------
set -euo pipefail        # stop on first error, unset vars are errors, trace pipes

# Bamboo converts periods to underscores in variable names; yours arrives as:
#   bamboo_fortify_version="24.4.0"   (exported by the calling task)
: "${bamboo_fortify_version:?bamboo_fortify_version is not set}"

# ------------------------------------------------------------------ constants
ARTY_BASE="https://conexus-artifactory.edc.ds1.usda.gov/artifactory/file-local/fortify"
BUILD_DIR="/opt/build"
INSTALL_DIR="/opt/Fortify/${bamboo_fortify_version}"

# ---------------------------------------------------------------- prepare host
echo "[*] installing prerequisites & trusted root CA"
curl -k "${ARTY_BASE}/certificates/USDA_Enterprise_Root_CA.crt" -o /tmp/USDA_Root.crt
update-ca-trust extract

mkdir -p "${BUILD_DIR}"
cd       "${BUILD_DIR}"

# ---------------------------------------------------------------- license file
echo "[*] downloading Fortify license"
curl -k -o fortify.license "${ARTY_BASE}/fortify.license"

# ---------------------------------------------------------------- installers
echo "[*] downloading Fortify SCA and Apps installers"
curl -k -o "Fortify_SCA_${bamboo_fortify_version}_linux_x64.run" \
     "${ARTY_BASE}/Fortify_SCA_${bamboo_fortify_version}_linux_x64.run"

curl -k -o "Fortify_Apps_and_Tools_${bamboo_fortify_version}_linux_x64.run" \
     "${ARTY_BASE}/Fortify_Apps_and_Tools_${bamboo_fortify_version}_linux_x64.run"

chmod +x Fortify_SCA_"${bamboo_fortify_version}"_linux_x64.run \
         Fortify_Apps_and_Tools_"${bamboo_fortify_version}"_linux_x64.run

# ---------------------------------------------------------------- install SCA
echo "[*] installing Fortify SCA ${bamboo_fortify_version}"
./Fortify_SCA_"${bamboo_fortify_version}"_linux_x64.run \
    --mode unattended \
    --installdir "${INSTALL_DIR}" \
    --fortify_license_path "${BUILD_DIR}/fortify.license"

echo "[*] installing Fortify Apps & Tools ${bamboo_fortify_version}"
./Fortify_Apps_and_Tools_"${bamboo_fortify_version}"_linux_x64.run \
    --mode unattended \
    --installdir "${INSTALL_DIR}" \
    --fortify_license_path "${BUILD_DIR}/fortify.license"

# ---------------------------------------------------------------- PATH helper
export FORTIFY_HOME="${INSTALL_DIR}"
export PATH="${FORTIFY_HOME}/bin:${FORTIFY_HOME}/Fortify_Apps_and_Tools/bin:${PATH}"

# ---------------------------------------------------------------- update check
"${FORTIFY_HOME}/${bamboo_fortify_version}/bin/fortifyupdate" --url https://update.fortify.com

# ---------------------------------------------------------------- trust SSC CA
echo "[*] importing SSC host certificate"
openssl s_client -showcerts -servername easfortify.edc.ds1.usda.gov \
        -connect easfortify.edc.ds1.usda.gov:8443 </dev/null 2>/dev/null |
    openssl x509 -inform pem -outform pem |
    keytool  -importcert -noprompt \
             -alias easfortify.edc.ds1.usda.gov \
             -keystore "${FORTIFY_HOME}/jre/lib/security/cacerts" \
             -storepass changeit

# ---------------------------------------------------------------- Maven plugin
echo "[*] installing Maven SCA plugin"
tar xzf "${FORTIFY_HOME}/plugins/maven/maven-plugin-bin.tar.gz" -C "${BUILD_DIR}"

mvn install:install-file \
   -Dfile=maven-plugin/sca-maven-plugin-"${bamboo_fortify_version}".jar \
   -DpomFile=maven-plugin/pom.xml \
   -s /usr/share/maven/conf/settings-release.xml

echo "[✓] Fortify ${bamboo_fortify_version} installed in ${INSTALL_DIR}"

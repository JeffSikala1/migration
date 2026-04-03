FROM redhat/ubi8-minimal
LABEL maintainer="Bob Wernsman <robert.wernsman@gsa.gov"
USER root
# Set timezone
RUN ln -s /usr/share/zoneinfo/America/Chicago /etc/localtime && \
    microdnf update -y  && \
    microdnf install -y java-17-openjdk-headless less nss unzip tar gzip shadow-utils vi fontconfig && \
    microdnf clean all && \
    mkdir -p NSFS_NAS/database && \
    rm -rf /var/cache/yum /tmp/*

# Start Jboss installation

USER root

ARG JBOSS_VER
ARG JBOSS_ZIP
ARG JBOSS_PATCH_ZIP
ARG DEJAVU_FONT_TARBALL
ENV ENVIRONMENT=dev
ENV JBOSS_HOME /app/jboss-eap-$JBOSS_VER

ENV CONTAINER_JBOSS_PATCH_ZIP=/app/jboss-eap-patch.zip
###########################################################################################
# Begin the Jboss work
###########################################################################################

# Override HEAP and META_SIZE
# The IT tests run fine with the default values of JVM Heap and Metaspace, but redeploying
# EARs regularly during local development causes the Metaspace to run out. Unfortunately,
# JBoss does not provide an good way to pass JVM system properties to the standalone server
# configuration. You can override the value of the JAVA_OPTS environmental variable, but you
# have to do so in a way that preserves the default JBoss JAVA_OPTS options configured in
# bin/standalone.conf. What a pain. So what you see below is the exact value of the default
# JAVA_OPTS as copied from the bin/standalone.conf with memory overrides plus the inclusion
# of a java.security file.
ARG JBOSS_MODULES_SYSTEM_PKGS="org.jboss.byteman"
ARG HEAP_SIZE=3072m
ARG MAX_META_SIZE=1303m
ARG JAVA_SECURITY_FILE=$JBOSS_HOME/standalone/configuration/java.security
ENV JAVA_OPTS -Xms$HEAP_SIZE \
  -Xmx$HEAP_SIZE \
  -XX:MetaspaceSize=96M \
  -XX:MaxMetaspaceSize=$MAX_META_SIZE \
  -Djava.net.preferIPv4Stack=true \
  -Djboss.modules.system.pkgs=$JBOSS_MODULES_SYSTEM_PKGS \
  -Djava.awt.headless=true \
  -Djava.security.properties=$JAVA_SECURITY_FILE

# Add the jboss user
RUN useradd -U -m -d /app/ jboss

# set jboss the owner of NSFS_NAS/database for vendor file IT testing
RUN chown -R jboss:jboss NSFS_NAS

# Copy and extract base Jboss installer and copy patch
WORKDIR /app/
COPY $JBOSS_ZIP /app/jboss-eap.zip
RUN unzip -q jboss-eap.zip && \
    rm jboss-eap.zip
COPY $JBOSS_PATCH_ZIP $CONTAINER_JBOSS_PATCH_ZIP
RUN chown -R jboss:jboss /app/*

# Copy jboss configuration scripts
COPY --chown=jboss:jboss jboss_config /app/jboss_config/
#COPY --chown=jboss:jboss files/jboss/vault $JBOSS_HOME/vault/

# Install java security file
COPY jboss_config/java.security $JAVA_SECURITY_FILE

# Install Postgres JDBC module
COPY tmp/driver/postgresql-42.7.8.jar /tmp/postgresql-42.7.8.jar

# Install required JasperReports Font
COPY $DEJAVU_FONT_TARBALL  /tmp/dejavu-fonts-ttf.tar.gz
RUN mkdir -p /usr/share/fonts/dejavu/
RUN tar -C /usr/share/fonts/dejavu -xzvf /tmp/dejavu-fonts-ttf.tar.gz
RUN fc-cache /usr/share/fonts/

# Modify the jboss-cli.xml file
#RUN sed -i 's/chown \$JBOSS_USER/chown \$JBOSS_USER\:/' /etc/init.d/jboss

# Start Jboss and apply patches and configurations
USER jboss
WORKDIR /app/jboss_config/

RUN cp restart-clean.sh $JBOSS_HOME/bin
RUN chmod a+x $JBOSS_HOME/bin/restart-clean.sh

RUN chmod a+x config.sh && \
    bash config.sh $CONTAINER_JBOSS_PATCH_ZIP
RUN sed -i 's|<location name="/" handler="welcome-content"/>||' $JBOSS_HOME/standalone/configuration/standalone-full.xml

# Delete applied patch kits and cli files
WORKDIR /app/
RUN rm -rf /app/jboss-*-patch.zip /app/jboss_config/

USER root
RUN chown -R jboss:jboss /app/jboss-eap*

USER jboss

# Ensure signals are forwarded to the JVM process correctly for graceful shutdown
ENV LAUNCH_JBOSS_IN_BACKGROUND true

# Expose the ports that we are interested in
EXPOSE 9797 8080 9990 5445 8443 9999 9993

WORKDIR $JBOSS_HOME/
# Specify the debug port *:8787 to match the agentlib pattern for Java 9+ (-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:8787)
CMD ["sh", "-c", "$JBOSS_HOME/bin/standalone.sh -c=standalone-full.xml --debug '*:8787' && tail -F $JBOSS_HOME/standalone/log/server.log"]
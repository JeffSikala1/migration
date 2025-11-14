FROM 339713019047.dkr.ecr.us-east-1.amazonaws.com/conexus-jboss:8.0.8

ARG UIWAR
ARG RESTEAR
USER jboss

ARG EAP_DEPLOY_DIR=/app
ARG EAP_VERSION=8.0
ENV JBOSS_HOME="${EAP_DEPLOY_DIR}/jboss-eap-${EAP_VERSION}"

COPY ${UIWAR}  ${JBOSS_HOME}/standalone/deployments/ui.war
COPY ${RESTEAR}  ${JBOSS_HOME}/standalone/deployments/rest.ear
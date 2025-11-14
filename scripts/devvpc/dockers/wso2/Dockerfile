FROM wso2/wso2mi:4.3.0-rocky

ARG WSOCARBON_HOME=/home/wso2carbon/wso2mi-4.3.0

COPY --chown=wso2carbon:wso2 *car ${WSOCARBON_HOME}/repository/deployment/server/carbonapps/

#COPY --chown=wso2carbon:wso2 deployment.toml ${WSOCARBON_HOME}/conf/deployment.toml

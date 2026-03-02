FROM 957770628377.dkr.ecr.us-east-1.amazonaws.com/sandbox-jboss-brms:0.1

#COPY ui-war.war /app/jboss-eap-7.4/standalone/deployments/
RUN yum -y install less
#COPY standalone-full.xml.fixedwars /app/jboss-eap-7.4/standalone/configuration/standalone-full.xml

CMD ["/app/jboss-eap-7.4/bin/standalone.sh", "-Djboss.home.dir=/app/jboss-eap-7.4/", "-Djboss.server.config.dir=/app/jboss-eap-7.4/standalone/configuration/", "-c",  "standalone-full.xml"]
#CMD ["/bin/bash", "/app/jboss_startup.sh", ">/dev/null", "2>&1"]  

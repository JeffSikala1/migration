FROM redhat/ubi10-minimal:10.0-1755721767


RUN microdnf update -y
RUN microdnf install -y httpd mod_auth_openidc mod_ssl less which net-tools procps-ng mod_session mod_proxy_html mod_security curl-minimal
RUN microdnf clean all


COPY ./swagger_vhost.conf /etc/httpd/conf.d/swagger_vhost.conf
COPY ./10-auth_openidc.conf /etc/httpd/conf.modules.d/10-auth_openidc.conf
COPY ./httpd.conf /etc/httpd/conf/httpd.conf
#Enable usertrack module
COPY ./00-optional.conf /etc/httpd/conf.modules.d/00-optional.conf
#Disable ssl, this is behind cilium gatewayapi which handles SSL
COPY ./ssl.conf /etc/httpd/conf.d/ssl.conf
COPY ./maintenance.html /var/www/html/errors/maintenance.html
RUN rm -f /etc/httpd/conf.d/mod_security.conf

#RUN touch /var/www/html/maintenance/maintenance.enable

#RUN systemctl enable httpd
ADD html /var/www/html/                   

EXPOSE 80  
CMD ["/bin/bash"]
USER apache
#CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]



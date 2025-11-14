FROM fedora:40           

RUN dnf update -y
RUN dnf install -y httpd mod_auth_openidc mod_ssl less which net-tools procps-ng mod_session mod_proxy_html mod_security curl 
RUN dnf clean all


RUN mkdir -p /app/conexus-ui-public /app/conexus-help 
COPY ./conexus_vhost.conf /etc/httpd/conf.d/conexus_vhost.conf
COPY ./10-auth_openidc.conf /etc/httpd/conf.modules.d/10-auth_openidc.conf
COPY ./httpd.conf /etc/httpd/conf/httpd.conf
COPY ./00-optional.conf /etc/httpd/conf.modules.d/00-optional.conf
COPY ./ssl.conf /etc/httpd/conf.d/ssl.conf
COPY ./maintenance.html /var/www/html/errors/maintenance.html
RUN rm -f /etc/httpd/conf.d/mod_security.conf

#RUN touch /var/www/html/maintenance/maintenance.enable

#RUN systemctl enable httpd
ADD html /var/www/html/                   
ADD conexus-ui-public /app/conexus-ui-public

EXPOSE 80  
CMD ["/bin/bash"]
#CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]


FROM fedora:40           

RUN dnf update -y
#RUN dnf install -y httpd mod_auth_openidc mod_ssl less which net-tools procps-ng mod_session mod_proxy_html mod_security clamav clamav-filesystem clamav-data clamav-freshclam crontabs curl python3-magic
RUN dnf install -y httpd less which net-tools procps-ng mod_session mod_proxy_html mod_security clamav clamav-filesystem clamav-data clamav-freshclam crontabs curl python3-magic
RUN dnf clean all


RUN mkdir -p /app /etc/httpd/scripts /app/modsecurity/tmp /app/modsecurity/upload && \
touch /var/log/httpd/av.log && \
chown apache:apache /etc/httpd/scripts /app/modsecurity/tmp /app/modsecurity/upload /var/log/httpd/av.log && \
chmod 0750 /etc/httpd/scripts && \
chmod 0755 /var/log/httpd && \
rm -f /etc/httpd/conf.d/welcome.conf && \
rm -f /etc/httpd/conf.d/userdir.conf && \
rm -f /etc/httpd/conf.d/autoindex.conf && \
rm -f /etc/httpd/conf.d/ssl.conf && \
rm -f /etc/httpd/conf.d/mod_security3.conf

COPY ./httpd.conf /etc/httpd/conf/httpd.conf
COPY proxy.conf /etc/httpd/conf.d/proxy.conf
COPY mod_security.conf /etc/httpd/conf.d/mod_security.conf
COPY --chown=apache:apache --chmod=0750 scripts/ /etc/httpd/scripts/
COPY --chmod=0644 httpd /etc/logrotate.d/httpd

COPY freshclamcron /etc/cron.d/freshclamcron
RUN chmod 0644 /etc/cron.d/freshclamcron
RUN crontab /etc/cron.d/freshclamcron
#RUN touch /var/www/html/maintenance/maintenance.enable

#RUN systemctl enable httpd

EXPOSE 80  
CMD ["/usr/sbin/crond && /bin/bash"]
#CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]


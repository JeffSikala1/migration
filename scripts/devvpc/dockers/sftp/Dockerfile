FROM fedora:40           

RUN dnf update -y
RUN dnf install -y mod_ssl less which net-tools procps-ng curl clamav clamav-filesystem clamav-data clamav-freshclam crontabs python3-magic sqlite moreutils
RUN dnf clean all


RUN mkdir -p /app/ConexusSFTP
ADD ConexusSFTP /app/ConexusSFTP

COPY freshclamcron /etc/cron.d/freshclamcron
COPY efschrootfolders-prodcreate.txt /app/ConexusSFTP
COPY efschrootfolders-certcreate.txt /app/ConexusSFTP
RUN chmod 0644 /etc/cron.d/freshclamcron
RUN crontab /etc/cron.d/freshclamcron
RUN /usr/bin/freshclam
COPY startup.sh .
RUN chmod 0744 startup.sh

CMD ["/bin/bash", "./startup.sh"]

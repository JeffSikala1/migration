FROM fedora:40

ENV PATH=$PATH
RUN dnf update -y
RUN dnf install -y httpd less which net-tools procps-ng curl python3-magic perl-CGI hostname
RUN dnf clean all
COPY prh /var/www/cgi-bin/prh
STOPSIGNAL SIGWINCH

COPY --chmod=755 ./httpd-foreground /usr/local/bin/
COPY --chmod=644 ./httpd.conf /etc/httpd/conf/

ENV PATH=/usr/local/bin:$PATH
EXPOSE 80
CMD ["/usr/local/bin/httpd-foreground"]


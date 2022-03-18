FROM alpine:3.15.0
LABEL maintainer="Molnár, Sándor Gábor <molnar.sandor.gabor@udinfopark.com>"

ENV SWAKS_VERSION=20201014.0

ENV DB_TYPE \
    DB_USER \
    DB_PASS \
    DB_NAME \
    DB_HOST \
    DB_PORT \
    ALL_DATABASES  \
    BACKUP_PATH \
    RETENTION_DAYS \
    TAG \
    DB_ENGINE \
    CRON_SCHEDULE \
    EMAIL_ON_ERROR \
    EMAIL_ON_SUCCESS \
    SKAWS_SERVER \
    SKAWS_PORT \
    SKAWS_TLS \
    SKAWS_FROM \
    SKAWS_TO \
    SKAWS_AUTH \
    SKAWS_USER \
    SKAWS_PASSWORD \
    SKAWS_HEADER
    
RUN apk add --update --no-cache mariadb-client postgresql-client bash findutils coreutils busybox \
        perl perl-net-ssleay perl-net-dns curl make tzdata

RUN curl -SLk https://www.jetmore.org/john/code/swaks/files/swaks-$SWAKS_VERSION/swaks -o swaks; \
    chmod +x swaks; \
    yes | perl -MCPAN -e 'install Authen::NTLM'; \
    rm -rf /root/.cpan; \
    apk del make; \
    mv /swaks /usr/bin

CMD mkdir /app

COPY backup.sh /app/backup.sh

CMD chmod 755 /app/backup.sh

ENTRYPOINT /app/backup.sh

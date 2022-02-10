FROM alpine:3.15.0
LABEL maintainer="Molnár, Sándor Gábor <molnar.sandor.gabor@udinfopark.hu>"


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
    CRON_SCHEDULE

RUN apk update && apk add --no-cache mariadb-client postgresql-client bash findutils coreutils busybox

CMD mkdir /app

COPY backup.sh /app/backup.sh

CMD chmod 755 /app/backup.sh

ENTRYPOINT /app/backup.sh

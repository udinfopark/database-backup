#!/usr/bin/env bash

# v0.1 2022.02.03. Molnar, Sandor Gabor <molnar.sandor.gabor@udinfopark.hu>
# v0.2 2022.02.10. Molnar, Sandor Gabor <molnar.sandor.gabor@udinfopark.hu>

# Expected environment variables from container settings
# DB_USER: database user which has rights to dump all/selected databases
# DB_PASS: password for database user
# DB_HOST: database host name or ip address
# DB_PORT: database port (mysql/mariadb: 3306, postgressql: 5432 by default)
# DB_TYPE: database type, valid values: "mariadb", "mysql" or "postgresql"
# DB_ENGINE: to handle different database engine. At mysql/mariadb the default is "innodb"
#
# ALL_DATABASES: if it is defined regardless it's value, all database will backup
# DB_NAME: name of the database to backup, if ALL_DATABASES is defined, this will be ignored
#
# BACKUP_PATH: path in the container where the backups will be created, this should be bind/mount as external volume
#
# RETENTION_DAYS: how much days has to be store in the backup days, default is 30
#
# TAG: tag of the backup. With this tag you can distict backups.
#      Eg: at manuall running before patch: TAG=before_tag
#
# CRON_SCHEDULE: if you want use periodically it, define the schedule by the usual cron format
#                The container will run inside the cron. This is recommended in docker environment.
#                In Kubernetes environment use the CronJob Kubernetes object.
#


### Environment variables and parameter check

# If the command line first parameter is "fromcron" that means it started from cron, so schedule is not needed.
if [ "$1" = 'fromcron' ]; then
    CRON_SCHEDULE=''
fi

if [ "${DB_USER}" = '' ]; then
    echo 'Missing DB_USER environment variable'
    exit 1
fi
if [ "${DB_PASS}" = '' ]; then
    echo 'Missing DB_PASS environment variable'
    exit 1
fi
if [ "${DB_HOST}" = '' ]; then
    echo 'Missing DB_HOST environment variable'
    exit 1
fi

if [ "${DB_TYPE}" = 'mysql' ]; then
    DB_TYPE='mariadb'
fi
if [ "${DB_TYPE}" != 'mariadb' ] && [ "${DB_TYPE}" != 'postgresql' ]; then
    echo 'Unsupported DB_TYPE'
    exit 1
fi
if [ "${DB_TYPE}" = 'postgresql' ]; then
    export PGPASSWORD="${DB_PASS}"
fi


if [ "${DB_PORT}" = '' ]; then
    if [ "${DB_TYPE}" = 'mariadb' ]; then
        DB_PORT=3306
    fi
    if [ "${DB_TYPE}" = 'postgresql' ]; then
        DB_PORT=5432
    fi
fi

if [ "${RETENTION_DAYS}" = '' ]; then
    RETENTION_DAYS=31
fi
if [ "${TAG}" = '' ]; then
    TAG='-'
fi

MARIADB_OPTIONS='--lock-all-tables'

if [ "${DB_ENGINE}" = '' ]; then
    DB_ENGINE='innodb'
fi
if [ "${DB_ENGINE}" = 'innodb' ]; then
    MARIADB_OPTIONS=' --single-transaction'
fi


if [ "${ALL_DATABASES}" = 'x' ]; then
    if [ "${DB_NAME}" = 'x' ]; then
        echo 'Missing DB_NAME environment variable'
        exit 1
    fi
fi


### Functions
function create_path {
    DATE=$(date +"%Y-%m-%d_%H-%M-%S")

    if [ "${TAG}" = '-' ]; then
        BPATH="${BACKUP_PATH}/${DATE}"
    else
        BPATH="${BACKUP_PATH}/${DATE}-${TAG}"
    fi
    mkdir -p "${BPATH}"
    export BACKUP_DIR="${BPATH}"
}

function backup_mariadb {
    if [ "${ALL_DATABASES}" = '' ]; then
        mysqldump --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" ${MARIADB_OPTIONS} "${DB_NAME}" | gzip > "${BACKUP_DIR}/${DB_NAME}.sql.gz"
    else
        databases=$(mysql --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
        for db in $databases; do
            if [ "$db" != 'information_schema' ] && [ "$db" != 'performance_schema' ] && [ "$db" != 'mysql' ]; then
                mysqldump --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" ${MARIADB_OPTIONS} --databases "$db" | gzip > "${BACKUP_DIR}/$db.sql.gz"
            fi
        done
    fi
}

function backup_postgresql {
    if [ "${ALL_DATABASES}" = '' ]; then
        pg_dump -U "${DB_USER}" -h "${DB_HOST}" -p "${DB_PORT}" ${POSTGRESQL_OPTIONS} "${DB_NAME}" | gzip > "${BACKUP_DIR}/${DB_NAME}.sql.gz"
    else
        pg_dumpall -U "${DB_USER}" -h "${DB_HOST}" -p "${DB_PORT}" ${POSTGRESQL_OPTIONS} | gzip > "${BACKUP_DIR}/all.sql.gz"
    fi
}

function cleanup_old_backups {
    find "${BACKUP_PATH}" -mtime +${RETENTION_DAYS} -delete
}

function backup {
    create_path
    if [ "${DB_TYPE}" = 'mariadb' ]; then
        backup_mariadb
    else
        backup_postgresql
    fi
    cleanup_old_backups
}

function setup_cron {
    CRON_SCHEDULE="${CRON_SCHEDULE/[\"\']//g}"
    echo "${CRON_SCHEDULE} /app/backup.sh fromcron" >/app/crontab.txt
    /usr/bin/crontab /app/crontab.txt

    /usr/sbin/crond -f -l 8
}


### Main part
if [ "${CRON_SCHEDULE}" != '' ]
then
    setup_cron
else
    backup
fi

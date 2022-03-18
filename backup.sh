#!/usr/bin/env bash

# 0.1 2022.02.03. Molnar, Sandor Gabor <molnar.sandor.gabor@udinfopark.hu>
# 0.2 2022.02.10. Molnar, Sandor Gabor <molnar.sandor.gabor@udinfopark.hu>
# 0.3 2022.03.17. Molnar, Sandor Gabor <molnar.sandor.gabor@udinfopark.hu>


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
#                In Kubernetes environment use the CronJob Kubernetes object so set it's value to "kubernetes"
#
#
# EMAIL_ON_ERROR
# EMAIL_ON_SUCCESS
# SWAKS_SERVER
# SWAKS_PORT
# SWAKS_TLS
# SWAKS_FROM
# SWAKS_TO
# SWAKS_AUTH
# SWAKS_USER
# SWAKS_PASSWORD
# SWAKS_HEADER
#

function error_echo { >&2 echo $@; }


### Environment variables and parameter check

# If the command line first parameter is "fromcron" that means it started from cron, so schedule is not needed.
if [ "$1" = 'fromcron' ]; then
    CRON_SCHEDULE=''
fi

if [ "${CRON_SCHEDULE}" = 'kubernetes' ]; then
    CRON_SCHEDULE=''
fi

if [ "${DB_USER}" = '' ]; then
    error_echo 'Missing DB_USER environment variable'
    exit 1
fi
if [ "${DB_PASS}" = '' ]; then
    error_echo 'Missing DB_PASS environment variable'
    exit 1
fi
if [ "${DB_HOST}" = '' ]; then
    error_echo 'Missing DB_HOST environment variable'
    exit 1
fi

if [ "${DB_TYPE}" = 'mysql' ]; then
    DB_TYPE='mariadb'
fi
if [ "${DB_TYPE}" != 'mariadb' ] && [ "${DB_TYPE}" != 'postgresql' ]; then
    error_echo 'Unsupported DB_TYPE'
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
        error_echo 'Missing DB_NAME environment variable'
        exit 1
    fi
fi

if [ "${EMAIL_ON_ERROR}" != '' ] || [ "${EMAIL_ON_SUCCESS}" != '' ]; then
    if [ "${SWAKS_SERVER}" = '' ]; then
        error_echo 'Missing SWAKS_SERVER environment variable'
        exit 1
    fi
    if [ "${SWAKS_PORT}" = '' ]; then
        error_echo 'Missing SWAKS_PORT environment variable'
        exit 1
    fi
    if [ "${SWAKS_FROM}" = '' ]; then
        error_echo 'Missing SWAKS_FROM environment variable'
        exit 1
    fi
    if [ "${SWAKS_TO}" = '' ]; then
        error_echo 'Missing SWAKS_TO environment variable'
        exit 1
    fi
    if [ "${SWAKS_HEADER}" = '' ]; then
        SWAKS_HEADER='Automatic report of database backup'
    fi
fi

if [ "${SWAKS_TLS}" = 'false' ] || [ "${SWAKS_TLS}" = 'no' ]; then
    SWAKS_TLS=''
fi


### Functions
function send_email {
    SWAKS_OPTIONS="--server ${SWAKS_SERVER} --port ${SWAKS_PORT} --from ${SWAKS_FROM} --to ${SWAKS_TO}"
    
    if [ "${SWAKS_TLS}" != '' ]; then
        SWAKS_OPTIONS="${SWAKS_OPTIONS} -tls"
    fi
    if [ "${SWAKS_AUTH}" != '' ]; then
        SWAKS_OPTIONS="${SWAKS_OPTIONS} --auth ${SWAKS_AUTH}"
    fi
    if [ "${SWAKS_USER}" != '' ]; then
        SWAKS_OPTIONS="${SWAKS_OPTIONS} --auth-user ${SWAKS_USER}"
    fi
    if [ "${SWAKS_PASSWORD}" != '' ]; then
        SWAKS_OPTIONS="${SWAKS_OPTIONS} --auth-password ${SWAKS_PASSWORD}"
    fi

    SWAKS_OPTIONS="${SWAKS_OPTIONS} --header 'Subject: ${SWAKS_HEADER}' --body '$@'"

    eval /usr/bin/swaks ${SWAKS_OPTIONS}
}


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
    ERROR_SUM=''
    if [ "${ALL_DATABASES}" = '' ]; then
        mysqldump --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" ${MARIADB_OPTIONS} "${DB_NAME}" 2> "${BACKUP_DIR}/${DB_NAME}.stderr.log" | gzip > "${BACKUP_DIR}/${DB_NAME}.sql.gz"
    else
        databases=$(mysql --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" -e "SHOW DATABASES;" | tr -d "| " | grep -v Database)
        for db in $databases; do
            if [ "$db" != 'information_schema' ] && [ "$db" != 'performance_schema' ] && [ "$db" != 'mysql' ]; then
                ERROR=$( { 
                    mysqldump --user="${DB_USER}" --password="${DB_PASS}" --host="${DB_HOST}" ${MARIADB_OPTIONS} --databases "$db" | gzip > "${BACKUP_DIR}/$db.sql.gz" 
                    } 2>&1 )
                if [ "${ERROR}" != '' ]; then
                    echo ${ERROR} > "${BACKUP_DIR}/$db.stderr.log"
                    ERROR_SUM=${ERROR_SUM}"\n"${ERROR}
                fi
            fi
        done
    fi
    if [ "${ERROR_SUM}" != '' ] && [ "${EMAIL_ON_ERROR}" != '' ]; then
        send_email "${ERROR_SUM}"
        return
    fi
    if [ "${EMAIL_ON_SUCCESS}" != '' ]; then
        DIRECTORY_CONTENT=$( ls -al "${BACKUP_DIR}" )
        send_email "${DIRECTORY_CONTENT}"
    fi
}


function backup_postgresql {
    if [ "${ALL_DATABASES}" = '' ]; then
        pg_dump -U "${DB_USER}" -h "${DB_HOST}" -p "${DB_PORT}" "${POSTGRESQL_OPTIONS}" "${DB_NAME}" | gzip > "${BACKUP_DIR}/${DB_NAME}.sql.gz"
    else
        pg_dumpall -U "${DB_USER}" -h "${DB_HOST}" -p "${DB_PORT}" "${POSTGRESQL_OPTIONS}" | gzip > "${BACKUP_DIR}/all.sql.gz"
    fi

    if [ "${ERROR_SUM}" != '' ] && [ "${EMAIL_ON_ERROR}" != '' ]; then
        send_email "${ERROR_SUM}"
        return
    fi
    if [ "${EMAIL_ON_SUCCESS}" != '' ]; then
        DIRECTORY_CONTENT=$( ls -al "${BACKUP_DIR}" )
        send_email "${DIRECTORY_CONTENT}"
    fi
}


function cleanup_old_backups {
    find "${BACKUP_PATH}" -mtime +${RETENTION_DAYS} -delete
}


function generate_md5sum {
    ls "${BACKUP_DIR}" | grep .gz | while read filename; do md5sum "${BACKUP_DIR}/${filename}" >> "${BACKUP_DIR}/checksum.md5"; done

}


function backup {
    create_path
    if [ "${DB_TYPE}" = 'mariadb' ]; then
        backup_mariadb
    else
        backup_postgresql
    fi
    generate_md5sum
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


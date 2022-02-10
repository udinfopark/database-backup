# Database Backup container for mysql/mariadb and postgresql with optional cron schedule

## Create docker image

docker build . -t nexus.udinfopark.hu:8444/repository/k8s/database-backup:0.1
docker push nexus.udinfopark.hu:8444/repository/k8s/database-backup:0.1


## Usage

You can find example docker-compose.yaml files in the directory examples.
- cp examples/postgresql_with_cron.yaml docker-compose.yaml
- customize/configure in the docker-compose.yaml
- docker-compose up

## Customization / configuration

Expected environment variables from container settings (docker-compose.yaml)

- DB_USER: database user which has rights to dump all/selected databases
- DB_PASS: password for database user
- DB_HOST: database host name or ip address
- DB_PORT: database port (mysql/mariadb: 3306, postgresql: 5432 by default)
- DB_TYPE: database type, valid values: "mariadb", "mysql" or "postgresql"
- DB_ENGINE: to handle different database engine. At mysql/mariadb the default is "innodb"
- ALL_DATABASES: if it is defined regardless it's value, all database will backup
- DB_NAME: name of the database to backup, if ALL_DATABASES is defined, this will be ignored
- BACKUP_PATH: path in the container where the backups will be created, this should be bind/mount as external volume
- RETENTION_DAYS: how much days has to be store in the backup days, default is 30
- TAG: tag of the backup. With this tag you can distict backups.
    Eg: at manuall running before patch: TAG=before_tag
- CRON_SCHEDULE: if you want use periodically it, define the schedule by the usual cron format
              The container will run inside the cron. This is recommended in docker environment.
              In Kubernetes environment use the CronJob Kubernetes object.

#!/bin/bash
# Se ejecuta una sola vez, en el primer arranque del contenedor de postgres
# (docker-entrypoint-initdb.d). POSTGRES_DB ya existe en este punto (creada
# por la imagen oficial); aqui se agregan los schemas de la capa medallion
# y una segunda base de datos para la metadata de Airflow.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    CREATE SCHEMA IF NOT EXISTS bronze;
    CREATE SCHEMA IF NOT EXISTS silver;
    CREATE SCHEMA IF NOT EXISTS gold;
SQL

AIRFLOW_DB_NAME="${AIRFLOW_DB:-airflow}"

DB_EXISTS=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -tAc "SELECT 1 FROM pg_database WHERE datname = '${AIRFLOW_DB_NAME}'")

if [ "$DB_EXISTS" != "1" ]; then
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
        -c "CREATE DATABASE \"${AIRFLOW_DB_NAME}\" OWNER \"${POSTGRES_USER}\";"
fi

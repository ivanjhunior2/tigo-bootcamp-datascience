"""Conexion a Postgres (schema warehouse: bronze/silver/gold), configurada por env vars."""
import os

import psycopg2
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine


def get_connection_params() -> dict:
    return {
        "host": os.environ.get("WAREHOUSE_HOST", "localhost"),
        "port": os.environ.get("WAREHOUSE_PORT", "5432"),
        "dbname": os.environ.get("WAREHOUSE_DB", "warehouse"),
        "user": os.environ.get("WAREHOUSE_USER", "dataeng"),
        "password": os.environ.get("WAREHOUSE_PASSWORD", "dataeng_pw"),
    }


def get_psycopg2_connection():
    return psycopg2.connect(**get_connection_params())


def get_engine() -> Engine:
    params = get_connection_params()
    url = (
        f"postgresql+psycopg2://{params['user']}:{params['password']}"
        f"@{params['host']}:{params['port']}/{params['dbname']}"
    )
    return create_engine(url)

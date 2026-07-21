"""Config de Superset -- SECRET_KEY y conexion a su propia base de metadata
(schema separado en la misma instancia de Postgres, ver
docker/postgres/init/01-init-databases.sh -- mismo criterio que Airflow)."""
import os

SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]

SQLALCHEMY_DATABASE_URI = (
    f"postgresql+psycopg2://{os.environ['POSTGRES_USER']}:{os.environ['POSTGRES_PASSWORD']}"
    f"@postgres:5432/{os.environ['SUPERSET_DB']}"
)

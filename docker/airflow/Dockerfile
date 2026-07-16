FROM apache/airflow:2.10.4-python3.11

# Instalar con el constraints file oficial de Airflow: evita que pip resuelva
# versiones de dependencias (ej. SQLAlchemy) incompatibles con el auth manager
# interno de Airflow, que rompe comandos como "airflow users create".
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt \
    --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.10.4/constraints-3.11.txt"

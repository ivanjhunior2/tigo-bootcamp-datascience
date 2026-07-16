"""Pipeline CRM + Billing + Universidad.

Este DAG se extiende fase a fase. Etapa actual: ingesta cruda -> bronze y
validacion de conteos contra manifest.json. Proximas iteraciones agregan
build_silver, build_gold, export_parquet y validate_pipeline como nuevos
TaskGroups sobre este mismo DAG.
"""
import sys
from datetime import datetime
from pathlib import Path

from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup

sys.path.append(str(Path("/opt/airflow/src")))

from ingestion.load_csv_to_bronze import DOMAIN_TABLES, load_domain  # noqa: E402
from validation.check_bronze_counts import check as validate_bronze_counts  # noqa: E402

default_args = {
    "owner": "data-eng",
    "retries": 1,
}

with DAG(
    dag_id="crm_billing_universidad_pipeline",
    description="Pipeline de datos CRM + Billing + Universidad (bronze -> silver -> gold)",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    default_args=default_args,
    tags=["crm", "billing", "universidad"],
) as dag:

    with TaskGroup("ingest_bronze") as ingest_bronze:
        for domain in DOMAIN_TABLES:
            PythonOperator(
                task_id=f"ingest_{domain}",
                python_callable=load_domain,
                op_kwargs={"domain": domain, "dag_run_id": "{{ run_id }}"},
            )

    validate_bronze = PythonOperator(
        task_id="validate_bronze_counts",
        python_callable=validate_bronze_counts,
    )

    ingest_bronze >> validate_bronze

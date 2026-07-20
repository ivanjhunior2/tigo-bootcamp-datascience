"""Pipeline CRM + Billing + Universidad.

DAG completo: ingesta -> bronze -> silver -> gold -> export a Parquet ->
validacion end-to-end. Silver (pandas) y gold (SQL) viven en notebooks de
Jupyter (ver notebooks/README.md); este DAG los dispara via nbconvert
(src/orchestration/run_notebook.py) en vez de duplicar esa logica en
scripts .py -- misma transformacion que ya se verifico a mano, solo
orquestada.
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
from validation.validate_pipeline import validate as validate_pipeline  # noqa: E402
from orchestration.run_notebook import run_notebook  # noqa: E402
from export.export_parquet import export_all as export_parquet  # noqa: E402

default_args = {
    "owner": "data-eng",
    "retries": 1,
}

# notebooks de silver por dominio, en orden de dependencia (ver notebooks/README.md)
SILVER_NOTEBOOKS = {
    "university": [
        "01_students.ipynb", "02_professors.ipynb", "03_courses.ipynb",
        "04_semesters.ipynb", "05_enrollments.ipynb", "06_grades.ipynb",
    ],
    "billing": [
        "01_customers.ipynb", "02_products.ipynb", "03_subscriptions.ipynb",
        "04_invoices.ipynb", "05_invoice_items.ipynb", "06_payments.ipynb",
    ],
    "crm": [
        "01_accounts.ipynb", "02_contacts.ipynb", "03_leads.ipynb",
        "04_opportunities.ipynb", "05_opportunity_contacts.ipynb", "06_activities.ipynb",
    ],
}

# notebooks de gold, estrictamente secuenciales (ver docs/decisiones.md #9)
GOLD_NOTEBOOKS = [
    "01_dim_date.ipynb",
    "02_estrella_academica.ipynb",
    "03_estrella_billing.ipynb",
    "04_estrella_crm.ipynb",
    "05_kpi_views.ipynb",
]


with DAG(
    dag_id="crm_billing_universidad_pipeline",
    description="Pipeline de datos CRM + Billing + Universidad (bronze -> silver -> gold -> parquet)",
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

    with TaskGroup("build_silver") as build_silver:
        for domain, notebooks in SILVER_NOTEBOOKS.items():
            with TaskGroup(domain) as domain_group:
                previous_task = None
                for notebook in notebooks:
                    task = PythonOperator(
                        task_id=f"silver_{notebook.replace('.ipynb', '')}",
                        python_callable=run_notebook,
                        op_kwargs={"relative_path": f"{domain}/{notebook}"},
                    )
                    if previous_task is not None:
                        previous_task >> task
                    previous_task = task

    with TaskGroup("build_gold") as build_gold:
        previous_task = None
        for notebook in GOLD_NOTEBOOKS:
            task = PythonOperator(
                task_id=f"gold_{notebook.replace('.ipynb', '')}",
                python_callable=run_notebook,
                op_kwargs={"relative_path": f"gold/{notebook}"},
            )
            if previous_task is not None:
                previous_task >> task
            previous_task = task

    export_parquet_task = PythonOperator(
        task_id="export_parquet",
        python_callable=export_parquet,
    )

    validate_pipeline_task = PythonOperator(
        task_id="validate_pipeline",
        python_callable=validate_pipeline,
    )

    ingest_bronze >> validate_bronze >> build_silver >> build_gold >> export_parquet_task >> validate_pipeline_task

"""Reconciliacion end-to-end: bronze -> silver -> gold -> parquet.

Complementa a check_bronze_counts.py (que ya valida CSV -> bronze). Para las
tablas gold con relacion 1:1 con su tabla silver de origen, los conteos
deben coincidir exacto (full-refresh, sin perdida ni duplicacion). Bronze y
silver tambien se comparan contra su propio parquet ahora que las 3 capas
se exportan (ver docs/decisiones.md #25), no solo gold. El conteo de cada
archivo Parquet se lee del metadata (sin cargar el archivo completo).
"""
import os
import sys
from pathlib import Path

import pyarrow.parquet as pq

sys.path.append(str(Path(__file__).resolve().parents[1]))
from utils.db import get_psycopg2_connection  # noqa: E402
from export.export_parquet import RAW_TABLES  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
PARQUET_ROOT = Path(os.environ.get("PARQUET_ROOT", str(REPO_ROOT / "data" / "parquet")))

# tabla gold -> tabla silver de origen (1:1, mismo grano)
GOLD_TO_SILVER = {
    "dim_student": "university__students",
    "dim_professor": "university__professors",
    "dim_course": "university__courses",
    "dim_semester": "university__semesters",
    "fact_enrollment": "university__enrollments",
    "fact_grade": "university__grades",
    "dim_customer": "billing__customers",
    "dim_product": "billing__products",
    "fact_invoice": "billing__invoices",
    "fact_invoice_item": "billing__invoice_items",
    "fact_payment": "billing__payments",
    "fact_subscription": "billing__subscriptions",
    "dim_account": "crm__accounts",
    "dim_contact": "crm__contacts",
    "fact_opportunity": "crm__opportunities",
    "fact_activity": "crm__activities",
    "fact_lead": "crm__leads",
    "bridge_opportunity_contact": "crm__opportunity_contacts",
}


def _table_count(cur, schema: str, table: str) -> int:
    cur.execute(f"SELECT COUNT(*) FROM {schema}.{table};")
    return cur.fetchone()[0]


def _check_parquet(cur, schema: str, table: str, mismatches: list) -> int:
    """Compara el conteo de una tabla en Postgres contra su archivo parquet. Devuelve el conteo de Postgres."""
    db_count = _table_count(cur, schema, table)
    parquet_count = pq.read_metadata(PARQUET_ROOT / schema / f"{table}.parquet").num_rows
    status = "OK" if parquet_count == db_count else "MISMATCH"
    print(f"[{schema}->parquet] {table}: {schema}={db_count} parquet={parquet_count} [{status}]")
    if parquet_count != db_count:
        mismatches.append(f"{table} ({schema} parquet): {schema}={db_count} parquet={parquet_count}")
    return db_count


def validate() -> None:
    mismatches = []
    conn = get_psycopg2_connection()
    try:
        with conn.cursor() as cur:
            for table in RAW_TABLES:
                _check_parquet(cur, "bronze", table, mismatches)
                _check_parquet(cur, "silver", table, mismatches)

            for gold_table, silver_table in GOLD_TO_SILVER.items():
                silver_count = _table_count(cur, "silver", silver_table)
                gold_count = _table_count(cur, "gold", gold_table)
                status = "OK" if silver_count == gold_count else "MISMATCH"
                print(f"[silver->gold] {gold_table}: silver={silver_count} gold={gold_count} [{status}]")
                if silver_count != gold_count:
                    mismatches.append(f"{gold_table}: silver={silver_count} gold={gold_count}")

                _check_parquet(cur, "gold", gold_table, mismatches)

            # dim_date no viene de silver, se valida aparte contra su archivo parquet
            _check_parquet(cur, "gold", "dim_date", mismatches)
    finally:
        conn.close()

    if mismatches:
        raise RuntimeError("Reconciliacion del pipeline fallo: " + "; ".join(mismatches))


if __name__ == "__main__":
    validate()

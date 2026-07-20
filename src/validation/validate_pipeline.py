"""Reconciliacion end-to-end: silver -> gold -> parquet.

Complementa a check_bronze_counts.py (que ya valida CSV -> bronze). Para las
tablas gold con relacion 1:1 con su tabla silver de origen, los conteos
deben coincidir exacto (full-refresh, sin perdida ni duplicacion). El
conteo de cada archivo Parquet se lee del metadata (sin cargar el archivo
completo) y debe coincidir con su tabla gold de origen.
"""
import os
import sys
from pathlib import Path

import pyarrow.parquet as pq

sys.path.append(str(Path(__file__).resolve().parents[1]))
from utils.db import get_psycopg2_connection  # noqa: E402

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


def validate() -> None:
    mismatches = []
    conn = get_psycopg2_connection()
    try:
        with conn.cursor() as cur:
            for gold_table, silver_table in GOLD_TO_SILVER.items():
                silver_count = _table_count(cur, "silver", silver_table)
                gold_count = _table_count(cur, "gold", gold_table)
                status = "OK" if silver_count == gold_count else "MISMATCH"
                print(f"[silver->gold] {gold_table}: silver={silver_count} gold={gold_count} [{status}]")
                if silver_count != gold_count:
                    mismatches.append(f"{gold_table}: silver={silver_count} gold={gold_count}")

                parquet_path = PARQUET_ROOT / "gold" / f"{gold_table}.parquet"
                parquet_count = pq.read_metadata(parquet_path).num_rows
                status = "OK" if parquet_count == gold_count else "MISMATCH"
                print(f"[gold->parquet] {gold_table}: gold={gold_count} parquet={parquet_count} [{status}]")
                if parquet_count != gold_count:
                    mismatches.append(f"{gold_table} (parquet): gold={gold_count} parquet={parquet_count}")

            # dim_date no viene de silver, se valida aparte contra su archivo parquet
            gold_date_count = _table_count(cur, "gold", "dim_date")
            parquet_date_count = pq.read_metadata(PARQUET_ROOT / "gold" / "dim_date.parquet").num_rows
            status = "OK" if gold_date_count == parquet_date_count else "MISMATCH"
            print(f"[gold->parquet] dim_date: gold={gold_date_count} parquet={parquet_date_count} [{status}]")
            if gold_date_count != parquet_date_count:
                mismatches.append(f"dim_date (parquet): gold={gold_date_count} parquet={parquet_date_count}")
    finally:
        conn.close()

    if mismatches:
        raise RuntimeError("Reconciliacion del pipeline fallo: " + "; ".join(mismatches))


if __name__ == "__main__":
    validate()

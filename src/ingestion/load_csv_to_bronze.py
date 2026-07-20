import argparse
import io
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

sys.path.append(str(Path(__file__).resolve().parents[1]))
from utils.db import get_psycopg2_connection 

REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("DATA_ROOT", str(REPO_ROOT)))
MANIFEST_PATH = Path(os.environ.get("MANIFEST_PATH", str(DATA_ROOT / "manifest.json")))
SQL_BRONZE_ROOT = REPO_ROOT / "sql" / "bronze"

DOMAIN_TABLES = {
    "university": ["semesters", "professors", "students", "courses", "enrollments", "grades"],
    "billing": ["customers", "products", "subscriptions", "invoices", "invoice_items", "payments"],
    "crm": ["accounts", "contacts", "leads", "opportunities", "opportunity_contacts", "activities"],
}


def _load_manifest_columns(domain: str, table: str) -> list:
    with open(MANIFEST_PATH, encoding="utf-8") as f:
        manifest = json.load(f)
    return manifest["domains"][domain][table]["cols"]


def _ensure_bronze_tables(conn, domain: str) -> None:
    ddl_path = SQL_BRONZE_ROOT / f"{domain}.sql"
    with open(ddl_path, encoding="utf-8") as f:
        ddl = f.read()
    with conn.cursor() as cur:
        cur.execute(ddl)
    conn.commit()


def _load_table(conn, domain: str, table: str, dag_run_id: str) -> int:
    csv_path = DATA_ROOT / domain / f"{table}.csv"
    columns = _load_manifest_columns(domain, table)

    df = pd.read_csv(csv_path, dtype=str, keep_default_na=True)
    missing = set(columns) - set(df.columns)
    if missing:
        raise ValueError(f"{csv_path} no tiene las columnas esperadas: {sorted(missing)}")
    df = df[columns].copy()

    df["_source_file"] = f"{domain}/{table}.csv"
    df["_ingested_at"] = datetime.now(timezone.utc).isoformat()
    df["_dag_run_id"] = dag_run_id

    all_columns = columns + ["_source_file", "_ingested_at", "_dag_run_id"]
    buffer = io.StringIO()
    df.to_csv(buffer, index=False, header=False, na_rep="\\N")
    buffer.seek(0)

    bronze_table = f"bronze.{domain}__{table}"
    with conn.cursor() as cur:
        cur.execute(f"TRUNCATE TABLE {bronze_table};")
        cur.copy_expert(
            f"COPY {bronze_table} ({', '.join(all_columns)}) "
            f"FROM STDIN WITH (FORMAT csv, NULL '\\N')",
            buffer,
        )
    conn.commit()
    return len(df)


def load_domain(domain: str, dag_run_id: str = "manual") -> dict:
    if domain not in DOMAIN_TABLES:
        raise ValueError(f"Dominio desconocido: {domain}")

    conn = get_psycopg2_connection()
    try:
        _ensure_bronze_tables(conn, domain)
        counts = {}
        for table in DOMAIN_TABLES[domain]:
            counts[table] = _load_table(conn, domain, table, dag_run_id)
            print(f"[bronze] {domain}.{table}: {counts[table]} filas cargadas")
        return counts
    finally:
        conn.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("domain", choices=sorted(DOMAIN_TABLES))
    parser.add_argument("--dag-run-id", default="manual")
    args = parser.parse_args()
    load_domain(args.domain, args.dag_run_id)

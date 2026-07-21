"""Exporta bronze, silver y gold a Parquet, un archivo por tabla y por esquema.

Full-refresh igual que el resto del pipeline: sobreescribe el archivo en
cada corrida (no aplica versionado ni particionado -- el volumen de datos,
max 150k filas, no lo amerita). Ver docs/decisiones.md #25 -- bronze/silver
se agregaron ademas de gold para dejar evidencia Parquet de las 3 capas,
no solo de la capa de consumo final.
"""
import os
from pathlib import Path

import pandas as pd

import sys
sys.path.append(str(Path(__file__).resolve().parents[1]))
from utils.db import get_engine  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
PARQUET_ROOT = Path(os.environ.get("PARQUET_ROOT", str(REPO_ROOT / "data" / "parquet")))

# Mismas 18 tablas en bronze y silver (bronze = crudo tipado como TEXT,
# silver = limpio/tipado) -- un archivo por dominio en sql/{bronze,silver}/.
RAW_TABLES = [
    "university__semesters", "university__professors", "university__students",
    "university__courses", "university__enrollments", "university__grades",
    "billing__customers", "billing__products", "billing__subscriptions",
    "billing__invoices", "billing__invoice_items", "billing__payments",
    "crm__accounts", "crm__contacts", "crm__leads",
    "crm__opportunities", "crm__opportunity_contacts", "crm__activities",
]

GOLD_TABLES = [
    "dim_date",
    "dim_student", "dim_professor", "dim_course", "dim_semester",
    "fact_enrollment", "fact_grade",
    "dim_customer", "dim_product",
    "fact_invoice", "fact_invoice_item", "fact_payment", "fact_subscription",
    "dim_account", "dim_contact",
    "fact_opportunity", "fact_activity", "fact_lead", "bridge_opportunity_contact",
]

SCHEMA_TABLES = {
    "bronze": RAW_TABLES,
    "silver": RAW_TABLES,
    "gold": GOLD_TABLES,
}


def _export_schema(engine, schema: str, tables: list) -> dict:
    out_dir = PARQUET_ROOT / schema
    out_dir.mkdir(parents=True, exist_ok=True)

    counts = {}
    for table in tables:
        df = pd.read_sql(f"SELECT * FROM {schema}.{table}", engine)
        out_path = out_dir / f"{table}.parquet"
        df.to_parquet(out_path, engine="pyarrow", index=False)
        counts[table] = len(df)
        print(f"[parquet] {schema}.{table}: {len(df)} filas -> {out_path}")
    return counts


def export_all() -> dict:
    engine = get_engine()
    return {schema: _export_schema(engine, schema, tables) for schema, tables in SCHEMA_TABLES.items()}


if __name__ == "__main__":
    export_all()

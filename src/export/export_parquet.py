"""Exporta las 19 tablas de gold a Parquet, un archivo por tabla.

Full-refresh igual que el resto del pipeline: sobreescribe el archivo en
cada corrida (no aplica versionado ni particionado -- el volumen de datos,
max 150k filas, no lo amerita).
"""
import os
from pathlib import Path

import pandas as pd

import sys
sys.path.append(str(Path(__file__).resolve().parents[1]))
from utils.db import get_engine  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
PARQUET_ROOT = Path(os.environ.get("PARQUET_ROOT", str(REPO_ROOT / "data" / "parquet")))

GOLD_TABLES = [
    "dim_date",
    "dim_student", "dim_professor", "dim_course", "dim_semester",
    "fact_enrollment", "fact_grade",
    "dim_customer", "dim_product",
    "fact_invoice", "fact_invoice_item", "fact_payment", "fact_subscription",
    "dim_account", "dim_contact",
    "fact_opportunity", "fact_activity", "fact_lead", "bridge_opportunity_contact",
]


def export_all() -> dict:
    engine = get_engine()
    out_dir = PARQUET_ROOT / "gold"
    out_dir.mkdir(parents=True, exist_ok=True)

    counts = {}
    for table in GOLD_TABLES:
        df = pd.read_sql(f"SELECT * FROM gold.{table}", engine)
        out_path = out_dir / f"{table}.parquet"
        df.to_parquet(out_path, engine="pyarrow", index=False)
        counts[table] = len(df)
        print(f"[parquet] gold.{table}: {len(df)} filas -> {out_path}")
    return counts


if __name__ == "__main__":
    export_all()

"""Reconcilia el conteo de filas de bronze.* contra manifest.json.

Falla (RuntimeError) si algun conteo no coincide -- pensado como task de
Airflow que corre despues de la ingesta para detectar cargas incompletas.
"""
import json
import os
import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[1]))
from utils.db import get_psycopg2_connection  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("DATA_ROOT", str(REPO_ROOT)))
MANIFEST_PATH = Path(os.environ.get("MANIFEST_PATH", str(DATA_ROOT / "manifest.json")))


def check() -> None:
    with open(MANIFEST_PATH, encoding="utf-8") as f:
        manifest = json.load(f)

    conn = get_psycopg2_connection()
    mismatches = []
    try:
        with conn.cursor() as cur:
            for domain, tables in manifest["domains"].items():
                for table, meta in tables.items():
                    expected = meta["rows"]
                    bronze_table = f"bronze.{domain}__{table}"
                    cur.execute(f"SELECT COUNT(*) FROM {bronze_table};")
                    actual = cur.fetchone()[0]
                    status = "OK" if actual == expected else "MISMATCH"
                    print(f"[validate] {bronze_table}: esperado={expected} actual={actual} [{status}]")
                    if actual != expected:
                        mismatches.append((bronze_table, expected, actual))
    finally:
        conn.close()

    if mismatches:
        detail = "; ".join(f"{t}: esperado {e}, actual {a}" for t, e, a in mismatches)
        raise RuntimeError(f"Reconciliacion de bronze fallo: {detail}")


if __name__ == "__main__":
    check()

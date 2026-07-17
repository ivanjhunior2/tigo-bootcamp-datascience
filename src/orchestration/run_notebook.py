"""Ejecuta un notebook de Jupyter via nbconvert, igual que se hizo a mano
durante el desarrollo (`jupyter nbconvert --to notebook --execute --inplace`).

Silver (pandas) y gold (SQL) viven en notebooks, no en scripts .py -- este
helper deja que Airflow dispare exactamente esa misma logica sin duplicarla.
Si una celda falla, nbconvert devuelve codigo de salida != 0 y
subprocess.run(check=True) levanta CalledProcessError, que Airflow reporta
como fallo de tarea.
"""
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
NOTEBOOKS_ROOT = Path(os.environ.get("NOTEBOOKS_ROOT", str(REPO_ROOT / "notebooks")))


def run_notebook(relative_path: str) -> None:
    """relative_path: ej. 'university/01_students.ipynb'."""
    notebook_path = NOTEBOOKS_ROOT / relative_path
    subprocess.run(
        [
            "jupyter", "nbconvert",
            "--to", "notebook",
            "--execute", "--inplace",
            str(notebook_path),
        ],
        check=True,
    )

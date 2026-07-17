"""Ejercicio comparativo puntual: pandas vs PySpark sobre la misma agregacion.

Reimplementa "ingreso por categoria de producto" (ya calculado con SQL en
notebooks/gold/03_estrella_billing.ipynb y con pandas en
notebooks/analysis/01_insights.ipynb) leyendo los Parquet ya exportados
(Etapa 4), una vez con cada motor, midiendo tiempo y confirmando que el
resultado coincide. No reemplaza el pipeline real -- ver docs/decisiones.md
para la conclusion sobre cuando Spark si vale la pena.
"""
import os
import time
from pathlib import Path

import pandas as pd

PARQUET_ROOT = Path(os.environ.get("PARQUET_ROOT", "/app/data/parquet")) / "gold"


def run_pandas() -> tuple[pd.DataFrame, float]:
    start = time.perf_counter()

    invoice_items = pd.read_parquet(PARQUET_ROOT / "fact_invoice_item.parquet")
    products = pd.read_parquet(PARQUET_ROOT / "dim_product.parquet")

    merged = invoice_items.merge(products, on="product_id")
    result = (
        merged.groupby("category")["line_total"]
        .sum()
        .reset_index()
        .rename(columns={"line_total": "ingreso"})
        .sort_values("ingreso", ascending=False)
        .reset_index(drop=True)
    )

    elapsed = time.perf_counter() - start
    return result, elapsed


def run_spark() -> tuple[pd.DataFrame, float]:
    from pyspark.sql import SparkSession
    from pyspark.sql import functions as F

    start = time.perf_counter()

    spark = SparkSession.builder.appName("pandas-vs-spark-exercise").master("local[*]").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")

    invoice_items = spark.read.parquet(str(PARQUET_ROOT / "fact_invoice_item.parquet"))
    products = spark.read.parquet(str(PARQUET_ROOT / "dim_product.parquet"))

    result_spark = (
        invoice_items.join(products, on="product_id")
        .groupBy("category")
        .agg(F.sum("line_total").alias("ingreso"))
        .orderBy(F.desc("ingreso"))
    )
    result = result_spark.toPandas()

    elapsed = time.perf_counter() - start
    spark.stop()
    return result, elapsed


def main() -> None:
    print("=== pandas ===")
    pandas_result, pandas_time = run_pandas()
    print(pandas_result.to_string(index=False))
    print(f"Tiempo pandas: {pandas_time:.3f}s\n")

    print("=== PySpark ===")
    spark_result, spark_time = run_spark()
    print(spark_result.sort_values("ingreso", ascending=False).reset_index(drop=True).to_string(index=False))
    print(f"Tiempo PySpark (incluye arranque de JVM): {spark_time:.3f}s\n")

    coinciden = (
        pandas_result.set_index("category")["ingreso"]
        .round(2)
        .equals(spark_result.set_index("category")["ingreso"].round(2))
    )
    print("=== Comparacion ===")
    print(f"Resultados identicos: {coinciden}")
    print(f"pandas: {pandas_time:.3f}s  |  PySpark: {spark_time:.3f}s  |  diferencia: {spark_time - pandas_time:+.3f}s")
    if spark_time > pandas_time:
        print("pandas fue mas rapido -- esperado con este volumen de datos (PySpark paga overhead de arrancar la JVM).")
    else:
        print("PySpark fue mas rapido en esta corrida.")


if __name__ == "__main__":
    main()

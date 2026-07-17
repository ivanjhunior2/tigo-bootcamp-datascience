FROM python:3.11-slim-bookworm

# Bookworm (Debian 12) fijo a proposito: python:3.11-slim trackea "trixie" y
# ya no tiene el paquete openjdk-17. PySpark 3.5.x soporta Java 8/11/17
# oficialmente, asi que fijamos la base donde ese paquete existe en vez de
# saltar a openjdk-21 (no confirmado como soportado por esta version de Spark).
# PySpark necesita una JVM. Imagen separada de jupyter/airflow a proposito:
# esto es un ejercicio puntual, no vale la pena meterle un JVM a una imagen
# que se reconstruye seguido (ver docs/decisiones.md).
RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

RUN pip install --no-cache-dir \
    pyspark==3.5.3 \
    pandas==2.2.3 \
    pyarrow==17.0.0

WORKDIR /app
CMD ["python", "src/spark_exercise/compare_pandas_spark.py"]

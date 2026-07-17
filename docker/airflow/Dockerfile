FROM apache/airflow:2.10.4-python3.11

# SQLAlchemy fijado a la version que ya trae la imagen base de Airflow
# 2.10.4 (verificado: 1.4.54). Sin este pin, pip resuelve una version mas
# nueva de SQLAlchemy (por requirements.txt, que no la fija) que rompe el
# auth manager interno de Airflow -- ej. "airflow users create" deja de
# existir. Antes se resolvia esto con el constraints file oficial de
# Airflow via URL, pero eso depende de poder llegar a
# raw.githubusercontent.com en build time; fijar la version a mano evita
# esa dependencia de red.
COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt nbconvert ipykernel "SQLAlchemy==1.4.54" \
    && python -m ipykernel install --user --name python3

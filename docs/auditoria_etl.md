# Auditoría del ETL (bronze → silver → gold → Airflow)

Verificación del pipeline ya implementado contra lo documentado en [`decisiones.md`](./decisiones.md)
y [`calidad_datos.md`](./calidad_datos.md), y evaluación contra buenas prácticas de las skills
`analytics-engineer` y `ml-pipeline-workflow`. Revisión de código (SQL, DAG, scripts, notebooks) — no
se levantó Docker ni se consultó Postgres en vivo, así que no reemplaza una corrida real, solo
confirma que el código hace lo que dice hacer.

## Confirmado correcto (sin discrepancias)

- **Bronze**: `sql/bronze/*.sql` — todas las columnas `TEXT` + `_source_file`, `_ingested_at`,
  `_dag_run_id`. `src/ingestion/load_csv_to_bronze.py` hace `TRUNCATE` + `COPY` por tabla en cada
  corrida (full-refresh idempotente, tal como #4 de decisiones.md).
- **Silver** (muestreado: `billing/02_products`, `billing/03_subscriptions`, `crm/04_opportunities`,
  `crm/06_activities`, `billing/01_customers`, `university/03_courses`) — las seis reglas de calidad
  documentadas están implementadas exactamente como se describen: `active` casteado a boolean;
  `_end_date_invalidated` + `end_date` anulado solo en las 783/15,000 filas afectadas (sin anular por
  la observación de "100% poblado por status", que fue investigada y descartada como error); flag
  `_close_date_before_created` en 1,029/3,000 filas sin descartar ni anular la fila; `contact_id` /
  `opportunity_id` / `external_ref` se mantienen nullable tal como diseñado; `department` de curso vs.
  profesor no se reconcilia. Todas usan `df.to_sql(..., if_exists="replace")`.
- **Gold** (`sql/gold/*.sql`): llaves naturales en todas las dimensiones, `TRUNCATE ... CASCADE` en
  las 18 tablas, `is_passing = avg_score >= 60` en la estrella académica, `sales_cycle_days` anulado
  exactamente cuando `_close_date_before_created` es verdadero, `dim_customer.student_id` como FK
  cross-domain hacia `dim_student`, `fact_lead` sin FK (mart independiente). El notebook
  `02_estrella_academica.ipynb` (revisado completo) solo ejecuta el SQL y corre queries de
  verificación — no hay lógica de transformación oculta fuera de `sql/gold/`.
- **Airflow**: un solo DAG, `TaskGroups` por fase (`ingest_bronze` → `build_silver` → `build_gold`
  01→04 estricto → `export_parquet` → `validate_pipeline`), coincide con la cadena de dependencias
  documentada. `run_notebook.py` propaga fallos de `nbconvert` a Airflow vía `subprocess.run(check=True)`.
- **Export/validación**: `export_parquet.py` exporta 18 Parquet sin particionar, sobreescritos cada
  corrida. `check_bronze_counts.py` reconcilia bronze vs. `manifest.json`; `validate_pipeline.py`
  reconcilia conteos silver → gold → parquet en las 18 tablas.

**Conclusión: lo que ya está aplicado es correcto.** Cada afirmación de `decisiones.md` y
`calidad_datos.md` se verificó contra el código real (DDL, SQL, DAG, scripts, 7 notebooks) sin
encontrar ninguna discrepancia.

## Oportunidades de mejora concretas (no bloqueantes, priorizadas)

Evaluadas con la óptica de "testing por modelo" (`analytics-engineer/references/testing_guide.md`) y
de validación/observabilidad de pipeline (`ml-pipeline-workflow`). Ninguna implica adoptar dbt ni
reescribir notebooks como scripts — esas alternativas ya fueron evaluadas y descartadas con
justificación en decisiones.md #7 y #13.

1. **Sin constraint/test automático para `line_total = quantity * unit_price`** en
   `gold.fact_invoice_item` (`sql/gold/billing.sql`) — se verificó una sola vez, manualmente, en
   `notebooks/billing/05_invoice_items.ipynb`. Un futuro batch con el cálculo roto pasaría
   silenciosamente porque ni `check_bronze_counts.py` ni `validate_pipeline.py` lo re-chequean.
2. **`validate_pipeline.py` solo reconcilia conteos de filas**, no valida explícitamente FKs
   huérfanas ni PKs duplicadas como paso propio (hoy se evita porque Postgres las rechaza al
   insertar, pero no hay un reporte independiente de integridad referencial).
3. **Sin chequeo tipo `accepted_values`** sobre columnas enum (`stage`, `status`, `type`,
   `category`) en `sql/gold/*.sql` ni en `src/validation/`. Un valor nuevo no previsto desde origen
   pasaría sin detectarse a la lógica de `is_won`/`is_lost`/`is_open` en `crm.sql`.
4. **`default_args` del DAG solo define `retries: 1`**, sin `retry_delay` ni
   `on_failure_callback`/alertas (email, Slack) — un fallo hoy solo es visible en la UI de Airflow.
5. **Sin un diccionario de columnas por tabla gold** (grano, PK, FK) en un artefacto único legible
   por máquina — razonable dado que no se usa dbt, pero hoy esa información vive repartida entre
   comentarios SQL y los notebooks.

Ninguno de estos puntos es un defecto del trabajo ya hecho — son controles adicionales de
robustez/observabilidad que se podrían sumar si se quiere blindar el pipeline contra regresiones
futuras, no correcciones a algo que esté mal hoy.

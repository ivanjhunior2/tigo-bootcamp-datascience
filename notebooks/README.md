# Notebooks — índice de progreso (bronze → silver)

Un notebook por tabla, organizado en subcarpetas por dominio. Cada uno sigue el mismo patrón: explorar `bronze.<tabla>` con pandas → decidir reglas de limpieza → limpiar → validar → escribir en `silver.<tabla>` con `df.to_sql(..., if_exists="replace")` → verificar en Postgres.

**Orden de ejecución:** dentro de cada dominio, correr los notebooks en el orden numerado — las tablas con FK (ej. `courses` → `professors`, `enrollments` → `students`/`courses`/`semesters`) leen de `silver` las tablas de las que dependen, así que el padre tiene que estar cargado primero.

## university ✅ completo

| # | Tabla | Notebook | Filas | FKs a | Notas |
|---|---|---|---|---|---|
| 01 | students | [`university/01_students.ipynb`](university/01_students.ipynb) | 5,000 | — | tabla de referencia del patrón |
| 02 | professors | [`university/02_professors.ipynb`](university/02_professors.ipynb) | 200 | — | |
| 03 | courses | [`university/03_courses.ipynb`](university/03_courses.ipynb) | 300 | professors | confirma que `department` de curso y profesor coinciden solo ~12% (azar, no error) |
| 04 | semesters | [`university/04_semesters.ipynb`](university/04_semesters.ipynb) | 8 | — | |
| 05 | enrollments | [`university/05_enrollments.ipynb`](university/05_enrollments.ipynb) | 25,000 | students, courses, semesters | |
| 06 | grades | [`university/06_grades.ipynb`](university/06_grades.ipynb) | 60,000 | enrollments | |

## billing ✅ completo

| # | Tabla | Notebook | Filas | FKs a | Notas |
|---|---|---|---|---|---|
| 01 | customers | [`billing/01_customers.ipynb`](billing/01_customers.ipynb) | 10,000 | students (opcional, `external_ref`) | FK opcional, ~50% nulo por diseño |
| 02 | products | [`billing/02_products.ipynb`](billing/02_products.ipynb) | 200 | — | `active` texto `True`/`False` → `boolean` real |
| 03 | subscriptions | [`billing/03_subscriptions.ipynb`](billing/03_subscriptions.ipynb) | 15,000 | customers, products | 783 filas (5.2%) con `start_date > end_date` → `end_date` anulado + flag `_end_date_invalidated` |
| 04 | invoices | [`billing/04_invoices.ipynb`](billing/04_invoices.ipynb) | 50,000 | customers | — |
| 05 | invoice_items | [`billing/05_invoice_items.ipynb`](billing/05_invoice_items.ipynb) | 150,000 | invoices, products | `line_total = quantity * unit_price` verificado consistente |
| 06 | payments | [`billing/06_payments.ipynb`](billing/06_payments.ipynb) | 80,000 | invoices | — |

## crm ✅ completo

| # | Tabla | Notebook | Filas | FKs a | Notas |
|---|---|---|---|---|---|
| 01 | accounts | [`crm/01_accounts.ipynb`](crm/01_accounts.ipynb) | 5,000 | — | |
| 02 | contacts | [`crm/02_contacts.ipynb`](crm/02_contacts.ipynb) | 15,000 | accounts | |
| 03 | leads | [`crm/03_leads.ipynb`](crm/03_leads.ipynb) | 2,000 | — | tabla independiente, sin FK |
| 04 | opportunities | [`crm/04_opportunities.ipynb`](crm/04_opportunities.ipynb) | 3,000 | accounts | `close_date < created_at` uniforme 31-37% en todos los stages → flag `_close_date_before_created`, sin anular datos |
| 05 | opportunity_contacts | [`crm/05_opportunity_contacts.ipynb`](crm/05_opportunity_contacts.ipynb) | 6,000 | opportunities, contacts | tabla puente N:N |
| 06 | activities | [`crm/06_activities.ipynb`](crm/06_activities.ipynb) | 20,000 | contacts, opportunities (ambos opcionales) | FKs nullable mantenidas tal cual |

## ✅ Silver completo: 18/18 tablas cargadas y verificadas

## gold ✅ completo — 3 estrellas en SQL puro

A diferencia de silver (pandas), acá la transformación es **SQL puro** (`sql/gold/*.sql`) — el notebook solo lee el archivo, lo ejecuta contra Postgres y muestra los resultados con pandas. Gold sí tiene foreign keys reales entre tablas (a diferencia de bronze/silver), así que **el orden de ejecución es obligatorio**: `01` → `02` → `03` → `04` (ver [`docs/decisiones.md`](../docs/decisiones.md) #9 — `TRUNCATE ... CASCADE` y por qué importa el orden).

| # | Notebook | SQL | Contenido | FKs a |
|---|---|---|---|---|
| 01 | [`gold/01_dim_date.ipynb`](gold/01_dim_date.ipynb) | `sql/gold/00_dim_date.sql` | `dim_date` (2015–2028), conformada, compartida por las 3 estrellas | — |
| 02 | [`gold/02_estrella_academica.ipynb`](gold/02_estrella_academica.ipynb) | `sql/gold/university.sql` | `dim_student`, `dim_professor`, `dim_course`, `dim_semester`, `fact_enrollment` (con rollup de notas), `fact_grade` | dim_date |
| 03 | [`gold/03_estrella_billing.ipynb`](gold/03_estrella_billing.ipynb) | `sql/gold/billing.sql` | `dim_customer` (bridge `student_id`), `dim_product`, `fact_invoice`, `fact_invoice_item`, `fact_payment`, `fact_subscription` | dim_date, **dim_student** (cross-domain) |
| 04 | [`gold/04_estrella_crm.ipynb`](gold/04_estrella_crm.ipynb) | `sql/gold/crm.sql` | `dim_account`, `dim_contact`, `fact_opportunity`, `fact_activity`, `fact_lead` (mart independiente, sin FK) | dim_date |

Cada notebook incluye, además de la carga y verificación de conteos, 1-2 queries de ejemplo que responden una pregunta de negocio real (ingreso por producto, churn por segmento, tasa de cierre por industria, rendimiento académico por departamento, conversión de leads por canal, etc.) — prueba de que la estrella sirve para analizar, no solo que carga bien.

**18 tablas gold** (9 dim + 9 fact), todas verificadas 1:1 contra su tabla `silver` de origen.

## Automatización (Airflow) + Parquet ✅ completo

El DAG `crm_billing_universidad_pipeline` corre las 4 etapas de punta a punta (bronze → silver → gold → export Parquet → validación), disparando los mismos notebooks vía `nbconvert` (ver `docs/decisiones.md` #13). Probado 2 veces completo, mismos resultados ambas veces (idempotencia confirmada). Los 18 `.parquet` quedan en `data/parquet/gold/`.

## analysis ✅ completo — insights de negocio

| Notebook | Contenido |
|---|---|
| [`analysis/01_insights.ipynb`](analysis/01_insights.ipynb) | Consolida las preguntas de negocio de las 3 estrellas con gráficos (paleta validada colorblind-safe) y hallazgos en texto con cifras exactas: rendimiento académico por departamento, deserción por semestre, churn por segmento, DSO por método de pago, win rate por industria, conversión de leads por canal, y el cruce cross-domain estudiante↔cliente. Termina con un resumen ejecutivo de 6 puntos, insumo directo para la presentación. |

## ml ✅ completo — stretch goal, fuera del stack obligatorio del README

| Notebook | Contenido |
|---|---|
| [`ml/01_churn_model.ipynb`](ml/01_churn_model.ipynb) | `RandomForestClassifier` sobre `fact_subscription` para predecir `is_cancelled`. Documenta qué features se excluyen por fuga de datos (`status`, `is_active`) y por qué. **Resultado: ROC-AUC ≈ 0.51** (sin señal real en los datos sintéticos) — documentado como hallazgo honesto, no forzado. Persiste `models/churn_model.joblib`. |
| [`ml/02_win_model.ipynb`](ml/02_win_model.ipynb) | Igual patrón para `fact_opportunity` → `is_won`. Excluye `stage`, `is_lost`/`is_open`, `sales_cycle_days` (fuga de datos). **ROC-AUC ≈ 0.51**, mismo hallazgo. Persiste `models/win_model.joblib`. |

Ver `docs/decisiones.md` #15 para el razonamiento completo de por qué no se fuerza el número.

## Streamlit ✅ completo — interfaz de predicción en vivo

`app/streamlit_app.py` (servicio Docker aparte, `localhost:8501`) carga los `.joblib` de `ml/` y expone un formulario por modelo (churn / win) que corre `predict_proba()` con lo que ingresa el usuario. No toca Postgres — ver `docs/decisiones.md` #16.

## Spark vs pandas ✅ completo — ejercicio comparativo puntual

`docker compose run --rm spark-exercise` corre `src/spark_exercise/compare_pandas_spark.py`: recalcula "ingreso por categoría de producto" leyendo los Parquet de `data/parquet/gold/`, una vez con pandas y otra con PySpark, comparando resultado y tiempo. No reemplaza el pipeline real — ver `docs/decisiones.md` #17.

## Después de todo esto

Queda pendiente la Etapa 6 del plan original (presentación ejecutiva en Power BI), pospuesta a pedido del usuario para priorizar estos stretch goals.

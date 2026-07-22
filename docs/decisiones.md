# Decisiones de diseño

Registro de decisiones no obvias, con alternativas descartadas y motivo.

---

## 1. Ubicación de los CSV crudos

**Decisión:** los CSV se dejan en `university/`, `billing/`, `crm/` en la raíz del repo, tal como se entregaron. No se mueven a `data/raw/` pese a que esa es la estructura sugerida en el README.

**Alternativa descartada:** copiar/mover los archivos a `data/raw/{university,billing,crm}/`.

**Por qué:** el propio README indica que los CSV reales ya están en esas carpetas dentro del mismo directorio del proyecto, y `manifest.json` los referencia por nombre de dominio, no por una ruta `data/raw/`. Moverlos no aporta nada y agrega una copia redundante a mantener sincronizada. Se montan de solo lectura (`:ro`) dentro de los contenedores.

---

## 2. Dos bases de datos en la misma instancia de Postgres

**Decisión:** un único contenedor de Postgres con dos bases de datos: `warehouse` (schemas `bronze`, `silver`, `gold`) y `airflow` (metadata de orquestación).

**Alternativa descartada:** una sola base de datos compartida, o dos contenedores de Postgres separados.

**Por qué:** mezclar metadata de Airflow (DAG runs, logs, conexiones) con las tablas de negocio en el mismo namespace dificulta razonar sobre el modelo de datos y arriesga colisiones de nombres. Levantar un segundo contenedor de Postgres es innecesario para este volumen de datos (el archivo más grande es 150k filas) y complica el docker-compose sin beneficio real.

---

## 3. Bronze: todas las columnas como `TEXT`

**Decisión:** las tablas bronze no tipan ninguna columna (todo `TEXT`), solo agregan metadata de ingesta (`_source_file`, `_ingested_at`, `_dag_run_id`).

**Por qué:** bronze debe preservar el dato crudo sin pérdida ni interpretación. Si se tipara en bronze (por ejemplo `INTEGER` o `DATE`) y un valor no calzara con el tipo esperado, la carga fallaría o silenciosamente perdería datos antes de poder auditarlos. Cargar todo como texto garantiza que cualquier problema de formato se detecta y trata explícitamente en silver, con el dato original todavía disponible para comparar.

---

## 4. Ingesta full-refresh (TRUNCATE + reload) en vez de incremental

**Decisión:** cada corrida del DAG trunca y recarga completamente las tablas bronze desde los CSV fuente.

**Alternativa descartada:** carga incremental basada en fecha de ingesta o upsert por clave primaria.

**Por qué:** los CSV fuente son estáticos (no cambian entre corridas), así que no hay nada que capturar incrementalmente. Un full-refresh es más simple, evita lógica de deduplicación, y cumple el requisito de idempotencia ("el pipeline debe poder re-ejecutarse sin duplicar datos") de la forma más directa: cada corrida es reproducible byte a byte.

---

## 5. Un solo DAG que crece por fases, en vez de un DAG por capa

**Decisión:** `dags/crm_billing_universidad_pipeline.py` es el único DAG del proyecto. Cada nueva fase (silver, gold, export, validación) se agrega como un `TaskGroup` nuevo sobre este mismo DAG, no como un DAG independiente.

**Por qué:** el pipeline es un flujo único de extremo a extremo con dependencias claras entre capas (silver depende de bronze, gold depende de silver, etc.). Repartirlo en varios DAGs obligaría a usar sensores o triggers externos para coordinar el orden, agregando complejidad sin necesidad real en este proyecto.

---

## 6. Hallazgos de calidad de datos que se tratan como diseño, no como defectos

Ver detalle en [`calidad_datos.md`](./calidad_datos.md). Dos casos se documentan aquí porque afectan directamente el modelo:

- `billing.customers.external_ref` vacío en el 50% de las filas: es solapamiento parcial intencional con `university.students` (no todo cliente de facturación es un estudiante). Se modela como relación opcional, no se filtra ni se completa.
- `university.courses.department` coincide con el departamento del profesor asignado en solo ~12% de los casos (36/300) — consistente con asignación aleatoria entre 8 categorías, no con una relación real. Se tratan como dos atributos independientes (departamento del curso vs. departamento de origen del profesor), sin intentar reconciliarlos.

---

## 7. Silver con pandas en Jupyter, Gold con SQL puro

**Decisión:** la limpieza de silver (18 tablas) se hizo con pandas dentro de notebooks de Jupyter — no con SQL. El modelado de gold (estrellas dimensionales) se hace con SQL puro en `sql/gold/*.sql`, ejecutado desde un notebook que solo corre el archivo y muestra resultados con pandas.

**Por qué:** decisión explícita del usuario para poder revisar y entender cada paso de la limpieza de forma interactiva en Jupyter, tabla por tabla, antes de escribir el modelo final. El requisito de SQL del stack obligatorio del README queda cubierto igual — solo que concentrado en la capa donde más aporta (el modelado dimensional), no en la limpieza.

---

## 8. Gold: llaves naturales, no surrogate keys

**Decisión:** los PK de las dimensiones en `gold` son los IDs que ya traen los datos (`student_id`, `customer_id`, `account_id`, etc.), no enteros autogenerados.

**Alternativa descartada:** generar surrogate keys (`SERIAL`/`IDENTITY`) para cada dimensión, como en un modelo Kimball clásico.

**Por qué:** surrogate keys existen principalmente para trackear historia (SCD tipo 2) o para desacoplarse de cambios en la llave de origen. Este proyecto es un warehouse de refresh completo (`TRUNCATE` + reload en cada corrida, sin versionar cambios históricos), así que agregar una capa de mapeo natural→surrogate sería complejidad sin beneficio real. Las llaves de origen ya son estables y únicas.

---

## 9. `TRUNCATE ... CASCADE` en gold, y orden de ejecución fijo

**Decisión:** todas las tablas de `gold` se recargan con `TRUNCATE ... CASCADE` (no `TRUNCATE` simple), y los 4 notebooks/scripts de gold deben correr siempre en el mismo orden: `dim_date` → `university` → `billing` → `crm`.

**Por qué:** a diferencia de bronze (sin FKs) y silver (sin FKs entre tablas), gold sí tiene foreign keys reales entre dimensiones y hechos — incluyendo referencias cruzadas entre archivos (`gold.dim_customer.student_id → gold.dim_student`). Postgres no permite `TRUNCATE` simple sobre una tabla referenciada por otra con datos; `CASCADE` lo resuelve, a costa de que **volver a correr un notebook temprano (ej. `01_dim_date`) vacía en cascada las tablas de las estrellas posteriores** hasta que esos notebooks se vuelvan a correr también. Es el mismo trade-off que un rebuild completo de warehouse: reproducible, pero hay que respetar el orden.

---

## 10. Umbral de aprobación asumido (60 sobre 100)

**Decisión:** en `gold.fact_enrollment`, `is_passing = true` cuando el promedio ponderado de notas (`avg_score`) es ≥ 60.

**Por qué:** el dataset no trae un umbral de aprobación explícito. 60/100 es un estándar razonable y común, pero es una **asunción del equipo**, no un dato de la fuente — queda documentada acá para que sea auditable y cuestionable si el negocio define otro criterio.

---

## 11. `sales_cycle_days` anulado cuando `close_date < created_at`

**Decisión:** en `gold.fact_opportunity`, `sales_cycle_days` (días entre creación y cierre de una oportunidad) se deja `NULL` cuando `_close_date_before_created = true` (~34% de las filas, ver `calidad_datos.md`), en vez de calcular un número negativo.

**Por qué:** un ciclo de venta negativo no es una métrica de negocio válida — es evidencia de que `close_date` en esas filas es una fecha objetivo/estimada anterior a la creación del registro, no la fecha real de cierre. Se prefiere `NULL` (dato faltante honesto) a un número que un análisis desprevenido podría promediar sin darse cuenta del problema. El flag `_close_date_before_created` se mantiene en la tabla para que sea auditable.

---

## 12. `crm.leads` fuera de la estrella comercial

**Decisión:** `gold.fact_lead` es un mart independiente, sin foreign key hacia `dim_account`, `dim_contact` ni `fact_opportunity`.

**Por qué:** `leads.csv` no tiene ninguna columna `*_id` que lo conecte con `accounts`/`opportunities` en la fuente — cualquier cruce (por email o nombre, por ejemplo) sería una inferencia no garantizada por el diseño de los datos, y el README es explícito en que las relaciones se infieren solo de columnas `*_id` compartidas. Forzar ese join generaría una falsa sensación de trazabilidad (ej. "este lead se convirtió en esta oportunidad ganada") que los datos no respaldan.

---

## 13. Airflow ejecuta los notebooks de silver/gold vía `nbconvert`, no los reescribe como scripts

**Decisión:** las tareas de `build_silver` y `build_gold` en el DAG son `PythonOperator` que corren `jupyter nbconvert --to notebook --execute --inplace <notebook>` (helper en `src/orchestration/run_notebook.py`), en vez de reimplementar la limpieza (pandas) y el modelado (SQL) como scripts `.py` separados.

**Alternativa descartada:** extraer la lógica de cada notebook a funciones Python puras en `src/`, importadas tanto por el notebook (para revisión visual) como por Airflow (para producción).

**Por qué:** los 18 notebooks de silver y los 4 de gold ya son la fuente de verdad, revisados y verificados manualmente dos veces cada uno. Duplicar esa lógica en scripts paralelos crea dos lugares que mantener sincronizados — con alto riesgo de que diverjan silenciosamente. Ejecutar el notebook tal cual desde Airflow garantiza que lo que corre en producción es exactamente lo mismo que se revisó en Jupyter. El costo es una imagen de Airflow más pesada (`nbconvert` + `ipykernel`) y un poco más de latencia por tarea — aceptable para este volumen de datos.

---

## 14. Parquet: un archivo por tabla, sin particionar

**Decisión:** `src/export/export_parquet.py` exporta cada una de las 18 tablas de `gold` a un único archivo `data/parquet/gold/<tabla>.parquet`, sobreescrito en cada corrida.

**Por qué:** particionar por fecha u otra columna es una optimización para volúmenes de datos mucho mayores (millones de filas, lectura distribuida). Acá la tabla más grande es 150k filas — particionar agregaría complejidad (múltiples archivos, lógica de reconciliación por partición) sin ningún beneficio de performance real.

---

## 15. Modelos ML: se documenta un resultado negativo (AUC ≈ 0.51) en vez de forzarlo

**Decisión:** los notebooks `notebooks/ml/01_churn_model.ipynb` y `02_win_model.ipynb` entrenan `RandomForestClassifier` para predecir `is_cancelled` e `is_won` respectivamente. Ambos dan **ROC-AUC ≈ 0.51** — prácticamente igual a adivinar al azar. No se ajustaron hiperparámetros ni se agregaron features adicionales para "mejorar" ese número.

**Por qué:** el objetivo de un modelo es reflejar la relación real (o su ausencia) entre features y resultado, no maximizar una métrica a cualquier costo. La falta de señal es consistente con lo ya observado en `notebooks/analysis/01_insights.ipynb` — el churn variaba solo 2 puntos entre segmentos, el win rate 12 puntos entre industrias con muestras chicas por grupo — indicando que el generador sintético de datos (`manifest.json`, `seed: 42`) probablemente asignó estos resultados de forma mayormente independiente de los atributos disponibles. Forzar un AUC más alto vía *tuning* agresivo sería sobreajustar al ruido del set de test, no capturar una relación real. Se documenta el hallazgo tal cual, con el razonamiento de por qué se descartaron `status`/`stage`/`sales_cycle_days` como features (fuga de datos trivial — ver los notebooks).

## 16. Streamlit no toca la base de datos, solo consume los `.joblib`

**Decisión:** `app/streamlit_app.py` corre como servicio independiente, sin conexión a Postgres — carga `models/*.joblib` (pipeline + opciones válidas de cada feature, guardadas al entrenar) y arma el formulario a partir de esos metadatos.

**Por qué:** el caso de uso es "predicción en vivo con un modelo ya entrenado", no explorar datos — no hay necesidad real de una dependencia a la base de datos, y evitarla simplifica el servicio (menos configuración, arranca más rápido, no depende de que Postgres esté sano).

## 17. Spark: imagen separada, ejercicio puntual, no reemplaza el pipeline

**Decisión:** `docker/spark/Dockerfile` (con JVM vía `openjdk-17-jre-headless`, fijado sobre `python:3.11-slim-bookworm` porque la tag `slim` sin versión ya trackea Debian trixie, que no tiene ese paquete) es una imagen aparte, con un servicio `spark-exercise` marcado con `profiles: [tools]` para que no se levante con `docker compose up -d` — se corre a demanda con `docker compose run --rm spark-exercise`.

**Por qué:** el pipeline real (silver en pandas, gold en SQL) ya está construido, probado y automatizado en Airflow — reemplazarlo por Spark sin una necesidad real de escala sería una migración de arquitectura injustificada. El ejercicio (`src/spark_exercise/compare_pandas_spark.py`) reimplementa una sola agregación ya validada (ingreso por categoría de producto) leyendo los mismos Parquet exportados, con pandas y con PySpark, midiendo tiempo de cada uno. Con este volumen de datos (150k filas máximo), pandas es más rápido — PySpark paga el costo fijo de arrancar una JVM que no se amortiza hasta volúmenes mucho mayores o procesamiento distribuido real. El ejercicio demuestra la capacidad de usar la herramienta, no reemplaza una decisión de arquitectura ya tomada y validada.

## 18. `gold.bridge_opportunity_contact`: se agrega una tabla puente que faltaba en la estrella comercial

**Decisión:** se agregó `gold.bridge_opportunity_contact` (`sql/gold/crm.sql`) para modelar la relación N:N entre `fact_opportunity` y `dim_contact` que ya existía en `silver.crm__opportunity_contacts` (6,000 filas) pero no se había llevado a gold. Grano = 1 fila por par `(opportunity_id, contact_id)`, con `role` como atributo y PK compuesta. `src/export/export_parquet.py` y `src/validation/validate_pipeline.py` se actualizaron para incluirla (pasa de 18 a 19 tablas gold).

**Por qué:** una auditoría del modelo dimensional (`docs/auditoria_etl.md`) encontró que, a diferencia de `fact_lead` (que deliberadamente no tiene FK porque la fuente no la provee — ver decisión #12), `opportunity_contacts` sí tiene ambas FKs en la fuente y se estaba perdiendo sin razón documentada: sin esta tabla no había forma de responder "qué contactos participaron en este deal" ni "tuvo un `decision_maker` identificado". Es el patrón estándar de Kimball para relaciones muchos-a-muchos entre un hecho y una dimensión (bridge table). Verificado en Postgres real: 6,000/6,000 filas, ambas FKs válidas, sin colisión de PK compuesta. Se agregó también una pregunta de negocio de ejemplo en `notebooks/gold/04_estrella_crm.ipynb` (win rate con vs. sin `decision_maker` identificado) — resultado: 60.7% vs. 61.3%, sin diferencia real, consistente con el patrón de "sin señal" ya documentado en la decisión #15.

---

## 19. Capa de vistas KPI en `gold` — la regla de negocio vive en un solo lugar

**Decisión:** `sql/gold/kpi_views.sql` agrega 6 vistas (`gold.vw_win_rate_by_industry`, `vw_churn_by_segment`, `vw_academic_performance_by_department`, `vw_lead_conversion_by_source`, `vw_dso_by_payment_method`, `vw_retention_by_student_status`) que encapsulan exactamente las queries de negocio ya validadas en `notebooks/analysis/01_insights.ipynb`. Se ejecutan desde `notebooks/gold/05_kpi_views.ipynb`, agregado como quinto paso del `build_gold` TaskGroup en el DAG.

**Por qué:** armando el dashboard en Power BI apareció un bug real — la medida DAX de "win rate por industria" dividía por *todas* las oportunidades (incluidas las que seguían abiertas) en vez de solo las cerradas, aplanando la señal real (todas las industrias se veían iguales ~16% en vez de 57%-69%). La causa raíz no fue un error de tipeo: la regla de negocio ("solo cuentan las oportunidades cerradas") solo estaba documentada en el SQL de `04_estrella_crm.ipynb`, y se perdió al reimplementarla en DAX. Centralizar la regla en una vista de `gold` significa que cualquier herramienta de BI (Power BI, Superset, o lo que sea) lee un número ya correcto, en vez de tener que acertar la misma lógica de negocio cada una por su cuenta — elimina esta clase entera de bug hacia adelante.

---

## 20. `fact_invoice_item`: `customer_id`/`issued_date_id` denormalizados desde `fact_invoice`

**Decisión:** `gold.fact_invoice_item` ahora incluye `customer_id` y `issued_date_id` directo (copiados de `fact_invoice` al momento de la carga), además de `invoice_id` y `product_id`. Antes solo tenía `invoice_id`+`product_id`, y había que saltar por `fact_invoice` para llegar a cliente o fecha.

**Por qué:** al comparar el modelo contra una propuesta externa (`modelo_estrella_diagramas.md`), esa era la diferencia real más señalable — sin esos dos campos directos, cualquier análisis "ingreso por cliente" o "ingreso por mes" a nivel de línea de factura obligaba a un join extra contra `fact_invoice` (una conexión fact-a-fact, que es justo lo que hacía que el diagrama de billing en DBeaver no se viera como una estrella limpia). Denormalizar estos dos campos es una práctica estándar en Kimball para hechos de grano fino que cuelgan de un hecho de grano más grueso — se paga con un poco de redundancia (el dato ya existe en `fact_invoice`) a cambio de consultas más simples y de una forma de estrella más clara. Migración aplicada: se recreó la tabla completa (`DROP` + recarga), verificado que las 150,000 filas tienen `customer_id`/`issued_date_id` consistentes con su `fact_invoice` padre (0 inconsistencias).

**Nota:** no se adoptó el resto de la propuesta externa (`dim_lead_source` conectada a `fact_opportunity`) porque asumía una relación que los datos fuente no respaldan — ver decisión #12.

---

## 21. Vistas KPI reorganizadas en 5 archivos: 3 individuales + 2 grupales

**Decisión:** `sql/gold/kpi_views.sql` (6 vistas en un solo archivo) se reemplazó por 5 archivos dentro de **`sql/gold/kpi/`**: `kpi_academic.sql`, `kpi_billing.sql`, `kpi_commercial.sql` (uno por estrella, "individuales") y `kpi_cross_university_billing.sql` + `kpi_executive_summary.sql` ("grupales"). Cada uno con su notebook correspondiente dentro de **`notebooks/gold/kpi/`** (`05` a `09`), agregados en orden a `GOLD_NOTEBOOKS` en el DAG (con `task_id` saneado — sin la `/` de la subcarpeta, que Airflow no acepta en nombres de tarea).

Se agregaron 5 vistas nuevas sobre las 6 que ya existían, saliendo de un banco de preguntas de negocio armado explícitamente antes de escribir SQL (documentado en la conversación, no en un archivo aparte):

- `vw_academic_performance_by_course` — igual que por departamento, pero a nivel de curso puntual.
- `vw_churn_by_product` — churn por producto/precio, no solo por segmento de cliente. Encontró variación real (22.5%-26.5% en el top 5), a diferencia de otras vistas que no mostraron señal.
- `vw_open_pipeline_by_industry` — valor del pipeline **abierto** (no cerrado) por industria. KPI candidato desde hace tiempo, nunca antes construido.
- `vw_failing_vs_churn` (grupal, cross university↔billing) — ¿reprobar un curso predice cancelar la suscripción? **Resultado: no** (14.3% vs 14.7% de churn, diferencia mínima) — se documenta como hallazgo negativo, no se descarta ni se maquilla.
- `vw_executive_summary` (grupal) — una fila con el KPI principal de cada dominio (`pct_aprobados_general`, `churn_rate_general`, `ingreso_total`, `win_rate_general`, `pipeline_abierto_valor`), calculados por separado con `CROSS JOIN` de subconsultas de 1 fila cada una — **no** inventa una relación entre CRM y los otros dos dominios, solo yuxtapone números ya calculados.

**Por qué esta organización:** separar en "individuales" (una estrella a la vez) vs. "grupales" (cruces reales o resúmenes) hace explícito qué vistas dependen de qué — las individuales solo necesitan su propia estrella ya construida; las grupales necesitan más de una. Evita mezclar en un solo archivo cosas con dependencias distintas, y deja claro para el lector cuáles cruzan dominios y cuáles no (evitando la confusión de asumir cruces que no existen, como pasó con la propuesta externa de `dim_lead_source`).

---

## 22. Silver: esquema explícito en SQL (`sql/silver/`), retrofit iniciado por `students`

**Decisión:** las tablas de `silver` se escribían con `df.to_sql(if_exists="replace")`, que genera tipos de columna correctos pero **sin `PRIMARY KEY`, `NOT NULL` ni `FOREIGN KEY`** — la integridad dependía solo de los `assert` de Python dentro de cada notebook, no de una restricción real en Postgres. Se agrega `sql/silver/*.sql` con el DDL explícito (mismo patrón que `sql/bronze/` y `sql/gold/`: el notebook lee el archivo y lo ejecuta), y el patrón de escritura cambia de `to_sql(if_exists="replace")` a `TRUNCATE` + `to_sql(if_exists="append")` contra la tabla ya creada con su esquema real.

**La transformación (limpieza en pandas) no se mueve** — sigue 100% dentro del notebook de Jupyter, que es lo que realmente se había pedido (`docs/decisiones.md` #7 quedó desactualizada en ese punto: la limitación era "silver no se limpia con SQL", no "silver no puede tener ningún SQL").

**Aplicado a las 18 tablas** de los 3 dominios (`sql/silver/university.sql`, `billing.sql`, `crm.sql` — un archivo por dominio, mismo criterio que `sql/bronze/`, no un archivo por tabla). Se probó primero en `university__students` como piloto y, verificado el patrón, se escaló al resto: `university` (6 tablas), `billing` (6 tablas), `crm` (6 tablas). Casos particulares reales:

- `silver.crm__opportunity_contacts` — PK compuesta (`opportunity_id`, `contact_id`), no un `id` propio, porque es la tabla puente N:N ya existente en bronze.
- `silver.billing__customers.external_ref`, `silver.crm__activities.contact_id`/`opportunity_id` — FKs *nullable a propósito* (relación opcional real: no todo cliente es estudiante, no toda actividad está ligada a un contacto u oportunidad), no un descuido.
- `silver.crm__leads` — sin ninguna FK, igual que en gold (ver decisión #12): la fuente no provee columna de conexión.

Verificado en Postgres real después de recrear las 18 tablas (`DROP ... CASCADE` + re-ejecución de los 18 notebooks en orden de dependencias): conteos de filas coinciden con bronze en las 18 tablas, `pg_constraint` confirma PK en las 18 y FK en cada relación esperada (incluida la compuesta), y una corrida completa del DAG de Airflow después del retrofit confirma que el patrón `TRUNCATE ... CASCADE` no rompe la orquestación.

---

## 23. Superset como complemento de Power BI, servicio corriendo pero dashboards armados a mano

**Decisión:** se agrega `apache/superset:3.1.3` (imagen oficial, sin `Dockerfile` propio) como servicio `superset`/`superset-init` en `docker-compose.yml`, con su propia base de datos de metadata (`superset`, misma instancia de Postgres, mismo criterio que la base `airflow` — ver decisión #2 y `docker/postgres/init/01-init-databases.sh`). El `SECRET_KEY` y la URI de conexión a esa base se configuran en `docker/superset/superset_config.py`, leyendo variables de `.env`.

**Alcance deliberadamente acotado:** el servicio queda levantado, con `superset-init` corriendo `db upgrade` + `fab create-admin` + `init` una sola vez, pero **no se automatiza el alta de la conexión a `warehouse` ni la creación de charts/dashboards** — eso se arma a mano desde la UI (`localhost:8088`, conectando a `postgresql://dataeng:dataeng_pw@postgres:5432/warehouse`, con las vistas `gold.vw_*` disponibles como datasets).

**Por qué:** Superset arma sus dashboards principalmente por UI (arrastrar/soltar), no por código — automatizar esa parte requeriría el formato de export/import de "assets" de Superset (YAML empaquetado), que es frágil entre versiones y no aporta nada que no se gane más simple aprendiendo la herramienta directamente en el navegador. A diferencia de Power BI (app de escritorio, fuera del repo, dashboards ya armados), Superset queda como alternativa web dentro del stack Docker (reproducible, versionable) — decisión explícita del usuario de mantener ambos en paralelo, no reemplazar uno por el otro.

**Nota operativa:** el script de init de Postgres (`01-init-databases.sh`) solo corre en el primer arranque del volumen `pgdata`. Como el volumen ya existía de corridas previas del proyecto, la base `superset` se creó a mano una vez (`CREATE DATABASE superset OWNER dataeng;`) — en un clon nuevo del repo (volumen vacío), el script la crea automáticamente sin pasos manuales.

---

## 24. Vistas de serie de tiempo mensual, pensadas como datasets de Superset

**Decisión:** se agregan 3 vistas nuevas — `gold.vw_revenue_by_month` y `gold.vw_subscription_events_by_month` en `sql/gold/kpi/kpi_billing.sql`, `gold.vw_opportunity_events_by_month` en `kpi_commercial.sql` — con dos convenciones deliberadas:

1. **`month` es `DATE` real** (`date_trunc('month', ...)::date`), no el `TEXT year_month` de `gold.dim_date`. Superset detecta automáticamente una columna `DATE`/`TIMESTAMP` como eje temporal y habilita sus propios controles de grano y rango; un `TEXT` la trataría como categórica más.
2. **`vw_subscription_events_by_month` y `vw_opportunity_events_by_month` van en formato largo** (una fila por `mes` + `evento`, con `cantidad`), no en columnas separadas (`altas`, `bajas`). Así un solo chart "Time-series" en Superset desglosa por color agrupando por `evento`, sin tener que pivotear en SQL ni crear un chart por serie.

**Por qué:** decisión #23 ya establece que los dashboards de Superset se arman a mano en la UI, no por código — lo único automatizable con sentido es dejar los *datasets* (vistas SQL) en la forma que la herramienta consume mejor. `vw_revenue_by_month` en cambio es una sola métrica por mes (no hay evento que desglosar), así que queda en formato ancho simple.

**Nota operativa:** tras correr `06_kpi_billing.ipynb` y `07_kpi_commercial.ipynb` (recrean las vistas), hay que refrescar los metadatos del dataset en Superset (⋮ → *Refresh column metadata* en cada dataset conectado a `gold.vw_*`) para que la UI detecte las columnas nuevas.

---

## 25. Parquet tambien para bronze y silver, no solo gold

**Decisión:** `src/export/export_parquet.py` ahora exporta las 3 capas (`bronze`, `silver`, `gold`), no solo `gold` (decisión #14 original). Mismas 18 tablas en bronze/silver (`RAW_TABLES`, un nombre compartido porque el esquema de tabla es igual en ambas capas — solo cambia si las columnas están tipadas/limpias) más las 19 de gold, cada capa a su propia carpeta (`data/parquet/{bronze,silver,gold}/`). `src/validation/validate_pipeline.py` se extendió igual: ahora reconcilia bronze→parquet y silver→parquet además de silver→gold→parquet, importando `RAW_TABLES` del script de export para no duplicar la lista de tablas.

**Por qué:** la fase 11 del README ("Exportación a Parquet — Persistencia de las **capas finales**") y el entregable ("Archivos Parquet — **capas** exportadas") usan plural — exportar solo gold es una lectura válida pero conservadora del requisito. Dejar evidencia Parquet de las 3 capas es más seguro de cara a la evaluación y no cuesta nada extra: el volumen sigue siendo chico (máx. 150k filas en la tabla más grande) y el patrón ya existía, solo se generalizó de una lista de tablas a tres.

**No cambia:** el orden del DAG. `export_parquet_task` sigue corriendo una sola vez, después de `build_gold` — para ese punto bronze y silver ya están completos, así que no hace falta moverlo antes ni duplicar la tarea.

---

## 26. Superset reemplaza a Power BI, no lo complementa

**Decisión:** se reemplaza la decisión #23 en el punto donde dice que Superset es un "complemento de Power BI" con "ambos en paralelo" — a partir de ahora **Superset es la única herramienta de dashboard** del proyecto. El `.pbix` (`visualizacion.pbix`) se mantiene en el repo como evidencia histórica del hallazgo documentado en la decisión #19 (el bug real de Win Rate contando oportunidades abiertas), pero no se sigue desarrollando ni se actualiza con las vistas nuevas.

**Por qué:** decisión explícita del usuario. El resto de la decisión #23 sigue vigente sin cambios — el servicio Superset corre en Docker (`localhost:8088`), conecta a `warehouse`, y los dashboards se arman a mano en la UI, no por código (ver esa decisión para el detalle de por qué no se automatiza).

**Impacto:** la **presentación ejecutiva pendiente** (fase 15 del README raíz, ver `notebooks/README.md` "Después de todo esto") ahora se arma sobre Superset, no sobre Power BI.

---

## 27. Banco de preguntas recibido por WhatsApp: 3 nuevas vistas en `kpi_billing.sql`, 2 quedan fuera de gold

**Decisión:** de las 7 preguntas recibidas ("retraso de pagos", "facturación", "promedio", "predicción de pagos y mis pagos", "ausencia o deserción de curso", "puntualidad de pagos", "plan de pagos"), 2 ya estaban cubiertas (`facturación`→`vw_revenue_by_month`/`ingreso_total`; `ausencia o deserción`→tasa de deserción por semestre en `01_insights.ipynb`; "ausencia" en sí no existe, el dataset no tiene tabla de asistencia), 1 quedó fuera de gold por ser un modelo predictivo, no una vista SQL (ver más abajo), y 3 se construyeron como vistas nuevas en `sql/gold/kpi/kpi_billing.sql`:

- **`vw_overdue_invoices_by_segment`** ("retraso de pagos") — % de facturas con `status = 'overdue'` por segmento. Es un estado de la factura (mora), no la puntualidad de un pago ya hecho.
- **`vw_payment_timeliness_by_method`** ("puntualidad de pagos") — de los pagos ya realizados, % que llegó en la fecha de vencimiento de su factura o antes (`paid_date_id <= due_date_id`), por método. Deliberadamente separada de la anterior: una mide facturas todavía impagas, la otra mide comportamiento de pago ya cerrado.
- **`vw_revenue_by_plan`** ("plan de pagos") — se interpretó como plan/producto de suscripción (`dim_product`), no como cuotas/financiamiento (ese concepto no existe en el dataset). Ingreso total y suscripciones activas por plan, complementa a `vw_churn_by_product` (que ya mide cancelación, no ingreso ni adopción).

**Nota tecnica en `vw_revenue_by_plan`:** se calculó con dos CTEs separados (`subs`, `revenue`) en vez de un JOIN directo `dim_product` → `fact_subscription` → `fact_invoice_item`. Un join directo entre dos tablas "many" al mismo grano de producto genera fan-out (cada suscripción se cruza con cada línea de factura del mismo producto) e infla `SUM(line_total)` silenciosamente. Verificado contra Postgres real: `SUM(ingreso_total)` de la vista = `34,931,806.31` = `SUM(line_total)` de `fact_invoice_item` exacto, confirma que no hay inflación.

**Hallazgos reales** (corridos contra Postgres, no estimados): facturas en mora van de 9.5% (`smb`) a 11.3% (`enterprise`) — diferencia chica, y **enterprise es el peor**, lo cual es interesante porque `enterprise` tiene el churn más bajo de los 3 segmentos (ver `vw_churn_by_segment`) — mora y cancelación no van de la mano acá. Puntualidad de pago es **prácticamente idéntica entre métodos** (69.5%-70.9%), mismo patrón de "sin señal" que ya se vio en DSO por método.

**Predicción de pagos:** "predicción de pagos y mis pagos" no es un KPI — es un tercer modelo de ML, construido en `notebooks/ml/03_payment_model.ipynb` (ver decisión #28). "Mis pagos" sugiere una vista personalizada por cliente, como ya hace `app/streamlit_app.py` con churn/win — pendiente de integrar a Streamlit si se quiere esa parte.

---

## 28. Tercer modelo ML: predicción de pago tardío al emitir la factura — acá sí hay señal real

**Decisión:** `notebooks/ml/03_payment_model.ipynb` entrena un `RandomForestClassifier` (mismo patrón que churn/win: `ColumnTransformer` + `OneHotEncoder`/`StandardScaler` + `class_weight="balanced"`) sobre `gold.fact_invoice` para predecir `late` (pago tardío), usando solo features conocidas **al momento de emitir la factura** — no al pagar: `country`, `segment`, `is_student` (de `dim_customer`), `total`, `days_to_due` (de `fact_invoice`). Se excluyen a propósito todas las columnas de `fact_payment` (`method`, `days_to_pay`, `paid_date_id`) por ser información del futuro respecto al momento de la predicción.

**Censura + hallazgo de calidad de datos nuevo:** se excluyen del entrenamiento, además de las 10,048 facturas `pending` (mismo criterio de censura que las suscripciones `active` en el modelo de churn — resultado todavía no ocurre), **3,533 facturas `status = 'paid'` sin ninguna fila en `fact_payment`** — un hallazgo de calidad de datos no documentado antes, encontrado al construir este modelo. Sin un pago asociado no hay forma de saber si llegó a tiempo o tarde, así que se tratan como dato incompleto, no se asume un resultado. Quedan 36,419 facturas resueltas (`overdue` o `paid` con pago real) para entrenar.

**Resultado real (verificado contra Postgres, no estimado): ROC-AUC = 0.862.** A diferencia de churn/win (~0.51 cada uno), acá sí hay señal real y fuerte — pero no la que se buscaba originalmente. La importancia de features muestra que **`days_to_due` explica el 94.8%** de la predicción (`total` otro 3.9%; `country`+`segment`+`is_student` combinadas no llegan al 1%). Verificado agrupando `late` por `days_to_due` directo en SQL: facturas a `net-7` llegan tarde el 94.1% de las veces, a `net-59` solo el 11.5% — relación casi monotónica.

**Por qué esto importa:** el modelo funciona, pero el hallazgo accionable no es "estos clientes son de riesgo" (el perfil del cliente no aporta señal, igual que en churn/win) — es que **el plazo de pago que el negocio le da a cada factura predice el atraso casi por sí solo**. No se retiró `days_to_due` para forzar que las variables de cliente "compitan" — el objetivo es reflejar la relación real, no producir el modelo que se esperaba encontrar. Mismo criterio de honestidad que la decisión #15, con el resultado inverso (esta vez sí hay señal, y se documenta igual de directo).

**Integrado a Streamlit:** `app/streamlit_app.py` ahora tiene una tercera pestaña ("💳 Predecir pago tardío") con el mismo patrón que churn/win (`render_model_tab`, generalizado con un parámetro `auc_note` para que cada pestaña muestre su propio hallazgo honesto en vez de un texto genérico de "sin señal" que ya no aplicaba acá). Incluye una nota explícita invitando a mover el slider de `days_to_due` para ver el hallazgo real en acción. Verificado: contenedor recargó sin errores (`docker logs`, HTTP 200).

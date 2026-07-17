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

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
- `university.courses.department` nunca coincide con el departamento del profesor asignado: se tratan como dos atributos independientes (departamento del curso vs. departamento de origen del profesor), sin intentar reconciliarlos.

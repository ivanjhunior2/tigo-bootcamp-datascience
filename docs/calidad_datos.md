# Análisis de calidad de datos

Hallazgos sobre los 18 CSV fuente, obtenidos por perfilado antes de construir bronze.
Confirmado: los conteos de filas y columnas de los 18 archivos coinciden exactamente
con `manifest.json`; ningún archivo tiene claves primarias duplicadas ni filas
duplicadas completas.

## university

| Archivo | Hallazgo | Tratamiento propuesto (silver) |
|---|---|---|
| `courses.csv` | `department` del curso coincide con `department` del profesor asignado en solo 36/300 filas (~12%) — consistente con asignación aleatoria/independiente entre 8 categorías (~12.5% esperado por azar), no con una relación real entre ambos campos | No es un error de join: son dos dimensiones independientes (área del curso vs. área de origen del profesor). Se conservan ambas columnas sin reconciliar. Verificado en `notebooks/university/03_courses.ipynb`. |
| resto de archivos | Sin nulos, sin FKs huérfanas, sin inconsistencias de formato | Solo tipado y renombrado estándar. |

## billing

| Archivo | Hallazgo | Tratamiento propuesto (silver) |
|---|---|---|
| `customers.csv` | `external_ref` vacío en 5000/10000 filas (50%) | Solapamiento parcial intencional con `university.students`. Se mantiene como FK opcional (nullable), no se descarta ni se imputa. |
| `products.csv` | `active` viene como texto `True`/`False` (estilo Python) | Castear explícitamente a `BOOLEAN` en silver. |
| `subscriptions.csv` | 783/15000 filas (5.2%) con `start_date > end_date` (rango de fechas invertido) | Regla de calidad: cuando `start_date > end_date`, se marca la fila (`_end_date_invalidated = true`) y se anula (`NULL`) `end_date` en silver, dejando el dato original visible en bronze para auditoría. Verificado en `notebooks/billing/03_subscriptions.ipynb`: 783 filas afectadas, quedan 14,217/15,000 con `end_date` válido. |
| `subscriptions.csv` | `end_date` poblado en el 100% de las filas, por igual en **todos** los `status` (no solo `active`) | Medido en el notebook antes de asumir que era un error: al ser uniforme entre todos los status, es el diseño del campo (fecha de fin contratada, no fecha real de terminación), **no un defecto**. No se anula por esta razón — corrige la hipótesis inicial de este documento. |
| resto de archivos | Sin nulos, sin FKs huérfanas | Solo tipado estándar. `invoice_items.line_total = quantity * unit_price` verificado consistente en el 100% de las filas. |

## crm

| Archivo | Hallazgo | Tratamiento propuesto (silver) |
|---|---|---|
| `opportunities.csv` | 1029/3000 filas (~34%) con `close_date < created_at` | Medido por `stage` en `notebooks/crm/04_opportunities.ipynb`: el porcentaje es uniforme entre todos los stages (31–37%, abiertos y cerrados por igual) — no se concentra en `won`/`lost` ni en abiertos. Confirma que `close_date` es una fecha objetivo/estimada, no la fecha real de cierre. No se anula ni descarta ninguna fila; se agrega el flag `_close_date_before_created` en silver para trazabilidad. |
| `activities.csv` | `contact_id` vacío en 5976/20000 filas (30%); `opportunity_id` vacío en 9985/20000 filas (50%) | FKs opcionales por diseño: una actividad puede no estar ligada a un contacto, a una oportunidad, a ambos o a ninguno. Se mantienen nullable, sin descartar filas. |
| resto de archivos | Sin nulos, sin FKs huérfanas | Solo tipado estándar. |

## Cross-cutting

- Ningún archivo tiene problemas de espacios en blanco, mayúsculas/minúsculas inconsistentes, o variantes con errores de tipeo en columnas categóricas (`status`, `stage`, `segment`, `category`, etc.) — todas usan `snake_case` limpio.
- Los formatos de fecha son consistentes dentro de cada columna (`YYYY-MM-DD` para fechas, `YYYY-MM-DD HH:MM:SS` para timestamps), sin mezclas.
- No se encontraron referencias huérfanas (`FK` sin `PK` correspondiente) en ninguna de las relaciones inferidas por columnas `*_id` compartidas.

## Estado: todas las reglas ya implementadas en silver

Las 18 tablas están cargadas en `silver` (ver `notebooks/README.md` para el detalle por tabla). Todas las reglas de esta tabla ya están aplicadas y verificadas con las cifras reales medidas en cada notebook — esto cumple el punto de "detección y tratamiento explícito" pedido por el README.

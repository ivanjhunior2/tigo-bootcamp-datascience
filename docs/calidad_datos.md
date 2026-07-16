# Análisis de calidad de datos

Hallazgos sobre los 18 CSV fuente, obtenidos por perfilado antes de construir bronze.
Confirmado: los conteos de filas y columnas de los 18 archivos coinciden exactamente
con `manifest.json`; ningún archivo tiene claves primarias duplicadas ni filas
duplicadas completas.

## university

| Archivo | Hallazgo | Tratamiento propuesto (silver) |
|---|---|---|
| `courses.csv` | `department` del curso nunca coincide con `department` del profesor asignado (0/300 coinciden) | No es un error de join: son dos dimensiones independientes (área del curso vs. área de origen del profesor). Se conservan ambas columnas sin reconciliar. |
| resto de archivos | Sin nulos, sin FKs huérfanas, sin inconsistencias de formato | Solo tipado y renombrado estándar. |

## billing

| Archivo | Hallazgo | Tratamiento propuesto (silver) |
|---|---|---|
| `customers.csv` | `external_ref` vacío en 5000/10000 filas (50%) | Solapamiento parcial intencional con `university.students`. Se mantiene como FK opcional (nullable), no se descarta ni se imputa. |
| `products.csv` | `active` viene como texto `True`/`False` (estilo Python) | Castear explícitamente a `BOOLEAN` en silver. |
| `subscriptions.csv` | 783/15000 filas (~5%) con `start_date > end_date` (rango de fechas invertido); `end_date` poblado incluso en suscripciones `active` | Regla de calidad: si `status = active` y `end_date` está poblado, o si `start_date > end_date`, se marca la fila y se anula (`NULL`) `end_date` en silver, dejando el dato original visible en bronze para auditoría. Documentar el conteo de filas afectadas como métrica de calidad. |
| resto de archivos | Sin nulos, sin FKs huérfanas | Solo tipado estándar. `invoice_items.line_total = quantity * unit_price` verificado consistente en el 100% de las filas. |

## crm

| Archivo | Hallazgo | Tratamiento propuesto (silver) |
|---|---|---|
| `opportunities.csv` | 1029/3000 filas (~34%) con `close_date < created_at` | `close_date` es una fecha objetivo/estimada, no necesariamente posterior a la creación. No se trata como error; se documenta y se deja pasar tal cual, salvo si además `stage` indica que la oportunidad sigue abierta con una fecha de cierre ya pasada (posible regla de calidad adicional a definir al construir silver). |
| `activities.csv` | `contact_id` vacío en 5976/20000 filas (30%); `opportunity_id` vacío en 9985/20000 filas (50%) | FKs opcionales por diseño: una actividad puede no estar ligada a un contacto, a una oportunidad, a ambos o a ninguno. Se mantienen nullable, sin descartar filas. |
| resto de archivos | Sin nulos, sin FKs huérfanas | Solo tipado estándar. |

## Cross-cutting

- Ningún archivo tiene problemas de espacios en blanco, mayúsculas/minúsculas inconsistentes, o variantes con errores de tipeo en columnas categóricas (`status`, `stage`, `segment`, `category`, etc.) — todas usan `snake_case` limpio.
- Los formatos de fecha son consistentes dentro de cada columna (`YYYY-MM-DD` para fechas, `YYYY-MM-DD HH:MM:SS` para timestamps), sin mezclas.
- No se encontraron referencias huérfanas (`FK` sin `PK` correspondiente) en ninguna de las relaciones inferidas por columnas `*_id` compartidas.

## Qué queda pendiente para la etapa de silver

- Definir y aplicar las reglas de la tabla de arriba (cast de `active`, invalidación de `end_date`/`start_date` inconsistentes en `subscriptions`).
- Decidir si `opportunities` con `close_date < created_at` y `stage` abierto amerita una regla de calidad adicional (ej. flag `is_stale_close_date`).
- Cuantificar y registrar en esta misma tabla el número de filas afectadas por cada regla, una vez implementada, como evidencia de "detección y tratamiento explícito" pedido por el README.

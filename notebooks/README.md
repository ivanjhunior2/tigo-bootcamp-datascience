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

## billing ⏳ pendiente

| # | Tabla | Notebook | FKs a | Regla de limpieza esperada |
|---|---|---|---|---|
| 01 | customers | `billing/01_customers.ipynb` | (university.students, opcional vía `external_ref`) | — |
| 02 | products | `billing/02_products.ipynb` | — | `active`: texto `True`/`False` → booleano real |
| 03 | subscriptions | `billing/03_subscriptions.ipynb` | customers, products | invalidar `end_date` cuando `start_date > end_date` o `status = active` con `end_date` poblado (~5% de filas) |
| 04 | invoices | `billing/04_invoices.ipynb` | customers | — |
| 05 | invoice_items | `billing/05_invoice_items.ipynb` | invoices, products | — |
| 06 | payments | `billing/06_payments.ipynb` | invoices | — |

## crm ⏳ pendiente

| # | Tabla | Notebook | FKs a | Regla de limpieza esperada |
|---|---|---|---|---|
| 01 | accounts | `crm/01_accounts.ipynb` | — | — |
| 02 | contacts | `crm/02_contacts.ipynb` | accounts | — |
| 03 | leads | `crm/03_leads.ipynb` | — | tabla independiente, sin FK |
| 04 | opportunities | `crm/04_opportunities.ipynb` | accounts | documentar `close_date < created_at` (~34% de filas), decidir si amerita flag |
| 05 | opportunity_contacts | `crm/05_opportunity_contacts.ipynb` | opportunities, contacts | tabla puente N:N |
| 06 | activities | `crm/06_activities.ipynb` | contacts, opportunities (ambos opcionales) | mantener FKs nullable, no descartar filas sin contacto/oportunidad |

## Después de silver: gold

Cuando las 18 tablas estén en `silver`, seguimos con el modelado dimensional (estrella) en SQL sobre `gold`, y ahí sí definimos foreign keys reales para que el diagrama ER se vea completo en DBeaver.

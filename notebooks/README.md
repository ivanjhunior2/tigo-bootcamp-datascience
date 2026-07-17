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

## Después de silver: gold

Cuando las 18 tablas estén en `silver`, seguimos con el modelado dimensional (estrella) en SQL sobre `gold`, y ahí sí definimos foreign keys reales para que el diagrama ER se vea completo en DBeaver.

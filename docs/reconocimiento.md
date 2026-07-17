# Reconocimiento de datos (Fase 4 — Discovery y perfilado)

Perfilado programático de los 18 CSV fuente (`billing/`, `crm/`, `university/`), siguiendo el proceso
de la skill `programmatic-eda`: overview estructural, perfil de nulos y verificación cruzada contra
`manifest.json` y los hallazgos ya registrados en [`decisiones.md`](./decisiones.md) y
[`calidad_datos.md`](./calidad_datos.md). Tipos inferidos por el patrón del valor (no son los tipos
finales de `silver`, que se definen en los notebooks de limpieza).

---

## 1. De qué trata cada dataset

### `billing/` — Facturación y suscripciones
Sistema de facturación de una plataforma que vende productos/planes por suscripción. Un cliente
(`customers`) contrata uno o más productos (`products`) mediante suscripciones (`subscriptions`),
recibe facturas (`invoices`) compuestas por líneas (`invoice_items`) y las paga (`payments`). Es el
dominio con más volumen (150,000 filas en `invoice_items`) y el único con una columna de solapamiento
explícito hacia otro dominio (`customers.external_ref` → `university.students.student_id`).

### `crm/` — Gestión comercial (CRM)
Sistema de ventas B2B: cuentas/empresas (`accounts`) con contactos (`contacts`) asociados, leads
comerciales (`leads`) que no se conectan a ninguna otra tabla, oportunidades de venta
(`opportunities`) ligadas a una cuenta, la relación N:N entre oportunidades y contactos
(`opportunity_contacts`), y actividades comerciales (`activities`, llamadas/reuniones/notas) que
opcionalmente referencian un contacto y/o una oportunidad.

### `university/` — Gestión académica
Sistema académico de una institución que ofrece cursos: estudiantes (`students`) se inscriben
(`enrollments`) a cursos (`courses`) dictados por profesores (`professors`) durante semestres
(`semesters`), y reciben calificaciones (`grades`) por evaluación dentro de cada inscripción.

Los tres dominios describen el mismo negocio de fondo (una institución educativa que también
factura sus servicios y gestiona ventas B2B), pero llegan de tres sistemas de origen distintos —no
hay un ER formal, las relaciones se infieren solo de columnas `*_id` compartidas (ver README raíz,
sección 2).

---

## 2. Columnas principales, tipos inferidos y % de nulos

Leyenda de estado: **OK** (0% nulos) · **WARN** (nulos, pero explicados/por diseño) · el resto de
columnas sin marca no presentan nulos.

### billing.customers (10,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| customer_id | string (`CUS-#######`) | 0.0 | PK, única |
| external_ref | string (`STU-#######`) | **50.0** | FK opcional → `university.students.student_id`; solapamiento parcial intencional (ver decisiones.md #6) |
| first_name / last_name | string | 0.0 | 50 valores únicos c/u (catálogo de nombres sintéticos) |
| email | string | 0.0 | única |
| country | string (ISO-2) | 0.0 | 8 valores |
| created_at | datetime | 0.0 | — |
| segment | string | 0.0 | 3 valores (`smb`, …) |

### billing.products (200 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| product_id / sku | string | 0.0 | PK / código, ambas únicas |
| name | string | 0.0 | única |
| category | string | 0.0 | 4 valores |
| monthly_price | float | 0.0 | — |
| active | bool (texto `True`/`False`) | 0.0 | requiere cast explícito en silver |

### billing.subscriptions (15,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| subscription_id | string | 0.0 | PK |
| status | string | 0.0 | 3 valores |
| start_date / end_date | date | 0.0 | 783/15,000 (5.22%) con `start_date > end_date` — verificado, coincide con calidad_datos.md |
| customer_id | string | 0.0 | FK → customers |
| product_id | string | 0.0 | FK → products |

### billing.invoices (50,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| invoice_id | string | 0.0 | PK |
| issued_at / due_at | date | 0.0 | — |
| total | float | 0.0 | — |
| status | string | 0.0 | 3 valores |
| currency | string | 0.0 | 8 valores |
| customer_id | string | 0.0 | FK → customers |

### billing.invoice_items (150,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| invoice_item_id | string | 0.0 | PK |
| quantity | int | 0.0 | — |
| unit_price / line_total | float | 0.0 | `line_total = quantity * unit_price` verificado consistente en 150,000/150,000 filas |
| invoice_id | string | 0.0 | FK → invoices |
| product_id | string | 0.0 | FK → products |

### billing.payments (80,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| payment_id | string | 0.0 | PK |
| amount | float | 0.0 | — |
| paid_at | date | 0.0 | — |
| method | string | 0.0 | 4 valores |
| invoice_id | string | 0.0 | FK → invoices |

### crm.accounts (5,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| account_id | string | 0.0 | PK |
| name | string | 0.0 | solo 599 valores únicos (nombres de empresa reutilizados) |
| industry / country | string | 0.0 | 8 valores c/u |
| annual_revenue | float | 0.0 | — |
| employees | int | 0.0 | — |
| created_at | datetime | 0.0 | — |

### crm.contacts (15,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| contact_id | string | 0.0 | PK |
| first_name / last_name | string | 0.0 | catálogo de 50 nombres c/u |
| email / phone | string | 0.0 | — |
| title | string | 0.0 | 10 valores |
| created_at | datetime | 0.0 | — |
| account_id | string | 0.0 | FK → accounts |

### crm.leads (2,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| lead_id | string | 0.0 | PK |
| first_name / last_name / email | string | 0.0 | — |
| source | string | 0.0 | 5 valores |
| status | string | 0.0 | 5 valores |
| score | int | 0.0 | 0–100 |
| created_at | datetime | 0.0 | tabla sin FK a otras tablas (ver decisiones.md #12) |

### crm.opportunities (3,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| opportunity_id | string | 0.0 | PK |
| name | string | 0.0 | — |
| stage | string | 0.0 | 6 valores |
| amount | float | 0.0 | — |
| close_date | date | 0.0 | 1,029/3,000 (34.30%) con `close_date < created_at`, uniforme entre stages (31.4%–36.8%) — verificado |
| created_at | datetime | 0.0 | — |
| account_id | string | 0.0 | FK → accounts |

### crm.opportunity_contacts (6,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| opportunity_id | string | 0.0 | FK → opportunities (tabla puente N:N, sin PK propia) |
| contact_id | string | 0.0 | FK → contacts |
| role | string | 0.0 | 5 valores |

### crm.activities (20,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| activity_id | string | 0.0 | PK |
| type | string | 0.0 | 5 valores |
| subject | string | 0.0 | única |
| occurred_at | datetime | 0.0 | — |
| contact_id | string | **29.88** | FK opcional → contacts |
| opportunity_id | string | **49.92** | FK opcional → opportunities |

### university.students (5,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| student_id | string | 0.0 | PK, tabla de referencia del patrón |
| first_name / last_name | string | 0.0 | catálogo de 50 nombres |
| email | string | 0.0 | — |
| birth_date / enrolled_at | date | 0.0 | — |
| country | string | 0.0 | 8 valores |

### university.professors (200 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| professor_id | string | 0.0 | PK |
| first_name / last_name | string | 0.0 | — |
| email | string | 0.0 | — |
| department | string | 0.0 | 8 valores |
| hired_at | date | 0.0 | — |

### university.courses (300 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| course_id / code | string | 0.0 | PK / código |
| name | string | 0.0 | — |
| credits | int | 0.0 | 5 valores |
| department | string | 0.0 | coincide con `professors.department` solo en 36/300 (12.00%) — verificado, azar entre 8 categorías |
| professor_id | string | 0.0 | FK → professors |

### university.semesters (8 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| semester_id / code | string | 0.0 | PK / código (`2022-1`) |
| year / half | int | 0.0 | — |
| start_date / end_date | date | 0.0 | — |

### university.enrollments (25,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| enrollment_id | string | 0.0 | PK |
| enrolled_at | date | 0.0 | — |
| status | string | 0.0 | 4 valores |
| student_id | string | 0.0 | FK → students |
| course_id | string | 0.0 | FK → courses |
| semester_id | string | 0.0 | FK → semesters |

### university.grades (60,000 filas)

| Columna | Tipo inferido | % nulos | Notas |
|---|---|---|---|
| grade_id | string | 0.0 | PK |
| assessment | string | 0.0 | 5 valores |
| score / weight | float | 0.0 | — |
| graded_at | date | 0.0 | — |
| enrollment_id | string | 0.0 | FK → enrollments |

---

## 3. Entidades clave detectadas

**Clientes / personas:**
- `billing.customers` (clientes de facturación)
- `crm.accounts` + `crm.contacts` (empresas y personas de contacto B2B)
- `crm.leads` (prospectos, aislados — sin FK hacia el resto del CRM)
- `university.students` (estudiantes)
- Puente cross-domain: `customers.external_ref → students.student_id` (50% de los clientes son también estudiantes; 0 huérfanos verificados)

**Productos / catálogo:**
- `billing.products` (planes/productos facturables)
- `university.courses` (cursos, con `professor_id` como dueño)

**Personal / recursos:**
- `university.professors`

**Transacciones / eventos de negocio:**
- `billing.subscriptions`, `billing.invoices`, `billing.invoice_items`, `billing.payments` (ciclo de facturación completo: contrato → factura → línea → pago)
- `crm.opportunities`, `crm.activities`, `crm.opportunity_contacts` (ciclo de venta)
- `university.enrollments`, `university.grades` (ciclo académico)

**Dimensiones temporales:**
- `university.semesters` (única tabla de calendario explícita)
- Columnas de fecha/timestamp presentes en prácticamente todas las tablas (`created_at`, `*_at`, `*_date`) — candidatas a `dim_date` conformada (ya construida en `gold`, ver `notebooks/gold/01_dim_date.ipynb`)

**Grain de cada tabla transaccional:** una fila = un evento atómico (una línea de factura, un pago, una inscripción, una calificación, una actividad), consistente con lo documentado en `notebooks/README.md`.

---

## 4. Verificación — ¿es correcto lo que ya teníamos documentado?

Se recalculó cada cifra reportada en `decisiones.md` y `calidad_datos.md` directamente contra los 18 CSV (perfilado propio + chequeos cruzados, sin depender de las corridas previas en Jupyter). Resultado: **todo lo documentado se confirma exacto**, sin discrepancias.

| Afirmación previa | Recalculado ahora | Estado |
|---|---|---|
| Filas y columnas de los 18 CSV coinciden con `manifest.json` | 18/18 archivos coinciden exactamente (filas y nombres de columna) | ✅ Confirmado |
| `customers.external_ref` vacío en 50% | 5,000/10,000 = 50.00%, 0 huérfanas contra `students.student_id` | ✅ Confirmado |
| `subscriptions` con `start_date > end_date` en 783 filas (5.2%) | 783/15,000 = 5.22% | ✅ Confirmado |
| `activities.contact_id` vacío ~30%, `opportunity_id` vacío ~50% | 5,976/20,000 = 29.88% · 9,985/20,000 = 49.92% | ✅ Confirmado |
| `opportunities` con `close_date < created_at` en ~34%, uniforme 31–37% entre stages | 1,029/3,000 = 34.30%; rango por stage 31.4%–36.8% | ✅ Confirmado |
| `courses.department` == `professors.department` en ~12% (36/300) | 36/300 = 12.00% | ✅ Confirmado |
| `invoice_items.line_total = quantity * unit_price` consistente al 100% | 0 discrepancias en 150,000 filas | ✅ Confirmado |
| Sin PKs duplicadas en ninguna tabla | 0 duplicados de PK en las 17 tablas con PK propia | ✅ Confirmado |
| Resto de columnas sin nulos | Confirmado — ninguna otra columna de los 18 archivos presenta valores nulos | ✅ Confirmado |

**Conclusión:** el reconocimiento y el análisis de calidad ya documentados en el repo son correctos y reproducibles byte a byte contra los CSV fuente. No se encontró ninguna cifra desactualizada ni ningún hallazgo nuevo que no estuviera ya cubierto en `calidad_datos.md`. Este documento formaliza el paso de "Discovery y perfilado" (Fase 4 del README) como entregable propio, complementando — no reemplazando — el detalle tabla-por-tabla que ya vive en `notebooks/{billing,crm,university}/`.

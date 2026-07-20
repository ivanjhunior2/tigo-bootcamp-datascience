-- Gold: capa de vistas KPI.
--
-- Motivo: el bug real que encontramos armando Power BI (Win Rate contando
-- oportunidades abiertas en el denominador) paso porque la regla de negocio
-- ("solo cuentan las oportunidades cerradas") solo vivia en el SQL de
-- notebooks/gold/04_estrella_crm.ipynb -- al reimplementarla en DAX se
-- perdio. Estas vistas mueven cada regla de negocio a un solo lugar (SQL,
-- en gold) para que Power BI, Superset o cualquier otra herramienta lean
-- el numero ya correcto en vez de recalcularlo cada una por su cuenta.
--
-- Requiere que university.sql, billing.sql y crm.sql ya hayan corrido
-- (lee de fact_opportunity, fact_subscription, fact_enrollment, fact_lead,
-- fact_payment y sus dimensiones).

CREATE OR REPLACE VIEW gold.vw_win_rate_by_industry AS
SELECT
    a.industry,
    count(*) FILTER (WHERE NOT o.is_open) AS oportunidades_cerradas,
    count(*) FILTER (WHERE o.is_won) AS ganadas,
    ROUND(100.0 * count(*) FILTER (WHERE o.is_won) / NULLIF(count(*) FILTER (WHERE NOT o.is_open), 0), 1) AS win_rate_pct
FROM gold.fact_opportunity o
JOIN gold.dim_account a ON a.account_id = o.account_id
GROUP BY a.industry;

CREATE OR REPLACE VIEW gold.vw_churn_by_segment AS
SELECT
    c.segment,
    count(*) AS suscripciones,
    count(*) FILTER (WHERE s.is_cancelled) AS canceladas,
    ROUND(100.0 * count(*) FILTER (WHERE s.is_cancelled) / count(*), 1) AS churn_rate_pct
FROM gold.fact_subscription s
JOIN gold.dim_customer c ON c.customer_id = s.customer_id
GROUP BY c.segment;

CREATE OR REPLACE VIEW gold.vw_academic_performance_by_department AS
SELECT
    c.department,
    count(*) AS inscripciones,
    ROUND(AVG(f.avg_score), 1) AS promedio,
    ROUND(100.0 * AVG(f.is_passing::int), 1) AS pct_aprobados
FROM gold.fact_enrollment f
JOIN gold.dim_course c ON c.course_id = f.course_id
WHERE f.avg_score IS NOT NULL
GROUP BY c.department;

CREATE OR REPLACE VIEW gold.vw_lead_conversion_by_source AS
SELECT
    source,
    count(*) AS leads,
    count(*) FILTER (WHERE is_converted) AS convertidos,
    ROUND(100.0 * count(*) FILTER (WHERE is_converted) / count(*), 1) AS conversion_rate_pct
FROM gold.fact_lead
GROUP BY source;

CREATE OR REPLACE VIEW gold.vw_dso_by_payment_method AS
SELECT
    method,
    count(*) AS pagos,
    ROUND(AVG(days_to_pay), 1) AS dias_promedio_pago
FROM gold.fact_payment
GROUP BY method;

CREATE OR REPLACE VIEW gold.vw_retention_by_student_status AS
SELECT
    c.is_student,
    count(*) AS suscripciones,
    ROUND(100.0 * count(*) FILTER (WHERE s.is_active) / count(*), 1) AS pct_activas,
    ROUND(100.0 * count(*) FILTER (WHERE s.is_cancelled) / count(*), 1) AS pct_canceladas
FROM gold.fact_subscription s
JOIN gold.dim_customer c ON c.customer_id = s.customer_id
GROUP BY c.is_student;

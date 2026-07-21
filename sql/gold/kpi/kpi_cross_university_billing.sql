-- Gold: KPIs grupales -- cruce university <-> billing.
-- Unico cruce real que existe en el modelo (via dim_customer.student_id ->
-- dim_student.student_id, 50% cobertura). No se cruza con CRM: no hay FK
-- que lo respalde (ver docs/decisiones.md #12).

CREATE OR REPLACE VIEW gold.vw_retention_by_student_status AS
SELECT
    c.is_student,
    count(*) AS suscripciones,
    ROUND(100.0 * count(*) FILTER (WHERE s.is_active) / count(*), 1) AS pct_activas,
    ROUND(100.0 * count(*) FILTER (WHERE s.is_cancelled) / count(*), 1) AS pct_canceladas
FROM gold.fact_subscription s
JOIN gold.dim_customer c ON c.customer_id = s.customer_id
GROUP BY c.is_student;

-- Pregunta cruzada #2 del banco de preguntas -- la mas interesante:
-- reprobar un curso predice cancelar la suscripcion? Solo entre clientes
-- que ademas son estudiantes (is_student = true) Y que tienen al menos una
-- inscripcion ya calificada (si no, no hay senal de rendimiento academico
-- para ese estudiante -- se excluye en vez de asumir "nunca reprobo").
CREATE OR REPLACE VIEW gold.vw_failing_vs_churn AS
WITH student_performance AS (
    SELECT
        student_id,
        BOOL_OR(NOT is_passing) AS ever_failed
    FROM gold.fact_enrollment
    WHERE is_passing IS NOT NULL
    GROUP BY student_id
)
SELECT
    sp.ever_failed,
    count(*) AS suscripciones,
    ROUND(100.0 * count(*) FILTER (WHERE s.is_cancelled) / count(*), 1) AS churn_rate_pct
FROM gold.fact_subscription s
JOIN gold.dim_customer c ON c.customer_id = s.customer_id
JOIN student_performance sp ON sp.student_id = c.student_id
WHERE c.is_student
GROUP BY sp.ever_failed;

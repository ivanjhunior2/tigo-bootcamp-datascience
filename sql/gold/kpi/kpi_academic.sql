-- Gold: KPIs individuales -- estrella academica.
-- Ver docs/decisiones.md #19 (por que las reglas de negocio viven en vistas,
-- no en cada herramienta de BI) y #21 (por que se organizan en 3
-- individuales + 2 grupales).

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

-- Grano mas fino que por departamento: pregunta academica #1 del banco de
-- preguntas ("que curso puntual tiene la mayor tasa de reprobacion").
CREATE OR REPLACE VIEW gold.vw_academic_performance_by_course AS
SELECT
    c.course_id,
    c.code,
    c.name,
    c.department,
    count(*) AS inscripciones,
    ROUND(AVG(f.avg_score), 1) AS promedio,
    ROUND(100.0 * AVG(f.is_passing::int), 1) AS pct_aprobados
FROM gold.fact_enrollment f
JOIN gold.dim_course c ON c.course_id = f.course_id
WHERE f.avg_score IS NOT NULL
GROUP BY c.course_id, c.code, c.name, c.department;

-- Gold: KPI grupal -- resumen ejecutivo de las 3 estrellas.
-- Una sola fila con el numero principal de cada dominio, calculado por
-- separado y yuxtapuesto con CROSS JOIN (cada subconsulta ya devuelve
-- exactamente 1 fila) -- no inventa ninguna relacion entre CRM y las otras
-- dos que los datos no respaldan (ver docs/decisiones.md #12).

CREATE OR REPLACE VIEW gold.vw_executive_summary AS
SELECT
    academic.pct_aprobados_general,
    billing.churn_rate_general,
    billing.ingreso_total,
    commercial.win_rate_general,
    commercial.pipeline_abierto_valor
FROM (
    SELECT ROUND(100.0 * AVG(is_passing::int), 1) AS pct_aprobados_general
    FROM gold.fact_enrollment
    WHERE is_passing IS NOT NULL
) academic
CROSS JOIN (
    SELECT
        (SELECT ROUND(100.0 * AVG(is_cancelled::int), 1) FROM gold.fact_subscription) AS churn_rate_general,
        (SELECT SUM(total) FROM gold.fact_invoice) AS ingreso_total
) billing
CROSS JOIN (
    SELECT
        (SELECT ROUND(100.0 * AVG(is_won::int), 1) FROM gold.fact_opportunity WHERE NOT is_open) AS win_rate_general,
        (SELECT SUM(amount) FROM gold.fact_opportunity WHERE is_open) AS pipeline_abierto_valor
) commercial;

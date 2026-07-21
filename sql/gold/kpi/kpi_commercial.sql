-- Gold: KPIs individuales -- estrella comercial.

CREATE OR REPLACE VIEW gold.vw_win_rate_by_industry AS
SELECT
    a.industry,
    count(*) FILTER (WHERE NOT o.is_open) AS oportunidades_cerradas,
    count(*) FILTER (WHERE o.is_won) AS ganadas,
    ROUND(100.0 * count(*) FILTER (WHERE o.is_won) / NULLIF(count(*) FILTER (WHERE NOT o.is_open), 0), 1) AS win_rate_pct
FROM gold.fact_opportunity o
JOIN gold.dim_account a ON a.account_id = o.account_id
GROUP BY a.industry;

CREATE OR REPLACE VIEW gold.vw_lead_conversion_by_source AS
SELECT
    source,
    count(*) AS leads,
    count(*) FILTER (WHERE is_converted) AS convertidos,
    ROUND(100.0 * count(*) FILTER (WHERE is_converted) / count(*), 1) AS conversion_rate_pct
FROM gold.fact_lead
GROUP BY source;

-- Pregunta comercial #1 del banco de preguntas -- la que marcamos como mas
-- valiosa: cuanto vale el pipeline abierto ahora mismo, por industria.
CREATE OR REPLACE VIEW gold.vw_open_pipeline_by_industry AS
SELECT
    a.industry,
    count(*) AS oportunidades_abiertas,
    SUM(o.amount) AS valor_pipeline,
    ROUND(AVG(o.amount), 0) AS ticket_promedio
FROM gold.fact_opportunity o
JOIN gold.dim_account a ON a.account_id = o.account_id
WHERE o.is_open
GROUP BY a.industry;

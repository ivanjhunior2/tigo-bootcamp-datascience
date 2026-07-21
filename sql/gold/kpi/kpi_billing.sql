-- Gold: KPIs individuales -- estrella facturacion.

CREATE OR REPLACE VIEW gold.vw_churn_by_segment AS
SELECT
    c.segment,
    count(*) AS suscripciones,
    count(*) FILTER (WHERE s.is_cancelled) AS canceladas,
    ROUND(100.0 * count(*) FILTER (WHERE s.is_cancelled) / count(*), 1) AS churn_rate_pct
FROM gold.fact_subscription s
JOIN gold.dim_customer c ON c.customer_id = s.customer_id
GROUP BY c.segment;

CREATE OR REPLACE VIEW gold.vw_dso_by_payment_method AS
SELECT
    method,
    count(*) AS pagos,
    ROUND(AVG(days_to_pay), 1) AS dias_promedio_pago
FROM gold.fact_payment
GROUP BY method;

-- Pregunta billing #2 del banco de preguntas: el precio del producto
-- se relaciona con mayor o menor churn?
CREATE OR REPLACE VIEW gold.vw_churn_by_product AS
SELECT
    p.product_id,
    p.name,
    p.category,
    p.monthly_price,
    count(*) AS suscripciones,
    count(*) FILTER (WHERE s.is_cancelled) AS canceladas,
    ROUND(100.0 * count(*) FILTER (WHERE s.is_cancelled) / count(*), 1) AS churn_rate_pct
FROM gold.fact_subscription s
JOIN gold.dim_product p ON p.product_id = s.product_id
GROUP BY p.product_id, p.name, p.category, p.monthly_price;

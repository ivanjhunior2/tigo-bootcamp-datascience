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

-- Serie de tiempo mensual -- dataset para chart "Time-series" en Superset.
-- `month` es DATE real (date_trunc), no el TEXT year_month de dim_date, para
-- que Superset detecte la columna temporal solo. Ver docs/decisiones.md #24.
CREATE OR REPLACE VIEW gold.vw_revenue_by_month AS
SELECT
    date_trunc('month', issued_date_id)::date AS month,
    SUM(line_total) AS ingreso
FROM gold.fact_invoice_item
GROUP BY 1
ORDER BY 1;

-- Altas y bajas de suscripciones por mes, en formato largo (una fila por
-- mes+evento) para desglosar por color en un solo chart sin pivotear en SQL.
CREATE OR REPLACE VIEW gold.vw_subscription_events_by_month AS
WITH altas AS (
    SELECT date_trunc('month', start_date_id)::date AS month, 'alta' AS evento, count(*) AS cantidad
    FROM gold.fact_subscription
    GROUP BY 1
),
bajas AS (
    SELECT date_trunc('month', end_date_id)::date AS month, 'baja' AS evento, count(*) AS cantidad
    FROM gold.fact_subscription
    WHERE is_cancelled AND end_date_id IS NOT NULL
    GROUP BY 1
)
SELECT * FROM altas
UNION ALL
SELECT * FROM bajas
ORDER BY month;

-- Pregunta del banco (WhatsApp) -- "retraso de pagos": facturas en mora
-- (status = 'overdue' en la fuente) por segmento de cliente. Es un estado
-- de la factura (que puede seguir sin pagar), no la puntualidad de un pago
-- ya realizado -- ver vw_payment_timeliness_by_method para eso. Ver
-- docs/decisiones.md #27.
CREATE OR REPLACE VIEW gold.vw_overdue_invoices_by_segment AS
SELECT
    c.segment,
    count(*) AS facturas,
    count(*) FILTER (WHERE i.is_overdue) AS vencidas,
    ROUND(100.0 * count(*) FILTER (WHERE i.is_overdue) / count(*), 1) AS pct_vencidas
FROM gold.fact_invoice i
JOIN gold.dim_customer c ON c.customer_id = i.customer_id
GROUP BY c.segment;

-- Pregunta del banco -- "puntualidad de pagos": de los pagos YA realizados,
-- cuantos llegaron en la fecha de vencimiento de su factura o antes, vs.
-- despues. Complementa (no reemplaza) al DSO -- DSO mide dias promedio,
-- esto mide el corte binario a-tiempo/tarde.
CREATE OR REPLACE VIEW gold.vw_payment_timeliness_by_method AS
SELECT
    p.method,
    count(*) AS pagos,
    count(*) FILTER (WHERE p.paid_date_id <= i.due_date_id) AS a_tiempo,
    ROUND(100.0 * count(*) FILTER (WHERE p.paid_date_id <= i.due_date_id) / count(*), 1) AS pct_a_tiempo
FROM gold.fact_payment p
JOIN gold.fact_invoice i ON i.invoice_id = p.invoice_id
GROUP BY p.method;

-- Pregunta del banco -- "plan de pagos" = plan/producto de suscripcion
-- (dim_product; el dataset no tiene concepto de cuotas/financiamiento).
-- Complementa a vw_churn_by_product (que mide cancelacion): esta mide
-- adopcion (suscripciones activas) e ingreso por plan. CTEs separados por
-- subscription/invoice_item para evitar fan-out (join directo de dos
-- tablas "many" al mismo grano de producto duplicaria filas y agrandaria
-- el ingreso -- ver docs/decisiones.md #27).
CREATE OR REPLACE VIEW gold.vw_revenue_by_plan AS
WITH subs AS (
    SELECT product_id, count(*) FILTER (WHERE is_active) AS suscripciones_activas
    FROM gold.fact_subscription
    GROUP BY product_id
),
revenue AS (
    SELECT product_id, SUM(line_total) AS ingreso_total
    FROM gold.fact_invoice_item
    GROUP BY product_id
)
SELECT
    p.product_id,
    p.name,
    p.category,
    p.monthly_price,
    COALESCE(subs.suscripciones_activas, 0) AS suscripciones_activas,
    COALESCE(revenue.ingreso_total, 0) AS ingreso_total
FROM gold.dim_product p
LEFT JOIN subs ON subs.product_id = p.product_id
LEFT JOIN revenue ON revenue.product_id = p.product_id
ORDER BY ingreso_total DESC NULLS LAST;

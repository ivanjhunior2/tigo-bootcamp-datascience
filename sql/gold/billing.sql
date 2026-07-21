-- Gold: estrella de facturacion (billing)
-- Requiere que gold.dim_student ya exista (sql/gold/university.sql corrido
-- antes) por el bridge dim_customer.student_id.

-- ============================================================
-- Dimensiones
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.dim_customer (
    customer_id  TEXT PRIMARY KEY,
    first_name   TEXT NOT NULL,
    last_name    TEXT NOT NULL,
    email        TEXT NOT NULL,
    country      TEXT NOT NULL,
    segment      TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL,
    is_student   BOOLEAN NOT NULL,
    student_id   TEXT REFERENCES gold.dim_student(student_id)  -- bridge; NULL si no es estudiante
);

TRUNCATE TABLE gold.dim_customer CASCADE;
INSERT INTO gold.dim_customer
SELECT
    customer_id, first_name, last_name, email, country, segment, created_at,
    external_ref IS NOT NULL,
    external_ref
FROM silver.billing__customers;

CREATE TABLE IF NOT EXISTS gold.dim_product (
    product_id     TEXT PRIMARY KEY,
    sku            TEXT NOT NULL,
    name           TEXT NOT NULL,
    category       TEXT NOT NULL,
    monthly_price  NUMERIC NOT NULL,
    active         BOOLEAN NOT NULL
);

TRUNCATE TABLE gold.dim_product CASCADE;
INSERT INTO gold.dim_product
SELECT product_id, sku, name, category, monthly_price, active
FROM silver.billing__products;

-- ============================================================
-- fact_invoice: grano = 1 fila por factura.
-- Rol de fecha doble: issued_date_id / due_date_id, ambas contra dim_date.
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_invoice (
    invoice_id       TEXT PRIMARY KEY,
    customer_id      TEXT NOT NULL REFERENCES gold.dim_customer(customer_id),
    issued_date_id   DATE NOT NULL REFERENCES gold.dim_date(date_day),
    due_date_id      DATE NOT NULL REFERENCES gold.dim_date(date_day),
    status           TEXT NOT NULL,
    currency         TEXT NOT NULL,
    total            NUMERIC NOT NULL,
    is_paid          BOOLEAN NOT NULL,
    is_overdue       BOOLEAN NOT NULL,
    days_to_due      INT NOT NULL
);

TRUNCATE TABLE gold.fact_invoice CASCADE;
INSERT INTO gold.fact_invoice
SELECT
    invoice_id, customer_id, issued_at, due_at, status, currency, total,
    status = 'paid',
    status = 'overdue',
    (due_at - issued_at)
FROM silver.billing__invoices;

-- ============================================================
-- fact_invoice_item: grano = 1 fila por linea de factura.
-- customer_id / issued_date_id denormalizados directo desde fact_invoice
-- (no solo invoice_id): asi se puede filtrar/agrupar por cliente o fecha
-- sin saltar por fact_invoice primero -- ver docs/decisiones.md #20.
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_invoice_item (
    invoice_item_id  TEXT PRIMARY KEY,
    invoice_id       TEXT NOT NULL REFERENCES gold.fact_invoice(invoice_id),
    customer_id      TEXT NOT NULL REFERENCES gold.dim_customer(customer_id),
    product_id       TEXT NOT NULL REFERENCES gold.dim_product(product_id),
    issued_date_id   DATE NOT NULL REFERENCES gold.dim_date(date_day),
    quantity         INT NOT NULL,
    unit_price       NUMERIC NOT NULL,
    line_total       NUMERIC NOT NULL
);

TRUNCATE TABLE gold.fact_invoice_item CASCADE;
INSERT INTO gold.fact_invoice_item
SELECT
    ii.invoice_item_id, ii.invoice_id, i.customer_id, ii.product_id, i.issued_date_id,
    ii.quantity, ii.unit_price, ii.line_total
FROM silver.billing__invoice_items ii
JOIN gold.fact_invoice i ON i.invoice_id = ii.invoice_id;

-- ============================================================
-- fact_payment: grano = 1 fila por pago. days_to_pay = dias entre
-- issued_at de la factura y paid_at del pago (indicador de cobranza).
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_payment (
    payment_id     TEXT PRIMARY KEY,
    invoice_id     TEXT NOT NULL REFERENCES gold.fact_invoice(invoice_id),
    customer_id    TEXT NOT NULL REFERENCES gold.dim_customer(customer_id),
    paid_date_id   DATE NOT NULL REFERENCES gold.dim_date(date_day),
    method         TEXT NOT NULL,
    amount         NUMERIC NOT NULL,
    days_to_pay    INT NOT NULL
);

TRUNCATE TABLE gold.fact_payment CASCADE;
INSERT INTO gold.fact_payment
SELECT
    p.payment_id, p.invoice_id, i.customer_id, p.paid_at::DATE, p.method, p.amount,
    (p.paid_at::DATE - i.issued_at)
FROM silver.billing__payments p
JOIN silver.billing__invoices i ON i.invoice_id = p.invoice_id;

-- ============================================================
-- fact_subscription: grano = 1 fila por suscripcion (snapshot, no MRR
-- mensual explotado -- ver docs/decisiones.md). end_date_id nullable:
-- silver ya anulo end_date cuando start_date > end_date.
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_subscription (
    subscription_id  TEXT PRIMARY KEY,
    customer_id      TEXT NOT NULL REFERENCES gold.dim_customer(customer_id),
    product_id       TEXT NOT NULL REFERENCES gold.dim_product(product_id),
    start_date_id    DATE NOT NULL REFERENCES gold.dim_date(date_day),
    end_date_id      DATE REFERENCES gold.dim_date(date_day),
    status           TEXT NOT NULL,
    is_active        BOOLEAN NOT NULL,
    is_cancelled     BOOLEAN NOT NULL,
    duration_days    INT
);

TRUNCATE TABLE gold.fact_subscription CASCADE;
INSERT INTO gold.fact_subscription
SELECT
    subscription_id, customer_id, product_id, start_date, end_date, status,
    status = 'active',
    status = 'cancelled',
    CASE WHEN end_date IS NULL THEN NULL ELSE (end_date - start_date) END
FROM silver.billing__subscriptions;

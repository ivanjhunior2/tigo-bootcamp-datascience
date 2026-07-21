-- Silver: dominio billing -- DDL explicito (PK, NOT NULL, FK).
-- Mismo criterio que sql/silver/university.sql -- ver docs/decisiones.md #22.

-- ============================================================
-- customers
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.billing__customers (
    customer_id        TEXT PRIMARY KEY,
    external_ref        TEXT,  -- nullable a proposito: 50% de clientes no son estudiantes
    first_name           TEXT NOT NULL,
    last_name             TEXT NOT NULL,
    email                  TEXT NOT NULL,
    country                 TEXT NOT NULL,
    created_at                TIMESTAMP NOT NULL,
    segment                    TEXT NOT NULL,
    _silver_loaded_at            TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- products
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.billing__products (
    product_id          TEXT PRIMARY KEY,
    sku                   TEXT NOT NULL,
    name                    TEXT NOT NULL,
    category                  TEXT NOT NULL,
    monthly_price               NUMERIC NOT NULL,
    active                         BOOLEAN NOT NULL,
    _silver_loaded_at                TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- subscriptions
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.billing__subscriptions (
    subscription_id         TEXT PRIMARY KEY,
    customer_id               TEXT NOT NULL REFERENCES silver.billing__customers(customer_id),
    product_id                  TEXT NOT NULL REFERENCES silver.billing__products(product_id),
    status                        TEXT NOT NULL,
    start_date                      DATE NOT NULL,
    end_date                          DATE,  -- nullable: anulado cuando start_date > end_date
    _end_date_invalidated                BOOLEAN NOT NULL,
    _silver_loaded_at                        TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- invoices
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.billing__invoices (
    invoice_id           TEXT PRIMARY KEY,
    customer_id            TEXT NOT NULL REFERENCES silver.billing__customers(customer_id),
    issued_at                 DATE NOT NULL,
    due_at                     DATE NOT NULL,
    total                        NUMERIC NOT NULL,
    status                         TEXT NOT NULL,
    currency                         TEXT NOT NULL,
    _silver_loaded_at                  TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- invoice_items
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.billing__invoice_items (
    invoice_item_id        TEXT PRIMARY KEY,
    invoice_id                TEXT NOT NULL REFERENCES silver.billing__invoices(invoice_id),
    product_id                   TEXT NOT NULL REFERENCES silver.billing__products(product_id),
    quantity                        INT NOT NULL,
    unit_price                         NUMERIC NOT NULL,
    line_total                            NUMERIC NOT NULL,
    _silver_loaded_at                        TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- payments
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.billing__payments (
    payment_id          TEXT PRIMARY KEY,
    invoice_id             TEXT NOT NULL REFERENCES silver.billing__invoices(invoice_id),
    amount                    NUMERIC NOT NULL,
    method                       TEXT NOT NULL,
    paid_at                        TIMESTAMP NOT NULL,
    _silver_loaded_at                 TIMESTAMPTZ NOT NULL
);

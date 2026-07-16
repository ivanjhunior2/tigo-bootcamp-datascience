-- Bronze: dominio billing (fuente: billing/*.csv)
-- Todas las columnas se cargan como TEXT: bronze no tipa ni limpia, solo
-- preserva el dato crudo tal como llega. Tipado/limpieza es trabajo de silver.

CREATE TABLE IF NOT EXISTS bronze.billing__customers (
    customer_id   TEXT,
    external_ref  TEXT,
    first_name    TEXT,
    last_name     TEXT,
    email         TEXT,
    country       TEXT,
    created_at    TEXT,
    segment       TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.billing__products (
    product_id    TEXT,
    sku           TEXT,
    name          TEXT,
    category      TEXT,
    monthly_price TEXT,
    active        TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.billing__subscriptions (
    subscription_id TEXT,
    status          TEXT,
    start_date      TEXT,
    end_date        TEXT,
    customer_id     TEXT,
    product_id      TEXT,
    _source_file    TEXT,
    _ingested_at    TIMESTAMP,
    _dag_run_id     TEXT
);

CREATE TABLE IF NOT EXISTS bronze.billing__invoices (
    invoice_id    TEXT,
    issued_at     TEXT,
    due_at        TEXT,
    total         TEXT,
    status        TEXT,
    currency      TEXT,
    customer_id   TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.billing__invoice_items (
    invoice_item_id TEXT,
    quantity        TEXT,
    unit_price      TEXT,
    line_total      TEXT,
    invoice_id      TEXT,
    product_id      TEXT,
    _source_file    TEXT,
    _ingested_at    TIMESTAMP,
    _dag_run_id     TEXT
);

CREATE TABLE IF NOT EXISTS bronze.billing__payments (
    payment_id    TEXT,
    amount        TEXT,
    paid_at       TEXT,
    method        TEXT,
    invoice_id    TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

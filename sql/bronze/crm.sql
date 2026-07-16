-- Bronze: dominio crm (fuente: crm/*.csv)
-- Todas las columnas se cargan como TEXT: bronze no tipa ni limpia, solo
-- preserva el dato crudo tal como llega. Tipado/limpieza es trabajo de silver.

CREATE TABLE IF NOT EXISTS bronze.crm__accounts (
    account_id     TEXT,
    name           TEXT,
    industry       TEXT,
    country        TEXT,
    annual_revenue TEXT,
    employees      TEXT,
    created_at     TEXT,
    _source_file   TEXT,
    _ingested_at   TIMESTAMP,
    _dag_run_id    TEXT
);

CREATE TABLE IF NOT EXISTS bronze.crm__contacts (
    contact_id    TEXT,
    first_name    TEXT,
    last_name     TEXT,
    email         TEXT,
    phone         TEXT,
    title         TEXT,
    created_at    TEXT,
    account_id    TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.crm__leads (
    lead_id       TEXT,
    first_name    TEXT,
    last_name     TEXT,
    email         TEXT,
    source        TEXT,
    status        TEXT,
    score         TEXT,
    created_at    TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.crm__opportunities (
    opportunity_id TEXT,
    name           TEXT,
    stage          TEXT,
    amount         TEXT,
    close_date     TEXT,
    created_at     TEXT,
    account_id     TEXT,
    _source_file   TEXT,
    _ingested_at   TIMESTAMP,
    _dag_run_id    TEXT
);

CREATE TABLE IF NOT EXISTS bronze.crm__opportunity_contacts (
    opportunity_id TEXT,
    contact_id     TEXT,
    role           TEXT,
    _source_file   TEXT,
    _ingested_at   TIMESTAMP,
    _dag_run_id    TEXT
);

CREATE TABLE IF NOT EXISTS bronze.crm__activities (
    activity_id    TEXT,
    type           TEXT,
    subject        TEXT,
    occurred_at    TEXT,
    contact_id     TEXT,
    opportunity_id TEXT,
    _source_file   TEXT,
    _ingested_at   TIMESTAMP,
    _dag_run_id    TEXT
);

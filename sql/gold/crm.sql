-- Gold: estrella comercial (crm)
-- leads no tiene FK hacia accounts/opportunities en la fuente -- se modela
-- como mart independiente (fact_lead) en vez de forzar un join no confiable
-- (ver docs/decisiones.md).

-- ============================================================
-- Dimensiones
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.dim_account (
    account_id      TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    industry        TEXT NOT NULL,
    country         TEXT NOT NULL,
    annual_revenue  NUMERIC NOT NULL,
    employees       INT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL
);

TRUNCATE TABLE gold.dim_account CASCADE;
INSERT INTO gold.dim_account
SELECT account_id, name, industry, country, annual_revenue, employees, created_at
FROM silver.crm__accounts;

CREATE TABLE IF NOT EXISTS gold.dim_contact (
    contact_id  TEXT PRIMARY KEY,
    account_id  TEXT NOT NULL REFERENCES gold.dim_account(account_id),
    first_name  TEXT NOT NULL,
    last_name   TEXT NOT NULL,
    email       TEXT NOT NULL,
    title       TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL
);

TRUNCATE TABLE gold.dim_contact CASCADE;
INSERT INTO gold.dim_contact
SELECT contact_id, account_id, first_name, last_name, email, title, created_at
FROM silver.crm__contacts;

-- ============================================================
-- fact_opportunity: grano = 1 fila por oportunidad.
-- sales_cycle_days queda NULL cuando close_date < created_at (flag
-- _close_date_before_created de silver) -- no tiene sentido un ciclo de
-- venta negativo.
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_opportunity (
    opportunity_id       TEXT PRIMARY KEY,
    account_id           TEXT NOT NULL REFERENCES gold.dim_account(account_id),
    created_date_id      DATE NOT NULL REFERENCES gold.dim_date(date_day),
    close_date_id        DATE NOT NULL REFERENCES gold.dim_date(date_day),
    stage                TEXT NOT NULL,
    amount               NUMERIC NOT NULL,
    is_won               BOOLEAN NOT NULL,
    is_lost              BOOLEAN NOT NULL,
    is_open              BOOLEAN NOT NULL,
    close_date_before_created BOOLEAN NOT NULL,
    sales_cycle_days     INT
);

TRUNCATE TABLE gold.fact_opportunity CASCADE;
INSERT INTO gold.fact_opportunity
SELECT
    opportunity_id, account_id, created_at::DATE, close_date, stage, amount,
    stage = 'won',
    stage = 'lost',
    stage NOT IN ('won', 'lost'),
    _close_date_before_created,
    CASE WHEN _close_date_before_created THEN NULL ELSE (close_date - created_at::DATE) END
FROM silver.crm__opportunities;

-- ============================================================
-- fact_activity: grano = 1 fila por actividad. contact_id/opportunity_id
-- nullable a proposito (FKs opcionales, ver docs/calidad_datos.md).
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_activity (
    activity_id      TEXT PRIMARY KEY,
    contact_id       TEXT REFERENCES gold.dim_contact(contact_id),
    opportunity_id   TEXT REFERENCES gold.fact_opportunity(opportunity_id),
    occurred_date_id DATE NOT NULL REFERENCES gold.dim_date(date_day),
    type             TEXT NOT NULL,
    subject          TEXT NOT NULL
);

TRUNCATE TABLE gold.fact_activity CASCADE;
INSERT INTO gold.fact_activity
SELECT activity_id, contact_id, opportunity_id, occurred_at::DATE, type, subject
FROM silver.crm__activities;

-- ============================================================
-- fact_lead: mart independiente, sin FK hacia el resto de la estrella
-- comercial (la fuente no vincula leads con accounts/opportunities).
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_lead (
    lead_id           TEXT PRIMARY KEY,
    created_date_id   DATE NOT NULL REFERENCES gold.dim_date(date_day),
    source            TEXT NOT NULL,
    status            TEXT NOT NULL,
    score             INT NOT NULL,
    is_converted      BOOLEAN NOT NULL
);

TRUNCATE TABLE gold.fact_lead CASCADE;
INSERT INTO gold.fact_lead
SELECT lead_id, created_at::DATE, source, status, score, status = 'converted'
FROM silver.crm__leads;

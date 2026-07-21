-- Silver: dominio crm -- DDL explicito (PK, NOT NULL, FK).
-- Mismo criterio que sql/silver/university.sql -- ver docs/decisiones.md #22.

-- ============================================================
-- accounts
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.crm__accounts (
    account_id          TEXT PRIMARY KEY,
    name                  TEXT NOT NULL,
    industry                TEXT NOT NULL,
    country                   TEXT NOT NULL,
    annual_revenue              NUMERIC NOT NULL,
    employees                      INT NOT NULL,
    created_at                        TIMESTAMP NOT NULL,
    _silver_loaded_at                    TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- contacts
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.crm__contacts (
    contact_id           TEXT PRIMARY KEY,
    account_id              TEXT NOT NULL REFERENCES silver.crm__accounts(account_id),
    first_name                 TEXT NOT NULL,
    last_name                     TEXT NOT NULL,
    email                            TEXT NOT NULL,
    phone                               TEXT NOT NULL,
    title                                  TEXT NOT NULL,
    created_at                                TIMESTAMP NOT NULL,
    _silver_loaded_at                             TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- leads (sin FK -- fuente no lo provee, ver docs/decisiones.md #12)
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.crm__leads (
    lead_id              TEXT PRIMARY KEY,
    first_name              TEXT NOT NULL,
    last_name                  TEXT NOT NULL,
    email                          TEXT NOT NULL,
    source                            TEXT NOT NULL,
    status                               TEXT NOT NULL,
    score                                   INT NOT NULL,
    created_at                                 TIMESTAMP NOT NULL,
    _silver_loaded_at                              TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- opportunities
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.crm__opportunities (
    opportunity_id                TEXT PRIMARY KEY,
    account_id                       TEXT NOT NULL REFERENCES silver.crm__accounts(account_id),
    name                                 TEXT NOT NULL,
    stage                                   TEXT NOT NULL,
    amount                                     NUMERIC NOT NULL,
    created_at                                     TIMESTAMP NOT NULL,
    close_date                                        DATE NOT NULL,
    _close_date_before_created                           BOOLEAN NOT NULL,
    _silver_loaded_at                                        TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- opportunity_contacts (tabla puente N:N, PK compuesta)
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.crm__opportunity_contacts (
    opportunity_id      TEXT NOT NULL REFERENCES silver.crm__opportunities(opportunity_id),
    contact_id             TEXT NOT NULL REFERENCES silver.crm__contacts(contact_id),
    role                      TEXT NOT NULL,
    _silver_loaded_at            TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (opportunity_id, contact_id)
);

-- ============================================================
-- activities (contact_id/opportunity_id nullable a proposito --
-- FKs opcionales, ver docs/calidad_datos.md)
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.crm__activities (
    activity_id          TEXT PRIMARY KEY,
    type                    TEXT NOT NULL,
    subject                   TEXT NOT NULL,
    occurred_at                  TIMESTAMP NOT NULL,
    contact_id                      TEXT REFERENCES silver.crm__contacts(contact_id),
    opportunity_id                     TEXT REFERENCES silver.crm__opportunities(opportunity_id),
    _silver_loaded_at                      TIMESTAMPTZ NOT NULL
);

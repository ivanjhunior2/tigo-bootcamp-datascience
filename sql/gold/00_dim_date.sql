-- Gold: dim_date -- conformada, compartida por las 3 estrellas.
-- Rango cubre todas las fechas reales de los datos (2018-2027) con margen
-- (2015-2028) para comparaciones interanuales sin quedarse corto en los bordes.

CREATE TABLE IF NOT EXISTS gold.dim_date (
    date_day     DATE PRIMARY KEY,
    year         INT NOT NULL,
    quarter      INT NOT NULL,
    month        INT NOT NULL,
    month_name   TEXT NOT NULL,
    day          INT NOT NULL,
    day_of_week  INT NOT NULL,   -- 0=domingo ... 6=sabado (dow de Postgres)
    day_name     TEXT NOT NULL,
    is_weekend   BOOLEAN NOT NULL,
    year_month   TEXT NOT NULL   -- 'YYYY-MM', util para agrupar/graficar
);

TRUNCATE TABLE gold.dim_date CASCADE;

INSERT INTO gold.dim_date
SELECT
    d::DATE AS date_day,
    EXTRACT(YEAR FROM d)::INT,
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    TO_CHAR(d, 'Month'),
    EXTRACT(DAY FROM d)::INT,
    EXTRACT(DOW FROM d)::INT,
    TO_CHAR(d, 'Day'),
    EXTRACT(DOW FROM d) IN (0, 6),
    TO_CHAR(d, 'YYYY-MM')
FROM generate_series('2015-01-01'::DATE, '2028-12-31'::DATE, '1 day') AS d;

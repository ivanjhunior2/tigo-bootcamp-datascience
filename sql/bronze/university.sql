-- Bronze: dominio university (fuente: university/*.csv)
-- Todas las columnas se cargan como TEXT: bronze no tipa ni limpia, solo
-- preserva el dato crudo tal como llega. Tipado/limpieza es trabajo de silver.

CREATE TABLE IF NOT EXISTS bronze.university__semesters (
    semester_id   TEXT,
    code          TEXT,
    year          TEXT,
    half          TEXT,
    start_date    TEXT,
    end_date      TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.university__professors (
    professor_id  TEXT,
    first_name    TEXT,
    last_name     TEXT,
    email         TEXT,
    department    TEXT,
    hired_at      TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.university__students (
    student_id    TEXT,
    first_name    TEXT,
    last_name     TEXT,
    email         TEXT,
    birth_date    TEXT,
    enrolled_at   TEXT,
    country       TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.university__courses (
    course_id     TEXT,
    code          TEXT,
    name          TEXT,
    credits       TEXT,
    department    TEXT,
    professor_id  TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.university__enrollments (
    enrollment_id TEXT,
    enrolled_at   TEXT,
    status        TEXT,
    student_id    TEXT,
    course_id     TEXT,
    semester_id   TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

CREATE TABLE IF NOT EXISTS bronze.university__grades (
    grade_id      TEXT,
    assessment    TEXT,
    score         TEXT,
    weight        TEXT,
    graded_at     TEXT,
    enrollment_id TEXT,
    _source_file  TEXT,
    _ingested_at  TIMESTAMP,
    _dag_run_id   TEXT
);

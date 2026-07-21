-- Silver: dominio university -- DDL explicito (PK, NOT NULL, FK).
--
-- La limpieza sigue siendo pandas dentro del notebook (ver
-- notebooks/university/*.ipynb) -- esto solo define el esquema que antes
-- generaba automatico pandas.to_sql(), que no declara PK/NOT NULL/FK. El
-- notebook ejecuta este archivo (igual patron que bronze/gold) y despues
-- hace TRUNCATE + INSERT con el dataframe ya limpio. Ver docs/decisiones.md
-- #22.
--
-- Se va completando tabla por tabla a medida que se retrofitea cada
-- notebook (empezando por students, la mas simple).

-- ============================================================
-- students
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.university__students (
    student_id         TEXT PRIMARY KEY,
    first_name         TEXT NOT NULL,
    last_name          TEXT NOT NULL,
    email              TEXT NOT NULL,
    birth_date         DATE NOT NULL,
    enrolled_at        DATE NOT NULL,
    country            TEXT NOT NULL,
    _silver_loaded_at  TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- professors
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.university__professors (
    professor_id       TEXT PRIMARY KEY,
    first_name         TEXT NOT NULL,
    last_name          TEXT NOT NULL,
    email              TEXT NOT NULL,
    department         TEXT NOT NULL,
    hired_at           DATE NOT NULL,
    _silver_loaded_at  TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- courses
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.university__courses (
    course_id          TEXT PRIMARY KEY,
    code               TEXT NOT NULL,
    name               TEXT NOT NULL,
    credits            INT NOT NULL,
    department         TEXT NOT NULL,
    professor_id       TEXT NOT NULL REFERENCES silver.university__professors(professor_id),
    _silver_loaded_at  TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- semesters
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.university__semesters (
    semester_id        TEXT PRIMARY KEY,
    code               TEXT NOT NULL,
    year               INT NOT NULL,
    half               INT NOT NULL,
    start_date         DATE NOT NULL,
    end_date           DATE NOT NULL,
    _silver_loaded_at  TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- enrollments
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.university__enrollments (
    enrollment_id      TEXT PRIMARY KEY,
    student_id         TEXT NOT NULL REFERENCES silver.university__students(student_id),
    course_id          TEXT NOT NULL REFERENCES silver.university__courses(course_id),
    semester_id        TEXT NOT NULL REFERENCES silver.university__semesters(semester_id),
    status             TEXT NOT NULL,
    enrolled_at        DATE NOT NULL,
    _silver_loaded_at  TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- grades
-- ============================================================
CREATE TABLE IF NOT EXISTS silver.university__grades (
    grade_id           TEXT PRIMARY KEY,
    enrollment_id      TEXT NOT NULL REFERENCES silver.university__enrollments(enrollment_id),
    assessment         TEXT NOT NULL,
    score              NUMERIC NOT NULL,
    weight             NUMERIC NOT NULL,
    graded_at          DATE NOT NULL,
    _silver_loaded_at  TIMESTAMPTZ NOT NULL
);

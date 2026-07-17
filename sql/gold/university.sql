-- Gold: estrella academica (university)
-- Llaves naturales (student_id, course_id, etc.) como PK de las dimensiones --
-- no se generan surrogate keys: full-refresh sin necesidad de trackear
-- historia (SCD). Ver docs/decisiones.md.

-- ============================================================
-- Dimensiones
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.dim_student (
    student_id   TEXT PRIMARY KEY,
    first_name   TEXT NOT NULL,
    last_name    TEXT NOT NULL,
    email        TEXT NOT NULL,
    birth_date   DATE NOT NULL,
    country      TEXT NOT NULL,
    enrolled_at  DATE NOT NULL
);

TRUNCATE TABLE gold.dim_student CASCADE;
INSERT INTO gold.dim_student
SELECT student_id, first_name, last_name, email, birth_date, country, enrolled_at
FROM silver.university__students;

CREATE TABLE IF NOT EXISTS gold.dim_professor (
    professor_id TEXT PRIMARY KEY,
    first_name   TEXT NOT NULL,
    last_name    TEXT NOT NULL,
    email        TEXT NOT NULL,
    department   TEXT NOT NULL,
    hired_at     DATE NOT NULL
);

TRUNCATE TABLE gold.dim_professor CASCADE;
INSERT INTO gold.dim_professor
SELECT professor_id, first_name, last_name, email, department, hired_at
FROM silver.university__professors;

CREATE TABLE IF NOT EXISTS gold.dim_semester (
    semester_id  TEXT PRIMARY KEY,
    code         TEXT NOT NULL,
    year         INT NOT NULL,
    half         INT NOT NULL,
    start_date   DATE NOT NULL,
    end_date     DATE NOT NULL
);

TRUNCATE TABLE gold.dim_semester CASCADE;
INSERT INTO gold.dim_semester
SELECT semester_id, code, year, half, start_date, end_date
FROM silver.university__semesters;

CREATE TABLE IF NOT EXISTS gold.dim_course (
    course_id           TEXT PRIMARY KEY,
    code                TEXT NOT NULL,
    name                TEXT NOT NULL,
    credits             INT NOT NULL,
    department          TEXT NOT NULL,
    professor_id        TEXT NOT NULL REFERENCES gold.dim_professor(professor_id),
    professor_department TEXT NOT NULL  -- denormalizado a proposito: course.department != professor.department (ver docs/calidad_datos.md), se exponen ambos
);

TRUNCATE TABLE gold.dim_course CASCADE;
INSERT INTO gold.dim_course
SELECT c.course_id, c.code, c.name, c.credits, c.department, c.professor_id, p.department
FROM silver.university__courses c
JOIN silver.university__professors p ON p.professor_id = c.professor_id;

-- ============================================================
-- fact_enrollment: grano = 1 fila por inscripcion.
-- Incluye rollup de notas (promedio ponderado, aprobacion) porque tiene la
-- misma cardinalidad que enrollment_id -- no amerita una segunda tabla.
-- Asuncion: aprueba si avg_score ponderado >= 60 (no viene dado por la fuente,
-- documentado en docs/decisiones.md).
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_enrollment (
    enrollment_id     TEXT PRIMARY KEY,
    student_id        TEXT NOT NULL REFERENCES gold.dim_student(student_id),
    course_id         TEXT NOT NULL REFERENCES gold.dim_course(course_id),
    semester_id       TEXT NOT NULL REFERENCES gold.dim_semester(semester_id),
    enrolled_date_id  DATE NOT NULL REFERENCES gold.dim_date(date_day),
    status            TEXT NOT NULL,
    num_assessments   INT NOT NULL,
    avg_score         NUMERIC,
    is_passing        BOOLEAN
);

TRUNCATE TABLE gold.fact_enrollment CASCADE;
INSERT INTO gold.fact_enrollment
SELECT
    e.enrollment_id,
    e.student_id,
    e.course_id,
    e.semester_id,
    e.enrolled_at,
    e.status,
    COALESCE(g.num_assessments, 0),
    g.avg_score,
    CASE WHEN g.avg_score IS NULL THEN NULL ELSE g.avg_score >= 60 END
FROM silver.university__enrollments e
LEFT JOIN (
    SELECT
        enrollment_id,
        COUNT(*) AS num_assessments,
        SUM(score * weight) / NULLIF(SUM(weight), 0) AS avg_score
    FROM silver.university__grades
    GROUP BY enrollment_id
) g ON g.enrollment_id = e.enrollment_id;

-- ============================================================
-- fact_grade: grano = 1 fila por calificacion individual (mas fino que
-- fact_enrollment) -- util para analisis por tipo de evaluacion.
-- ============================================================

CREATE TABLE IF NOT EXISTS gold.fact_grade (
    grade_id        TEXT PRIMARY KEY,
    enrollment_id   TEXT NOT NULL REFERENCES gold.fact_enrollment(enrollment_id),
    graded_date_id  DATE NOT NULL REFERENCES gold.dim_date(date_day),
    assessment      TEXT NOT NULL,
    score           NUMERIC NOT NULL,
    weight          NUMERIC NOT NULL
);

TRUNCATE TABLE gold.fact_grade CASCADE;
INSERT INTO gold.fact_grade
SELECT grade_id, enrollment_id, graded_at, assessment, score, weight
FROM silver.university__grades;

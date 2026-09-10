-- ═══════════════════════════════════════════════════════════════════════════
-- V077 — the CBT question bank
--
--   Questions authored per course, each with its options, the correct answer,
--   a topic and a difficulty, so a paper can be assembled to a blueprint (so many
--   from each topic and difficulty) rather than picked by hand. A question is
--   retired, not deleted, so a paper that used it can still be explained.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE assessment.question (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_code  text NOT NULL REFERENCES catalogue.course(code),
    topic        text NULL,
    stem         text NOT NULL,
    options      jsonb NOT NULL,
    answer       int NOT NULL,
    difficulty   text NOT NULL DEFAULT 'MEDIUM',
    marks        int NOT NULL DEFAULT 1,
    active       boolean NOT NULL DEFAULT true,
    authored_at  timestamptz NOT NULL DEFAULT now(),
    authored_by  uuid NULL,
    CONSTRAINT ck_q_difficulty CHECK (difficulty IN ('EASY','MEDIUM','HARD')),
    CONSTRAINT ck_q_marks CHECK (marks > 0),
    CONSTRAINT ck_q_stem CHECK (btrim(stem) <> ''),
    CONSTRAINT ck_q_options CHECK (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) >= 2),
    CONSTRAINT ck_q_answer CHECK (answer >= 0 AND answer < jsonb_array_length(options))
);
CREATE INDEX ix_q_course ON assessment.question (course_code, active);
SELECT audit.attach('assessment.question');

COMMIT;

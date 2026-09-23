-- ═══════════════════════════════════════════════════════════════════════════
-- V239 — each course says how its hundred marks split between CA and examination
--
--   Since V013 every score was continuous assessment out of 40 and an
--   examination out of 60, written into the check on assessment.score. Some
--   courses assess 30 and examine 70. The split is now the course's own:
--   catalogue.course.ca_max (40 unless the department says otherwise; the
--   examination is the rest of a hundred). The Head of Department sets it on
--   the department's catalogue, course by course or for a level at once.
--
--   The check on the score becomes the arithmetic (each part within a
--   hundred, the two within a hundred together); a trigger holds each new
--   mark to the split of its course, by name, so a lecturer's 35 on a 30/70
--   course is refused with the reason. A mark the old portal imported whole
--   is not judged.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE catalogue.course
    ADD COLUMN ca_max int NOT NULL DEFAULT 40
    CONSTRAINT ck_course_ca_max CHECK (ca_max BETWEEN 0 AND 100);

COMMENT ON COLUMN catalogue.course.ca_max IS
  'The continuous-assessment share of the hundred marks (40 unless the department sets it); the examination is the rest.';

ALTER TABLE assessment.score DROP CONSTRAINT ck_score_range;
ALTER TABLE assessment.score ADD CONSTRAINT ck_score_range CHECK (
    (ca IS NULL OR ca BETWEEN 0 AND 100) AND (exam IS NULL OR exam BETWEEN 0 AND 100)
    AND (ca IS NULL OR exam IS NULL OR ca + exam <= 100));

CREATE OR REPLACE FUNCTION assessment.score_within_split()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_code text; v_ca_max int;
BEGIN
    IF NEW.imported THEN RETURN NEW; END IF;
    SELECT c.code, c.ca_max INTO v_code, v_ca_max
      FROM assessment.score_sheet s
      JOIN catalogue.offering o ON o.id = s.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
     WHERE s.id = NEW.sheet_id;
    IF NEW.ca IS NOT NULL AND NEW.ca > v_ca_max THEN
        RAISE EXCEPTION 'continuous assessment in % is out of %, not %', v_code, v_ca_max, NEW.ca
            USING ERRCODE = '23514',
                  HINT = format('This course assesses %s and examines %s. Enter the CA out of %s.', v_ca_max, 100 - v_ca_max, v_ca_max);
    END IF;
    IF NEW.exam IS NOT NULL AND NEW.exam > 100 - v_ca_max THEN
        RAISE EXCEPTION 'the examination in % is out of %, not %', v_code, 100 - v_ca_max, NEW.exam
            USING ERRCODE = '23514',
                  HINT = format('This course assesses %s and examines %s. Enter the examination out of %s.', v_ca_max, 100 - v_ca_max, 100 - v_ca_max);
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_score_within_split ON assessment.score;
CREATE TRIGGER trg_score_within_split
    BEFORE INSERT ON assessment.score
    FOR EACH ROW EXECUTE FUNCTION assessment.score_within_split();

COMMENT ON FUNCTION assessment.score_within_split() IS
  'A new mark is held to its course''s CA/examination split (catalogue.course.ca_max); an imported total is not judged.';

COMMIT;

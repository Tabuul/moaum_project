-- V368: course uploads keep the GST/EPS classification and a course given back; what the reclassification moved, listed for
--       the offices; the old-portal GST reconciliation reads refunds by the payment they refund.
--
-- 1  The upload keeps it. The catalogue upload read a row's GST/EPS classification as "GST" whichever it was, so an EPS
--    course with a GST-looking code landed with the GST office; and both uploads made a course of kind GST again whenever a
--    row gave it status G or a GST classification — undoing a course an office had given back to its department. Now an
--    EPS classification files the course under the EPS office; a course given back carries general_released_at, and no
--    upload or edit makes it general again — only an office claiming it, which clears the mark; its programme bindings stay Core.
-- 2  What moved, listed. catalogue.general_reclassification keeps every change of a course's office or of its being a general
--    course — filled once from the audit record with what V367 moved, and from here by the change itself, naming its cause
--    (the rule, a claim, a course given back, a family, an upload, an edit). The GST and EPS offices see the moves that
--    touch them on their courses page and confirm each, or take or give back the course there.
-- 3  The old-portal GST reconciliation (V323) asked "is the student's GST payment refunded?" by the refund's own RF- number,
--    as the entitlement did until V367; it now asks by the payment the refund names (source_reference), so a student whose
--    earlier payment was refunded is not refused an old-portal payment as a duplicate.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V368: uploads keep the GST/EPS classification; what V367 moved, listed; legacy refunds by source', true);

-- ── 1 · a course given back stays its department's ──────────────────────────────────────────────────────────────

ALTER TABLE catalogue.course ADD COLUMN general_released_at timestamptz NULL;
COMMENT ON COLUMN catalogue.course.general_released_at IS
  'V368: when an office gave the course back to its department (catalogue.return_general_course). While set, no upload or edit makes the course general again and its programme bindings stay Core; an office claiming it clears it.';

CREATE OR REPLACE FUNCTION catalogue.course_general_office()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- V368: a course given back to its department stays its department's: an upload's status G or GST classification does not make it general again
    IF TG_OP = 'UPDATE' AND OLD.general_released_at IS NOT NULL AND NEW.general_released_at IS NOT NULL AND NEW.kind = 'GST' AND OLD.kind <> 'GST' THEN
        NEW.kind := OLD.kind;
    END IF;
    IF NEW.kind <> 'GST' THEN
        NEW.general_office := NULL;
    ELSIF NEW.general_office IS NULL THEN
        NEW.general_office := catalogue.general_office_of(NEW.code, NEW.title, NEW.kind);
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION catalogue.course_offer_released()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.basis = 'GST' AND EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = NEW.course_code AND c.kind <> 'GST' AND c.general_released_at IS NOT NULL) THEN
        NEW.basis := 'Core';
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_course_offer_released ON catalogue.course_offer;
CREATE TRIGGER trg_course_offer_released BEFORE INSERT OR UPDATE OF basis ON catalogue.course_offer
    FOR EACH ROW EXECUTE FUNCTION catalogue.course_offer_released();

-- ── 2 · every move of a course between the offices and its department, kept and listed ─────────────────────────

CREATE TABLE catalogue.general_reclassification (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_code      text NOT NULL REFERENCES catalogue.course(code) ON DELETE CASCADE ON UPDATE CASCADE,
    before_office    text NULL,
    after_office     text NULL,
    before_kind      text NULL,
    after_kind       text NOT NULL,
    cause            text NOT NULL CHECK (cause IN ('RULE', 'CLAIM', 'RETURN', 'FAMILY', 'UPLOAD', 'EDIT')),
    reason           text NULL,
    changed_by       uuid NULL,
    changed_office   text NULL,
    changed_at       timestamptz NOT NULL DEFAULT now(),
    confirmed_by     uuid NULL,
    confirmed_office text NULL,
    confirmed_at     timestamptz NULL
);
COMMENT ON TABLE catalogue.general_reclassification IS
  'V368: each change of a course''s office (GST, EPS or none) or of its being a general course, with its cause — the V367 rule (backfilled from the audit), an office''s claim, a course given back, a family, an upload or an edit — and whether the office it touches confirmed it.';
CREATE INDEX ix_general_reclass_course ON catalogue.general_reclassification (course_code, changed_at DESC);
CREATE INDEX ix_general_reclass_open ON catalogue.general_reclassification (changed_at DESC) WHERE confirmed_at IS NULL;
SELECT audit.attach('catalogue.general_reclassification');
GRANT SELECT ON catalogue.general_reclassification TO app_auditor;

-- what V367 (and anything since) moved, from the audit record: V367 shipped on 8 October 2026
INSERT INTO catalogue.general_reclassification (course_code, before_office, after_office, before_kind, after_kind, cause, reason, changed_by, changed_office, changed_at)
SELECT c.code, e.before_state->>'general_office', e.after_state->>'general_office', e.before_state->>'kind', coalesce(e.after_state->>'kind', c.kind),
       CASE WHEN e.reason LIKE 'V367:%' THEN 'RULE' WHEN e.reason LIKE 'Course catalogue upload%' THEN 'UPLOAD' ELSE 'EDIT' END,
       e.reason, nullif(e.actor_id, '00000000-0000-0000-0000-000000000000'::uuid), e.actor_office, e.occurred_at
  FROM audit.entries e
  JOIN catalogue.course c ON c.code = e.after_state->>'code'
 WHERE e.occurred_at >= timestamptz '2026-10-08 00:00:00+01'
   AND e.subject_type = 'catalogue.course' AND e.action = 'UPDATE'
   AND ((e.before_state->>'general_office') IS DISTINCT FROM (e.after_state->>'general_office')
        OR ((e.before_state->>'kind') = 'GST') IS DISTINCT FROM ((e.after_state->>'kind') = 'GST'));

CREATE OR REPLACE FUNCTION catalogue.course_reclassified()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.general_office IS DISTINCT FROM OLD.general_office OR (NEW.kind = 'GST') IS DISTINCT FROM (OLD.kind = 'GST') THEN
        INSERT INTO catalogue.general_reclassification (course_code, before_office, after_office, before_kind, after_kind, cause, reason, changed_by, changed_office)
        VALUES (NEW.code, OLD.general_office, NEW.general_office, OLD.kind, NEW.kind,
                coalesce(nullif(current_setting('moaum.general_cause', true), ''),
                         CASE WHEN current_setting('moaum.owner_source', true) = 'IMPORT' THEN 'UPLOAD' ELSE 'EDIT' END),
                nullif(current_setting('moaum.reason', true), ''), nullif(current_setting('moaum.actor_id', true), '')::uuid,
                nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_course_reclassified ON catalogue.course;
CREATE TRIGGER trg_course_reclassified AFTER UPDATE OF kind, general_office ON catalogue.course
    FOR EACH ROW EXECUTE FUNCTION catalogue.course_reclassified();

/* the office a move touches confirms it is right */
CREATE OR REPLACE FUNCTION catalogue.confirm_reclassification(p_id uuid)
RETURNS catalogue.general_reclassification
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; r catalogue.general_reclassification;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a move is confirmed by a person' USING ERRCODE = '23514'; END IF;
    UPDATE catalogue.general_reclassification
       SET confirmed_by = who, confirmed_office = nullif(current_setting('moaum.actor_office', true), ''), confirmed_at = now()
     WHERE id = p_id AND confirmed_at IS NULL
    RETURNING * INTO r;
    IF NOT FOUND THEN RAISE EXCEPTION 'GEN_MOVE: no unconfirmed move %', p_id USING ERRCODE = '23503'; END IF;
    RETURN r;
END $$;

-- the claim, the return and the family, as V367 left them, each naming its cause on the move it makes; a claim takes back a course given back
CREATE OR REPLACE FUNCTION catalogue.claim_general_course(p_code text, p_office text)
RETURNS catalogue.course
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := upper(btrim(coalesce(p_office, ''))); c catalogue.course;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is classified by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('GST', 'EPS') THEN RAISE EXCEPTION 'GEN_OFFICE: a general course is the GST or the EPS office''s' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF c.kind <> 'GST' AND c.general_released_at IS NULL THEN
        RAISE EXCEPTION 'GEN_NOT_GENERAL: % is a departmental course (%); its department classifies it', c.code, c.kind USING ERRCODE = '23514',
            HINT = 'A course is offered as GST/EPS through the programmes that take it (basis GST) on the catalogue.';
    END IF;
    PERFORM set_config('moaum.general_cause', 'CLAIM', true);
    UPDATE catalogue.course SET kind = 'GST', general_office = v_office, general_released_at = NULL WHERE code = c.code RETURNING * INTO c;
    PERFORM set_config('moaum.general_cause', '', true);
    UPDATE assessment.cbt_exam SET office = v_office WHERE course_code = c.code AND office IN ('GST', 'EPS', 'EXAMS') AND office <> v_office;
    RETURN c;
END $$;

CREATE OR REPLACE FUNCTION catalogue.return_general_course(p_code text, p_reason text)
RETURNS catalogue.course
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; c catalogue.course;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is classified by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'GEN_REASON: say why the course goes back to its department' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF c.kind <> 'GST' THEN RAISE EXCEPTION 'GEN_NOT_GENERAL: % is already a departmental course', c.code USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.general_cause', 'RETURN', true);
    UPDATE catalogue.course SET kind = 'Core', general_released_at = now() WHERE code = c.code RETURNING * INTO c;
    PERFORM set_config('moaum.general_cause', '', true);
    UPDATE catalogue.course_offer SET basis = 'Core' WHERE course_code = c.code AND basis = 'GST';
    UPDATE assessment.cbt_exam SET office = 'EXAMS' WHERE course_code = c.code AND office IN ('GST', 'EPS');
    RETURN c;
END $$;

CREATE OR REPLACE FUNCTION catalogue.set_general_family(p_prefix text, p_office text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_prefix text := upper(btrim(coalesce(p_prefix, ''))); v_office text := upper(nullif(btrim(coalesce(p_office, '')), '')); n int := 0;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a family is set by a person' USING ERRCODE = '23514'; END IF;
    IF v_prefix !~ '^[A-Z]{2,5}$' THEN RAISE EXCEPTION 'GEN_FAMILY: a family is the two to five letters of a course code' USING ERRCODE = '23514'; END IF;
    IF v_office IS NULL THEN
        DELETE FROM catalogue.general_family WHERE prefix = v_prefix;
        RETURN 0;
    END IF;
    IF v_office NOT IN ('GST', 'EPS') THEN RAISE EXCEPTION 'GEN_OFFICE: a family is the GST or the EPS office''s' USING ERRCODE = '23514'; END IF;
    INSERT INTO catalogue.general_family (prefix, office, added_by) VALUES (v_prefix, v_office, who)
    ON CONFLICT (prefix) DO UPDATE SET office = EXCLUDED.office, added_by = EXCLUDED.added_by, added_at = now();
    PERFORM set_config('moaum.general_cause', 'FAMILY', true);
    UPDATE catalogue.course SET general_office = v_office
     WHERE kind = 'GST' AND general_office IS NULL AND catalogue.course_subject(code) = v_prefix;
    GET DIAGNOSTICS n = ROW_COUNT;
    PERFORM set_config('moaum.general_cause', '', true);
    UPDATE assessment.cbt_exam e SET office = v_office FROM catalogue.course c
     WHERE c.code = e.course_code AND c.general_office = v_office AND catalogue.course_subject(c.code) = v_prefix AND e.office = 'EXAMS';
    RETURN n;
END $$;

-- ── 3 · the catalogue upload keeps an EPS classification ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION catalogue.import_catalogue_rows(p_rows jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
WITH raw AS (
    SELECT ord::int AS n, r AS j FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY AS t(r, ord)
), norm AS (
    SELECT n,
           nullif(btrim(coalesce(j->>'code', '')), '') AS code_raw,
           coalesce(catalogue.normal_code(j->>'code'), nullif(regexp_replace(upper(btrim(coalesce(j->>'code', ''))), '\s+', ' ', 'g'), '')) AS code,
           nullif(btrim(coalesce(j->>'title', '')), '') AS title,
           nullif(btrim(coalesce(j->>'units', '')), '') AS units_raw,
           nullif(btrim(coalesce(j->>'level', '')), '') AS level_raw,
           nullif(btrim(coalesce(j->>'semester', '')), '') AS sem_raw,
           nullif(btrim(coalesce(j->>'courseType', '')), '') AS type_raw,
           nullif(btrim(coalesce(j->>'ownerFaculty', '')), '') AS ofa_raw,
           nullif(btrim(coalesce(j->>'ownerDepartment', '')), '') AS od_raw,
           nullif(btrim(coalesce(j->>'ownerProgramme', '')), '') AS op_raw,
           nullif(btrim(coalesce(j->>'offeringFaculty', '')), '') AS ffa_raw,
           nullif(btrim(coalesce(j->>'offeringDepartment', '')), '') AS fd_raw,
           nullif(btrim(coalesce(j->>'offeringProgramme', '')), '') AS fp_raw,
           upper(nullif(btrim(coalesce(j->>'offeringType', '')), '')) AS otype_raw,
           upper(nullif(btrim(coalesce(j->>'status', '')), '')) AS status_raw,
           nullif(btrim(coalesce(j->>'session', '')), '') AS session_raw,
           nullif(btrim(coalesce(j->>'description', '')), '') AS description,
           nullif(btrim(coalesce(j->>'prerequisite', '')), '') AS prereq_raw,
           upper(nullif(btrim(coalesce(j->>'classification', '')), '')) AS class_raw,
           nullif(btrim(coalesce(j->>'remarks', '')), '') AS remarks
      FROM raw
     WHERE coalesce(btrim(j->>'code'), '') <> '' OR coalesce(btrim(j->>'title'), '') <> '' OR coalesce(btrim(j->>'offeringProgramme'), '') <> ''
), res AS (
    SELECT x.*,
           CASE WHEN x.units_raw ~ '^[0-9]{1,2}$' AND x.units_raw::int <= 12 THEN x.units_raw::int END AS units,
           CASE WHEN regexp_replace(coalesce(x.level_raw, ''), '[^0-9]', '', 'g') ~ '^[1-9]00$' THEN regexp_replace(x.level_raw, '[^0-9]', '', 'g')::int END AS level,
           CASE WHEN x.sem_raw ~* '^(1|1st|first)' THEN 1 WHEN x.sem_raw ~* '^(2|2nd|second)' THEN 2 WHEN x.sem_raw ~* '^(3|3rd|third)' THEN 3 END AS semester,
           CASE WHEN x.type_raw IS NULL THEN NULL WHEN upper(x.type_raw) = 'GST' THEN 'GST'
                WHEN upper(x.type_raw) IN ('CORE', 'COMPULSORY') THEN 'Core' WHEN upper(x.type_raw) = 'REQUIRED' THEN 'Required'
                WHEN upper(x.type_raw) = 'ELECTIVE' THEN 'Elective' END AS course_type,
           ofa.code AS ofa, od.code AS od, od.faculty_code AS od_fac, op.code AS op, op.dept_code AS op_dept,
           ffa.code AS ffa, fd.code AS fd, fp.code AS fp, fp.dept_code AS fp_dept, fp.faculty_code AS fp_fac, coalesce(fp.archived, false) AS fp_archived,
           ec.code AS existing, ec.state AS existing_state, ec.reset_batch_id AS existing_reset, ec.dept_code AS existing_dept,
           ec.owner_programme AS existing_prog, ec.general_office AS existing_office,
           EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = x.session_raw) AS session_ok
      FROM norm x
      LEFT JOIN LATERAL (SELECT f.code FROM ref.faculty f
                          WHERE x.ofa_raw IS NOT NULL AND (upper(f.code) = upper(x.ofa_raw) OR upper(f.name) = catalogue.bare_name(x.ofa_raw) OR upper(f.name) = upper(x.ofa_raw)) LIMIT 1) ofa ON true
      LEFT JOIN LATERAL (SELECT d.code, d.faculty_code FROM ref.department d
                          WHERE x.od_raw IS NOT NULL AND d.ended_on IS NULL
                            AND (upper(d.code) = upper(x.od_raw) OR upper(d.name) = catalogue.bare_name(x.od_raw) OR upper(d.name) = upper(x.od_raw)) LIMIT 1) od ON true
      LEFT JOIN LATERAL (SELECT p.code, p.dept_code FROM ref.programme p
                          WHERE x.op_raw IS NOT NULL AND NOT coalesce(p.archived, false) AND (upper(p.code) = upper(x.op_raw) OR upper(p.name) = upper(x.op_raw))
                          ORDER BY (p.dept_code = od.code) DESC NULLS LAST LIMIT 1) op ON true
      LEFT JOIN LATERAL (SELECT f.code FROM ref.faculty f
                          WHERE x.ffa_raw IS NOT NULL AND (upper(f.code) = upper(x.ffa_raw) OR upper(f.name) = catalogue.bare_name(x.ffa_raw) OR upper(f.name) = upper(x.ffa_raw)) LIMIT 1) ffa ON true
      LEFT JOIN LATERAL (SELECT d.code FROM ref.department d
                          WHERE x.fd_raw IS NOT NULL AND d.ended_on IS NULL
                            AND (upper(d.code) = upper(x.fd_raw) OR upper(d.name) = catalogue.bare_name(x.fd_raw) OR upper(d.name) = upper(x.fd_raw)) LIMIT 1) fd ON true
      LEFT JOIN LATERAL (SELECT p.code, p.dept_code, p.faculty_code, p.archived FROM ref.programme p
                          WHERE x.fp_raw IS NOT NULL AND (upper(p.code) = upper(x.fp_raw) OR upper(p.name) = upper(x.fp_raw))
                          ORDER BY coalesce(p.archived, false), (p.dept_code = fd.code) DESC NULLS LAST LIMIT 1) fp ON true
      LEFT JOIN catalogue.course ec ON ec.code = x.code
), judged AS (
    SELECT r.*,
           coalesce(r.od, r.existing_dept) AS owner_dept,
           CASE WHEN r.class_raw IN ('GST', 'EPS') THEN 'GST' WHEN r.otype_raw IN ('CORE', 'C') THEN 'Core' WHEN r.otype_raw IN ('ELECTIVE', 'E') THEN 'Elective' END AS basis,
           row_number() OVER (PARTITION BY r.code, r.fp, r.level ORDER BY r.n) AS dup_rank,
           a.titles, a.unitss, a.sems, a.owners, a.owner_progs,
           ARRAY(SELECT coalesce(catalogue.normal_code(q), regexp_replace(upper(btrim(q)), '\s+', ' ', 'g'))
                   FROM unnest(regexp_split_to_array(coalesce(r.prereq_raw, ''), '\s*[,;/]\s*')) q WHERE btrim(q) <> '') AS prereqs
      FROM res r
      JOIN (SELECT code,
                   count(DISTINCT upper(title)) FILTER (WHERE title IS NOT NULL) AS titles,
                   count(DISTINCT units) FILTER (WHERE units IS NOT NULL) AS unitss,
                   count(DISTINCT semester) FILTER (WHERE semester IS NOT NULL) AS sems,
                   count(DISTINCT od) FILTER (WHERE od IS NOT NULL) AS owners,
                   count(DISTINCT op) FILTER (WHERE op IS NOT NULL) AS owner_progs
              FROM res GROUP BY code) a ON a.code IS NOT DISTINCT FROM r.code
), checked AS (
    SELECT j.*,
           array_remove(ARRAY[
             CASE WHEN j.code_raw IS NULL THEN 'CODE_MISSING: the course code is blank'
                  WHEN j.code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN 'CODE_INVALID: ' || j.code_raw || ' is not a course code' END,
             CASE WHEN j.title IS NULL AND j.existing IS NULL THEN 'TITLE_MISSING: a new course needs its title' END,
             CASE WHEN j.units_raw IS NOT NULL AND j.units IS NULL THEN 'UNITS_INVALID: units are a whole number from 0 to 12'
                  WHEN j.units IS NULL AND j.existing IS NULL THEN 'UNITS_INVALID: a new course needs its units' END,
             CASE WHEN j.level IS NULL THEN 'LEVEL_INVALID: the level is 100 to 900' END,
             CASE WHEN j.sem_raw IS NOT NULL AND j.semester IS NULL THEN 'SEMESTER_INVALID: the semester is 1, 2 or 3'
                  WHEN j.semester IS NULL AND j.existing IS NULL THEN 'SEMESTER_INVALID: a new course needs its semester' END,
             CASE WHEN j.type_raw IS NOT NULL AND j.course_type IS NULL THEN 'COURSE_TYPE_INVALID: the course type is Core, Required, Elective or GST' END,
             CASE WHEN j.od_raw IS NULL AND j.existing IS NULL THEN 'OWNER_DEPARTMENT_MISSING: a new course needs the department that owns it'
                  WHEN j.od_raw IS NOT NULL AND j.od IS NULL THEN 'OWNER_DEPARTMENT_UNKNOWN: no live department is coded or named ' || j.od_raw END,
             CASE WHEN j.ofa_raw IS NOT NULL AND j.ofa IS NULL THEN 'OWNER_FACULTY_UNKNOWN: no faculty is coded or named ' || j.ofa_raw
                  WHEN j.ofa IS NOT NULL AND j.od IS NOT NULL AND j.od_fac IS DISTINCT FROM j.ofa THEN 'OWNER_FACULTY_MISMATCH: the owner department is not in that faculty' END,
             CASE WHEN j.op_raw IS NOT NULL AND j.op IS NULL THEN 'OWNER_PROGRAMME_UNKNOWN: no live programme is coded or named ' || j.op_raw
                  WHEN j.op IS NOT NULL AND j.op_dept IS DISTINCT FROM coalesce(j.od, j.existing_dept) THEN 'OWNER_PROGRAMME_NOT_IN_DEPARTMENT: the owner programme is not a programme of the owner department' END,
             CASE WHEN j.fp_raw IS NULL THEN 'OFFERING_PROGRAMME_MISSING: name the programme that offers the course'
                  WHEN j.fp IS NULL THEN 'OFFERING_PROGRAMME_UNKNOWN: no programme is coded or named ' || j.fp_raw
                  WHEN j.fp_archived THEN 'OFFERING_PROGRAMME_ARCHIVED: ' || j.fp || ' is archived' END,
             CASE WHEN j.fd_raw IS NOT NULL AND j.fd IS NULL THEN 'OFFERING_DEPARTMENT_UNKNOWN: no live department is coded or named ' || j.fd_raw
                  WHEN j.fd IS NOT NULL AND j.fp IS NOT NULL AND j.fp_dept IS DISTINCT FROM j.fd THEN 'OFFERING_PROGRAMME_NOT_IN_DEPARTMENT: the offering programme is not a programme of that department' END,
             CASE WHEN j.ffa_raw IS NOT NULL AND j.ffa IS NULL THEN 'OFFERING_FACULTY_UNKNOWN: no faculty is coded or named ' || j.ffa_raw
                  WHEN j.ffa IS NOT NULL AND j.fp IS NOT NULL AND j.fp_fac IS DISTINCT FROM j.ffa THEN 'OFFERING_FACULTY_MISMATCH: the offering programme is not in that faculty' END,
             CASE WHEN j.class_raw IS NOT NULL AND j.class_raw NOT IN ('GST', 'EPS') THEN 'CLASSIFICATION_INVALID: the GST/EPS classification is GST, EPS or blank'
                  WHEN j.basis IS NULL THEN 'OFFERING_TYPE_INVALID: the offering type is CORE or ELECTIVE' END,
             CASE WHEN j.status_raw IS NOT NULL AND j.status_raw NOT IN ('ACTIVE', 'INACTIVE') THEN 'STATUS_INVALID: the status is ACTIVE or INACTIVE' END,
             CASE WHEN j.session_raw IS NOT NULL AND NOT j.session_ok THEN 'SESSION_UNKNOWN: no academic session is named ' || j.session_raw END,
             CASE WHEN j.existing IS NOT NULL AND j.existing_state = 'ENDED' AND j.existing_reset IS NULL THEN 'COURSE_ENDED: ' || j.code || ' was ended on its department''s desk; restore it there first' END,
             CASE WHEN j.dup_rank > 1 THEN 'DUPLICATE_OFFERING: ' || j.code || ' is offered to ' || j.fp || ' at ' || j.level || ' level on an earlier row' END,
             CASE WHEN j.titles > 1 OR j.unitss > 1 OR j.sems > 1 OR j.owners > 1 OR j.owner_progs > 1
                  THEN 'COURSE_CONFLICT: the rows of ' || j.code || ' disagree on its title, units, semester or owner' END,
             CASE WHEN EXISTS (SELECT 1 FROM unnest(j.prereqs) q WHERE q = j.code) THEN 'PREREQUISITE_INVALID: a course does not require itself'
                  WHEN EXISTS (SELECT 1 FROM unnest(j.prereqs) q
                                WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = q)
                                  AND NOT EXISTS (SELECT 1 FROM res r2 WHERE r2.code = q))
                  THEN 'PREREQUISITE_UNKNOWN: ' || (SELECT string_agg(q, ', ') FROM unnest(j.prereqs) q
                                                     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = q) AND NOT EXISTS (SELECT 1 FROM res r2 WHERE r2.code = q)) || ' is not a course' END
           ], NULL) AS errors
      FROM judged j
)
SELECT coalesce(jsonb_agg(jsonb_build_object(
           'n', c.n, 'code', c.code, 'title', c.title, 'units', c.units, 'level', c.level, 'semester', c.semester,
           'ownerDepartment', c.owner_dept, 'ownerProgramme', coalesce(c.op, CASE WHEN c.od IS NULL OR c.od = c.existing_dept THEN c.existing_prog END),
           'offeringProgramme', c.fp, 'offeringDepartment', c.fp_dept, 'basis', c.basis, 'classification', c.class_raw, 'courseType', c.course_type, 'description', c.description,
           'prerequisites', to_jsonb(c.prereqs), 'remarks', c.remarks, 'session', c.session_raw,
           'state', CASE WHEN cardinality(c.errors) > 0 THEN 'INVALID' WHEN c.status_raw = 'INACTIVE' THEN 'SKIPPED' ELSE 'VALID' END,
           'errors', to_jsonb(c.errors),
           'existing', c.existing IS NOT NULL, 'general', c.existing_office IS NOT NULL,
           'revived', c.existing IS NOT NULL AND c.existing_state = 'ENDED' AND c.existing_reset IS NOT NULL,
           'ownerChange', c.existing IS NOT NULL AND c.existing_office IS NULL AND c.od IS NOT NULL AND c.od <> c.existing_dept,
           'existingOffering', EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = c.fp AND co.level = c.level)
       ) ORDER BY c.n), '[]'::jsonb)
  FROM checked c;
$$;

CREATE OR REPLACE FUNCTION catalogue.import_catalogue(p_rows jsonb, p_commit boolean, p_file text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_rows jsonb; v_sum jsonb; v_id uuid; v_ref text; v_valid jsonb;
        n_new int := 0; n_upd int := 0; n_rev int := 0; n_own int := 0; n_bnew int := 0; n_bupd int := 0; n_pre int := 0;
BEGIN
    v_rows := catalogue.import_catalogue_rows(p_rows);
    SELECT jsonb_build_object(
        'total', count(*),
        'valid', count(*) FILTER (WHERE x->>'state' = 'VALID'),
        'invalid', count(*) FILTER (WHERE x->>'state' = 'INVALID'),
        'skipped', count(*) FILTER (WHERE x->>'state' = 'SKIPPED'),
        'newCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND NOT (x->>'existing')::boolean),
        'existingCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'existing')::boolean),
        'revivedCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'revived')::boolean),
        'ownerChanges', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'ownerChange')::boolean),
        'newOfferings', count(*) FILTER (WHERE x->>'state' = 'VALID' AND NOT (x->>'existingOffering')::boolean),
        'existingOfferings', count(*) FILTER (WHERE x->>'state' = 'VALID' AND (x->>'existingOffering')::boolean),
        'duplicateOfferings', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "DUPLICATE_OFFERING")'),
        'conflicts', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "COURSE_CONFLICT")' OR x->'errors' @? '$[*] ? (@ starts with "COURSE_ENDED")'),
        'ownerErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "OWNER_")'),
        'programmeErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "PROGRAMME_")'),
        'departmentErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "DEPARTMENT_")'),
        'facultyErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "FACULTY_")'),
        'typeErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "OFFERING_TYPE" || @ starts with "CLASSIFICATION" || @ starts with "COURSE_TYPE")'),
        'prerequisiteErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "PREREQUISITE")'))
      INTO v_sum
      FROM jsonb_array_elements(v_rows) x;
    IF NOT coalesce(p_commit, false) THEN
        RETURN jsonb_build_object('committed', false, 'summary', v_sum, 'rows', v_rows);
    END IF;

    IF who IS NULL THEN RAISE EXCEPTION 'a catalogue upload is committed by a person' USING ERRCODE = '23514'; END IF;
    IF (v_sum->>'invalid')::int > 0 THEN
        RAISE EXCEPTION 'CAT_IMPORT_INVALID: % row(s) are invalid; nothing was written', v_sum->>'invalid' USING ERRCODE = '23514',
            HINT = 'Download the error report, correct the rows and upload the file again.';
    END IF;
    IF (v_sum->>'valid')::int = 0 THEN
        RAISE EXCEPTION 'CAT_IMPORT_EMPTY: the file has no row to import' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('catalogue.course_catalogue'));
    v_ref := 'COURSE-IMPORT-' || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('COURSE_IMPORT', 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0');
    PERFORM set_config('moaum.reason', 'Course catalogue upload ' || v_ref, true);
    PERFORM set_config('moaum.owner_source', 'IMPORT', true);
    v_valid := (SELECT jsonb_agg(x) FROM jsonb_array_elements(v_rows) x WHERE x->>'state' = 'VALID');

    -- one course per code: its title, units, semester and owner from its rows; its level from the owner programme's row
    WITH per AS (
        SELECT x->>'code' AS code,
               (array_agg(x->>'title' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'title' IS NOT NULL))[1] AS title,
               (array_agg((x->>'units')::int ORDER BY (x->>'n')::int) FILTER (WHERE x->>'units' IS NOT NULL))[1] AS units,
               (array_agg((x->>'semester')::int ORDER BY (x->>'n')::int) FILTER (WHERE x->>'semester' IS NOT NULL))[1] AS semester,
               (array_agg((x->>'level')::int ORDER BY coalesce(x->>'offeringProgramme' = x->>'ownerProgramme', false) DESC, (x->>'level')::int))[1] AS level,
               (array_agg(x->>'ownerDepartment' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'ownerDepartment' IS NOT NULL))[1] AS dept,
               (array_agg(x->>'ownerProgramme' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'ownerProgramme' IS NOT NULL))[1] AS prog,
               (array_agg(x->>'courseType' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'courseType' IS NOT NULL))[1] AS ctype,
               bool_or(x->>'basis' = 'GST') AS gst,
               -- V368: a row classified EPS files the course under the EPS office; GST is left to the code families
               bool_or(x->>'classification' = 'EPS') AS eps,
               (array_agg(x->>'description' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'description' IS NOT NULL))[1] AS description,
               bool_or((x->>'existing')::boolean) AS existing, bool_or((x->>'general')::boolean) AS general,
               bool_or((x->>'revived')::boolean) AS revived, bool_or((x->>'ownerChange')::boolean) AS owner_change
          FROM jsonb_array_elements(v_valid) x GROUP BY x->>'code'
    ), ins AS (
        INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, owner_programme, kind, description, state, general_office)
        SELECT p.code, p.title, p.units, p.semester, p.level, p.dept, p.prog,
               CASE WHEN p.gst THEN 'GST' ELSE coalesce(p.ctype, 'Core') END, p.description, 'LIVE', CASE WHEN p.gst AND p.eps THEN 'EPS' END
          FROM per p WHERE NOT p.existing
        RETURNING 1
    ), upd AS (
        UPDATE catalogue.course c
           SET title = coalesce(p.title, c.title), units = coalesce(p.units, c.units), semester = coalesce(p.semester, c.semester),
               dept_code = coalesce(p.dept, c.dept_code),
               owner_programme = CASE WHEN p.prog IS NOT NULL THEN p.prog WHEN p.dept IS NOT NULL AND p.dept <> c.dept_code THEN NULL ELSE c.owner_programme END,
               kind = CASE WHEN p.gst THEN 'GST' ELSE coalesce(p.ctype, c.kind) END,
               general_office = CASE WHEN p.gst AND p.eps THEN 'EPS' ELSE c.general_office END,
               description = coalesce(p.description, c.description),
               state = CASE WHEN c.reset_batch_id IS NOT NULL OR c.state IN ('BOARD', 'SENATE') THEN 'LIVE' ELSE c.state END,
               ended_on = CASE WHEN c.reset_batch_id IS NOT NULL THEN NULL ELSE c.ended_on END,
               reset_batch_id = NULL
          FROM per p
         WHERE c.code = p.code AND p.existing AND NOT p.general
        RETURNING 1
    )
    SELECT (SELECT count(*) FROM ins), (SELECT count(*) FROM upd),
           (SELECT count(*) FROM per WHERE revived), (SELECT count(*) FROM per WHERE owner_change)
      INTO n_new, n_upd, n_rev, n_own;

    -- the offerings: one binding per course, programme and level, Core / Elective / GST as the row says
    SELECT count(*) FILTER (WHERE NOT (x->>'existingOffering')::boolean), count(*) FILTER (WHERE (x->>'existingOffering')::boolean)
      INTO n_bnew, n_bupd FROM jsonb_array_elements(v_valid) x;
    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, added_by, source)
    SELECT x->>'code', x->>'offeringProgramme', (x->>'level')::int, x->>'basis', who, 'IMPORT'
      FROM jsonb_array_elements(v_valid) x
    ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;

    -- the prerequisites
    WITH p AS (
        INSERT INTO catalogue.course_prerequisite (course_code, requires_code, added_by)
        SELECT DISTINCT x->>'code', q, who
          FROM jsonb_array_elements(v_valid) x CROSS JOIN LATERAL jsonb_array_elements_text(x->'prerequisites') q
        ON CONFLICT DO NOTHING
        RETURNING 1
    ) SELECT count(*) INTO n_pre FROM p;

    INSERT INTO catalogue.course_import (ref, file_name, rows, courses_created, courses_updated, courses_revived, owner_changes,
                                         offerings_created, offerings_updated, prerequisites, result, imported_by, imported_office)
    VALUES (v_ref, nullif(btrim(coalesce(p_file, '')), ''), (v_sum->>'total')::int, n_new, n_upd, n_rev, n_own, n_bnew, n_bupd, n_pre, v_rows, who, office)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('committed', true, 'id', v_id, 'ref', v_ref, 'summary', v_sum || jsonb_build_object(
               'coursesCreated', n_new, 'coursesUpdated', n_upd, 'coursesRevived', n_rev, 'ownerChangesMade', n_own,
               'offeringsCreated', n_bnew, 'offeringsUpdated', n_bupd, 'prerequisitesAdded', n_pre), 'rows', v_rows);
END $$;

-- ── 4 · the old-portal GST reconciliation reads refunds by the payment they refund ──────────────────────────────

CREATE OR REPLACE FUNCTION finance.legacy_gst_validate_one(p_payment uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE p finance.legacy_gst_payment; rc finance.legacy_gst_reconciliation; f record; v_dup uuid; v_other uuid; v_code text; v_reason text; v_status text; v_fee numeric := NULL;
BEGIN
    SELECT * INTO p FROM finance.legacy_gst_payment WHERE id = p_payment;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment;
    IF rc.student_id IS NULL OR rc.status NOT IN ('MATCHED', 'REQUIRES_REVIEW', 'REJECTED', 'DUPLICATE') THEN RETURN; END IF;
    IF rc.status = 'RECONCILED' THEN RETURN; END IF;
    v_status := 'MATCHED'; v_code := NULL; v_reason := NULL;
    IF p.normalized_status <> 'SUCCESS' THEN
        v_status := 'REJECTED';
        v_code := CASE p.normalized_status WHEN 'REFUNDED' THEN 'PAYMENT_REFUNDED' WHEN 'REVERSED' THEN 'PAYMENT_REVERSED' WHEN 'PENDING' THEN 'PAYMENT_PENDING' WHEN 'FAILED' THEN 'PAYMENT_FAILED' ELSE 'PAYMENT_STATUS_UNKNOWN' END;
        v_reason := 'the old portal recorded the payment as "' || coalesce(p.legacy_status, '—') || '"; only a successful payment establishes anything';
    ELSIF finance.legacy_gst_type_of(p.payment_type) IS NULL THEN
        v_status := 'REJECTED'; v_code := 'UNKNOWN_PAYMENT_TYPE';
        v_reason := 'the payment type "' || coalesce(p.payment_type, '—') || '" is not one the Bursary reads as the GST fee';
    ELSIF p.session IS NULL THEN
        v_status := 'REJECTED'; v_code := 'MISSING_SESSION'; v_reason := 'the row names no session the payment belongs to';
    ELSIF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p.session) THEN
        v_status := 'REJECTED'; v_code := 'INVALID_SESSION'; v_reason := 'the session ' || p.session || ' is not on the calendar';
    ELSIF p.amount IS NULL OR p.amount <= 0 THEN
        v_status := 'REJECTED'; v_code := 'MISSING_AMOUNT'; v_reason := 'the row carries no amount';
    ELSE
        -- an entitlement already on the ledger for this student and session: the new portal''s, or an earlier reconciliation''s
        SELECT r.id INTO v_dup FROM finance.payment_reference r
         WHERE r.student_id = rc.student_id AND r.session = p.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.source_reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))
         ORDER BY r.confirmed_at LIMIT 1;
        IF v_dup IS NOT NULL THEN
            v_status := 'DUPLICATE'; v_code := 'EXISTING_ENTITLEMENT';
            v_reason := 'the student already holds a confirmed GST payment for ' || p.session || ' on the ledger (' || (SELECT reference || ' · ' || coalesce(channel, '') FROM finance.payment_reference WHERE id = v_dup) || '); one entitlement stands, both histories are kept';
        ELSE
            SELECT * INTO f FROM finance.gst_fee_for(rc.student_id, p.session);
            IF f.stated THEN v_fee := f.amount; END IF;
            IF NOT f.stated THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'NO_FEE_FOR_SESSION';
                v_reason := 'no GST fee is stated for ' || p.session || ' for this student, so the amount cannot be judged; the Bursar states the fee of that session first';
            ELSIF p.amount < f.amount THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'PARTIAL_PAYMENT';
                v_reason := 'the old portal shows NGN ' || to_char(p.amount, 'FM999,999,990.00') || ' against a fee of NGN ' || to_char(f.amount, 'FM999,999,990.00') || ' for ' || p.session;
            ELSIF p.amount > f.amount THEN
                v_status := 'REQUIRES_REVIEW'; v_code := 'AMOUNT_ABOVE_FEE';
                v_reason := 'the old portal shows NGN ' || to_char(p.amount, 'FM999,999,990.00') || ' against a fee of NGN ' || to_char(f.amount, 'FM999,999,990.00') || ' for ' || p.session;
            END IF;
            -- the same money may already sit on the ledger as school fees from the Old Fees History import: an officer decides
            IF v_status = 'MATCHED' THEN
                SELECT r.id INTO v_other FROM finance.payment_reference r
                 WHERE r.student_id = rc.student_id AND r.session = p.session AND r.channel = 'Legacy' AND r.purpose LIKE 'School fees%'
                   AND r.amount = p.amount AND (p.paid_at IS NULL OR r.confirmed_at::date = p.paid_at::date)
                 LIMIT 1;
                IF v_other IS NOT NULL THEN
                    v_status := 'REQUIRES_REVIEW'; v_code := 'POSSIBLE_RELABEL';
                    v_reason := 'the same amount on the same day already sits on the ledger as school fees imported from the old portal (' || (SELECT reference FROM finance.payment_reference WHERE id = v_other) || '); relabel it as the GST fee, or record this payment separately';
                END IF;
            END IF;
        END IF;
    END IF;
    UPDATE finance.legacy_gst_reconciliation
       SET status = v_status, reason_code = v_code, reason = v_reason, fee_amount = coalesce(v_fee, fee_amount)
     WHERE payment_id = p_payment;
END $$;

CREATE OR REPLACE FUNCTION finance.legacy_gst_resolve(p_payment uuid, p_action text, p_student uuid, p_reason text)
RETURNS finance.legacy_gst_reconciliation LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        p finance.legacy_gst_payment; rc finance.legacy_gst_reconciliation; i finance.legacy_gst_import; v_act text := upper(btrim(coalesce(p_action, ''))); v_other uuid; v_id uuid; v_ref text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: a reconciliation is resolved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO p FROM finance.legacy_gst_payment WHERE id = p_payment;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_PAYMENT_NOT_FOUND: no such old-portal payment' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment FOR UPDATE;
    SELECT * INTO i FROM finance.legacy_gst_import WHERE id = rc.import_id;
    IF rc.status = 'RECONCILED' THEN RAISE EXCEPTION 'LEGACY_ALREADY_RECONCILED: this payment is already on the ledger as %', (SELECT reference FROM finance.payment_reference WHERE id = rc.payment_reference_id) USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'LEGACY_REASON_REQUIRED: resolving a payment names its reason' USING ERRCODE = '23514'; END IF;

    IF v_act = 'MATCH' THEN
        IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: name the current student' USING ERRCODE = '23514'; END IF;
        -- the identifiers on the row must not point at somebody else: ownership is never moved by guesswork
        IF (p.matric_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = p.matric_no AND s.id <> p_student))
           OR (p.jamb_no IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.jamb_reg_no) = p.jamb_no AND s.id <> p_student)) THEN
            RAISE EXCEPTION 'LEGACY_IDENTIFIER_CONFLICT: the matriculation or JAMB number on the row belongs to another student; a payment is not moved to a student its identifiers do not name' USING ERRCODE = '23514';
        END IF;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'MATCHED', reason_code = NULL, reason = NULL, student_id = p_student, match_method = 'MANUAL', match_confidence = 'MANUAL',
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
        PERFORM finance.legacy_gst_validate_one(p_payment);
        -- the old id, once resolved by hand, is on the crosswalk for the next file
        IF p.source_student_id IS NOT NULL AND p.source_student_id !~ '^[0-9a-f]{8}-' THEN
            INSERT INTO finance.legacy_student_crosswalk (legacy_student_id, student_id, note, set_by)
            VALUES (upper(p.source_student_id), p_student, 'set when ' || coalesce(p.source_reference, p.source_transaction_id) || ' was resolved: ' || btrim(p_reason), v_actor)
            ON CONFLICT (legacy_student_id) DO NOTHING;
        END IF;
    ELSIF v_act = 'RECONCILE' THEN
        IF rc.student_id IS NULL THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: match the payment to a student first' USING ERRCODE = '23514'; END IF;
        IF rc.status NOT IN ('MATCHED', 'REQUIRES_REVIEW') THEN RAISE EXCEPTION 'LEGACY_STATE: a % payment is not reconciled by hand', lower(replace(rc.status, '_', ' ')) USING ERRCODE = '23514'; END IF;
        IF p.normalized_status <> 'SUCCESS' THEN RAISE EXCEPTION 'LEGACY_NOT_SUCCESSFUL: the old portal did not record this payment as successful; it cannot establish an entitlement' USING ERRCODE = '23514'; END IF;
        IF p.session IS NULL OR p.amount IS NULL OR p.amount <= 0 THEN RAISE EXCEPTION 'LEGACY_INCOMPLETE: the row needs a session and an amount' USING ERRCODE = '23514'; END IF;
        IF EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.student_id = rc.student_id AND r.session = p.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                      AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.source_reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))) THEN
            RAISE EXCEPTION 'LEGACY_DUPLICATE: the student already holds a confirmed GST payment for %', p.session USING ERRCODE = '23514';
        END IF;
        v_ref := finance.legacy_gst_ledger_reference(p);
        IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref) THEN RAISE EXCEPTION 'LEGACY_DUPLICATE: a ledger row already carries the old-portal reference %', v_ref USING ERRCODE = '23514'; END IF;
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (rc.student_id, p.session, v_ref, 'GST fee ' || p.session, p.amount, coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), coalesce(p.paid_at, now()), v_actor, 'Legacy', 'LEG-' || v_ref,
                'Old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || ', reconciled by hand under ' || i.reference || ': ' || btrim(p_reason))
        RETURNING id INTO v_id;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'RECONCILED', reason_code = NULL, reason = NULL, payment_reference_id = v_id, reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office,
               resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSIF v_act = 'RELABEL' THEN
        -- the money is already on the ledger as school fees from the old portal: it was for the GST fee
        IF rc.student_id IS NULL THEN RAISE EXCEPTION 'LEGACY_STUDENT_REQUIRED: match the payment to a student first' USING ERRCODE = '23514'; END IF;
        SELECT r.id INTO v_other FROM finance.payment_reference r
         WHERE r.student_id = rc.student_id AND r.session = p.session AND r.channel = 'Legacy' AND r.purpose LIKE 'School fees%' AND r.amount = p.amount
         ORDER BY abs(extract(epoch FROM (r.confirmed_at - coalesce(p.paid_at, r.confirmed_at)))) LIMIT 1;
        IF v_other IS NULL THEN RAISE EXCEPTION 'LEGACY_NOTHING_TO_RELABEL: no old-portal school-fees row of that amount is on the ledger for the student and session' USING ERRCODE = '23514'; END IF;
        UPDATE finance.payment_reference
           SET purpose = 'GST fee ' || p.session,
               note = coalesce(note || ' · ', '') || 'relabelled from school fees: old-portal GST payment ' || coalesce(p.source_reference, p.source_transaction_id) || ', under ' || i.reference || ': ' || btrim(p_reason)
         WHERE id = v_other;
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'RECONCILED', reason_code = 'RELABELLED', reason = 'the old-portal school-fees row was relabelled as the GST fee', payment_reference_id = v_other,
               reconciled_at = now(), reconciled_by = v_actor, reconciled_office = v_office, resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSIF v_act = 'REJECT' THEN
        UPDATE finance.legacy_gst_reconciliation
           SET status = 'REJECTED', reason_code = 'REJECTED_BY_OFFICER', reason = btrim(p_reason), resolved_at = now(), resolved_by = v_actor, resolved_office = v_office, override_reason = btrim(p_reason)
         WHERE payment_id = p_payment;
    ELSE
        RAISE EXCEPTION 'LEGACY_ACTION: unknown action %', v_act USING ERRCODE = '23514';
    END IF;
    SELECT * INTO rc FROM finance.legacy_gst_reconciliation WHERE payment_id = p_payment;
    RETURN rc;
END $$;

COMMIT;

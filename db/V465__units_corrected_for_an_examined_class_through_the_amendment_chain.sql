-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V465 — Units corrected for an examined class through the results-amendment chain, and what a change of units reaches
--        counted wherever units are changed
--
--   · Since V464 a class whose results are being worked on keeps its units: a change on Programme Structure, the review or
--     the course's page does not reach it. When the number was wrong, the class had no way to be put right. Now the desk of
--     entry (the course's lecturer, or the Programme Examinations Officer, or the GST / EPS office for its own courses)
--     raises a units correction for one programme's students on the class, with the reason. It is an amendment of kind
--     UNITS on assessment.amendment, so it goes the way a mark correction goes (V358): approved by each desk of the chain in
--     turn, never twice in a row by one person, and applied by the Registrar on the Senate minute — the registrations of the
--     programme's students on the class then carry the corrected units, the grade point average reads them, and each student
--     is told by e-mail. A desk may refuse it with the reason; the person who raised it may withdraw it.
--   · assessment.class_units(sheet): the class's programmes — their students, the units they carry and what each programme's
--     structure says now — for the sheet's chain, where a correction is raised.
--   · catalogue.units_change_rows / course_units_change_rows: what a change reaches, registration by registration; the counts
--     (units_change_impact, restated from V464, and course_units_change_impact) and the list of examined classes that keep
--     their units read the same rows. catalogue.units_pinned_by_course: the other departments' programmes a change of the
--     course's own units leaves at the old number (catalogue.course_units_reflect restated from V460 to read it).
--   · Nothing is moved by this migration.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V465: units corrected for an examined class through the amendment chain', true);

-- ── 1 · what a change reaches, registration by registration ─────────────────────────────────────────────────────────

-- a programme's units for a course at a level set to p_units (the course's own number taking the course's units): each of the
-- programme's registrations of the course, its units now and as units_for would read them after, and whether it is held
CREATE OR REPLACE FUNCTION catalogue.units_change_rows(p_course text, p_programme text, p_level int, p_units int)
RETURNS TABLE(registration_id uuid, offering_id uuid, old_units int, to_units int, held boolean)
LANGUAGE sql STABLE AS $fn$
    WITH c AS (SELECT x.units FROM catalogue.course x WHERE x.code = p_course),
    b AS (SELECT co.level,
                 CASE WHEN co.level = p_level THEN nullif(p_units, (SELECT c.units FROM c)) ELSE co.units END AS units
            FROM catalogue.course_offer co WHERE co.course_code = p_course AND co.programme_code = p_programme),
    any_own AS (SELECT b.units FROM b WHERE b.units IS NOT NULL ORDER BY b.level LIMIT 1)
    SELECT e.registration_id, o.id, e.units,
           coalesce((SELECT b.units FROM b WHERE b.level = r.level),
                    CASE WHEN NOT EXISTS (SELECT 1 FROM b WHERE b.level = r.level) THEN (SELECT a.units FROM any_own a) END,
                    (SELECT c.units FROM c)),
           (EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state = 'CLOSED') OR catalogue.class_examined(o.id))
      FROM registration.entry e
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN people.student s ON s.id = r.student_id
      JOIN catalogue.offering o ON o.id = e.offering_id
     WHERE o.course_code = p_course AND s.programme_code = p_programme
$fn$;
COMMENT ON FUNCTION catalogue.units_change_rows(text, text, int, int) IS
  'V465: each registration a programme''s change of units for a course would reach — its units now, after, and whether it is held (a closed session, or the class examined).';

-- restated from V464: the counts read the rows
CREATE OR REPLACE FUNCTION catalogue.units_change_impact(p_course text, p_programme text, p_level int, p_units int)
RETURNS TABLE(now_units int, new_units int, follow int, kept int)
LANGUAGE sql STABLE AS $fn$
    SELECT catalogue.units_for(p_course, p_programme, p_level),
           coalesce(p_units, (SELECT x.units FROM catalogue.course x WHERE x.code = p_course)),
           (count(*) FILTER (WHERE NOT x.held AND x.old_units IS DISTINCT FROM x.to_units))::int,
           (count(*) FILTER (WHERE x.held AND x.old_units IS DISTINCT FROM x.to_units))::int
      FROM catalogue.units_change_rows(p_course, p_programme, p_level, p_units) x
$fn$;

-- the other departments' programmes a change of the course's own units leaves at the old number, pinned on their bindings —
-- not for a GST / EPS course, the University's, which reaches every programme
CREATE OR REPLACE FUNCTION catalogue.units_pinned_by_course(p_course text)
RETURNS TABLE(programme_code text, level int)
LANGUAGE sql STABLE AS $fn$
    SELECT co.programme_code, co.level
      FROM catalogue.course_offer co
      JOIN catalogue.course c ON c.code = co.course_code
      JOIN ref.programme p ON p.code = co.programme_code
     WHERE co.course_code = p_course AND co.units IS NULL
       AND c.general_office IS NULL AND c.kind <> 'GST'
       AND p.dept_code IS DISTINCT FROM c.dept_code
$fn$;
COMMENT ON FUNCTION catalogue.units_pinned_by_course(text) IS
  'V465: the bindings of other departments'' programmes that a change of the course''s own units pins at the old number (V460''s rule, read by the trigger and by the count).';

-- restated from V460: the pinned bindings read from the one rule
CREATE OR REPLACE FUNCTION catalogue.course_units_reflect()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF OLD.units IS DISTINCT FROM NEW.units THEN
        UPDATE catalogue.course_offer co SET units = OLD.units
          FROM catalogue.units_pinned_by_course(NEW.code) x
         WHERE co.course_code = NEW.code AND co.programme_code = x.programme_code AND co.level = x.level;
        PERFORM catalogue.reflect_units(NEW.code, NULL, NULL);
    END IF;
    RETURN NEW;
END $fn$;

-- a change of the course's own units to p_units: each registration of the course, its units now and after, whether held
CREATE OR REPLACE FUNCTION catalogue.course_units_change_rows(p_course text, p_units int)
RETURNS TABLE(registration_id uuid, offering_id uuid, programme_code text, old_units int, to_units int, held boolean)
LANGUAGE sql STABLE AS $fn$
    WITH c AS (SELECT x.units FROM catalogue.course x WHERE x.code = p_course),
    pin AS (SELECT x.programme_code, x.level FROM catalogue.units_pinned_by_course(p_course) x WHERE p_units IS DISTINCT FROM (SELECT c.units FROM c)),
    b AS (SELECT co.programme_code, co.level,
                 CASE WHEN co.units IS NULL AND EXISTS (SELECT 1 FROM pin WHERE pin.programme_code = co.programme_code AND pin.level = co.level)
                      THEN (SELECT c.units FROM c) ELSE co.units END AS units
            FROM catalogue.course_offer co WHERE co.course_code = p_course)
    SELECT e.registration_id, o.id, s.programme_code, e.units,
           coalesce((SELECT b.units FROM b WHERE b.programme_code = s.programme_code AND b.level = r.level),
                    CASE WHEN NOT EXISTS (SELECT 1 FROM b WHERE b.programme_code = s.programme_code AND b.level = r.level)
                         THEN (SELECT b.units FROM b WHERE b.programme_code = s.programme_code AND b.units IS NOT NULL ORDER BY b.level LIMIT 1) END,
                    p_units),
           (EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state = 'CLOSED') OR catalogue.class_examined(o.id))
      FROM registration.entry e
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN people.student s ON s.id = r.student_id
      JOIN catalogue.offering o ON o.id = e.offering_id
     WHERE o.course_code = p_course
$fn$;
COMMENT ON FUNCTION catalogue.course_units_change_rows(text, int) IS
  'V465: each registration a change of the course''s own units would reach — its units now, after, and whether it is held.';

CREATE OR REPLACE FUNCTION catalogue.course_units_change_impact(p_course text, p_units int)
RETURNS TABLE(now_units int, new_units int, follow int, kept int, pinned int)
LANGUAGE sql STABLE AS $fn$
    SELECT (SELECT x.units FROM catalogue.course x WHERE x.code = p_course), p_units, f.follow, f.kept,
           CASE WHEN p_units IS DISTINCT FROM (SELECT x.units FROM catalogue.course x WHERE x.code = p_course)
                THEN (SELECT count(*) FROM catalogue.units_pinned_by_course(p_course))::int ELSE 0 END
      FROM (SELECT (count(*) FILTER (WHERE NOT r.held AND r.old_units IS DISTINCT FROM r.to_units))::int AS follow,
                   (count(*) FILTER (WHERE r.held AND r.old_units IS DISTINCT FROM r.to_units))::int AS kept
              FROM catalogue.course_units_change_rows(p_course, p_units) r) f
$fn$;
COMMENT ON FUNCTION catalogue.course_units_change_impact(text, int) IS
  'V465: before a course''s own units change — the units now and after, the registrations that follow, those that keep theirs, and the other departments'' bindings left at the old number.';

-- ── 2 · a units correction through the results-amendment chain ──────────────────────────────────────────────────────
ALTER TABLE assessment.amendment
    DROP CONSTRAINT amendment_kind_check,
    ADD CONSTRAINT amendment_kind_check CHECK (kind IN ('AMEND', 'LATE', 'UNITS')),
    ALTER COLUMN student_id DROP NOT NULL,
    ALTER COLUMN outcome DROP NOT NULL,
    ADD COLUMN programme_code text NULL REFERENCES ref.programme(code),
    ADD COLUMN units int NULL CHECK (units IS NULL OR units BETWEEN 0 AND 12),
    ADD COLUMN was_units int NULL,
    ADD COLUMN applied_count int NULL,
    DROP CONSTRAINT ck_amendment_late,
    ADD CONSTRAINT ck_amendment_late CHECK ((kind = 'AMEND') = (was_version IS NOT NULL) AND (kind = 'AMEND') = (was_outcome IS NOT NULL)),
    ADD CONSTRAINT ck_amendment_units CHECK ((kind = 'UNITS') = (student_id IS NULL) AND (kind = 'UNITS') = (programme_code IS NOT NULL)
                                             AND (kind = 'UNITS') = (units IS NOT NULL) AND (kind = 'UNITS') = (outcome IS NULL));
COMMENT ON COLUMN assessment.amendment.kind IS
  'V422, V465: AMEND corrects a published mark (was_* hold it); LATE gives a candidate on the published sheet''s roll their first mark (no was_*); UNITS corrects the units one programme''s students carry on an examined class (programme_code, units; no student, no mark).';
COMMENT ON COLUMN assessment.amendment.was_units IS 'V465: the units most of the programme''s students on the class carried when the correction was raised.';
COMMENT ON COLUMN assessment.amendment.applied_count IS 'V465: the registrations a units correction changed when it was applied.';

/* raised by the desk of entry for one programme's students on a class whose results are worked on, with the reason */
CREATE OR REPLACE FUNCTION assessment.raise_units_amendment(p_sheet uuid, p_programme text, p_units int, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_prog text := upper(btrim(coalesce(p_programme, ''))); v_offering uuid; v_code text; n int; n_same int; v_was int; v_open text; v_id uuid;
        v_year text := to_char(current_date, 'YYYY');
BEGIN
    PERFORM assessment.require_stage_desk('ENTRY', v_office, 'raised');
    SELECT s.offering_id, o.course_code INTO v_offering, v_code
      FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id WHERE s.id = p_sheet;
    IF v_offering IS NULL THEN RAISE EXCEPTION 'no score sheet %', p_sheet USING ERRCODE = 'no_data_found'; END IF;
    IF NOT catalogue.class_examined(v_offering) THEN
        RAISE EXCEPTION 'RES_UNITS_NOT_EXAMINED: no result of % on this class is worked on yet; change the programme''s units on its Programme Structure and its registrations follow', v_code
            USING ERRCODE = '23514';
    END IF;
    IF p_units IS NULL OR p_units NOT BETWEEN 0 AND 12 THEN
        RAISE EXCEPTION 'RES_UNITS_RANGE: a course is taken at 0 to 12 units' USING ERRCODE = '23514';
    END IF;
    SELECT count(*), count(*) FILTER (WHERE e.units = p_units), mode() WITHIN GROUP (ORDER BY e.units)
      INTO n, n_same, v_was
      FROM registration.entry e
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN people.student st ON st.id = r.student_id
     WHERE e.offering_id = v_offering AND st.programme_code = v_prog;
    IF n = 0 THEN
        RAISE EXCEPTION 'RES_UNITS_NO_STUDENTS: no student of % is registered on this class of %', v_prog, v_code USING ERRCODE = '23514';
    END IF;
    IF n_same = n THEN
        RAISE EXCEPTION 'RES_AMEND_SAME: the students of % on this class carry % units already', v_prog, p_units USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'RES_AMEND_REASON: an amendment says why, in words Senate can read' USING ERRCODE = '23514';
    END IF;
    SELECT m.ref INTO v_open FROM assessment.amendment m JOIN assessment.score_sheet s ON s.id = m.sheet_id
     WHERE m.kind = 'UNITS' AND s.offering_id = v_offering AND m.programme_code = v_prog AND m.stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN')
     LIMIT 1;
    IF v_open IS NOT NULL THEN
        RAISE EXCEPTION 'RES_UNITS_OPEN: % is open for the units of % on this class; it is decided or withdrawn first', v_open, v_prog USING ERRCODE = '23514';
    END IF;
    INSERT INTO assessment.amendment (ref, sheet_id, student_id, kind, programme_code, units, was_units, outcome, reason, raised_by, raised_office)
    VALUES ('AMD-' || v_year || '-' || lpad(platform.next_number('RESULT_AMENDMENT', 'UNIVERSITY', v_year)::text, 5, '0'),
            p_sheet, NULL, 'UNITS', v_prog, p_units, v_was, NULL, btrim(p_reason), v_actor, v_office)
    RETURNING id INTO v_id;
    INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (v_id, NULL, 'VERIFICATION', 'RAISE', v_actor, v_office, btrim(p_reason));
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION assessment.raise_units_amendment(uuid, text, int, text) IS
  'V465: a units correction for one programme''s students on a class whose results are worked on — raised by the desk of entry, then the chain as any amendment.';

/* each student of the programme on the class told that the course's units on their registration are corrected */
CREATE OR REPLACE FUNCTION assessment.tell_units_amended(p_sheet uuid, p_programme text, p_course text, p_units int, p_ref text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE r record; v_from text := coalesce((SELECT name FROM platform.institution_profile LIMIT 1), 'the University');
BEGIN
    FOR r IN SELECT DISTINCT st.id, st.surname, st.other_names, rc.email
               FROM assessment.score_sheet sh
               JOIN registration.entry e ON e.offering_id = sh.offering_id
               JOIN registration.course_registration cr ON cr.id = e.registration_id
               JOIN people.student st ON st.id = cr.student_id
               LEFT JOIN LATERAL people.student_reach(st.id) rc ON true
              WHERE sh.id = p_sheet AND st.programme_code = p_programme LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, 'Your units in ' || p_course || ' are corrected',
            'Dear ' || r.surname || ', ' || r.other_names || E',\n\n' || p_course || ' is now recorded at ' || p_units || ' unit'
            || CASE WHEN p_units = 1 THEN '' ELSE 's' END || ' on your registration, corrected on the Senate''s approval (' || p_ref || '). '
            || E'Your grade point average reads the corrected units. Any transcript or statement issued before the correction is superseded.\n\n'
            || v_from || ' — Examinations and Records',
            'student', r.id);
    END LOOP;
END $fn$;

/* restated from V422: at Senate, a units correction applied on the minute to the programme's registrations on the class */
CREATE OR REPLACE FUNCTION assessment.advance_amendment(p_amendment uuid, p_comment text, p_minute text)
RETURNS text
LANGUAGE plpgsql AS $function$
DECLARE m assessment.amendment; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_last uuid; v_next text; v_version int; v_course text; v_count int;
BEGIN
    SELECT * INTO m FROM assessment.amendment WHERE id = p_amendment FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'no amendment %', p_amendment USING ERRCODE = 'no_data_found'; END IF;
    IF m.stage IN ('APPLIED', 'REFUSED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'RES_AMEND_CLOSED: the amendment is % already', lower(m.stage) USING ERRCODE = '23514';
    END IF;
    PERFORM assessment.require_stage_desk(m.stage, v_office, 'approved');
    SELECT d.actor_id INTO v_last FROM assessment.amendment_decision d WHERE d.amendment_id = p_amendment AND d.kind IN ('RAISE', 'ADVANCE')
     ORDER BY d.decided_at DESC LIMIT 1;
    IF v_last IS NOT NULL AND v_last = v_actor THEN
        RAISE EXCEPTION 'you took the previous step of this amendment; another desk must approve this one' USING ERRCODE = 'check_violation',
            HINT = 'BR-006. No one person moves a correction from raising to Senate alone.';
    END IF;
    v_next := assessment.stage_after(m.stage);
    IF v_next = 'PUBLISHED' THEN
        IF p_minute IS NULL OR btrim(p_minute) = '' THEN
            RAISE EXCEPTION 'an amendment is applied on the Senate minute that approved it, and none was cited' USING ERRCODE = 'check_violation';
        END IF;
        SELECT o.course_code INTO v_course FROM assessment.score_sheet s JOIN catalogue.offering o ON o.id = s.offering_id WHERE s.id = m.sheet_id;
        IF m.kind = 'UNITS' THEN
            UPDATE registration.entry e SET units = m.units
              FROM registration.course_registration r, people.student st, assessment.score_sheet sh
             WHERE sh.id = m.sheet_id AND e.offering_id = sh.offering_id AND e.registration_id = r.id AND r.student_id = st.id
               AND st.programme_code = m.programme_code AND e.units IS DISTINCT FROM m.units;
            GET DIAGNOSTICS v_count = ROW_COUNT;
            UPDATE assessment.amendment SET stage = 'APPLIED', senate_minute = btrim(p_minute), applied_at = now(), applied_count = v_count WHERE id = p_amendment;
            INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
            VALUES (p_amendment, m.stage, 'APPLIED', 'APPLY', v_actor, v_office, nullif(btrim(coalesce(p_comment, '')), ''));
            PERFORM assessment.tell_units_amended(m.sheet_id, m.programme_code, v_course, m.units, m.ref);
            RETURN 'APPLIED';
        END IF;
        SELECT coalesce(max(version), 0) + 1 INTO v_version FROM assessment.score WHERE sheet_id = m.sheet_id AND student_id = m.student_id;
        INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, outcome, reason)
        VALUES (m.sheet_id, m.student_id, v_version, m.ca, m.exam, m.outcome,
                CASE WHEN m.kind = 'LATE' THEN 'Late result ' ELSE 'Amendment ' END || m.ref || ' on Senate minute ' || btrim(p_minute) || ': ' || m.reason);
        UPDATE assessment.amendment SET stage = 'APPLIED', senate_minute = btrim(p_minute), applied_at = now(), applied_version = v_version WHERE id = p_amendment;
        INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
        VALUES (p_amendment, m.stage, 'APPLIED', 'APPLY', v_actor, v_office, nullif(btrim(coalesce(p_comment, '')), ''));
        IF m.kind = 'LATE' THEN
            PERFORM assessment.tell_late_result(m.student_id, v_course, m.ref);
        ELSE
            PERFORM assessment.tell_amended(m.student_id, v_course, m.ref);
        END IF;
        RETURN 'APPLIED';
    END IF;
    UPDATE assessment.amendment SET stage = v_next WHERE id = p_amendment;
    INSERT INTO assessment.amendment_decision (amendment_id, from_stage, to_stage, kind, actor_id, actor_office, comment)
    VALUES (p_amendment, m.stage, v_next, 'ADVANCE', v_actor, v_office, nullif(btrim(coalesce(p_comment, '')), ''));
    RETURN v_next;
END $function$;

/* the sheet's amendments (V465: a units correction has a programme and no student, so the function is made again) */
DROP FUNCTION assessment.amendments_of(uuid);
CREATE FUNCTION assessment.amendments_of(p_sheet uuid)
RETURNS TABLE(id uuid, ref text, sheet_id uuid, student_id uuid, number text, name text, query_ref text, was_ca integer, was_exam integer, was_outcome text,
              ca integer, exam integer, outcome text, reason text, stage text, raised_by uuid, raised_by_name text, raised_office text,
              raised_at timestamp with time zone, senate_minute text, applied_at timestamp with time zone, closed_reason text, last_actor uuid, decisions jsonb,
              kind text, programme_code text, programme_name text, units integer, was_units integer, applied_count integer)
LANGUAGE sql STABLE AS $function$
    SELECT m.id, m.ref, m.sheet_id, m.student_id, coalesce(st.matric_no, st.admission_no), upper(st.surname) || ', ' || st.other_names, q.ref,
           m.was_ca, m.was_exam, m.was_outcome, m.ca, m.exam, m.outcome, m.reason, m.stage, m.raised_by, p.surname || ', ' || p.given_names, m.raised_office, m.raised_at,
           m.senate_minute, m.applied_at, m.closed_reason,
           (SELECT d.actor_id FROM assessment.amendment_decision d WHERE d.amendment_id = m.id AND d.kind IN ('RAISE', 'ADVANCE') ORDER BY d.decided_at DESC LIMIT 1),
           (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', d.kind, 'from', d.from_stage, 'to', d.to_stage, 'office', d.actor_office, 'comment', d.comment,
                                                         'at', d.decided_at, 'by', (SELECT x.surname || ', ' || x.given_names FROM iam.person x WHERE x.id = d.actor_id))
                                       ORDER BY d.decided_at), '[]'::jsonb)
              FROM assessment.amendment_decision d WHERE d.amendment_id = m.id),
           m.kind, m.programme_code, pr.name, m.units, m.was_units, m.applied_count
      FROM assessment.amendment m
      LEFT JOIN people.student st ON st.id = m.student_id
      LEFT JOIN ref.programme pr ON pr.code = m.programme_code
      LEFT JOIN assessment.result_query q ON q.id = m.query_id LEFT JOIN iam.person p ON p.id = m.raised_by
     WHERE m.sheet_id = p_sheet
     ORDER BY m.raised_at DESC
$function$;

/* the class's programmes: their students on it, the units they carry, what each programme's structure says now, whether the
   class's results are worked on, and the units correction open for the programme */
CREATE OR REPLACE FUNCTION assessment.class_units(p_sheet uuid)
RETURNS TABLE(programme_code text, programme_name text, students int, carried int[], takes int[], examined boolean, open_ref text)
LANGUAGE sql STABLE AS $fn$
    SELECT st.programme_code, pr.name, count(*)::int,
           array_agg(DISTINCT e.units ORDER BY e.units),
           array_agg(DISTINCT catalogue.units_for(o.course_code, st.programme_code, r.level) ORDER BY catalogue.units_for(o.course_code, st.programme_code, r.level)),
           catalogue.class_examined(o.id),
           (SELECT m.ref FROM assessment.amendment m JOIN assessment.score_sheet s2 ON s2.id = m.sheet_id
             WHERE m.kind = 'UNITS' AND s2.offering_id = o.id AND m.programme_code = st.programme_code
               AND m.stage NOT IN ('APPLIED', 'REFUSED', 'WITHDRAWN') LIMIT 1)
      FROM assessment.score_sheet sh
      JOIN catalogue.offering o ON o.id = sh.offering_id
      JOIN registration.entry e ON e.offering_id = o.id
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN people.student st ON st.id = r.student_id
      LEFT JOIN ref.programme pr ON pr.code = st.programme_code
     WHERE sh.id = p_sheet
     GROUP BY st.programme_code, pr.name, o.id, o.course_code
     ORDER BY st.programme_code
$fn$;
COMMENT ON FUNCTION assessment.class_units(uuid) IS
  'V465: a sheet''s class by programme — students, the units they carry, what the programme''s structure says now, whether the class is examined, and the units correction open.';

COMMIT;

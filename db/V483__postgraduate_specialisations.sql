-- ═══════════════════════════════════════
-- V483 — Postgraduate specialisations
--
-- A postgraduate programme is often read in options — an M.Sc. Economics in Monetary or Development Economics — on one
-- programme structure: most courses for every student of the programme, some for one option only. The structure knew a
-- binding's curriculum track (BMAS/CCMAS, V235), which is the cohort's framework, not a choice within the programme.
--
--   catalogue.programme_specialisation    a postgraduate programme's specialisations (code, name; ended, never deleted).
--   catalogue.course_offer_specialisation a binding named for one or more specialisations; a binding with none is for every
--                                         student of the programme, as every binding is today.
--   people.student_specialisation         the specialisation a student reads (one; none until the School sets it).
--
--   catalogue.save_specialisation(programme, code, name[, id])   added or renamed — a postgraduate programme only.
--   catalogue.end_specialisation(id, active)                       ended or restored; its students and bindings keep it.
--   catalogue.set_offer_specialisations(course, programme, level, ids[])   the specialisations a binding is for.
--   people.set_student_specialisation(student, id)                 set or cleared (NULL) — a specialisation of the
--                                                                  student's own programme, and not ended.
--
-- registration.student_menu is restated from its current definition with one rule added: a binding named for
-- specialisations is on the menu of those specialisations' students only. A student with none set sees the courses for every
-- student, so nothing anyone sees changes until the School names a specialisation's courses.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V483: postgraduate specialisations', true);

CREATE TABLE catalogue.programme_specialisation (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    programme_code text NOT NULL REFERENCES ref.programme (code),
    code           text NOT NULL CHECK (code ~ '^[A-Z0-9][A-Z0-9-]{0,11}$'),
    name           text NOT NULL CHECK (btrim(name) <> ''),
    active         boolean NOT NULL DEFAULT true,
    created_by     uuid,
    created_office text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    ended_at       timestamptz,
    ended_by       uuid,
    CONSTRAINT uq_programme_specialisation_code UNIQUE (programme_code, code)
);
CREATE UNIQUE INDEX uq_programme_specialisation_name ON catalogue.programme_specialisation (programme_code, lower(btrim(name)));
SELECT audit.attach('catalogue.programme_specialisation');
COMMENT ON TABLE catalogue.programme_specialisation IS
  'V483: a postgraduate programme''s specialisations (options) — read on the programme''s one structure; ended, never deleted.';

CREATE TABLE catalogue.course_offer_specialisation (
    course_code       text NOT NULL,
    programme_code    text NOT NULL,
    level             integer NOT NULL,
    specialisation_id uuid NOT NULL REFERENCES catalogue.programme_specialisation (id),
    added_by          uuid,
    added_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (course_code, programme_code, level, specialisation_id),
    FOREIGN KEY (course_code, programme_code, level) REFERENCES catalogue.course_offer (course_code, programme_code, level)
        ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX ix_course_offer_specialisation_spec ON catalogue.course_offer_specialisation (specialisation_id);
SELECT audit.attach('catalogue.course_offer_specialisation');
COMMENT ON TABLE catalogue.course_offer_specialisation IS
  'V483: a binding named for specialisations is on those specialisations'' students'' menus only; a binding with none is for every student of the programme.';

CREATE TABLE people.student_specialisation (
    student_id        uuid PRIMARY KEY REFERENCES people.student (id) ON DELETE CASCADE,
    specialisation_id uuid NOT NULL REFERENCES catalogue.programme_specialisation (id),
    set_by            uuid,
    set_office        text,
    set_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_student_specialisation_spec ON people.student_specialisation (specialisation_id);
SELECT audit.attach('people.student_specialisation');
COMMENT ON TABLE people.student_specialisation IS 'V483: the specialisation a postgraduate student reads within their programme (one; none until the School sets it).';

CREATE FUNCTION catalogue.save_specialisation(p_programme text, p_code text, p_name text, p_id uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_prog text; v_cat text; v_code text := upper(btrim(coalesce(p_code, ''))); v_name text := btrim(coalesce(p_name, '')); v_id uuid;
BEGIN
    SELECT code, category INTO v_prog, v_cat FROM ref.programme WHERE upper(code) = upper(btrim(coalesce(p_programme, '')));
    IF v_prog IS NULL THEN RAISE EXCEPTION 'PG_SPECIALISATION_PROGRAMME: no such programme' USING ERRCODE = '23514'; END IF;
    IF v_cat IS DISTINCT FROM 'POST GRADUATE' THEN
        RAISE EXCEPTION 'PG_SPECIALISATION_PROGRAMME: % is not a postgraduate programme; specialisations are a postgraduate programme''s', v_prog USING ERRCODE = '23514';
    END IF;
    IF v_code !~ '^[A-Z0-9][A-Z0-9-]{0,11}$' THEN
        RAISE EXCEPTION 'PG_SPECIALISATION_CODE: a short code of letters and digits (up to 12), e.g. MON' USING ERRCODE = '23514';
    END IF;
    IF v_name = '' THEN RAISE EXCEPTION 'PG_SPECIALISATION_NAME: name the specialisation' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM catalogue.programme_specialisation x WHERE x.programme_code = v_prog AND x.id IS DISTINCT FROM p_id
                  AND (x.code = v_code OR lower(btrim(x.name)) = lower(v_name))) THEN
        RAISE EXCEPTION 'PG_SPECIALISATION_TAKEN: % already has a specialisation % or named %', v_prog, v_code, v_name USING ERRCODE = '23514';
    END IF;
    IF p_id IS NULL THEN
        INSERT INTO catalogue.programme_specialisation (programme_code, code, name, created_by, created_office)
        VALUES (v_prog, v_code, v_name, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
        RETURNING id INTO v_id;
    ELSE
        UPDATE catalogue.programme_specialisation SET code = v_code, name = v_name WHERE id = p_id AND programme_code = v_prog RETURNING id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'PG_SPECIALISATION_OTHER: no such specialisation of %', v_prog USING ERRCODE = '23514'; END IF;
    END IF;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION catalogue.save_specialisation(text, text, text, uuid) IS 'V483: a postgraduate programme''s specialisation added (no id) or renamed.';

CREATE FUNCTION catalogue.end_specialisation(p_id uuid, p_active boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE catalogue.programme_specialisation
       SET active = p_active,
           ended_at = CASE WHEN p_active THEN NULL ELSE now() END,
           ended_by = CASE WHEN p_active THEN NULL ELSE nullif(current_setting('moaum.actor_id', true), '')::uuid END
     WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'PG_SPECIALISATION_OTHER: no such specialisation' USING ERRCODE = '23514'; END IF;
END $$;
COMMENT ON FUNCTION catalogue.end_specialisation(uuid, boolean) IS 'V483: a specialisation ended (no longer given to a student) or restored; its students and bindings keep it.';

CREATE FUNCTION catalogue.set_offer_specialisations(p_course text, p_programme text, p_level integer, p_ids uuid[]) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE v_ids uuid[] := ARRAY(SELECT DISTINCT x FROM unnest(coalesce(p_ids, '{}'::uuid[])) x WHERE x IS NOT NULL);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = p_course AND co.programme_code = p_programme AND co.level = p_level) THEN
        RAISE EXCEPTION 'CAT_NOT_BOUND: % is not bound into % at % level', p_course, p_programme, p_level USING ERRCODE = '23514';
    END IF;
    -- the programme's own, and running (an ended one the binding already names may stay on it)
    IF EXISTS (SELECT 1 FROM unnest(v_ids) x WHERE NOT EXISTS (SELECT 1 FROM catalogue.programme_specialisation ps
                                                               WHERE ps.id = x AND ps.programme_code = p_programme
                                                                 AND (ps.active OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation y
                                                                                            WHERE y.course_code = p_course AND y.programme_code = p_programme
                                                                                              AND y.level = p_level AND y.specialisation_id = x)))) THEN
        RAISE EXCEPTION 'PG_SPECIALISATION_OTHER: a binding is named only for the programme''s own specialisations still running' USING ERRCODE = '23514';
    END IF;
    DELETE FROM catalogue.course_offer_specialisation x
     WHERE x.course_code = p_course AND x.programme_code = p_programme AND x.level = p_level AND NOT (x.specialisation_id = ANY (v_ids));
    INSERT INTO catalogue.course_offer_specialisation (course_code, programme_code, level, specialisation_id, added_by)
    SELECT p_course, p_programme, p_level, x, nullif(current_setting('moaum.actor_id', true), '')::uuid FROM unnest(v_ids) x
    ON CONFLICT DO NOTHING;
    RETURN cardinality(v_ids);
END $$;
COMMENT ON FUNCTION catalogue.set_offer_specialisations(text, text, integer, uuid[]) IS
  'V483: the specialisations a binding is for (none: every student of the programme).';

CREATE FUNCTION people.set_student_specialisation(p_student uuid, p_specialisation uuid) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_prog text; v_code text;
BEGIN
    SELECT programme_code INTO v_prog FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    IF p_specialisation IS NULL THEN
        DELETE FROM people.student_specialisation WHERE student_id = p_student;
        RETURN NULL;
    END IF;
    SELECT ps.code INTO v_code FROM catalogue.programme_specialisation ps WHERE ps.id = p_specialisation AND ps.programme_code = v_prog AND ps.active;
    IF v_code IS NULL THEN
        RAISE EXCEPTION 'PG_SPECIALISATION_OTHER: a student reads a specialisation of their own programme (%) still running', v_prog USING ERRCODE = '23514';
    END IF;
    INSERT INTO people.student_specialisation (student_id, specialisation_id, set_by, set_office)
    VALUES (p_student, p_specialisation, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    ON CONFLICT (student_id) DO UPDATE SET specialisation_id = EXCLUDED.specialisation_id, set_by = EXCLUDED.set_by,
                                           set_office = EXCLUDED.set_office, set_at = now()
     WHERE people.student_specialisation.specialisation_id IS DISTINCT FROM EXCLUDED.specialisation_id;
    RETURN v_code;
END $$;
COMMENT ON FUNCTION people.set_student_specialisation(uuid, uuid) IS 'V483: the specialisation a student reads, set or cleared (NULL).';

CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(offering_id uuid, course_code text, title text, units integer, kind text, basis text, owner_dept text, carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V380: the student's stream: a CCE student is offered the Centre's classes, every other student the full-time ones
    WITH s AS (SELECT st.*, people.student_stream(st.id) AS stream,   -- V389: and the School's classes for a PG student
                      -- V483: the student's specialisation within their programme (none: the courses for every student only)
                      (SELECT ss.specialisation_id FROM people.student_specialisation ss
                         JOIN catalogue.programme_specialisation ps ON ps.id = ss.specialisation_id AND ps.programme_code = st.programme_code
                        WHERE ss.student_id = st.id) AS specialisation_id
                 FROM people.student st WHERE st.id = p_student),
    -- V366: the GST/EPS courses of the programme at this level the student has already passed
    gst_passed AS (SELECT x.course_code FROM finance.gst_eps_rows(p_session, p_student) x WHERE x.status = 'ALREADY_PASSED'),
    offered AS (
        SELECT o.id AS offering_id, c.code, c.title, coalesce(co.units, c.units) AS units, c.kind, co.basis, c.dept_code   -- V460: the programme's units
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = s.stream
         WHERE (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
           AND NOT (c.kind = 'GST' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))
           -- V483: a binding named for specialisations is offered to the students of those specialisations only
           AND (NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x
                             WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level)
                OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x
                            WHERE x.course_code = co.course_code AND x.programme_code = co.programme_code AND x.level = co.level
                              AND x.specialisation_id = s.specialisation_id))),
    -- V402: a BSU- code and its MOAU- twin are both on offer; where both reach the student, the student sees their cohort's
    -- family only (cohorts admitted from the stated session register MOAU-, earlier cohorts BSU-); a code with no twin on offer,
    -- or the rule unstated, is shown as before. Carry-overs and deferred courses come by their own code and are untouched.
    eligible AS (
        SELECT e.* FROM offered e
         WHERE NOT (catalogue.other_familys_code(p_student, e.code)
                    AND EXISTS (SELECT 1 FROM offered e2 WHERE e2.code = catalogue.twin_by_code(e.code)))),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, catalogue.units_for(c.code, s.programme_code, NULL) AS units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)),
    -- a course set aside by an approved deferment, due since the student returned, offered this semester and not yet passed
    deferred AS (
        SELECT o.id AS offering_id, c.code, c.title, catalogue.units_for(c.code, s.programme_code, NULL) AS units, c.kind, 'Deferred'::text AS basis, c.dept_code,
               dc.original_session || ' semester ' || dc.original_semester AS deferred_from
          FROM people.deferred_courses(p_student) dc
          JOIN catalogue.course c ON c.code = dc.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE o.stream = s.stream AND dc.status = 'DEFERRED' AND dc.due
           AND (dc.original_session, dc.original_semester) < (p_session, p_semester)
           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code))
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis IN ('Carryover','Deferred')), x.failed_in, p.surname || ', ' || p.given_names,
           (x.basis = 'Deferred'), x.deferred_from
      FROM (SELECT e.*, NULL::text AS failed_in, NULL::text AS deferred_from FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
              AND NOT EXISTS (SELECT 1 FROM deferred df WHERE df.offering_id = e.offering_id)
            UNION ALL SELECT cv.*, NULL::text AS deferred_from FROM carry cv
            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, (x.basis = 'Deferred') DESC, x.kind, x.code;
$function$;
COMMENT ON FUNCTION registration.student_menu(uuid, text, integer) IS
  'The courses a student may register in a semester (V380 stream, V402 code family, V460 units); V483: a binding named for specialisations only for those specialisations'' students.';

COMMIT;

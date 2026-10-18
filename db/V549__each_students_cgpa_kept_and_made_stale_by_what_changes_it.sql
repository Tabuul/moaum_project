-- V549: each student's CGPA kept, made stale by what changes it, and read from what is kept.
--
-- The Records & Queries register shows every student's CGPA, worked out from the published results (assessment.scope_cgpa,
-- V531): for the whole University that is every live student's every registered course and sheet, about 7 s on the live-shaped
-- copy on a fresh connection — each time the list is opened.
--   * assessment.cgpa_kept holds each student's CGPA with two counters: stale_gen, raised whenever anything the CGPA is read from
--     changes for the student, and kept_gen, the stale_gen the kept CGPA was worked out at. A kept CGPA is current only while the
--     two agree, so a change committed while the CGPA is being worked out is never taken as done.
--   * What raises it, by statement (one upsert of the students touched, not one a row): a score entered, amended or removed
--     (assessment.score); a sheet added, moved through its stages or removed (assessment.score_sheet: the students registered for
--     its class); an exam sitting's kind changed (assessment.exam_session); a course added to, changed on or dropped from a
--     registration (registration.entry); a registration changed or removed (registration.course_registration); and the grading
--     itself (policy.grade_band, a grading policy.version) for every student. A grading version comes into force on a date with no
--     write at all, so every CGPA is also made stale once a night.
--   * assessment.kept_cgpa(students): the kept CGPA of those current, and scope_cgpa's for the rest, in one answer — the same
--     figures scope_cgpa gives, whatever is kept.
--   * assessment.refresh_kept_cgpa(limit): every student held, and the stale ones worked out again, a batch at a time (the API's
--     CgpaKeeper every minute; assessment.cgpa_stale_all() at night).
--   * The kept copy is derived from the results, which are on the audit spine; it is exempt from it.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V549: each student''s CGPA kept and made stale by what changes it', true);

CREATE TABLE assessment.cgpa_kept (
    student_id  uuid PRIMARY KEY REFERENCES people.student (id) ON DELETE CASCADE,
    cgpa        numeric,
    stale_gen   bigint NOT NULL DEFAULT 1,
    kept_gen    bigint,
    computed_at timestamptz
);
CREATE INDEX ix_cgpa_kept_stale ON assessment.cgpa_kept (student_id) WHERE kept_gen IS DISTINCT FROM stale_gen;
COMMENT ON TABLE assessment.cgpa_kept IS
  'V549: each student''s CGPA as assessment.scope_cgpa works it out, current while kept_gen = stale_gen; stale_gen is raised by whatever changes it';
INSERT INTO audit.exemption (relid, reason) VALUES
  ('assessment.cgpa_kept'::regclass, 'V549: a kept copy of each student''s CGPA, worked out again from the published results (which are on the spine) whenever they change');

-- the students named made stale; a student no longer on the register (removed in the same statement) is passed over
CREATE FUNCTION assessment.cgpa_stale(p_students uuid[])
RETURNS integer
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    IF p_students IS NULL OR cardinality(p_students) = 0 THEN RETURN 0; END IF;
    INSERT INTO assessment.cgpa_kept AS k (student_id)
    SELECT DISTINCT x FROM unnest(p_students) x
     WHERE x IS NOT NULL AND EXISTS (SELECT 1 FROM people.student s WHERE s.id = x)
     ORDER BY 1
    ON CONFLICT (student_id) DO UPDATE SET stale_gen = k.stale_gen + 1;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION assessment.cgpa_stale(uuid[]) IS 'V549: the kept CGPA of the students named made stale';

CREATE FUNCTION assessment.cgpa_stale_all()
RETURNS integer
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
    UPDATE assessment.cgpa_kept SET stale_gen = stale_gen + 1;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION assessment.cgpa_stale_all() IS 'V549: every kept CGPA made stale — the grading changed, or the nightly pass';

-- one trigger function for every table watched, by statement: TG_ARGV[0] says how a row names its students
CREATE FUNCTION assessment.cgpa_stale_by_statement()
RETURNS trigger
LANGUAGE plpgsql AS $fn$
DECLARE ids uuid[] := '{}';
BEGIN
    IF TG_ARGV[0] = 'grading' THEN
        IF TG_OP <> 'DELETE' THEN
            IF EXISTS (SELECT 1 FROM n WHERE n.kind = 'grading') THEN PERFORM assessment.cgpa_stale_all(); RETURN NULL; END IF;
        END IF;
        IF TG_OP <> 'INSERT' THEN
            IF EXISTS (SELECT 1 FROM o WHERE o.kind = 'grading') THEN PERFORM assessment.cgpa_stale_all(); END IF;
        END IF;
        RETURN NULL;
    ELSIF TG_ARGV[0] = 'band' THEN
        PERFORM assessment.cgpa_stale_all();
        RETURN NULL;
    END IF;
    -- each branch its own statement: a statement names the columns of the one table it is fired for
    IF TG_ARGV[0] = 'student' THEN
        IF TG_OP <> 'DELETE' THEN ids := ids || ARRAY(SELECT DISTINCT n.student_id FROM n); END IF;
        IF TG_OP <> 'INSERT' THEN ids := ids || ARRAY(SELECT DISTINCT o.student_id FROM o); END IF;
    ELSIF TG_ARGV[0] = 'registration' THEN
        IF TG_OP <> 'DELETE' THEN
            ids := ids || ARRAY(SELECT DISTINCT cr.student_id FROM (SELECT DISTINCT n.registration_id FROM n) x
                                  JOIN registration.course_registration cr ON cr.id = x.registration_id);
        END IF;
        IF TG_OP <> 'INSERT' THEN
            ids := ids || ARRAY(SELECT DISTINCT cr.student_id FROM (SELECT DISTINCT o.registration_id FROM o) x
                                  JOIN registration.course_registration cr ON cr.id = x.registration_id);
        END IF;
    ELSIF TG_ARGV[0] = 'sheet' THEN
        IF TG_OP <> 'DELETE' THEN
            ids := ids || ARRAY(SELECT DISTINCT cr.student_id FROM (SELECT DISTINCT n.offering_id FROM n) x
                                  JOIN registration.entry e ON e.offering_id = x.offering_id
                                  JOIN registration.course_registration cr ON cr.id = e.registration_id);
        END IF;
        IF TG_OP <> 'INSERT' THEN
            ids := ids || ARRAY(SELECT DISTINCT cr.student_id FROM (SELECT DISTINCT o.offering_id FROM o) x
                                  JOIN registration.entry e ON e.offering_id = x.offering_id
                                  JOIN registration.course_registration cr ON cr.id = e.registration_id);
        END IF;
    ELSIF TG_ARGV[0] = 'sitting' THEN
        ids := ARRAY(SELECT DISTINCT cr.student_id FROM (SELECT DISTINCT n.id FROM n) x
                       JOIN assessment.score_sheet sh ON sh.exam_session_id = x.id
                       JOIN registration.entry e ON e.offering_id = sh.offering_id
                       JOIN registration.course_registration cr ON cr.id = e.registration_id);
    END IF;
    PERFORM assessment.cgpa_stale(ids);
    RETURN NULL;
END $fn$;
COMMENT ON FUNCTION assessment.cgpa_stale_by_statement() IS
  'V549: a statement on a table the CGPA is read from makes the kept CGPA of the students it touches stale (TG_ARGV[0]: student, registration, sheet, sitting, grading, band)';

-- a trigger with transition tables fires on one event: three a table
DO $$
DECLARE t record;
BEGIN
    FOR t IN SELECT * FROM (VALUES ('assessment.score', 'student', 'cgpa_score'),
                                   ('registration.course_registration', 'student', 'cgpa_registration'),
                                   ('registration.entry', 'registration', 'cgpa_entry'),
                                   ('assessment.score_sheet', 'sheet', 'cgpa_sheet'),
                                   ('policy.version', 'grading', 'cgpa_grading')) v(tbl, how, name)
    LOOP
        EXECUTE format('CREATE TRIGGER %I AFTER INSERT ON %s REFERENCING NEW TABLE AS n FOR EACH STATEMENT EXECUTE FUNCTION assessment.cgpa_stale_by_statement(%L)',
                       'trg_' || t.name || '_ins', t.tbl, t.how);
        EXECUTE format('CREATE TRIGGER %I AFTER UPDATE ON %s REFERENCING OLD TABLE AS o NEW TABLE AS n FOR EACH STATEMENT EXECUTE FUNCTION assessment.cgpa_stale_by_statement(%L)',
                       'trg_' || t.name || '_upd', t.tbl, t.how);
        EXECUTE format('CREATE TRIGGER %I AFTER DELETE ON %s REFERENCING OLD TABLE AS o FOR EACH STATEMENT EXECUTE FUNCTION assessment.cgpa_stale_by_statement(%L)',
                       'trg_' || t.name || '_del', t.tbl, t.how);
    END LOOP;
END $$;
CREATE TRIGGER trg_cgpa_sitting_upd AFTER UPDATE ON assessment.exam_session REFERENCING OLD TABLE AS o NEW TABLE AS n
    FOR EACH STATEMENT EXECUTE FUNCTION assessment.cgpa_stale_by_statement('sitting');
CREATE TRIGGER trg_cgpa_band AFTER INSERT OR UPDATE OR DELETE ON policy.grade_band
    FOR EACH STATEMENT EXECUTE FUNCTION assessment.cgpa_stale_by_statement('band');

-- the students' CGPA: kept where current, worked out for the rest — both read by one-off plans, never a plan cached for another size
CREATE FUNCTION assessment.kept_cgpa(p_students uuid[])
RETURNS TABLE(student_id uuid, cgpa numeric)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_rest uuid[];
BEGIN
    RETURN QUERY EXECUTE
        'SELECT k.student_id, k.cgpa FROM (SELECT DISTINCT x FROM unnest($1) x) t JOIN assessment.cgpa_kept k ON k.student_id = t.x WHERE k.kept_gen = k.stale_gen'
        USING p_students;
    EXECUTE 'SELECT coalesce(array_agg(t.x), ''{}'') FROM (SELECT DISTINCT x FROM unnest($1) x WHERE x IS NOT NULL) t
              WHERE NOT EXISTS (SELECT 1 FROM assessment.cgpa_kept k WHERE k.student_id = t.x AND k.kept_gen = k.stale_gen)'
        INTO v_rest USING p_students;
    IF cardinality(v_rest) > 0 THEN
        RETURN QUERY EXECUTE 'SELECT g.student_id, g.cgpa FROM assessment.scope_cgpa($1) g' USING v_rest;
    END IF;
END $fn$;
COMMENT ON FUNCTION assessment.kept_cgpa(uuid[]) IS
  'V549: the students'' CGPA — kept where current (assessment.cgpa_kept), worked out by assessment.scope_cgpa for the rest; the same figures scope_cgpa gives';

-- every student held, and up to p_limit stale ones worked out again
CREATE FUNCTION assessment.refresh_kept_cgpa(p_limit integer DEFAULT 5000)
RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE v_ids uuid[]; v_gens bigint[]; n_seed int; n_done int := 0;
BEGIN
    INSERT INTO assessment.cgpa_kept (student_id)
    SELECT s.id FROM people.student s WHERE NOT EXISTS (SELECT 1 FROM assessment.cgpa_kept k WHERE k.student_id = s.id)
    ON CONFLICT (student_id) DO NOTHING;
    GET DIAGNOSTICS n_seed = ROW_COUNT;
    SELECT array_agg(x.student_id ORDER BY x.student_id), array_agg(x.stale_gen ORDER BY x.student_id) INTO v_ids, v_gens
      FROM (SELECT k.student_id, k.stale_gen FROM assessment.cgpa_kept k WHERE k.kept_gen IS DISTINCT FROM k.stale_gen
             ORDER BY k.student_id LIMIT greatest(coalesce(p_limit, 5000), 1)) x;
    IF v_ids IS NOT NULL THEN
        -- written only where nothing made the student stale again meanwhile (stale_gen still the one read)
        EXECUTE 'UPDATE assessment.cgpa_kept k SET cgpa = g.cgpa, kept_gen = t.gen, computed_at = clock_timestamp()
                   FROM unnest($1::uuid[], $2::bigint[]) AS t(id, gen)
                   LEFT JOIN assessment.scope_cgpa($1) g ON g.student_id = t.id
                  WHERE k.student_id = t.id AND k.stale_gen = t.gen'
            USING v_ids, v_gens;
        GET DIAGNOSTICS n_done = ROW_COUNT;
    END IF;
    RETURN jsonb_build_object('seeded', n_seed, 'refreshed', n_done,
                              'left', (SELECT count(*) FROM assessment.cgpa_kept k WHERE k.kept_gen IS DISTINCT FROM k.stale_gen));
END $fn$;
COMMENT ON FUNCTION assessment.refresh_kept_cgpa(integer) IS
  'V549: every student held in assessment.cgpa_kept, and up to p_limit stale CGPAs worked out again (a batch of the CgpaKeeper job)';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════════
--  V776 · SIWES: a programme is added whether or not its SIWES course is known yet, and SIWES courses are recognised from the catalogue
-- ═══════════════════════════════════════════════════════════════════════════════
--  The user's word of 22 November 2026, with the SIWES desk's refusal on screen ("no SIWES course reaches the 300 Level students of
--  B.Sc. COMPUTER SCIENCE … the programme takes part in 2025/2026 only once each is mapped"): "remove this restriction and let admin
--  add the programmes that their students are on SIWES … SIWES carries different course code and title for different department …
--  once you see SIWES or Industrial Training but different course code, recognize it as SIWES, or let me add all the SIWES courses so
--  you will understand that this is SIWES and it requires paying 4000 … before the student registers".
--
--  What was wrong (V752). A programme could be added to an open period only once a SIWES course was mapped for every curriculum of its
--  300 Level students (SIWES_COURSE_MISSING) — and the desk sets a programme's course only on a programme already added, so a
--  programme with no course mapped could not be added at all. And a programme's SIWES course had to be mapped by hand, one programme
--  and curriculum at a time, although the catalogue already knows which courses are SIWES (catalogue.course.industrial_training,
--  V155) — a marker seeded once from the titles of that day and never kept up for the courses added since.
--
--  Now:
--    · registration.siwes_add_programme and siwes_set_period no longer refuse for a missing course. A cohort no SIWES course reaches
--      is not bound (V503 stands for it, as before) until one does; the desk lists it.
--    · A programme's SIWES course is recognised from the catalogue (registration.siwes_course_recognised): a SIWES course the
--      programme's own structure carries at 300 Level, taught in the Second Semester (of several, the one of most units; several of
--      equal standing: none — it is never a guess); else the one such course of the programme's department that no programme's
--      structure carries and no other programme owns. It is WRITTEN DOWN as the programme's SIWES course (registration.siwes_course,
--      with how it was found) in one place only, and only where it cannot bind a semester the University did not make a SIWES
--      semester: as the programme is added to a session's SIWES (or when a course is added to the SIWES courses that gives a waiting
--      programme its structure's course), for a programme whose 300 Level Second Semester IS a SIWES attachment semester — V503's
--      own test, the SIWES course alone with no other required course (registration.siwes_units) — and where every waiting
--      curriculum of the programme has a recognised course. Everything else the catalogue offers is shown on the desk — the course
--      found, the several to choose from, the SIWES course a programme carries at another level or in the First Semester — and the
--      Academic Office takes it with one press (Set course), knowing what that binds. A written-down course stands exactly as a course
--      set on the desk stands: nothing the catalogue does afterwards — a draft course, a structure upload, a course marked or
--      retitled — moves it under students who have paid, and V752's rules (replaced, never taken away while students have paid or
--      registered) hold it; the desk shows when the catalogue would now give another. registration.siwes_course_of, the one reading
--      every part of the portal uses, is unchanged.
--    · A SIWES course is a catalogue course marked industrial_training. A course whose title reads SIWES, Industrial Training,
--      Industrial Attachment or Industrial Work Experience is marked as it is added or retitled (trigger), and those already in the
--      catalogue unmarked are marked here. The Academic Office adds a course to the SIWES courses, or takes one off, on the desk
--      (registration.siwes_mark_course) — never one set for a programme, one students have paid or registered on, or one whose
--      attachment semester students are registered in.
--    · "SIWES already passed" is a pass in the programme's own SIWES course or a SIWES course of 300 Level (by the catalogue or the
--      programme's structure) — not SIWES I at 200 Level, now that every SIWES-titled course of every level is marked.
--    · A programme's SIWES course is a 300 Level course: the desk refuses to set one the programme carries only at another level
--      (SIWES registration is the 300 Level cohort's: its fee, its Second Semester).
--    · The ₦4,000 SIWES registration fee is unchanged: it is paid before the SIWES course is registered (registration.siwes_register).
-- ═══════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V776: SIWES courses recognised from the catalogue; a programme added before its course is known', true);

-- presence: every function restated here is as V752 left it (another change since would be overwritten); registration.siwes_course_of
-- is read, not restated — the rows it reads are what a recognition writes
DO $$
DECLARE f text; h text; want text;
BEGIN
    FOR f, want IN VALUES
        ('registration.siwes_course_of(text,text)', '7da65e49832e8faad32b553e9b7a8409'),
        ('registration.siwes_add_programme(text,text)', '9dd3105253efa211d3471bc2b8991eda'),
        ('registration.siwes_set_period(text,text,date,date,date,date,integer,text)', 'a569e4964a3ab8e03a818fd52b470477'),
        ('registration.siwes_set_course(text,text,text)', 'b29c54e7ecc6e4ec46e8c90568c16c19'),
        ('registration.siwes_passed_among(text,uuid[])', '25c1b031c56c10416777450a7d464933'),
        ('registration.siwes_config(text)', 'b1c4c0560bf7e9bf85c7474d32da0d17')
    LOOP
        SELECT md5(replace(p.prosrc, E'\r', '')) INTO h FROM pg_proc p WHERE p.oid = to_regprocedure(f);
        IF h IS DISTINCT FROM want THEN
            RAISE EXCEPTION 'V776: % is not as V752 left it (restate this migration from its live text)', f;
        END IF;
    END LOOP;
END $$;

-- ── 1 · a SIWES course, by its title ────────────────────────────────────────────────────────────────────────────────────────────
/* a course title that reads as SIWES: the words V155 seeded the marker from. Each department carries the course under its own code and
   title ("SIWES", "Students Industrial Work Experience Scheme", "Industrial Training I", "Industrial Attachment"). "Industrial Work"
   alone is not enough (an Industrial Workshop is not SIWES): Industrial Work Experience */
CREATE FUNCTION catalogue.reads_as_siwes(p_title text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(p_title ~* '(siwes|industrial\s+(training|attachment|work[\s-]+experience))', false);
$$;
COMMENT ON FUNCTION catalogue.reads_as_siwes(text) IS
  'V776: whether a course title reads as SIWES — SIWES, Industrial Training, Industrial Attachment, Industrial Work Experience — whatever the course''s code. Such a course is marked industrial_training as it is added or retitled.';

/* a course added, or retitled into such a title, is marked a SIWES course. A course the Academic Office has taken off the SIWES
   courses stays off while its title stands */
CREATE FUNCTION catalogue.course_marks_siwes() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF catalogue.reads_as_siwes(NEW.title) AND (TG_OP = 'INSERT' OR NOT catalogue.reads_as_siwes(OLD.title)) THEN
        NEW.industrial_training := true;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_course_marks_siwes BEFORE INSERT OR UPDATE OF title ON catalogue.course
    FOR EACH ROW EXECUTE FUNCTION catalogue.course_marks_siwes();

-- the courses already in the catalogue whose title reads so and are not marked (added since V155 seeded the marker) — the ended ones
-- too, so that one restored later is a SIWES course as it comes back (a restore touches neither the title nor the marker). An ended
-- course is recognised for no programme and makes no attachment semester while it is ended
UPDATE catalogue.course SET industrial_training = true
 WHERE NOT industrial_training AND catalogue.reads_as_siwes(title);

-- ── 2 · the SIWES course of a programme: recognised from the catalogue, and written down ─────────────────────────────────────────
-- how a programme's SIWES course came to be the programme's: set on the desk, or recognised in the programme's own structure or as
-- its department's one course. A recognised course stands exactly as a set one does (V752's rules); the desk says which it is
ALTER TABLE registration.siwes_course ADD COLUMN origin text NOT NULL DEFAULT 'DESK'
    CONSTRAINT ck_siwes_course_origin CHECK (origin IN ('DESK', 'STRUCTURE', 'DEPARTMENT'));
COMMENT ON COLUMN registration.siwes_course.origin IS
  'V776: how the course became the programme''s SIWES course — DESK (set by the Academic Office on the SIWES desk), STRUCTURE (recognised: the SIWES course the programme''s own 300 Level Second Semester structure carries) or DEPARTMENT (recognised: the one SIWES course of the programme''s department). Recognised as the programme was added, the period saved or a course added to the SIWES courses; it stands as a set one does.';

/* the SIWES courses the catalogue offers a programme and curriculum, for the recognition and for the desk's hints:
   · STRUCTURE: the SIWES courses (industrial_training, not ended, taught in the Second Semester) the programme's own structure carries
     at 300 Level (catalogue.course_offer) — the student's own curriculum's first, a LIVE one first, then the one of most units (the
     only load V503's attachment semester accepts; a 1-unit "SIWES report" beside the 6-unit course is never the SIWES course, whoever
     hosts either), the programme's own department's before another department's among equal units;
   · DEPARTMENT, only for a programme whose own structure carries no SIWES course at all (at any level: one it carries at 400 Level is
     not its 300 Level students'): the SIWES courses of the programme's department at 300 Level in the Second Semester that no
     programme's structure carries and no other programme owns — the LIVE ones when one is LIVE (a draft never unseats the
     department's live course).
   top: the course stands alone at the head of its list only when exactly one row is top */
CREATE FUNCTION registration.siwes_course_candidates(p_programme text, p_curriculum text)
RETURNS TABLE(course_code text, origin text, units integer, top boolean) LANGUAGE sql STABLE AS $$
    WITH own AS (
        SELECT c.code, coalesce(co.units, c.units) AS units,
               rank() OVER (ORDER BY (c.curriculum IS NOT DISTINCT FROM p_curriculum) DESC, (c.state = 'LIVE') DESC,
                                     coalesce(co.units, c.units) DESC,
                                     (c.dept_code IS NOT DISTINCT FROM pr.dept_code) DESC,
                                     (c.curriculum IS NULL) DESC, c.curriculum DESC) AS rk,
               max(coalesce(co.units, c.units)) OVER (PARTITION BY (c.state = 'LIVE')) AS stand_max
          FROM catalogue.course_offer co
          JOIN catalogue.course c ON c.code = co.course_code
          JOIN ref.programme pr ON pr.code = co.programme_code
         WHERE co.programme_code = p_programme AND co.level = 300
           AND c.industrial_training AND c.state <> 'ENDED' AND catalogue.runs_in(c.semester, c.both_semesters, 2)
           AND (c.curriculum IS NULL OR p_curriculum IS NULL OR c.curriculum = p_curriculum OR registration.curriculum_open())),
    dept AS (
        SELECT c.code, c.units, c.state
          FROM ref.programme p
          JOIN catalogue.course c ON c.dept_code = p.dept_code
         WHERE p.code = p_programme AND c.level = 300
           AND c.industrial_training AND c.state <> 'ENDED' AND catalogue.runs_in(c.semester, c.both_semesters, 2)
           AND (c.curriculum IS NULL OR p_curriculum IS NULL OR c.curriculum = p_curriculum OR registration.curriculum_open())
           AND (c.owner_programme IS NULL OR c.owner_programme = p_programme)
           AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer o2 WHERE o2.course_code = c.code)
           AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer o3 JOIN catalogue.course c3 ON c3.code = o3.course_code
                            WHERE o3.programme_code = p_programme AND c3.industrial_training AND c3.state <> 'ENDED'))
    -- the head stands only where it is also the course of most units among its live (or not live) peers: a course labelled for the
    -- student's curriculum does not beat an unlabelled course of more units — with both candidates the programme waits and the desk lists them
    SELECT o.code, 'STRUCTURE'::text, o.units, o.rk = 1 AND o.units = o.stand_max FROM own o
    UNION ALL
    SELECT d.code, 'DEPARTMENT'::text, d.units, (d.state = 'LIVE' OR NOT EXISTS (SELECT 1 FROM dept l WHERE l.state = 'LIVE')) FROM dept d;
$$;
COMMENT ON FUNCTION registration.siwes_course_candidates(text, text) IS
  'V776: the SIWES courses the catalogue offers a programme and curriculum — those its own 300 Level Second Semester structure carries (STRUCTURE), else, for a programme whose structure carries none at any level, those of its department that no programme''s structure carries and no other programme owns (DEPARTMENT); top marks the head of the list. Read by the recognition and by the desk''s hints, never by the registration.';

/* the SIWES course recognised for a programme and curriculum: the one candidate that stands alone at the head of its list. Several
   of equal standing, or none: NULL — a course is never taken by a guess; the Academic Office sets it on the desk */
CREATE FUNCTION registration.siwes_course_recognised(p_programme text, p_curriculum text, OUT course_code text, OUT origin text)
LANGUAGE sql STABLE AS $$
    SELECT min(k.course_code), min(k.origin)
      FROM registration.siwes_course_candidates(p_programme, p_curriculum) k
     WHERE k.top
    HAVING count(*) = 1;
$$;
COMMENT ON FUNCTION registration.siwes_course_recognised(text, text) IS
  'V776: the SIWES course the catalogue gives a programme and curriculum with no guess — the one candidate at the head of registration.siwes_course_candidates — and how it was found (STRUCTURE, DEPARTMENT); NULLs when there is none or several of equal standing.';

/* the SIWES course the catalogue gives a programme written down (registration.siwes_course), for each curriculum of its students that no
   course reaches yet — and only where that cannot bind a semester the University did not make a SIWES semester:
   · the programme's 300 Level Second Semester is a SIWES attachment semester (registration.siwes_units: V503's test, the SIWES course
     alone with no other required course) — otherwise the course is shown on the desk (siwes_config found) and the Academic Office takes
     it with Set course, knowing what it binds;
   · the course is the programme's own structure's (STRUCTURE), never the department's guess;
   · EVERY waiting curriculum of the programme has a recognised course (while every curriculum's courses are open the reader hands a
     row to the programme's other curriculum, so one curriculum's row must never answer for another that recognised none): all or nothing;
   · with p_only_course (a course just added to the SIWES courses), only where that course gives a waiting curriculum its course or has just made
     the semester an attachment semester;
   · never for a programme that takes part in a planned or current session whose SIWES period is CLOSED (the row is the programme's for
     every session).
   All the recognitions are read before anything is written. One row for every curriculum (curriculum NULL) when the programme has no
   row yet and every curriculum recognises the same course; a row for each curriculum otherwise. Never over a row that is there: a
   course set or written down before stands. Called by the desk's own acts — a programme added, a course added to the SIWES courses —
   never by a reading and never by saving the period */
CREATE FUNCTION registration.siwes_pin_courses(p_programme text, p_only_course text DEFAULT NULL) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE who uuid := coalesce(nullif(current_setting('moaum.actor_id', true), '')::uuid, '00000000-0000-0000-0000-000000000000');
        v_office text := coalesce(nullif(current_setting('moaum.actor_office', true), ''), 'academic');
        v_rows jsonb; v_keys int; v_waiting int; v_found int; v_touched int; v_courses int; n int := 0;
BEGIN
    IF registration.siwes_units(p_programme, 300, 2) IS NULL THEN RETURN 0; END IF;   -- not an attachment semester: the desk shows it, the office decides
    -- the row is the programme's for every session, so a programme that takes part in a planned or current session whose SIWES period is
    -- CLOSED is never written down by a desk act on another session: its cohort would be bound when nobody can pay or register
    IF EXISTS (SELECT 1 FROM registration.siwes_programme sp
                 JOIN registration.siwes_period pd ON pd.session = sp.session AND pd.state = 'CLOSED'
                 JOIN policy.academic_session a ON a.name = sp.session AND a.state IN ('PLANNED', 'CURRENT')
                WHERE sp.programme_code = p_programme) THEN RETURN 0; END IF;
    -- each curriculum the programme's students in study hold (none recorded: NULL; no student yet: every curriculum), whether a
    -- course reaches it already, and the course the catalogue gives it — all read before anything is written
    SELECT coalesce(jsonb_agg(jsonb_build_object('curriculum', k.curriculum,
                                                 'reached', registration.siwes_course_of(p_programme, k.curriculum) IS NOT NULL,
                                                 'course', r.course_code, 'origin', r.origin)), '[]'::jsonb)
      INTO v_rows
      FROM (SELECT DISTINCT s.curriculum_version AS curriculum
              FROM people.student s
             WHERE s.programme_code = p_programme AND s.status IN ('ACTIVE', 'PROBATION') AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
            UNION
            SELECT NULL WHERE NOT EXISTS (SELECT 1 FROM people.student s
                                           WHERE s.programme_code = p_programme AND s.status IN ('ACTIVE', 'PROBATION')
                                             AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE'))) k
      LEFT JOIN LATERAL registration.siwes_course_recognised(p_programme, k.curriculum) r ON true;
    SELECT count(*) FILTER (WHERE NOT (t->>'reached')::boolean),
           count(*) FILTER (WHERE NOT (t->>'reached')::boolean AND t->>'origin' = 'STRUCTURE'),
           count(*) FILTER (WHERE NOT (t->>'reached')::boolean AND t->>'origin' = 'STRUCTURE' AND t->>'course' = p_only_course),
           count(*), count(DISTINCT t->>'course') FILTER (WHERE NOT (t->>'reached')::boolean)
      INTO v_waiting, v_found, v_touched, v_keys, v_courses
      FROM jsonb_array_elements(v_rows) t;
    IF v_waiting = 0 OR v_found < v_waiting THEN RETURN 0; END IF;   -- all or nothing: every waiting curriculum has a course
    -- with p_only_course: the course just marked gives a waiting curriculum its course, or has just made the semester an attachment semester
    IF p_only_course IS NOT NULL AND v_touched = 0
       AND registration.siwes_units_without(p_programme, 300, 2, p_only_course) IS NOT DISTINCT FROM registration.siwes_units(p_programme, 300, 2) THEN RETURN 0; END IF;
    IF v_waiting = v_keys AND v_courses = 1 AND NOT EXISTS (SELECT 1 FROM registration.siwes_course sc WHERE sc.programme_code = p_programme) THEN
        INSERT INTO registration.siwes_course (programme_code, curriculum, course_code, set_by, set_office, origin)
        SELECT p_programme, NULL, min(t->>'course'), who, v_office, 'STRUCTURE' FROM jsonb_array_elements(v_rows) t
        ON CONFLICT (programme_code, (coalesce(curriculum, ''))) DO NOTHING;
        GET DIAGNOSTICS n = ROW_COUNT;
    ELSE
        -- a row for each named waiting curriculum; the students with no curriculum recorded read the programme's other rows
        -- (registration.siwes_course_of): a row "for every curriculum" is not made from one curriculum's answer
        INSERT INTO registration.siwes_course (programme_code, curriculum, course_code, set_by, set_office, origin)
        SELECT p_programme, t->>'curriculum', t->>'course', who, v_office, 'STRUCTURE'
          FROM jsonb_array_elements(v_rows) t
         WHERE NOT (t->>'reached')::boolean AND (t->>'curriculum' IS NOT NULL OR v_keys = 1)
         ORDER BY t->>'curriculum'
        ON CONFLICT (programme_code, (coalesce(curriculum, ''))) DO NOTHING;
        GET DIAGNOSTICS n = ROW_COUNT;
    END IF;
    RETURN n;
END $$;
COMMENT ON FUNCTION registration.siwes_pin_courses(text, text) IS
  'V776: writes down the SIWES course the programme''s own 300 Level structure gives it (registration.siwes_course_recognised, origin STRUCTURE) for each curriculum of its students that no course reaches yet — only for a programme whose 300 Level Second Semester is a SIWES attachment semester (registration.siwes_units), only when every waiting curriculum has a recognised course, never over a course already set or written down, and with p_only_course only that course. Run by the desk''s acts (registration.siwes_add_programme, siwes_mark_course); never by a reading, never by saving the period. Answers the rows written.';

/* what the catalogue offers a programme and curriculum, for the desk, from ONE read of the candidates (the desk's configuration asks it
   once for each programme, curriculum and cohort: reading the candidates three times each made the page a third slower):
   found — the course the catalogue gives (the one candidate at the head of the list), where none is read for the programme and curriculum,
           or where the row read was written down from the catalogue (not set on the desk) and the catalogue would now give another;
   choices — every candidate, where none is read;  elsewhere — the SIWES courses its structure carries where SIWES registration does not
   reach them, where none is read. A course set on the desk has no offer beside it ('{}').
   p_cohort: for a cohort no live SIWES course reaches — the offer is made whatever row is read (an ended course) */
CREATE FUNCTION registration.siwes_course_offer(p_programme text, p_curriculum text, p_cohort boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v_read text := registration.siwes_course_of(p_programme, p_curriculum); v_top text; v_n int; v_choices jsonb;
BEGIN
    IF NOT p_cohort AND v_read IS NOT NULL AND registration.siwes_course_source(p_programme, p_curriculum) = 'SET' THEN
        RETURN '{}'::jsonb;
    END IF;
    WITH c AS MATERIALIZED (SELECT x.course_code, x.top FROM registration.siwes_course_candidates(p_programme, p_curriculum) x)
    SELECT (SELECT min(c.course_code) FROM c WHERE c.top), (SELECT count(*) FROM c WHERE c.top),
           (SELECT jsonb_agg(registration.siwes_course_json(c.course_code, p_programme) ORDER BY c.course_code) FROM c)
      INTO v_top, v_n, v_choices;
    RETURN jsonb_build_object(
        'found', CASE WHEN v_n = 1 AND (p_cohort OR v_read IS NULL OR v_top IS DISTINCT FROM v_read) THEN registration.siwes_course_json(v_top, p_programme) END,
        'choices', CASE WHEN p_cohort OR v_read IS NULL THEN v_choices END,
        'elsewhere', CASE WHEN p_cohort OR v_read IS NULL THEN nullif(registration.siwes_courses_elsewhere(p_programme), '[]'::jsonb) END);
END $$;
COMMENT ON FUNCTION registration.siwes_course_offer(text, text, boolean) IS
  'V776: for the desk — what the catalogue offers a programme and curriculum, from one read of registration.siwes_course_candidates: found (the one course at the head, where none is read or the row read was written from the catalogue and it would now give another), choices (every candidate, where none is read), elsewhere (the SIWES courses carried where SIWES registration does not reach, where none is read). Nothing beside a course set on the desk. For a cohort no live course reaches (p_cohort) the offer is made whatever row is read.';

/* what a programme's 300 Level Second Semester is, for the desk: whether it is a SIWES attachment semester (V503: the SIWES course alone,
   registration.siwes_units) and the required courses (Core, GST) it carries besides SIWES — which a programme bound to SIWES could no
   longer register */
CREATE FUNCTION registration.siwes_semester_load(p_programme text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('attachment', registration.siwes_units(p_programme, 300, 2) IS NOT NULL,
                              'otherRequired', jsonb_build_object('courses', x.n, 'units', x.u))
      FROM (SELECT count(*) AS n, coalesce(sum(coalesce(o2.units, c2.units)), 0) AS u
              FROM catalogue.course_offer o2 JOIN catalogue.course c2 ON c2.code = o2.course_code
             WHERE o2.programme_code = p_programme AND o2.level = 300 AND o2.basis IN ('Core', 'GST')
               AND NOT c2.industrial_training AND c2.state <> 'ENDED' AND catalogue.runs_in(c2.semester, c2.both_semesters, 2)) x;
$$;
COMMENT ON FUNCTION registration.siwes_semester_load(text) IS
  'V776: for the desk — whether the programme''s 300 Level Second Semester is a SIWES attachment semester (registration.siwes_units) and how many required courses (Core, GST), of how many units, it carries beside SIWES.';

/* the SIWES courses a programme's own structure carries where SIWES registration does not reach them (another level, or the First
   Semester): a programme whose SIWES course is one of these has none for this registration — the University's rule is the Second
   Semester of 300 Level — and the desk says so instead of inviting a Set course that is refused */
CREATE FUNCTION registration.siwes_courses_elsewhere(p_programme text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'title', c.title, 'level', co.level,
                                                 'semester', CASE WHEN c.both_semesters THEN 'BOTH' WHEN c.semester = 1 THEN 'FIRST' ELSE 'SECOND' END)
                              ORDER BY co.level, c.code), '[]'::jsonb)
      FROM catalogue.course_offer co
      JOIN catalogue.course c ON c.code = co.course_code
     WHERE co.programme_code = p_programme AND c.industrial_training AND c.state <> 'ENDED'
       AND NOT (co.level = 300 AND catalogue.runs_in(c.semester, c.both_semesters, 2));
$$;
COMMENT ON FUNCTION registration.siwes_courses_elsewhere(text) IS
  'V776: for the desk — the SIWES courses a programme''s own structure carries outside the Second Semester of 300 Level, which SIWES registration does not reach.';

/* how a programme and curriculum came by their SIWES course — the row registration.siwes_course_of reads: SET (on the desk),
   STRUCTURE (recognised in the programme's own 300 Level structure), DEPARTMENT (recognised as the department's one course), or NULL */
CREATE FUNCTION registration.siwes_course_source(p_programme text, p_curriculum text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE sc.origin WHEN 'DESK' THEN 'SET' ELSE sc.origin END
      FROM registration.siwes_course sc
     WHERE sc.programme_code = p_programme
       AND (sc.curriculum IS NULL OR p_curriculum IS NULL OR sc.curriculum = p_curriculum OR registration.curriculum_open())
     ORDER BY (sc.curriculum IS NOT DISTINCT FROM p_curriculum) DESC, (sc.curriculum IS NULL) DESC, sc.curriculum DESC
     LIMIT 1;
$$;
COMMENT ON FUNCTION registration.siwes_course_source(text, text) IS
  'V776: how the programme''s SIWES course (registration.siwes_course_of) is known — SET on the SIWES desk, recognised in the programme''s own 300 Level STRUCTURE, or the one SIWES course of its DEPARTMENT; NULL when there is none.';

-- a course set on the desk is the desk's, whatever the row was before; and a 300 Level course: SIWES registration is the 300 Level cohort's
CREATE OR REPLACE FUNCTION registration.siwes_set_course(p_programme text, p_curriculum text, p_course text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_prog text := upper(btrim(coalesce(p_programme, ''))); v_cur text := upper(nullif(btrim(coalesce(p_curriculum, '')), ''));
        v_raw text := regexp_replace(upper(btrim(coalesce(p_course, ''))), '\s+', ' ', 'g'); c catalogue.course; p ref.programme;
        n int; v_sessions text;
BEGIN
    PERFORM registration.siwes_office();
    SELECT * INTO p FROM ref.programme WHERE code = v_prog;
    IF p.code IS NULL THEN RAISE EXCEPTION 'SIWES_PROGRAMME: % is not a programme on the register', v_prog USING ERRCODE = '23514'; END IF;
    IF p.category <> 'UNDER GRADUATE' THEN
        RAISE EXCEPTION 'SIWES_NOT_UNDERGRADUATE: % is a postgraduate programme; SIWES registration is for undergraduates', p.name USING ERRCODE = '23514';
    END IF;
    IF v_cur IS NOT NULL AND v_cur NOT IN ('CCMAS', 'BMAS') THEN
        RAISE EXCEPTION 'SIWES_CURRICULUM: a curriculum is CCMAS or BMAS (or none, for every curriculum)' USING ERRCODE = '23514';
    END IF;
    IF v_raw = '' THEN
        DELETE FROM registration.siwes_course WHERE programme_code = v_prog AND curriculum IS NOT DISTINCT FROM v_cur;
        -- the students who paid or registered, in any session the programme takes part in, whom no live course would reach now
        SELECT count(DISTINCT u.student_id), string_agg(DISTINCT sp.session, ', ') INTO n, v_sessions
          FROM registration.siwes_programme sp
          CROSS JOIN LATERAL registration.siwes_in_use_students(sp.session, v_prog) u
         WHERE sp.programme_code = v_prog
           AND NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = registration.siwes_course_of(v_prog, u.curriculum) AND k.state <> 'ENDED');
        IF n > 0 THEN
            RAISE EXCEPTION 'SIWES_COURSE_IN_USE: % student(s) of % have paid or registered for SIWES (%) and would be left with no SIWES course; the mapping is replaced by another course, never taken away',
                n, v_prog, v_sessions USING ERRCODE = '23514', HINT = 'Set another live Second Semester course for the programme instead.';
        END IF;
        RETURN jsonb_build_object('programmeCode', v_prog, 'curriculum', v_cur, 'course', NULL);
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = coalesce(catalogue.resolve_course_code(v_raw), v_raw);
    IF c.code IS NULL THEN
        RAISE EXCEPTION 'SIWES_COURSE_UNKNOWN: there is no course % in the catalogue; a SIWES course is an existing course, never one made here', v_raw
            USING ERRCODE = '23514', HINT = 'The department adds the course to the catalogue first.';
    END IF;
    IF c.state = 'ENDED' THEN
        RAISE EXCEPTION 'SIWES_COURSE_ENDED: % has ended and is not taught', c.code USING ERRCODE = '23514';
    END IF;
    IF NOT catalogue.runs_in(c.semester, c.both_semesters, 2) THEN
        RAISE EXCEPTION 'SIWES_COURSE_SEMESTER: % is taught in the first semester; the SIWES course is a Second Semester course', c.code USING ERRCODE = '23514';
    END IF;
    -- V776: SIWES registration is the 300 Level cohort's (its fee, its Second Semester): a course the programme's own structure carries
    -- only at another level, or one in no structure of the programme whose catalogue level is another, is not its SIWES course here
    IF EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.programme_code = v_prog AND co.course_code = c.code) THEN
        IF NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.programme_code = v_prog AND co.course_code = c.code AND co.level = 300) THEN
            RAISE EXCEPTION 'SIWES_COURSE_LEVEL: % is not a 300 Level course of %; SIWES registration is the 300 Level students'' (their fee, their Second Semester)', c.code, p.name
                USING ERRCODE = '23514', HINT = 'Set a 300 Level SIWES course of the programme.';
        END IF;
    ELSIF c.level IS DISTINCT FROM 300 THEN
        RAISE EXCEPTION 'SIWES_COURSE_LEVEL: % is not a 300 Level course; SIWES registration is the 300 Level students'' (their fee, their Second Semester)', c.code
            USING ERRCODE = '23514', HINT = 'Set a 300 Level SIWES course of the programme.';
    END IF;
    INSERT INTO registration.siwes_course (programme_code, curriculum, course_code, set_by, set_office, origin)
    VALUES (v_prog, v_cur, c.code, who, v_office, 'DESK')
    ON CONFLICT (programme_code, (coalesce(curriculum, ''))) DO UPDATE SET course_code = EXCLUDED.course_code, set_by = EXCLUDED.set_by,
           set_office = EXCLUDED.set_office, set_at = now(), origin = 'DESK';   -- V776: over a recognised course too
    RETURN jsonb_build_object('programmeCode', v_prog, 'curriculum', v_cur, 'course', registration.siwes_course_json(c.code, v_prog));
END $$;
COMMENT ON FUNCTION registration.siwes_set_course(text, text, text) IS
  'V752, V776: the SIWES course of a programme, for a curriculum or for every curriculum, set by the Academic Office (origin DESK, over a recognised one too): an existing course of the catalogue, taught in the Second Semester and not ended. No course: the row is taken away — never while students of the programme who have paid or registered would be left with no live SIWES course (SIWES_COURSE_IN_USE). Refusals SIWES_OFFICE, SIWES_PROGRAMME, SIWES_NOT_UNDERGRADUATE, SIWES_CURRICULUM, SIWES_COURSE_UNKNOWN, SIWES_COURSE_ENDED, SIWES_COURSE_SEMESTER.';

-- ── 3 · SIWES already passed: the programme's SIWES course, or a SIWES course of 300 Level ─────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.siwes_passed_among(p_session text, p_students uuid[]) RETURNS TABLE(student_id uuid) LANGUAGE sql STABLE AS $$
    SELECT DISTINCT k.student_id
      FROM (SELECT s.id AS student_id, o.id AS offering_id
              FROM people.student s
              JOIN registration.course_registration r ON r.student_id = s.id AND r.status IN ('APPROVED', 'LOCKED') AND r.session < p_session
              JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN catalogue.course c ON c.code = o.course_code
             WHERE s.id = ANY (p_students)
               -- V776: the course set or recognised for the student's programme, or a SIWES course of 300 Level (by the catalogue, or
               -- by the programme's structure) — not another level's (SIWES I at 200 Level, a seminar), now that every SIWES-titled
               -- course of every level is marked. An ended course's pass still counts
               AND ((c.industrial_training
                     AND (c.level = 300
                          OR EXISTS (SELECT 1 FROM catalogue.course_offer co
                                      WHERE co.course_code = c.code AND co.programme_code = s.programme_code AND co.level = 300)))
                    OR EXISTS (SELECT 1 FROM registration.siwes_course sc WHERE sc.programme_code = s.programme_code AND sc.course_code = c.code))
            OFFSET 0) k
     WHERE EXISTS (SELECT 1 FROM assessment.course_final(k.student_id, k.offering_id) cf WHERE cf.stage = 'PUBLISHED' AND cf.outcome = 'GRADED' AND cf.points > 0);
$$;
COMMENT ON FUNCTION registration.siwes_passed_among(text, uuid[]) IS
  'V752, V776: of the students given, those who passed SIWES before the session — a published pass in the course set or recognised for their programme, or in a SIWES course (industrial_training) of 300 Level (by the catalogue, or by their programme''s structure). A pass in another level''s course (SIWES I at 200 Level, a seminar) is not SIWES passed.';

-- ── 4 · the desk: a programme added, a period opened, before every course is known ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.siwes_add_programme(p_session text, p_programme text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_code text := upper(btrim(coalesce(p_programme, ''))); p ref.programme;
BEGIN
    PERFORM registration.siwes_office();
    PERFORM registration.siwes_session_ok(p_session);
    SELECT * INTO p FROM ref.programme WHERE code = v_code;
    IF p.code IS NULL OR p.archived THEN
        RAISE EXCEPTION 'SIWES_PROGRAMME: % is not a programme on the register', v_code USING ERRCODE = '23514';
    END IF;
    IF p.category <> 'UNDER GRADUATE' THEN
        RAISE EXCEPTION 'SIWES_NOT_UNDERGRADUATE: % is a postgraduate programme; SIWES registration is for undergraduates', p.name USING ERRCODE = '23514';
    END IF;
    INSERT INTO registration.siwes_period (session, state, set_by, set_office) VALUES (p_session, 'DRAFT', who, v_office) ON CONFLICT (session) DO NOTHING;
    INSERT INTO registration.siwes_programme (session, programme_code, added_by, added_office) VALUES (p_session, v_code, who, v_office)
    ON CONFLICT (session, programme_code) DO NOTHING;
    -- V776: the programme is added whether or not its SIWES course is known yet. Where its 300 Level Second Semester is a SIWES
    -- attachment semester, the course its own structure gives it is written down now (registration.siwes_pin_courses: never over a
    -- course already set or written down); otherwise the desk shows what the catalogue offers and the Academic Office sets it. Until
    -- a course reaches them its students are not bound (V503 stands for them), and the desk says which cohorts wait
    PERFORM registration.siwes_pin_courses(v_code);
    RETURN registration.siwes_config(p_session);
END $$;
COMMENT ON FUNCTION registration.siwes_add_programme(text, text) IS
  'V752, V776: a programme taking part in a session''s SIWES registration (its period made a draft when there is none yet). Added whether or not its SIWES course is known: where its 300 Level Second Semester is a SIWES attachment semester the course its own structure gives it is written down as it is added (registration.siwes_pin_courses); otherwise the desk shows what the catalogue offers and the Academic Office sets it. A cohort no course reaches is not bound until one does. Refusals SIWES_OFFICE, SIWES_PROGRAMME, SIWES_NOT_UNDERGRADUATE.';

CREATE OR REPLACE FUNCTION registration.siwes_set_period(p_session text, p_state text, p_registration_opens date, p_registration_closes date,
                                              p_training_starts date, p_training_ends date, p_duration_months integer, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_state text := upper(coalesce(nullif(btrim(p_state), ''), 'DRAFT')); n int;
BEGIN
    PERFORM registration.siwes_office();
    PERFORM registration.siwes_session_ok(p_session);
    IF v_state NOT IN ('DRAFT', 'OPEN', 'CLOSED') THEN
        RAISE EXCEPTION 'SIWES_PERIOD_STATE: a SIWES period is DRAFT, OPEN or CLOSED' USING ERRCODE = '23514';
    END IF;
    IF v_state = 'OPEN' AND (p_registration_opens IS NULL OR p_registration_closes IS NULL OR p_training_starts IS NULL OR p_training_ends IS NULL) THEN
        RAISE EXCEPTION 'SIWES_PERIOD_DATES: SIWES registration opens with its registration window and its training period dated' USING ERRCODE = '23514',
            HINT = 'Give the registration opening and closing dates and the training commencement and expected completion dates.';
    END IF;
    IF p_registration_opens IS NOT NULL AND p_registration_closes IS NOT NULL AND p_registration_closes < p_registration_opens THEN
        RAISE EXCEPTION 'SIWES_PERIOD_DATES: registration closes (%) before it opens (%)', p_registration_closes, p_registration_opens USING ERRCODE = '23514';
    END IF;
    IF p_training_starts IS NOT NULL AND p_training_ends IS NOT NULL AND p_training_ends <= p_training_starts THEN
        RAISE EXCEPTION 'SIWES_PERIOD_DATES: the training ends (%) on or before it starts (%)', p_training_ends, p_training_starts USING ERRCODE = '23514';
    END IF;
    IF p_duration_months IS NOT NULL AND p_duration_months NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'SIWES_PERIOD_DURATION: the duration is 1 to 12 months' USING ERRCODE = '23514';
    END IF;
    -- V776: the period opens whether or not every configured programme's SIWES course is known: a cohort no course reaches is not
    -- bound until one does, and the desk lists it. Saving the period changes nobody's binding (the desk shows what the catalogue offers)
    IF v_state = 'DRAFT' AND EXISTS (SELECT 1 FROM registration.siwes_period WHERE session = p_session AND state <> 'DRAFT') THEN
        n := registration.siwes_in_use(p_session);
        IF n > 0 THEN
            RAISE EXCEPTION 'SIWES_PERIOD_IN_USE: % student(s) have paid or registered for SIWES in %; the period is closed, never put back to a draft', n, p_session
                USING ERRCODE = '23514';
        END IF;
    END IF;
    INSERT INTO registration.siwes_period (session, state, registration_opens, registration_closes, training_starts, training_ends,
                                           duration_months, note, set_by, set_office)
    VALUES (p_session, v_state, p_registration_opens, p_registration_closes, p_training_starts, p_training_ends,
            coalesce(p_duration_months, 6), nullif(btrim(p_note), ''), who, v_office)
    ON CONFLICT (session) DO UPDATE SET state = EXCLUDED.state, registration_opens = EXCLUDED.registration_opens,
           registration_closes = EXCLUDED.registration_closes, training_starts = EXCLUDED.training_starts, training_ends = EXCLUDED.training_ends,
           duration_months = EXCLUDED.duration_months, note = EXCLUDED.note, set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, set_at = now();
    -- no longer open: the open references of the session close (one already on its way to a bank still pays: a payment is never lost)
    IF v_state <> 'OPEN' THEN
        UPDATE finance.payment_reference SET expires_at = now()
         WHERE session = p_session AND purpose LIKE 'SIWES registration fee%' AND confirmed_at IS NULL AND archived_at IS NULL AND expires_at > now();
    END IF;
    RETURN registration.siwes_period_json(p_session);
END $$;
COMMENT ON FUNCTION registration.siwes_set_period(text, text, date, date, date, date, integer, text) IS
  'V752, V776: the SIWES period of a session stated or changed. OPEN needs both registration dates and both training dates; it opens whether or not every configured programme''s SIWES course is known (a cohort no course reaches is not bound until one does; saving the period changes nobody''s binding). A period no longer open closes its open references; a period in use is never put back to a draft.';

-- V503's attachment-semester load of a programme level and semester as it would read with one course no longer a SIWES course: the
-- course counts then as an ordinary course of the structure. Used to say what taking a course off the SIWES courses would end
CREATE FUNCTION registration.siwes_units_without(p_programme text, p_level integer, p_semester integer, p_course text)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT max(c.units)::int
      FROM catalogue.course_offer co
      JOIN catalogue.course c ON c.code = co.course_code
     WHERE co.programme_code = p_programme AND co.level = p_level
       AND catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.industrial_training AND c.code <> p_course AND c.state <> 'ENDED'
       AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer o2 JOIN catalogue.course c2 ON c2.code = o2.course_code
                        WHERE o2.programme_code = p_programme AND o2.level = p_level AND o2.basis IN ('Core', 'GST')
                          AND (NOT c2.industrial_training OR c2.code = p_course) AND c2.state <> 'ENDED'
                          AND catalogue.runs_in(c2.semester, c2.both_semesters, p_semester));
$$;
COMMENT ON FUNCTION registration.siwes_units_without(text, integer, integer, text) IS
  'V776: registration.siwes_units (V503''s attachment-semester load) as it would read with the course no longer a SIWES course — NULL when the semester would stop being an attachment semester.';

-- ── 5 · the SIWES courses, listed and marked on the desk ────────────────────────────────────────────────────────────────────────
/* every course the portal reads as SIWES (and a course set as a programme's SIWES course though not marked: marked false), for the
   desk: its department, level, semester and state, whether its title reads so, whether
   a programme can come by it as it stands (300 Level, Second Semester, not ended), the programmes whose structure carries it, the
   programmes it is the SIWES course of (and how: set or recognised), and the programme semesters V503 reads as an attachment semester
   because of it (taking it off the SIWES courses ends that) */
CREATE FUNCTION registration.siwes_course_list() RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'code', c.code, 'title', c.title, 'units', c.units, 'level', c.level,
               'semester', CASE WHEN c.both_semesters THEN 'BOTH' WHEN c.semester = 1 THEN 'FIRST' WHEN c.semester = 2 THEN 'SECOND' ELSE c.semester::text END,
               'state', c.state, 'curriculum', c.curriculum,
               'departmentCode', d.code, 'department', d.name,
               'byTitle', catalogue.reads_as_siwes(c.title),
               'marked', c.industrial_training,   -- false: listed only because it is set as a programme's SIWES course on the desk
               'recognised', c.state <> 'ENDED' AND c.level = 300 AND catalogue.runs_in(c.semester, c.both_semesters, 2),
               'programmes', coalesce((SELECT jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'level', co.level) ORDER BY p.name, co.level)
                                         FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code
                                        WHERE co.course_code = c.code), '[]'::jsonb),
               'setFor', coalesce((SELECT jsonb_agg(jsonb_build_object('code', sc.programme_code, 'curriculum', sc.curriculum,
                                                                       'source', CASE sc.origin WHEN 'DESK' THEN 'SET' ELSE sc.origin END)
                                                    ORDER BY sc.programme_code, sc.curriculum)
                                     FROM registration.siwes_course sc WHERE sc.course_code = c.code), '[]'::jsonb),
               'attachmentFor', coalesce((SELECT jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'level', co.level, 'semester', x.sem)
                                                           ORDER BY p.name, co.level, x.sem)
                                            FROM catalogue.course_offer co
                                            JOIN ref.programme p ON p.code = co.programme_code
                                           CROSS JOIN (VALUES (1), (2)) x(sem)
                                           WHERE co.course_code = c.code AND c.state <> 'ENDED' AND c.industrial_training
                                             AND catalogue.runs_in(c.semester, c.both_semesters, x.sem)
                                             AND registration.siwes_units(co.programme_code, co.level, x.sem) IS NOT NULL
                                             AND registration.siwes_units_without(co.programme_code, co.level, x.sem, c.code) IS DISTINCT FROM
                                                 registration.siwes_units(co.programme_code, co.level, x.sem)), '[]'::jsonb))
             ORDER BY d.name NULLS LAST, c.code), '[]'::jsonb)
      FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code
     WHERE c.industrial_training OR EXISTS (SELECT 1 FROM registration.siwes_course sc WHERE sc.course_code = c.code);
$$;
COMMENT ON FUNCTION registration.siwes_course_list() IS
  'V776: the SIWES courses of the catalogue (industrial_training, and any course set as a programme''s SIWES course) as the SIWES desk lists them, each department''s under its own code and title — with the programmes whose structure carries each, those it is the SIWES course of (set or recognised) and the programme semesters it makes an attachment semester (V503).';

/* a catalogue course added to the SIWES courses, or taken off them.
   Added: the programmes of the planned and current sessions' SIWES (period not closed) that wait for a course and carry this course in
   their own 300 Level structure get it where their Second Semester is an attachment semester. Nothing already set or recognised moves.
   Taken off: never while it is a programme's SIWES course set on the desk, nor while students who have paid or registered SIWES read it
   or registered on it, nor while students are registered in a programme semester it makes an attachment semester (V503: they would
   be left with a semester they cannot submit) — SIWES_COURSE_IN_USE. A row that only recognised it for a programme (nobody paid or
   registered) goes with it: the cohort waits again */
CREATE FUNCTION registration.siwes_mark_course(p_course text, p_on boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_raw text := regexp_replace(upper(btrim(coalesce(p_course, ''))), '\s+', ' ', 'g'); c catalogue.course; n int; v_who text;
BEGIN
    PERFORM registration.siwes_office();
    IF v_raw = '' THEN RAISE EXCEPTION 'SIWES_COURSE_UNKNOWN: give the course code, as the catalogue holds it' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = coalesce(catalogue.resolve_course_code(v_raw), v_raw) FOR UPDATE;
    IF c.code IS NULL THEN
        RAISE EXCEPTION 'SIWES_COURSE_UNKNOWN: there is no course % in the catalogue; a SIWES course is an existing course, never one made here', v_raw
            USING ERRCODE = '23514', HINT = 'The department adds the course to the catalogue first.';
    END IF;
    IF coalesce(p_on, true) THEN
        IF c.state = 'ENDED' THEN
            RAISE EXCEPTION 'SIWES_COURSE_ENDED: % has ended and is not taught', c.code USING ERRCODE = '23514';
        END IF;
        UPDATE catalogue.course SET industrial_training = true WHERE code = c.code AND NOT industrial_training;
        -- the programmes of the planned and current sessions still waiting for a course whose own structure carries THIS course and
        -- whose Second Semester is an attachment semester now get it — not while the period is closed (nobody could pay or register)
        PERFORM registration.siwes_pin_courses(q.programme_code, c.code)
           FROM (SELECT DISTINCT sp.programme_code
                   FROM registration.siwes_programme sp
                   JOIN policy.academic_session a ON a.name = sp.session AND a.state IN ('PLANNED', 'CURRENT')
                   JOIN registration.siwes_period p ON p.session = sp.session AND p.state <> 'CLOSED'
                   JOIN catalogue.course_offer co ON co.programme_code = sp.programme_code AND co.course_code = c.code AND co.level = 300
                  ORDER BY sp.programme_code) q;
    ELSE
        SELECT string_agg(sc.programme_code || coalesce(' (' || sc.curriculum || ')', ''), ', ' ORDER BY sc.programme_code, sc.curriculum) INTO v_who
          FROM registration.siwes_course sc WHERE sc.course_code = c.code AND sc.origin = 'DESK';
        IF v_who IS NOT NULL THEN
            RAISE EXCEPTION 'SIWES_COURSE_IN_USE: % is set as the SIWES course of %; it stays a SIWES course', c.code, v_who
                USING ERRCODE = '23514', HINT = 'Set another course for those programmes first.';
        END IF;
        SELECT count(DISTINCT u.student_id) INTO n
          FROM registration.siwes_programme sp
          CROSS JOIN LATERAL registration.siwes_in_use_students(sp.session, sp.programme_code) u
         WHERE registration.siwes_course_of(sp.programme_code, u.curriculum) = c.code
            OR EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.student_id = u.student_id AND x.session = sp.session AND x.course_code = c.code);
        IF n > 0 THEN
            RAISE EXCEPTION 'SIWES_COURSE_IN_USE: % student(s) have paid or registered for SIWES on %; it stays a SIWES course', n, c.code
                USING ERRCODE = '23514', HINT = 'Set another SIWES course for their programme first.';
        END IF;
        -- V503 reads the same marker: the programme semesters whose only required load is this course are attachment semesters, and
        -- their students could not submit the semester without it
        SELECT count(DISTINCT r.student_id), string_agg(DISTINCT co.programme_code || ' at ' || co.level || ' Level', ', ') INTO n, v_who
          FROM catalogue.course_offer co
          JOIN people.student s ON s.programme_code = co.programme_code
          JOIN registration.course_registration r ON r.student_id = s.id AND r.level = co.level
          JOIN policy.academic_session a ON a.name = r.session AND a.state IN ('PLANNED', 'CURRENT')
         WHERE co.course_code = c.code AND catalogue.runs_in(c.semester, c.both_semesters, r.semester)
           AND registration.siwes_units(co.programme_code, co.level, r.semester) IS NOT NULL
           AND registration.siwes_units_without(co.programme_code, co.level, r.semester, c.code) IS DISTINCT FROM
               registration.siwes_units(co.programme_code, co.level, r.semester)
           AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED'));
        IF n > 0 THEN
            RAISE EXCEPTION 'SIWES_COURSE_IN_USE: % student(s) of % are registered in the attachment semester % makes; it stays a SIWES course', n, v_who, c.code
                USING ERRCODE = '23514';
        END IF;
        -- the rows that only recognised it go with it: those cohorts wait for a course again
        DELETE FROM registration.siwes_course sc WHERE sc.course_code = c.code AND sc.origin <> 'DESK';
        UPDATE catalogue.course SET industrial_training = false WHERE code = c.code AND industrial_training;
    END IF;
    RETURN registration.siwes_course_list();
END $$;
COMMENT ON FUNCTION registration.siwes_mark_course(text, boolean) IS
  'V776: the Academic Office (or the Registry) adds an existing catalogue course to the SIWES courses — the programmes still waiting whose own structure carries it get it where their Second Semester is an attachment semester — or takes one off: never one set as a programme''s SIWES course, one students have paid or registered on, or one whose attachment semester students are registered in (SIWES_COURSE_IN_USE); a row that only recognised it goes with it. Refusals SIWES_OFFICE, SIWES_COURSE_UNKNOWN, SIWES_COURSE_ENDED.';

-- ── 6 · the desk's configuration says how each course is known, lists the SIWES courses and the cohorts still waiting ────────────
CREATE OR REPLACE FUNCTION registration.siwes_config(p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH v AS (SELECT coalesce(nullif(btrim(coalesce(p_session, '')), ''), policy.university_current_session()) AS session),
    -- V776: each student's reasons read once (eligible is "no reason": asking the roster for both reads them twice a student)
    rost AS MATERIALIZED (SELECT x.programme_code, x.programme, x.curriculum, x.reasons
                            FROM v CROSS JOIN LATERAL registration.siwes_roster(v.session) x),
    ros AS (SELECT r.programme_code, count(*) FILTER (WHERE cardinality(r.reasons) = 0) AS eligible FROM rost r GROUP BY r.programme_code),
    keys AS (SELECT sc.programme_code, sc.curriculum FROM registration.siwes_course sc
             UNION
             SELECT s.programme_code, s.curriculum_version FROM v
               JOIN registration.siwes_programme sp ON sp.session = v.session
               JOIN people.student s ON s.programme_code = sp.programme_code AND s.status IN ('ACTIVE', 'PROBATION') AND s.current_level = 300
                                    AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE'))
    SELECT jsonb_build_object(
        'session', v.session,
        'period', registration.siwes_period_json(v.session),
        'programmes', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'code', p.code, 'name', p.name, 'departmentCode', d.code, 'department', d.name, 'facultyCode', fa.code, 'faculty', fa.name,
                       'eligible', coalesce(ros.eligible, 0),
                       'course', registration.siwes_course_json(registration.siwes_course_of(p.code, NULL), p.code),
                       -- V776: how the course is known (SET on the desk, or recognised: STRUCTURE, DEPARTMENT); with none, the course the
                       -- catalogue now gives the programme (found: one press takes it) or the several it offers (choices)
                       'source', registration.siwes_course_source(p.code, NULL),
                       'found', po.o->'found',
                       'choices', po.o->'choices',
                       'elsewhere', po.o->'elsewhere',
                       'curricula', coalesce((SELECT jsonb_agg(jsonb_build_object('curriculum', k.curriculum,
                                                                                  'mapped', EXISTS (SELECT 1 FROM registration.siwes_course sc WHERE sc.programme_code = p.code
                                                                                                       AND sc.curriculum IS NOT DISTINCT FROM k.curriculum),
                                                                                  'course', registration.siwes_course_json(registration.siwes_course_of(p.code, k.curriculum), p.code),
                                                                                  'source', registration.siwes_course_source(p.code, k.curriculum),
                                                                                  'found', ko.o->'found',
                                                                                  'choices', ko.o->'choices',
                                                                                  'elsewhere', ko.o->'elsewhere')
                                                         ORDER BY k.curriculum NULLS FIRST)
                                                FROM keys k CROSS JOIN LATERAL (SELECT registration.siwes_course_offer(p.code, k.curriculum) AS o) ko   -- V776: what the catalogue offers, read once
                                               WHERE k.programme_code = p.code), '[]'::jsonb))
                       || registration.siwes_semester_load(p.code)   -- V776: attachment (V503's SIWES semester), otherRequired {courses, units}
                       ORDER BY p.name)
              FROM registration.siwes_programme sp
              JOIN ref.programme p ON p.code = sp.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty fa ON fa.code = coalesce(d.faculty_code, p.faculty_code)
              LEFT JOIN ros ON ros.programme_code = p.code
              LEFT JOIN LATERAL (SELECT registration.siwes_course_offer(p.code, NULL) AS o) po ON true   -- V776: what the catalogue offers, read once
             WHERE sp.session = v.session), '[]'::jsonb),
        'candidates', coalesce((
            SELECT jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name,
                                                'attachment', registration.siwes_units(p.code, 300, 2) IS NOT NULL) ORDER BY p.name)
              FROM ref.programme p
             WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived
               AND NOT EXISTS (SELECT 1 FROM registration.siwes_programme sp WHERE sp.session = v.session AND sp.programme_code = p.code)), '[]'::jsonb),
        -- V776: the SIWES courses of the catalogue, and the cohorts of the configured programmes no live SIWES course reaches (of
        -- them, "paid" have paid or registered: they stay bound and wait for the course to register; the rest are not bound)
        'siwesCourses', registration.siwes_course_list(),
        'unreached', coalesce((SELECT jsonb_agg(jsonb_build_object(
                                          'programmeCode', q.programme_code, 'programme', q.programme, 'curriculum', q.curriculum, 'students', q.n,
                                          'paid', (SELECT count(*) FROM registration.siwes_in_use_students(v.session, q.programme_code) u
                                                    WHERE u.curriculum IS NOT DISTINCT FROM q.curriculum),
                                          'found', qo.o->'found', 'choices', qo.o->'choices', 'elsewhere', qo.o->'elsewhere')
                                        ORDER BY q.programme, q.curriculum)
                                 FROM (SELECT r.programme_code, r.programme, r.curriculum, count(*) AS n FROM rost r
                                        WHERE 'NO_COURSE' = ANY (r.reasons) AND r.reasons <@ ARRAY['NO_COURSE', 'NO_PERIOD']
                                        GROUP BY r.programme_code, r.programme, r.curriculum) q
                                 CROSS JOIN LATERAL (SELECT registration.siwes_course_offer(q.programme_code, q.curriculum, true) AS o) qo), '[]'::jsonb),
        'fee', (SELECT jsonb_build_object('amount', f.amount, 'state', f.state) FROM finance.siwes_fee f WHERE f.session = v.session),
        'sessions', coalesce((SELECT jsonb_agg(a.name ORDER BY a.name DESC) FROM policy.academic_session a
                               WHERE a.state <> 'CANCELLED' AND a.merged_into IS NULL), '[]'::jsonb))
      FROM v;
$$;
COMMENT ON FUNCTION registration.siwes_config(text) IS
  'V752, V776: the Academic Office''s configuration of a session — the period, the programmes with their SIWES course for each curriculum (and how it is known: SET on the desk, or written down from the programme''s STRUCTURE; where there is none — or the catalogue would now give another to a recognised one — the course it gives (found), the several it offers (choices), and the SIWES courses the programme carries where SIWES registration does not reach (elsewhere); and what the programme''s 300 Level Second Semester is: attachment, otherRequired), the programmes not yet configured, the SIWES courses of the catalogue, the cohorts no live SIWES course reaches, the fee, the sessions.';

COMMIT;

-- ═══════════════════════════════════════
-- V558 — Student lifecycle reconciliation: the cohort engine's classifications reviewed, verified and reconciled in batches
--
--   The cohort engine (V331, V463) computes where every student stands — the effective cohort, the programme's length, the
--   expected completion, the sessions beyond it — and the Registry decided one student at a time (people.decide_cohort). What
--   it lacked was a controlled way to act on thousands of them: nothing here recomputes a cohort, a length or a spillover, and
--   nothing changes a student because a calculation says so. On top of the one engine:
--
--   1 · people.lifecycle_completion — whether an active student at or beyond the programme's length has completed what they
--       registered, read from the published results (assessment.student_results) and the courses still owed
--       (registration.carryovers): COMPLETED, OUTSTANDING_COURSES, AWAITING_RESULT (a course with no published result — never
--       a failure), FINAL_LEVEL_NOT_REACHED or NO_PUBLISHED_RESULT. Checked on demand in pages ("Refresh analysis") and again
--       for each student at the moment they are reconciled; when it was checked is kept.
--   2 · people.lifecycle_recommendation — for every ACTIVE or PROBATION student the engine has not already settled: a
--       graduation candidate (final year, or beyond the length with everything completed), spillover year 1, 2 …, maximum
--       spillover reached, on the graduation list already, within the normal duration, data incomplete or requires review;
--       a confidence (HIGH, MEDIUM, LOW) with its reasons, and an explanation written from the record, never guessed. A
--       cohort read from the matriculation number alone is never used: the entry session is the evidence, and a matriculation
--       year that disagrees with it lowers the confidence.
--   3 · people.lifecycle_review — the review of a recommendation (UNDER_REVIEW, VERIFIED, REJECTED, REQUIRES_CORRECTION) for
--       the session it was made in; a recommendation that changes is pending again. A low-confidence record is verified one at
--       a time, never in bulk.
--   4 · people.lifecycle_batch (RECON/YYYY/NNNNNN) and people.lifecycle_reconciliation — a verified recommendation reconciled
--       once per session, by the officer's batch: a spillover is confirmed (the status stays ACTIVE, the level raised to the
--       programme's final level where it is lower, never lowered); at the maximum the officer chooses — kept ACTIVE and flagged,
--       or DORMANT or WITHDRAWN on a reason (never automatic); a graduation candidate is put on the session's graduation list for
--       the audit (GraduationService) — the Senate still approves, and nobody becomes GRADUATED here. Each act writes the
--       student's cohort decision and, where the status moves, people.change_status; nothing is deleted and no matriculation
--       number, result, registration or payment is touched.
--   5 · people.lifecycle_correct — a reconciliation reversed on a reason: the status changed back, a level raised by it put
--       back where nobody has moved it since, and a graduation-list entry it added removed while the Senate has not acted on it;
--       the reconciliation is kept, marked corrected.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V558: student lifecycle reconciliation reviewed, verified and reconciled in batches', true);

-- ── 1 · completion: what a student at or beyond the programme's length has completed ─────────────────────────────────────
CREATE TABLE people.lifecycle_completion (
    student_id          uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    completion          text NOT NULL,
    registered          int  NOT NULL,
    published           int  NOT NULL,
    awaiting            int  NOT NULL,
    outstanding         int  NOT NULL,
    highest_level       int  NULL,
    outstanding_courses text NULL,
    awaiting_courses    text NULL,
    checked_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_lifecycle_completion CHECK (completion IN ('COMPLETED','OUTSTANDING_COURSES','AWAITING_RESULT','FINAL_LEVEL_NOT_REACHED','NO_PUBLISHED_RESULT'))
);
COMMENT ON TABLE people.lifecycle_completion IS
  'V558: whether an active student at or beyond the programme''s length has completed what they registered — from the published results and the courses still owed; checked on demand and again when the student is reconciled.';
SELECT audit.exempt('people.lifecycle_completion', 'Derived from the published results and the carry-overs by people.lifecycle_completion_rows; checked again whenever a student is reconciled, and the reconciliation records what it found.');

CREATE FUNCTION people.lifecycle_completion_rows(p_students uuid[])
RETURNS TABLE (student_id uuid, completion text, registered int, published int, awaiting int, outstanding int, highest_level int,
               outstanding_courses text, awaiting_courses text)
LANGUAGE sql STABLE AS $$
    SELECT x.id,
           CASE WHEN r.registered = 0 OR r.published = 0 THEN 'NO_PUBLISHED_RESULT'
                WHEN o.n > 0 THEN 'OUTSTANDING_COURSES'
                WHEN ap.final_level IS NOT NULL AND coalesce(h.lvl, 0) < ap.final_level THEN 'FINAL_LEVEL_NOT_REACHED'
                WHEN r.awaiting > 0 THEN 'AWAITING_RESULT'
                ELSE 'COMPLETED' END,
           r.registered, r.published, r.awaiting, o.n, h.lvl, o.codes, r.codes
      FROM unnest(p_students) AS x(id)
      LEFT JOIN people.academic_position ap ON ap.student_id = x.id
      CROSS JOIN LATERAL (
          SELECT count(*)::int AS registered,
                 count(*) FILTER (WHERE q.published)::int AS published,
                 -- a course with no published result is awaited, unless the student passed it in another sitting
                 count(*) FILTER (WHERE NOT q.published AND NOT q.passed)::int AS awaiting,
                 left(string_agg(DISTINCT q.course_code, ', ' ORDER BY q.course_code) FILTER (WHERE NOT q.published AND NOT q.passed), 300) AS codes
            FROM (SELECT sr.course_code, sr.published,
                         bool_or(sr.published AND sr.outcome = 'GRADED' AND sr.points > 0) OVER (PARTITION BY sr.course_code) AS passed
                    FROM assessment.student_results(x.id) sr) q) r
      CROSS JOIN LATERAL (
          SELECT count(*)::int AS n, left(string_agg(DISTINCT c.course_code, ', ' ORDER BY c.course_code), 300) AS codes
            FROM registration.carryovers(x.id) c) o
      LEFT JOIN LATERAL (
          SELECT max(cr.level) AS lvl FROM registration.course_registration cr
           WHERE cr.student_id = x.id AND cr.status IN ('APPROVED','LOCKED')) h ON true
$$;
COMMENT ON FUNCTION people.lifecycle_completion_rows(uuid[]) IS
  'V558: each listed student''s completion — NO_PUBLISHED_RESULT (nothing published to judge by), OUTSTANDING_COURSES (a failed course not yet passed), FINAL_LEVEL_NOT_REACHED, AWAITING_RESULT (a registered course with no published result: never read as failed) or COMPLETED — with the counts and the courses named.';

CREATE FUNCTION people.refresh_lifecycle_completion(p_students uuid[])
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    IF p_students IS NULL OR cardinality(p_students) = 0 THEN RETURN 0; END IF;
    INSERT INTO people.lifecycle_completion AS lc (student_id, completion, registered, published, awaiting, outstanding, highest_level,
                                                  outstanding_courses, awaiting_courses, checked_at)
    SELECT r.student_id, r.completion, r.registered, r.published, r.awaiting, r.outstanding, r.highest_level, r.outstanding_courses, r.awaiting_courses, now()
      FROM people.lifecycle_completion_rows(p_students) r
      JOIN people.student s ON s.id = r.student_id
    ON CONFLICT (student_id) DO UPDATE SET
        completion = EXCLUDED.completion, registered = EXCLUDED.registered, published = EXCLUDED.published, awaiting = EXCLUDED.awaiting,
        outstanding = EXCLUDED.outstanding, highest_level = EXCLUDED.highest_level, outstanding_courses = EXCLUDED.outstanding_courses,
        awaiting_courses = EXCLUDED.awaiting_courses, checked_at = EXCLUDED.checked_at;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;
COMMENT ON FUNCTION people.refresh_lifecycle_completion(uuid[]) IS 'V558: the listed students'' completion checked now and kept. Returns the students checked.';

-- the students whose completion matters: active, at or beyond the programme's length, within a faculty, department or programme
CREATE FUNCTION people.lifecycle_pool(p_after uuid, p_limit int, p_fac text, p_dept text, p_prog text)
RETURNS uuid[]
LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(x.student_id ORDER BY x.student_id), '{}'::uuid[])
      FROM (SELECT ap.student_id
              FROM people.academic_position ap
              JOIN people.student s ON s.id = ap.student_id
              JOIN ref.programme p ON p.code = s.programme_code
             WHERE ap.existing_status IN ('ACTIVE','PROBATION') AND ap.rule IN ('R3','R3L','R4','R4L')
               AND (ap.spillover_years > 0 OR ap.expected_completion = ap.current_session)
               AND (p_after IS NULL OR ap.student_id > p_after)
               AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
             ORDER BY ap.student_id
             LIMIT greatest(1, least(coalesce(p_limit, 500), 2000))) x
$$;
COMMENT ON FUNCTION people.lifecycle_pool(uuid, int, text, text, text) IS
  'V558: the next page (after a student id, in id order) of the active students at or beyond their programme''s length whose completion is checked, within the scope given.';

-- ── 2 · the recommendation, its confidence and its explanation ─────────────────────────────────────────────────────────
CREATE TABLE people.lifecycle_review (
    student_id     uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    recommendation text NOT NULL,
    session        text NOT NULL REFERENCES policy.academic_session(name),
    state          text NOT NULL,
    note           text NULL,
    reviewed_by    uuid NOT NULL,
    actor_office   text NULL,
    reviewed_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_lifecycle_review_state CHECK (state IN ('UNDER_REVIEW','VERIFIED','REJECTED','REQUIRES_CORRECTION'))
);
CREATE INDEX ix_lifecycle_review_session ON people.lifecycle_review (session);
COMMENT ON TABLE people.lifecycle_review IS
  'V558: the review of a student''s lifecycle recommendation for the session it was made in — under review, verified, rejected or requiring a correction of the data; when the recommendation or the session changes, the student is pending again.';
SELECT audit.attach('people.lifecycle_review');

CREATE SEQUENCE people.lifecycle_batch_seq;
CREATE TABLE people.lifecycle_batch (
    batch_ref         text PRIMARY KEY,
    description       text NOT NULL,
    effective_session text NOT NULL REFERENCES policy.academic_session(name),
    scope             text NULL,
    reconciled        int  NOT NULL DEFAULT 0,
    skipped           int  NOT NULL DEFAULT 0,
    corrected         int  NOT NULL DEFAULT 0,
    created_by        uuid NOT NULL,
    actor_office      text NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    closed_at         timestamptz NULL,
    CONSTRAINT ck_lifecycle_batch_ref CHECK (batch_ref ~ '^RECON/[0-9]{4}/[0-9]{6}$')
);
COMMENT ON TABLE people.lifecycle_batch IS 'V558: one officer''s reconciliation batch (RECON/YYYY/NNNNNN): what it was for, the session it took effect in, the scope, and how many it reconciled, skipped and later corrected.';
SELECT audit.attach('people.lifecycle_batch');

CREATE TABLE people.lifecycle_reconciliation (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_ref              text NOT NULL REFERENCES people.lifecycle_batch(batch_ref),
    student_id             uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    effective_session      text NOT NULL REFERENCES policy.academic_session(name),
    recommendation         text NOT NULL,
    confidence             text NOT NULL,
    outcome                text NOT NULL,
    previous_status        text NOT NULL,
    new_status             text NOT NULL,
    previous_level         int  NULL,
    new_level              int  NULL,
    effective_cohort       text NULL,
    expected_completion    text NULL,
    spillover_years        int  NOT NULL DEFAULT 0,
    completion             text NULL,
    explanation            text NOT NULL,
    reason                 text NOT NULL,
    decision_id            uuid NULL REFERENCES people.cohort_decision(id) ON DELETE SET NULL,
    graduand_id            uuid NULL REFERENCES records.graduand(id) ON DELETE SET NULL,
    graduand_added         boolean NOT NULL DEFAULT false,
    graduand_unmet         text NULL,
    reconciled_by          uuid NOT NULL,
    actor_office           text NULL,
    reconciled_at          timestamptz NOT NULL DEFAULT now(),
    corrected_at           timestamptz NULL,
    corrected_by           uuid NULL,
    correction_reason      text NULL,
    correction_decision_id uuid NULL REFERENCES people.cohort_decision(id) ON DELETE SET NULL,
    level_restored         boolean NULL,
    CONSTRAINT ck_lifecycle_outcome CHECK (outcome IN ('SPILLOVER_CONFIRMED','KEPT_ACTIVE_LIMIT_REACHED','STATUS_CHANGED','GRADUATION_LIST')),
    CONSTRAINT ck_lifecycle_confidence CHECK (confidence IN ('HIGH','MEDIUM','LOW')),
    CONSTRAINT ck_lifecycle_never_graduated CHECK (new_status <> 'GRADUATED'),
    CONSTRAINT ck_lifecycle_corrected CHECK ((corrected_at IS NULL) = (correction_reason IS NULL))
);
-- a recommendation is reconciled once in a session; a corrected one may be reconciled again
CREATE UNIQUE INDEX ux_lifecycle_once ON people.lifecycle_reconciliation (student_id, effective_session, recommendation) WHERE corrected_at IS NULL;
CREATE INDEX ix_lifecycle_reconciliation_batch ON people.lifecycle_reconciliation (batch_ref);
CREATE INDEX ix_lifecycle_reconciliation_student ON people.lifecycle_reconciliation (student_id, reconciled_at DESC);
CREATE INDEX ix_lifecycle_reconciliation_decision ON people.lifecycle_reconciliation (decision_id) WHERE decision_id IS NOT NULL;
CREATE INDEX ix_lifecycle_reconciliation_correction ON people.lifecycle_reconciliation (correction_decision_id) WHERE correction_decision_id IS NOT NULL;
CREATE INDEX ix_lifecycle_reconciliation_graduand ON people.lifecycle_reconciliation (graduand_id) WHERE graduand_id IS NOT NULL;
CREATE INDEX ix_lifecycle_reconciliation_session ON people.lifecycle_reconciliation (effective_session);
COMMENT ON TABLE people.lifecycle_reconciliation IS
  'V558: each lifecycle reconciliation — the recommendation reconciled with its confidence and explanation as they stood, the officer''s outcome, the status and level before and after, the cohort decision written, the graduation-list entry, the batch, and a correction when one reversed it. Written once; a later recommendation never rewrites it.';
SELECT audit.attach('people.lifecycle_reconciliation');

CREATE VIEW people.lifecycle_recommendation AS
SELECT c.*,
       CASE WHEN rc.id IS NOT NULL THEN 'RECONCILED'
            WHEN rv.recommendation = c.recommendation AND rv.session = c.current_session THEN rv.state
            ELSE 'PENDING' END AS review_state,
       CASE WHEN rv.recommendation = c.recommendation AND rv.session = c.current_session THEN rv.note END AS review_note,
       CASE WHEN rv.recommendation = c.recommendation AND rv.session = c.current_session THEN rv.reviewed_by END AS reviewed_by,
       CASE WHEN rv.recommendation = c.recommendation AND rv.session = c.current_session THEN rv.reviewed_at END AS reviewed_at,
       rc.id AS reconciliation_id, rc.batch_ref, rc.reconciled_at
  FROM (
    SELECT b.*,
           CASE WHEN b.recommendation IN ('DATA_INCOMPLETE','REQUIRES_REVIEW') OR b.last_session IS NULL OR b.matric_year_differs
                     OR b.matric_no IS NULL OR (b.level_conflict AND b.spillover_years = 0) THEN 'LOW'
                WHEN (b.registered_current OR b.enrolled_current) AND b.duration_source IN ('PROGRAMME','CCE_ROUTE') THEN 'HIGH'
                ELSE 'MEDIUM' END AS confidence,
           array_to_string(array_remove(ARRAY[
               CASE WHEN b.last_session IS NULL THEN 'No course registration on record' END,
               CASE WHEN b.matric_year_differs THEN 'The matriculation number''s year (' || b.matric_year || ') differs from the entry session ' || b.entry_session END,
               CASE WHEN b.matric_no IS NULL THEN 'No matriculation number on record' END,
               CASE WHEN b.level_conflict AND b.spillover_years = 0 THEN 'The level on record (' || b.current_level || ') differs from the computed level (' || b.computed_level || ')' END,
               CASE WHEN NOT (b.registered_current OR b.enrolled_current) AND b.last_session IS NOT NULL THEN 'Not registered for ' || b.current_session || '; last registered ' || b.last_session END,
               CASE WHEN b.duration_source = 'UNIVERSITY_RULE' THEN 'The programme''s length is the University rule, not set on the programme' END,
               CASE WHEN b.recommendation = 'DATA_INCOMPLETE' THEN 'The entry session or the programme''s length is missing' END,
               CASE WHEN 'ENTRY_SESSION_AHEAD' = ANY (b.issues) THEN 'The entry session is later than the current session' END,
               CASE WHEN 'DUPLICATE_MATRIC' = ANY (b.issues) THEN 'Another student holds the same matriculation number' END
           ]::text[], NULL), '; ') AS confidence_reasons,
           b.recommendation IN ('GRADUATION_CANDIDATE','MAXIMUM_SPILLOVER_REACHED') OR b.recommendation LIKE 'SPILLOVER_YEAR_%' AS actionable,
           concat_ws('; ',
               'Entry session ' || coalesce(b.entry_session, 'not stated')
                   || CASE b.cohort_source WHEN 'MERGED' THEN ' (merged into ' || b.effective_cohort || ')'
                                           WHEN 'OVERRIDE' THEN ' (cohort set by the Registry to ' || b.effective_cohort || ')' ELSE '' END,
               CASE WHEN b.duration_years IS NOT NULL THEN 'programme length ' || b.duration_years || CASE WHEN b.duration_years = 1 THEN ' session' ELSE ' sessions' END
                         || coalesce(' to ' || b.final_level || ' Level', '')
                         || CASE b.duration_source WHEN 'UNIVERSITY_RULE' THEN ' (University rule)' WHEN 'CCE_ROUTE' THEN ' (CCE route)' ELSE '' END
                    ELSE 'programme length not configured' END,
               CASE WHEN b.deferred_sessions > 0 THEN b.deferred_sessions || CASE WHEN b.deferred_sessions = 1 THEN ' session deferred' ELSE ' sessions deferred' END END,
               CASE WHEN b.expected_completion IS NOT NULL THEN 'expected to complete in ' || b.expected_completion END,
               'current session ' || coalesce(b.current_session, 'not open'),
               CASE WHEN b.spillover_years > 0 THEN b.spillover_years || CASE WHEN b.spillover_years = 1 THEN ' session' ELSE ' sessions' END
                         || ' beyond the programme''s length (the limit is ' || b.max_spill || ')' END,
               CASE WHEN b.registered_current THEN 'registered for ' || b.current_session
                    WHEN b.enrolled_current THEN 'enrolled for ' || b.current_session
                    WHEN b.last_session IS NOT NULL THEN 'last registered ' || b.last_session
                    ELSE 'no course registration on record' END,
               CASE b.completion
                    WHEN 'COMPLETED' THEN 'every registered course passed and published' || coalesce(' (to ' || b.highest_level || ' Level)', '')
                    WHEN 'OUTSTANDING_COURSES' THEN b.outstanding || ' course' || CASE WHEN b.outstanding = 1 THEN '' ELSE 's' END || ' still owed (' || b.outstanding_courses || ')'
                    WHEN 'AWAITING_RESULT' THEN 'no published result yet for ' || b.awaiting || ' course' || CASE WHEN b.awaiting = 1 THEN '' ELSE 's' END || ' (' || b.awaiting_courses || ')'
                    WHEN 'FINAL_LEVEL_NOT_REACHED' THEN 'registered up to ' || coalesce(b.highest_level || ' Level', 'no level') || ', below the final ' || b.final_level || ' Level'
                    WHEN 'NO_PUBLISHED_RESULT' THEN 'no published result on record'
                    ELSE CASE WHEN b.in_pool THEN 'completion not yet checked' END END
           ) AS explanation
      FROM (
        SELECT ap.student_id, s.matric_no, ap.matric_year, ap.entry_session, ap.effective_cohort, ap.cohort_source, ap.entry_level, ap.programme_code,
               ap.final_level, ap.duration_years, ap.current_session, ap.current_level, ap.computed_level, ap.expected_completion, ap.deferred_sessions,
               ap.elapsed_sessions, ap.spillover_years, ap.spillover_state, ap.registered_current, ap.enrolled_current, ap.last_session, ap.existing_status,
               ap.classification, ap.proposed_status, ap.rule, ap.confidence AS engine_confidence, ap.issues, ap.computed_at,
               CASE WHEN ap.duration_years IS NULL THEN NULL WHEN s.entry_mode = 'CCE' THEN 'CCE_ROUTE'
                    WHEN p.final_level IS NOT NULL OR p.duration_years IS NOT NULL THEN 'PROGRAMME' ELSE 'UNIVERSITY_RULE' END AS duration_source,
               lc.completion, lc.registered AS registered_courses, lc.published AS published_courses, lc.awaiting, lc.outstanding, lc.highest_level,
               lc.outstanding_courses, lc.awaiting_courses, lc.checked_at AS completion_checked_at,
               (ap.matric_year IS NOT NULL AND policy.session_year(ap.entry_session) IS NOT NULL AND ap.matric_year <> policy.session_year(ap.entry_session)) AS matric_year_differs,
               'LEVEL_CONFLICT' = ANY (ap.issues) AS level_conflict,
               ap.rule IN ('R3','R3L','R4','R4L') AND (ap.spillover_years > 0 OR ap.expected_completion = ap.current_session) AS in_pool,
               cfg.max_spillover_years AS max_spill,
               CASE
                 WHEN ap.rule = 'R5' THEN 'ON_GRADUATION_LIST'
                 WHEN ap.current_session IS NULL OR ap.issues && ARRAY['MISSING_ENTRY_SESSION','ENTRY_SESSION_INVALID','DURATION_NOT_CONFIGURED']::text[] THEN 'DATA_INCOMPLETE'
                 WHEN ap.rule = 'R6' OR ap.issues && ARRAY['ENTRY_SESSION_AHEAD','DUPLICATE_MATRIC']::text[] THEN 'REQUIRES_REVIEW'
                 WHEN ap.spillover_years > 0 AND lc.completion = 'COMPLETED' THEN 'GRADUATION_CANDIDATE'
                 WHEN ap.spillover_years > cfg.max_spillover_years THEN 'MAXIMUM_SPILLOVER_REACHED'
                 WHEN ap.spillover_years > 0 THEN 'SPILLOVER_YEAR_' || ap.spillover_years
                 WHEN ap.expected_completion = ap.current_session THEN 'GRADUATION_CANDIDATE'
                 ELSE 'WITHIN_NORMAL_DURATION' END AS recommendation,
               CASE WHEN ap.rule IN ('R3','R3L','R4','R4L') AND ap.spillover_years > 0 AND lc.completion = 'COMPLETED' THEN 'COMPLETED_BEYOND_LENGTH'
                    WHEN ap.rule IN ('R3','R3L','R4','R4L') AND ap.spillover_years = 0 AND ap.expected_completion = ap.current_session THEN 'FINAL_YEAR' END AS candidate_basis
          FROM people.academic_position ap
          JOIN people.student s ON s.id = ap.student_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN people.lifecycle_completion lc ON lc.student_id = ap.student_id
          CROSS JOIN (SELECT max_spillover_years FROM policy.progression_setting WHERE row_no) cfg
         -- a graduated student, an approved award (R1) and every official status other than ACTIVE and PROBATION stay as they are
         WHERE ap.existing_status IN ('ACTIVE','PROBATION') AND ap.rule <> 'R1'
      ) b
  ) c
  LEFT JOIN people.lifecycle_review rv ON rv.student_id = c.student_id
  LEFT JOIN LATERAL (
      SELECT r.id, r.batch_ref, r.reconciled_at FROM people.lifecycle_reconciliation r
       WHERE r.student_id = c.student_id AND r.effective_session = c.current_session AND r.recommendation = c.recommendation AND r.corrected_at IS NULL
       LIMIT 1) rc ON true;
COMMENT ON VIEW people.lifecycle_recommendation IS
  'V558: each ACTIVE or PROBATION student''s lifecycle recommendation from the cohort engine''s position and the completion check — GRADUATION_CANDIDATE (FINAL_YEAR or COMPLETED_BEYOND_LENGTH), SPILLOVER_YEAR_n, MAXIMUM_SPILLOVER_REACHED, ON_GRADUATION_LIST, WITHIN_NORMAL_DURATION, DATA_INCOMPLETE or REQUIRES_REVIEW — with its confidence and reasons, the explanation written from the record, and its review state for the current session.';

-- ── 3 · who acts, and within what ────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.lifecycle_actor()
RETURNS uuid
LANGUAGE plpgsql STABLE AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'LIFECYCLE_PERSON: a lifecycle reconciliation is the act of a person' USING ERRCODE = '42501'; END IF;
    IF coalesce(office, '') NOT IN ('academic','registrar','dregistrar','records') THEN
        RAISE EXCEPTION 'LIFECYCLE_OFFICE: lifecycle recommendations are reviewed and reconciled by the Academic Office and the Registry' USING ERRCODE = '42501',
            HINT = 'Deans, Heads of Department and ICT read the figures and the history; the Registry acts on them.';
    END IF;
    RETURN who;
END $$;

CREATE FUNCTION people.lifecycle_in_scope(p_student uuid, p_fac text, p_dept text, p_prog text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                    WHERE s.id = p_student AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog))
$$;

-- ── 4 · review: under review, verified, rejected, requiring correction — or pending again ──────────────────────────────
CREATE FUNCTION people.lifecycle_mark(p_students uuid[], p_state text, p_note text, p_single boolean, p_fac text, p_dept text, p_prog text)
RETURNS TABLE (marked int, low int, skipped int)
LANGUAGE plpgsql AS $$
DECLARE who uuid := people.lifecycle_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        v_note text := nullif(btrim(coalesce(p_note, '')), ''); n_mark int := 0; n_low int := 0; n_skip int := 0; r record;
BEGIN
    IF p_state NOT IN ('PENDING','UNDER_REVIEW','VERIFIED','REJECTED','REQUIRES_CORRECTION') THEN
        RAISE EXCEPTION 'LIFECYCLE_REVIEW_STATE: % is not a review state', p_state USING ERRCODE = '23514';
    END IF;
    IF p_state IN ('REJECTED','REQUIRES_CORRECTION') AND v_note IS NULL THEN
        RAISE EXCEPTION 'LIFECYCLE_REVIEW_NOTE: a rejected recommendation, or one whose data needs correcting, says why' USING ERRCODE = '23514',
            HINT = 'Name what is wrong: the entry session, the programme, the level, a missing result.';
    END IF;
    IF p_students IS NULL OR cardinality(p_students) = 0 THEN RETURN QUERY SELECT 0, 0, 0; RETURN; END IF;
    IF cardinality(p_students) > 5000 THEN
        RAISE EXCEPTION 'LIFECYCLE_SIZE: at most 5,000 students at a time' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(p_students) x(id) WHERE NOT people.lifecycle_in_scope(x.id, p_fac, p_dept, p_prog)) THEN
        RAISE EXCEPTION 'LIFECYCLE_SCOPE: a student chosen is outside your scope' USING ERRCODE = '42501';
    END IF;
    PERFORM set_config('moaum.reason', left('Lifecycle review: ' || lower(replace(p_state, '_', ' ')) || coalesce(' — ' || v_note, ''), 2000), true);
    FOR r IN SELECT lr.student_id, lr.recommendation, lr.current_session, lr.confidence, lr.actionable, lr.review_state
               FROM people.lifecycle_recommendation lr WHERE lr.student_id = ANY (p_students) ORDER BY lr.student_id LOOP
        IF r.review_state = 'RECONCILED' OR (p_state = 'VERIFIED' AND NOT r.actionable) OR r.current_session IS NULL THEN
            n_skip := n_skip + 1;
        ELSIF p_state = 'VERIFIED' AND r.confidence = 'LOW' AND NOT coalesce(p_single, false) THEN
            -- a low-confidence record is verified one at a time, never in bulk
            n_low := n_low + 1;
        ELSIF p_state = 'PENDING' THEN
            DELETE FROM people.lifecycle_review WHERE student_id = r.student_id;
            n_mark := n_mark + 1;
        ELSE
            INSERT INTO people.lifecycle_review (student_id, recommendation, session, state, note, reviewed_by, actor_office, reviewed_at)
            VALUES (r.student_id, r.recommendation, r.current_session, p_state, v_note, who, office, now())
            ON CONFLICT (student_id) DO UPDATE SET recommendation = EXCLUDED.recommendation, session = EXCLUDED.session, state = EXCLUDED.state,
                note = EXCLUDED.note, reviewed_by = EXCLUDED.reviewed_by, actor_office = EXCLUDED.actor_office, reviewed_at = EXCLUDED.reviewed_at;
            n_mark := n_mark + 1;
        END IF;
    END LOOP;
    n_skip := n_skip + (cardinality(p_students) - n_mark - n_low - n_skip);   -- students the recommendation does not cover
    RETURN QUERY SELECT n_mark, n_low, n_skip;
END $$;
COMMENT ON FUNCTION people.lifecycle_mark(uuid[], text, text, boolean, text, text, text) IS
  'V558: the chosen students'' current recommendations marked under review, verified, rejected or requiring correction (a note for the last two), or set pending again — never one already reconciled; only an actionable recommendation is verified, and a low-confidence one only on its own (once verified it may be reconciled in a batch). Returns marked, held back as low confidence, and skipped.';

-- ── 5 · a batch, and each student reconciled in it ────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.lifecycle_open_batch(p_description text, p_scope text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := people.lifecycle_actor(); office text := nullif(current_setting('moaum.actor_office', true), ''); v_ref text; v_session text;
BEGIN
    IF btrim(coalesce(p_description, '')) = '' THEN
        RAISE EXCEPTION 'LIFECYCLE_BATCH_DESCRIPTION: a reconciliation batch says what it is for' USING ERRCODE = '23514';
    END IF;
    SELECT name INTO v_session FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1;
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'LIFECYCLE_NO_SESSION: no session is current; a reconciliation takes effect in the current session' USING ERRCODE = '23514';
    END IF;
    v_ref := 'RECON/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('people.lifecycle_batch_seq')::text, 6, '0');
    INSERT INTO people.lifecycle_batch (batch_ref, description, effective_session, scope, created_by, actor_office)
    VALUES (v_ref, btrim(p_description), v_session, nullif(btrim(coalesce(p_scope, '')), ''), who, office);
    RETURN v_ref;
END $$;

-- the chosen students locked, their positions and completion brought up to date, before each is reconciled
CREATE FUNCTION people.lifecycle_prepare(p_students uuid[])
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    PERFORM people.lifecycle_actor();
    IF p_students IS NULL OR cardinality(p_students) = 0 THEN RETURN 0; END IF;
    IF cardinality(p_students) > 500 THEN RAISE EXCEPTION 'LIFECYCLE_SIZE: at most 500 students are reconciled in one step' USING ERRCODE = '23514'; END IF;
    PERFORM 1 FROM people.student WHERE id = ANY (p_students) ORDER BY id FOR UPDATE;
    n := people.refresh_academic_positions(p_students);
    PERFORM people.refresh_lifecycle_completion(p_students);
    RETURN n;
END $$;

CREATE FUNCTION people.lifecycle_reconcile(p_batch text, p_student uuid, p_expect text, p_outcome text, p_status text, p_reason text,
                                           p_fac text, p_dept text, p_prog text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := people.lifecycle_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); b people.lifecycle_batch; s people.student; r record;
        v_out text; v_status text; v_level int; v_dec uuid; v_id uuid;
BEGIN
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'LIFECYCLE_REASON: a reconciliation says why' USING ERRCODE = '23514', HINT = 'Cite the evidence: the registrations, the results, the Registry''s review.';
    END IF;
    SELECT * INTO b FROM people.lifecycle_batch WHERE batch_ref = p_batch FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LIFECYCLE_BATCH: no reconciliation batch %', p_batch USING ERRCODE = '23514'; END IF;
    IF b.created_by <> who THEN RAISE EXCEPTION 'LIFECYCLE_BATCH_OWNER: a batch is reconciled by the officer who opened it' USING ERRCODE = '42501'; END IF;
    IF b.closed_at IS NOT NULL THEN RAISE EXCEPTION 'LIFECYCLE_BATCH_CLOSED: batch % is closed' , p_batch USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no student %', p_student USING ERRCODE = 'no_data_found'; END IF;
    IF NOT people.lifecycle_in_scope(p_student, p_fac, p_dept, p_prog) THEN
        RAISE EXCEPTION 'LIFECYCLE_SCOPE: the student is outside your scope' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO r FROM people.lifecycle_recommendation WHERE student_id = p_student;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIFECYCLE_NOT_APPLICABLE: the student''s status is % — lifecycle reconciliation is for active students', s.status USING ERRCODE = '23514';
    END IF;
    IF r.recommendation IS DISTINCT FROM p_expect THEN
        RAISE EXCEPTION 'LIFECYCLE_CHANGED: the recommendation is now % (it was % when reviewed)', r.recommendation, coalesce(p_expect, 'none') USING ERRCODE = '23514',
            HINT = 'Review the student again: the record changed since.';
    END IF;
    IF r.review_state = 'RECONCILED' THEN
        RAISE EXCEPTION 'LIFECYCLE_ALREADY: already reconciled for % in batch %', r.current_session, r.batch_ref USING ERRCODE = '23514';
    END IF;
    IF NOT r.actionable THEN
        RAISE EXCEPTION 'LIFECYCLE_NOT_ACTIONABLE: % is not reconciled — correct the record or decide the standing on it', r.recommendation USING ERRCODE = '23514';
    END IF;
    IF r.review_state <> 'VERIFIED' THEN
        RAISE EXCEPTION 'LIFECYCLE_NOT_VERIFIED: the recommendation is % — only a verified one is reconciled', lower(replace(r.review_state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF r.recommendation LIKE 'SPILLOVER_YEAR_%' THEN
        IF coalesce(p_outcome, 'SPILLOVER_CONFIRMED') <> 'SPILLOVER_CONFIRMED' THEN
            RAISE EXCEPTION 'LIFECYCLE_OUTCOME: a spillover is confirmed; the student stays %', s.status USING ERRCODE = '23514';
        END IF;
        v_out := 'SPILLOVER_CONFIRMED'; v_status := s.status; v_level := greatest(s.current_level, coalesce(r.final_level, s.current_level));
    ELSIF r.recommendation = 'MAXIMUM_SPILLOVER_REACHED' THEN
        IF p_outcome = 'KEPT_ACTIVE_LIMIT_REACHED' THEN
            v_out := p_outcome; v_status := s.status; v_level := greatest(s.current_level, coalesce(r.final_level, s.current_level));
        ELSIF p_outcome = 'STATUS_CHANGED' AND p_status IN ('DORMANT','WITHDRAWN') THEN
            v_out := p_outcome; v_status := p_status; v_level := s.current_level;
        ELSE
            RAISE EXCEPTION 'LIFECYCLE_LIMIT_OUTCOME: at the maximum spillover the officer chooses: kept active and flagged, or dormant or withdrawn on a reason' USING ERRCODE = '23514';
        END IF;
    ELSE
        IF coalesce(p_outcome, 'GRADUATION_LIST') <> 'GRADUATION_LIST' THEN
            RAISE EXCEPTION 'LIFECYCLE_OUTCOME: a graduation candidate is put on the graduation list; the Senate approves the award' USING ERRCODE = '23514';
        END IF;
        v_out := 'GRADUATION_LIST'; v_status := s.status; v_level := greatest(s.current_level, coalesce(r.final_level, s.current_level));
    END IF;

    PERFORM set_config('moaum.reason', left('Lifecycle reconciliation ' || p_batch || ': ' || v_reason, 2000), true);
    IF v_status <> s.status THEN
        PERFORM people.change_status(p_student, v_status, 'Lifecycle reconciliation · ' || p_batch, current_date, v_reason);
    END IF;
    IF v_level > s.current_level THEN
        UPDATE people.student SET current_level = v_level WHERE id = p_student AND current_level < v_level;   -- never lowers
    ELSE
        v_level := s.current_level;
    END IF;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                        previous_level, new_level, rule, reason, officer, actor_office, batch_ref)
    VALUES (p_student, s.status, r.proposed_status, v_status, r.classification, r.entry_session, r.effective_cohort,
            s.current_level, v_level, 'LIFECYCLE_' || r.recommendation, v_reason, who, office, p_batch)
    RETURNING id INTO v_dec;
    INSERT INTO people.lifecycle_reconciliation (batch_ref, student_id, effective_session, recommendation, confidence, outcome, previous_status, new_status,
                                                 previous_level, new_level, effective_cohort, expected_completion, spillover_years, completion, explanation, reason,
                                                 decision_id, reconciled_by, actor_office)
    VALUES (p_batch, p_student, r.current_session, r.recommendation, r.confidence, v_out, s.status, v_status, s.current_level, v_level,
            r.effective_cohort, r.expected_completion, r.spillover_years, r.completion, r.explanation, v_reason, v_dec, who, office)
    RETURNING id INTO v_id;
    UPDATE people.lifecycle_batch SET reconciled = reconciled + 1 WHERE batch_ref = p_batch;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION people.lifecycle_reconcile(text, uuid, text, text, text, text, text, text, text) IS
  'V558: one verified recommendation reconciled in the officer''s batch, all or nothing: revalidated first (a changed recommendation is refused), then a spillover confirmed (status kept, level raised to the final level where lower), a maximum spillover kept ACTIVE flagged or made DORMANT or WITHDRAWN by people.change_status on the officer''s choice, or a graduation candidate marked for the graduation list — the cohort decision written, never GRADUATED.';

-- the graduation-list entry the audit made for a candidate, recorded on the reconciliation
CREATE FUNCTION people.lifecycle_graduand_placed(p_reconciliation uuid, p_graduand uuid, p_added boolean, p_unmet text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := people.lifecycle_actor();
BEGIN
    UPDATE people.lifecycle_reconciliation SET graduand_id = p_graduand, graduand_added = coalesce(p_added, false), graduand_unmet = p_unmet
     WHERE id = p_reconciliation AND outcome = 'GRADUATION_LIST' AND reconciled_by = who AND graduand_id IS NULL AND corrected_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'LIFECYCLE_GRADUAND: that reconciliation does not await a graduation-list entry' USING ERRCODE = '23514'; END IF;
END $$;

CREATE FUNCTION people.lifecycle_close_batch(p_batch text, p_skipped int)
RETURNS people.lifecycle_batch
LANGUAGE plpgsql AS $$
DECLARE who uuid := people.lifecycle_actor(); b people.lifecycle_batch;
BEGIN
    UPDATE people.lifecycle_batch SET closed_at = coalesce(closed_at, now()), skipped = skipped + greatest(coalesce(p_skipped, 0), 0)
     WHERE batch_ref = p_batch AND created_by = who RETURNING * INTO b;
    IF NOT FOUND THEN RAISE EXCEPTION 'LIFECYCLE_BATCH: no batch % of yours', p_batch USING ERRCODE = '23514'; END IF;
    RETURN b;
END $$;

CREATE FUNCTION people.lifecycle_batch_skipped(p_batch text, p_skipped int)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := people.lifecycle_actor();
BEGIN
    UPDATE people.lifecycle_batch SET skipped = skipped + greatest(coalesce(p_skipped, 0), 0) WHERE batch_ref = p_batch AND created_by = who AND closed_at IS NULL;
END $$;

-- ── 6 · a reconciliation corrected ───────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.lifecycle_correct(p_reconciliation uuid, p_reason text, p_fac text, p_dept text, p_prog text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := people.lifecycle_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); x people.lifecycle_reconciliation; s people.student; g records.graduand;
        v_level int; v_restored boolean := false; v_dec uuid;
BEGIN
    IF v_reason IS NULL THEN RAISE EXCEPTION 'LIFECYCLE_REASON: a correction says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO x FROM people.lifecycle_reconciliation WHERE id = p_reconciliation FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no reconciliation %', p_reconciliation USING ERRCODE = 'no_data_found'; END IF;
    IF x.corrected_at IS NOT NULL THEN RAISE EXCEPTION 'LIFECYCLE_CORRECTED: that reconciliation was corrected on %', to_char(x.corrected_at, 'DD Mon YYYY') USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM people.student WHERE id = x.student_id FOR UPDATE;
    IF NOT people.lifecycle_in_scope(x.student_id, p_fac, p_dept, p_prog) THEN
        RAISE EXCEPTION 'LIFECYCLE_SCOPE: the student is outside your scope' USING ERRCODE = '42501';
    END IF;
    IF x.new_status <> x.previous_status AND s.status <> x.new_status THEN
        RAISE EXCEPTION 'LIFECYCLE_STATUS_MOVED: the status has changed since (now %); correct it on the record', s.status USING ERRCODE = '23514';
    END IF;
    IF x.graduand_id IS NOT NULL AND x.graduand_added THEN
        SELECT * INTO g FROM records.graduand WHERE id = x.graduand_id FOR UPDATE;
        IF FOUND AND g.senate_state <> 'AWAITING' THEN
            RAISE EXCEPTION 'LIFECYCLE_SENATE_ACTED: the Senate has % the award; the graduation list is corrected through the Senate', lower(g.senate_state) USING ERRCODE = '23514';
        END IF;
    END IF;

    PERFORM set_config('moaum.reason', left('Lifecycle reconciliation ' || x.batch_ref || ' corrected: ' || v_reason, 2000), true);
    IF x.new_status <> x.previous_status THEN
        PERFORM people.change_status(x.student_id, x.previous_status, 'Lifecycle reconciliation corrected · ' || x.batch_ref, current_date, v_reason);
    END IF;
    v_level := s.current_level;
    IF x.new_level IS DISTINCT FROM x.previous_level AND s.current_level = x.new_level THEN
        UPDATE people.student SET current_level = x.previous_level WHERE id = x.student_id;
        v_level := x.previous_level; v_restored := true;
    END IF;
    IF x.graduand_id IS NOT NULL AND x.graduand_added THEN
        DELETE FROM records.graduand WHERE id = x.graduand_id AND senate_state = 'AWAITING';
    END IF;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, previous_cohort, effective_cohort,
                                        previous_level, new_level, rule, reason, officer, actor_office, batch_ref)
    VALUES (x.student_id, s.status, x.previous_status, x.previous_status, x.effective_cohort, x.effective_cohort,
            s.current_level, v_level, 'LIFECYCLE_CORRECTION', v_reason, who, office, x.batch_ref)
    RETURNING id INTO v_dec;
    UPDATE people.lifecycle_reconciliation SET corrected_at = now(), corrected_by = who, correction_reason = v_reason, correction_decision_id = v_dec,
                                               level_restored = v_restored
     WHERE id = x.id;
    UPDATE people.lifecycle_batch SET corrected = corrected + 1 WHERE batch_ref = x.batch_ref;
    -- the student is reviewed again
    INSERT INTO people.lifecycle_review (student_id, recommendation, session, state, note, reviewed_by, actor_office, reviewed_at)
    VALUES (x.student_id, x.recommendation, x.effective_session, 'UNDER_REVIEW', 'Reconciliation ' || x.batch_ref || ' corrected: ' || v_reason, who, office, now())
    ON CONFLICT (student_id) DO UPDATE SET recommendation = EXCLUDED.recommendation, session = EXCLUDED.session, state = EXCLUDED.state, note = EXCLUDED.note,
        reviewed_by = EXCLUDED.reviewed_by, actor_office = EXCLUDED.actor_office, reviewed_at = EXCLUDED.reviewed_at;
    -- the position follows: noted when the caller refreshes a page together, at once otherwise
    IF coalesce(current_setting('moaum.position_defer', true), '') = 'on' THEN
        PERFORM set_config('moaum.position_pending', coalesce(current_setting('moaum.position_pending', true), '') || x.student_id::text || ',', true);
    ELSE
        PERFORM people.refresh_academic_position(x.student_id);
    END IF;
    RETURN v_dec;
END $$;
COMMENT ON FUNCTION people.lifecycle_correct(uuid, text, text, text, text) IS
  'V558: a lifecycle reconciliation reversed on a reason, all or nothing: the status changed back through people.change_status (refused when it has moved since), a level it raised put back where nobody has changed it since, a graduation-list entry it added removed while the Senate has not acted on it; the reconciliation is kept and marked corrected, the student is under review again.';

-- ── 7 · grants, as V331 gives the cohort tables ──────────────────────────────────────────────────────────────────────
GRANT SELECT ON people.lifecycle_completion, people.lifecycle_review, people.lifecycle_batch, people.lifecycle_reconciliation, people.lifecycle_recommendation
    TO app_auditor, app_acrecords, app_reporting;

COMMIT;

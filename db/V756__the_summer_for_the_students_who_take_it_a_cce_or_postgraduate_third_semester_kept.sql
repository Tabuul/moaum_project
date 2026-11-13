-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V756 · The Summer for the students who take it: a CCE or postgraduate third semester kept
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The Summer Semester is semester 3 of its session for an undergraduate outside the Centre for Continuing Education — the same
--  students registration.summer_eligibility admits (V735, V739). A CCE student and a postgraduate student have a third semester of
--  their own (V379, V389): in a session that also had a Summer it is still their third semester, registered, paid for and
--  examined as such.
--
--  V735, V739, V741 and V754 read every semester 3 of a session with a Summer as the Summer, whoever the student. For a CCE or
--  postgraduate third semester in such a session that meant:
--    · the examination card asked for a Summer payment the student can never make (registration.exam_card_state), and the
--      withheld-cards list said so (registration.exam_cards_withheld);
--    · its results were released on the Summer's rule, not the student's own fees (finance.results_cleared);
--    · its fees were left out of the semesters registered for school fees (finance.reg_semesters, finance.fee_profiles) and of
--      the registrations-without-fees list (finance.registrations_without_fees);
--    · its results were left out of the student's standing (assessment.student_standing);
--    · its transcript, results statement, examination card and permit named it the Summer semester (credentials.build_statement,
--      registration.exam_card_state, registration.gst_eps_permit_state — V754);
--    · the student's menu offered the Summer Semester page for any semester-3 registration (registration.summer_area).
--  registration.is_summer_for(student, session, semester) now answers for the student, and each of those reads it. The course
--  registration gate already kept CCE and postgraduate students out (V735) and now reads the same answer. A class opened for
--  semester 3 still runs any course (catalogue.open_class): it is a class, not a student.
--
--  Also, from the review of V754 and of this change:
--    · a CCE or postgraduate third semester now in the standing is read by the rule of the end of a session (assessment.standing_of
--      says nothing for a semester 3, which only the Summer is now) — never GOOD for a CGPA under the threshold;
--    · the session-wide readers test semester 3 first, so only semester-3 rows ask registration.is_summer_for;
--    · a withdrawn or restored Summer permit's message, and the student's result status, name the Summer; the Summer's results are
--      not "not yet uploaded" while the Summer is still running (assessment.student_result_periods, student_result_status);
--    · the Bursary's list of reallocations at the old count (finance.reallocations_at_old_level) holds only reallocations that moved
--      money and still stand;
--    · the Academic Office's list (registration.summer_authorisations_to_review) reads a rewritten authorisation as it stands now:
--      gone once revoked, re-authorised since the repair, or naming the course the trail gives; one row per course a repair took;
--    · a course-scoped grant (iam.course_grant_follow) ends on a twin only when the twin is in force; a twin not begun yet bounds the
--      followed grant to the day before it begins;
--    · the grants V754's one-off repair moved or ended by code are followed again each from the date it began, read from its first V754
--      entry to its last: a grant ended on a twin of the right course stays ended, one ended wrongly is restored to the right course, one
--      moved to another grant's course moves to its own (a grant changed since is left as it stands; none ends later than it was to);
--    · the probation refusal of a registration names a standing pronounced on a third semester (registration.submit_checks).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V756: the Summer for the students who take it', true);

CREATE FUNCTION registration.is_summer_for(p_student uuid, p_session text, p_semester integer) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT registration.is_summer(p_session, p_semester)
       AND EXISTS (SELECT 1 FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                    WHERE s.id = p_student AND coalesce(s.entry_mode, '') NOT IN ('CCE', 'POSTGRADUATE') AND p.category = 'UNDER GRADUATE');
$$;
COMMENT ON FUNCTION registration.is_summer_for(uuid, text, integer) IS
    'V756: true for semester 3 of a session that had a Summer Semester, for an undergraduate outside CCE (whom the Summer admits); a CCE or postgraduate student''s semester 3 is their own third semester. Callers over many rows test semester = 3 first.';

-- each reader of "semester 3 of a session with a Summer" asks for the student; every anchor must be found exactly as many times as stated
DO $$
DECLARE d text; i int; n int; sig text;
    -- {signature, anchor, replacement, times}
    edits text[][] := ARRAY[
      ARRAY['registration.exam_card_state(uuid,text,integer)',
            'WHEN EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session) THEN ''Summer'' ELSE ''third'' END',
            'WHEN registration.is_summer_for(p_student, p_session, p_semester) THEN ''Summer'' ELSE ''third'' END', '1'],
      ARRAY['registration.exam_card_state(uuid,text,integer)',
            'v_paid := CASE WHEN p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session)',
            'v_paid := CASE WHEN registration.is_summer_for(p_student, p_session, p_semester)   -- V756', '1'],
      ARRAY['registration.exam_card_state(uuid,text,integer)',
            '''summer'', registration.is_summer(p_session, p_semester)',
            '''summer'', registration.is_summer_for(p_student, p_session, p_semester)', '1'],
      ARRAY['registration.exam_cards_withheld(text,integer)',
            'WHEN r.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session)',
            'WHEN r.semester = 3 AND registration.is_summer_for(r.student_id, p_session, r.semester)', '1'],
      ARRAY['registration.exam_cards_withheld(text,integer)',
            'CASE WHEN k.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session)',
            'CASE WHEN k.semester = 3 AND registration.is_summer_for(k.student_id, p_session, k.semester)', '1'],
      ARRAY['finance.results_cleared(uuid,text,integer)',
            'IF p_semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session) THEN',
            'IF registration.is_summer_for(p_student, p_session, p_semester) THEN   -- V756: the Summer of a student it admits', '1'],
      ARRAY['assessment.student_standing(uuid)',
            'AND NOT (g.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = g.session))',
            'AND NOT (g.semester = 3 AND registration.is_summer_for(p_student, g.session, g.semester))   -- V756: the student''s Summer', '1'],
      -- a third semester left in the standing (CCE, postgraduate, a session with no Summer) is the end of that session's year
      ARRAY['assessment.student_standing(uuid)',
            'assessment.standing_of(l.level, l.semester, l.cgpa, l.lcgpa,',
            'assessment.standing_of(l.level, CASE WHEN l.semester = 3 THEN 2 ELSE l.semester END, l.cgpa, l.lcgpa,', '1'],
      ARRAY['finance.registrations_without_fees(text)',
            'AND NOT (r.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session))',
            'AND NOT (r.semester = 3 AND registration.is_summer_for(r.student_id, p_session, r.semester))', '1'],
      ARRAY['finance.reg_semesters(uuid,text)',
            'AND NOT (cr.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session))',
            'AND NOT (cr.semester = 3 AND registration.is_summer_for(p_student, p_session, cr.semester))', '1'],
      ARRAY['finance.fee_profiles(text)',
            'AND NOT (cr.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session))',
            'AND NOT (cr.semester = 3 AND registration.is_summer_for(cr.student_id, p_session, cr.semester))', '1'],
      ARRAY['registration.registration_gate(uuid,text,integer)',
            E'WHEN p_semester = 3 AND st.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'')\n                  AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session)',
            'WHEN registration.is_summer_for(p_student, p_session, p_semester)   -- V756', '1'],
      ARRAY['credentials.build_statement(uuid,text,text,integer)',
            '''summer'', registration.is_summer(r.session, r.semester)',
            '''summer'', registration.is_summer_for(p_student, r.session, r.semester)', '2'],
      ARRAY['registration.gst_eps_permit_state(uuid,text,integer)',
            'v_summer := registration.is_summer(p_session, p_semester) AND s.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'');',
            'v_summer := registration.is_summer_for(p_student, p_session, p_semester);', '1'],
      ARRAY['registration.gst_eps_permit_state(uuid,text,integer)',
            'CASE WHEN registration.is_summer(p_session, 3) THEN ''Summer'' ELSE ''third'' END',
            'CASE WHEN registration.is_summer_for(p_student, p_session, 3) THEN ''Summer'' ELSE ''third'' END', '1'],
      ARRAY['registration.summer_area(uuid)',
            'WHERE r.student_id = p_student AND r.semester = 3)',
            'WHERE r.student_id = p_student AND r.semester = 3 AND registration.is_summer_for(p_student, r.session, r.semester))', '1'],
      -- the messages of a withdrawn or restored permit name the Summer as the permit does
      ARRAY['registration.revoke_gst_eps_permit(uuid,text,text,boolean)',
            'v_sem := CASE pm.semester WHEN 1 THEN ''first'' WHEN 2 THEN ''second'' ELSE ''third'' END || '' semester'';',
            'v_sem := CASE pm.semester WHEN 1 THEN ''first'' WHEN 2 THEN ''second''
                  ELSE CASE WHEN registration.is_summer_for(pm.student_id, pm.session, pm.semester) THEN ''Summer'' ELSE ''third'' END END || '' semester'';   -- V756', '1'],
      -- the student's Summer is in progress until its results are due; its status names it
      ARRAY['assessment.student_result_periods(uuid)',
            'WHERE m.route = ''CCE'' AND m.session = p.session AND m.number = p.semester AND m.state IN (''OPEN'', ''NOT_YET_OPEN''))',
            'WHERE m.route = ''CCE'' AND m.session = p.session AND m.number = p.semester AND m.state IN (''OPEN'', ''NOT_YET_OPEN''))
             -- V756: the student''s Summer Semester runs until its results are due (its examinations'' end, else its registration''s close)
             OR (p.semester = 3 AND registration.is_summer_for(p_student, p.session, p.semester)
                 AND EXISTS (SELECT 1 FROM registration.summer_period q
                              WHERE q.session = p.session AND current_date <= coalesce(q.results_due, q.exams_to, q.registration_closes)))', '1'],
      ARRAY['assessment.student_result_status(uuid)',
            'WHEN 3 THEN ''third''',
            'WHEN 3 THEN CASE WHEN registration.is_summer_for(p_student, p.session, 3) THEN ''Summer'' ELSE ''third'' END', '1'],
      -- a standing pronounced on a CCE or postgraduate third semester is named so (never on the Summer, which the standing leaves out)
      ARRAY['registration.submit_checks(uuid)',
            'CASE st.pronounced_semester WHEN 1 THEN ''first'' ELSE ''second'' END',
            'CASE st.pronounced_semester WHEN 1 THEN ''first'' WHEN 2 THEN ''second'' ELSE ''third'' END', '1']];
BEGIN
    i := 1;
    WHILE i <= array_length(edits, 1) LOOP
        sig := edits[i][1];
        d := pg_get_functiondef(sig::regprocedure);
        -- every edit of one function, applied to one text and executed once
        WHILE i <= array_length(edits, 1) AND edits[i][1] = sig LOOP
            n := (length(d) - length(replace(d, edits[i][2], ''))) / length(edits[i][2]);
            IF n <> edits[i][4]::int THEN
                RAISE EXCEPTION 'V756: % is not as V754 left it (% found % times, % expected)', sig, left(edits[i][2], 70), n, edits[i][4];
            END IF;
            d := replace(d, edits[i][2], edits[i][3]);
            i := i + 1;
        END LOOP;
        IF position('summer_period sp WHERE sp.session' IN d) > 0 OR position('registration.is_summer(' IN d) > 0 THEN
            RAISE EXCEPTION 'V756: % still reads the Summer for every student', sig;
        END IF;
        EXECUTE d;
    END LOOP;
END $$;

-- ── the Bursary's list: reallocations that moved money and still stand ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.reallocations_at_old_level()
RETURNS TABLE (id uuid, realloc_ref text, status text, reference text, amount numeric, student_id uuid, matric_no text, name text,
               entry_session text, to_purpose text, to_session text, to_semester integer, level_recorded integer, level_now integer,
               initiated_at timestamptz, executed_at timestamptz)
LANGUAGE sql STABLE AS $$
    -- V756: a rejected, cancelled, failed, pending or returned correction moved no money, a reversed one is back where it came from,
    -- and a reversal is the money's return: only a completed reallocation is at a level
    SELECT x.id, x.realloc_ref, x.status, x.reference, x.amount, x.student_id, coalesce(s.matric_no, s.admission_no),
           s.surname || ', ' || s.other_names, s.entry_session, x.to_purpose, x.to_session, x.to_semester, x.to_level,
           people.level_in(x.student_id, x.to_session), x.initiated_at, x.executed_at
      FROM finance.payment_reallocation x JOIN people.student s ON s.id = x.student_id
     WHERE x.kind = 'REALLOCATION' AND x.status = 'COMPLETED'
       AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
       AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(s.entry_session))
       AND x.to_level IS DISTINCT FROM people.level_in(x.student_id, x.to_session)
     ORDER BY x.initiated_at DESC;
$$;

-- ── the Academic Office's list: a rewritten authorisation as it stands now ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.summer_authorisations_to_review(p_session text)
RETURNS TABLE (kind text, session text, student_id uuid, number text, name text, course_named text, courses_now text[], trail_gives text,
               rewritten_by text, at timestamptz)
LANGUAGE sql STABLE AS $$
    -- an authorisation naming a course no longer on the catalogue (what the trail from the grant gives, where it gives one)
    SELECT 'DEAD_CODE', sa.session, sa.student_id, coalesce(st.matric_no, st.admission_no), st.surname || ', ' || st.other_names,
           upper(btrim(x)), sa.courses, registration.summer_code_after(x, sa.granted_at), NULL::text, sa.granted_at
      FROM registration.summer_authorisation sa JOIN people.student st ON st.id = sa.student_id
      CROSS JOIN LATERAL unnest(sa.courses) x
     WHERE (p_session IS NULL OR sa.session = p_session) AND sa.revoked_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x)))
    UNION ALL
    -- an authorisation a one-off repair (V746, V751, V753) rewrote to another course than the trail from the grant gives, each choice
    -- brought forward to today; V756: read as it stands now — gone once revoked, re-authorised since the repair, or naming the course
    -- the trail gives; the latest repair of a course once
    SELECT 'REWRITTEN', w.session, w.student_id, w.number, w.name, w.old_code, w.courses, w.trail, w.by, w.at
      FROM (SELECT DISTINCT ON (sa.session, sa.student_id, o.old_code)
                   sa.session, sa.student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name,
                   o.old_code, sa.courses, t.trail, split_part(e.reason, ':', 1) AS by, e.occurred_at AS at
              FROM audit.entries e
              JOIN registration.summer_authorisation sa
                ON sa.session = e.after_state ->> 'session' AND sa.student_id = (e.after_state ->> 'student_id')::uuid
              JOIN people.student st ON st.id = sa.student_id
              CROSS JOIN LATERAL (SELECT upper(btrim(b)) AS old_code FROM jsonb_array_elements_text(e.before_state -> 'courses') b
                                   WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(e.after_state -> 'courses') a
                                                      WHERE upper(btrim(a)) = upper(btrim(b)))) o
              CROSS JOIN LATERAL (SELECT registration.summer_code_after(o.old_code, (e.before_state ->> 'granted_at')::timestamptz) AS trail) t
             WHERE e.subject_type = 'registration.summer_authorisation' AND (e.reason LIKE 'V746:%' OR e.reason LIKE 'V751:%' OR e.reason LIKE 'V753:%')
               AND (p_session IS NULL OR e.after_state ->> 'session' = p_session)
               AND sa.revoked_at IS NULL AND sa.granted_at <= e.occurred_at
               AND t.trail IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM unnest(sa.courses) a
                                WHERE upper(btrim(a)) = t.trail
                                   OR coalesce(registration.summer_code_after(upper(btrim(a)), e.occurred_at), upper(btrim(a))) = t.trail)
             ORDER BY sa.session, sa.student_id, o.old_code, e.occurred_at DESC) w
    ORDER BY 1, 2, 5;
$$;

-- ── a course-scoped grant follows its course; a twin ends it only once in force ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION iam.course_grant_follow(p_old text, p_new text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n int; m int; k int; v_ended uuid[]; v_bounded uuid[];
BEGIN
    IF upper(btrim(p_old)) = upper(btrim(p_new)) THEN RETURN 0; END IF;
    -- a live grant whose holder already holds the same office on the new code, in force today, ends keeping the code it had (the
    -- merge must not fail on the twin)
    WITH e AS (
        UPDATE iam.office_assignment a SET valid_to = greatest(a.valid_from, current_date)
         WHERE a.scope_kind = 'course' AND upper(btrim(a.scope_id)) = upper(btrim(p_old)) AND a.valid_to IS NULL
           AND EXISTS (SELECT 1 FROM iam.office_assignment b
                        WHERE b.person_id = a.person_id AND b.office_code = a.office_code AND b.valid_to IS NULL AND b.valid_from <= current_date
                          AND b.scope_kind = 'course' AND upper(btrim(b.scope_id)) = upper(btrim(p_new)))
        RETURNING a.id)
    SELECT coalesce(array_agg(e.id), '{}') INTO v_ended FROM e;
    m := cardinality(v_ended);
    -- V756: a twin that has not begun yet: the grant follows its course and ends the day before the twin begins
    WITH f AS (
        UPDATE iam.office_assignment a SET scope_id = p_new,
               valid_to = greatest(a.valid_from, (SELECT min(b.valid_from) FROM iam.office_assignment b
                                                    WHERE b.person_id = a.person_id AND b.office_code = a.office_code AND b.valid_to IS NULL
                                                      AND b.scope_kind = 'course' AND upper(btrim(b.scope_id)) = upper(btrim(p_new))) - 1)
         WHERE a.scope_kind = 'course' AND upper(btrim(a.scope_id)) = upper(btrim(p_old)) AND a.valid_to IS NULL AND a.id <> ALL (v_ended)
           AND EXISTS (SELECT 1 FROM iam.office_assignment b
                        WHERE b.person_id = a.person_id AND b.office_code = a.office_code AND b.valid_to IS NULL
                          AND b.scope_kind = 'course' AND upper(btrim(b.scope_id)) = upper(btrim(p_new)))
        RETURNING a.id)
    SELECT coalesce(array_agg(f.id), '{}') INTO v_bounded FROM f;
    k := cardinality(v_bounded);
    UPDATE iam.office_assignment a SET scope_id = p_new
     WHERE a.scope_kind = 'course' AND upper(btrim(a.scope_id)) = upper(btrim(p_old))
       AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND a.id <> ALL (v_ended) AND a.id <> ALL (v_bounded);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n + m + k;
END $$;
COMMENT ON FUNCTION iam.course_grant_follow(text, text) IS
    'V754, V756: every course-scoped grant in force bounded by p_old follows the course to p_new; a holder with a twin on p_new in force keeps the twin (the other ends with its code); a twin not begun yet bounds the followed grant to the day before it begins.';

-- ── put right, and told ──────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record; g iam.office_assignment; v_right text; v_now text; v_ended boolean; v_day date; v_end date; v_start date; n_regrant int := 0;
        n_cce int; n_pg int;
BEGIN
    -- V754's one-off repair called the follow once for each grant naming a dead code, each time by that grant's date, so a grant could
    -- be moved to another grant's course, or ended on a twin and then moved, ended, by a later call. Each grant it touched is read from its
    -- first V754 entry (as it was) to its last (as V754 left it) and followed again from the date it began, alone. A grant changed since
    -- V754 in any other way is left as it stands.
    FOR r IN WITH v AS (
                 SELECT e.subject_id::text AS gid, e.occurred_at, e.before_state AS b, e.after_state AS a,
                        row_number() OVER (PARTITION BY e.subject_id ORDER BY e.occurred_at, e.id) AS k,
                        count(*) OVER (PARTITION BY e.subject_id) AS n
                   FROM audit.entries e
                  WHERE e.subject_type = 'iam.office_assignment' AND e.reason LIKE 'V754:%'
                    AND e.before_state ->> 'scope_kind' = 'course'
                    AND (upper(btrim(e.before_state ->> 'scope_id')) <> upper(btrim(e.after_state ->> 'scope_id'))
                         OR (e.before_state ->> 'valid_to') IS DISTINCT FROM (e.after_state ->> 'valid_to')))
             SELECT f.gid, f.b ->> 'scope_id' AS old_code, (f.b ->> 'valid_from')::date AS began, nullif(f.b ->> 'valid_to', '')::date AS was_to,
                    l.a ->> 'scope_id' AS last_code, nullif(l.a ->> 'valid_to', '')::date AS last_to, l.occurred_at AS at
               FROM v f JOIN v l ON l.gid = f.gid AND l.k = l.n
              WHERE f.k = 1 LOOP
        v_right := registration.summer_code_after(r.old_code, r.began::timestamptz);
        IF v_right IS NULL THEN CONTINUE; END IF;
        SELECT * INTO g FROM iam.office_assignment a WHERE a.id::text = r.gid AND a.scope_kind = 'course';
        IF NOT FOUND THEN CONTINUE; END IF;
        -- as V754 left it: the course it was put on (its code today) and the end it was given
        v_now := coalesce(registration.summer_code_after(r.last_code, r.at), upper(btrim(r.last_code)));
        IF upper(btrim(g.scope_id)) <> v_now OR g.valid_to IS DISTINCT FROM r.last_to THEN CONTINUE; END IF;
        v_day := r.at::date;
        v_ended := r.last_to IS DISTINCT FROM r.was_to;
        IF v_ended THEN
            -- ended on a twin: right when the holder held the right course that day; nothing to restore if it would have ended by now
            IF EXISTS (SELECT 1 FROM iam.office_assignment b
                        WHERE b.person_id = g.person_id AND b.office_code = g.office_code AND b.id <> g.id AND b.scope_kind = 'course'
                          AND upper(btrim(b.scope_id)) = v_right AND b.valid_from <= v_day
                          AND (b.valid_to IS NULL OR b.valid_to >= v_day
                               -- ended since V754 ran, whatever end it was given: it stood on V754's day
                               OR EXISTS (SELECT 1 FROM audit.entries x
                                           WHERE x.subject_type = 'iam.office_assignment' AND x.subject_id::text = b.id::text AND x.occurred_at > r.at
                                             AND (x.before_state ->> 'valid_to') IS NULL AND (x.after_state ->> 'valid_to') IS NOT NULL)))
               OR (r.was_to IS NOT NULL AND r.was_to < current_date) THEN
                CONTINUE;
            END IF;
            v_end := r.was_to;
        ELSE
            -- moved: nothing to do when V754 followed it to the right course, or it has ended since of itself
            IF v_now = v_right OR (g.valid_to IS NOT NULL AND g.valid_to < current_date) THEN CONTINUE; END IF;
            v_end := g.valid_to;
        END IF;
        -- a twin on the right course in force that covers the grant's whole term: the holder keeps the twin; a moved grant ends (never later
        -- than it was to), an ended one stays ended
        IF EXISTS (SELECT 1 FROM iam.office_assignment b
                    WHERE b.person_id = g.person_id AND b.office_code = g.office_code AND b.id <> g.id AND b.scope_kind = 'course'
                      AND upper(btrim(b.scope_id)) = v_right AND b.valid_from <= current_date
                      AND (b.valid_to IS NULL OR b.valid_to >= coalesce(v_end, 'infinity'::date))) THEN
            IF NOT v_ended THEN
                UPDATE iam.office_assignment a SET valid_to = greatest(a.valid_from, least(coalesce(a.valid_to, current_date), current_date))
                 WHERE a.id = g.id;
                n_regrant := n_regrant + 1;
            END IF;
            CONTINUE;
        END IF;
        -- the right course, to its own end, bounded by the day before an open-ended twin on the right course that has not begun
        SELECT min(b.valid_from) INTO v_start FROM iam.office_assignment b
         WHERE b.person_id = g.person_id AND b.office_code = g.office_code AND b.id <> g.id AND b.scope_kind = 'course'
           AND upper(btrim(b.scope_id)) = v_right AND b.valid_to IS NULL AND b.valid_from > current_date;
        IF v_start IS NOT NULL THEN
            v_end := greatest(g.valid_from, least(coalesce(v_end, 'infinity'::date), v_start - 1));
        END IF;
        UPDATE iam.office_assignment a SET scope_id = v_right, valid_to = v_end WHERE a.id = g.id;
        n_regrant := n_regrant + 1;
    END LOOP;

    SELECT count(*) FILTER (WHERE s.entry_mode = 'CCE'), count(*) FILTER (WHERE s.entry_mode = 'POSTGRADUATE' OR p.category <> 'UNDER GRADUATE')
      INTO n_cce, n_pg
      FROM registration.course_registration cr JOIN people.student s ON s.id = cr.student_id JOIN ref.programme p ON p.code = s.programme_code
     WHERE registration.is_summer(cr.session, cr.semester) AND NOT registration.is_summer_for(cr.student_id, cr.session, cr.semester);
    RAISE NOTICE 'V756: % CCE and % postgraduate semester-3 registrations in a session with a Summer now read as their own third semester; % course-scoped grants V754 moved by code followed again from the date each began; listed now: % reallocations at the old count, % Summer authorisations to look at again',
        n_cce, n_pg, n_regrant, (SELECT count(*) FROM finance.reallocations_at_old_level()),
        (SELECT count(DISTINCT (x.session, x.student_id)) FROM registration.summer_authorisations_to_review(NULL) x);
END $$;

COMMIT;

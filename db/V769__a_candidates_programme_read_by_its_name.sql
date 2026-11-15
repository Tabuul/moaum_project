-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V769 · A candidate's programme read by its name
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The Academic Office's report of 15 November 2026 ("why is offered and accepted columns not counting"): on Admissions, the
--  cycle's cards counted the session's offers and acceptances, while the "Programmes — merit lists" table showed OFFERED 0 and
--  ACCEPTED 0 on every programme. admissions.candidate.programme holds the programme's NAME as JAMB's list gives it (B.Sc. COMPUTER
--  SCIENCE, LL.B (LAW)) — the applicant's registration, the applicant import, a change of programme and an admission correction
--  all write the name (registration writes JAMB's code only for a code no programme here carries) — not its code; the table grouped
--  the candidates by that name and joined it to the programme's code, so nothing ever matched (on the live-shaped copy, 6,232
--  offers and 10 acceptances for 2026/2027, every candidate's programme a name). The same reading was wrong in three database
--  functions and two more screens:
--    · people.programme_mismatches (V578, V669): "admitted to another programme" compared the name with the code held, so every
--      live student with a candidate (6,234 on the copy) was listed as a POSSIBLE mismatch on that alone (9,056 POSSIBLE; 2,822
--      read rightly), and the admitted programme was never named;
--    · people.programme_history (V578, V669): the original admission's row carried the name as its programme code, so its programme,
--      department and faculty were blank;
--    · people.university_transfer_lookup (V763): the applicant under a JAMB number was shown without a programme name;
--    · and in the API (not here): the full record's "Original admission programme" (V578) never showed, and the programme swap
--      page's signal "Admitted to …" (V578) was given the name as a code, so it named every student with a candidate.
--
--  One reading for all of them: admissions.candidate_programme_code(text, held) — the text itself when it is a programme's code (a
--  record written before the name was the rule, and the test fixtures), the programme held when that programme carries the name (a
--  name several programmes share, as some postgraduate names do, is not read as another of them), else the programme of that name
--  (admissions.programme_code_of, the house rule: the live one first, then the lowest code). A name no programme carries reads as
--  nothing, and is not judged. The merit table's offers and acceptances by programme are one function the Admissions page and the
--  check both read, admissions.offers_by_programme(session): the candidates counted once for each programme name, each name read
--  once, summed by code — the preliminary and proficiency candidates left out, as the cards leave them out (V737).
--
--  people.intake_one already reads the name first and a code after it, and is left as it is.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V769: a candidate''s programme read by its name', true);

-- ── the programme a candidate's programme text names ────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.candidate_programme_code(p_programme text, p_held text DEFAULT NULL)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p.code FROM ref.programme p WHERE p.code = p_programme),
                    (SELECT p.code FROM ref.programme p WHERE p.code = p_held AND p.name = p_programme),
                    admissions.programme_code_of(p_programme))
$$;
COMMENT ON FUNCTION admissions.candidate_programme_code(text, text) IS
  'V769: the code of the programme a candidate''s programme names (admissions.candidate.programme holds the NAME JAMB''s list gives): the text itself when it is a programme''s code; the programme held (p_held, a student''s programme code) when that programme carries the name; else the programme of that name (admissions.programme_code_of). NULL for a name no programme carries.';

-- ── the merit table's offers and acceptances, by programme ──────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.offers_by_programme(p_session text)
RETURNS TABLE (code text, offered bigint, accepted bigint)
LANGUAGE sql STABLE AS $$
    SELECT m.code, sum(n.offered)::bigint, sum(n.accepted)::bigint
      FROM (SELECT c.programme, count(*) FILTER (WHERE c.offer_state IN ('ADMITTED', 'ACCEPTED')) AS offered,
                   count(*) FILTER (WHERE c.offer_state = 'ACCEPTED') AS accepted
              FROM admissions.candidate c
             WHERE c.session = p_session AND c.entry_mode NOT IN ('PRELIMINARY', 'PROFICIENCY')
             GROUP BY c.programme) n
     CROSS JOIN LATERAL (SELECT admissions.candidate_programme_code(n.programme) AS code) m
     WHERE m.code IS NOT NULL
     GROUP BY m.code
$$;
COMMENT ON FUNCTION admissions.offers_by_programme(text) IS
  'V769: a session''s offers (ADMITTED or ACCEPTED) and acceptances by programme code, as the Admissions page''s "Programmes — merit lists" table reads them: the candidates counted once for each programme name, each name read once as its code (admissions.candidate_programme_code), summed by code. The preliminary and proficiency candidates are left out, as the cycle''s cards leave them out (V737); a name no programme carries is counted on no programme.';

-- ── V669's programme history, restated: the original admission's programme read as its code ──
CREATE OR REPLACE FUNCTION people.programme_history(p_student uuid)
 RETURNS TABLE(at timestamp with time zone, session text, source text, kind text, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, level integer, from_programme text, from_level integer, reference text, detail text, by_whom text, current boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH st AS (SELECT s.* FROM people.student s WHERE s.id = p_student),
    moves AS (
        SELECT t.effected_at, t.session, 'TRANSFER', 'TRANSFER_EFFECTED', t.to_programme_code, t.from_programme_code, t.from_level,
               NULL, 'Inter-departmental transfer effected', helpdesk.person_name(t.effected_by)
          FROM people.transfer_application t WHERE t.student_id = p_student AND t.state = 'EFFECTED' AND t.effected_at IS NOT NULL
        UNION ALL
        SELECT m.moved_at, NULL, 'RECORD_MOVE', 'RECORD_MOVED', m.to_programme, m.from_programme, m.from_level, NULL,
               'Record moved to a postgraduate programme: ' || m.reason, helpdesk.person_name(m.moved_by)
          FROM people.record_move m WHERE m.student_id = p_student
        UNION ALL
        SELECT x.executed_at, x.effective_session, 'SWAP', 'PROGRAMME_SWAP_' || x.kind, x.to_programme, x.from_programme, x.from_level, x.swap_ref,
               x.reason, helpdesk.person_name(x.decided_by)
          FROM people.programme_swap x WHERE x.student_id = p_student AND x.status = 'COMPLETED'
        UNION ALL
        -- V669: a transfer approved on the old portal, dated when it was approved (else when its session began); its restoration here is
        -- the programme swap after it
        SELECT coalesce(pt.approved_on::timestamptz, (SELECT a.starts_on::timestamptz FROM policy.academic_session a WHERE a.name = pt.effective_session), pt.recorded_at),
               pt.effective_session, 'OLD_PORTAL', 'TRANSFER_APPROVED_OLD_PORTAL', pt.to_programme, pt.from_programme, pt.from_level, pt.reference,
               'Inter-departmental transfer approved on the old portal' || CASE WHEN pt.approved_on IS NOT NULL THEN ' on ' || to_char(pt.approved_on, 'DD Mon YYYY') ELSE '' END
               || CASE WHEN pt.effective_semester IS NOT NULL THEN ', effective ' || CASE pt.effective_semester WHEN 1 THEN 'first' ELSE 'second' END || ' semester' ELSE '' END,
               coalesce(people.officer_name(pt.recorded_by), 'The ' || initcap(pt.recorded_office) || ' office')
          FROM people.prior_transfer pt WHERE pt.student_id = p_student
        UNION ALL
        -- any other change of programme the audit chain holds (an upload, a merge, a correction by hand)
        SELECT e.occurred_at, NULL, 'RECORD', 'PROGRAMME_CHANGED', e.after_state->>'programme_code', e.before_state->>'programme_code',
               nullif(e.before_state->>'current_level', '')::int, NULL, coalesce(e.reason, 'Programme changed on the record'),
               CASE WHEN e.actor_office = 'student' THEN 'The student' WHEN e.actor_id IS NULL THEN 'The system' ELSE helpdesk.person_name(e.actor_id) END
          FROM audit.entries e
         WHERE e.subject_type = 'people.student' AND e.subject_id = p_student AND e.action = 'UPDATE'
           AND e.before_state->>'programme_code' IS DISTINCT FROM e.after_state->>'programme_code'
           AND NOT EXISTS (SELECT 1 FROM people.programme_swap x WHERE x.student_id = p_student AND x.status = 'COMPLETED' AND x.executed_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')
           AND NOT EXISTS (SELECT 1 FROM people.transfer_application t WHERE t.student_id = p_student AND t.effected_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')
           AND NOT EXISTS (SELECT 1 FROM people.record_move m WHERE m.student_id = p_student AND m.moved_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')),
    rows AS (
        -- the admission: the candidate's programme where the record is linked to one; else the programme the record held before its
        -- first recorded move; else the programme it holds (a record never moved). V769: the candidate's programme is the NAME JAMB's
        -- list gave, read as the programme's code (admissions.candidate_programme_code); a name no programme carries is kept as written
        SELECT coalesce(a.starts_on::timestamptz, st.matriculated_at, '1900-01-01'::timestamptz) AS at, st.entry_session, 'ADMISSION', 'ORIGINAL_ADMISSION',
               coalesce(admissions.candidate_programme_code(c.programme, st.programme_code), c.programme, (SELECT m.from_programme FROM moves m(at, s, src, k, prog, from_programme, fl, rf, d, b) WHERE m.from_programme IS NOT NULL ORDER BY m.at NULLS LAST LIMIT 1),
                        st.programme_code),
               NULL::text, NULL::integer, NULL::text, 'Original admission programme', NULL::text
          FROM st LEFT JOIN admissions.candidate c ON c.id = st.candidate_id LEFT JOIN policy.academic_session a ON a.name = st.entry_session
        UNION ALL
        SELECT * FROM moves)
    SELECT r.at, r.entry_session, r.source, r.kind, r.programme_code, p.name, p.dept_code, d.name, p.faculty_code, f.name, r.from_level, r.from_programme, r.from_level,
           r.reference, r.detail, r.by_whom,
           -- the current placement: the latest move, or the admission where the record was never moved
           CASE WHEN r.kind = 'ORIGINAL_ADMISSION' THEN NOT EXISTS (SELECT 1 FROM moves)
                ELSE r.at = (SELECT max(m.at) FROM moves m(at)) AND r.programme_code = (SELECT programme_code FROM st) END
      FROM rows r(at, entry_session, source, kind, programme_code, from_programme, from_level, reference, detail, by_whom)
      LEFT JOIN ref.programme p ON p.code = r.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     ORDER BY (r.kind = 'ORIGINAL_ADMISSION') DESC, r.at NULLS FIRST
$function$;

-- ── V669's mismatch list, restated: the admitted programme read as its code, compared with the code held ──
CREATE OR REPLACE FUNCTION people.programme_mismatches(p_fac text, p_dept text, p_prog text)
 RETURNS TABLE(student_id uuid, surname text, other_names text, matric_no text, jamb_reg_no text, status text, entry_mode text, entry_session text, current_level integer, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, matric_segment text, programme_segment text, registration_dept text, registration_dept_name text, registration_share numeric, admitted_programme text, admitted_programme_name text, classification text, suggested_dept text, suggested_programme text, suggested_programme_name text, review_status text, review_note text, reviewed_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    WITH st AS MATERIALIZED (
        SELECT s.id, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.status, s.entry_mode, s.entry_session, s.current_level, s.programme_code,
               s.candidate_id, p.name AS programme, p.dept_code, p.faculty_code, p.matric_code, p.category,
               CASE WHEN s.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/' THEN split_part(s.matric_no, '/', 3) END AS seg
          FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT')
           AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)),
    -- V669: a placement this portal recorded — an effected transfer, a completed programme swap, a transfer approved on the old portal —
    -- to the programme the student holds: since when (the registrations before it are of the programme left)
    moved AS MATERIALIZED (
        SELECT m.student_id, max(m.since) AS since FROM (
            SELECT t.student_id, t.session AS since FROM people.transfer_application t JOIN st ON st.id = t.student_id AND t.to_programme_code = st.programme_code
             WHERE t.state = 'EFFECTED'
            UNION ALL
            SELECT x.student_id, x.effective_session FROM people.programme_swap x JOIN st ON st.id = x.student_id AND x.to_programme = st.programme_code
             WHERE x.status = 'COMPLETED'
            UNION ALL
            SELECT pt.student_id, pt.effective_session FROM people.prior_transfer pt JOIN st ON st.id = pt.student_id AND pt.to_programme = st.programme_code) m
         GROUP BY m.student_id),
    -- the segment most of a programme's students carry: read over the whole register, so a filtered view judges by the same measure
    observed AS MATERIALIZED (
        SELECT programme_code, seg FROM (
            SELECT s.programme_code, split_part(s.matric_no, '/', 3) AS seg, count(*) AS n,
                   row_number() OVER (PARTITION BY s.programme_code ORDER BY count(*) DESC, split_part(s.matric_no, '/', 3)) AS rn
              FROM people.student s WHERE s.status IN ('ACTIVE', 'PROBATION', 'ADMITTED') AND s.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/'
             GROUP BY 1, 2) o WHERE rn = 1 AND n >= 3),
    seg_dept AS MATERIALIZED (   -- which department a segment names: the programme carrying it, by its own code or by its students
        SELECT seg, dept_code FROM (
            SELECT coalesce(p.matric_code, o.seg) AS seg, p.dept_code, row_number() OVER (PARTITION BY coalesce(p.matric_code, o.seg) ORDER BY (p.matric_code IS NOT NULL) DESC, p.code) rn
              FROM ref.programme p LEFT JOIN observed o ON o.programme_code = p.code WHERE coalesce(p.matric_code, o.seg) IS NOT NULL AND p.dept_code IS NOT NULL) q WHERE rn = 1),
    latest AS MATERIALIZED (
        SELECT DISTINCT ON (r.student_id) r.student_id, r.id FROM registration.course_registration r JOIN st ON st.id = r.student_id
          LEFT JOIN moved mv ON mv.student_id = r.student_id
         WHERE r.status IN ('APPROVED', 'LOCKED') AND (mv.since IS NULL OR r.session >= mv.since) ORDER BY r.student_id, r.session DESC, r.semester DESC),
    regdept AS MATERIALIZED (
        SELECT student_id, dept_code, share FROM (
            SELECT l.student_id, c.dept_code, count(*)::numeric / sum(count(*)) OVER (PARTITION BY l.student_id) AS share,
                   row_number() OVER (PARTITION BY l.student_id ORDER BY count(*) DESC, c.dept_code) AS rn
              FROM latest l JOIN registration.entry e ON e.registration_id = l.id AND e.status IN ('REGISTERED', 'APPROVED')
              JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
             WHERE c.kind NOT IN ('GST', 'EPS') AND c.dept_code IS NOT NULL
             GROUP BY 1, 2) q WHERE rn = 1),
    -- V769: the programme each admission names, read once for each programme text and programme held (a candidate's programme is the
    -- NAME JAMB's list gave, never its code: compared with the code held it differed for every student with a candidate)
    admitted AS MATERIALIZED (
        SELECT n.programme, n.held, admissions.candidate_programme_code(n.programme, n.held) AS code
          FROM (SELECT DISTINCT c.programme, st.programme_code AS held FROM st JOIN admissions.candidate c ON c.id = st.candidate_id) n),
    judged AS (
        SELECT st.*, coalesce(st.matric_code, o.seg) AS programme_segment, sd.dept_code AS seg_dept, rd.dept_code AS reg_dept, rd.share,
               ad.code AS admitted_programme,
               -- V669: the number names the department a student was admitted to; after a recorded move it is not a sign of anything
               (mv.student_id IS NULL AND st.seg IS NOT NULL AND coalesce(st.matric_code, o.seg) IS NOT NULL AND st.seg <> coalesce(st.matric_code, o.seg) AND sd.dept_code IS NOT NULL AND sd.dept_code <> st.dept_code) AS by_matric,
               (rd.dept_code IS NOT NULL AND rd.dept_code <> st.dept_code AND rd.share >= 0.5) AS by_registration,
               -- admitted to another programme: one the admission's name reads as (a name no programme carries is not judged)
               (mv.student_id IS NULL AND ad.code IS NOT NULL AND ad.code <> st.programme_code) AS by_admission
          FROM st
          LEFT JOIN observed o ON o.programme_code = st.programme_code
          LEFT JOIN seg_dept sd ON sd.seg = st.seg
          LEFT JOIN regdept rd ON rd.student_id = st.id
          LEFT JOIN admissions.candidate c ON c.id = st.candidate_id
          LEFT JOIN admitted ad ON ad.programme = c.programme AND ad.held = st.programme_code
          LEFT JOIN moved mv ON mv.student_id = st.id),
    classed AS (
        SELECT j.*,
               CASE WHEN j.by_matric AND j.by_registration AND j.seg_dept = j.reg_dept THEN 'CONFIRMED'
                    WHEN j.by_matric AND j.by_registration THEN 'REQUIRES_REVIEW'
                    WHEN j.by_matric OR j.by_registration OR j.by_admission THEN 'POSSIBLE'
                    ELSE 'NO_MISMATCH' END AS classification,
               CASE WHEN j.by_matric AND j.by_registration AND j.seg_dept = j.reg_dept THEN j.seg_dept
                    -- V669: the matriculation number alone never suggests a department (a student transferred keeps the number of the one left)
                    WHEN j.by_registration THEN j.reg_dept END AS suggested_dept
          FROM judged j),
    -- the programme suggested for a department: the one of the student's own category most of its students sit on (read once)
    suggested AS MATERIALIZED (
        SELECT DISTINCT ON (p.dept_code, p.category) p.dept_code, p.category, p.code, p.name
          FROM ref.programme p
          LEFT JOIN (SELECT s2.programme_code, count(*) AS n FROM people.student s2 WHERE s2.status IN ('ACTIVE', 'PROBATION') GROUP BY 1) pop ON pop.programme_code = p.code
         WHERE NOT p.archived AND p.dept_code IS NOT NULL
         ORDER BY p.dept_code, p.category, coalesce(pop.n, 0) DESC, p.code)
    SELECT c.id, c.surname, c.other_names, c.matric_no, c.jamb_reg_no, c.status, c.entry_mode, c.entry_session, c.current_level, c.programme_code, c.programme,
           c.dept_code, d.name, c.faculty_code, f.name, c.seg, c.programme_segment, c.reg_dept, rdn.name, round(c.share, 2), c.admitted_programme, ap.name,
           c.classification, c.suggested_dept, sp.code, sp.name,
           coalesce(rv.status, 'NOT_REVIEWED'), rv.note, rv.reviewed_at
      FROM classed c
      LEFT JOIN ref.department d ON d.code = c.dept_code
      LEFT JOIN ref.faculty f ON f.code = c.faculty_code
      LEFT JOIN ref.department rdn ON rdn.code = c.reg_dept
      LEFT JOIN ref.programme ap ON ap.code = c.admitted_programme
      LEFT JOIN suggested sp ON sp.dept_code = c.suggested_dept AND sp.category = c.category
      LEFT JOIN people.programme_mismatch_review rv ON rv.student_id = c.id
     WHERE c.classification <> 'NO_MISMATCH' OR rv.student_id IS NOT NULL
$function$;

-- ── V763's transfer lookup, restated: the applicant's programme read as its code, named ──
CREATE OR REPLACE FUNCTION people.university_transfer_lookup(p_number text, p_direction text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_no text := upper(regexp_replace(coalesce(p_number, ''), '\s+', '', 'g')); s record; k record; v_by text; v_pending text;
        v_dir text := upper(btrim(coalesce(p_direction, '')));
        v_live CONSTANT text[] := ARRAY['ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT'];
BEGIN
    -- as the check finds a student for the direction: going out (or unsaid), the matriculation number, a former one, then the JAMB
    -- number directly or through the applicant; coming in, the JAMB number alone — the form's incoming row carries no other, and a
    -- student found here by another number would be one the check never finds
    SELECT x.id, x.surname, x.other_names, x.sex, x.date_of_birth, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code,
           p.name AS programme_name, p.dept_code, p.faculty_code INTO s
      FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
     WHERE x.duplicate_of IS NULL AND length(v_no) >= 4 AND v_dir <> 'INCOMING' AND upper(x.matric_no) = v_no;
    IF s.id IS NOT NULL THEN v_by := 'MATRIC'; END IF;
    IF s.id IS NULL AND length(v_no) >= 4 AND v_dir <> 'INCOMING' THEN
        SELECT x.id, x.surname, x.other_names, x.sex, x.date_of_birth, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code,
               p.name AS programme_name, p.dept_code, p.faculty_code INTO s
          FROM people.matric_alias a JOIN people.student x ON x.id = a.student_id LEFT JOIN ref.programme p ON p.code = x.programme_code
         WHERE upper(a.old_no) = v_no AND a.ended_at IS NULL;
        IF s.id IS NOT NULL THEN v_by := 'FORMER_MATRIC'; END IF;
    END IF;
    IF s.id IS NULL AND length(v_no) >= 4 THEN
        SELECT x.id, x.surname, x.other_names, x.sex, x.date_of_birth, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code,
               p.name AS programme_name, p.dept_code, p.faculty_code INTO s
          FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
         WHERE x.duplicate_of IS NULL
           AND (upper(btrim(x.jamb_reg_no)) = v_no OR x.candidate_id IN (SELECT c.id FROM admissions.candidate c WHERE upper(c.jamb_reg_no) = v_no))
         ORDER BY (x.status = ANY (v_live)) DESC, x.matriculated_at DESC NULLS LAST LIMIT 1;
        IF s.id IS NOT NULL THEN v_by := 'JAMB'; END IF;
    END IF;
    -- the applicant under a JAMB number: a student coming in is linked to the application (going out, only a student is transferred).
    -- V769: the candidate's programme is the NAME JAMB's list gave: the code it reads as, and the programme's name (as written where no
    -- programme carries it)
    SELECT c.id, c.session, c.surname, c.other_names, c.sex, coalesce(p.code, c.programme) AS programme, c.offer_state,
           coalesce(p.name, c.programme) AS programme_name INTO k
      FROM admissions.candidate c LEFT JOIN ref.programme p ON p.code = admissions.candidate_programme_code(c.programme)
     WHERE length(v_no) >= 4 AND v_dir <> 'OUTGOING' AND upper(c.jamb_reg_no) = v_no ORDER BY c.session DESC LIMIT 1;
    v_pending := (SELECT b.ref FROM people.university_transfer t JOIN people.university_transfer_batch b ON b.id = t.batch_id
                   WHERE t.status = 'PENDING_APPROVAL' AND ((s.id IS NOT NULL AND t.student_id = s.id) OR (length(v_no) >= 4 AND upper(t.jamb_reg_no) = v_no))
                   ORDER BY t.prepared_at DESC LIMIT 1);
    RETURN jsonb_build_object('number', v_no, 'direction', nullif(v_dir, ''), 'matchedBy', v_by,
        'student', CASE WHEN s.id IS NOT NULL THEN jsonb_build_object('id', s.id, 'name', s.surname || ', ' || s.other_names, 'surname', s.surname,
            'otherNames', s.other_names, 'sex', s.sex, 'dateOfBirth', s.date_of_birth, 'matricNo', s.matric_no, 'jambRegNo', s.jamb_reg_no, 'status', s.status,
            'live', s.status = ANY (v_live), 'faculty', s.faculty_code, 'dept', s.dept_code, 'programme', s.programme_code, 'programmeName', s.programme_name,
            'level', s.current_level) END,
        'applicant', CASE WHEN k.id IS NOT NULL THEN jsonb_build_object('id', k.id, 'session', k.session, 'surname', k.surname, 'otherNames', k.other_names,
            'sex', k.sex, 'programme', k.programme, 'programmeName', k.programme_name, 'offerState', k.offer_state) END,
        'pendingRef', v_pending);
END $function$;

-- ── the descriptions of the three restated, extended ──
DO $$
DECLARE f text; c text; i int;
    fs CONSTANT text[] := ARRAY['people.programme_history(uuid)', 'people.programme_mismatches(text,text,text)', 'people.university_transfer_lookup(text,text)'];
    notes CONSTANT text[] := ARRAY[
        ' V769: the original admission''s programme is the code the candidate''s programme name reads as (admissions.candidate_programme_code), a name no programme carries kept as written.',
        ' V769: the admitted programme is the code the candidate''s programme name reads as (admissions.candidate_programme_code), compared with the code held; a name no programme carries is not judged.',
        ' V769: the applicant''s programme is the code their programme name reads as (admissions.candidate_programme_code), with the programme''s name.'];
BEGIN
    FOR i IN 1 .. array_length(fs, 1) LOOP
        f := fs[i];
        c := obj_description(f::regprocedure, 'pg_proc');
        IF c IS NULL THEN RAISE EXCEPTION 'V769: % has no description to extend', f; END IF;
        EXECUTE format('COMMENT ON FUNCTION %s IS %L', f, c || notes[i]);
    END LOOP;
END $$;

COMMIT;

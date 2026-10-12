-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V399 — applicants told of another faculty's programme before V397, put right; a change of programme stays in the faculty
--
--   V397 made the engine suggest only programmes of the faculty the candidate applied to. Before it, the reconsiderations
--   emailed some refused candidates another faculty's programmes (admissions.suggestion_sent keeps the last list each was
--   sent), and a candidate may already have asked to move to one. Two things follow:
--
--   1  A change of programme stays in the faculty applied to. The applicant's request (admissions.request_programme_change)
--      and the office's recommendation (recommend_programme_change) are refused for another faculty's programme
--      (PROGRAMME_CHANGE_OTHER_FACULTY); the office may still recommend one under the Registrar's override, with its reason,
--      as for a programme the engine refuses (V284), and the request then carries the override. A request made before V397
--      for another faculty's programme is not approved (decide_programme_change); the office rejects it, with its reason,
--      and the applicant is told as for any rejection. An admission correction (V297) is decided on its own terms, untouched.
--   2  The Admissions Office sees who was told (admissions.cross_faculty_told): each applicant whose last suggestion named a
--      programme outside their faculty, with what they were told and when, the programmes of their own faculty the engine
--      suggests now, and any request still open for another faculty's programme. admissions.correct_suggestion sends one
--      the corrected list — what was named is in another faculty; the programmes of their faculty they may be considered
--      for, or none at present — records it (admissions.suggestion_correction) and makes it the last list sent; once
--      corrected, the applicant leaves the list unless a request for another faculty's programme is still open.
--   Nothing told is deleted: the notices stay on the queue and the correction keeps what was named.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V399: applicants told of another faculty''s programme put right; a change of programme stays in the faculty', true);

-- ── whether two programmes are of one faculty (both on the register, one faculty_code) ──
CREATE OR REPLACE FUNCTION admissions.same_faculty(p_a text, p_b text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT pa.faculty_code = pb.faculty_code FROM ref.programme pa, ref.programme pb WHERE pa.code = p_a AND pb.code = p_b), false)
$fn$;
COMMENT ON FUNCTION admissions.same_faculty(text, text) IS
  'True when both programmes are on the register in one faculty (V399): the test a suggestion (V397) and a change of programme are held to.';

CREATE OR REPLACE FUNCTION admissions.request_programme_change(p_app uuid, p_to text, p_note text, p_by_kind text, p_by uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; c admissions.candidate; g ref.programme; r record; v_run uuid; v_id uuid; v_from text;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    -- after the Board's decision a change is possible only where the online screening was unsuccessful (V269): the screening committee's path, once
    IF a.decision_released_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = p_app AND f.state = 'UNSUCCESSFUL') THEN
        RAISE EXCEPTION 'the Board''s decision on this application has been released; a change of programme is a new decision of the Board' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.screening_form f JOIN admissions.programme_change_request q0 ON q0.application_id = f.application_id
                WHERE f.application_id = p_app AND f.state = 'UNSUCCESSFUL' AND q0.state = 'APPROVED' AND q0.decided_at >= f.decided_at) THEN
        RAISE EXCEPTION 'a change of programme has already been approved after the screening' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO g FROM ref.programme WHERE code = p_to;
    IF g.code IS NULL OR g.archived THEN RAISE EXCEPTION 'no such active programme %', p_to USING ERRCODE = '23514'; END IF;
    v_from := admissions.programme_code_of(c.programme);
    IF v_from = p_to THEN RAISE EXCEPTION 'that is the programme applied for' USING ERRCODE = '23514'; END IF;
    -- V399: a change is to a programme of the faculty applied to, as the suggestions are (V397)
    IF NOT admissions.same_faculty(v_from, p_to) THEN
        RAISE EXCEPTION 'PROGRAMME_CHANGE_OTHER_FACULTY: % is not in the faculty of %; a change of programme is to a programme of the same faculty', g.name, c.programme
              USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a change of programme is already requested and awaits the Admissions Office' USING ERRCODE = '23514';
    END IF;
    -- read again now, never from a stale screen
    v_run := admissions.eligibility_current(p_app, p_by);
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, p_to, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        RAISE EXCEPTION 'the candidate is not eligible for %: %', g.name, array_to_string(r.reasons, '; ') USING ERRCODE = '23514',
              HINT = 'A programme is requested only when every mandatory requirement is met on the current admission policy.';
    END IF;
    INSERT INTO admissions.programme_change_request (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme, run_id, eligibility_at_request, requested_by_kind, requested_by, note)
    VALUES (p_app, c.id, a.session, v_from, c.programme, p_to, g.name, v_run, r.result, p_by_kind, p_by, nullif(btrim(coalesce(p_note, '')), ''))
    RETURNING id INTO v_id;
    PERFORM admissions.eligibility_log(p_app, v_run, 'PROGRAMME_CHANGE_REQUESTED', p_to, r.result, 'From ' || c.programme || ' to ' || g.name || coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    PERFORM admissions.notify_applicant(p_app, 'Your request to change programme has been received',
        'Your request to be considered for ' || g.name || ' in place of ' || c.programme || ' has been received and is with the Admissions Office. Your programme changes only when the Office approves; you will be told.',
        'MOAUM: your request to change to ' || g.name || ' is with the Admissions Office.');
    PERFORM admissions.tell_office('academic', 'A programme change request awaits the Admissions Office',
        'Applicant ' || c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || ') asks to move from ' || c.programme || ' to ' || g.name || '; the engine finds them ' || lower(replace(r.result, '_', ' ')) || '. Open Programme eligibility on the admissions desk to decide.', p_app);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION admissions.recommend_programme_change(p_app uuid, p_to text, p_reason text, p_note text, p_actor uuid, p_office text, p_override boolean, p_override_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; c admissions.candidate; g ref.programme; rs admissions.programme_change_reason; f admissions.screening_form; r record;
        v_run uuid; v_id uuid; v_from text; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO rs FROM admissions.programme_change_reason WHERE code = p_reason AND active;
    IF rs.code IS NULL THEN RAISE EXCEPTION 'a change of programme carries one of the configured reasons' USING ERRCODE = '23514'; END IF;
    IF rs.requires_note AND v_note IS NULL THEN RAISE EXCEPTION 'the reason "%" is described in a note', rs.label USING ERRCODE = '23514'; END IF;
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    -- after the Board's decision the change is a screening act: while the screening is open, or after an unsuccessful one, once
    IF a.decision_released_at IS NOT NULL AND (f.application_id IS NULL OR f.state NOT IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
        RAISE EXCEPTION 'the Board''s decision on this application has been released; the programme is changed only during the University''s screening'
            USING ERRCODE = '23514', HINT = 'Correct an error in the admission on Programme Changes.';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q0 WHERE q0.application_id = p_app AND q0.state = 'APPROVED' AND f.decided_at IS NOT NULL AND q0.decided_at >= f.decided_at) THEN
        RAISE EXCEPTION 'a change of programme has already been approved after the screening' USING ERRCODE = '23514',
              HINT = 'An error found in the admission since is corrected on Programme Changes.';
    END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO g FROM ref.programme WHERE code = p_to;
    IF g.code IS NULL OR g.archived THEN RAISE EXCEPTION 'no such active programme %', p_to USING ERRCODE = '23514'; END IF;
    v_from := admissions.programme_code_of(c.programme);
    IF v_from = p_to THEN RAISE EXCEPTION 'that is the programme the candidate holds' USING ERRCODE = '23514'; END IF;
    -- V399: another faculty's programme is never recommended on the engine's word (V397); only the Registrar's override, with its reason
    IF NOT admissions.same_faculty(v_from, p_to) THEN
        IF NOT coalesce(p_override, false) THEN
            RAISE EXCEPTION 'PROGRAMME_CHANGE_OTHER_FACULTY: % is not in the faculty of %; a change of programme is to a programme of the same faculty', g.name, c.programme
                  USING ERRCODE = '23514', HINT = 'Another faculty''s programme is the Registrar''s override, with its reason.';
        END IF;
        IF nullif(btrim(coalesce(p_override_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an override carries its reason' USING ERRCODE = '23514'; END IF;
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a change of programme is already recommended and awaits approval' USING ERRCODE = '23514';
    END IF;
    -- the engine, read again now against the session's settings, never from a stale screen
    v_run := admissions.eligibility_current(p_app, p_actor);
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, p_to, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        IF NOT coalesce(p_override, false) THEN
            RAISE EXCEPTION 'the candidate is not eligible for %: %', g.name, array_to_string(r.reasons, '; ') USING ERRCODE = '23514',
                  HINT = 'Recommend a programme the candidate is eligible for; an override is reserved to the Registrar.';
        END IF;
        IF nullif(btrim(coalesce(p_override_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an eligibility override carries its reason' USING ERRCODE = '23514'; END IF;
    END IF;
    INSERT INTO admissions.programme_change_request (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme, run_id, eligibility_at_request,
                                                     requested_by_kind, requested_by, note, reason_code, recommended_office, override, override_reason, original_eligibility, screening_state_at_request)
    VALUES (p_app, c.id, a.session, v_from, c.programme, p_to, g.name, v_run, r.result, 'OFFICE', p_actor, v_note, rs.code, p_office,
            r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') OR NOT admissions.same_faculty(v_from, p_to), nullif(btrim(coalesce(p_override_reason, '')), ''), r.result, f.state)
    RETURNING id INTO v_id;
    PERFORM admissions.eligibility_log(p_app, v_run, 'PROGRAMME_CHANGE_RECOMMENDED', p_to, r.result,
        'From ' || c.programme || ' to ' || g.name || ' Â· ' || rs.label || coalesce(' Â· ' || v_note, '') || ' Â· by the ' || coalesce(p_office, 'office')
        || CASE WHEN r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN ' Â· OVERRIDE: ' || coalesce(p_override_reason, '') ELSE '' END);
    IF f.application_id IS NOT NULL THEN
        PERFORM admissions.screening_log(p_app, 'PROGRAMME_CHANGE_RECOMMENDED', 'From ' || c.programme || ' to ' || g.name || ' Â· ' || rs.label || ' Â· awaiting approval');
    END IF;
    PERFORM admissions.notify_applicant(p_app, 'Your programme change is under review',
        'During the University''s screening the Academic Office has recommended that your admission be changed from ' || c.programme || ' to ' || g.name
        || ' (' || rs.label || '). The change takes effect only when it is approved; you will be told. Your acceptance fee, already paid, is not paid again.',
        'MOAUM: a change of your programme to ' || g.name || ' is under review; you will be told when it is decided.');
    PERFORM admissions.tell_office('academic', 'A programme change awaits approval',
        'Applicant ' || c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || '): the ' || coalesce(p_office, 'office') || ' recommends ' || g.name || ' in place of ' || c.programme
        || ' Â· ' || rs.label || ' Â· the engine finds them ' || lower(replace(r.result, '_', ' ')) || CASE WHEN coalesce(p_override, false) THEN ' (override)' ELSE '' END, p_app);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION admissions.decide_programme_change(p_req uuid, p_decision text, p_note text, p_actor uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE q admissions.programme_change_request; a admissions.application; c admissions.candidate; r record; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_prog text; v_fac text; v_dept text;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO q FROM admissions.programme_change_request WHERE id = p_req FOR UPDATE;
    IF q.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF q.state <> 'REQUESTED' THEN RAISE EXCEPTION 'the request is already %', lower(q.state) USING ERRCODE = '23514'; END IF;
    -- an admission correction (V297) is decided on its own terms
    IF q.kind = 'CORRECTION' THEN RETURN admissions.decide_admission_correction(p_req, p_decision, p_note, p_actor); END IF;
    SELECT * INTO a FROM admissions.application WHERE id = q.application_id;
    SELECT * INTO c FROM admissions.candidate WHERE id = q.candidate_id;
    IF p_decision = 'REJECT' THEN
        IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.programme_change_request SET state = 'REJECTED', decided_at = now(), decided_by = p_actor, decided_office = v_office, decision_note = v_note WHERE id = q.id;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_REJECTED', q.to_programme_code, NULL, v_note);
        PERFORM admissions.notify_applicant(q.application_id, 'Your request to change programme was not approved', 'Your request to move to ' || q.to_programme || ' was not approved by the Admissions Office. Reason: ' || v_note || ' Your application for ' || q.from_programme || ' stands as it was.', NULL);
        RETURN 'REJECTED';
    ELSIF p_decision = 'APPROVE' THEN
        -- after the release a change is a screening decision (V269, V284): while the screening is open, or after an unsuccessful one
        IF a.decision_released_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
            RAISE EXCEPTION 'the Board''s decision has been released; the programme is not changed under it' USING ERRCODE = '23514',
                  HINT = 'An error found in a released admission is corrected on Programme Changes (an admission correction).';
        END IF;
        -- V399: a request made before V397 for another faculty's programme is not approved; it is rejected with its reason
        IF NOT q.override AND NOT admissions.same_faculty(q.from_programme_code, q.to_programme_code) THEN
            RAISE EXCEPTION 'PROGRAMME_CHANGE_OTHER_FACULTY: % is not in the faculty of %; reject the request with its reason', q.to_programme, q.from_programme
                  USING ERRCODE = '23514', HINT = 'Only programmes of the faculty applied to are offered as a change; another faculty''s is the Registrar''s override.';
        END IF;
        -- eligibility read again at the moment of decision
        SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, q.to_programme_code, c.entry_mode);
        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') AND NOT q.override THEN
            RAISE EXCEPTION 'on the current settings the candidate is no longer eligible for %: %', q.to_programme, array_to_string(r.reasons, '; ') USING ERRCODE = '23514';
        END IF;
        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
            -- the authorised override (V284): approved with the engine's verdict on the record, never hidden
            PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'ELIGIBILITY_OVERRIDE_APPLIED', q.to_programme_code, r.result, 'Approved by override: ' || coalesce(q.override_reason, '') || ' · engine: ' || array_to_string(r.reasons, '; '));
        END IF;
        UPDATE admissions.candidate SET programme = q.to_programme WHERE id = c.id;
        -- the student on the register, not yet matriculated, follows the programme (V269); the original stays on the request and the trail
        UPDATE people.student SET programme_code = q.to_programme_code WHERE candidate_id = c.id AND matric_no IS NULL;
        IF EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'UNSUCCESSFUL')) THEN
            -- the change is the screening's decision (V284): the record is screened successful on the new programme, the acceptance
            -- fee paid once stands, the forms are generated for the new programme, school fees open
            UPDATE admissions.screening_form
               SET state = 'SUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = 'academic', decision_reason = NULL, returned_note = NULL,
                   remarks = concat_ws(' · ', nullif(remarks, ''), 'Programme changed from ' || q.from_programme || ' to ' || q.to_programme || ' on the approval of the change request'
                             || coalesce(' (' || (SELECT rs.label FROM admissions.programme_change_reason rs WHERE rs.code = q.reason_code) || ')', '')),
                   updated_at = now()
             WHERE application_id = a.id;
            UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = a.id;
            PERFORM admissions.screening_log(a.id, 'PROGRAMME_CHANGED', 'From ' || q.from_programme || ' to ' || q.to_programme || ' on the approval of the change request; screened successful on the new programme; acceptance fee already paid, not charged again');
            SELECT p.name, f.name, d.name INTO v_prog, v_fac, v_dept FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = q.to_programme_code;
            PERFORM admissions.notify_applicant(a.id, 'Programme change approved — next step: school fees',
                'Your programme change has been approved.' || E'\n\nPrevious programme: ' || q.from_programme || E'\nNew programme: ' || coalesce(v_prog, q.to_programme)
                || coalesce(E'\nFaculty: ' || v_fac, '') || coalesce(E'\nDepartment: ' || v_dept, '')
                || E'\n\nYour screening is recorded as successful on the new programme and your screening forms are available on your dashboard. Your acceptance fee, already paid, remains valid and is not paid again. Next step: pay your school fees on the portal.',
                'MOAUM: your change to ' || q.to_programme || ' is approved. Acceptance fee not charged again; next, school fees.');
        END IF;
        UPDATE admissions.programme_change_request SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decided_office = v_office, decision_note = v_note, eligibility_at_decision = r.result WHERE id = q.id;
        -- an approved change after an unsuccessful screening opens school fees: the register follows it (V278)
        PERFORM admissions.register_when_due(a.id);
        IF EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'SUCCESSFUL' AND f.decided_at >= now() - interval '1 minute') THEN
            PERFORM admissions.issue_screening_forms(a.id);
        END IF;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_APPROVED', q.to_programme_code, r.result, 'From ' || q.from_programme || ' to ' || q.to_programme || coalesce(' · ' || v_note, ''));
        PERFORM admissions.evaluate_application(q.application_id, 'PROGRAMME_CHANGE', p_actor);
        PERFORM admissions.notify_applicant(q.application_id, 'Your programme has been changed to ' || q.to_programme,
            'The Admissions Office has approved your request: your application is now for ' || q.to_programme || ' (' || r.result || ' on the current admission policy). This is not an offer of admission; the Admissions Board decides in the normal way.' || coalesce(' Note: ' || v_note, ''),
            'MOAUM: your application is now for ' || q.to_programme || '. This is not yet an offer of admission.');
        RETURN 'APPROVED';
    ELSE
        RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';
    END IF;
END $function$;


-- ── the corrections sent: what was named, what the applicant was told instead ──
CREATE TABLE IF NOT EXISTS admissions.suggestion_correction (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application(id) ON DELETE CASCADE,
    told           text NOT NULL,
    told_at        timestamptz NULL,
    other_faculty  text[] NOT NULL,
    corrected_to   text NULL,
    sent_at        timestamptz NOT NULL DEFAULT now(),
    sent_by        uuid NULL
);
CREATE INDEX IF NOT EXISTS ix_suggestion_correction_app ON admissions.suggestion_correction (application_id, sent_at DESC);
COMMENT ON TABLE admissions.suggestion_correction IS
  'A corrected suggestion sent to an applicant told of another faculty''s programme before V397 (V399): the list they were told (told, told_at), the programmes of it outside their faculty, and the programmes of their faculty they were told instead (corrected_to; none at present when null).';
SELECT audit.attach('admissions.suggestion_correction')
 WHERE NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_admissions_suggestion_correction');

-- ── who was told of another faculty's programme, and who still asks for one ──
CREATE OR REPLACE FUNCTION admissions.cross_faculty_told(p_session text)
RETURNS TABLE(application_id uuid, application_no text, name text, jamb_reg_no text, email text, programme text, faculty text,
              told text, told_at timestamptz, told_other text[], suggested_now text[], corrected_at timestamptz,
              request_id uuid, request_to text, request_faculty text)
LANGUAGE sql STABLE AS $fn$
    WITH base AS (
        SELECT a.id AS app, a.application_no, c.surname || ', ' || c.other_names AS name, c.jamb_reg_no, aa.email,
               c.programme, pc.faculty_code AS fac, f.name AS faculty_name, ss.programmes AS told, ss.sent_at AS told_at
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.applicant_account aa ON aa.id = a.account_id
          LEFT JOIN ref.programme pc ON pc.code = admissions.programme_code_of(c.programme)
          LEFT JOIN ref.faculty f ON f.code = pc.faculty_code
          LEFT JOIN admissions.suggestion_sent ss ON ss.application_id = a.id
         WHERE a.session = p_session),
    told AS (
        -- each programme named in the last list sent, read by its name; one is another faculty's when no programme of that
        -- name is in the applicant's faculty. A candidate who has since moved programme is not asked about again.
        SELECT b.app, array_agg(btrim(t.nm) ORDER BY btrim(t.nm)) AS other
          FROM base b
         CROSS JOIN LATERAL unnest(string_to_array(b.told, ', ')) AS t(nm)
         WHERE b.told IS NOT NULL
           AND EXISTS (SELECT 1 FROM ref.programme p WHERE upper(btrim(p.name)) = upper(btrim(t.nm)))
           AND NOT EXISTS (SELECT 1 FROM ref.programme p WHERE upper(btrim(p.name)) = upper(btrim(t.nm)) AND p.faculty_code = b.fac)
           AND NOT EXISTS (SELECT 1 FROM admissions.programme_change_request q
                            WHERE q.application_id = b.app AND q.state = 'APPROVED' AND q.decided_at > b.told_at)
         GROUP BY b.app),
    req AS (
        SELECT DISTINCT ON (q.application_id) q.application_id AS app, q.id, q.to_programme, tf.name AS to_faculty
          FROM admissions.programme_change_request q
          LEFT JOIN ref.programme tp ON tp.code = q.to_programme_code
          LEFT JOIN ref.faculty tf ON tf.code = tp.faculty_code
         WHERE q.session = p_session AND q.state = 'REQUESTED' AND q.kind <> 'CORRECTION' AND NOT q.override
           AND NOT admissions.same_faculty(q.from_programme_code, q.to_programme_code)
         ORDER BY q.application_id, q.requested_at DESC)
    SELECT b.app, b.application_no, b.name, b.jamb_reg_no, b.email, b.programme, b.faculty_name,
           b.told, b.told_at, t.other,
           (SELECT array_agg(er.programme ORDER BY er.ord, er.programme)
              FROM admissions.eligibility_run r JOIN admissions.eligibility_result er ON er.run_id = r.id
             WHERE r.application_id = b.app AND r.superseded_at IS NULL AND er.suggested),
           (SELECT max(x.sent_at) FROM admissions.suggestion_correction x WHERE x.application_id = b.app),
           q.id, q.to_programme, q.to_faculty
      FROM base b
      LEFT JOIN told t ON t.app = b.app
      LEFT JOIN req q ON q.app = b.app
     WHERE t.other IS NOT NULL OR q.id IS NOT NULL
     ORDER BY b.programme, b.name
$fn$;
COMMENT ON FUNCTION admissions.cross_faculty_told(text) IS
  'The applicants of a session told of another faculty''s programme before V397, or still asking for one (V399): what they were told and when, the programmes of their faculty suggested now, the last correction sent, and the request still open.';

-- ── the corrected list, sent to one applicant ──
CREATE OR REPLACE FUNCTION admissions.correct_suggestion(p_app uuid, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE x record; v_session text; v_now text; v_body text;
BEGIN
    SELECT a.session INTO v_session FROM admissions.application a WHERE a.id = p_app;
    IF v_session IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO x FROM admissions.cross_faculty_told(v_session) t WHERE t.application_id = p_app;
    IF x.application_id IS NULL OR x.told_other IS NULL THEN RETURN 'NOTHING_TO_CORRECT'; END IF;
    v_now := nullif(array_to_string(x.suggested_now, ', '), '');
    v_body := 'On ' || to_char(x.told_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY') || ' you were told you might be considered for '
              || array_to_string(x.told_other, ', ') || '. '
              || CASE WHEN cardinality(x.told_other) = 1 THEN 'That programme is' ELSE 'Those programmes are' END
              || ' in another faculty; the University suggests only programmes of the faculty you applied to'
              || coalesce(' (' || x.faculty || ')', '') || '. '
              || CASE WHEN v_now IS NULL THEN 'No other programme of your faculty is open to you at present.'
                      ELSE 'You may be considered for: ' || v_now || '.' END;
    PERFORM admissions.notify_applicant(p_app, 'Your ' || v_session || ' admission: suggested programmes corrected', v_body,
        'MOAUM: the programmes suggested to you have been corrected. See your email or the portal.');
    INSERT INTO admissions.suggestion_correction (application_id, told, told_at, other_faculty, corrected_to, sent_by)
    VALUES (p_app, x.told, x.told_at, x.told_other, v_now, p_actor);
    -- the corrected list is now the last one sent
    UPDATE admissions.suggestion_sent SET programmes = coalesce(v_now, 'None of the faculty at present'), sent_at = now(), sent_by = p_actor
     WHERE application_id = p_app;
    RETURN 'CORRECTED';
END $fn$;
COMMENT ON FUNCTION admissions.correct_suggestion(uuid, uuid) IS
  'Sends an applicant told of another faculty''s programme the corrected list (V399) — what was named is in another faculty; the programmes of their faculty they may be considered for, or none at present — records it and makes it the last list sent. NOTHING_TO_CORRECT when nothing named was another faculty''s.';

COMMIT;

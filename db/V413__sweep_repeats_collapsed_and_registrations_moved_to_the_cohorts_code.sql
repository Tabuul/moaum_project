-- ═══════════════════════════════════════
-- V413 — the sweep's repeated answers collapsed; a registration under the other code family moved to the cohort's code
--
--   1 · The reconciler's sweep asks the gateway about a hanging reference every ten minutes and wrote a log row each time it got
--       no usable answer — twelve rows for one reference. Now a repeat of the same answer for the same reference is folded into
--       the open row (finance.gateway_event.times, last_at), so the log reads "checked 5 times, last at …", and the row still
--       resolves as one. The sweep itself now waits longer between checks (5, 10, 30 minutes, then an hour) — the API's rule.
--   2 · V402 shows each student their cohort's code family. Students who registered before it may hold the other family's code
--       (a 300-level student on MOAU-LIS 115 where their cohort's is BSU-LIS 115). catalogue.other_family_registrations lists
--       them for a session, and catalogue.move_entry_to_own_code moves one registration line to the cohort's class — the same
--       session, semester and stream, opened if the structure allows and it is not yet — unless a score is already entered on
--       it, which the Examinations Office decides. Registration moves; nothing graded is touched.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V413: sweep repeats collapsed; registrations moved to the cohort''s code', true);

-- ── 1 · the sweep's repeats, one row ───────────────────────────────────────────────────────
ALTER TABLE finance.gateway_event ADD COLUMN IF NOT EXISTS times int NOT NULL DEFAULT 1;
ALTER TABLE finance.gateway_event ADD COLUMN IF NOT EXISTS last_at timestamptz;
COMMENT ON COLUMN finance.gateway_event.times IS 'V413: how many times the sweep got this same answer for this reference; the row is written once and counted up.';
COMMENT ON COLUMN finance.gateway_event.last_at IS 'V413: when the sweep last got this same answer.';

/* a sweep answer that repeats the open row's for the reference is counted on that row; true when it was */
CREATE OR REPLACE FUNCTION finance.collapse_sweep_repeat(p_gateway text, p_reference text, p_status text, p_payload jsonb)
RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE v uuid;
BEGIN
    SELECT e.id INTO v
      FROM finance.gateway_event e
     WHERE e.gateway = p_gateway AND e.reference = upper(btrim(p_reference)) AND e.source = 'SWEEP' AND e.outcome = 'GATEWAY_ERROR'
       AND e.resolved_at IS NULL AND e.status IS NOT DISTINCT FROM p_status
     ORDER BY e.received_at DESC LIMIT 1;
    IF v IS NULL THEN
        RETURN false;
    END IF;
    UPDATE finance.gateway_event SET times = times + 1, last_at = now(), payload = coalesce(p_payload, payload) WHERE id = v;
    RETURN true;
END $fn$;

-- ── 2 · registrations under the other family's code ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.other_family_registrations(p_session text)
RETURNS TABLE(registration_id uuid, student_id uuid, matric_no text, surname text, other_names text, level int, registration_status text,
              semester int, course_code text, offering_id uuid, own_code text, own_offering_id uuid, scored boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT r.id, s.id, s.matric_no, s.surname, s.other_names, r.level, r.status, r.semester, o.course_code, o.id,
           catalogue.twin_by_code(o.course_code), o2.id,
           EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
                    WHERE sh.offering_id = o.id AND sc.student_id = s.id)
      FROM registration.course_registration r
      JOIN people.student s ON s.id = r.student_id
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      LEFT JOIN catalogue.offering o2 ON o2.course_code = catalogue.twin_by_code(o.course_code)
                                     AND o2.session = o.session AND o2.semester = o.semester AND o2.stream = o.stream
     WHERE r.session = p_session AND r.status IN ('DRAFT', 'SUBMITTED', 'APPROVED')
       AND catalogue.other_familys_code(s.id, o.course_code)
     ORDER BY s.matric_no, o.course_code
$fn$;
COMMENT ON FUNCTION catalogue.other_family_registrations(text) IS
  'V413: the registration lines of a session holding the other code family''s code of a course the student''s cohort registers under its own — with the cohort''s class, if open, and whether a score is already on the line.';

CREATE OR REPLACE FUNCTION catalogue.move_entry_to_own_code(p_registration uuid, p_offering uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE r registration.course_registration; o catalogue.offering; v_own text; v_target uuid;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'CODE_FAMILY_ACTOR: a registration is moved by a person' USING ERRCODE = '23514';
    END IF;
    IF btrim(coalesce(p_reason, '')) = '' THEN
        RAISE EXCEPTION 'CODE_FAMILY_REASON: say why the registration is moved' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'CODE_FAMILY_NONE: no such registration' USING ERRCODE = '23514'; END IF;
    IF r.status NOT IN ('DRAFT', 'SUBMITTED', 'APPROVED') THEN
        RAISE EXCEPTION 'CODE_FAMILY_LOCKED: a % registration is not moved', lower(r.status) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO o FROM catalogue.offering WHERE id = p_offering;
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = p_registration AND offering_id = p_offering AND status IN ('REGISTERED', 'APPROVED')) THEN
        RAISE EXCEPTION 'CODE_FAMILY_NONE: the registration does not hold that class' USING ERRCODE = '23514';
    END IF;
    IF NOT catalogue.other_familys_code(r.student_id, o.course_code) THEN
        RAISE EXCEPTION 'CODE_FAMILY_OWN: % is the student''s own family''s code', o.course_code USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.score sc JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id WHERE sh.offering_id = o.id AND sc.student_id = r.student_id) THEN
        RAISE EXCEPTION 'CODE_FAMILY_SCORED: a score is already entered on % for this student; the Examinations Office decides', o.course_code
            USING ERRCODE = '23514', HINT = 'A published result is amended through the results chain, not by moving the registration.';
    END IF;
    v_own := catalogue.twin_by_code(o.course_code);
    SELECT id INTO v_target FROM catalogue.offering WHERE course_code = v_own AND session = o.session AND semester = o.semester AND stream = o.stream;
    IF v_target IS NULL THEN
        PERFORM catalogue.open_classes_for_courses(ARRAY[v_own]);
        SELECT id INTO v_target FROM catalogue.offering WHERE course_code = v_own AND session = o.session AND semester = o.semester AND stream = o.stream;
    END IF;
    IF v_target IS NULL THEN
        RAISE EXCEPTION 'CODE_FAMILY_NO_CLASS: % has no class in % semester %; open it on the allocation desk first', v_own, o.session, o.semester USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', 'Registration moved to the cohort''s code: ' || btrim(p_reason), true);
    IF EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = p_registration AND offering_id = v_target) THEN
        -- the cohort's class is already on the registration: the other family's line is dropped, nothing is deleted
        UPDATE registration.entry SET status = 'DROPPED' WHERE registration_id = p_registration AND offering_id = p_offering;
    ELSE
        UPDATE registration.entry SET offering_id = v_target WHERE registration_id = p_registration AND offering_id = p_offering;
    END IF;
    RETURN v_target;
END $fn$;
COMMENT ON FUNCTION catalogue.move_entry_to_own_code(uuid, uuid, text) IS
  'V413: one registration line moved from the other family''s class to the cohort''s class of the same session, semester and stream (opened if owed), unless a score is on it; the cohort''s class id.';

COMMIT;

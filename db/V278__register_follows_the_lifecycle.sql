-- ═══════════════════════════════════════════════════════════════════════════
-- V278 — the register follows the lifecycle: no separate intake to wait for
--
--   A candidate who accepted the offer and was successfully screened stood at
--   "Wait for the Registry to bring you onto the register" until an office ran
--   the session's intake; until then the admission number did not exist, the
--   student portal did not know them and the sign-in door sent them back to
--   the applicant portal. The register now follows the lifecycle itself: the
--   student record and the admission number are created the moment the
--   screening succeeds, on acceptance where the session asks no screening, and
--   when a change of programme is approved after an unsuccessful screening.
--   people.intake_one brings one candidate on (idempotent); people.intake
--   loops it, so the office's button remains for stragglers and does nothing
--   twice.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V278: the register follows the lifecycle', true);

/* one candidate onto the register: the student record under an admission number; the same record again when already there */
CREATE OR REPLACE FUNCTION people.intake_one(p_candidate uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c admissions.candidate; v_id uuid; v_code text; v_yy text;
BEGIN
    SELECT * INTO c FROM admissions.candidate WHERE id = p_candidate;
    IF c.id IS NULL THEN RAISE EXCEPTION 'no such candidate' USING ERRCODE = '23503'; END IF;
    SELECT id INTO v_id FROM people.student WHERE candidate_id = c.id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    IF c.offer_state NOT IN ('ADMITTED', 'ACCEPTED') THEN
        RAISE EXCEPTION 'only an admitted candidate is brought onto the register; % is %', c.jamb_reg_no, lower(coalesce(c.offer_state, 'not admitted')) USING ERRCODE = '23514';
    END IF;
    -- candidate.programme is the programme NAME; resolve it to a code, accepting a value that is already a code
    v_code := (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1);
    IF v_code IS NULL THEN
        IF EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = c.programme) THEN
            v_code := c.programme;
        ELSE
            RAISE EXCEPTION 'the programme "%" for candidate % is not one the University runs; it cannot be brought onto the register',
                c.programme, c.jamb_reg_no USING ERRCODE = '23503',
                HINT = 'Set the programme''s University name to match ref.programme, or correct the candidate''s programme.';
        END IF;
    END IF;
    v_yy := substr(c.session, 3, 2);
    INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names,
                                programme_code, entry_mode, entry_session, entry_level, current_level)
    VALUES (gen_random_uuid(), c.id,
            'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', c.session)::text, 6, '0'),
            c.jamb_reg_no, c.surname, c.other_names, v_code,
            CASE WHEN c.entry_mode IN ('UTME', 'DIRECT_ENTRY') THEN c.entry_mode ELSE 'UTME' END,
            c.session, c.entry_level, c.entry_level)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

/* the session's intake, as the office's button runs it: every admitted candidate not yet on the register */
CREATE OR REPLACE FUNCTION people.intake(p_session text)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE c record; v_n int := 0;
BEGIN
    FOR c IN
        SELECT a.id FROM admissions.candidate a
         WHERE a.session = p_session AND a.offer_state IN ('ADMITTED', 'ACCEPTED')
           AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.id)
         ORDER BY a.surname, a.other_names
    LOOP
        PERFORM people.intake_one(c.id);
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $$;

/* the register when the lifecycle is due it: the offer accepted and not declined, the screening satisfied (or none asked) */
CREATE OR REPLACE FUNCTION admissions.register_when_due(p_app uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL OR a.accepted_at IS NULL OR a.declined_at IS NOT NULL THEN RETURN NULL; END IF;
    IF NOT admissions.screening_ok(p_app) THEN RETURN NULL; END IF;
    RETURN people.intake_one(a.candidate_id);
END $$;

CREATE OR REPLACE FUNCTION admissions.screening_decide(p_app uuid, p_decision text, p_reason text, p_remarks text, p_actor uuid, p_office text)
 RETURNS admissions.screening_form
 LANGUAGE plpgsql
AS $function$

DECLARE f admissions.screening_form; a admissions.application; c admissions.candidate; v_alts int := 0; v_run uuid;

BEGIN

    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app FOR UPDATE;

    IF f.application_id IS NULL THEN RAISE EXCEPTION 'no screening form for this application' USING ERRCODE = '23503'; END IF;

    IF f.state NOT IN ('SUBMITTED', 'UNDER_REVIEW') THEN RAISE EXCEPTION 'a decision is taken on a submitted form; this one is %', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514'; END IF;

    SELECT * INTO a FROM admissions.application WHERE id = p_app;

    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;

    IF p_decision = 'RETURNED' THEN

        IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a form returned for correction says what must be corrected' USING ERRCODE = '23514'; END IF;

        UPDATE admissions.screening_form SET state = 'RETURNED', returned_note = btrim(p_reason), remarks = coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), remarks), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;

        PERFORM admissions.screening_log(p_app, 'RETURNED', btrim(p_reason));

        PERFORM admissions.notify_applicant(p_app, 'Your screening form needs a correction',

            'The screening officers returned your form ' || f.screening_no || ' for correction: ' || btrim(p_reason) || ' Open Online Screening on your portal, make the correction and submit again.',

            'MOAUM: your screening form was returned for correction — see the portal.');

        RETURN f;

    ELSIF p_decision = 'SUCCESSFUL' THEN

        UPDATE admissions.screening_form SET state = 'SUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_reason = nullif(btrim(coalesce(p_reason, '')), ''),

               remarks = nullif(btrim(coalesce(p_remarks, '')), ''), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;

        -- the application is cleared (the stage the journey already knows), the answers go onto the record

        UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = p_app;

        PERFORM admissions.screening_apply_biodata(p_app);
        -- the register follows the screening (V278): the student record and the admission number, the moment the screening succeeds
        PERFORM admissions.register_when_due(p_app);

        PERFORM admissions.screening_log(p_app, 'SUCCESSFUL', coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), 'Successfully screened'));

        PERFORM admissions.notify_applicant(p_app, 'You have been successfully screened',

            'You have been successfully screened for ' || c.programme || '. You can go ahead and pay school fees and commence registration using your admission number' || coalesce(' ' || (SELECT s.admission_no FROM people.student s WHERE s.candidate_id = c.id LIMIT 1), '') || '. Your matriculation number is issued afterwards over the list of students who registered.',

            'MOAUM: you have been successfully screened. You may now pay school fees and register.');

        RETURN f;

    ELSIF p_decision = 'UNSUCCESSFUL' THEN

        IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an unsuccessful screening carries its reason' USING ERRCODE = '23514'; END IF;

        UPDATE admissions.screening_form SET state = 'UNSUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_reason = btrim(p_reason),

               remarks = nullif(btrim(coalesce(p_remarks, '')), ''), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;

        PERFORM admissions.screening_log(p_app, 'UNSUCCESSFUL', btrim(p_reason));

        -- the programmes the candidate does qualify for, read now by the engine

        v_run := admissions.evaluate_application(p_app, 'SYSTEM', p_actor);

        SELECT count(*) INTO v_alts FROM admissions.eligibility_result x WHERE x.run_id = v_run AND x.kind = 'ALTERNATIVE' AND x.result IN ('ELIGIBLE', 'ELIGIBLE_SCREENING');

        PERFORM admissions.notify_applicant(p_app, 'Your screening was not successful',

            'Your screening for ' || c.programme || ' was not successful. Reason: ' || btrim(p_reason) || ' '

            || CASE WHEN v_alts > 0 THEN 'Based on your results and the current admission policy, ' || v_alts || ' other programme(s) may be available to you; open Online Screening on your portal to apply for a change of programme. Your acceptance fee remains valid and is not paid again.'

                    ELSE 'No alternative programme was found on the current admission policy; contact the Admissions Office.' END,

            'MOAUM: your screening was not successful. ' || CASE WHEN v_alts > 0 THEN v_alts || ' other programme(s) may be open to you — see the portal.' ELSE 'See the portal for the reason.' END);

        RETURN f;

    END IF;

    RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';

END $function$;

CREATE OR REPLACE FUNCTION admissions.settle_acceptance(p_app uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.accepted_at IS NULL AND a.undertaking_at IS NOT NULL AND a.acceptance_confirmed_at IS NOT NULL AND a.declined_at IS NULL THEN
        UPDATE admissions.application SET accepted_at = now() WHERE id = p_app;
        UPDATE admissions.candidate SET offer_state = 'ACCEPTED' WHERE id = a.candidate_id AND offer_state = 'ADMITTED';
        -- where the session asks no screening, the register follows the acceptance (V278)
        PERFORM admissions.register_when_due(p_app);
        PERFORM admissions.notify_applicant(p_app, 'Your place is held',
            'Your acceptance fee is confirmed and your undertaking is on record. Your place is held. Bring your original documents to the Registry for clearance; nothing is paid at clearance.',
            'MOAUM: your place is held. Bring your original documents to the Registry for clearance.');
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION admissions.decide_programme_change(p_req uuid, p_decision text, p_note text, p_actor uuid)
 RETURNS text
 LANGUAGE plpgsql
AS $function$

DECLARE q admissions.programme_change_request; a admissions.application; c admissions.candidate; r record; v_note text := nullif(btrim(coalesce(p_note, '')), '');

BEGIN

    SELECT * INTO q FROM admissions.programme_change_request WHERE id = p_req FOR UPDATE;

    IF q.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;

    IF q.state <> 'REQUESTED' THEN RAISE EXCEPTION 'the request is already %', lower(q.state) USING ERRCODE = '23514'; END IF;

    SELECT * INTO a FROM admissions.application WHERE id = q.application_id;

    SELECT * INTO c FROM admissions.candidate WHERE id = q.candidate_id;

    IF p_decision = 'REJECT' THEN

        IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514'; END IF;

        UPDATE admissions.programme_change_request SET state = 'REJECTED', decided_at = now(), decided_by = p_actor, decision_note = v_note WHERE id = q.id;

        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_REJECTED', q.to_programme_code, NULL, v_note);

        PERFORM admissions.notify_applicant(q.application_id, 'Your request to change programme was not approved', 'Your request to move to ' || q.to_programme || ' was not approved by the Admissions Office. Reason: ' || v_note || ' Your application for ' || q.from_programme || ' stands as it was.', NULL);

        RETURN 'REJECTED';

    ELSIF p_decision = 'APPROVE' THEN

        IF a.decision_released_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'UNSUCCESSFUL') THEN

            RAISE EXCEPTION 'the Board''s decision has been released; the programme is not changed under it' USING ERRCODE = '23514';

        END IF;

        -- eligibility read again at the moment of decision

        SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, q.to_programme_code, c.entry_mode);

        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN

            RAISE EXCEPTION 'on the current settings the candidate is no longer eligible for %: %', q.to_programme, array_to_string(r.reasons, '; ') USING ERRCODE = '23514';

        END IF;

        UPDATE admissions.candidate SET programme = q.to_programme WHERE id = c.id;

        -- the student on the register, not yet matriculated, follows the programme (V269); the original stays on the request and the trail

        UPDATE people.student SET programme_code = q.to_programme_code WHERE candidate_id = c.id AND matric_no IS NULL;

        IF EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'UNSUCCESSFUL') THEN

            -- the acceptance fee was paid for the admission, once: the approved change carries the entitlement and opens school fees

            UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = a.id;

            PERFORM admissions.screening_log(a.id, 'PROGRAMME_CHANGED', 'From ' || q.from_programme || ' to ' || q.to_programme || ' after an unsuccessful screening; acceptance fee already paid, not charged again');

            PERFORM admissions.notify_applicant(a.id, 'Programme change approved — next step: school fees',

                'Your change of programme from ' || q.from_programme || ' to ' || q.to_programme || ' is approved. Your acceptance fee, already paid, remains valid and is not paid again. The next step is school fees, on the student portal under your admission number.',

                'MOAUM: your change to ' || q.to_programme || ' is approved. Acceptance fee not charged again; next, school fees.');

        END IF;

        UPDATE admissions.programme_change_request SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decision_note = v_note, eligibility_at_decision = r.result WHERE id = q.id;
        -- an approved change after an unsuccessful screening opens school fees: the register follows it (V278)
        PERFORM admissions.register_when_due(a.id);

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

-- the hooks run under the offices that decide screenings, confirm fees and approve changes
GRANT SELECT, INSERT ON people.student TO app_admissions, app_finance, app_payments;

-- candidates already due the register today are brought on now, so nobody waits on a button
DO $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT a.id FROM admissions.application a
              WHERE a.accepted_at IS NOT NULL AND a.declined_at IS NULL
                AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.candidate_id)
    LOOP
        BEGIN
            IF admissions.register_when_due(r.id) IS NOT NULL THEN n := n + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'V278: application % not brought on: %', r.id, SQLERRM;
        END;
    END LOOP;
    RAISE NOTICE 'V278: % candidate(s) brought onto the register', n;
END $$;

COMMIT;

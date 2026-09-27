-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V281 — the suggested programmes are capped: the best three (or up to five) the settings allow
--
--   The eligibility engine (V266) evaluates a refused candidate against every
--   open programme with a rule and listed every one they qualified for — on a
--   permissive policy a dozen or more, on the Programme Eligibility desk, the
--   applicant's own page, the list that goes back to JAMB and the reconsiderations.
--   The Office asked for a short list. The session's admission settings now
--   carry how many programmes are suggested (max_alternatives, 1–5, default 3);
--   the engine still evaluates and records every alternative — the desk's
--   "everything" view keeps them, with their checks — but marks only the
--   best-ranked eligible ones as suggested (eligibility_result.suggested), in
--   the engine's order: eligible before eligible-on-screening, the candidate's
--   own faculty first, then by name. Every reader of the suggestions — the
--   desk, the applicant, the change-of-programme check, the JAMB template, the
--   reconsiderations, the screening desk and the unsuccessful-screening notice —
--   reads the suggested rows; the run's alternatives count is the suggestions.
--   Current runs are re-ranked here on their session's setting; nothing is
--   deleted and nothing is re-evaluated.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V281: the suggested programmes capped on the session''s settings', true);

ALTER TABLE admissions.session_policy
    ADD COLUMN IF NOT EXISTS max_alternatives integer NOT NULL DEFAULT 3
        CONSTRAINT ck_policy_max_alternatives CHECK (max_alternatives BETWEEN 1 AND 5);
COMMENT ON COLUMN admissions.session_policy.max_alternatives IS
  'How many alternative programmes the eligibility engine suggests to a refused candidate (1–5): the best-ranked eligible ones; every alternative is still evaluated and kept.';

ALTER TABLE admissions.eligibility_result
    ADD COLUMN IF NOT EXISTS suggested boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN admissions.eligibility_result.suggested IS
  'True on the alternatives the run suggests: the best-ranked eligible ones within the session''s max_alternatives. The rest are kept, evaluated, for the desk''s full view.';
CREATE INDEX IF NOT EXISTS ix_elres_suggested ON admissions.eligibility_result (run_id) WHERE suggested;

-- ── the ranking: the top of the eligible alternatives, in the engine's order, as many as the cap ──
CREATE OR REPLACE FUNCTION admissions.rank_alternatives(p_run uuid, p_cap integer)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE n integer;
BEGIN
    UPDATE admissions.eligibility_result SET suggested = false WHERE run_id = p_run AND suggested;
    WITH top AS (
        SELECT id FROM admissions.eligibility_result
         WHERE run_id = p_run AND kind = 'ALTERNATIVE' AND result IN ('ELIGIBLE', 'ELIGIBLE_SCREENING')
         ORDER BY ord, programme LIMIT greatest(1, least(5, coalesce(p_cap, 3))))
    UPDATE admissions.eligibility_result x SET suggested = true FROM top WHERE x.id = top.id;
    SELECT count(*) INTO n FROM admissions.eligibility_result WHERE run_id = p_run AND suggested;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION admissions.rank_alternatives(uuid, integer) IS
  'Marks the best-ranked eligible alternatives of a run as suggested, as many as the cap (1–5), and returns how many.';

-- ── the engine marks the suggestions as it evaluates ──
CREATE OR REPLACE FUNCTION admissions.evaluate_application(p_app uuid, p_trigger text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $fn$
DECLARE a admissions.application; c admissions.candidate; pol admissions.session_policy; v_run uuid; v_code text; r record; g record; n int := 0; ord int := 0;
        v_prev text; v_prev_alts int; v_fac text; e record;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    v_code := admissions.programme_code_of(c.programme);
    SELECT * INTO pol FROM admissions.session_policy p WHERE p.session = a.session ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1;
    SELECT x.applied_result, x.alternatives INTO v_prev, v_prev_alts FROM admissions.eligibility_run x WHERE x.application_id = p_app AND x.superseded_at IS NULL ORDER BY x.evaluated_at DESC LIMIT 1;
    UPDATE admissions.eligibility_run SET superseded_at = now() WHERE application_id = p_app AND superseded_at IS NULL;
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, v_code, c.entry_mode);
    INSERT INTO admissions.eligibility_run (application_id, candidate_id, session, jamb_key, entry_mode, applied_programme_code, applied_programme, policy_id, policy_state, rules_version, applied_result, evaluated_by, trigger_kind)
    VALUES (p_app, c.id, a.session, c.jamb_key, c.entry_mode, v_code, c.programme, pol.id, pol.state, pol.rules_version, r.result, p_actor, p_trigger)
    RETURNING id INTO v_run;
    SELECT p.faculty_code INTO v_fac FROM ref.programme p WHERE p.code = v_code;
    INSERT INTO admissions.eligibility_result (run_id, programme_code, programme, faculty_code, faculty, department, kind, result, checks, reasons, ord)
    SELECT v_run, coalesce(v_code, '?'), c.programme, p.faculty_code, f.name, d.name, 'APPLIED', r.result, r.checks, r.reasons, 0
      FROM (SELECT 1) one LEFT JOIN ref.programme p ON p.code = v_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code;
    -- alternatives are searched only when the applied programme is refused on the rules
    IF r.result = 'NOT_ELIGIBLE' AND pol.id IS NOT NULL THEN
        FOR g IN
            SELECT p.code, p.name, p.faculty_code, f.name AS faculty, d.name AS department
              FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
             WHERE NOT p.archived AND p.code <> coalesce(v_code, '')
               AND EXISTS (SELECT 1 FROM admissions.programme_rule pr WHERE pr.policy_id = pol.id AND pr.programme_code = p.code)
               AND NOT EXISTS (SELECT 1 FROM admissions.programme_closed cl WHERE cl.policy_id = pol.id AND cl.programme_code = p.code)
             ORDER BY p.name
        LOOP
            SELECT * INTO e FROM admissions.evaluate_programme(a.session, c.jamb_key, g.code, c.entry_mode);
            INSERT INTO admissions.eligibility_result (run_id, programme_code, programme, faculty_code, faculty, department, kind, result, checks, reasons, ord)
            VALUES (v_run, g.code, g.name, g.faculty_code, g.faculty, g.department, 'ALTERNATIVE', e.result, e.checks, e.reasons,
                    CASE e.result WHEN 'ELIGIBLE' THEN 0 WHEN 'ELIGIBLE_SCREENING' THEN 100 WHEN 'UNVERIFIED' THEN 200 ELSE 300 END + CASE WHEN g.faculty_code = v_fac THEN 0 ELSE 50 END);
        END LOOP;
    END IF;
    -- the suggestions: the best-ranked eligible alternatives, as many as the session's settings allow (V281)
    n := admissions.rank_alternatives(v_run, coalesce(pol.max_alternatives, 3));
    UPDATE admissions.eligibility_run SET alternatives = n WHERE id = v_run;
    PERFORM admissions.eligibility_log(p_app, v_run, 'EVALUATED', v_code, r.result,
        'Applied programme ' || coalesce(c.programme, '?') || ': ' || r.result || CASE WHEN r.result = 'NOT_ELIGIBLE' THEN ' · ' || n || ' eligible alternative(s)' ELSE '' END
        || ' · policy ' || coalesce(a.session, '') || '-V' || coalesce(pol.rules_version::text, '?') || ' (' || coalesce(pol.state, 'none') || ') · ' || p_trigger);
    IF n > 0 OR r.result = 'NOT_ELIGIBLE' THEN
        PERFORM admissions.eligibility_log(p_app, v_run, 'RECOMMENDATION_GENERATED', v_code, r.result, n || ' eligible alternative programme(s) found');
    END IF;
    -- the applicant told once per change of verdict, never that admission is guaranteed
    IF r.result = 'NOT_ELIGIBLE' AND (v_prev IS DISTINCT FROM r.result OR coalesce(v_prev_alts, -1) <> n) AND p_trigger IN ('SUBMISSION', 'SYSTEM', 'DATA_CHANGE', 'POLICY_CHANGE', 'PROGRAMME_CHANGE') THEN
        PERFORM admissions.notify_applicant(p_app, 'Your ' || a.session || ' application — programme eligibility',
            'Your selected programme, ' || c.programme || ', does not meet the current admission requirements based on the information on your record. '
            || CASE WHEN n > 0 THEN 'Based on your submitted qualifications, ' || n || ' alternative programme(s) may be available to you. Please review Programme eligibility on your admission portal; nothing changes unless you ask and the Admissions Office approves.'
                    ELSE 'No eligible alternative programme was found on the current admission policy. Please review the reasons on your admission portal.' END,
            'MOAUM: your selected programme does not meet the admission requirements on record. ' || CASE WHEN n > 0 THEN n || ' alternative programme(s) may be available — see the portal.' ELSE 'See the reasons on the portal.' END);
    ELSIF r.result IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') AND v_prev = 'NOT_ELIGIBLE' THEN
        PERFORM admissions.notify_applicant(p_app, 'Your ' || a.session || ' application — programme eligibility',
            'On the information now on your record, your selected programme, ' || c.programme || ', meets the current admission requirements. This is not an offer of admission; the Admissions Board decides in the normal way.', NULL);
    END IF;
    RETURN v_run;
END $fn$;

-- ── the unsuccessful-screening notice counts the suggestions, not every eligible alternative ──
CREATE OR REPLACE FUNCTION admissions.screening_decide(p_app uuid, p_decision text, p_reason text, p_remarks text, p_actor uuid, p_office text)
 RETURNS admissions.screening_form
 LANGUAGE plpgsql
AS $fn$







DECLARE f admissions.screening_form; a admissions.application; c admissions.candidate; v_alts int := 0; v_run uuid;







BEGIN







    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app FOR UPDATE;







    IF f.application_id IS NULL THEN RAISE EXCEPTION 'no screening form for this application' USING ERRCODE = '23503'; END IF;







    IF f.state NOT IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN RAISE EXCEPTION 'a decision is taken on a screening awaiting it; this one is %', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514'; END IF;







    SELECT * INTO a FROM admissions.application WHERE id = p_app;







    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;







    IF p_decision IN ('RETURNED', 'CORRECTION') THEN

        -- V280: one correction named; the applicant provides that and nothing else

        IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a correction names the one thing to be corrected' USING ERRCODE = '23514'; END IF;

        UPDATE admissions.screening_form SET state = 'CORRECTION_REQUIRED', returned_note = btrim(p_reason), remarks = coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), remarks), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;

        PERFORM admissions.screening_log(p_app, 'CORRECTION_REQUIRED', btrim(p_reason));

        PERFORM admissions.notify_applicant(p_app, 'Your screening needs one correction',

            'The screening officers need one thing corrected on screening ' || f.screening_no || ': ' || btrim(p_reason) || ' Open Screening on your portal, provide it, and press "I have made the correction". Nothing else is asked of you.',

            'MOAUM: your screening needs one correction - see the portal.');

        RETURN f;

    ELSIF p_decision = 'SUCCESSFUL' THEN







        UPDATE admissions.screening_form SET state = 'SUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_reason = nullif(btrim(coalesce(p_reason, '')), ''),







               remarks = nullif(btrim(coalesce(p_remarks, '')), ''), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;







        -- the application is cleared (the stage the journey already knows), the answers go onto the record







        UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = p_app;







        PERFORM admissions.screening_apply_biodata(p_app);



        -- the register follows the screening (V278): the student record and the admission number, the moment the screening succeeds



        PERFORM admissions.register_when_due(p_app);

        -- the official screening forms are generated from the record (V280): the applicant prints them, never fills them

        PERFORM admissions.issue_screening_forms(p_app);







        PERFORM admissions.screening_log(p_app, 'SUCCESSFUL', coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), 'Successfully screened'));







        PERFORM admissions.notify_applicant(p_app, 'You have been successfully screened',







            'You have been successfully screened for ' || c.programme || '. Your screening forms have been generated from your record; view, download and print them on the portal. You can go ahead and pay school fees and commence registration using your admission number' || coalesce(' ' || (SELECT s.admission_no FROM people.student s WHERE s.candidate_id = c.id LIMIT 1), '') || '. Your matriculation number is issued afterwards over the list of students who registered.',







            'MOAUM: you have been successfully screened. You may now pay school fees and register.');







        RETURN f;







    ELSIF p_decision = 'UNSUCCESSFUL' THEN







        IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an unsuccessful screening carries its reason' USING ERRCODE = '23514'; END IF;







        UPDATE admissions.screening_form SET state = 'UNSUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_reason = btrim(p_reason),







               remarks = nullif(btrim(coalesce(p_remarks, '')), ''), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;







        PERFORM admissions.screening_log(p_app, 'UNSUCCESSFUL', btrim(p_reason));







        -- the programmes the candidate does qualify for, read now by the engine







        v_run := admissions.evaluate_application(p_app, 'SYSTEM', p_actor);







        SELECT count(*) INTO v_alts FROM admissions.eligibility_result x WHERE x.run_id = v_run AND x.kind = 'ALTERNATIVE' AND x.suggested;







        PERFORM admissions.notify_applicant(p_app, 'Your screening was not successful',







            'Your screening for ' || c.programme || ' was not successful. Reason: ' || btrim(p_reason) || ' '







            || CASE WHEN v_alts > 0 THEN 'Based on your results and the current admission policy, ' || v_alts || ' other programme(s) may be available to you; open Online Screening on your portal to apply for a change of programme. Your acceptance fee remains valid and is not paid again.'







                    ELSE 'No alternative programme was found on the current admission policy; contact the Admissions Office.' END,







            'MOAUM: your screening was not successful. ' || CASE WHEN v_alts > 0 THEN v_alts || ' other programme(s) may be open to you — see the portal.' ELSE 'See the portal for the reason.' END);







        RETURN f;







    END IF;







    RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';







END $fn$;

-- ── current runs re-ranked on their session's setting; the count on the run follows ──
DO $do$
DECLARE r record; n integer;
BEGIN
    PERFORM set_config('moaum.maintenance', 'on', true);
    FOR r IN SELECT x.id, coalesce(p.max_alternatives, 3) AS cap
               FROM admissions.eligibility_run x
               LEFT JOIN admissions.session_policy p ON p.session = x.session
              WHERE x.superseded_at IS NULL
    LOOP
        n := admissions.rank_alternatives(r.id, r.cap);
        UPDATE admissions.eligibility_run SET alternatives = n WHERE id = r.id AND alternatives IS DISTINCT FROM n;
    END LOOP;
    PERFORM set_config('moaum.maintenance', 'off', true);
END $do$;

COMMIT;

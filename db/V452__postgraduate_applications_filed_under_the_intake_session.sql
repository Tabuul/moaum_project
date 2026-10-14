-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V452 — Postgraduate applications filed under the intake session (2026/2027), not the School's running session
--
--   · Since V224 a postgraduate application took the PG School's current session, admissions.pg_current_session(), the
--     session its students are registered in. So while 2025/2026 runs, the public PG application page, the Director of
--     ICT's window and every application made since read 2025/2026, when the applicants applying now are for 2026/2027
--     (the user: "PG application is 2026/2027 not 2025/2026"). Post-UTME moved to its intake session in V378; PG stayed.
--   · admissions.pg_intake_session(): the first planned session after the School's current one on the PG calendar, else the
--     University's intake session when it is later than the School's current, else the School's current session. New
--     applications (pg_apply) and the public application window (policy.application_session) read it.
--     admissions.pg_current_session() is unchanged: registration, coursework, matriculation and the student portal stay on
--     the running session.
--   · The fees: admissions.pg_fee_rule(session) gives the stated fees of the session; for a session the Bursary has stated
--     none, now the latest earlier session's stated fees (the user's choice: carry 2025/2026 until 2026/2027 is stated), and
--     only where no PG fee was ever stated, the amounts V202 wrote in. The Bursary states 2026/2027 on Fees as before.
--   · Re-filed under the intake (the user's choice: every application not yet admitted):
--       - the Director of ICT's POSTGRADUATE_APPLICATION window of the running session, dates unchanged, with its history,
--         where the intake has none of its own — left behind, the intake would have no window and stay open with no end;
--       - every application of the running session not admitted (no student record, not ADMITTED), with its applicant
--         account; payments keep their references and amounts (a PG fee reference carries no session of its own) and the
--         application keeps its number. Each application's history records the move. The admitted stay in the running session.
--   · Nothing is deleted. Nobody is messaged.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V452: postgraduate applications filed under the intake session', true);

CREATE OR REPLACE FUNCTION admissions.pg_intake_session()
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT s.name FROM admissions.pg_academic_session s
          WHERE s.state = 'PLANNED' AND s.name ~ '^[0-9]{4}/[0-9]{4}$' AND s.name > admissions.pg_current_session()
          ORDER BY s.name LIMIT 1),
        (SELECT i.s FROM (SELECT policy.intake_session() AS s) i WHERE i.s > admissions.pg_current_session()),
        admissions.pg_current_session())
$fn$;
COMMENT ON FUNCTION admissions.pg_intake_session() IS
  'The postgraduate intake session (V452): the session applicants are admitted into — the first planned session after the PG School''s current one, else the University''s intake when later, else the School''s current session. New applications and the PG application window read it; registration and coursework stay on admissions.pg_current_session().';

CREATE OR REPLACE FUNCTION admissions.pg_fee_rule(p_session text)
RETURNS TABLE (application_fee numeric, acceptance_fee numeric, checking_fee numeric)
LANGUAGE sql STABLE AS $fn$
    -- the session's stated fees; else the latest earlier session's stated fees (V452: carried until the Bursary states the
    -- session); else, where no postgraduate fee was ever stated, the amounts V202 wrote in
    SELECT f.application_fee, f.acceptance_fee, f.checking_fee
      FROM admissions.pg_fee f
     WHERE f.session = coalesce((SELECT x.session FROM admissions.pg_fee x WHERE x.session = p_session),
                                (SELECT max(x.session) FROM admissions.pg_fee x WHERE x.session < p_session))
    UNION ALL
    SELECT 20000, 50000, 3000
     WHERE NOT EXISTS (SELECT 1 FROM admissions.pg_fee f WHERE f.session = p_session)
       AND NOT EXISTS (SELECT 1 FROM admissions.pg_fee f WHERE f.session < p_session)
$fn$;
COMMENT ON FUNCTION admissions.pg_fee_rule(text) IS
  'The postgraduate fees of a session (V452): the stated ones; else the latest earlier session''s stated ones, carried until the Bursary states the session; else the amounts V202 wrote in.';

CREATE OR REPLACE FUNCTION admissions.pg_apply(p_form jsonb)
 RETURNS TABLE(application_id uuid, application_no text, reference text, amount numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session text; v_prog text; v_cat text; v_award text; v_applicant uuid; v_app uuid;
    v_ref text; v_amt numeric; v_yy text; v_sex text; ref jsonb; d jsonb; v_kind text;
BEGIN
    v_session := coalesce(nullif(btrim(p_form->>'session'), ''), admissions.pg_intake_session());   -- V452: the intake, not the School's running session
    v_prog := upper(btrim(coalesce(p_form->>'programme', '')));
    SELECT category, pg_award INTO v_cat, v_award FROM ref.programme WHERE upper(code) = v_prog AND NOT archived;
    IF v_cat IS NULL THEN
        RAISE EXCEPTION 'that programme is not one the University runs' USING ERRCODE = '23503';
    END IF;
    IF v_cat <> 'POST GRADUATE' THEN
        RAISE EXCEPTION 'that programme is not a postgraduate programme' USING ERRCODE = '23514';
    END IF;
    v_yy := substr(v_session, 3, 2);
    v_sex := nullif(upper(left(btrim(coalesce(p_form->>'sex', '')), 1)), '');
    IF v_sex IS NOT NULL AND v_sex NOT IN ('F', 'M') THEN v_sex := NULL; END IF;

    INSERT INTO admissions.pg_applicant (session, surname, other_names, sex, date_of_birth, state_of_origin, lga,
                                         nationality, contact_address, email, phone, password_hash)
    VALUES (v_session, btrim(coalesce(p_form->>'surname', '')), btrim(coalesce(p_form->>'otherNames', '')),
            v_sex,
            CASE WHEN coalesce(p_form->>'dob', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (p_form->>'dob')::date END,
            nullif(btrim(coalesce(p_form->>'state', '')), ''), nullif(btrim(coalesce(p_form->>'lga', '')), ''),
            left(nullif(btrim(coalesce(p_form->>'nationality', '')), ''), 80),
            -- the address on one line: its line breaks become commas, its spaces single
            left(nullif(btrim(regexp_replace(regexp_replace(coalesce(p_form->>'contactAddress', ''), '[\s,]*[\r\n]+[\s,]*', ', ', 'g'),
                                             '\s+', ' ', 'g'), ' ,'), ''), 300),
            lower(btrim(coalesce(p_form->>'email', ''))), nullif(btrim(coalesce(p_form->>'phone', '')), ''),
            p_form->>'passwordHash')
    RETURNING id INTO v_applicant;

    -- the first degree, kept on the application (for the desks): from priorDegrees[0], else the flat fields
    INSERT INTO admissions.pg_application (applicant_id, session, application_no, programme_code, entry_level,
            prior_institution, prior_award, prior_class, prior_cgpa, prior_year, proposal_title, proposal_text,
            state, submitted_at)
    VALUES (v_applicant, v_session,
            'PG/' || v_yy || '/' || lpad(platform.next_number('PG_APPLICATION', 'UNIVERSITY', v_session)::text, 6, '0'),
            v_prog, admissions.pg_award_level(v_award),
            coalesce(nullif(btrim(p_form->'priorDegrees'->0->>'institution'), ''), nullif(btrim(coalesce(p_form->>'priorInstitution', '')), '')),
            coalesce(nullif(btrim(p_form->'priorDegrees'->0->>'award'), ''),       nullif(btrim(coalesce(p_form->>'priorAward', '')), '')),
            coalesce(nullif(btrim(p_form->'priorDegrees'->0->>'classOfDegree'), ''), nullif(btrim(coalesce(p_form->>'priorClass', '')), '')),
            nullif(regexp_replace(coalesce(p_form->'priorDegrees'->0->>'cgpa', p_form->>'priorCgpa', ''), '[^0-9.]', '', 'g'), '')::numeric,
            nullif(regexp_replace(coalesce(p_form->'priorDegrees'->0->>'year', p_form->>'priorYear', ''), '[^0-9]', '', 'g'), '')::int,
            nullif(btrim(coalesce(p_form->>'proposalTitle', '')), ''),
            nullif(btrim(coalesce(p_form->>'proposalText', '')), ''),
            'SUBMITTED', now())
    RETURNING id INTO v_app;

    -- every qualification given, into the child table (first degree, prior Master's, PGD, NCE, HND, …)
    IF jsonb_typeof(p_form->'priorDegrees') = 'array' THEN
        FOR d IN SELECT * FROM jsonb_array_elements(p_form->'priorDegrees') LOOP
            IF coalesce(btrim(d->>'institution'), '') <> '' OR coalesce(btrim(d->>'award'), '') <> ''
               OR coalesce(btrim(d->>'field'), '') <> '' THEN
                v_kind := upper(coalesce(nullif(btrim(d->>'kind'), ''), 'FIRST'));
                IF v_kind NOT IN ('NCE','ND','HND','FIRST','PGD','MASTERS','PHD','OTHER') THEN v_kind := 'OTHER'; END IF;
                INSERT INTO admissions.pg_prior_degree (application_id, kind, institution, award, field, class_of_degree, cgpa, year)
                VALUES (v_app, v_kind,
                        nullif(btrim(d->>'institution'), ''), nullif(btrim(d->>'award'), ''),
                        nullif(btrim(d->>'field'), ''),
                        nullif(btrim(d->>'classOfDegree'), ''),
                        nullif(regexp_replace(coalesce(d->>'cgpa', ''), '[^0-9.]', '', 'g'), '')::numeric,
                        nullif(regexp_replace(coalesce(d->>'year', ''), '[^0-9]', '', 'g'), '')::int);
            END IF;
        END LOOP;
    END IF;

    IF jsonb_typeof(p_form->'referees') = 'array' THEN
        FOR ref IN SELECT * FROM jsonb_array_elements(p_form->'referees') LOOP
            IF coalesce(btrim(ref->>'name'), '') <> '' THEN
                INSERT INTO admissions.pg_referee (application_id, name, email, phone, institution, position)
                VALUES (v_app, btrim(ref->>'name'), nullif(btrim(coalesce(ref->>'email', '')), ''),
                        nullif(btrim(coalesce(ref->>'phone', '')), ''),
                        nullif(btrim(coalesce(ref->>'institution', '')), ''), nullif(btrim(coalesce(ref->>'position', '')), ''));
            END IF;
        END LOOP;
    END IF;

    v_ref := admissions.pg_new_fee_reference(v_app, 'APPLICATION');
    SELECT fr.amount INTO v_amt FROM admissions.pg_fee_reference fr WHERE fr.reference = v_ref;
    RETURN QUERY SELECT v_app,
                        (SELECT a.application_no FROM admissions.pg_application a WHERE a.id = v_app),
                        v_ref, v_amt;
END $function$;

CREATE OR REPLACE FUNCTION policy.application_session(p_type text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN admissions.pg_intake_session()
                WHEN p_type = 'CCE_APPLICATION' THEN policy.route_session('CCE')
                WHEN p_type = 'PRELIMINARY_SCIENCE_APPLICATION' THEN policy.route_session('PRELIMINARY_SCIENCE')
                WHEN p_type LIKE 'JUPEB%'
                    THEN coalesce((SELECT current_session FROM jupeb.setting WHERE session = '*'), policy.university_current_session())
                ELSE policy.intake_session() END
$function$;

DO $$
DECLARE v_from text := admissions.pg_current_session(); v_to text := admissions.pg_intake_session();
        w record; r record; n_win int := 0; n_app int := 0;
BEGIN
    IF v_to IS NULL OR v_to = v_from THEN
        RAISE NOTICE 'V452: the PG intake is the running session (%), nothing re-filed', v_from;
        RETURN;
    END IF;

    -- ── 1 · the Director of ICT's postgraduate application window, dates unchanged, where the intake has none ──
    IF EXISTS (SELECT 1 FROM policy.portal_window WHERE window_type = 'POSTGRADUATE_APPLICATION' AND session = v_from)
       AND NOT EXISTS (SELECT 1 FROM policy.portal_window WHERE window_type = 'POSTGRADUATE_APPLICATION' AND session = v_to) THEN
        UPDATE policy.portal_window SET session = v_to WHERE window_type = 'POSTGRADUATE_APPLICATION' AND session = v_from;
        UPDATE policy.portal_window_event SET session = v_to WHERE window_type = 'POSTGRADUATE_APPLICATION' AND session = v_from;
        FOR w IN SELECT * FROM policy.portal_window WHERE window_type = 'POSTGRADUATE_APPLICATION' AND session = v_to AND superseded_at IS NULL LOOP
            INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, new_opens_at, new_closes_at, new_late_until,
                                                    late_fee_enabled, reason, office, at)
            VALUES (w.id, 'POSTGRADUATE_APPLICATION', v_to, w.semester, 'EDIT', w.opens_at, w.closes_at, w.late_until, w.late_fee_enabled,
                    'Re-filed from ' || v_from || ' to ' || v_to || ' with its dates unchanged (V452): postgraduate applications are for the intake session', 'pgschool', now());
        END LOOP;
        n_win := 1;
    END IF;

    -- ── 2 · every application of the running session not admitted, with its applicant account ──
    FOR r IN SELECT a.id, a.applicant_id FROM admissions.pg_application a
              WHERE a.session = v_from AND a.student_id IS NULL AND a.admitted_at IS NULL AND a.state <> 'ADMITTED'
              ORDER BY a.created_at FOR UPDATE LOOP
        UPDATE admissions.pg_application SET session = v_to WHERE id = r.id;
        UPDATE admissions.pg_applicant p SET session = v_to
         WHERE p.id = r.applicant_id AND p.session = v_from
           AND NOT EXISTS (SELECT 1 FROM admissions.pg_application o WHERE o.applicant_id = p.id AND o.session = v_from);
        PERFORM admissions.pg_app_event(r.id, 'SESSION_REFILED',
            'Re-filed from ' || v_from || ' to ' || v_to || ': postgraduate applications are for the intake session. '
            || 'The application number and every payment (reference and amount) are unchanged.');
        n_app := n_app + 1;
    END LOOP;

    RAISE NOTICE 'V452: re-filed under %: % application window(s), % application(s); the admitted stay in %', v_to, n_win, n_app, v_from;
END $$;

COMMIT;

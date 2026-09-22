-- ═══════════════════════════════════════════════════════════════════════════
-- V217 — the postgraduate applicant's full prior-qualification history
--
--   V210 recorded the prior degree(s) an admission rests on as FIRST · MASTERS.
--   In practice an applicant carries more: a Master's applicant may already hold
--   a Master's in another or related field, or a Postgraduate Diploma bearing on
--   the programme; some carry an NCE or an HND that covers a deficiency. So the
--   prior-qualification list is widened to every kind a postgraduate applicant
--   might present, and gains a "field" (the discipline/course of study) beside
--   the award. The first degree is still kept on the application's own columns so
--   the existing desks read it unchanged; the child table now holds the rest.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'PG prior-qualification history widened (V217)', true);

-- ── 1 · the field of study, and the wider set of qualification kinds ─────────
ALTER TABLE admissions.pg_prior_degree ADD COLUMN IF NOT EXISTS field text NULL;
ALTER TABLE admissions.pg_prior_degree DROP CONSTRAINT IF EXISTS ck_pg_prior_kind;
ALTER TABLE admissions.pg_prior_degree ADD  CONSTRAINT ck_pg_prior_kind
    CHECK (kind IN ('NCE','ND','HND','FIRST','PGD','MASTERS','PHD','OTHER'));

-- ── 2 · the apply call records every qualification given, with its field ──────
CREATE OR REPLACE FUNCTION admissions.pg_apply(p_form jsonb)
RETURNS TABLE (application_id uuid, application_no text, reference text, amount numeric)
LANGUAGE plpgsql AS $$
DECLARE
    v_session text; v_prog text; v_cat text; v_award text; v_applicant uuid; v_app uuid;
    v_ref text; v_amt numeric; v_yy text; v_sex text; ref jsonb; d jsonb; v_kind text;
BEGIN
    v_session := coalesce(nullif(btrim(p_form->>'session'), ''),
                          (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), '2025/2026');
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
                                         email, phone, password_hash)
    VALUES (v_session, btrim(coalesce(p_form->>'surname', '')), btrim(coalesce(p_form->>'otherNames', '')),
            v_sex,
            CASE WHEN coalesce(p_form->>'dob', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (p_form->>'dob')::date END,
            nullif(btrim(coalesce(p_form->>'state', '')), ''), nullif(btrim(coalesce(p_form->>'lga', '')), ''),
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
                INSERT INTO admissions.pg_referee (application_id, name, email, institution, position)
                VALUES (v_app, btrim(ref->>'name'), nullif(btrim(coalesce(ref->>'email', '')), ''),
                        nullif(btrim(coalesce(ref->>'institution', '')), ''), nullif(btrim(coalesce(ref->>'position', '')), ''));
            END IF;
        END LOOP;
    END IF;

    v_ref := admissions.pg_new_fee_reference(v_app, 'APPLICATION');
    SELECT fr.amount INTO v_amt FROM admissions.pg_fee_reference fr WHERE fr.reference = v_ref;
    RETURN QUERY SELECT v_app,
                        (SELECT a.application_no FROM admissions.pg_application a WHERE a.id = v_app),
                        v_ref, v_amt;
END $$;

COMMIT;

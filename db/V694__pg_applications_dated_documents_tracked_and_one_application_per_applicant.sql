-- ═══════════════════════════════════════
-- V694 — Postgraduate applications: one per person a session, their documents tracked
--
--   The University's word of 29 October 2026, on the Postgraduate applications desk: "i want date of application to be displayed
--   here, also a status field for completion of upload of document or still pending or not uploaded, the ones that paid for
--   application but not uploaded yet should display, etc also some applicants applied twice or three times, they try to apply
--   again, find a way to restrict them from applying twice".
--
--   An applicant account is one email (uq_pg_applicant_email) and holds one application (uq_pg_application_per_applicant), so the
--   same person applying again opened a second account under another email: nothing tied the two together.
--
--   1 · admissions.pg_same_person: two applications are the same person's when two of three agree — the name (its words in any
--       order, case and punctuation aside: admissions.pg_name_key), the date of birth, the phone (0…, 234… or +234…:
--       admissions.pg_phone_key). A name alone never decides: two people may share one.
--   2 · admissions.pg_person_applications — the applications a person already holds in a session; pg_same_person_applications —
--       the others of an application's person; pg_session_duplicates — every application of a session with the others of its
--       person (the desk's "applied more than once").
--   3 · admissions.pg_apply (restated from V452) refuses a second application of the same person in the session, whatever the
--       email (PG_APP_DUPLICATE), naming the email of the first, masked, to sign in with; applications of one session are taken one
--       at a time so two at once cannot both pass. A phone given is kept in the 0… form.
--   4 · admissions.pg_new_fee_reference (restated from V675) issues no application-fee reference to an application whose person
--       has paid the fee on another application of the session (PG_APP_DUPLICATE_PAID) — an application made twice before this
--       is not paid for twice.
--   5 · admissions.pg_documents_required(level) — the documents an applicant uploads (as the portal's upload list asks them: the
--       passport photograph, the undergraduate certificate, the O'Level result, the birth certificate or declaration of age, the
--       NYSC certificate, the LGA certificate, and for an MPhil/PhD the higher degree); admissions.pg_document_state — where an
--       application's upload stands: COMPLETE, PENDING (some), NONE (fee paid, nothing uploaded) or FEE_UNPAID (the upload opens
--       once the fee is confirmed), with the documents missing.
--
--   Nothing is removed: an application made twice before this stays, flagged on the desk with its other number(s) for the School.
-- ═══════════════════════════════════════
BEGIN;

-- ── 1 · the same person ───────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_name_key(p_surname text, p_other_names text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $function$
    -- the name's words, in capitals, each once, in alphabetical order: "Abata, Catherine Ema" = "CATHERINE EMA ABATA"
    SELECT nullif(array_to_string(ARRAY(
        SELECT DISTINCT w FROM unnest(regexp_split_to_array(upper(coalesce(p_surname, '') || ' ' || coalesce(p_other_names, '')), '[^[:alpha:]]+')) w
         WHERE w <> '' ORDER BY w), ' '), '')
$function$;
COMMENT ON FUNCTION admissions.pg_name_key(text, text) IS
  'V694: a postgraduate applicant''s name as compared for one application per person: its words in capitals, each once, in alphabetical order.';

CREATE OR REPLACE FUNCTION admissions.pg_phone_key(p_phone text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $function$
    -- a Nigerian number in its 0… form, from 0…, 234…, +234… or the ten digits after the 0; anything else is no number
    SELECT CASE WHEN d ~ '^0[0-9]{10}$' THEN d
                WHEN d ~ '^234[0-9]{10}$' THEN '0' || substr(d, 4)
                WHEN d ~ '^[789][0-9]{9}$' THEN '0' || d END
      FROM (SELECT regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g') AS d) x
$function$;
COMMENT ON FUNCTION admissions.pg_phone_key(text) IS
  'V694: a phone number in its 0… form (from 0…, 234… or +234…), or NULL — as compared for one application per person.';

CREATE OR REPLACE FUNCTION admissions.pg_same_person(p_name1 text, p_dob1 date, p_phone1 text, p_name2 text, p_dob2 date, p_phone2 text)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $function$
    -- two of three agree; the name and the phone as pg_name_key and pg_phone_key give them, an unknown one agreeing with nothing
    SELECT coalesce(p_name1 = p_name2, false)::int + coalesce(p_dob1 = p_dob2, false)::int + coalesce(p_phone1 = p_phone2, false)::int >= 2
$function$;
COMMENT ON FUNCTION admissions.pg_same_person(text, date, text, text, date, text) IS
  'V694: whether two postgraduate applicants are one person — two of name (pg_name_key), date of birth and phone (pg_phone_key) agree. A name alone never decides.';

-- ── 2 · a person's applications ──────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_person_applications(p_session text, p_surname text, p_other_names text, p_dob date, p_phone text,
                                                             p_except uuid DEFAULT NULL)
RETURNS TABLE (application_id uuid, application_no text, email text, fee_paid boolean, applied_at timestamptz, matched_on text)
LANGUAGE sql STABLE AS $function$
    WITH me AS (SELECT admissions.pg_name_key(p_surname, p_other_names) AS n, admissions.pg_phone_key(p_phone) AS ph),
         them AS (
        SELECT a.id, a.application_no, p.email, a.fee_confirmed_at IS NOT NULL AS paid, coalesce(a.submitted_at, a.created_at) AS at,
               admissions.pg_name_key(p.surname, p.other_names) AS n, p.date_of_birth AS d, admissions.pg_phone_key(p.phone) AS ph
          FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id
         WHERE a.session = p_session AND a.id IS DISTINCT FROM p_except)
    SELECT t.id, t.application_no, t.email, t.paid, t.at,
           concat_ws(', ', CASE WHEN t.n = me.n THEN 'name' END, CASE WHEN t.d = p_dob THEN 'date of birth' END,
                           CASE WHEN t.ph = me.ph THEN 'phone' END)
      FROM them t CROSS JOIN me
     WHERE admissions.pg_same_person(t.n, t.d, t.ph, me.n, p_dob, me.ph)
     ORDER BY t.paid DESC, t.at, t.application_no
$function$;
COMMENT ON FUNCTION admissions.pg_person_applications(text, text, text, date, text, uuid) IS
  'V694: the applications a person (name, date of birth, phone) holds in a session, paid first then oldest — by admissions.pg_same_person.';

CREATE OR REPLACE FUNCTION admissions.pg_same_person_applications(p_application uuid)
RETURNS TABLE (application_id uuid, application_no text, email text, fee_paid boolean, applied_at timestamptz, matched_on text)
LANGUAGE sql STABLE AS $function$
    SELECT x.* FROM admissions.pg_application a
      JOIN admissions.pg_applicant p ON p.id = a.applicant_id
     CROSS JOIN LATERAL admissions.pg_person_applications(a.session, p.surname, p.other_names, p.date_of_birth, p.phone, a.id) x
     WHERE a.id = p_application
$function$;
COMMENT ON FUNCTION admissions.pg_same_person_applications(uuid) IS
  'V694: the other applications of this application''s person in its session.';

CREATE OR REPLACE FUNCTION admissions.pg_session_duplicates(p_session text)
RETURNS TABLE (application_id uuid, also_applied text, times int)
LANGUAGE sql STABLE AS $function$
    -- every application of the session that shares its person with another, the others' numbers oldest first
    WITH k AS (
        SELECT a.id, a.application_no, coalesce(a.submitted_at, a.created_at) AS at,
               admissions.pg_name_key(p.surname, p.other_names) AS n, p.date_of_birth AS d, admissions.pg_phone_key(p.phone) AS ph
          FROM admissions.pg_application a JOIN admissions.pg_applicant p ON p.id = a.applicant_id
         WHERE a.session = p_session)
    SELECT x.id, string_agg(y.application_no, ', ' ORDER BY y.at, y.application_no), count(*)::int + 1
      FROM k x JOIN k y ON y.id <> x.id AND admissions.pg_same_person(x.n, x.d, x.ph, y.n, y.d, y.ph)
     GROUP BY x.id
$function$;
COMMENT ON FUNCTION admissions.pg_session_duplicates(text) IS
  'V694: the applications of a session made by a person who made another — with the other numbers and how many the person made.';

CREATE OR REPLACE FUNCTION admissions.pg_mask_email(p_email text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $function$
    -- "ada.bem@gmail.com" → "a***m@gmail.com": enough for its owner to know it, not enough for another to use it
    SELECT CASE WHEN p_email IS NULL OR strpos(p_email, '@') = 0 THEN NULL
                WHEN strpos(p_email, '@') <= 2 THEN '***' || substr(p_email, strpos(p_email, '@'))
                ELSE left(p_email, 1) || '***' || substr(p_email, strpos(p_email, '@') - 1) END
$function$;

-- ── 3 · the public application: once a session per person ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_apply(p_form jsonb)
 RETURNS TABLE(application_id uuid, application_no text, reference text, amount numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_session text; v_prog text; v_cat text; v_award text; v_applicant uuid; v_app uuid;
    v_ref text; v_amt numeric; v_yy text; v_sex text; ref jsonb; d jsonb; v_kind text;
    v_dob date; v_prior record;
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
    v_dob := CASE WHEN coalesce(p_form->>'dob', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (p_form->>'dob')::date END;

    -- V694: one application per person a session. Applications of the session are taken one at a time, so the same person
    -- applying twice at once cannot pass twice; then any application of theirs already made refuses this one, whatever its email.
    PERFORM pg_advisory_xact_lock(hashtext('admissions.pg_apply ' || v_session));
    SELECT * INTO v_prior FROM admissions.pg_person_applications(v_session, p_form->>'surname', p_form->>'otherNames', v_dob, p_form->>'phone') LIMIT 1;
    IF FOUND THEN
        RAISE EXCEPTION 'PG_APP_DUPLICATE: you have already applied for the % session, with the email %. One application is taken from each applicant in a session',
              v_session, admissions.pg_mask_email(v_prior.email)
              USING ERRCODE = '23514',
                    HINT = 'Sign in with that email to pay for and continue your application; if you have forgotten its password, use "Forgot your password?" on the sign-in page. To change your programme, write to the School of Postgraduate Studies.';
    END IF;

    INSERT INTO admissions.pg_applicant (session, surname, other_names, sex, date_of_birth, state_of_origin, lga,
                                         nationality, contact_address, email, phone, password_hash)
    VALUES (v_session, btrim(coalesce(p_form->>'surname', '')), btrim(coalesce(p_form->>'otherNames', '')),
            v_sex, v_dob,
            nullif(btrim(coalesce(p_form->>'state', '')), ''), nullif(btrim(coalesce(p_form->>'lga', '')), ''),
            left(nullif(btrim(coalesce(p_form->>'nationality', '')), ''), 80),
            -- the address on one line: its line breaks become commas, its spaces single
            left(nullif(btrim(regexp_replace(regexp_replace(coalesce(p_form->>'contactAddress', ''), '[\s,]*[\r\n]+[\s,]*', ', ', 'g'),
                                             '\s+', ' ', 'g'), ' ,'), ''), 300),
            lower(btrim(coalesce(p_form->>'email', ''))),
            -- V694: a phone given as 234… or +234… kept in its 0… form; anything else as typed (the table's check refuses it)
            coalesce(admissions.pg_phone_key(p_form->>'phone'), nullif(btrim(coalesce(p_form->>'phone', '')), '')),
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

-- ── 4 · an application made twice is not paid for twice ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_new_fee_reference(p_application uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_session text; v_amt numeric; v_ref text; v_rule record; v_try int; v_top bigint; v_paid record;
BEGIN
    SELECT session INTO v_session FROM admissions.pg_application WHERE id = p_application;
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'no such postgraduate application';
    END IF;
    -- V694: the application fee is paid once by a person in a session; one of theirs paid, another made before V694 is not paid too
    IF p_kind = 'APPLICATION' THEN
        SELECT * INTO v_paid FROM admissions.pg_same_person_applications(p_application) x WHERE x.fee_paid LIMIT 1;
        IF FOUND THEN
            RAISE EXCEPTION 'PG_APP_DUPLICATE_PAID: you have already paid the application fee for the % session on another application, made with the email %',
                  v_session, admissions.pg_mask_email(v_paid.email)
                  USING ERRCODE = '23514',
                        HINT = 'Sign in with that email to continue that application. One application is taken from each applicant in a session; to change your programme, write to the School of Postgraduate Studies.';
        END IF;
    END IF;
    -- V675: the same fee paid on the old portal is being verified; not paid twice meanwhile
    IF EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = p_application AND x.kind = p_kind AND x.state = 'REQUIRES_REVIEW') THEN
        RAISE EXCEPTION 'PG_FEE_UNDER_REVIEW: the % fee you paid on the old portal is being verified by the Bursary; you do not pay it again meanwhile', lower(p_kind)
              USING ERRCODE = '23514', HINT = 'You are told by email once it is verified.';
    END IF;
    IF p_kind = 'CHECKING' AND EXISTS (SELECT 1 FROM admissions.pg_legacy_application l WHERE l.application_id = p_application AND l.decided_on_old_portal) THEN
        RAISE EXCEPTION 'PG_FEE_NOT_NEEDED: your admission was decided on the old portal and is read here without the checking fee' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO v_rule FROM admissions.pg_fee_rule(v_session);
    v_amt := CASE p_kind WHEN 'ACCEPTANCE' THEN v_rule.acceptance_fee
                         WHEN 'CHECKING'   THEN v_rule.checking_fee
                         ELSE v_rule.application_fee END;
    -- V564: the series is the session's but the reference names no session, so a new session's series draws numbers an earlier
    -- one issued: a taken reference carries the series past every postgraduate fee reference's number, and is drawn again
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-PG' || CASE p_kind WHEN 'ACCEPTANCE' THEN 'ACC' WHEN 'CHECKING' THEN 'CHK' ELSE 'APP' END || '-'
                 || lpad(platform.next_number('PG_FEEREF', 'UNIVERSITY', v_session)::text, 6, '0');
        INSERT INTO admissions.pg_fee_reference (application_id, kind, reference, amount, expires_at)
        VALUES (p_application, p_kind, v_ref, v_amt, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
        SELECT max(substring(f.reference FROM '-([0-9]+)$')::bigint) INTO v_top
          FROM admissions.pg_fee_reference f WHERE f.reference ~ '^MOAUM-PG(APP|CHK|ACC)-[0-9]+$';
        UPDATE platform.number_series SET next_value = greatest(next_value, coalesce(v_top, 0) + 1)
         WHERE kind = 'PG_FEEREF' AND scope = 'UNIVERSITY' AND session = v_session;
    END LOOP;
    RAISE EXCEPTION 'PG_FEE_REFERENCE_EXHAUSTED: no free % reference was found in fifty draws', lower(p_kind) USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, tell the Directorate of ICT.';
END;
$function$;

-- ── 5 · the documents an applicant uploads, and where an application's upload stands ────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.pg_documents_required(p_entry_level int)
RETURNS text[]
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $function$
    -- as the portal's upload list asks them (the change of name is only for an applicant whose name changed); the higher
    -- degree for an MPhil/PhD applicant, who enters on a Master's
    SELECT ARRAY['PASSPORT', 'UNDERGRAD_CERT', 'OLEVEL', 'BIRTH_CERTIFICATE', 'NYSC', 'LGA_CERTIFICATE']
           || CASE WHEN p_entry_level >= 900 THEN ARRAY['HIGHER_DEGREE'] ELSE ARRAY[]::text[] END
$function$;
COMMENT ON FUNCTION admissions.pg_documents_required(int) IS
  'V694: the documents a postgraduate applicant uploads, by entry level — the passport, undergraduate certificate, O''Level, birth certificate, NYSC, LGA certificate, and the higher degree for MPhil/PhD.';

CREATE OR REPLACE FUNCTION admissions.pg_document_state(p_application uuid)
RETURNS TABLE (state text, required int, uploaded int, missing text)
LANGUAGE sql STABLE AS $function$
    SELECT CASE WHEN cardinality(m.missing) = 0 THEN 'COMPLETE'
                WHEN a.fee_confirmed_at IS NULL THEN 'FEE_UNPAID'
                WHEN m.got = 0 THEN 'NONE'
                ELSE 'PENDING' END,
           cardinality(r.req), m.got, nullif(array_to_string(m.missing, ','), '')
      FROM admissions.pg_application a
     CROSS JOIN LATERAL (SELECT admissions.pg_documents_required(a.entry_level) AS req) r
     CROSS JOIN LATERAL (SELECT coalesce(array_agg(DISTINCT d.kind), '{}') AS kinds FROM admissions.pg_document d WHERE d.application_id = a.id) h
     CROSS JOIN LATERAL (SELECT count(*) FILTER (WHERE u.k = ANY (h.kinds))::int AS got,
                                coalesce(array_agg(u.k ORDER BY u.o) FILTER (WHERE NOT u.k = ANY (h.kinds)), '{}') AS missing
                           FROM unnest(r.req) WITH ORDINALITY u(k, o)) m
     WHERE a.id = p_application
$function$;
COMMENT ON FUNCTION admissions.pg_document_state(uuid) IS
  'V694: where a postgraduate application''s document upload stands — COMPLETE, PENDING (some), NONE (fee paid, nothing uploaded) or FEE_UNPAID — with the required, the uploaded and the missing kinds.';

COMMIT;

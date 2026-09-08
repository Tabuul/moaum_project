-- ═══════════════════════════════════════════════════════════════════════════
-- V021 — the applicant's journey, from the JAMB number to the register
--
-- The applicant side of admissions (proto/part13.html), built to match what
-- the Academic Office already runs:
--
--   · Post-UTME registration starts from the JAMB registration number and
--     nothing else. The number is looked for on the CAPS list the Academic
--     Office loaded; the name, the programme and the list are READ from it,
--     never typed. Nobody is verified while no list is loaded.
--   · Registering creates the candidate record from the CAPS row — which is
--     the record the reconciliation has been asking for — and opens the
--     application under an application number.
--   · The application fee is a reference this portal generates. There is no
--     payment gateway on the portal yet, so the reference is confirmed by
--     the Bursary or the Academic Office against the bank's record, and the
--     confirmation is an attributed act. The form opens when it is confirmed.
--   · The form: biodata from JAMB, the O'Level results JAMB sent (unedited),
--     next of kin, five documents, a declaration. Submitted once.
--   · Screening batches are the Academic Office's; seats are assigned over
--     the submitted applications. Scores are entered per candidate and
--     released together. The aggregate is computed under the session's
--     admission settings (paragraph 2.6), never stored.
--   · The Board's decision per application, released together; an offer
--     makes the candidate ADMITTED on the strength of the CAPS row. Accepting
--     is the undertaking and the acceptance fee, and makes the candidate
--     ACCEPTED — the Academic Office then brings them onto the register
--     (people.intake) with an admission number, exactly as it does today.
--   · Clearance is the Registry's: six documents seen, each an act.
--   · The stage of an application is COMPUTED from these facts, never stored.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- the applicant is an office the audit spine knows, so every act is attributed;
-- the spine refuses an unattributed write, including this one
DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'ict', true);
    PERFORM set_config('moaum.reason', 'The applicant as an office the audit spine knows (V021), Directorate of ICT', true);
END $seed$;

INSERT INTO ref.office (code, label, scope_kind) VALUES ('applicant', 'Applicant', 'institution')
ON CONFLICT (code) DO NOTHING;

-- ── the fees, stated per session ────────────────────────────────────────
CREATE TABLE admissions.applicant_fee (
    session         text PRIMARY KEY,
    application_fee numeric(12,2) NOT NULL,
    portal_charge   numeric(12,2) NOT NULL,
    acceptance_fee  numeric(12,2) NOT NULL,
    stated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_afee_amounts CHECK (application_fee >= 0 AND portal_charge >= 0 AND acceptance_fee >= 0)
);
SELECT audit.attach('admissions.applicant_fee');

CREATE OR REPLACE FUNCTION admissions.applicant_fee_rule(p_session text)
RETURNS TABLE (stated boolean, application_fee numeric, portal_charge numeric, acceptance_fee numeric)
LANGUAGE sql STABLE AS $$
    SELECT true, f.application_fee, f.portal_charge, f.acceptance_fee FROM admissions.applicant_fee f WHERE f.session = p_session
    UNION ALL
    SELECT false, 2000, 300, 25000 WHERE NOT EXISTS (SELECT 1 FROM admissions.applicant_fee f WHERE f.session = p_session);
$$;

-- ── the account ─────────────────────────────────────────────────────────
CREATE TABLE admissions.applicant_account (
    id               uuid PRIMARY KEY,
    session          text NOT NULL,
    candidate_id     uuid NOT NULL UNIQUE REFERENCES admissions.candidate(id),
    jamb_key         text NOT NULL,
    email            text NOT NULL,
    phone            text NOT NULL,
    password_hash    text NOT NULL,
    failed_attempts  int  NOT NULL DEFAULT 0,
    locked_until     timestamptz NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    last_signed_in_at timestamptz NULL,
    CONSTRAINT uq_applicant_per_session UNIQUE (session, jamb_key),
    CONSTRAINT ck_applicant_phone CHECK (phone ~ '^0[0-9]{10}$'),
    CONSTRAINT ck_applicant_email CHECK (email ~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$'),
    CONSTRAINT ck_applicant_hash  CHECK (password_hash LIKE '$2%$12$%')
);
CREATE UNIQUE INDEX uq_applicant_email ON admissions.applicant_account (lower(email));
SELECT audit.exempt('admissions.applicant_account',
    'Carries a password hash; a hash copied into a longer-lived trail is a second place to steal it from. The acts on the application are on the spine.');

CREATE TABLE admissions.applicant_event (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id uuid NULL,
    identifier text NOT NULL,
    outcome    text NOT NULL,
    ip         text NULL,
    at         timestamptz NOT NULL DEFAULT now()
);
SELECT audit.exempt('admissions.applicant_event', 'The sign-in log itself; auditing the audit of sign-ins doubles every row.');

-- ── the application ─────────────────────────────────────────────────────
CREATE TABLE admissions.screening_batch (
    id         uuid PRIMARY KEY,
    session    text NOT NULL,
    label      text NOT NULL,
    held_on    date NOT NULL,
    starts_at  time NOT NULL,
    ends_at    time NOT NULL,
    venue      text NOT NULL,
    capacity   int  NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_batch_label UNIQUE (session, label),
    CONSTRAINT ck_batch_capacity CHECK (capacity BETWEEN 1 AND 5000),
    CONSTRAINT ck_batch_times CHECK (ends_at > starts_at)
);
SELECT audit.attach('admissions.screening_batch');

CREATE TABLE admissions.application (
    id                      uuid PRIMARY KEY,
    account_id              uuid NOT NULL UNIQUE REFERENCES admissions.applicant_account(id),
    candidate_id            uuid NOT NULL UNIQUE REFERENCES admissions.candidate(id),
    session                 text NOT NULL,
    application_no          text NOT NULL UNIQUE,
    next_of_kin             text NULL,
    fee_confirmed_at        timestamptz NULL,
    submitted_at            timestamptz NULL,
    declaration_ip          text NULL,
    screening_batch_id      uuid NULL REFERENCES admissions.screening_batch(id),
    seat                    text NULL,
    screening_score         numeric(5,2) NULL,
    score_entered_at        timestamptz NULL,
    score_released_at       timestamptz NULL,
    decision                text NULL,
    decision_note           text NULL,
    decided_at              timestamptz NULL,
    decision_released_at    timestamptz NULL,
    undertaking_at          timestamptz NULL,
    acceptance_confirmed_at timestamptz NULL,
    accepted_at             timestamptz NULL,
    declined_at             timestamptz NULL,
    cleared_at              timestamptz NULL,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_app_no CHECK (application_no ~ '^APP/[0-9]{2}/[0-9]{6}$'),
    CONSTRAINT ck_app_score CHECK (screening_score IS NULL OR screening_score BETWEEN 0 AND 100),
    CONSTRAINT ck_app_decision CHECK (decision IS NULL OR decision IN ('OFFERED','WAITING','NOT_OFFERED')),
    CONSTRAINT ck_app_seat CHECK ((screening_batch_id IS NULL) = (seat IS NULL)),
    CONSTRAINT ck_app_released_decided CHECK (decision_released_at IS NULL OR decision IS NOT NULL)
);
CREATE INDEX ix_application_session ON admissions.application (session);
SELECT audit.attach('admissions.application');

CREATE TABLE admissions.fee_reference (
    id             uuid PRIMARY KEY,
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    kind           text NOT NULL,
    reference      text NOT NULL UNIQUE,
    amount         numeric(12,2) NOT NULL,
    generated_at   timestamptz NOT NULL DEFAULT now(),
    expires_at     timestamptz NOT NULL,
    confirmed_at   timestamptz NULL,
    confirmed_by   uuid NULL,
    channel        text NULL,
    note           text NULL,
    CONSTRAINT ck_fref_kind CHECK (kind IN ('APPLICATION','ACCEPTANCE')),
    CONSTRAINT ck_fref_confirmed CHECK (confirmed_at IS NULL OR (confirmed_by IS NOT NULL AND channel IS NOT NULL))
);
CREATE INDEX ix_fref_application ON admissions.fee_reference (application_id);
SELECT audit.attach('admissions.fee_reference');

CREATE TABLE admissions.application_document (
    id             uuid PRIMARY KEY,
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    kind           text NOT NULL,
    filename       text NOT NULL,
    content_type   text NOT NULL,
    bytes          bigint NOT NULL,
    uploaded_at    timestamptz NOT NULL DEFAULT now(),
    status         text NOT NULL DEFAULT 'PENDING',
    reviewed_at    timestamptz NULL,
    reviewed_by    uuid NULL,
    review_note    text NULL,
    superseded_at  timestamptz NULL,
    CONSTRAINT ck_doc_kind CHECK (kind IN ('OLEVEL_STATEMENT','BIRTH_CERT','LGA_ID','JAMB_SLIP','PASSPORT')),
    CONSTRAINT ck_doc_status CHECK (status IN ('PENDING','ACCEPTED','REJECTED')),
    CONSTRAINT ck_doc_bytes CHECK (bytes BETWEEN 1 AND 2097152),
    CONSTRAINT ck_doc_type CHECK (content_type IN ('application/pdf','image/jpeg','image/png')),
    CONSTRAINT ck_doc_reviewed CHECK (status = 'PENDING' OR (reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL)),
    CONSTRAINT ck_doc_rejected_note CHECK (status <> 'REJECTED' OR review_note IS NOT NULL)
);
CREATE UNIQUE INDEX uq_doc_current ON admissions.application_document (application_id, kind) WHERE superseded_at IS NULL;
SELECT audit.attach('admissions.application_document');

CREATE TABLE admissions.application_document_blob (
    document_id uuid PRIMARY KEY REFERENCES admissions.application_document(id),
    content     bytea NOT NULL
);
SELECT audit.exempt('admissions.application_document_blob',
    'The file itself, up to 2 MB; the fact of it — name, size, status, who reviewed it — is on the spine in application_document.');

CREATE TABLE admissions.clearance_document (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    item           text NOT NULL,
    state          text NOT NULL DEFAULT 'NOT_PRESENTED',
    note           text NULL,
    decided_at     timestamptz NULL,
    decided_by     uuid NULL,
    CONSTRAINT uq_clearance_item UNIQUE (application_id, item),
    CONSTRAINT ck_cl_item CHECK (item IN ('OLEVEL_ORIGINAL','BIRTH_CERT','LGA_ID','JAMB_LETTER','MEDICAL','PHOTOGRAPHS')),
    CONSTRAINT ck_cl_state CHECK (state IN ('NOT_PRESENTED','VERIFIED','QUERY')),
    CONSTRAINT ck_cl_query_note CHECK (state <> 'QUERY' OR note IS NOT NULL)
);
SELECT audit.attach('admissions.clearance_document');

-- ── who is acting ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.acting_person()
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('moaum.actor_id', true), '')::uuid;
$$;

-- ── the lookup: the number against the list JAMB sent ───────────────────
-- 'nolist'     nothing is loaded for the session, so nobody can be verified
-- 'none'       a readable number that is on no list
-- 'found'      on a list, and free to register
-- 'registered' on a list, and already holds an account
CREATE OR REPLACE FUNCTION admissions.applicant_lookup(p_session text, p_jamb_key text)
RETURNS TABLE (state text, row_id uuid, surname text, other_names text, programme_code text, programme text,
               list_kind text, entry_mode text, sex text, state_of_origin text, lga text, aggregate int)
LANGUAGE plpgsql STABLE AS $$
DECLARE key text := upper(btrim(p_jamb_key)); r record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM admissions.caps_row_live x WHERE x.session = p_session) THEN
        RETURN QUERY SELECT 'nolist'::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::int;
        RETURN;
    END IF;
    SELECT x.id, x.surname, x.other_names, x.jamb_code, p.name AS programme, b.list_kind, x.entry_mode,
           x.sex, x.state_of_origin, x.lga, x.aggregate
      INTO r
      FROM admissions.caps_row_live x
      JOIN admissions.caps_batch b ON b.id = x.batch_id
      LEFT JOIN ref.programme p ON p.code = x.jamb_code
     WHERE x.session = p_session AND x.jamb_key = key
     ORDER BY b.uploaded_at DESC LIMIT 1;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'none'::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::int;
        RETURN;
    END IF;
    RETURN QUERY SELECT CASE WHEN EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.session = p_session AND a.jamb_key = key)
                             THEN 'registered' ELSE 'found' END,
                        r.id, r.surname, r.other_names, r.jamb_code, r.programme, r.list_kind, r.entry_mode, r.sex, r.state_of_origin, r.lga, r.aggregate;
END $$;

-- ── registering: the candidate record from the CAPS row, the account, the application ──
CREATE OR REPLACE FUNCTION admissions.register_applicant(p_session text, p_jamb_key text, p_email text, p_phone text, p_hash text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE key text := upper(btrim(p_jamb_key)); f record; v_candidate uuid; v_account uuid := gen_random_uuid();
        v_app uuid := gen_random_uuid(); v_no text; v_yy text := substr(p_session, 3, 2);
BEGIN
    SELECT * INTO f FROM admissions.applicant_lookup(p_session, key);
    IF f.state = 'nolist' THEN
        RAISE EXCEPTION 'nobody can be verified: no admission list is loaded for %', p_session
        USING ERRCODE = '23514', HINT = 'The Academic Office loads the list JAMB sent on the JAMB admission lists screen. Until it does, this screen will not guess.';
    ELSIF f.state = 'none' THEN
        RAISE EXCEPTION 'the number % is not on the list JAMB sent the University for %', key, p_session
        USING ERRCODE = '23514', HINT = 'A digit may be wrong, the University may not have been chosen on CAPS, or the tranche has not reached us yet. Do not travel to the campus over this.';
    ELSIF f.state = 'registered' THEN
        RAISE EXCEPTION 'an application account already exists for %', key
        USING ERRCODE = '23505', HINT = 'Sign in with the email and password you chose. A second account would invalidate both.';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = lower(btrim(p_email))) THEN
        RAISE EXCEPTION 'the address % already belongs to an application account', btrim(p_email)
        USING ERRCODE = '23505', HINT = 'Sign in with it, or use another address.';
    END IF;

    SELECT c.id INTO v_candidate FROM admissions.candidate c WHERE c.session = p_session AND c.jamb_key = key;
    IF v_candidate IS NULL THEN
        v_candidate := gen_random_uuid();
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
        VALUES (v_candidate, p_session, key, f.surname, f.other_names, coalesce(f.programme, f.programme_code),
                CASE WHEN f.entry_mode IN ('UTME','DIRECT_ENTRY','TRANSFER') THEN f.entry_mode ELSE 'UTME' END,
                CASE WHEN f.entry_mode = 'UTME' THEN 100 ELSE 200 END, 'PROPOSED', f.row_id);
    END IF;

    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
    VALUES (v_account, p_session, v_candidate, key, btrim(p_email), p_phone, p_hash);

    v_no := 'APP/' || v_yy || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', p_session)::text, 6, '0');
    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no)
    VALUES (v_app, v_account, v_candidate, p_session, v_no);
    RETURN v_account;
END $$;

-- ── the stage, computed ─────────────────────────────────────────────────
-- 0 account · 1 fee confirmed · 2 submitted · 3 slip issued · 4 score released ·
-- 5 decision released · 6 offer accepted · 7 cleared · 8 registered · 9 matriculated
CREATE OR REPLACE FUNCTION admissions.application_stage(p_app uuid)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN a.fee_confirmed_at IS NULL THEN 0
        WHEN a.submitted_at IS NULL THEN 1
        WHEN a.screening_batch_id IS NULL THEN 2
        WHEN a.score_released_at IS NULL THEN 3
        WHEN a.decision_released_at IS NULL THEN 4
        WHEN a.accepted_at IS NULL THEN 5
        WHEN a.cleared_at IS NULL THEN 6
        WHEN NOT EXISTS (SELECT 1 FROM people.student s
                           JOIN registration.course_registration r ON r.student_id = s.id AND r.session = a.session
                          WHERE s.candidate_id = a.candidate_id AND r.status IN ('APPROVED','LOCKED')) THEN 7
        WHEN NOT EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.candidate_id AND s.matric_no IS NOT NULL) THEN 8
        ELSE 9 END
      FROM admissions.application a WHERE a.id = p_app;
$$;

-- ── the fee reference ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    v_amount := CASE p_kind WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge ELSE fee.acceptance_fee END;
    v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
             || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
    VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours');
    RETURN v_ref;
END $$;

-- confirmed by an office against the bank's record; an attributed act
CREATE OR REPLACE FUNCTION admissions.confirm_fee(p_reference text, p_channel text, p_note text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r admissions.fee_reference; a admissions.application;
BEGIN
    SELECT * INTO r FROM admissions.fee_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN RAISE EXCEPTION 'no reference % was generated by this portal', p_reference USING ERRCODE = '23503',
        HINT = 'Only a reference this portal generated is confirmed; money sent anywhere else did not reach the University.'; END IF;
    IF r.confirmed_at IS NOT NULL THEN RETURN 'already confirmed'; END IF;
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'a payment is confirmed by a person' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.fee_reference SET confirmed_at = now(), confirmed_by = admissions.acting_person(),
           channel = p_channel, note = p_note WHERE id = r.id;
    SELECT * INTO a FROM admissions.application WHERE id = r.application_id;
    IF r.kind = 'APPLICATION' THEN
        UPDATE admissions.application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = a.id;
    ELSE
        UPDATE admissions.application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = a.id;
        PERFORM admissions.settle_acceptance(a.id);
    END IF;
    RETURN 'confirmed';
END $$;

-- ── submitting ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.submit_application(p_app uuid, p_ip text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application; missing text; rejected text;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.submitted_at IS NOT NULL THEN RETURN 'already submitted'; END IF;
    IF a.fee_confirmed_at IS NULL THEN
        RAISE EXCEPTION 'the form opens when the application fee is confirmed' USING ERRCODE = '23514',
            HINT = 'Pay against the reference this portal generated; the Bursary confirms it against the bank''s record.';
    END IF;
    IF a.next_of_kin IS NULL OR btrim(a.next_of_kin) = '' THEN
        RAISE EXCEPTION 'the next of kin is not given' USING ERRCODE = '23514', HINT = 'Name and phone number of your next of kin, under Biodata.';
    END IF;
    SELECT string_agg(k, ', ') INTO missing FROM unnest(ARRAY['OLEVEL_STATEMENT','BIRTH_CERT','LGA_ID','JAMB_SLIP','PASSPORT']) k
     WHERE NOT EXISTS (SELECT 1 FROM admissions.application_document d WHERE d.application_id = p_app AND d.kind = k AND d.superseded_at IS NULL);
    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'documents not yet uploaded: %', missing USING ERRCODE = '23514', HINT = 'All five documents are uploaded before the application is submitted.';
    END IF;
    SELECT string_agg(d.kind, ', ') INTO rejected FROM admissions.application_document d
     WHERE d.application_id = p_app AND d.superseded_at IS NULL AND d.status = 'REJECTED';
    IF rejected IS NOT NULL THEN
        RAISE EXCEPTION 'a document was rejected and not replaced: %', rejected USING ERRCODE = '23514', HINT = 'Upload a replacement that meets the stated requirement.';
    END IF;
    UPDATE admissions.application SET submitted_at = now(), declaration_ip = p_ip WHERE id = p_app;
    RETURN 'submitted';
END $$;

-- ── screening ───────────────────────────────────────────────────────────
-- seats over the submitted, unseated applications of the session, in application order, up to capacity
CREATE OR REPLACE FUNCTION admissions.assign_screening(p_batch uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE b admissions.screening_batch; taken int; n int := 0; r record;
BEGIN
    SELECT * INTO b FROM admissions.screening_batch WHERE id = p_batch;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    SELECT count(*) INTO taken FROM admissions.application WHERE screening_batch_id = p_batch;
    FOR r IN SELECT a.id FROM admissions.application a
              WHERE a.session = b.session AND a.submitted_at IS NOT NULL AND a.screening_batch_id IS NULL
              ORDER BY a.application_no
    LOOP
        EXIT WHEN taken + n >= b.capacity;
        n := n + 1;
        UPDATE admissions.application SET screening_batch_id = p_batch, seat = b.label || '-' || lpad((taken + n)::text, 3, '0')
         WHERE id = r.id;
    END LOOP;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION admissions.release_scores(p_session text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    -- the result of every seated candidate: the CBT score where one was sat, else the O'Level score under the session's grading
    UPDATE admissions.application SET score_released_at = now()
     WHERE session = p_session AND screening_batch_id IS NOT NULL AND score_released_at IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- the cut-off where the session's settings state one; nothing where they do not, rather than an error on the slip
CREATE OR REPLACE FUNCTION admissions.cutoff_or_null(p_session text, p_programme text)
RETURNS int
LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF p_programme IS NULL THEN RETURN NULL; END IF;
    RETURN admissions.cutoff_for(p_session, p_programme);
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END $$;

-- the screening result: the aggregate under paragraph 2.6, the cut-off, the merit position
-- The screening component of one application, out of 100: the CBT score where
-- one was sat and entered, else the O'Level score under the session's grading
-- (V020) scaled over its ceiling — the subjects counted at the best grade, and
-- the one-sitting bonus. This is the "OL/TEST SCORE" of JAMB's admission
-- template, and the same rule the Academic Office's own screen applies.
CREATE OR REPLACE FUNCTION admissions.screening_component(p_app uuid)
RETURNS TABLE (screening numeric, source text, olevel_total int, olevel_ceiling int)
LANGUAGE sql STABLE AS $$
    WITH a AS (
        SELECT ap.screening_score, ap.session, c.jamb_key,
               (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code
          FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
    rule AS (SELECT r.* FROM a, admissions.olevel_rule(a.session) r),
    ceiling AS (
        SELECT (rule.subjects_counted * greatest(admissions.olevel_points(a.session, 'A1'), 1) + rule.bonus_one_sitting) AS top
          FROM a, rule),
    ol AS (SELECT s.total FROM a, admissions.olevel_score(a.session, a.jamb_key, a.code) s)
    SELECT CASE WHEN a.screening_score IS NOT NULL THEN a.screening_score
                WHEN ol.total > 0 THEN round((ol.total::numeric / ceiling.top) * 100, 2)
                ELSE NULL END,
           CASE WHEN a.screening_score IS NOT NULL THEN 'CBT' WHEN ol.total > 0 THEN 'OLEVEL' ELSE 'NONE' END,
           ol.total, ceiling.top
      FROM a, ol, ceiling;
$$;

CREATE OR REPLACE FUNCTION admissions.screening_result(p_app uuid)
RETURNS TABLE (utme int, utme_scaled numeric, screening numeric, screening_source text, weight_utme int, weight_putme int,
               aggregate numeric, cutoff int, merit_position int, applied int, places int)
LANGUAGE sql STABLE AS $$
    WITH me AS (
        SELECT a.*, c.programme AS programme_name, r.aggregate AS utme_raw,
               (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE a.id = p_app),
    w AS (
        SELECT coalesce((SELECT p.weight_utme FROM admissions.session_policy p, me WHERE p.session = me.session), 70) AS wu,
               coalesce((SELECT p.weight_putme FROM admissions.session_policy p, me WHERE p.session = me.session), 30) AS wp),
    mine AS (SELECT * FROM admissions.screening_component(p_app)),
    agg AS (
        SELECT a.id,
               round((coalesce(r.aggregate, 0) / 400.0 * 100 * w.wu / 100.0 + sc.screening * w.wp / 100.0)::numeric, 2) AS total
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          CROSS JOIN LATERAL admissions.screening_component(a.id) sc, w, me
         WHERE a.session = me.session AND a.score_released_at IS NOT NULL AND sc.screening IS NOT NULL
           AND c.programme = me.programme_name),
    ranked AS (SELECT id, rank() OVER (ORDER BY total DESC) AS pos, count(*) OVER () AS applied FROM agg)
    SELECT me.utme_raw,
           round(me.utme_raw / 400.0 * 100, 1),
           mine.screening, mine.source,
           w.wu, w.wp,
           CASE WHEN mine.screening IS NULL OR me.utme_raw IS NULL THEN NULL
                ELSE round((me.utme_raw / 400.0 * 100 * w.wu / 100.0 + mine.screening * w.wp / 100.0)::numeric, 2) END,
           admissions.cutoff_or_null(me.session, me.code),
           (SELECT pos::int FROM ranked WHERE ranked.id = me.id),
           (SELECT applied::int FROM ranked WHERE ranked.id = me.id),
           (SELECT f.quota FROM admissions.faculty_quota f JOIN admissions.session_policy p ON p.id = f.policy_id
             JOIN ref.programme pr ON pr.code = me.code WHERE p.session = me.session AND f.faculty_code = pr.faculty_code)
      FROM me, w, mine;
$$;

-- ── the decision ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.decide_application(p_app uuid, p_decision text, p_note text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NOT NULL THEN
        RAISE EXCEPTION 'the decision was released on % and stands', a.decision_released_at::date USING ERRCODE = '23514',
            HINT = 'A released decision is not quietly changed; the Board minutes a new one.';
    END IF;
    IF a.score_released_at IS NULL THEN
        RAISE EXCEPTION 'the screening score has not been released' USING ERRCODE = '23514', HINT = 'The Board decides on released scores.';
    END IF;
    UPDATE admissions.application SET decision = p_decision, decision_note = p_note, decided_at = now() WHERE id = p_app;
    RETURN p_decision;
END $$;

-- released together; an offer makes the candidate ADMITTED on the strength of the CAPS row
CREATE OR REPLACE FUNCTION admissions.release_decisions(p_session text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    UPDATE admissions.candidate c SET offer_state = 'ADMITTED'
      FROM admissions.application a
     WHERE a.candidate_id = c.id AND a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NULL
       AND c.offer_state = 'PROPOSED';
    UPDATE admissions.application SET decision_released_at = now()
     WHERE session = p_session AND decision IS NOT NULL AND decision_released_at IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- ── accepting ───────────────────────────────────────────────────────────
-- the undertaking is signed on the portal; the place is held when the acceptance fee is confirmed
CREATE OR REPLACE FUNCTION admissions.sign_undertaking(p_app uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
        RAISE EXCEPTION 'there is nothing to accept yet' USING ERRCODE = '23514', HINT = 'This opens when the Admissions Board publishes an offer.';
    END IF;
    IF a.declined_at IS NOT NULL THEN
        RAISE EXCEPTION 'this offer was declined on %', a.declined_at::date USING ERRCODE = '23514', HINT = 'A declined offer is not reinstated.';
    END IF;
    UPDATE admissions.application SET undertaking_at = coalesce(undertaking_at, now()) WHERE id = p_app;
    PERFORM admissions.settle_acceptance(p_app);
    RETURN CASE WHEN (SELECT accepted_at FROM admissions.application WHERE id = p_app) IS NULL THEN 'undertaking signed' ELSE 'accepted' END;
END $$;

CREATE OR REPLACE FUNCTION admissions.settle_acceptance(p_app uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.accepted_at IS NULL AND a.undertaking_at IS NOT NULL AND a.acceptance_confirmed_at IS NOT NULL AND a.declined_at IS NULL THEN
        UPDATE admissions.application SET accepted_at = now() WHERE id = p_app;
        UPDATE admissions.candidate SET offer_state = 'ACCEPTED' WHERE id = a.candidate_id AND offer_state = 'ADMITTED';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION admissions.decline_offer(p_app uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
        RAISE EXCEPTION 'there is no offer to decline' USING ERRCODE = '23514';
    END IF;
    IF a.accepted_at IS NOT NULL THEN
        RAISE EXCEPTION 'the offer was accepted on %; withdrawing is a change of status on the register', a.accepted_at::date USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.application SET declined_at = coalesce(declined_at, now()) WHERE id = p_app;
    UPDATE admissions.candidate SET offer_state = 'DECLINED' WHERE id = a.candidate_id AND offer_state IN ('PROPOSED','ADMITTED');
    RETURN 'declined';
END $$;

-- ── clearance: six documents seen at the Registry ───────────────────────
CREATE OR REPLACE FUNCTION admissions.clear_document(p_app uuid, p_item text, p_state text, p_note text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE a admissions.application; verified int;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.accepted_at IS NULL THEN
        RAISE EXCEPTION 'clearance opens when the offer has been accepted' USING ERRCODE = '23514',
            HINT = 'The Registry clears only candidates who have accepted and paid the acceptance fee.';
    END IF;
    INSERT INTO admissions.clearance_document (application_id, item, state, note, decided_at, decided_by)
    VALUES (p_app, p_item, p_state, p_note, now(), admissions.acting_person())
    ON CONFLICT (application_id, item) DO UPDATE
        SET state = EXCLUDED.state, note = EXCLUDED.note, decided_at = now(), decided_by = admissions.acting_person();
    SELECT count(*) INTO verified FROM admissions.clearance_document d WHERE d.application_id = p_app AND d.state = 'VERIFIED';
    IF verified = 6 THEN
        UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = p_app;
    ELSE
        UPDATE admissions.application SET cleared_at = NULL WHERE id = p_app;
    END IF;
    RETURN verified;
END $$;

COMMIT;

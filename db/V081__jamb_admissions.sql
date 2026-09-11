-- ═══════════════════════════════════════════════════════════════════════════
-- V081 — the JAMB admission-status list, uploaded back into the portal
--
--   After the screening list is sent to JAMB and JAMB offers admission, the
--   candidates accept on JAMB's own portal. The Academic Office downloads the
--   admission-status list from JAMB (RG_NUM, name, course, AdmissionStatus,
--   category, JAMB/PostUTME/Total) and uploads it here. Each row is matched to
--   the candidate the University already screened, by JAMB registration number
--   and never by name. A candidate JAMB records as ACCEPTED is offered
--   admission on the portal and the offer is released — so the applicant can
--   pay the acceptance/offer fee, pay school fees, register and be matriculated.
--   The upload never invents an admission: a number not on the register sits in
--   suspense for the Registry, exactly as a NELFUND remittance does.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE admissions.jamb_admission (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session       text NOT NULL,
    jamb_reg_no   text NOT NULL,
    name          text NULL,
    sex           text NULL,
    state_name    text NULL,
    lga_name      text NULL,
    course_name   text NULL,
    aggregate     int NULL,
    putme_score   numeric(6,2) NULL,
    status        text NULL,
    category      text NULL,
    jamb_component  numeric(7,2) NULL,
    putme_component numeric(7,2) NULL,
    total         numeric(7,2) NULL,
    candidate_id  uuid NULL REFERENCES admissions.candidate(id),
    matched       boolean NOT NULL DEFAULT false,
    offered       boolean NOT NULL DEFAULT false,
    why           text NULL,
    loaded_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_jamb_adm_per_session UNIQUE (session, jamb_reg_no)
);
CREATE INDEX ix_jamb_adm_session ON admissions.jamb_admission (session, status);
SELECT audit.attach('admissions.jamb_admission');

-- JAMB's admission category, in the portal's own basis codes; the raw category is kept on the note
CREATE OR REPLACE FUNCTION admissions.jamb_basis(p_category text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_category IS NULL THEN NULL
        WHEN upper(p_category) LIKE 'MERIT%' THEN 'NM'
        WHEN upper(p_category) LIKE 'CATCH%' THEN 'LOCALITY'
        WHEN upper(p_category) LIKE 'ELG%' OR upper(p_category) LIKE '%LESS DEVELOP%' OR upper(p_category) LIKE 'ELDS%' THEN 'ELG'
        WHEN upper(p_category) LIKE '%STATE%' THEN 'SM'
        ELSE NULL END
$$;

CREATE OR REPLACE FUNCTION admissions.load_jamb_admissions(p_session text, p_rows jsonb)
RETURNS TABLE (loaded int, matched int, accepted int, offered int, unmatched int)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_reg text; v_status text; v_cat text; v_basis text; v_cand uuid; v_app uuid; v_state text; v_admitted_from uuid;
        v_is_accept boolean; n int := 0; nm int := 0; na int := 0; no int := 0; nu int := 0;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'a JAMB admission list is uploaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the list is rows: registration number, name, course, admission status' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_reg := upper(btrim(coalesce(r->>'RG_NUM', r->>'regNo', r->>'reg_no', r->>'jambRegNo', '')));
        IF v_reg = '' THEN CONTINUE; END IF;
        v_status := btrim(coalesce(r->>'AdmissionStatus', r->>'status', ''));
        v_cat := nullif(btrim(coalesce(r->>'AdmissionCategoryName', r->>'category', '')), '');
        v_basis := admissions.jamb_basis(v_cat);
        v_is_accept := upper(v_status) LIKE 'ACCEPT%';

        SELECT id, offer_state, admitted_from INTO v_cand, v_state, v_admitted_from
          FROM admissions.candidate WHERE session = p_session AND upper(jamb_reg_no) = v_reg;

        INSERT INTO admissions.jamb_admission (session, jamb_reg_no, name, sex, state_name, lga_name, course_name,
                aggregate, putme_score, status, category, jamb_component, putme_component, total, candidate_id, matched, offered, why)
        VALUES (p_session, v_reg,
                nullif(btrim(coalesce(r->>'RG_CANDNAME', r->>'name', '')), ''),
                nullif(btrim(coalesce(r->>'RG_SEX', r->>'sex', '')), ''),
                nullif(btrim(coalesce(r->>'STATE_NAME', r->>'state', '')), ''),
                nullif(btrim(coalesce(r->>'LGA_NAME', r->>'lga', '')), ''),
                nullif(btrim(coalesce(r->>'CO_NAME', r->>'course', '')), ''),
                nullif(regexp_replace(coalesce(r->>'RG_AGGREGATE', ''), '[^0-9]', '', 'g'), '')::int,
                nullif(regexp_replace(coalesce(r->>'PUTMESCORE', ''), '[^0-9.]', '', 'g'), '')::numeric,
                nullif(v_status, ''), v_cat,
                nullif(regexp_replace(coalesce(r->>'JAMB', ''), '[^0-9.]', '', 'g'), '')::numeric,
                nullif(regexp_replace(coalesce(r->>'PostUTME', ''), '[^0-9.]', '', 'g'), '')::numeric,
                nullif(regexp_replace(coalesce(r->>'Total', ''), '[^0-9.]', '', 'g'), '')::numeric,
                v_cand, v_cand IS NOT NULL, false,
                CASE WHEN v_cand IS NULL THEN 'Registration number not on the register — screened here?' ELSE NULL END)
        ON CONFLICT (session, jamb_reg_no) DO UPDATE SET name = EXCLUDED.name, sex = EXCLUDED.sex, state_name = EXCLUDED.state_name,
            lga_name = EXCLUDED.lga_name, course_name = EXCLUDED.course_name, aggregate = EXCLUDED.aggregate, putme_score = EXCLUDED.putme_score,
            status = EXCLUDED.status, category = EXCLUDED.category, jamb_component = EXCLUDED.jamb_component,
            putme_component = EXCLUDED.putme_component, total = EXCLUDED.total, candidate_id = EXCLUDED.candidate_id,
            matched = EXCLUDED.matched, why = EXCLUDED.why, loaded_at = now();

        n := n + 1;
        IF v_cand IS NULL THEN nu := nu + 1; CONTINUE; END IF;
        nm := nm + 1;
        IF NOT v_is_accept THEN CONTINUE; END IF;
        na := na + 1;

        -- offered on the portal: the candidate is admitted and the offer released, so the acceptance fee can be paid
        SELECT id INTO v_app FROM admissions.application WHERE candidate_id = v_cand;
        IF v_app IS NULL THEN
            UPDATE admissions.jamb_admission SET why = 'Accepted at JAMB, but no application exists on the portal — the applicant has not registered here'
             WHERE session = p_session AND jamb_reg_no = v_reg;
            CONTINUE;
        END IF;
        UPDATE admissions.application
           SET decision = 'OFFERED',
               decision_basis = coalesce(decision_basis, v_basis),
               decision_note = coalesce(decision_note, 'JAMB admission' || coalesce(' · ' || v_cat, '')),
               decided_at = coalesce(decided_at, now()),
               decision_released_at = coalesce(decision_released_at, now())
         WHERE id = v_app;
        IF v_admitted_from IS NOT NULL AND v_state = 'PROPOSED' THEN
            UPDATE admissions.candidate SET offer_state = 'ADMITTED' WHERE id = v_cand;
        END IF;
        UPDATE admissions.jamb_admission SET offered = true WHERE session = p_session AND jamb_reg_no = v_reg;
        no := no + 1;
    END LOOP;
    RETURN QUERY SELECT n, nm, na, no, nu;
END $$;

-- the Bursary/Academic view of what was uploaded, and how it matched
CREATE OR REPLACE FUNCTION admissions.jamb_admission_list(p_session text)
RETURNS TABLE (jamb_reg_no text, name text, course_name text, status text, category text, total numeric,
               matched boolean, offered boolean, why text, loaded_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT jamb_reg_no, name, course_name, status, category, total, matched, offered, why, loaded_at
      FROM admissions.jamb_admission WHERE session = p_session ORDER BY matched, status, name
$$;

CREATE OR REPLACE FUNCTION admissions.jamb_admission_tiles(p_session text)
RETURNS TABLE (loaded bigint, matched bigint, accepted bigint, offered bigint, unmatched bigint)
LANGUAGE sql STABLE AS $$
    SELECT count(*), count(*) FILTER (WHERE matched), count(*) FILTER (WHERE upper(status) LIKE 'ACCEPT%'),
           count(*) FILTER (WHERE offered), count(*) FILTER (WHERE NOT matched)
      FROM admissions.jamb_admission WHERE session = p_session
$$;

-- the JAMB admission list references candidates; the intake reset (V078) must clear it before the candidates go
CREATE OR REPLACE FUNCTION admissions.reset_intake(p_session text)
RETURNS TABLE (candidates int, applications int, caps_rows int, olevel int, students_detached int)
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        n_cand int; n_app int; n_caps int; n_ol int; n_stu int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'the JAMB list is reset by a person' USING ERRCODE = '23514'; END IF;
    IF p_session IS NULL OR btrim(p_session) = '' THEN RAISE EXCEPTION 'a reset names the session it clears' USING ERRCODE = '23514'; END IF;

    UPDATE people.student SET candidate_id = NULL
     WHERE candidate_id IN (SELECT id FROM admissions.candidate WHERE session = p_session);
    GET DIAGNOSTICS n_stu = ROW_COUNT;

    DELETE FROM finance.gateway_event
     WHERE reference IN (SELECT reference FROM admissions.fee_reference
                          WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session));
    DELETE FROM finance.gateway_attempt
     WHERE reference IN (SELECT reference FROM admissions.fee_reference
                          WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session));
    DELETE FROM finance.payment_reconciliation
     WHERE reference IN (SELECT reference FROM admissions.fee_reference
                          WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session));

    DELETE FROM admissions.application_document_blob
     WHERE document_id IN (SELECT d.id FROM admissions.application_document d
                             JOIN admissions.application a ON a.id = d.application_id WHERE a.session = p_session);
    DELETE FROM admissions.application_document
     WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session);
    DELETE FROM admissions.fee_reference
     WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session);
    DELETE FROM admissions.clearance_document
     WHERE application_id IN (SELECT id FROM admissions.application WHERE session = p_session);
    DELETE FROM admissions.password_reset
     WHERE account_id IN (SELECT id FROM admissions.applicant_account WHERE session = p_session);
    DELETE FROM admissions.applicant_event
     WHERE account_id IN (SELECT id FROM admissions.applicant_account WHERE session = p_session);
    DELETE FROM admissions.application WHERE session = p_session;
    GET DIAGNOSTICS n_app = ROW_COUNT;
    DELETE FROM admissions.applicant_account WHERE session = p_session;
    DELETE FROM admissions.screening_batch WHERE session = p_session;

    -- the JAMB admission-status rows uploaded back (V081), before the candidates they point to
    DELETE FROM admissions.jamb_admission WHERE session = p_session;

    DELETE FROM admissions.olevel_grade
     WHERE sitting_id IN (SELECT id FROM admissions.olevel_sitting WHERE session = p_session);
    DELETE FROM admissions.olevel_sitting WHERE session = p_session;
    GET DIAGNOSTICS n_ol = ROW_COUNT;
    DELETE FROM admissions.candidate_photo
     WHERE candidate_id IN (SELECT id FROM admissions.candidate WHERE session = p_session);
    DELETE FROM admissions.attachment WHERE session = p_session;
    DELETE FROM admissions.candidate WHERE session = p_session;
    GET DIAGNOSTICS n_cand = ROW_COUNT;

    DELETE FROM admissions.caps_row WHERE session = p_session;
    GET DIAGNOSTICS n_caps = ROW_COUNT;
    DELETE FROM admissions.caps_row_excluded WHERE session = p_session;
    DELETE FROM admissions.caps_batch WHERE session = p_session;

    RETURN QUERY SELECT n_cand, n_app, n_caps, n_ol, n_stu;
END $$;

COMMIT;

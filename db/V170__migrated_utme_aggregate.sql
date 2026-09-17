-- ═══════════════════════════════════════════════════════════════════════════
-- V170 — carry the UTME aggregate for applicants migrated from the old portal
--
--   Migrated applicants have no CAPS row (the old file carries a programme NAME,
--   not a JAMB code, so a valid caps_row cannot be built for them). The screening
--   engine reads UTME from admissions.caps_row_live, so without a CAPS row a
--   migrated applicant has no UTME and does not even appear in the computed
--   screening or the register (both INNER JOIN caps_row_live).
--
--   So: store the UTME aggregate on the candidate itself, set at import from the
--   file's AGGR. column, and make the two report functions LEFT JOIN caps_row_live
--   and fall back to the candidate's stored aggregate and entry mode. For an
--   applicant who DOES have a CAPS row nothing changes (coalesce prefers the CAPS
--   value); a migrated applicant now appears, scored on the stored UTME. The
--   authoritative merit engine still keys off the real CAPS list when it is
--   uploaded, which the migration reconciles to by JAMB number.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.candidate ADD COLUMN IF NOT EXISTS utme_aggregate int NULL;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_candidate_utme') THEN
        ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_utme
            CHECK (utme_aggregate IS NULL OR utme_aggregate BETWEEN 1 AND 400);
    END IF;
END $$;

-- import_applicant gains a UTME aggregate argument (replaces the 8-arg V169 form)
DROP FUNCTION IF EXISTS admissions.import_applicant(text, text, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION admissions.import_applicant(
    p_session text, p_jamb_reg_no text, p_surname text, p_other_names text,
    p_programme text, p_entry_mode text, p_email text, p_phone text, p_utme text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    key     text := upper(btrim(coalesce(p_jamb_reg_no, '')));
    v_email text := lower(btrim(coalesce(p_email, '')));
    v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
    mode    text := upper(btrim(coalesce(p_entry_mode, 'UTME')));
    utme    int  := nullif(regexp_replace(coalesce(p_utme, ''), '\D', '', 'g'), '')::int;
    placeholder_email text;
    prog    text;
    lvl     int;
    v_candidate uuid;
    v_account   uuid;
    v_app       uuid;
    v_no        text;
    v_yy        text := substr(p_session, 3, 2);
    v_ref       text;
    v_rct       text;
    fee         record;
    v_amount    numeric;
BEGIN
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'an import is made by a person' USING ERRCODE = '23514';
    END IF;

    IF key !~ '^[0-9]{6,}[A-Z]{0,3}$' THEN RETURN 'skip: bad JAMB number'; END IF;
    IF btrim(coalesce(p_surname, '')) = '' OR btrim(coalesce(p_other_names, '')) = '' THEN RETURN 'skip: missing name'; END IF;
    IF utme IS NOT NULL AND (utme < 1 OR utme > 400) THEN utme := NULL; END IF;  -- ignore an out-of-range score

    placeholder_email := lower(key) || '@migrate.moau.local';

    IF length(v_phone) = 13 AND left(v_phone, 3) = '234' THEN v_phone := '0' || right(v_phone, 10); END IF;
    IF length(v_phone) = 10 AND left(v_phone, 1) <> '0' THEN v_phone := '0' || v_phone; END IF;
    IF v_phone !~ '^0[0-9]{10}$' THEN v_phone := '00000000000'; END IF;

    IF v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := placeholder_email; END IF;

    mode := CASE WHEN mode IN ('DE', 'DIRECT ENTRY', 'DIRECT-ENTRY', 'DIRECT_ENTRY') THEN 'DIRECT_ENTRY'
                 WHEN mode = 'TRANSFER' THEN 'TRANSFER' ELSE 'UTME' END;
    lvl := CASE WHEN mode = 'UTME' THEN 100 ELSE 200 END;

    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.session = p_session AND a.jamb_key = key) THEN
        RETURN 'exists';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = v_email) THEN
        v_email := placeholder_email;
        IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = v_email) THEN
            RETURN 'skip: duplicate account';
        END IF;
    END IF;

    prog := coalesce((SELECT p.name FROM ref.programme p
                       WHERE upper(p.code) = upper(btrim(p_programme)) OR upper(p.name) = upper(btrim(p_programme))
                       ORDER BY p.archived, p.code LIMIT 1), nullif(btrim(p_programme), ''));
    IF prog IS NULL THEN RETURN 'skip: missing programme'; END IF;

    BEGIN
        SELECT c.id INTO v_candidate FROM admissions.candidate c WHERE c.session = p_session AND c.jamb_key = key;
        IF v_candidate IS NULL THEN
            v_candidate := gen_random_uuid();
            INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, utme_aggregate)
            VALUES (v_candidate, p_session, key, btrim(p_surname), btrim(p_other_names), prog, mode, lvl, 'PROPOSED', utme);
        ELSIF utme IS NOT NULL THEN
            UPDATE admissions.candidate SET utme_aggregate = utme WHERE id = v_candidate AND utme_aggregate IS NULL;
        END IF;

        v_account := gen_random_uuid();
        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
        VALUES (v_account, p_session, v_candidate, key, v_email, v_phone, crypt(key, gen_salt('bf', 12)));

        v_app := gen_random_uuid();
        v_no  := 'APP/' || v_yy || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', p_session)::text, 6, '0');
        INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at)
        VALUES (v_app, v_account, v_candidate, p_session, v_no, now(), now());

        SELECT * INTO fee FROM admissions.applicant_fee_rule(p_session);
        v_amount := fee.application_fee + fee.portal_charge;
        v_ref := 'MOAUM-APP-' || right(v_no, 6) || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
        v_rct := 'RCT-' || left(p_session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', p_session)::text, 5, '0');
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at, confirmed_at, confirmed_by, channel, note, receipt_no)
        VALUES (gen_random_uuid(), v_app, 'APPLICATION', v_ref, v_amount, now(), now(), admissions.acting_person(),
                'Old-portal migration', 'Migrated: applied and paid on the previous portal', v_rct);

        IF v_email = placeholder_email AND v_phone = '00000000000' THEN RETURN 'imported (no contacts)';
        ELSIF v_email = placeholder_email THEN RETURN 'imported (no email)';
        ELSIF v_phone = '00000000000' THEN RETURN 'imported (no phone)';
        ELSE RETURN 'imported';
        END IF;
    EXCEPTION
        WHEN unique_violation THEN RETURN 'exists';
        WHEN OTHERS THEN RETURN 'error: ' || SQLERRM;
    END;
END $$;

-- ── the two report functions now LEFT JOIN the CAPS list and fall back to the
--    candidate's stored UTME / entry mode, so migrated applicants appear too ──

CREATE OR REPLACE FUNCTION admissions.non_sitter_post_utme(p_session text)
RETURNS TABLE (jamb_reg_no text, name text, programme text, entry_mode text,
               olevel_total int, olevel_ceiling int, olevel_scaled numeric, utme int, computed numeric, source text)
LANGUAGE sql STABLE AS $$
    WITH apps AS (
        SELECT a.id AS app_id, a.session, a.screening_score, c.jamb_key, c.jamb_reg_no,
               c.surname || ', ' || c.other_names AS cand_name, c.programme AS prog_name,
               (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code,
               coalesce(x.entry_mode, c.entry_mode) AS mode, coalesce(x.aggregate, c.utme_aggregate) AS utme_agg
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
         WHERE a.session = p_session AND a.submitted_at IS NOT NULL AND a.fee_confirmed_at IS NOT NULL
    ),
    scored AS (
        SELECT ap.*,
               admissions.screened_by_exam(ap.session, ap.code) AS by_exam,
               (SELECT s.total FROM admissions.olevel_score(ap.session, ap.jamb_key, ap.code) s) AS ol_total,
               (SELECT (r.subjects_counted * greatest(admissions.olevel_points(ap.session, 'A1'), 1) + r.bonus_one_sitting)
                  FROM admissions.olevel_rule(ap.session) r) AS ceiling,
               coalesce((SELECT weight_utme FROM admissions.session_policy WHERE session = ap.session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 70) AS wu,
               coalesce((SELECT weight_putme FROM admissions.session_policy WHERE session = ap.session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 30) AS wp
          FROM apps ap
    )
    SELECT jamb_reg_no, cand_name, prog_name, mode, ol_total, ceiling,
           CASE WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2) ELSE 0 END,
           utme_agg,
           CASE WHEN ol_total > 0 AND ceiling > 0 AND utme_agg IS NOT NULL
                     THEN round((utme_agg / 400.0 * 100) * wu / 100.0 + (ol_total::numeric / ceiling * 100) * wp / 100.0, 2)
                WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2)
                WHEN utme_agg IS NOT NULL THEN round(utme_agg / 400.0 * 100, 2)
                ELSE NULL END,
           CASE WHEN utme_agg IS NOT NULL AND ol_total > 0 THEN 'O''Level + UTME'
                WHEN ol_total > 0 THEN 'O''Level'
                WHEN utme_agg IS NOT NULL THEN 'UTME'
                ELSE 'none' END
      FROM scored
     WHERE NOT by_exam OR mode = 'DIRECT_ENTRY'
     ORDER BY 9 DESC NULLS LAST, 2;
$$;

CREATE OR REPLACE FUNCTION admissions.screening_register(p_session text)
RETURNS TABLE (jamb_reg_no text, name text, programme text, programme_code text, entry_mode text,
               utme int, olevel_scaled numeric, post_utme numeric, screening numeric, source text)
LANGUAGE sql STABLE AS $$
    WITH apps AS (
        SELECT a.session, a.screening_score, c.jamb_key, c.jamb_reg_no,
               c.surname || ', ' || c.other_names AS cand_name, c.programme AS prog_name,
               (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1) AS code,
               coalesce(x.entry_mode, c.entry_mode) AS mode, coalesce(x.aggregate, c.utme_aggregate) AS utme_agg
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
         WHERE a.session = p_session AND a.submitted_at IS NOT NULL
    ),
    scored AS (
        SELECT ap.*,
               admissions.screened_by_exam(ap.session, ap.code) AS by_exam,
               (SELECT s.total FROM admissions.olevel_score(ap.session, ap.jamb_key, ap.code) s) AS ol_total,
               (SELECT (r.subjects_counted * greatest(admissions.olevel_points(ap.session, 'A1'), 1) + r.bonus_one_sitting)
                  FROM admissions.olevel_rule(ap.session) r) AS ceiling,
               coalesce((SELECT weight_utme FROM admissions.session_policy WHERE session = ap.session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 70) AS wu,
               coalesce((SELECT weight_putme FROM admissions.session_policy WHERE session = ap.session ORDER BY (state = 'IN_FORCE') DESC LIMIT 1), 30) AS wp
          FROM apps ap
    )
    SELECT jamb_reg_no, cand_name, prog_name, code, mode,
           utme_agg,
           CASE WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2) END AS olevel_scaled,
           screening_score::numeric AS post_utme,
           CASE
             WHEN screening_score IS NOT NULL THEN screening_score::numeric
             WHEN by_exam THEN NULL
             WHEN ol_total > 0 AND ceiling > 0 AND utme_agg IS NOT NULL
                  THEN round((utme_agg / 400.0 * 100) * wu / 100.0 + (ol_total::numeric / ceiling * 100) * wp / 100.0, 2)
             WHEN ol_total > 0 AND ceiling > 0 THEN round(ol_total::numeric / ceiling * 100, 2)
             WHEN utme_agg IS NOT NULL THEN round(utme_agg / 400.0 * 100, 2)
             ELSE NULL END AS screening,
           CASE
             WHEN screening_score IS NOT NULL THEN 'Post-UTME'
             WHEN by_exam THEN 'Awaiting Post-UTME'
             WHEN ol_total > 0 AND utme_agg IS NOT NULL THEN 'O''Level + UTME'
             WHEN ol_total > 0 THEN 'O''Level'
             WHEN utme_agg IS NOT NULL THEN 'UTME'
             ELSE 'none' END AS source
      FROM scored
     ORDER BY prog_name, screening DESC NULLS LAST, cand_name;
$$;

COMMIT;

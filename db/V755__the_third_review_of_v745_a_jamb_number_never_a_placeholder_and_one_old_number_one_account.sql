-- ═══════════════════════════════════════════════════════════
-- V755 — the third review of V745 applied
--
--   V745 (the independent review of V737, old-portal preliminary applicants) is on main and may already run, so it is not edited;
--   what the review of its last fixes confirmed is put right here, each function restated from its current definition.
--
--   1 · A JAMB cell is read as a JAMB number by one test, admissions.prelim_mig_jamb_key, wherever the migration reads one: V737's
--       shape, but never one digit repeated ("0000000000", written by applicants who had none) nor a Nigerian mobile number. V745
--       kept "N/A" and "NIL" out of the keys; a cell of zeros still made strangers "the same JAMB number" and held every later one
--       for review. Such a cell is now JAMB_INVALID (a warning, kept as written), no key, and on nobody's record. The rows already
--       staged are keyed again.
--   2 · An old number shaped like the numbers this portal itself issues to postgraduate (PG/yy/nnnnnn) or JUPEB (the setting's
--       prefix/yyyy/nnnnnn) applicants is refused at the preliminary check, as an APP-shaped one is: it would one day be a new
--       applicant's number, and that door is tried first at sign-in.
--   3 · The postgraduate dry run (pg_migration_assess, from V675) and the JUPEB old-portal upload's preview
--       (jupeb.import_old_portal_students, from V345) name an old number a migrated preliminary applicant signs in with: the PG row
--       is a conflict at the check, not a failure at the import; the JUPEB row is INVALID in the preview and at the upload, and the
--       rest of the file imports (V745's trigger refused the whole upload, naming only the first such number).
--   4 · V745's trigger on jupeb.application looks only at rows brought from the old portal (legacy_source set): an application made
--       on this portal (jupeb.apply) is never refused by it — a refusal there would have rolled the number series back with it,
--       every later applicant drawing the same number and being refused in turn.
--
--   Restated (a later migration restating any of them starts from V755's text): admissions.prelim_mig_person_keys,
--   admissions.prelim_migration_assess (from V745), admissions.pg_migration_assess (from V675), jupeb.import_old_portal_students
--   (from V345). New: admissions.prelim_mig_jamb_key. The trigger jupeb.trg_application_not_prelim recreated with a WHEN clause.
-- ═══════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V755: the third review of V745 (preliminary applicants migrated from the old portal) applied', true);

-- ── 1 · one test of a JAMB number ─────────────────────────────────────────────────────────────────────────────────────────────
/* the JAMB number a migration cell holds, written without spaces and in capitals — or NULL when the cell holds none: blank, not
   JAMB-shaped (V737's test: six digits or more, up to three letters), one digit repeated ("0000000000", "1111111111AB": what an old
   form took from applicants who had no JAMB number), or a Nigerian mobile number written in the wrong column */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_jamb_key(p_cell text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN j ~ '^[0-9]{6,}[A-Z]{0,3}$' AND j !~ '^([0-9])\1+[A-Z]*$' AND j !~ '^0[789][01][0-9]{8}$' THEN j END
      FROM (SELECT nullif(upper(regexp_replace(coalesce(p_cell, ''), '\s', '', 'g')), '') AS j) x
$$;
COMMENT ON FUNCTION admissions.prelim_mig_jamb_key(text) IS
  'V755: the JAMB number a preliminary migration cell holds (no spaces, capitals), or NULL — blank, not JAMB-shaped, one digit repeated (a placeholder) or a Nigerian mobile number. Every JAMB test of the migration reads it: the person keys, JAMB_INVALID, the earlier-migration review and JAMB_ON_PORTAL.';

-- ── 2 · who a row is: the JAMB number only when it is one ─────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admissions.prelim_mig_person_keys(d jsonb)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_surname text := admissions.pg_mig_t(d, 'surname'); v_first text := admissions.pg_mig_t(d, 'firstName'); v_full text := admissions.pg_mig_t(d, 'fullName');
        v_x text; v_phone text; v_dob date; v_jamb text; k text[] := '{}';
BEGIN
    IF v_surname IS NULL AND v_first IS NULL AND v_full IS NOT NULL THEN
        IF position(',' IN v_full) > 0 THEN
            v_surname := btrim(split_part(v_full, ',', 1)); v_x := btrim(substr(v_full, position(',' IN v_full) + 1));
        ELSE
            v_surname := split_part(v_full, ' ', 1); v_x := btrim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1));
        END IF;
        v_first := nullif(split_part(v_x, ' ', 1), '');
    END IF;
    v_surname := nullif(upper(btrim(coalesce(v_surname, ''))), '');
    v_first := nullif(lower(split_part(btrim(coalesce(v_first, '')), ' ', 1)), '');
    v_x := admissions.pg_mig_t(d, 'phone');
    v_phone := nullif(admissions.cce_phone(coalesce(admissions.first_mobile(v_x), v_x)), '00000000000');
    v_dob := admissions.pg_mig_date(admissions.pg_mig_t(d, 'dateOfBirth'));
    v_jamb := nullif(upper(regexp_replace(coalesce(admissions.pg_mig_t(d, 'jambRegNo'), ''), '\s', '', 'g')), '');
    IF v_surname IS NOT NULL AND v_phone IS NOT NULL THEN k := k || ('SP|' || v_surname || '|' || v_phone); END IF;
    IF v_surname IS NOT NULL AND v_first IS NOT NULL AND v_dob IS NOT NULL THEN k := k || ('SFD|' || v_surname || '|' || v_first || '|' || v_dob::text); END IF;
    -- V755: a JAMB number only as admissions.prelim_mig_jamb_key reads one (no placeholder, of letters or of one repeated digit, no phone)
    v_jamb := admissions.prelim_mig_jamb_key(v_jamb);
    IF v_jamb IS NOT NULL THEN k := k || ('J|' || v_jamb); END IF;
    RETURN k;
END $function$;

COMMENT ON FUNCTION admissions.prelim_mig_person_keys(jsonb) IS
  'V745, V755: the keys a preliminary migration row is compared on with the earlier rows of its file — SP|surname|phone, SFD|surname|first name|birth date, J|JAMB number (only as admissions.prelim_mig_jamb_key reads one) — so the dry run sees what the import will: a second row of the same person held for review.';

-- the rows already staged, keyed again (a placeholder JAMB key dropped)
UPDATE admissions.prelim_migration_row r SET person_keys = admissions.prelim_mig_person_keys(r.data)
 WHERE r.person_keys IS DISTINCT FROM admissions.prelim_mig_person_keys(r.data);

-- ── 3 · the check of one row (V745's, restated) ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admissions.prelim_migration_assess(p_row uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    r admissions.prelim_migration_row; b admissions.prelim_migration_batch; p admissions.prelim_programme; o admissions.prelim_programme;
    d jsonb; probs jsonb := '[]'; c record; res record; v_x text; v_n int; v_dup int; v_nos text; v_i int;
    v_legacy text; v_surname text; v_first text; v_others text; v_full text; v_sex text; v_dob date; v_email text; v_email_raw text; v_phone text;
    v_kin_phone text; v_jamb text; v_state text; v_admission text; v_pay text; v_word text;
    v_ref text; v_gw text; v_amt_raw text; v_amt numeric; v_paid_on date; v_applied date; v_fee numeric; v_route_named text;
    v_target uuid; v_spec uuid; v_tproblem text; v_tdetail text;
    v_sittings jsonb := '[]'; v_body text; v_type text; v_type_raw text; v_year int; v_no text; v_subjects jsonb; v_keys text[] := '{}'; v_key text; v_sp text;
    v_max int; v_bad boolean;
    v_app_legacy uuid; v_app_email uuid; v_acc_email uuid; v_acc_route text; v_acc_app_no text; v_app uuid;
    a admissions.application; ac admissions.candidate; ar admissions.prelim_review; lg admissions.prelim_legacy_application;
    v_match text; v_action text; v_verdict text; v_clash text; v_target_state text; v_answers jsonb;
    -- V745
    v_pkeys text[]; v_dkeys text[]; v_dup_name text; v_basis text; v_left text[] := '{}'; v_taken text;
BEGIN
    SELECT * INTO r FROM admissions.prelim_migration_row WHERE id = p_row;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such migration row' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = r.batch_id;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = b.route;
    SELECT * INTO o FROM admissions.prelim_programme WHERE route = CASE b.route WHEN 'PRELIMINARY_SCIENCE' THEN 'PRELIMINARY_TECHNOLOGY' ELSE 'PRELIMINARY_SCIENCE' END;
    d := r.data;

    -- the old number: its shape, and once in the file
    v_legacy := upper(admissions.pg_mig_t(d, 'legacyApplicationNo'));
    IF v_legacy IS NOT NULL AND (length(v_legacy) > 40 OR v_legacy !~ '^[A-Z0-9][A-Z0-9/.-]*$') THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NO_INVALID', 'error', format('"%s" is not an application number.', left(v_legacy, 40)),
                 'Letters, digits and / - . only, no spaces, at most 40 characters, as the old portal shows it.');
    ELSIF v_legacy IS NOT NULL THEN
        SELECT min(x.row_no) INTO v_dup FROM admissions.prelim_migration_row x WHERE x.batch_id = r.batch_id AND x.legacy_no = v_legacy AND x.row_no < r.row_no;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('DUPLICATE_IN_FILE', 'duplicate', format('Row %s has the same application number.', v_dup),
                     'Keep one row for the applicant; this repeat is not imported.');
        END IF;
    END IF;
    -- the old number is a sign-in beside this portal's own: never shaped like this portal's APP number, never a number an account here
    -- already signs in with (an application number or a JAMB number; V745: a postgraduate applicant's old number, V709, or a JUPEB
    -- application's number or old reference, V718 — each opens its own account first); a JAMB-shaped number no account holds stays the old number
    -- V755: nor shaped like the postgraduate (PG/yy/nnnnnn) or JUPEB (the setting's prefix/yyyy/nnnnnn) numbers this portal issues —
    -- such an old number would one day be a new applicant's, who signs in at that door first
    IF v_legacy ~ '^APP/[0-9]{2}/[0-9]{6}$' OR v_legacy ~ '^PG/[0-9]{2}/[0-9]{6}$'
       OR EXISTS (SELECT 1 FROM jupeb.setting s WHERE v_legacy ~ ('^' || upper(s.application_prefix) || '/[0-9]{4}/[0-9]{6}$')) THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NO_IS_PORTAL_NUMBER', 'error', format('"%s" is shaped like this portal''s own application numbers (APP, PG or JUPEB), not the old portal''s.', v_legacy),
                 'Give the application number the old portal issued; this portal gives its own APP number at the import.');
    ELSIF v_legacy IS NOT NULL THEN
        v_taken := CASE WHEN EXISTS (SELECT 1 FROM admissions.application x WHERE x.application_no = v_legacy) THEN 'application number'
                        WHEN EXISTS (SELECT 1 FROM admissions.applicant_account x WHERE x.jamb_key = v_legacy) THEN 'JAMB number'
                        WHEN EXISTS (SELECT 1 FROM admissions.pg_legacy_application x WHERE upper(btrim(x.legacy_application_no)) = v_legacy) THEN 'old-portal postgraduate application number'
                        WHEN EXISTS (SELECT 1 FROM jupeb.application x WHERE x.application_no = v_legacy)
                          OR EXISTS (SELECT 1 FROM jupeb.application x WHERE upper(x.legacy_ref) = v_legacy) THEN 'JUPEB application number' END;
        IF v_taken IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_NO_IS_PORTAL_NUMBER', 'conflict',
                     format('"%s" is already an applicant''s %s on this portal, and signs that applicant in.', v_legacy, v_taken),
                     'One number signs in one applicant: check the number against the old portal; ICT settles a number this portal already uses.');
        END IF;
    END IF;

    -- the name (a "Full Name" column read when the template's are blank)
    v_surname := admissions.pg_mig_t(d, 'surname');
    v_first := admissions.pg_mig_t(d, 'firstName');
    v_others := admissions.pg_mig_t(d, 'otherNames');
    v_full := admissions.pg_mig_t(d, 'fullName');
    IF v_surname IS NULL AND v_first IS NULL AND v_full IS NOT NULL THEN
        IF position(',' IN v_full) > 0 THEN
            v_surname := btrim(split_part(v_full, ',', 1)); v_x := btrim(substr(v_full, position(',' IN v_full) + 1));
        ELSE
            v_surname := split_part(v_full, ' ', 1); v_x := btrim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1));
        END IF;
        v_first := nullif(split_part(v_x, ' ', 1), ''); v_others := nullif(btrim(substr(v_x, length(split_part(v_x, ' ', 1)) + 1)), '');
    END IF;

    -- every required column given
    FOR c IN SELECT x.key, x.header, x.note FROM admissions.prelim_migration_columns(b.route) x WHERE x.required LOOP
        v_x := CASE c.key WHEN 'surname' THEN v_surname WHEN 'firstName' THEN v_first ELSE admissions.pg_mig_t(d, c.key) END;
        IF v_x IS NULL THEN
            probs := probs || admissions.pg_mig_problem('MISSING_' || upper(regexp_replace(c.key, '([a-z0-9])([A-Z])', '\1_\2', 'g')), 'error',
                     format('%s is missing.', c.header), coalesce(c.note, 'Give it as the old portal shows it.'));
        END IF;
    END LOOP;
    IF (v_surname IS NOT NULL OR v_first IS NOT NULL)
       AND (coalesce(v_surname, '') || ' ' || coalesce(v_first, '') || ' ' || coalesce(v_others, '')) ~ '[0-9=@<>{}\\;|_]'
        OR length(coalesce(v_surname, '')) > 60 OR length(coalesce(v_first, '')) > 60 OR length(coalesce(v_others, '')) > 60
        OR (v_surname IS NOT NULL AND v_surname !~ '[[:alpha:]]') OR (v_first IS NOT NULL AND v_first !~ '[[:alpha:]]') THEN
        probs := probs || admissions.pg_mig_problem('NAME_INVALID', 'error', format('"%s, %s" is not a name.', left(coalesce(v_surname, ''), 40), left(concat_ws(' ', v_first, v_others), 40)),
                 'Letters, spaces, hyphens and apostrophes only; at most 60 characters each.');
    END IF;

    -- the person: gender, birth date, contacts
    v_x := admissions.pg_mig_t(d, 'gender'); v_sex := admissions.prelim_mig_gender(v_x);
    IF v_x IS NOT NULL AND v_sex IS NULL THEN
        probs := probs || admissions.pg_mig_problem('GENDER_INVALID', 'error', format('Gender "%s" is not read.', left(v_x, 20)), 'Male or Female.');
    END IF;
    v_x := admissions.pg_mig_t(d, 'dateOfBirth'); v_dob := admissions.pg_mig_date(v_x);
    IF v_x IS NOT NULL AND v_dob IS NULL THEN
        probs := probs || admissions.pg_mig_problem('DATE_INVALID', 'error', format('Date of birth "%s" is not a date, or is in the future.', left(v_x, 20)),
                 'DD/MM/YYYY, YYYY-MM-DD or an Excel date.');
    ELSIF v_dob IS NOT NULL AND (v_dob > current_date - interval '10 years' OR v_dob < DATE '1950-01-01') THEN
        probs := probs || admissions.pg_mig_problem('DOB_UNLIKELY', 'warning', format('Date of birth %s is unlikely for an applicant.', to_char(v_dob, 'DD Mon YYYY')),
                 'Check it against the old portal; it is imported as written.');
    END IF;
    v_email_raw := admissions.pg_mig_t(d, 'email');
    v_email := admissions.first_email(v_email_raw);
    IF v_email_raw IS NOT NULL AND (v_email IS NULL OR length(v_email) > 254) THEN
        probs := probs || admissions.pg_mig_problem('EMAIL_INVALID', 'error', format('"%s" is not an email address.', left(v_email_raw, 80)), 'Correct it, or leave it blank.');
        v_email := NULL;
    ELSIF v_email IS NOT NULL THEN
        SELECT min(x.row_no) INTO v_dup FROM admissions.prelim_migration_row x
         WHERE x.batch_id = r.batch_id AND x.email = v_email AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('DUPLICATE_EMAIL_IN_FILE', 'duplicate', format('Row %s has the same email for another application number.', v_dup),
                     'One email is one applicant''s sign-in: correct one of the two rows.');
        END IF;
    END IF;
    v_x := admissions.pg_mig_t(d, 'phone'); v_phone := admissions.cce_phone(coalesce(admissions.first_mobile(v_x), v_x));
    IF v_x IS NOT NULL AND v_phone IS NULL THEN
        probs := probs || admissions.pg_mig_problem('PHONE_INVALID', 'error', format('Phone "%s" is not a Nigerian mobile number.', left(v_x, 30)), 'Eleven digits, 080…, or +234….');
    END IF;
    v_x := admissions.pg_mig_t(d, 'nextOfKinPhone'); v_kin_phone := admissions.cce_phone(coalesce(admissions.first_mobile(v_x), v_x));
    IF v_x IS NOT NULL AND v_kin_phone IS NULL THEN
        probs := probs || admissions.pg_mig_problem('PHONE_INVALID', 'warning', format('Next of kin phone "%s" is not read; left blank.', left(v_x, 30)), 'Eleven digits, 080…, or +234….');
    END IF;
    v_jamb := upper(regexp_replace(coalesce(admissions.pg_mig_t(d, 'jambRegNo'), ''), '\s', '', 'g'));
    v_jamb := nullif(v_jamb, '');
    IF v_jamb IS NOT NULL AND admissions.prelim_mig_jamb_key(v_jamb) IS NULL THEN   -- V755: one test of a JAMB number
        probs := probs || admissions.pg_mig_problem('JAMB_INVALID', 'warning', format('"%s" is not a JAMB registration number; kept as written.', left(v_jamb, 30)), NULL);
    END IF;
    FOREACH v_x IN ARRAY ARRAY['applicationDate', 'paymentDate'] LOOP
        IF admissions.pg_mig_t(d, v_x) IS NOT NULL AND admissions.pg_mig_date(admissions.pg_mig_t(d, v_x)) IS NULL THEN
            probs := probs || admissions.pg_mig_problem('DATE_INVALID', 'error',
                     format('%s "%s" is not a date, or is in the future.', CASE v_x WHEN 'applicationDate' THEN 'Application date' ELSE 'Payment date' END, left(admissions.pg_mig_t(d, v_x), 20)),
                     'DD/MM/YYYY, YYYY-MM-DD or an Excel date.');
        END IF;
    END LOOP;
    v_applied := admissions.pg_mig_date(admissions.pg_mig_t(d, 'applicationDate'));

    -- the old portal's words for the application, the admission and the payment
    v_word := admissions.pg_mig_t(d, 'applicationStatus');
    v_state := admissions.prelim_mig_status('APPLICATION', v_word);
    IF v_word IS NOT NULL AND v_state IS NULL THEN
        probs := probs || admissions.pg_mig_problem('STATUS_UNKNOWN', 'error', format('Application status "%s" is not one this portal reads.', left(v_word, 40)),
                 'One of the statuses in the template''s drop-down.');
    END IF;
    v_word := admissions.pg_mig_t(d, 'admissionStatus');
    v_admission := coalesce(admissions.prelim_mig_status('ADMISSION', v_word), CASE WHEN v_word IS NULL THEN 'PENDING' END);
    IF v_admission IS NULL THEN
        probs := probs || admissions.pg_mig_problem('STATUS_UNKNOWN', 'error', format('Admission status "%s" is not one this portal reads.', left(v_word, 40)),
                 'One of the statuses in the template''s drop-down, or blank for pending.');
    END IF;
    v_word := admissions.pg_mig_t(d, 'paymentStatus');
    v_pay := admissions.prelim_mig_status('PAYMENT', v_word);
    IF v_word IS NOT NULL AND v_pay IS NULL THEN
        probs := probs || admissions.pg_mig_problem('STATUS_UNKNOWN', 'error', format('Payment status "%s" is not one this portal reads.', left(v_word, 40)),
                 'Paid or Not paid (the template''s drop-down).');
    END IF;
    IF v_admission IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') AND v_state IN ('DRAFT', 'WITHDRAWN') THEN
        probs := probs || admissions.pg_mig_problem('STATUS_INCONSISTENT', 'error',
                 format('Decided on the old portal (%s) but the application is %s there.', lower(replace(v_admission, '_', ' ')), lower(v_state)),
                 'An application decided on the old portal was submitted: correct the application status or the admission status.');
    END IF;
    v_target_state := CASE WHEN v_admission IN ('ADMITTED', 'ACCEPTED') THEN 'ADMITTED' WHEN v_admission = 'NOT_ADMITTED' THEN 'NOT_ADMITTED' ELSE v_state END;

    -- the programme: the upload's route; a row naming the other preliminary programme is held back
    v_x := admissions.pg_mig_t(d, 'programme');
    IF v_x IS NOT NULL THEN
        v_route_named := admissions.prelim_mig_route_of(v_x);
        IF v_route_named = o.route THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_MISMATCH', 'conflict',
                     format('The row names %s ("%s"); this upload is for %s.', o.name, left(v_x, 80), p.name),
                     'Upload the row with the ' || o.name || ' file, or correct its programme on the portal after it is imported.');
        ELSIF v_route_named IS NULL THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_WORD_UNKNOWN', 'warning',
                     format('Programme "%s" is not read; the applicant comes in under %s, the programme of this upload.', left(v_x, 80), p.name), NULL);
        END IF;
    END IF;

    -- the target (and its specialisation) among the route's own
    SELECT x.target_id, x.specialisation_id, x.problem, x.detail INTO v_target, v_spec, v_tproblem, v_tdetail
      FROM admissions.prelim_mig_target_of(b.route, admissions.pg_mig_t(d, 'target'),
                                           CASE WHEN b.route = 'PRELIMINARY_TECHNOLOGY' THEN admissions.pg_mig_t(d, 'specialisation') END) x;
    -- V745: a target that is one of the other preliminary programme's own (an old export pasted with no Programme column, or into the
    -- other programme's section) is that programme's applicant, held back as a Programme cell naming it is — never imported here
    -- without a target. Only a target on the other programme's list counts (not a word in it: "Applied Sciences" names neither).
    IF v_tproblem = 'TARGET_NOT_FOUND' AND v_route_named IS DISTINCT FROM o.route
       AND EXISTS (SELECT 1 FROM admissions.prelim_target t LEFT JOIN ref.programme g ON g.code = t.programme_code
                    WHERE t.route = o.route AND t.state = 'MAPPED'
                      AND admissions.pg_legacy_key(admissions.pg_mig_t(d, 'target'))
                          IN (admissions.pg_legacy_key(t.programme_code), admissions.pg_legacy_key(g.name), admissions.pg_legacy_key(t.requested_name),
                              admissions.pg_legacy_key(t.group_name))) THEN
        probs := probs || admissions.pg_mig_problem('PROGRAMME_MISMATCH', 'conflict',
                 format('The row''s target "%s" is one of %s''s; this upload is for %s.', left(admissions.pg_mig_t(d, 'target'), 80), o.name, p.name),
                 'Upload the row with the ' || o.name || ' file, or correct its programme on the portal after it is imported.');
    ELSIF v_tproblem IS NOT NULL THEN
        probs := probs || admissions.pg_mig_problem(v_tproblem, 'warning', v_tdetail || '; imported without it.',
                 'The applicant, or the Office, chooses it on the portal; or correct it from the template''s list.');
    END IF;

    -- the O'Level: each sitting complete and released, of a body and a qualification the route accepts
    v_max := least(greatest(coalesce(p.max_sittings, 1), 1), 2);
    FOR v_i IN 1 .. 2 LOOP
        v_body := admissions.pg_mig_t(d, 'olevel' || v_i || 'Body');
        v_type_raw := admissions.pg_mig_t(d, 'olevel' || v_i || 'Qualification');
        v_x := admissions.pg_mig_t(d, 'olevel' || v_i || 'Year');
        v_no := admissions.pg_mig_t(d, 'olevel' || v_i || 'Number');
        v_sp := admissions.pg_mig_t(d, 'olevel' || v_i || 'Results');
        CONTINUE WHEN coalesce(v_body, v_type_raw, v_x, v_no, v_sp) IS NULL;
        IF v_i > v_max THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_SITTINGS', 'error', format('%s accepts at most %s sitting%s; the row gives sitting %s.', p.name, v_max, CASE WHEN v_max = 1 THEN '' ELSE 's' END, v_i),
                     'Give the sittings the applicant used, up to the number allowed.');
            CONTINUE;
        END IF;
        v_bad := false;
        IF v_body IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_BODY_MISSING', 'error', format('O''Level sitting %s: the examination type is missing.', v_i), 'WAEC, NECO, NABTEB or OTHER.'); v_bad := true;
        ELSIF admissions.prelim_mig_body(v_body) IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_BODY_INVALID', 'error', format('O''Level sitting %s: "%s" is not an examination body.', v_i, left(v_body, 30)), 'WAEC, NECO, NABTEB or OTHER.'); v_bad := true;
        END IF;
        v_body := admissions.prelim_mig_body(v_body);
        IF v_type_raw IS NULL THEN
            v_type := 'SSCE';
        ELSE
            SELECT q.code INTO v_type FROM admissions.qualification_type q
             WHERE q.active AND admissions.pg_legacy_key(v_type_raw) IN (admissions.pg_legacy_key(q.code), admissions.pg_legacy_key(q.label)) LIMIT 1;
        END IF;
        IF v_type IS NULL OR v_type <> ALL (p.qualification_types) THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_QUALIFICATION_INVALID', 'error',
                     format('O''Level sitting %s: "%s" is not a qualification %s accepts.', v_i, left(coalesce(v_type_raw, v_type, ''), 40), p.name),
                     'One of: ' || (SELECT string_agg(q.code, ', ' ORDER BY q.ord) FROM admissions.qualification_type q WHERE q.active AND q.code = ANY (p.qualification_types)) || '.');
            v_bad := true;
        END IF;
        v_year := CASE WHEN coalesce(v_x, '') ~ '^[0-9]{4}$' THEN v_x::int END;
        IF v_x IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_YEAR_MISSING', 'error', format('O''Level sitting %s: the examination year is missing.', v_i), 'YYYY.'); v_bad := true;
        ELSIF v_year IS NULL OR v_year < 1970 OR v_year > extract(year FROM current_date)::int THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_YEAR_INVALID', 'error', format('O''Level sitting %s: "%s" is not an examination year.', v_i, left(v_x, 10)), 'YYYY, from 1970 to this year.'); v_bad := true;
        END IF;
        IF v_no IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_NUMBER_MISSING', 'error', format('O''Level sitting %s: the examination number is missing.', v_i), NULL); v_bad := true;
        ELSIF length(v_no) > 30 THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_NUMBER_INVALID', 'error', format('O''Level sitting %s: the examination number is longer than 30 characters.', v_i), NULL); v_bad := true;
        END IF;
        v_subjects := '[]';
        IF v_sp IS NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_RESULTS_MISSING', 'error', format('O''Level sitting %s: the subjects and grades are missing.', v_i),
                     'Subject:Grade; Subject:Grade — e.g. English Language:C4; Mathematics:B3.'); v_bad := true;
        ELSE
            v_n := 0;
            FOR res IN SELECT * FROM admissions.prelim_mig_results(v_sp) LOOP
                v_n := v_n + 1;
                IF res.problem IS NULL THEN
                    v_subjects := v_subjects || jsonb_build_array(jsonb_build_object('subject', res.subject, 'grade', res.grade));
                ELSE
                    v_bad := true;
                    probs := probs || CASE res.problem
                        WHEN 'SUBJECT_UNKNOWN' THEN admissions.pg_mig_problem('OLEVEL_SUBJECT_UNKNOWN', 'error', format('O''Level sitting %s: "%s" is not a subject the application form knows.', v_i, left(res.given, 60)),
                                                    'Write the subject as the template''s Subjects sheet names it, each Subject:Grade apart (a semicolon, or a line of its own).')
                        WHEN 'NO_GRADE' THEN admissions.pg_mig_problem('OLEVEL_GRADE_INVALID', 'error', format('O''Level sitting %s: %s has no grade.', v_i, left(res.given, 60)),
                                                    'Subject:Grade, the grade A1 to F9.')
                        WHEN 'AWAITING' THEN admissions.pg_mig_problem('OLEVEL_AWAITING', 'error', format('O''Level sitting %s: %s is an awaiting result; %s admits on results already released.', v_i, left(res.given, 60), p.name),
                                                    'Give the released grade, or leave the sitting out.')
                        WHEN 'GRADE_INVALID' THEN admissions.pg_mig_problem('OLEVEL_GRADE_INVALID', 'error', format('O''Level sitting %s: "%s" is not a grade (%s).', v_i, left(coalesce(res.grade, ''), 10), left(res.given, 60)),
                                                    'A1, B2, B3, C4, C5, C6, D7, E8 or F9.')
                        ELSE admissions.pg_mig_problem('OLEVEL_SUBJECT_TWICE', 'error', format('O''Level sitting %s: %s is given twice.', v_i, left(res.given, 60)), 'Give each subject once.') END;
                END IF;
            END LOOP;
            IF v_n = 0 THEN
                probs := probs || admissions.pg_mig_problem('OLEVEL_RESULTS_MISSING', 'error', format('O''Level sitting %s: no subject and grade is read.', v_i),
                         'Subject:Grade; Subject:Grade — e.g. English Language:C4; Mathematics:B3.'); v_bad := true;
            ELSIF v_n > 9 THEN
                probs := probs || admissions.pg_mig_problem('OLEVEL_RESULTS_TOO_MANY', 'error', format('O''Level sitting %s: %s subjects; nine at most.', v_i, v_n), NULL); v_bad := true;
            END IF;
        END IF;
        CONTINUE WHEN v_bad;
        v_key := admissions.prelim_mig_olevel_key(v_body, v_year::text, v_no);
        IF v_key = ANY (v_keys) THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_SITTING_TWICE', 'error', format('O''Level sitting %s is the same examination as sitting 1.', v_i), 'Give two different sittings, or one.');
            CONTINUE;
        END IF;
        v_keys := v_keys || v_key;
        v_sittings := v_sittings || jsonb_build_array(jsonb_build_object('sitting', v_i, 'body', v_body, 'type', v_type, 'year', v_year, 'number', v_no, 'subjects', v_subjects));
        -- the same sitting on another row of the file (through the keys' own index)
        SELECT min(x.row_no) INTO v_dup
          FROM (SELECT x2.row_no, x2.batch_id, x2.legacy_no FROM admissions.prelim_migration_row x2 WHERE x2.olevel_keys @> ARRAY[v_key] OFFSET 0) x
         WHERE x.batch_id = r.batch_id AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_IN_FILE', 'duplicate', format('O''Level sitting %s (%s %s, %s) is also on row %s, another applicant.', v_i, v_body, v_year, left(v_no, 30), v_dup),
                     'One examination sitting is one person''s: correct the number on one of the rows.');
        END IF;
    END LOOP;

    -- who this is: the application the old number brought before, the account of the email, or nobody yet
    IF v_legacy IS NOT NULL THEN
        SELECT l.application_id INTO v_app_legacy FROM admissions.prelim_legacy_application l WHERE upper(btrim(l.legacy_application_no)) = v_legacy;
    END IF;
    IF v_email IS NOT NULL THEN
        SELECT acc.id, ap.id, pr.route, ap.application_no INTO v_acc_email, v_app_email, v_acc_route, v_acc_app_no
          FROM admissions.applicant_account acc LEFT JOIN admissions.application ap ON ap.account_id = acc.id
          LEFT JOIN admissions.prelim_review pr ON pr.application_id = ap.id
         WHERE lower(acc.email) = v_email LIMIT 1;
        IF v_acc_email IS NOT NULL AND coalesce(v_acc_route, '') NOT IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY') THEN
            probs := probs || admissions.pg_mig_problem('EMAIL_ELSEWHERE', 'conflict',
                     format('%s is the sign-in of another application on this portal (%s), not a preliminary one.', v_email, coalesce(v_acc_app_no, 'an applicant account')),
                     'Give the email the applicant used on the old portal for this application, or leave it blank.');
            v_app_email := NULL;
        END IF;
    END IF;
    IF v_app_legacy IS NOT NULL AND v_app_email IS NOT NULL AND v_app_legacy <> v_app_email THEN
        probs := probs || admissions.pg_mig_problem('IDENTITY_SPLIT', 'conflict',
                 format('The application number and the email point to different applications here (%s, %s).',
                        (SELECT x.application_no FROM admissions.application x WHERE x.id = v_app_legacy), v_acc_app_no),
                 'Settle which application is this applicant''s before importing the row.');
    END IF;
    v_app := coalesce(v_app_legacy, v_app_email);

    IF v_app IS NOT NULL THEN
        SELECT * INTO a FROM admissions.application WHERE id = v_app;
        SELECT * INTO ac FROM admissions.candidate WHERE id = a.candidate_id;
        SELECT * INTO ar FROM admissions.prelim_review WHERE application_id = v_app;
        SELECT * INTO lg FROM admissions.prelim_legacy_application WHERE application_id = v_app;
        v_match := 'EXISTING_APPLICANT';
        v_action := CASE WHEN v_app_legacy IS NOT NULL THEN CASE WHEN b.allow_update THEN 'UPDATE' ELSE 'NONE' END ELSE 'RECONCILE' END;
        IF ar.route IS DISTINCT FROM b.route THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_CONFLICT', 'conflict',
                     format('Already on the portal under %s as %s.', coalesce((SELECT x.name FROM admissions.prelim_programme x WHERE x.route = ar.route), ar.route), a.application_no),
                     'Correct its programme on the portal instead (Programme corrections), or upload the row with that programme''s file.');
        END IF;
        IF v_app_legacy IS NULL AND lg.application_id IS NOT NULL AND v_legacy IS NOT NULL AND upper(btrim(lg.legacy_application_no)) <> v_legacy THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_DIFFERS', 'conflict',
                     format('Application %s already carries old application number %s.', a.application_no, lg.legacy_application_no),
                     'One application, one old number: check which is right.');
        END IF;
        IF v_surname IS NOT NULL AND admissions.pg_legacy_key(ac.surname) IS DISTINCT FROM admissions.pg_legacy_key(v_surname) THEN
            probs := probs || admissions.pg_mig_problem('NAME_DIFFERS', 'conflict', format('Application %s is in the name of %s, %s.', a.application_no, ac.surname, ac.other_names),
                     'Check that this is the same person; a name is corrected on the application, not by a migration.');
        END IF;
        -- V745: found by the email alone, the person is shown by the first name and the sex as well — a parent's or a twin's email is
        -- never another person's way onto this application (prelim_register's own duplicate rule reads the first name too)
        IF v_app_legacy IS NULL THEN
            IF v_first IS NOT NULL AND admissions.pg_legacy_key(split_part(btrim(coalesce(ac.other_names, '')), ' ', 1))
                                       IS DISTINCT FROM admissions.pg_legacy_key(split_part(btrim(v_first), ' ', 1)) THEN
                probs := probs || admissions.pg_mig_problem('FIRST_NAME_DIFFERS', 'conflict',
                         format('Application %s, which this email signs in, is in the name of %s, %s; the row names %s.', a.application_no, ac.surname, ac.other_names, v_first),
                         'One email is one applicant''s sign-in: give this applicant''s own email, or leave it blank so the row comes in as a new applicant.');
            END IF;
            IF v_sex IS NOT NULL AND ac.sex IS NOT NULL AND upper(ac.sex) <> v_sex THEN
                probs := probs || admissions.pg_mig_problem('SEX_DIFFERS', 'conflict',
                         format('Application %s, which this email signs in, is of a %s applicant; the row is %s.', a.application_no,
                                CASE upper(ac.sex) WHEN 'M' THEN 'male' ELSE 'female' END, CASE v_sex WHEN 'M' THEN 'male' ELSE 'female' END),
                         'One email is one applicant''s sign-in: give this applicant''s own email, or leave it blank so the row comes in as a new applicant.');
            END IF;
        END IF;
        v_x := (SELECT sa.value FROM admissions.screening_answer sa WHERE sa.application_id = v_app AND sa.field = 'date_of_birth');
        IF v_dob IS NOT NULL AND v_x IS NOT NULL AND v_x <> v_dob::text THEN
            probs := probs || admissions.pg_mig_problem('DOB_DIFFERS', 'conflict', format('Application %s gives the date of birth %s.', a.application_no, v_x),
                     'Check that this is the same person.');
        END IF;
        IF a.session IS DISTINCT FROM b.session THEN
            probs := probs || admissions.pg_mig_problem('SESSION_DIFFERS', 'conflict', format('Application %s is of %s; this upload is for %s.', a.application_no, a.session, b.session),
                     'A preliminary application is migrated into the session its programme admits for.');
        END IF;
        -- the outcome: one decided here stands, and a contrary one on the old portal is held back
        IF ar.published_at IS NOT NULL AND ((ar.state = 'ADMITTED' AND v_admission = 'NOT_ADMITTED')
                                            OR (ar.state IN ('NOT_ADMITTED', 'REJECTED') AND v_admission IN ('ADMITTED', 'ACCEPTED'))) THEN
            probs := probs || admissions.pg_mig_problem('DECISION_DIFFERS', 'conflict',
                     format('Application %s is %s here; the old portal says %s.', a.application_no, lower(replace(ar.state, '_', ' ')), lower(replace(v_admission, '_', ' '))),
                     'The outcome published here stands; the Academic Office settles a difference.');
        ELSIF v_admission IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') AND (ar.published_at IS NOT NULL OR ar.state IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED', 'WITHDRAWN'))
              AND NOT (ar.state = 'ADMITTED' AND v_admission IN ('ADMITTED', 'ACCEPTED')) THEN
            probs := probs || admissions.pg_mig_problem('PORTAL_FURTHER', 'warning',
                     format('Application %s is %s here: kept; the old portal''s decision is not applied.', a.application_no, lower(replace(ar.state, '_', ' '))), NULL);
        END IF;
        IF v_state = 'WITHDRAWN' AND ar.state <> 'WITHDRAWN' THEN
            probs := probs || admissions.pg_mig_problem('WITHDRAWN_ON_OLD_PORTAL', 'warning',
                     format('Withdrawn on the old portal; application %s stays as it is here.', a.application_no), NULL);
        END IF;
        -- V745: an application made here and found by its email is changed only where the upload fills in missing details: without
        -- it, the old number is kept with it and nothing else — no outcome published, no state moved forward, no fee held
        IF v_action = 'RECONCILE' AND NOT b.allow_update THEN
            v_left := array_remove(ARRAY[
                CASE WHEN v_admission IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') THEN 'the old portal''s admission (' || lower(replace(v_admission, '_', ' ')) || ')' END,
                CASE WHEN coalesce(v_admission, 'PENDING') NOT IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') AND v_state IN ('SUBMITTED', 'UNDER_REVIEW') AND ar.published_at IS NULL
                          AND (ar.state = 'DRAFT' OR (ar.state = 'SUBMITTED' AND v_state = 'UNDER_REVIEW'))
                     THEN 'the state it reached there (' || lower(replace(v_state, '_', ' ')) || ')' END,
                CASE WHEN v_pay = 'PAID' AND a.fee_confirmed_at IS NULL THEN 'the application fee paid there' END], NULL);
            IF cardinality(v_left) > 0 THEN
                probs := probs || admissions.pg_mig_problem('OLD_NUMBER_ONLY', 'warning',
                         format('Application %s was made on this portal: only the old number is kept with it; %s %s here ("Fill in missing details" is not ticked).',
                                a.application_no, array_to_string(v_left, ', '), CASE WHEN cardinality(v_left) = 1 THEN 'is left as it stands' ELSE 'are left as they stand' END),
                         'Upload the row again with "Fill in missing details" ticked to bring them in.');
            END IF;
        END IF;
    ELSE
        v_match := 'NEW_APPLICANT'; v_action := 'CREATE';
        IF v_email IS NULL AND v_email_raw IS NULL THEN
            probs := probs || admissions.pg_mig_problem('NO_EMAIL', 'warning',
                     'No email: the applicant signs in with the application number, and is told by SMS.', NULL);
        END IF;
        -- the same person, perhaps, on a preliminary application of either route: never merged unseen
        IF v_surname IS NOT NULL THEN
            SELECT string_agg(x.application_no, ', ') INTO v_nos FROM (
                SELECT ap.application_no FROM admissions.candidate cc
                  JOIN admissions.application ap ON ap.candidate_id = cc.id
                  JOIN admissions.prelim_review pr ON pr.application_id = ap.id AND pr.route IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY')
                  JOIN admissions.applicant_account acc ON acc.id = ap.account_id
                  LEFT JOIN admissions.screening_answer sa ON sa.application_id = ap.id AND sa.field = 'date_of_birth'
                 WHERE cc.entry_mode IN ('PRELIMINARY', 'PROFICIENCY') AND upper(cc.surname) = upper(v_surname)
                   AND ((v_dob IS NOT NULL AND v_first IS NOT NULL AND lower(split_part(cc.other_names, ' ', 1)) = lower(v_first) AND sa.value = v_dob::text)
                        OR (v_phone IS NOT NULL AND acc.phone = v_phone))
                 ORDER BY ap.application_no LIMIT 3) x;
            IF v_nos IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('POSSIBLE_SAME_APPLICANT', CASE WHEN r.decided_new THEN 'warning' ELSE 'review' END,
                         format('A preliminary applicant of the same surname and %s is on the portal (%s).', CASE WHEN v_phone IS NOT NULL THEN 'first name and birth date, or phone' ELSE 'first name and birth date' END, v_nos)
                         || CASE WHEN r.decided_new THEN ' Confirmed a new applicant: ' || coalesce(r.decided_new_reason, '') ELSE '' END,
                         'If it is the same person, give that application''s email so the row finds it; else confirm a new applicant on the row, with the reason.');
            END IF;
        END IF;
        -- V745: the same person, perhaps, on an earlier row of this very file — the import creates that row first and then finds it, so
        -- the dry run says so now (the surname and phone; the surname, first name and birth date; the JAMB number)
        v_pkeys := admissions.prelim_mig_person_keys(d);
        IF cardinality(v_pkeys) > 0 THEN
            SELECT x.row_no, x.person_keys, x.applicant INTO v_dup, v_dkeys, v_dup_name
              FROM (SELECT x2.row_no, x2.batch_id, x2.legacy_no, x2.person_keys, x2.applicant FROM admissions.prelim_migration_row x2
                     WHERE x2.person_keys && v_pkeys OFFSET 0) x
             WHERE x.batch_id = r.batch_id AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy
             ORDER BY x.row_no LIMIT 1;
            IF v_dup IS NOT NULL THEN
                v_basis := CASE WHEN EXISTS (SELECT 1 FROM unnest(v_dkeys) k WHERE k LIKE 'J|%' AND k = ANY (v_pkeys)) THEN 'the same JAMB number'
                                WHEN EXISTS (SELECT 1 FROM unnest(v_dkeys) k WHERE k LIKE 'SFD|%' AND k = ANY (v_pkeys)) THEN 'the same surname, first name and date of birth'
                                ELSE 'the same surname and phone' END;
                probs := probs || admissions.pg_mig_problem('POSSIBLE_SAME_APPLICANT', CASE WHEN r.decided_new THEN 'warning' ELSE 'review' END,
                         format('Row %s of this file (%s) has %s; the import brings that row in first.', v_dup, coalesce(v_dup_name, 'another applicant'), v_basis)
                         || CASE WHEN r.decided_new THEN ' Confirmed a new applicant: ' || coalesce(r.decided_new_reason, '') ELSE '' END,
                         'If it is the same person, keep one row for the applicant; else confirm a new applicant on this row, with the reason.');
            END IF;
        END IF;
        -- V745: a JAMB number an earlier migration brought (kept on the old portal's record): perhaps the same person — only a JAMB
        -- number (a placeholder such as "N/A", kept as written on many records, names nobody)
        IF admissions.prelim_mig_jamb_key(v_jamb) IS NOT NULL THEN   -- V755
            SELECT string_agg(x.application_no, ', ') INTO v_nos FROM (
                SELECT ap.application_no FROM admissions.prelim_legacy_application l JOIN admissions.application ap ON ap.id = l.application_id
                 WHERE l.legacy_jamb_reg_no = v_jamb ORDER BY ap.application_no LIMIT 3) x;
            IF v_nos IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('POSSIBLE_SAME_APPLICANT', CASE WHEN r.decided_new THEN 'warning' ELSE 'review' END,
                         format('An applicant brought from the old portal with JAMB number %s is on the portal (%s).', v_jamb, v_nos)
                         || CASE WHEN r.decided_new THEN ' Confirmed a new applicant: ' || coalesce(r.decided_new_reason, '') ELSE '' END,
                         'If it is the same person, give that application''s old number or email so the row finds it; else confirm a new applicant on the row, with the reason.');
            END IF;
        END IF;
    END IF;
    IF admissions.prelim_mig_jamb_key(v_jamb) IS NOT NULL THEN   -- V755: a placeholder is on nobody's record
        SELECT string_agg(x.w, ', ') INTO v_nos FROM (
            SELECT cc.session || ' ' || cc.surname AS w FROM admissions.candidate cc WHERE cc.jamb_key = v_jamb AND (v_app IS NULL OR cc.id <> a.candidate_id)
            UNION ALL
            -- V745: on another migrated application (a new applicant's is held for review above)
            SELECT ap.application_no FROM admissions.prelim_legacy_application l JOIN admissions.application ap ON ap.id = l.application_id
             WHERE v_app IS NOT NULL AND l.legacy_jamb_reg_no = v_jamb AND l.application_id <> v_app
            LIMIT 3) x;
        IF v_nos IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('JAMB_ON_PORTAL', 'warning', format('JAMB number %s is already on the portal (%s); kept on the old portal''s record only, never merged.', v_jamb, v_nos), NULL);
        END IF;
    END IF;
    -- a sitting on another live application of the route and session
    IF cardinality(v_keys) > 0 THEN
        SELECT string_agg(DISTINCT ap.application_no, ', ') INTO v_nos
          FROM admissions.screening_olevel so
          JOIN admissions.prelim_review pr ON pr.application_id = so.application_id AND pr.route = b.route AND pr.state <> 'WITHDRAWN'
          JOIN admissions.application ap ON ap.id = so.application_id
         WHERE so.active AND ap.session = b.session AND so.application_id IS DISTINCT FROM v_app
           AND (so.exam_year, upper(regexp_replace(so.exam_number, '\s', '', 'g'))) IN
               (SELECT split_part(k, '|', 2)::int, split_part(k, '|', 3) FROM unnest(v_keys) k)
           AND (upper(so.exam_body) || '|' || so.exam_year || '|' || upper(regexp_replace(so.exam_number, '\s', '', 'g'))) = ANY (v_keys);
        IF v_nos IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('OLEVEL_ELSEWHERE', 'conflict', format('An O''Level sitting of the row is already on another %s application for %s (%s).', p.name, b.session, v_nos),
                     'One examination sitting is one person''s: check which applicant it belongs to.');
        END IF;
    END IF;

    -- the payment: a "Paid" is held for the Bursary; nothing is invented
    v_ref := admissions.pg_mig_t(d, 'paymentReference');
    v_gw := admissions.pg_mig_t(d, 'gatewayReference');
    v_amt_raw := admissions.pg_mig_t(d, 'amountPaid');
    v_amt := admissions.pg_mig_amount(v_amt_raw);
    v_paid_on := admissions.pg_mig_date(admissions.pg_mig_t(d, 'paymentDate'));
    SELECT f.application_fee + f.portal_charge INTO v_fee FROM admissions.route_fee_rule(b.session, b.route) f;
    IF v_pay = 'PAID' THEN
        IF v_amt IS NULL AND v_amt_raw IS NULL THEN
            -- V745: as a missing reference is: held all the same, and flagged for the Bursary (the applicant who paid is never charged again)
            probs := probs || admissions.pg_mig_problem('AMOUNT_MISSING', 'warning',
                     'Paid, with no amount: held, and flagged for the Bursary to confirm the amount from the evidence.', NULL);
        ELSIF v_amt IS NULL THEN
            probs := probs || admissions.pg_mig_problem('AMOUNT_MISSING', 'error', format('Paid, but the amount "%s" is not read.', left(v_amt_raw, 20)),
                     'Give the amount paid in naira, or leave it blank for the Bursary to confirm.');
        ELSIF v_fee IS NOT NULL AND v_amt <> v_fee THEN
            probs := probs || admissions.pg_mig_problem('AMOUNT_DIFFERS', 'warning',
                     format('The amount paid (₦%s) is not the %s application fee (₦%s); held for the Bursary to settle.', to_char(v_amt, 'FM999,999,990.##'), p.name, to_char(v_fee, 'FM999,999,990.##')), NULL);
        END IF;
        IF v_ref IS NULL THEN
            probs := probs || admissions.pg_mig_problem('NO_PAYMENT_REFERENCE', 'warning',
                     'Paid, with no payment reference: held, and flagged for the Bursary to find the reference.' || CASE WHEN v_gw IS NOT NULL THEN ' The gateway''s reference is kept.' ELSE '' END, NULL);
        ELSE
            -- V745: another row's payment or gateway reference (the import records each reference once, either way round)
            SELECT min(x.row_no) INTO v_dup FROM admissions.prelim_migration_row x
             WHERE x.batch_id = r.batch_id AND (x.fee_ref = upper(btrim(v_ref)) OR x.gateway_ref = upper(btrim(v_ref))) AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
            IF v_dup IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_IN_FILE', 'duplicate', format('Payment reference %s is also on row %s, another applicant.', left(v_ref, 40), v_dup),
                         'One payment belongs to one applicant: correct the reference.');
            ELSE
                v_clash := admissions.prelim_mig_fee_clash(v_ref, v_app);
                IF v_clash IS NOT NULL THEN
                    probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_ELSEWHERE', 'conflict', format('Payment reference %s is %s.', left(v_ref, 40), v_clash),
                             'A payment is recorded once: the Bursary settles a payment claimed twice.');
                END IF;
            END IF;
        END IF;
        IF v_gw IS NOT NULL THEN
            -- V745: a gateway reference another row of the file gives is one payment claimed twice, as the import would find it
            SELECT min(x.row_no) INTO v_dup FROM admissions.prelim_migration_row x
             WHERE x.batch_id = r.batch_id AND (x.gateway_ref = upper(btrim(v_gw)) OR x.fee_ref = upper(btrim(v_gw))) AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
            IF v_dup IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_IN_FILE', 'duplicate', format('Gateway reference %s is also on row %s, another applicant.', left(v_gw, 40), v_dup),
                         'One payment belongs to one applicant: correct the reference.');
            ELSIF v_clash IS NULL THEN
                v_clash := admissions.prelim_mig_fee_clash(v_gw, v_app);
                IF v_clash IS NOT NULL THEN
                    probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_ELSEWHERE', 'conflict', format('Gateway reference %s is %s.', left(v_gw, 40), v_clash),
                             'A payment is recorded once: the Bursary settles a payment claimed twice.');
                END IF;
            END IF;
        END IF;
        IF v_app IS NOT NULL AND a.fee_confirmed_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee x WHERE x.application_id = v_app AND x.state <> 'REJECTED') THEN
            probs := probs || admissions.pg_mig_problem('FEE_ALREADY_PAID_HERE', 'warning',
                     format('Application %s''s fee is already paid on this portal: the old payment is not held.', a.application_no), NULL);
        END IF;
    ELSIF v_ref IS NOT NULL OR v_amt_raw IS NOT NULL OR v_gw IS NOT NULL THEN
        probs := probs || admissions.pg_mig_problem('PAYMENT_INCONSISTENT', 'error',
                 format('A payment reference or amount is given, but the payment status is %s.', CASE WHEN v_pay IS NULL THEN 'blank' ELSE '"' || left(admissions.pg_mig_t(d, 'paymentStatus'), 30) || '"' END),
                 'Mark the payment Paid (it is held for the Bursary to verify), or clear the reference and amount.');
    END IF;
    IF v_admission IN ('ADMITTED', 'ACCEPTED') AND v_pay IS DISTINCT FROM 'PAID' THEN
        probs := probs || admissions.pg_mig_problem('ADMITTED_WITHOUT_FEE', 'warning', 'Admitted on the old portal with no application fee paid.', 'The Bursary looks into it; the admission comes in as it stood.');
    END IF;
    IF jsonb_array_length(v_sittings) = 0 AND v_state IN ('SUBMITTED', 'UNDER_REVIEW') AND NOT probs @> '[{"level":"error"}]' THEN
        probs := probs || admissions.pg_mig_problem('OLEVEL_NONE', 'warning', 'No O''Level result is given: the eligibility reads "result required" until the Office records it.', NULL);
    END IF;

    v_verdict := CASE WHEN probs @> '[{"level":"duplicate"}]' THEN 'DUPLICATE_IN_FILE'
                      WHEN probs @> '[{"level":"error"}]' THEN 'ERROR'
                      WHEN probs @> '[{"level":"conflict"}]' THEN 'CONFLICT'
                      WHEN probs @> '[{"level":"review"}]' THEN 'REQUIRES_REVIEW'
                      WHEN probs @> '[{"level":"warning"}]' THEN 'WARNING'
                      ELSE 'READY' END;
    v_answers := jsonb_strip_nulls(jsonb_build_object(
        'date_of_birth', v_dob::text, 'mobile', v_phone, 'personal_email', v_email,
        'state_of_origin', left(admissions.pg_mig_t(d, 'stateOfOrigin'), 400), 'lga', left(admissions.pg_mig_t(d, 'lga'), 400),
        'nationality', left(admissions.pg_mig_t(d, 'nationality'), 400), 'home_address', left(admissions.pg_mig_t(d, 'address'), 400),
        'kin_name', left(admissions.pg_mig_t(d, 'nextOfKinName'), 400), 'kin_relationship', left(admissions.pg_mig_t(d, 'nextOfKinRelationship'), 400),
        'kin_mobile', v_kin_phone));
    RETURN jsonb_build_object('verdict', v_verdict, 'match', v_match, 'action', v_action, 'applicationId', v_app, 'problems', probs,
                              'legacy', v_legacy, 'surname', upper(v_surname), 'firstName', initcap(v_first), 'otherNames', initcap(v_others), 'sex', v_sex, 'dob', v_dob,
                              'email', v_email, 'phone', v_phone, 'jamb', v_jamb, 'state', v_state, 'admission', v_admission, 'targetState', v_target_state,
                              'payment', v_pay, 'reference', v_ref, 'gatewayReference', v_gw, 'amount', v_amt, 'paidOn', v_paid_on, 'appliedOn', v_applied,
                              'targetId', v_target, 'specialisationId', v_spec, 'sittings', v_sittings, 'answers', v_answers,
                              -- V745: what a RECONCILE row without "fill in missing details" leaves as it stands here
                              'numberOnly', v_action = 'RECONCILE' AND NOT b.allow_update, 'leftAlone', to_jsonb(v_left));
END $function$;

-- ── 4 · the postgraduate dry run (V675's, restated) ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admissions.pg_migration_assess(p_row uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    r admissions.pg_migration_row; b admissions.pg_migration_batch; d jsonb; probs jsonb := '[]';
    v_legacy text; v_newno text; v_matric text; v_email text; v_email_raw text; v_surname text; v_given text; v_full text;
    v_session text; v_raw text; v_prog text; v_spec uuid; v_how text; v_problem text; v_detail text; v_x text; v_n int;
    v_target text; v_word text; v_accepted boolean := false; v_acc_ok boolean := false; v_screen text; v_dob date; v_phone text;
    v_app uuid; v_app2 uuid; v_app3 uuid; v_student uuid; v_student2 uuid; v_student3 uuid; v_nos text;
    a admissions.pg_application; ap admissions.pg_applicant; st people.student; lg admissions.pg_legacy_application;
    v_match text; v_action text; v_verdict text; v_dup int; v_clash text;
    f record; v_status text; v_ref text; v_amt numeric; v_refs text[] := '{}';
BEGIN
    SELECT * INTO r FROM admissions.pg_migration_row WHERE id = p_row;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such migration row' USING ERRCODE = '23503'; END IF;
    SELECT * INTO b FROM admissions.pg_migration_batch WHERE id = r.batch_id;
    d := r.data;

    -- the old number: required, and once in the file
    v_legacy := upper(admissions.pg_mig_t(d, 'legacyApplicationNo'));
    IF v_legacy IS NULL THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_MISSING', 'error', 'The old application number is missing.',
                 'Copy it from the old portal: it is how this applicant is found again.');
    ELSIF length(v_legacy) > 60 OR v_legacy !~ '^[A-Z0-9][A-Z0-9/._ -]*$' THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_FORM', 'error', format('"%s" is not an application number.', left(v_legacy, 60)),
                 'Letters, digits and / . _ - only, as the old portal shows it.');
    ELSE
        SELECT min(x.row_no) INTO v_dup FROM admissions.pg_migration_row x
         WHERE x.batch_id = r.batch_id AND x.legacy_no = v_legacy AND x.row_no < r.row_no;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('DUPLICATE_IN_FILE', 'duplicate', format('Row %s has the same old application number.', v_dup),
                     'Keep one row for the applicant; this repeat is not imported.');
        END IF;
        -- V755: an old number a migrated preliminary applicant signs in with is theirs (the import refuses it: V745's trigger) — said now
        v_clash := admissions.prelim_legacy_number_holder(v_legacy);
        IF v_clash IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_NO_IS_PORTAL_NUMBER', 'conflict',
                     format('Old application number %s is the old portal number a preliminary applicant brought across (%s) signs in with.', v_legacy, v_clash),
                     'One number signs in one applicant: check the number against the old portal; ICT settles a number already in use.');
        END IF;
    END IF;

    -- the name
    v_surname := admissions.pg_mig_t(d, 'lastName');
    v_given := nullif(btrim(concat_ws(' ', admissions.pg_mig_t(d, 'firstName'), admissions.pg_mig_t(d, 'middleName'), admissions.pg_mig_t(d, 'otherNames'))), '');
    v_full := admissions.pg_mig_t(d, 'fullName');
    IF v_surname IS NULL AND v_given IS NULL AND v_full IS NOT NULL THEN
        IF position(',' IN v_full) > 0 THEN
            v_surname := btrim(split_part(v_full, ',', 1)); v_given := nullif(btrim(substr(v_full, position(',' IN v_full) + 1)), '');
        ELSE
            v_surname := split_part(v_full, ' ', 1); v_given := nullif(btrim(substr(v_full, length(split_part(v_full, ' ', 1)) + 1)), '');
        END IF;
    END IF;
    IF v_surname IS NULL OR v_given IS NULL THEN
        probs := probs || admissions.pg_mig_problem('NAME_MISSING', 'error', 'The last name or the first name is missing.', 'Give both, as on the old portal.');
    ELSIF (v_surname || ' ' || v_given) ~ '[0-9=@<>{}\\;|]' OR v_surname !~ '[[:alpha:]]' OR length(v_surname) > 80 OR length(v_given) > 120 THEN
        probs := probs || admissions.pg_mig_problem('NAME_FORM', 'error', format('"%s, %s" is not a name.', left(v_surname, 40), left(v_given, 40)),
                 'Letters, spaces, hyphens and apostrophes only.');
    END IF;

    -- the email (the sign-in), once in the file
    v_email_raw := lower(admissions.pg_mig_t(d, 'email'));
    IF v_email_raw IS NOT NULL AND (v_email_raw !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' OR length(v_email_raw) > 254) THEN
        probs := probs || admissions.pg_mig_problem('EMAIL_FORM', 'error', format('"%s" is not an email address.', left(v_email_raw, 80)), 'Correct it, or leave it blank for an applicant already on this portal.');
    ELSE
        v_email := v_email_raw;
    END IF;
    IF v_email IS NOT NULL THEN
        SELECT min(x.row_no) INTO v_dup FROM admissions.pg_migration_row x
         WHERE x.batch_id = r.batch_id AND x.email = v_email AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('DUPLICATE_EMAIL_IN_FILE', 'duplicate',
                     format('Row %s has the same email for another old application.', v_dup),
                     'One person holds one postgraduate application here: keep the application they are placed in now.');
        END IF;
    END IF;

    -- the rest of the person: read, or left out and said so
    v_x := admissions.pg_mig_t(d, 'gender');
    IF v_x IS NOT NULL AND upper(left(v_x, 1)) NOT IN ('M', 'F') THEN
        probs := probs || admissions.pg_mig_problem('GENDER_UNKNOWN', 'warning', format('Gender "%s" is not read; left blank.', left(v_x, 20)), 'Male or Female.');
    END IF;
    v_x := admissions.pg_mig_t(d, 'dateOfBirth'); v_dob := admissions.pg_mig_date(v_x);
    IF v_x IS NOT NULL AND v_dob IS NULL THEN
        probs := probs || admissions.pg_mig_problem('DATE_OF_BIRTH_FORM', 'warning', format('Date of birth "%s" is not read; left blank.', left(v_x, 20)), 'DD/MM/YYYY.');
    END IF;
    v_x := admissions.pg_mig_t(d, 'phone'); v_phone := admissions.pg_mig_phone(v_x);
    IF v_x IS NOT NULL AND v_phone IS NULL THEN
        probs := probs || admissions.pg_mig_problem('PHONE_FORM', 'warning', format('Phone "%s" is not read; left blank.', left(v_x, 20)), 'Eleven digits, 080…, or +234….');
    END IF;
    FOREACH v_x IN ARRAY ARRAY['applicationDate', 'applicationFeeDate', 'admissionDate', 'acceptanceFeeDate', 'screeningDate', 'schoolFeesDate'] LOOP
        IF admissions.pg_mig_t(d, v_x) IS NOT NULL AND admissions.pg_mig_date(admissions.pg_mig_t(d, v_x)) IS NULL THEN
            probs := probs || admissions.pg_mig_problem('DATE_FORM', 'warning',
                     format('%s "%s" is not read; today stands in for it.', (SELECT c.header FROM admissions.pg_migration_columns(b.kind) c WHERE c.key = v_x), left(admissions.pg_mig_t(d, v_x), 20)),
                     'DD/MM/YYYY.');
        END IF;
    END LOOP;

    -- the session, as this portal holds it
    v_raw := admissions.pg_mig_t(d, 'session');
    v_session := admissions.pg_legacy_session(v_raw);
    IF v_raw IS NULL THEN
        probs := probs || admissions.pg_mig_problem('SESSION_MISSING', 'error', 'The application session is missing.', 'YYYY/YYYY, as on the Sessions sheet.');
    ELSIF v_session IS NULL THEN
        probs := probs || admissions.pg_mig_problem('SESSION_FORM', 'error', format('"%s" is not a session.', left(v_raw, 20)), 'YYYY/YYYY, e.g. 2025/2026.');
    ELSIF NOT admissions.pg_session_known(v_session) THEN
        probs := probs || admissions.pg_mig_problem('SESSION_UNKNOWN', 'error', format('%s is not a session on this portal''s calendar.', v_session),
                 'Use a session on the Sessions sheet; the Academic Office adds a session to the calendar.');
    END IF;
    IF b.kind = 'ADMITTED' AND admissions.pg_mig_t(d, 'admissionSession') IS NOT NULL THEN
        v_x := admissions.pg_legacy_session(admissions.pg_mig_t(d, 'admissionSession'));
        IF v_x IS NULL OR NOT admissions.pg_session_known(v_x) THEN
            probs := probs || admissions.pg_mig_problem('ADMISSION_SESSION_UNKNOWN', 'error',
                     format('Admission session "%s" is not a session on this portal''s calendar.', left(admissions.pg_mig_t(d, 'admissionSession'), 20)),
                     'YYYY/YYYY, as on the Sessions sheet, or blank for the application session.');
        END IF;
    END IF;

    -- the programme the applicant is placed in now: mapped, never guessed, never created
    IF admissions.pg_mig_t(d, 'programme') IS NULL AND admissions.pg_mig_t(d, 'programmeCode') IS NULL THEN
        probs := probs || admissions.pg_mig_problem('PROGRAMME_MISSING', 'error', 'The programme is missing.', 'The programme the applicant is placed in now on the old portal.');
    ELSE
        SELECT x.programme_code, x.specialisation_id, x.how, x.problem, x.detail INTO v_prog, v_spec, v_how, v_problem, v_detail
          FROM admissions.pg_legacy_programme_of(admissions.pg_mig_t(d, 'programmeCode'), admissions.pg_mig_t(d, 'programme'),
                                                 admissions.pg_mig_t(d, 'department'), admissions.pg_mig_t(d, 'faculty')) x;
        IF v_problem IN ('PROGRAMME_NOT_MAPPED', 'PROGRAMME_AMBIGUOUS') THEN
            probs := probs || admissions.pg_mig_problem(v_problem, 'review', 'Programme not found: ' || v_detail || '.',
                     'Map the old programme to this portal''s programme on Programme mapping, then check the file again.');
            v_prog := NULL;
        ELSIF v_problem = 'PLACEMENT_DIFFERS' THEN
            probs := probs || admissions.pg_mig_problem(v_problem, 'conflict', v_detail || '.', 'Correct the faculty or department, or the programme, to the old portal''s current placement.');
        ELSIF v_problem IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem(v_problem, 'error', v_detail || '.', 'Give a postgraduate programme this portal runs, or map the old one.');
            v_prog := NULL;
        END IF;
        v_x := admissions.pg_mig_t(d, 'specialisation');
        IF v_x IS NOT NULL AND v_prog IS NOT NULL THEN
            SELECT ps.id INTO v_spec FROM catalogue.programme_specialisation ps
             WHERE ps.programme_code = v_prog AND ps.active AND (lower(btrim(ps.name)) = lower(v_x) OR upper(ps.code) = upper(v_x)) LIMIT 1;
            IF v_spec IS NULL THEN
                probs := probs || admissions.pg_mig_problem('SPECIALISATION_UNKNOWN', 'warning',
                         format('"%s" is not a specialisation of the programme; left unset.', left(v_x, 60)), 'As on the Specialisations sheet; the School can set it on the application.');
            END IF;
        END IF;
    END IF;

    -- the state the old portal reached, read onto this portal's states
    IF b.kind = 'APPLICANTS' THEN
        v_word := coalesce(admissions.pg_mig_t(d, 'applicationStatus'), 'SUBMITTED');
        v_target := admissions.pg_legacy_state(v_word);
        IF v_target IS NULL THEN
            probs := probs || admissions.pg_mig_problem('STATUS_UNMAPPED', 'review', format('Application status "%s" is not a state this portal knows.', left(v_word, 40)),
                     'Use a status on the Statuses sheet; an application withdrawn or cancelled on the old portal is not migrated as one.');
        ELSIF v_target IN ('OFFERED', 'ACCEPTED') THEN
            probs := probs || admissions.pg_mig_problem('ADMITTED_IN_APPLICANT_FILE', 'error', format('"%s": admitted on the old portal.', left(v_word, 40)),
                     'Upload this applicant with the admitted PG applicants template, which carries the admission.');
        END IF;
    ELSE
        v_word := admissions.pg_mig_t(d, 'admissionStatus');
        v_target := admissions.pg_legacy_state(v_word);
        IF v_word IS NULL THEN
            probs := probs || admissions.pg_mig_problem('ADMISSION_STATUS_MISSING', 'error', 'The admission status is missing.', 'Admitted, Offered or Accepted.');
        ELSIF v_target IS NULL THEN
            probs := probs || admissions.pg_mig_problem('STATUS_UNMAPPED', 'review', format('Admission status "%s" is not a state this portal knows.', left(v_word, 40)),
                     'Use a status on the Statuses sheet.');
        ELSIF v_target NOT IN ('OFFERED', 'ACCEPTED') THEN
            probs := probs || admissions.pg_mig_problem('NOT_ADMITTED_IN_ADMITTED_FILE', 'error', format('"%s": not admitted on the old portal.', left(v_word, 40)),
                     'Upload this applicant with the PG applicant template.');
            v_target := NULL;
        END IF;
        IF v_target IS NOT NULL THEN
            -- the acceptance: taken as paid only on a verified payment with its reference
            v_word := upper(coalesce(admissions.pg_mig_t(d, 'acceptanceStatus'), ''));
            v_accepted := v_target = 'ACCEPTED' OR v_word IN ('ACCEPTED', 'YES', 'DONE', 'COMPLETED', 'PAID', 'OFFER ACCEPTED', 'ACCEPTANCE PAID');
            IF v_word <> '' AND NOT v_accepted AND v_word NOT IN ('NO', 'NOT ACCEPTED', 'PENDING', 'NONE') THEN
                probs := probs || admissions.pg_mig_problem('ACCEPTANCE_WORD', 'warning', format('Acceptance status "%s" is not read.', left(v_word, 30)), 'Accepted, or blank.');
            END IF;
            IF v_accepted THEN
                IF admissions.pg_mig_t(d, 'acceptanceFeeReference') IS NOT NULL AND admissions.pg_mig_amount(admissions.pg_mig_t(d, 'acceptanceFeeAmount')) IS NOT NULL THEN
                    v_acc_ok := admissions.pg_mig_paid(admissions.pg_mig_t(d, 'acceptanceVerification')) = 'VERIFIED';
                    IF NOT v_acc_ok THEN
                        probs := probs || admissions.pg_mig_problem('ACCEPTANCE_UNDER_REVIEW', 'warning',
                                 'The acceptance fee is not verified: it is held for the Bursary or the PG Secretary to verify, and the offer stands until then.',
                                 'Nothing to correct; the applicant is not asked to pay it again meanwhile.');
                    END IF;
                ELSE
                    probs := probs || admissions.pg_mig_problem('ACCEPTANCE_NO_PAYMENT', 'warning',
                             'Accepted on the old portal with no payment reference and amount: the acceptance fee is not taken as paid; the offer stands.',
                             'Give the acceptance payment''s reference and amount, or the School records the acceptance on the application once it has checked.');
                END IF;
            END IF;
            v_target := CASE WHEN v_acc_ok THEN 'ACCEPTED' ELSE 'OFFERED' END;
            -- the screening the old portal recorded: historical, completed
            v_word := upper(regexp_replace(coalesce(admissions.pg_mig_t(d, 'screeningDecision'), ''), '[ -]+', '_', 'g'));
            v_screen := CASE WHEN v_word IN ('CLEARED', 'PASSED', 'SCREENED', 'SUCCESSFUL', 'VERIFIED', 'COMPLETED') THEN 'CLEARED'
                             WHEN v_word IN ('NOT_CLEARED', 'FAILED', 'REJECTED', 'UNSUCCESSFUL') THEN 'NOT_CLEARED'
                             WHEN v_word IN ('CORRECTION_REQUIRED', 'CORRECTION', 'INCOMPLETE') THEN 'CORRECTION_REQUIRED'
                             WHEN v_word IN ('PENDING', 'NOT_SCREENED', 'AWAITING', 'SCHEDULED') THEN 'PENDING' END;
            IF v_word <> '' AND v_screen IS NULL THEN
                probs := probs || admissions.pg_mig_problem('SCREENING_WORD', 'warning', format('Screening decision "%s" is not read.', left(v_word, 30)), 'Cleared, Not cleared, Correction required or Pending.');
            ELSIF v_screen = 'CLEARED' AND v_target = 'ACCEPTED' THEN
                v_target := 'ADMITTED';
            ELSIF v_screen = 'CLEARED' THEN
                probs := probs || admissions.pg_mig_problem('SCREENING_WAITS', 'warning',
                         'Cleared at screening on the old portal: kept, and applied once the acceptance is settled.', NULL);
            END IF;
        END IF;
    END IF;

    -- who this is: the student on the register, the application on this portal, or nobody yet
    v_newno := upper(admissions.pg_mig_t(d, 'applicationNo'));
    IF v_newno IS NOT NULL THEN
        SELECT x.id INTO v_app FROM admissions.pg_application x WHERE x.application_no = v_newno;
        IF v_app IS NULL THEN
            probs := probs || admissions.pg_mig_problem('NEW_NUMBER_UNKNOWN', 'error', format('%s is not an application on this portal.', left(v_newno, 30)),
                     'Leave the new application number blank unless the applicant already has one here.');
        END IF;
    END IF;
    IF v_legacy IS NOT NULL THEN
        SELECT x.application_id INTO v_app2 FROM admissions.pg_legacy_application x WHERE upper(btrim(x.legacy_application_no)) = v_legacy;
    END IF;
    IF v_email IS NOT NULL THEN
        SELECT x.id INTO v_app3 FROM admissions.pg_application x JOIN admissions.pg_applicant p ON p.id = x.applicant_id WHERE lower(p.email) = v_email;
    END IF;
    SELECT count(DISTINCT x.id), string_agg(DISTINCT x.application_no, ', ')
      INTO v_n, v_nos FROM admissions.pg_application x WHERE x.id = ANY (ARRAY[v_app, v_app2, v_app3]);
    IF v_n > 1 THEN
        probs := probs || admissions.pg_mig_problem('IDENTITY_SPLIT', 'conflict',
                 format('The old number, the email and the new number point to different applications here (%s).', v_nos),
                 'Settle which application is this applicant''s before importing the row.');
    END IF;
    v_app := coalesce(v_app, v_app2, v_app3);

    v_matric := upper(admissions.pg_mig_t(d, 'matricNo'));
    IF v_matric IS NOT NULL THEN
        SELECT s.id INTO v_student FROM people.student s WHERE upper(s.matric_no) = v_matric;
        IF v_student IS NULL THEN
            probs := probs || admissions.pg_mig_problem('MATRIC_NOT_ON_RECORD', 'review', format('No student holds matriculation number %s here.', left(v_matric, 40)),
                     'Load the student through Records → Migration → PG students first, then check the file again; a matriculation number is never issued twice.');
        END IF;
    END IF;
    IF v_legacy IS NOT NULL THEN
        SELECT count(*), (array_agg(b2.student_id))[1] INTO v_n, v_student2 FROM people.biodata b2
         WHERE b2.field = 'legacy_appno' AND upper(btrim(b2.value)) = v_legacy;
        IF v_n > 1 THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_ON_SEVERAL_STUDENTS', 'review', format('%s students on the register carry old application number %s.', v_n, v_legacy),
                     'Give the matriculation number of the one this row is.');
            v_student2 := NULL;
        END IF;
    END IF;
    IF v_app IS NOT NULL THEN
        SELECT * INTO a FROM admissions.pg_application WHERE id = v_app;
        v_student3 := a.student_id;
    END IF;
    SELECT count(DISTINCT u) INTO v_n FROM unnest(ARRAY[v_student, v_student2, v_student3]) u WHERE u IS NOT NULL;
    IF v_n > 1 THEN
        probs := probs || admissions.pg_mig_problem('STUDENT_SPLIT', 'conflict',
                 'The matriculation number, the old application number and the application point to different students on the register.',
                 'Settle which student this is before importing the row.');
    END IF;
    v_student := coalesce(v_student, v_student3, v_student2);

    IF v_app IS NOT NULL THEN
        SELECT * INTO ap FROM admissions.pg_applicant WHERE id = a.applicant_id;
        SELECT * INTO lg FROM admissions.pg_legacy_application WHERE application_id = v_app;
        v_match := CASE WHEN a.student_id IS NOT NULL THEN 'EXISTING_STUDENT' ELSE 'EXISTING_APPLICANT' END;
        v_action := 'UPDATE';
        IF lg.application_id IS NOT NULL AND v_legacy IS NOT NULL AND upper(btrim(lg.legacy_application_no)) <> v_legacy THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_DIFFERS', 'conflict',
                     format('Application %s already carries old application number %s.', a.application_no, lg.legacy_application_no),
                     'One application, one old number: check which is right.');
        END IF;
        IF v_surname IS NOT NULL AND admissions.pg_legacy_key(ap.surname) IS DISTINCT FROM admissions.pg_legacy_key(v_surname) THEN
            probs := probs || admissions.pg_mig_problem('NAME_DIFFERS', 'conflict',
                     format('Application %s is in the name of %s, %s.', a.application_no, ap.surname, ap.other_names),
                     'Check that this is the same person; a name is corrected on the application, not by a migration.');
        END IF;
        IF v_prog IS NOT NULL AND a.programme_code <> v_prog THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_DIFFERS', 'conflict',
                     format('Application %s is for %s here; the file says %s.', a.application_no, a.programme_code, v_prog),
                     'The application''s programme stands: correct the file, or the application, to the approved current programme.');
        END IF;
        IF v_target IS NOT NULL THEN
            IF (a.state = 'NOT_OFFERED' AND v_target IN ('OFFERED', 'ACCEPTED', 'ADMITTED'))
               OR (a.state IN ('OFFERED', 'ACCEPTED', 'ADMITTED') AND v_target = 'NOT_OFFERED') THEN
                probs := probs || admissions.pg_mig_problem('DECISION_DIFFERS', 'conflict',
                         format('Application %s is %s here; the old portal says %s.', a.application_no, lower(replace(a.state, '_', ' ')), lower(replace(v_target, '_', ' '))),
                         'The two decisions differ: the School settles which stands.');
            ELSIF admissions.pg_state_rank(v_target) > admissions.pg_state_rank(a.state) THEN
                v_action := 'RECONCILE';
            ELSIF admissions.pg_state_rank(v_target) < admissions.pg_state_rank(a.state) THEN
                probs := probs || admissions.pg_mig_problem('PORTAL_FURTHER', 'warning',
                         format('Application %s is further along here (%s): kept, never moved back.', a.application_no, lower(replace(a.state, '_', ' '))), NULL);
            END IF;
        END IF;
        IF a.student_id IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('ALREADY_STUDENT', 'warning',
                     format('Already on the register (%s): linked, not admitted again.', (SELECT coalesce(s.matric_no, s.admission_no) FROM people.student s WHERE s.id = a.student_id)), NULL);
        END IF;
    ELSIF v_student IS NOT NULL THEN
        SELECT * INTO st FROM people.student WHERE id = v_student;
        v_match := 'EXISTING_STUDENT'; v_action := 'LINK_STUDENT';
        IF st.entry_mode IS DISTINCT FROM 'POSTGRADUATE' THEN
            probs := probs || admissions.pg_mig_problem('NOT_PG_STUDENT', 'conflict',
                     format('%s is not a postgraduate student here.', coalesce(st.matric_no, st.admission_no)), 'Check the matriculation number.');
        END IF;
        IF v_prog IS NOT NULL AND st.programme_code <> v_prog THEN
            probs := probs || admissions.pg_mig_problem('PROGRAMME_DIFFERS', 'conflict',
                     format('%s is in %s on the register; the file says %s.', coalesce(st.matric_no, st.admission_no), st.programme_code, v_prog),
                     'The register''s placement stands: if it is wrong, correct it through the programme swap, then check the file again.');
        END IF;
        IF v_surname IS NOT NULL AND admissions.pg_legacy_key(st.surname) IS DISTINCT FROM admissions.pg_legacy_key(v_surname) THEN
            probs := probs || admissions.pg_mig_problem('NAME_DIFFERS', 'conflict',
                     format('%s is in the name of %s, %s.', coalesce(st.matric_no, st.admission_no), st.surname, st.other_names),
                     'Check that this is the same person.');
        END IF;
        SELECT b2.value INTO v_x FROM people.biodata b2 WHERE b2.student_id = st.id AND b2.field = 'legacy_appno';
        IF v_x IS NOT NULL AND v_legacy IS NOT NULL AND upper(btrim(v_x)) <> v_legacy THEN
            probs := probs || admissions.pg_mig_problem('LEGACY_NUMBER_DIFFERS', 'conflict',
                     format('%s already carries old application number %s.', coalesce(st.matric_no, st.admission_no), v_x), 'One student, one old number: check which is right.');
        END IF;
        probs := probs || admissions.pg_mig_problem('ALREADY_STUDENT', 'warning',
                 format('Already on the register (%s): linked, not admitted again.', coalesce(st.matric_no, st.admission_no)), NULL);
    ELSE
        v_match := 'NEW_APPLICANT'; v_action := 'CREATE';
        IF v_email IS NULL AND v_email_raw IS NULL THEN
            probs := probs || admissions.pg_mig_problem('EMAIL_MISSING', 'error', 'A new applicant needs an email: it is their sign-in on this portal.',
                     'Give the email the applicant used on the old portal.');
        END IF;
        -- the same person, perhaps, under another email: never created twice unseen
        IF v_surname IS NOT NULL THEN
            SELECT string_agg(x.application_no, ', ') INTO v_nos FROM (
                SELECT a2.application_no FROM admissions.pg_applicant p JOIN admissions.pg_application a2 ON a2.applicant_id = p.id
                 WHERE (v_phone IS NOT NULL AND p.phone = v_phone AND admissions.pg_legacy_key(p.surname) = admissions.pg_legacy_key(v_surname))
                    OR (v_dob IS NOT NULL AND upper(p.surname) = upper(v_surname) AND p.date_of_birth = v_dob)
                 LIMIT 3) x;
            IF v_nos IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('POSSIBLE_SAME_APPLICANT', CASE WHEN r.decided_new THEN 'warning' ELSE 'review' END,
                         format('An applicant of the same surname and %s is on this portal (%s).', CASE WHEN v_phone IS NOT NULL THEN 'phone or birth date' ELSE 'birth date' END, v_nos)
                         || CASE WHEN r.decided_new THEN ' The School confirmed a new applicant: ' || coalesce(r.decided_new_reason, '') ELSE '' END,
                         'Give that application''s number as the new application number if it is the same person; else confirm a new applicant on the row.');
            END IF;
            SELECT string_agg(coalesce(s.matric_no, s.admission_no), ', ') INTO v_nos FROM (
                SELECT s.matric_no, s.admission_no FROM people.student s
                 WHERE s.entry_mode = 'POSTGRADUATE' AND upper(s.surname) = upper(v_surname)
                   AND ((v_dob IS NOT NULL AND s.date_of_birth = v_dob) OR (v_prog IS NOT NULL AND s.programme_code = v_prog
                        AND admissions.pg_legacy_key(s.other_names) = admissions.pg_legacy_key(v_given)))
                 LIMIT 3) s;
            IF v_nos IS NOT NULL THEN
                probs := probs || admissions.pg_mig_problem('POSSIBLE_STUDENT', CASE WHEN r.decided_new THEN 'warning' ELSE 'review' END,
                         format('A postgraduate student of the same name is on the register (%s).', v_nos)
                         || CASE WHEN r.decided_new THEN ' The School confirmed a new applicant: ' || coalesce(r.decided_new_reason, '') ELSE '' END,
                         'Give the matriculation number if it is the same person; else confirm a new applicant on the row.');
            END IF;
        END IF;
    END IF;

    -- the fees: one old reference, one fee
    FOR f IN SELECT * FROM (VALUES
                ('APPLICATION', 'applicationFeeStatus', 'applicationFeeReference', 'applicationFeeAmount', 'Application fee'),
                ('ACCEPTANCE', 'acceptanceVerification', 'acceptanceFeeReference', 'acceptanceFeeAmount', 'Acceptance fee'),
                ('SCHOOL_FEES', 'schoolFeesVerification', 'schoolFeesReference', 'schoolFeesAmount', 'School fees')) x(kind, status_key, ref_key, amount_key, label)
              WHERE x.kind = 'APPLICATION' OR b.kind = 'ADMITTED' LOOP
        v_ref := admissions.pg_mig_t(d, f.ref_key);
        v_amt := admissions.pg_mig_amount(admissions.pg_mig_t(d, f.amount_key));
        v_status := CASE f.kind WHEN 'APPLICATION' THEN admissions.pg_mig_paid(admissions.pg_mig_t(d, f.status_key))
                                WHEN 'ACCEPTANCE' THEN CASE WHEN v_accepted THEN 'ANY' ELSE 'NONE' END
                                ELSE CASE WHEN v_ref IS NOT NULL THEN 'ANY' ELSE 'NONE' END END;
        IF f.kind = 'APPLICATION' AND v_status = 'UNKNOWN' THEN
            probs := probs || admissions.pg_mig_problem('FEE_STATUS_UNKNOWN', 'warning',
                     format('Application fee status "%s" is not read: the fee is not recorded.', left(admissions.pg_mig_t(d, f.status_key), 30)), 'Verified, Paid or Unpaid.');
            CONTINUE;
        END IF;
        CONTINUE WHEN v_status = 'NONE';
        IF v_action = 'LINK_STUDENT' AND f.kind <> 'SCHOOL_FEES' THEN
            probs := probs || admissions.pg_mig_problem('FEE_NOT_FOR_STUDENT', 'warning',
                     f.label || ': a student on the register has no application here to post it to; not recorded.', NULL);
            CONTINUE;
        END IF;
        IF v_ref IS NULL OR v_amt IS NULL THEN
            IF f.kind = 'APPLICATION' AND v_status = 'VERIFIED' THEN
                probs := probs || admissions.pg_mig_problem('FEE_INCOMPLETE', 'error', 'A verified application fee needs its old reference and amount.',
                         'Give both, as the old portal shows them, or mark the fee Paid to hold it for review.');
            ELSIF f.kind <> 'ACCEPTANCE' THEN
                probs := probs || admissions.pg_mig_problem('FEE_INCOMPLETE', 'warning', f.label || ': no reference or amount, so nothing is recorded.', 'Give both to record it.');
            END IF;
            CONTINUE;
        END IF;
        IF upper(btrim(v_ref)) = ANY (v_refs) THEN
            probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_TWICE', 'error', format('%s: reference %s is given for another fee in the same row.', f.label, left(v_ref, 40)),
                     'Each payment has its own reference.');
            CONTINUE;
        END IF;
        v_refs := v_refs || upper(btrim(v_ref));
        -- through the reference's own index (the fence keeps the planner from walking every earlier row of the batch)
        SELECT min(x.row_no) INTO v_dup
          FROM (SELECT x2.row_no, x2.batch_id, x2.legacy_no FROM admissions.pg_migration_row x2 WHERE x2.fee_refs @> ARRAY[upper(btrim(v_ref))] OFFSET 0) x
         WHERE x.batch_id = r.batch_id AND x.row_no < r.row_no AND x.legacy_no IS DISTINCT FROM v_legacy;
        IF v_dup IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_IN_FILE', 'conflict', format('%s: reference %s is also on row %s, another applicant.', f.label, left(v_ref, 40), v_dup),
                     'One payment belongs to one applicant: correct the reference.');
            CONTINUE;
        END IF;
        v_clash := admissions.pg_mig_fee_clash(f.kind, v_ref, v_app, v_student);
        IF v_clash IS NOT NULL THEN
            probs := probs || admissions.pg_mig_problem('FEE_REFERENCE_ELSEWHERE', 'conflict', format('%s: reference %s is %s.', f.label, left(v_ref, 40), v_clash),
                     'A payment is recorded once: the Bursary settles a payment claimed twice through its own reconciliation.');
        ELSIF f.kind = 'APPLICATION' AND v_app IS NOT NULL AND a.fee_confirmed_at IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.application_id = v_app AND x.kind = 'APPLICATION' AND upper(btrim(x.legacy_reference)) = upper(btrim(v_ref))) THEN
            probs := probs || admissions.pg_mig_problem('FEE_ALREADY_PAID_HERE', 'warning',
                     'An application fee is already confirmed on this portal: the old payment is held for the Bursary to review, not posted.', NULL);
        ELSIF f.kind = 'APPLICATION' AND v_status = 'CLAIMED' THEN
            probs := probs || admissions.pg_mig_problem('FEE_UNDER_REVIEW', 'warning',
                     'The application fee is not verified: held for the Bursary or the PG Secretary to verify; the applicant is not asked to pay it again meanwhile.', NULL);
        END IF;
    END LOOP;

    v_verdict := CASE WHEN probs @> '[{"level":"duplicate"}]' THEN 'DUPLICATE_IN_FILE'
                      WHEN probs @> '[{"level":"error"}]' THEN 'ERROR'
                      WHEN probs @> '[{"level":"conflict"}]' THEN 'CONFLICT'
                      WHEN probs @> '[{"level":"review"}]' THEN 'REQUIRES_REVIEW'
                      WHEN probs @> '[{"level":"warning"}]' THEN 'WARNING'
                      ELSE 'READY' END;
    RETURN jsonb_build_object('verdict', v_verdict, 'match', v_match, 'action', v_action, 'applicationId', v_app, 'studentId', v_student,
                              'programme', v_prog, 'specialisationId', v_spec, 'session', v_session, 'target', v_target, 'screening', v_screen,
                              'accepted', v_accepted, 'acceptanceVerified', v_acc_ok, 'surname', v_surname, 'givenNames', v_given,
                              'email', v_email, 'phone', v_phone, 'dob', v_dob, 'legacy', v_legacy, 'problems', probs);
END $function$;

-- ── 5 · the JUPEB old-portal upload (V345's, restated) ───────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION jupeb.import_old_portal_students(p_rows jsonb, p_session text, p_dmy boolean, p_commit boolean, p_file text, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_out jsonb := '[]'::jsonb; v_status text; v_notes text[]; v_app text; v_email text; v_sur text; v_first text; v_mid text;
        v_phone text; v_nin text; v_sex text; v_dob date; v_state text; v_lga text; v_stream text; v_comb uuid; v_comb_code text;
        n_valid int := 0; n_review int := 0; n_invalid int := 0; n_exists int := 0; n_applied int := 0; v_ref text; v_acc uuid; v_id uuid; v_created jsonb := '[]'::jsonb;
        seen_app text[] := '{}'; seen_email text[] := '{}';
BEGIN
    IF p_session IS NULL OR p_session !~ '^[0-9]{4}/[0-9]{4}$' THEN
        RAISE EXCEPTION 'JUPEB_SESSION: choose the session the students are in' USING ERRCODE = '23514';
    END IF;
    IF p_commit THEN
        v_ref := jupeb.batch_ref('OLD_PORTAL_STUDENTS');
        PERFORM set_config('moaum.jupeb_quiet', 'on', true);
    END IF;
    FOR r IN SELECT x FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) x LOOP
        v_notes := '{}'; v_status := 'VALID';
        v_app := nullif(upper(regexp_replace(btrim(coalesce(r->>'appNo', '')), '\s+', '', 'g')), '');
        v_email := nullif(lower(btrim(coalesce(r->>'email', ''))), '');
        v_sur := nullif(initcap(btrim(coalesce(r->>'surname', ''))), '');
        v_first := nullif(initcap(btrim(coalesce(r->>'firstName', ''))), '');
        v_mid := nullif(initcap(btrim(coalesce(r->>'middleName', ''))), '');
        v_sex := CASE upper(left(btrim(coalesce(r->>'sex', '')), 1)) WHEN 'F' THEN 'F' WHEN 'M' THEN 'M' END;
        IF v_sex IS NULL AND btrim(coalesce(r->>'sex', '')) <> '' THEN v_notes := v_notes || ('sex "' || (r->>'sex') || '" not read'); END IF;
        v_phone := jupeb.legacy_phone(r->>'phone');
        IF v_phone IS NULL AND btrim(coalesce(r->>'phone', '')) <> '' THEN v_notes := v_notes || ('phone "' || (r->>'phone') || '" not read'); END IF;
        v_nin := nullif(regexp_replace(coalesce(r->>'nin', ''), '[^0-9]', '', 'g'), '');
        IF v_nin IS NOT NULL AND v_nin !~ '^[0-9]{11}$' THEN v_notes := v_notes || ('NIN "' || (r->>'nin') || '" is not eleven digits'); v_nin := NULL; END IF;
        v_dob := jupeb.legacy_date(r->>'dob', coalesce(p_dmy, true));
        IF v_dob IS NOT NULL AND (v_dob > current_date - interval '10 years' OR v_dob < current_date - interval '70 years') THEN
            v_notes := v_notes || ('date of birth ' || to_char(v_dob, 'DD Mon YYYY') || ' is not likely'); v_dob := NULL;
        ELSIF v_dob IS NULL AND btrim(coalesce(r->>'dob', '')) <> '' THEN
            v_notes := v_notes || ('date of birth "' || (r->>'dob') || '" not read');
        END IF;
        v_state := nullif(initcap(btrim(coalesce(r->>'state', ''))), '');
        v_lga := nullif(initcap(btrim(coalesce(r->>'lga', ''))), '');
        v_stream := CASE upper(regexp_replace(btrim(coalesce(r->>'programme', '')), '[- ]', '_', 'g'))
                        WHEN 'SCIENCE' THEN 'SCIENCE' WHEN 'NON_SCIENCE' THEN 'NON_SCIENCE' WHEN 'ARTS' THEN 'NON_SCIENCE' END;
        v_comb := NULL; v_comb_code := NULL;
        IF nullif(btrim(coalesce(r->>'combination', '')), '') IS NOT NULL THEN
            SELECT c.id, c.code INTO v_comb, v_comb_code FROM jupeb.combination c WHERE upper(c.code) = upper(btrim(r->>'combination'));
            IF v_comb IS NULL THEN v_notes := v_notes || ('combination "' || (r->>'combination') || '" is not on the catalogue'); END IF;
        END IF;

        IF v_app IS NULL THEN v_status := 'INVALID'; v_notes := ARRAY['the App No is missing'];
        ELSIF v_app = ANY (seen_app) THEN v_status := 'INVALID'; v_notes := ARRAY['the App No ' || v_app || ' is twice in the file'];
        ELSIF EXISTS (SELECT 1 FROM jupeb.application x WHERE upper(x.application_no) = v_app OR upper(x.legacy_ref) = v_app) THEN
            v_status := 'EXISTS'; v_notes := ARRAY['already on the portal — skipped'];
        -- V755: an App No a migrated preliminary applicant signs in with: the row refused here, in the preview as at the upload (V745's
        -- trigger would otherwise refuse the whole upload, naming only the first)
        ELSIF admissions.prelim_legacy_number_holder(v_app) IS NOT NULL THEN
            v_status := 'INVALID';
            v_notes := ARRAY['the App No ' || v_app || ' is the old portal number a preliminary applicant brought across ('
                             || admissions.prelim_legacy_number_holder(v_app) || ') signs in with; one number never opens two accounts — ICT settles it'];
        ELSIF v_sur IS NULL OR v_first IS NULL THEN v_status := 'INVALID'; v_notes := ARRAY['the surname and first name are required'];
        ELSIF v_email IS NULL OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
            v_status := 'INVALID'; v_notes := ARRAY['the email "' || coalesce(r->>'email', '') || '" is not valid — correct it in the file'];
        ELSIF v_email = ANY (seen_email) THEN v_status := 'INVALID'; v_notes := ARRAY['the email ' || v_email || ' is twice in the file'];
        ELSIF EXISTS (SELECT 1 FROM jupeb.account x WHERE lower(x.email) = v_email) THEN
            v_status := 'INVALID'; v_notes := ARRAY['the email ' || v_email || ' already has a JUPEB account'];
        ELSIF cardinality(v_notes) > 0 THEN v_status := 'REVIEW';
        END IF;
        IF v_app IS NOT NULL THEN seen_app := seen_app || v_app; END IF;
        IF v_email IS NOT NULL THEN seen_email := seen_email || v_email; END IF;

        IF v_status = 'VALID' THEN n_valid := n_valid + 1; ELSIF v_status = 'REVIEW' THEN n_review := n_review + 1;
        ELSIF v_status = 'EXISTS' THEN n_exists := n_exists + 1; ELSE n_invalid := n_invalid + 1; END IF;

        v_id := NULL;
        IF p_commit AND v_status IN ('VALID', 'REVIEW') THEN
            IF coalesce(r->>'passwordHash', '') !~ '^\$2[aby]?\$12\$' THEN
                RAISE EXCEPTION 'JUPEB_IMPORT_PASSWORD: row % has no temporary password', r->>'row' USING ERRCODE = '23514';
            END IF;
            INSERT INTO jupeb.account (email, password_hash, must_change_password) VALUES (v_email, r->>'passwordHash', true) RETURNING id INTO v_acc;
            INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, middle_name, sex, date_of_birth, nin, email, phone,
                                           nationality, state_of_origin, lga, stream, combination_id, state, fee_confirmed_at, submitted_at, activated_at,
                                           legacy_source, legacy_ref, legacy_batch)
            VALUES (v_acc, p_session, v_app, upper(v_sur), v_first, v_mid, v_sex, v_dob, v_nin, v_email, v_phone,
                    CASE WHEN v_state IS NOT NULL THEN 'Nigerian' END, v_state, v_lga, v_stream, v_comb, 'STUDENT', now(), now(), now(),
                    'OLD_PORTAL', v_app, v_ref)
            RETURNING id INTO v_id;
            PERFORM jupeb.app_event(v_id, 'IMPORTED', 'Registered on the old portal as ' || v_app || '; uploaded in ' || v_ref);
            n_applied := n_applied + 1;
            v_created := v_created || jsonb_build_object('row', r->'row', 'applicationId', v_id, 'applicationNo', v_app, 'email', v_email,
                                                         'name', upper(v_sur) || ', ' || v_first || coalesce(' ' || v_mid, ''));
        END IF;
        v_out := v_out || jsonb_build_object('row', r->'row', 'status', v_status, 'message', array_to_string(v_notes, '; '),
            'appNo', v_app, 'name', coalesce(upper(v_sur), '') || ', ' || coalesce(v_first, '') || coalesce(' ' || v_mid, ''), 'email', v_email,
            'sex', v_sex, 'phone', v_phone, 'nin', v_nin, 'dob', v_dob, 'state', v_state, 'lga', v_lga, 'programme', v_stream, 'combination', v_comb_code,
            'applicationId', v_id);
    END LOOP;
    IF p_commit THEN
        PERFORM set_config('moaum.jupeb_quiet', 'off', true);
        INSERT INTO jupeb.import_batch (ref, kind, file_name, rows, applied, result, imported_by, imported_office)
        VALUES (v_ref, 'OLD_PORTAL_STUDENTS', p_file, jsonb_array_length(coalesce(p_rows, '[]'::jsonb)), n_applied,
                jsonb_build_object('valid', n_valid, 'review', n_review, 'invalid', n_invalid, 'exists', n_exists, 'session', p_session),
                p_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN jsonb_build_object('rows', v_out, 'valid', n_valid, 'review', n_review, 'invalid', n_invalid, 'exists', n_exists,
                              'committed', p_commit, 'ref', v_ref, 'applied', n_applied, 'created', v_created);
END $function$;

COMMENT ON FUNCTION admissions.prelim_migration_assess(uuid) IS
  'V737, V745, V755: the check of one preliminary migration row, writing nothing — the verdict, the match, the action and every problem with what to correct. V755: every JAMB test reads admissions.prelim_mig_jamb_key; an old number shaped like this portal''s own APP, PG or JUPEB numbers is refused.';
COMMENT ON FUNCTION admissions.pg_migration_assess(uuid) IS
  'V675, V755: the check of one migration row, writing nothing: the verdict (READY, WARNING, DUPLICATE_IN_FILE, ERROR, CONFLICT, REQUIRES_REVIEW), the match (a new applicant, an application on this portal, a student on the register), the action (CREATE, UPDATE, RECONCILE, LINK_STUDENT), the programme and the state this portal would hold, and every problem with what to correct. V755: an old number a migrated preliminary applicant signs in with is a conflict (LEGACY_NO_IS_PORTAL_NUMBER).';
COMMENT ON FUNCTION jupeb.import_old_portal_students(jsonb, text, boolean, boolean, text, uuid) IS
  'V345, V755: the old portal''s JUPEB students — previewed (p_commit false) or uploaded with their logins. V755: an App No a migrated preliminary applicant signs in with is INVALID, in the preview as at the upload, and the rest of the file imports.';

-- ── 6 · the JUPEB trigger: rows brought from the old portal only ───────────────────────────────────────────────────────────────
DROP TRIGGER trg_application_not_prelim ON jupeb.application;
CREATE TRIGGER trg_application_not_prelim BEFORE INSERT OR UPDATE OF application_no, legacy_ref ON jupeb.application
    FOR EACH ROW WHEN (NEW.legacy_source IS NOT NULL) EXECUTE FUNCTION jupeb.trg_application_not_prelim();
COMMENT ON TRIGGER trg_application_not_prelim ON jupeb.application IS
  'V745, V755: a JUPEB student brought from the old portal never carries, as App No or old reference, an old number a migrated preliminary applicant signs in with. Only such rows (legacy_source set): an application made here draws its number from the series, which V755 keeps out of the preliminary old numbers at their check.';

COMMIT;

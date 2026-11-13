-- ═══════════════════════════════════════════════════════════
-- V745 — the independent review of V737 applied
--
--   V737 (old-portal preliminary applicants migrated, their fees held for the Bursary, the programme corrected by ICT) is on main and
--   may already run, so it is not edited: what its independent review found is put right here, each V737 function restated from its
--   current text where it changes. And the University's decisions of 12 November 2026 on the review: the Head of ICT Support has no
--   implicit right to upload or to correct a programme — the head acts only through an agent posting carrying the capability, as any
--   agent; super keeps its access; a Database Operator uploads only with a grant over the whole University; the programme moves stay
--   the fixed pair (Technology ↔ Science), with no setting built.
--
--   1 · The dry run compares the rows of one file with each other, as the import will (findings 1, 16). Each row stages its person
--       keys (surname and phone; surname, first name and birth date; the JAMB number) and its gateway reference beside the old
--       number, email, payment reference and O'Level keys: an earlier row of the file that is perhaps the same person holds the row for
--       review (POSSIBLE_SAME_APPLICANT, confirmable as before), and a payment or gateway reference another row already gave is a
--       duplicate (FEE_REFERENCE_IN_FILE) — so the preview and the confirmation dialog say what the import will do. A JAMB number an
--       earlier migration brought (prelim_legacy_application.legacy_jamb_reg_no) holds a new applicant for review too. Only a JAMB
--       number is a key: "N/A", "NIL" or "None" written by applicants who had none names nobody. A row the import skipped for review
--       can be confirmed as a new applicant afterwards in its own batch, and is imported there and then.
--   2 · The check costs less a row (finding 2): an O'Level cell's subjects are matched against the form's list keyed once a
--       transaction (prelim_olevel_subject_keys, kept in moaum.prelim_olevel_subject_map), not keyed afresh for every subject (four
--       fifths of a row's check). The import can be asked for no batch summary (prelim_migration_import(…, p_summary => false)), so
--       the API can commit a few rows at a time and hold the APPLICATION number series for a moment, not for a chunk; each row's import
--       is prelim_migration_import_row. A results cell written one subject a line is staged with "; " between the lines, and a subject
--       that still holds a grade or a colon is SUBJECT_UNKNOWN, never a silent single subject (finding 8, the server's half).
--   3 · An email match is checked on the first name and the sex (finding 4): either differing is a conflict, never an import onto that
--       application (a parent's or a twin's email).
--   4 · Without "fill in missing details" an applicant already here keeps their state (finding 6): a RECONCILE row only keeps the old
--       number with the application — no outcome published, no state moved forward, no fee held — and says what it left alone, in the
--       check (OLD_NUMBER_ONLY) and in the result.
--   5 · Who acts (findings 5, 17): prelim_mig_writer and prelim_route_officer no longer pass the Head of ICT Support; the head, like an
--       agent, passes with a University-wide posting carrying the capability; a Database Operator uploads only on a grant over the
--       whole University (iam.dbops_scope 'institution').
--   6 · The applicant's status says the old-portal fee is being verified while it is held (finding 9: admissions.prelim_status).
--   7 · An old number that is a postgraduate applicant's old number (V709) or a JUPEB application's number or old reference (V718) is
--       held back as a sign-in already in use (finding 10); the other way round, a postgraduate or JUPEB import may not bring in an old
--       number a migrated preliminary applicant signs in with (triggers on admissions.pg_legacy_application and jupeb.application).
--   8 · The dashboard's "new" leaves out an application a migration created with no Application Date (finding 11): the day an
--       application was made is admissions.prelim_applied_on — for one a migration created, the old portal's date its old-number record
--       holds (NULL when no file gave one, the date a later "fill in missing details" upload gave when one did) — which prelim_stats
--       counts and the desk's list reads.
--   9 · A programme change adds its note to the Office's pending correction instead of replacing it, and an application the Office sent
--       back stays with the applicant (finding 12).
--  10 · A "Paid" row with no amount is imported with its fee held and flagged for the Bursary to confirm the amount (finding 14); the
--       Bursary verifies it at the amount it gives, or else at the programme's stated application fee.
--  11 · The reconciliation's duplicate references are counted from every batch whose old number is still not migrated, whatever the
--       batch's state, and are among those needing financial review (finding 15).
--  12 · The ICT applicant password desk finds a migrated preliminary applicant by the old portal's application number, as it signs in
--       and as Forgot password finds it (admissions.applicant_password_find, restated from V706 with the number as a last column).
--  13 · A row whose target is one of the other preliminary programme's own is that programme's applicant: held back as a conflict
--       (PROGRAMME_MISMATCH), as a Programme cell naming the other programme is, never imported here without a target (finding 7, the
--       server's half: an old export with no Programme column, or a file uploaded in the other section by a direct call).
--
--   Restated from V737 (a later migration restating any of them starts from V745's text): admissions.prelim_mig_writer,
--   prelim_route_officer, prelim_olevel_subjects, prelim_mig_results, prelim_migration_assess, prelim_mig_hold, prelim_migration_apply,
--   prelim_migration_stage, prelim_migration_row_new, prelim_migration_summary, prelim_legacy_fee_figures, prelim_change_route_check,
--   prelim_change_route, prelim_stats; admissions.prelim_status from V701; admissions.applicant_password_find from V706 (dropped and
--   created: a column more, last). Dropped and created with a defaulted parameter more:
--   prelim_migration_import (p_summary) and prelim_legacy_fee_decide (p_amount) — their callers' arguments unchanged. New:
--   prelim_mig_person_keys, prelim_olevel_subject_keys, prelim_migration_import_row, prelim_applied_on, prelim_legacy_number_holder;
--   triggers trg_pg_legacy_not_prelim (admissions.pg_legacy_application) and trg_application_not_prelim (jupeb.application). Columns: prelim_migration_row
--   person_keys and gateway_ref; prelim_legacy_fee.amount nullable (never for a verified fee).
-- ═══════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V745: the independent review of V737 (preliminary applicants migrated from the old portal) applied', true);

-- ── 1 · the rows of one file compared with each other ───────────────────────────────────────────────────────────────────────
ALTER TABLE admissions.prelim_migration_row
    ADD COLUMN person_keys text[] NOT NULL DEFAULT '{}',
    ADD COLUMN gateway_ref text NULL;
COMMENT ON COLUMN admissions.prelim_migration_row.person_keys IS
  'V745: who the row is, as keys an earlier row of the same file is compared on (admissions.prelim_mig_person_keys): SP|surname|phone, SFD|surname|first name|birth date, J|JAMB number.';
COMMENT ON COLUMN admissions.prelim_migration_row.gateway_ref IS
  'V745: the payment service''s own reference the row gives (upper case), compared with the other rows'' payment and gateway references.';

/* who a row is, as keys: the surname and phone; the surname, first name and birth date; the JAMB number — read as
   prelim_migration_assess reads them (a "Full Name" column when the template's name columns are blank; the placeholder phone is no key,
   nor is a JAMB cell that is not a JAMB number: "N/A", "NIL" or "None" written by applicants who had none would otherwise make every
   such applicant of the file, and of every later file, one person) */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_person_keys(d jsonb) RETURNS text[] LANGUAGE plpgsql STABLE AS $fn$
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
    IF v_jamb ~ '^[0-9]{6,}[A-Z]{0,3}$' THEN k := k || ('J|' || v_jamb); END IF;
    RETURN k;
END $fn$;
COMMENT ON FUNCTION admissions.prelim_mig_person_keys(jsonb) IS
  'V745: the keys a preliminary migration row is compared on with the earlier rows of its file — SP|surname|phone, SFD|surname|first name|birth date, J|JAMB number — so the dry run sees what the import will: a second row of the same person held for review.';

-- the rows already staged (an open batch is checked again with them)
UPDATE admissions.prelim_migration_row r
   SET person_keys = admissions.prelim_mig_person_keys(r.data),
       gateway_ref = nullif(upper(btrim(coalesce(admissions.pg_mig_t(r.data, 'gatewayReference'), ''))), '');
CREATE INDEX ix_prelimmig_row_person ON admissions.prelim_migration_row USING gin (person_keys);
CREATE INDEX ix_prelimmig_row_gateway ON admissions.prelim_migration_row (batch_id, gateway_ref) WHERE gateway_ref IS NOT NULL;
-- a JAMB number an earlier migration brought, looked up by a new row
CREATE INDEX ix_prelim_legacy_application_jamb ON admissions.prelim_legacy_application (legacy_jamb_reg_no) WHERE legacy_jamb_reg_no IS NOT NULL;

-- ── 2 · a fee paid on the old portal with no amount: held, the amount for the Bursary to confirm ─────────────────────────────
ALTER TABLE admissions.prelim_legacy_fee ALTER COLUMN amount DROP NOT NULL;
ALTER TABLE admissions.prelim_legacy_fee ADD CONSTRAINT ck_prelim_legacy_fee_amount_verified CHECK (state <> 'VERIFIED' OR amount IS NOT NULL);
COMMENT ON COLUMN admissions.prelim_legacy_fee.amount IS
  'V737, V745: the amount the file stated; NULL when it gave none (the fee held all the same, the amount for the Bursary to confirm). A verified fee always carries the amount posted.';

-- ── 3 · who uploads, who corrects a programme (the University's decisions of 12 November 2026) ─────────────────────────────
/* who uploads old-portal preliminary applicants: the Director of ICT, the Academic Office, super, a Database Operator granted over the
   whole University (iam.dbops_scope) — or an ICT Support agent, or the Head of ICT Support, on a University-wide posting carrying
   MIGRATE_PRELIM_APPLICANTS (the head has no implicit right: V745); a person, never a job */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_writer() RETURNS void LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PRELIMMIG_ACTOR: a migration is made by a person' USING ERRCODE = '23514'; END IF;
    IF v_office IN ('ict', 'academic', 'super') THEN RETURN; END IF;
    -- V745: a Database Operator only on a grant over the whole University (a faculty's or a department's operator does not upload)
    IF v_office = 'dbops' AND coalesce((SELECT s.kind FROM iam.dbops_scope(v_actor) s), '') = 'institution' THEN RETURN; END IF;
    IF v_office IN ('ictagent', 'helpdeskhead') AND coalesce((SELECT s.global FROM helpdesk.agent_scope_for(v_actor, 'MIGRATE_PRELIM_APPLICANTS') s), false) THEN RETURN; END IF;
    RAISE EXCEPTION 'PRELIMMIG_OFFICE: the Director of ICT, the Academic Office, a Database Operator granted over the whole University or an ICT Support agent the Director has authorised uploads old-portal preliminary applicants, not %',
        coalesce(nullif(v_office, ''), 'this office') USING ERRCODE = '42501';
END $fn$;

/* who corrects a preliminary applicant's programme: the Director of ICT, super, or an ICT Support agent — the Head of ICT Support too —
   on a University-wide posting carrying CHANGE_PRELIM_PROGRAMME (the head has no implicit right: V745) */
CREATE OR REPLACE FUNCTION admissions.prelim_route_officer() RETURNS void LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PRELIM_CHANGE_ACTOR: a programme is corrected by a person' USING ERRCODE = '23514'; END IF;
    IF v_office IN ('ict', 'super') THEN RETURN; END IF;
    IF v_office IN ('ictagent', 'helpdeskhead') AND coalesce((SELECT s.global FROM helpdesk.agent_scope_for(v_actor, 'CHANGE_PRELIM_PROGRAMME') s), false) THEN RETURN; END IF;
    RAISE EXCEPTION 'PRELIM_CHANGE_OFFICE: the Director of ICT or an ICT Support agent the Director has authorised changes a preliminary applicant''s programme, not %',
        coalesce(nullif(v_office, ''), 'this office') USING ERRCODE = '42501';
END $fn$;

-- ── 4 · an O'Level cell read: the form's subjects keyed once ─────────────────────────────────────────────────────────────
/* the O'Level subjects a preliminary migration file may name, each with its key (admissions.subject_key) — V737's
   prelim_olevel_subjects, each name keyed once (it was keyed two or three times over, for every subject of every cell) */
CREATE OR REPLACE FUNCTION admissions.prelim_olevel_subject_keys()
RETURNS TABLE (name text, subject_key text, ord int) LANGUAGE sql STABLE AS $$
    WITH form AS (
        SELECT u.n AS name, u.o::int AS ord
          FROM unnest(ARRAY['English Language', 'Mathematics', 'Biology', 'Chemistry', 'Physics', 'Agricultural Science', 'Further Mathematics', 'Economics', 'Geography',
                            'Technical Drawing', 'Computer Studies', 'Data Processing', 'Government', 'Literature in English', 'Christian Religious Studies', 'Islamic Religious Studies',
                            'Civic Education', 'Commerce', 'Financial Accounting', 'Health Education', 'Physical Education', 'Food and Nutrition', 'Fine Art', 'History', 'French', 'Tiv',
                            'Hausa', 'Yoruba', 'Igbo', 'Clothing and Textiles', 'Home Management', 'Marketing', 'Office Practice', 'Book Keeping', 'Store Management', 'Insurance', 'ICT',
                            'Basic Electricity', 'Basic Electronics', 'Auto Mechanics', 'Building Construction', 'Metalwork', 'Woodwork',
                            'Electrical Installation and Maintenance Work']) WITH ORDINALITY u(n, o)),
    rules AS (
        SELECT btrim(s) AS name, 1000 AS ord FROM admissions.prelim_programme p, unnest(p.core_subjects || p.required_subjects || p.completion_subjects) s
        UNION ALL
        SELECT btrim(s), 2000 FROM admissions.prelim_target t, unnest(coalesce(t.core_subjects, '{}'::text[])) s),
    alls AS MATERIALIZED (SELECT a.name, a.ord, admissions.subject_key(a.name) AS k FROM (SELECT * FROM form UNION ALL SELECT * FROM rules) a),
    one AS (SELECT DISTINCT ON (a.k) a.name, a.k, a.ord FROM alls a WHERE a.k IS NOT NULL ORDER BY a.k, a.ord, a.name)
    SELECT one.name, one.k, one.ord FROM one ORDER BY one.ord, one.name
$$;
COMMENT ON FUNCTION admissions.prelim_olevel_subject_keys() IS
  'V745: the O''Level subjects a preliminary migration file may name (V737''s list: the application form''s own and every subject a preliminary rule names), one name a subject, with its admissions.subject_key — each name keyed once.';

CREATE OR REPLACE FUNCTION admissions.prelim_olevel_subjects()
RETURNS TABLE (name text) LANGUAGE sql STABLE AS $$
    SELECT k.name FROM admissions.prelim_olevel_subject_keys() k ORDER BY k.ord, k.name
$$;
COMMENT ON FUNCTION admissions.prelim_olevel_subjects() IS
  'V737, V745: the O''Level subjects a preliminary migration file may name — the application form''s own list (frontend lib/preliminary.ts SUBJECTS) and every subject a preliminary rule names — one name a subject (admissions.subject_key). The template''s Subjects sheet and the check read it; a subject not on it is OLEVEL_SUBJECT_UNKNOWN. V745: read from prelim_olevel_subject_keys.';

/* "Mathematics:B3; English Language:C4" read into its subjects and grades, each with what is wrong with it (NULL when nothing):
   SUBJECT_UNKNOWN, NO_GRADE, GRADE_INVALID, AWAITING, SUBJECT_TWICE. The subject is given back in the form's own name.
   V745: the form's list keyed once a transaction — kept in moaum.prelim_olevel_subject_map for the rest of it (a check of a thousand
   rows reads it once; it was keyed again for every subject of every cell, four fifths of a row's check) — and a "subject" that still
   holds a colon or a grade ("Maths:B3 English": several subjects on one line without a separator) is SUBJECT_UNKNOWN, never read as
   the one subject its first word names. */
CREATE OR REPLACE FUNCTION admissions.prelim_mig_results(p text)
RETURNS TABLE (ord int, given text, subject text, grade text, problem text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_part text; i int := 0; m text[]; v_s text; v_g text; v_canon text; v_seen text[] := '{}'; v_map jsonb;
BEGIN
    FOR v_part IN SELECT btrim(x) FROM regexp_split_to_table(coalesce(p, ''), '[;,|\n\r]+') x WHERE btrim(x) <> '' LOOP
        IF v_map IS NULL THEN
            v_map := nullif(current_setting('moaum.prelim_olevel_subject_map', true), '')::jsonb;
            IF v_map IS NULL THEN
                SELECT coalesce(jsonb_object_agg(k.subject_key, k.name), '{}'::jsonb) INTO v_map FROM admissions.prelim_olevel_subject_keys() k;
                PERFORM set_config('moaum.prelim_olevel_subject_map', v_map::text, true);
            END IF;
        END IF;
        i := i + 1;
        m := regexp_match(v_part, '^(.*?)\s*[:=]\s*([^:=]*)$');
        IF m IS NULL THEN
            m := regexp_match(v_part, '^(.*?)[[:space:]-]+([A-Fa-f][[:space:]]?[1-9]|[Aa][Rr])$');
        END IF;
        v_s := btrim(coalesce(m[1], v_part));
        v_g := upper(regexp_replace(btrim(coalesce(m[2], '')), '\s', '', 'g'));
        v_canon := CASE WHEN v_s ~ '[:=]' OR v_s ~* '(^|[^[:alnum:]])[A-F][1-9]([^[:alnum:]]|$)' THEN NULL
                        ELSE v_map ->> admissions.subject_key(v_s) END;
        ord := i; given := left(v_s, 60); subject := v_canon; grade := nullif(v_g, '');
        problem := CASE WHEN v_s = '' OR length(v_s) > 60 OR v_canon IS NULL THEN 'SUBJECT_UNKNOWN'
                        WHEN v_g = '' THEN 'NO_GRADE'
                        WHEN v_g IN ('AR', 'AWAITING', 'AWAITINGRESULT', 'PENDING', 'NR', '*', 'ABS') THEN 'AWAITING'
                        WHEN v_g NOT IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6', 'D7', 'E8', 'F9') THEN 'GRADE_INVALID'
                        WHEN admissions.subject_key(v_canon) = ANY (v_seen) THEN 'SUBJECT_TWICE' END;
        IF v_canon IS NOT NULL THEN v_seen := v_seen || admissions.subject_key(v_canon); END IF;
        RETURN NEXT;
    END LOOP;
END $fn$;

-- ── 5 · the check of one row (V737's, restated) ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.prelim_migration_assess(p_row uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
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
    IF v_legacy ~ '^APP/[0-9]{2}/[0-9]{6}$' THEN
        probs := probs || admissions.pg_mig_problem('LEGACY_NO_IS_PORTAL_NUMBER', 'error', format('"%s" is shaped like this portal''s own application numbers, not the old portal''s.', v_legacy),
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
    IF v_jamb IS NOT NULL AND v_jamb !~ '^[0-9]{6,}[A-Z]{0,3}$' THEN
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
        IF v_jamb ~ '^[0-9]{6,}[A-Z]{0,3}$' THEN
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
    IF v_jamb IS NOT NULL THEN
        SELECT string_agg(x.w, ', ') INTO v_nos FROM (
            SELECT cc.session || ' ' || cc.surname AS w FROM admissions.candidate cc WHERE cc.jamb_key = v_jamb AND (v_app IS NULL OR cc.id <> a.candidate_id)
            UNION ALL
            -- V745: on another migrated application (a new applicant's is held for review above)
            SELECT ap.application_no FROM admissions.prelim_legacy_application l JOIN admissions.application ap ON ap.id = l.application_id
             WHERE v_app IS NOT NULL AND v_jamb ~ '^[0-9]{6,}[A-Z]{0,3}$' AND l.legacy_jamb_reg_no = v_jamb AND l.application_id <> v_app
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
END $fn$;
COMMENT ON FUNCTION admissions.prelim_migration_assess(uuid) IS
  'V737, V745: the check of one preliminary migration row, writing nothing: the verdict (READY, WARNING, DUPLICATE_IN_FILE, ERROR, CONFLICT, REQUIRES_REVIEW — the most serious problem decides), the match (a new applicant, or one on this portal), the action (CREATE, UPDATE, RECONCILE, NONE), every problem {code, level, message, fix}, and the values the import would write. V745: an earlier row of the same file that is perhaps the same person (surname and phone; surname, first name and birth date; the JAMB number), or a JAMB number an earlier migration brought, holds a new applicant for review; another row''s payment or gateway reference is a duplicate; an email match must agree on the first name and the sex; an old number in use as a postgraduate or JUPEB number is held back; a RECONCILE without "fill in missing details" keeps only the old number (numberOnly, leftAlone); a Paid row with no amount is held with the amount to confirm.';

-- ── 6 · the import ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- a fee the old portal says was paid, held for the Bursary (once; never where the fee is already paid here or one is held or decided);
-- V745: with no amount too (the Bursary confirms it)
CREATE OR REPLACE FUNCTION admissions.prelim_mig_hold(p_app uuid, p_batch uuid, p_row uuid, x jsonb, p_stated text) RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE v_state text;
BEGIN
    IF x->>'payment' IS DISTINCT FROM 'PAID' THEN RETURN false; END IF;
    IF (SELECT a.fee_confirmed_at FROM admissions.application a WHERE a.id = p_app) IS NOT NULL THEN RETURN false; END IF;
    -- a fee the Bursary rejected is not held again by the same claim: only a row bringing another, non-blank reference is held anew
    IF EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f
                WHERE f.application_id = p_app
                  AND (f.state <> 'REJECTED' OR nullif(btrim(x->>'reference'), '') IS NULL
                       OR upper(btrim(f.legacy_reference)) IS NOT DISTINCT FROM upper(btrim(x->>'reference')))) THEN
        RETURN false;
    END IF;
    INSERT INTO admissions.prelim_legacy_fee (application_id, batch_id, row_id, legacy_reference, gateway_reference, amount, paid_on, stated_status, state)
    VALUES (p_app, p_batch, p_row, left(btrim(x->>'reference'), 80), left(btrim(x->>'gatewayReference'), 120), (x->>'amount')::numeric,
            (x->>'paidOn')::date, left(p_stated, 60), 'REQUIRES_REVIEW');
    -- a reference this portal drew and not yet paid is closed: the applicant is not asked to pay while the old payment is checked
    UPDATE admissions.fee_reference SET expires_at = least(expires_at, now())
     WHERE application_id = p_app AND kind = 'APPLICATION' AND confirmed_at IS NULL AND expires_at > now();
    SELECT r.state INTO v_state FROM admissions.prelim_review r WHERE r.application_id = p_app;
    PERFORM admissions.prelim_log(p_app, 'OLD_FEE_HELD', v_state, v_state, 'The application fee paid on the old portal is held for the Bursary to verify'
                                  || CASE WHEN (x->>'amount') IS NULL THEN ' (no amount was given: the Bursary confirms it)' ELSE '' END,
                                  jsonb_strip_nulls(jsonb_build_object('reference', x->>'reference', 'gatewayReference', x->>'gatewayReference', 'amount', (x->>'amount')::numeric, 'paidOn', x->>'paidOn',
                                                                       'amountToConfirm', CASE WHEN (x->>'amount') IS NULL THEN true END)));
    RETURN true;
END $fn$;

-- one row imported: created, updated or reconciled — from a fresh check, so nothing changed since is missed
CREATE OR REPLACE FUNCTION admissions.prelim_migration_apply(p_row uuid) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
    r admissions.prelim_migration_row; b admissions.prelim_migration_batch; p admissions.prelim_programme; d jsonb; x jsonb; fee record;
    v_app uuid; v_cand uuid; v_acc uuid; v_no text; v_email text; v_result text; v_changed boolean := false; v_n int; v_at timestamptz;
    v_state text; v_adm text; v_lg_new boolean := false; v_note text; v_held boolean := false;
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
    v_number_only boolean; v_left text;
BEGIN
    SELECT * INTO r FROM admissions.prelim_migration_row WHERE id = p_row;
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = r.batch_id;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = b.route;
    d := r.data;
    x := admissions.prelim_migration_assess(p_row);
    IF x->>'verdict' NOT IN ('READY', 'WARNING') THEN
        RETURN jsonb_build_object('result', 'SKIPPED', 'assessment', x,
               'note', replace(lower(x->>'verdict'), '_', ' ') || ': ' || coalesce((SELECT e->>'message' FROM jsonb_array_elements(x->'problems') e WHERE e->>'level' <> 'warning' LIMIT 1), ''));
    END IF;
    IF x->>'action' = 'NONE' THEN
        RETURN jsonb_build_object('result', 'UNCHANGED', 'assessment', x, 'applicationId', x->>'applicationId',
               'note', (SELECT 'application ' || ap.application_no || ' is already here; this upload does not fill in details' FROM admissions.application ap WHERE ap.id = (x->>'applicationId')::uuid));
    END IF;
    v_at := admissions.pg_mig_at((x->>'appliedOn')::date);
    v_state := x->>'state'; v_adm := x->>'admission';
    v_note := format('Decided on the old portal (old application number %s); published here when it was brought across, %s.', x->>'legacy', b.reference);
    -- V745: an application made here, found by its email, while the upload does not fill in missing details: the old number only
    v_number_only := x->>'action' = 'RECONCILE' AND NOT b.allow_update;

    IF x->>'action' = 'CREATE' THEN
        v_cand := gen_random_uuid(); v_acc := gen_random_uuid(); v_app := gen_random_uuid();
        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, sex)
        VALUES (v_cand, b.session, NULL, left(x->>'surname', 60), left(btrim((x->>'firstName') || coalesce(' ' || (x->>'otherNames'), '')), 121), p.name,
                CASE p.programme_type WHEN 'PROFICIENCY_CERTIFICATE' THEN 'PROFICIENCY' ELSE 'PRELIMINARY' END, 0, 'PROPOSED', x->>'sex');
        -- the sign-in: the old email, or a placeholder the applicant never sees (the application number signs in)
        v_email := x->>'email';
        IF v_email IS NULL THEN
            v_email := 'prelim-' || btrim(lower(regexp_replace(x->>'legacy', '[^A-Za-z0-9]+', '-', 'g')), '-') || '@migrate.moau.local';
            IF EXISTS (SELECT 1 FROM admissions.applicant_account z WHERE lower(z.email) = v_email) THEN
                v_email := replace(v_email, '@', '-' || left(md5(v_app::text), 6) || '@');
            END IF;
        END IF;
        -- on a number at the first sign-in (this portal's or the old portal's), then a password of their own, before anything else (as V709)
        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash, must_change_password)
        VALUES (v_acc, b.session, v_cand, NULL, v_email, x->>'phone', 'SET_ON_FIRST_LOGIN', true);
        -- this portal's own number, from its own series: never the old one
        v_no := 'APP/' || substr(b.session, 3, 2) || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', b.session)::text, 6, '0');
        INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, created_at) VALUES (v_app, v_acc, v_cand, b.session, v_no, v_at);
        INSERT INTO admissions.prelim_review (application_id, route, state, submitted_at, review_started_at, withdrawn_at,
                                              target_id, target_programme, specialisation_id, target_set_at, created_at)
        VALUES (v_app, b.route, coalesce(v_state, 'DRAFT'),
                CASE WHEN v_state IN ('SUBMITTED', 'UNDER_REVIEW') THEN v_at END, CASE WHEN v_state = 'UNDER_REVIEW' THEN v_at END,
                CASE WHEN v_state = 'WITHDRAWN' THEN v_at END,
                (x->>'targetId')::uuid, (SELECT t.programme_code FROM admissions.prelim_target t WHERE t.id = (x->>'targetId')::uuid),
                (x->>'specialisationId')::uuid, CASE WHEN (x->>'targetId') IS NOT NULL THEN v_at END, v_at);
        INSERT INTO admissions.screening_answer (application_id, field, value)
        SELECT v_app, e.key, e.value FROM jsonb_each_text(coalesce(x->'answers', '{}'::jsonb)) e;
        UPDATE admissions.application ap
           SET next_of_kin = nullif(btrim(concat_ws(', ', (x->'answers'->>'kin_name') || coalesce(' (' || (x->'answers'->>'kin_relationship') || ')', ''),
                                                    x->'answers'->>'kin_mobile')), '')
         WHERE ap.id = v_app;
        PERFORM admissions.prelim_mig_olevel(v_app, x->'sittings');
        -- an application fee stated as nothing is nothing to pay (as prelim_register)
        SELECT * INTO fee FROM admissions.route_fee_rule(b.session, b.route);
        IF fee.stated IS NOT NULL AND coalesce(fee.application_fee, -1) + coalesce(fee.portal_charge, 0) = 0 THEN
            UPDATE admissions.application SET fee_confirmed_at = now() WHERE id = v_app;
        END IF;
        v_result := 'CREATED'; v_changed := true;
    ELSE
        v_app := (x->>'applicationId')::uuid;
        PERFORM 1 FROM admissions.application WHERE id = v_app FOR UPDATE;
        IF x->>'action' = 'UPDATE' OR b.allow_update THEN
            v_changed := admissions.prelim_mig_fill(v_app, x) OR v_changed;
        END IF;
        v_result := CASE x->>'action' WHEN 'RECONCILE' THEN 'RECONCILED' ELSE 'UPDATED' END;
    END IF;

    -- the old number and what the old portal said, beside the application (its empty fields filled once)
    INSERT INTO admissions.prelim_legacy_application (application_id, legacy_application_no, legacy_jamb_reg_no, legacy_exam_number, legacy_programme, legacy_target,
                                                      legacy_status, legacy_admission, applied_on, route_at_import, batch_id, row_id, migrated_by, migrated_office)
    VALUES (v_app, x->>'legacy', left(x->>'jamb', 40), left(admissions.pg_mig_t(d, 'examinationNumber'), 60), left(admissions.pg_mig_t(d, 'programme'), 200),
            left(nullif(concat_ws(' / ', admissions.pg_mig_t(d, 'target'), admissions.pg_mig_t(d, 'specialisation')), ''), 200),
            left(admissions.pg_mig_t(d, 'applicationStatus'), 60), left(admissions.pg_mig_t(d, 'admissionStatus'), 60), (x->>'appliedOn')::date,
            b.route, b.id, r.id, v_actor, v_office)
    ON CONFLICT (application_id) DO UPDATE SET
        legacy_jamb_reg_no = coalesce(admissions.prelim_legacy_application.legacy_jamb_reg_no, EXCLUDED.legacy_jamb_reg_no),
        legacy_exam_number = coalesce(admissions.prelim_legacy_application.legacy_exam_number, EXCLUDED.legacy_exam_number),
        legacy_programme = coalesce(admissions.prelim_legacy_application.legacy_programme, EXCLUDED.legacy_programme),
        legacy_target = coalesce(admissions.prelim_legacy_application.legacy_target, EXCLUDED.legacy_target),
        legacy_status = coalesce(admissions.prelim_legacy_application.legacy_status, EXCLUDED.legacy_status),
        legacy_admission = coalesce(admissions.prelim_legacy_application.legacy_admission, EXCLUDED.legacy_admission),
        applied_on = coalesce(admissions.prelim_legacy_application.applied_on, EXCLUDED.applied_on)
    WHERE b.allow_update
      AND (admissions.prelim_legacy_application.legacy_jamb_reg_no, admissions.prelim_legacy_application.legacy_exam_number, admissions.prelim_legacy_application.legacy_programme,
           admissions.prelim_legacy_application.legacy_target, admissions.prelim_legacy_application.legacy_status, admissions.prelim_legacy_application.legacy_admission,
           admissions.prelim_legacy_application.applied_on)
          IS DISTINCT FROM
          (coalesce(admissions.prelim_legacy_application.legacy_jamb_reg_no, EXCLUDED.legacy_jamb_reg_no), coalesce(admissions.prelim_legacy_application.legacy_exam_number, EXCLUDED.legacy_exam_number),
           coalesce(admissions.prelim_legacy_application.legacy_programme, EXCLUDED.legacy_programme), coalesce(admissions.prelim_legacy_application.legacy_target, EXCLUDED.legacy_target),
           coalesce(admissions.prelim_legacy_application.legacy_status, EXCLUDED.legacy_status), coalesce(admissions.prelim_legacy_application.legacy_admission, EXCLUDED.legacy_admission),
           coalesce(admissions.prelim_legacy_application.applied_on, EXCLUDED.applied_on))
    RETURNING (xmax = 0) INTO v_lg_new;
    IF FOUND THEN v_changed := true; END IF;

    IF v_number_only THEN
        -- V745: nothing else of the old portal's is applied to an application made here; the result says what was left alone
        v_left := (SELECT string_agg(e, ', ') FROM jsonb_array_elements_text(coalesce(x->'leftAlone', '[]'::jsonb)) e);
    ELSE
        -- the outcome the old portal published, here only where nothing is decided here; else the state it reached, forward only
        IF v_adm IN ('ADMITTED', 'ACCEPTED', 'NOT_ADMITTED') THEN
            v_changed := admissions.prelim_mig_publish(v_app, v_adm,
                             CASE WHEN v_adm = 'NOT_ADMITTED' THEN replace(v_note, 'Decided on the old portal', 'Not admitted on the old portal') ELSE v_note END) OR v_changed;
        ELSIF x->>'action' <> 'CREATE' THEN
            v_changed := admissions.prelim_mig_advance(v_app, v_state, v_at) OR v_changed;
        END IF;

        -- the fee the old portal says was paid: held for the Bursary, never posted here
        v_held := admissions.prelim_mig_hold(v_app, b.id, r.id, x, admissions.pg_mig_t(d, 'paymentStatus'));
        v_changed := v_changed OR v_held;
    END IF;
    IF v_changed THEN PERFORM admissions.prelim_evaluate(v_app); END IF;

    IF x->>'action' = 'CREATE' OR coalesce(v_lg_new, false) THEN
        PERFORM admissions.prelim_log(v_app, 'MIGRATED', NULL, (SELECT z.state FROM admissions.prelim_review z WHERE z.application_id = v_app),
                                      format('From the old portal: %s, batch %s', x->>'legacy', b.reference)
                                      || CASE WHEN v_left IS NOT NULL THEN '; only the old number kept (left as it stands here: ' || v_left || ')' ELSE '' END,
                                      jsonb_strip_nulls(jsonb_build_object('legacy', x->>'legacy', 'batch', b.reference, 'row', r.row_no, 'route', b.route,
                                                                           'action', x->>'action', 'admission', v_adm, 'payment', x->>'payment', 'feeHeld', v_held,
                                                                           'numberOnly', CASE WHEN v_number_only THEN true END, 'leftAlone', CASE WHEN v_left IS NOT NULL THEN x->'leftAlone' END)));
    ELSIF v_changed THEN
        PERFORM admissions.prelim_log(v_app, 'MIGRATION_UPDATED', (SELECT z.state FROM admissions.prelim_review z WHERE z.application_id = v_app),
                                      (SELECT z.state FROM admissions.prelim_review z WHERE z.application_id = v_app),
                                      format('Details filled in from the old portal: %s, batch %s', x->>'legacy', b.reference), NULL);
    END IF;

    -- told once, if the batch tells
    IF b.notify AND (SELECT l.told_at FROM admissions.prelim_legacy_application l WHERE l.application_id = v_app) IS NULL THEN
        IF admissions.prelim_mig_tell(v_app) THEN
            UPDATE admissions.prelim_legacy_application SET told_at = now() WHERE application_id = v_app;
        END IF;
    END IF;

    IF v_result IN ('UPDATED', 'RECONCILED') AND NOT v_changed THEN v_result := 'UNCHANGED'; END IF;
    RETURN jsonb_build_object('result', v_result, 'assessment', x, 'applicationId', v_app,
                              'note', (SELECT 'application ' || ap.application_no || ', ' || lower(replace(z.state, '_', ' ')) || CASE WHEN v_held THEN ', fee held for the Bursary' ELSE '' END
                                              || CASE WHEN v_number_only THEN '; only the old number kept'
                                                                           || coalesce(' (left as it stands here, "Fill in missing details" not ticked: ' || v_left || ')', '') ELSE '' END
                                         FROM admissions.application ap JOIN admissions.prelim_review z ON z.application_id = ap.id WHERE ap.id = v_app));
END $fn$;
COMMENT ON FUNCTION admissions.prelim_migration_apply(uuid) IS
  'V737, V745: one preliminary migration row imported from a fresh check: a new applicant (candidate, account, APP number, prelim_review, answers, O''Level, as prelim_register writes them, without its window and its notice), an applicant already here reconciled or filled in (only what is empty; the state forward only), the old number beside it, the old portal''s published outcome (admitted, accepted, not admitted) where nothing is decided here, a fee paid there held for the Bursary, the eligibility read again, the history, and the applicant told once. V745: an application made here and found by its email, in an upload that does not fill in missing details, keeps only the old number — no outcome, no state forward, no fee held — and the result says what was left alone.';

-- one row's import, recorded on the row: undone and FAILED, with the reason, if it fails (the rest go on)
CREATE OR REPLACE FUNCTION admissions.prelim_migration_import_row(p_row uuid) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE res jsonb; v_result text;
BEGIN
    BEGIN
        res := admissions.prelim_migration_apply(p_row);
        UPDATE admissions.prelim_migration_row
           SET imported_at = now(), result = res->>'result', result_note = left(res->>'note', 500),
               checked_at = now(), verdict = res->'assessment'->>'verdict', match = res->'assessment'->>'match', action = res->'assessment'->>'action',
               application_id = coalesce((res->>'applicationId')::uuid, (res->'assessment'->>'applicationId')::uuid), problems = res->'assessment'->'problems'
         WHERE id = p_row;
        v_result := res->>'result';
    EXCEPTION WHEN OTHERS THEN
        -- the row's writes are undone; the rest go on, and the row says why
        UPDATE admissions.prelim_migration_row SET imported_at = now(), result = 'FAILED', result_note = left(SQLERRM, 500) WHERE id = p_row;
        v_result := 'FAILED';
    END;
    RETURN v_result;
END $fn$;
COMMENT ON FUNCTION admissions.prelim_migration_import_row(uuid) IS
  'V745: one preliminary migration row imported (admissions.prelim_migration_apply) and its result recorded on the row; a failure undoes the row''s writes and records FAILED with the reason. The import''s loop, and the confirmation of a skipped row as a new applicant.';

/* the rows of a batch from p_from to p_to not yet imported, each alone (prelim_migration_import_row). V745: p_summary false returns only
   {processed, reference, state} — the API commits a few rows a transaction, so the APPLICATION number series (platform.next_number,
   shared with every applicant's registration of the session) is held for a moment, not for a whole chunk, and asks for the batch's
   summary once at the end */
DROP FUNCTION admissions.prelim_migration_import(uuid, int, int);
CREATE FUNCTION admissions.prelim_migration_import(p_batch uuid, p_from int, p_to int, p_summary boolean DEFAULT true) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.prelim_migration_batch; r record; n int := 0; v_from int; v_to int;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    IF b.state IN ('COMPLETED', 'ABANDONED') THEN
        RAISE EXCEPTION 'PRELIMMIG_CLOSED: % is %', b.reference, lower(b.state) USING ERRCODE = '23514';
    END IF;
    IF b.state = 'STAGING' OR EXISTS (SELECT 1 FROM admissions.prelim_migration_row x WHERE x.batch_id = b.id AND x.checked_at IS NULL) THEN
        RAISE EXCEPTION 'PRELIMMIG_NOT_CHECKED: check the whole file (the dry run) before it is imported' USING ERRCODE = '23514';
    END IF;
    v_from := greatest(coalesce(p_from, 1), 1); v_to := coalesce(p_to, b.rows_expected);
    IF v_to - v_from + 1 > 1000 THEN RAISE EXCEPTION 'PRELIMMIG_CHUNK: rows are imported up to 1,000 at a time' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.prelim_migration_batch SET state = 'IMPORTING', import_started_at = coalesce(import_started_at, now()) WHERE id = b.id;
    PERFORM set_config('moaum.prelim_migration', b.reference, true);
    FOR r IN SELECT x.id FROM admissions.prelim_migration_row x
              WHERE x.batch_id = b.id AND x.row_no BETWEEN v_from AND v_to AND x.result IS NULL ORDER BY x.row_no LOOP
        PERFORM admissions.prelim_migration_import_row(r.id);
        n := n + 1;
    END LOOP;
    PERFORM set_config('moaum.prelim_migration', '', true);
    IF NOT coalesce(p_summary, true) THEN
        RETURN jsonb_build_object('processed', n, 'reference', b.reference, 'state', 'IMPORTING');
    END IF;
    RETURN admissions.prelim_migration_summary(b.id) || jsonb_build_object('processed', n);
END $fn$;
COMMENT ON FUNCTION admissions.prelim_migration_import(uuid, int, int, boolean) IS
  'V737, V745: the checked rows p_from..p_to of a batch not yet imported, each imported alone (prelim_migration_import_row: a failed row undone and FAILED), up to 1,000 a call; the batch IMPORTING. p_summary (default true) returns the batch''s summary and processed; false returns only processed, reference and state, for an API that commits a few rows a transaction and reads the summary once.';

-- the rows of a file staged as read (V737's), with V745's person keys and gateway reference beside them
CREATE OR REPLACE FUNCTION admissions.prelim_migration_stage(p_batch uuid, p_first int, p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE b admissions.prelim_migration_batch; v_keys text[]; i int; n int; o jsonb; c jsonb; v_s int;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such migration batch' USING ERRCODE = '23503'; END IF;
    -- every row of a file is the opener's: the uploader of every fee it holds is the officer who never verifies one
    IF b.started_by IS DISTINCT FROM nullif(current_setting('moaum.actor_id', true), '')::uuid THEN
        RAISE EXCEPTION 'PRELIMMIG_NOT_YOURS: the rows of % are sent by the officer who opened it', b.reference USING ERRCODE = '23514';
    END IF;
    IF b.state <> 'STAGING' THEN
        RAISE EXCEPTION 'PRELIMMIG_STAGED: the file of % is already in; upload a corrected file as a new batch', b.reference USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000 THEN
        RAISE EXCEPTION 'PRELIMMIG_CHUNK: rows arrive 1 to 1,000 at a time' USING ERRCODE = '23514';
    END IF;
    n := jsonb_array_length(p_rows);
    IF p_first IS NULL OR p_first < 1 OR p_first + n - 1 > b.rows_expected THEN
        RAISE EXCEPTION 'PRELIMMIG_ROWS_BEYOND: rows % to % are beyond the % the file was opened with', p_first, p_first + n - 1, b.rows_expected USING ERRCODE = '23514';
    END IF;
    v_keys := ARRAY(SELECT c2.key FROM admissions.prelim_migration_columns(b.route) c2) || ARRAY['fullName', 'sheetRow'];
    FOR i IN 0 .. n - 1 LOOP
        o := p_rows -> i;
        IF jsonb_typeof(o) <> 'object' THEN
            RAISE EXCEPTION 'PRELIMMIG_ROW_SHAPE: row % is not a row of the template', p_first + i USING ERRCODE = '23514';
        END IF;
        -- only the template's columns, as text, without control characters, at most 1,000 characters each; V745: a results cell written
        -- one subject a line keeps its lines apart ("; "), so no two subjects run together into one
        SELECT coalesce(jsonb_object_agg(e.k, left(btrim(regexp_replace(e.v, '[[:cntrl:]]+', ' ', 'g')), 1000)), '{}') INTO c
          FROM (SELECT e0.k, CASE WHEN e0.k ~ '^olevel[0-9]+Results$' THEN regexp_replace(e0.v, '[[:space:]]*[\r\n]+[[:space:]]*', '; ', 'g') ELSE e0.v END AS v
                  FROM jsonb_each_text(o) e0(k, v)) e
         WHERE e.k = ANY (v_keys) AND btrim(regexp_replace(coalesce(e.v, ''), '[[:cntrl:]]+', ' ', 'g')) <> '';
        INSERT INTO admissions.prelim_migration_row (batch_id, row_no, data, legacy_no, applicant, email, fee_ref, olevel_keys, person_keys, gateway_ref)
        VALUES (b.id, p_first + i, c, upper(admissions.pg_mig_t(c, 'legacyApplicationNo')),
                left(nullif(concat_ws(', ', upper(admissions.pg_mig_t(c, 'surname')),
                                      nullif(concat_ws(' ', admissions.pg_mig_t(c, 'firstName'), admissions.pg_mig_t(c, 'otherNames')), '')), ''), 200),
                admissions.first_email(admissions.pg_mig_t(c, 'email')),
                upper(btrim(admissions.pg_mig_t(c, 'paymentReference'))),
                ARRAY(SELECT k FROM (SELECT admissions.prelim_mig_olevel_key(admissions.pg_mig_t(c, 'olevel' || s || 'Body'), admissions.pg_mig_t(c, 'olevel' || s || 'Year'),
                                                                               admissions.pg_mig_t(c, 'olevel' || s || 'Number')) AS k
                                       FROM generate_series(1, 2) s) z WHERE k IS NOT NULL),
                admissions.prelim_mig_person_keys(c), upper(btrim(admissions.pg_mig_t(c, 'gatewayReference'))))
        ON CONFLICT (batch_id, row_no) DO UPDATE
           SET data = EXCLUDED.data, legacy_no = EXCLUDED.legacy_no, applicant = EXCLUDED.applicant, email = EXCLUDED.email, fee_ref = EXCLUDED.fee_ref,
               olevel_keys = EXCLUDED.olevel_keys, person_keys = EXCLUDED.person_keys, gateway_ref = EXCLUDED.gateway_ref;
    END LOOP;
    UPDATE admissions.prelim_migration_batch SET rows_staged = (SELECT count(*) FROM admissions.prelim_migration_row r WHERE r.batch_id = b.id) WHERE id = b.id
    RETURNING rows_staged INTO v_s;
    RETURN jsonb_build_object('staged', v_s, 'expected', b.rows_expected);
END $fn$;

/* the officer's word on a possible same applicant: a new applicant all the same, with its reason. V745: a row the import skipped for that
   review alone (SKIPPED, REQUIRES_REVIEW) can be confirmed afterwards in its own batch — imported or finished, never set aside — and is
   then imported there and then (prelim_migration_import_row), as the import would have */
CREATE OR REPLACE FUNCTION admissions.prelim_migration_row_new(p_row uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_migration_row; b admissions.prelim_migration_batch; x jsonb; v_skipped boolean; v_result text;
BEGIN
    PERFORM admissions.prelim_mig_writer();
    SELECT * INTO r FROM admissions.prelim_migration_row WHERE id = p_row;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such migration row' USING ERRCODE = '23503'; END IF;
    -- the batch first, as the import takes it: a row confirmed while its batch is importing waits for the chunk in hand
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = r.batch_id FOR UPDATE;
    SELECT * INTO r FROM admissions.prelim_migration_row WHERE id = p_row FOR UPDATE;
    v_skipped := r.result = 'SKIPPED' AND r.verdict = 'REQUIRES_REVIEW';
    IF NOT ((b.state IN ('CHECKED', 'IMPORTING') AND r.result IS NULL) OR (b.state IN ('IMPORTING', 'COMPLETED') AND v_skipped)) THEN
        RAISE EXCEPTION 'PRELIMMIG_CLOSED: row % of % is no longer open', r.row_no, b.reference USING ERRCODE = '23514';
    END IF;
    IF NOT r.problems @> '[{"code":"POSSIBLE_SAME_APPLICANT"}]' THEN
        RAISE EXCEPTION 'PRELIMMIG_NOTHING_TO_DECIDE: row % is not held as a possible same applicant', r.row_no USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PRELIMMIG_REASON: say how you know this is another person (at least ten characters)' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.prelim_migration_row SET decided_new = true, decided_new_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, decided_new_reason = btrim(p_reason)
     WHERE id = r.id;
    x := admissions.prelim_migration_assess(r.id);
    IF v_skipped AND x->>'verdict' IN ('READY', 'WARNING') THEN
        -- skipped by the import for this review alone: imported now, in its own batch
        PERFORM set_config('moaum.prelim_migration', b.reference, true);
        v_result := admissions.prelim_migration_import_row(r.id);
        PERFORM set_config('moaum.prelim_migration', '', true);
        RETURN x || (SELECT jsonb_build_object('result', z.result, 'resultNote', z.result_note, 'applicationId', z.application_id)
                       FROM admissions.prelim_migration_row z WHERE z.id = r.id);
    END IF;
    UPDATE admissions.prelim_migration_row
       SET checked_at = now(), verdict = x->>'verdict', match = x->>'match', action = x->>'action', application_id = (x->>'applicationId')::uuid, problems = x->'problems'
     WHERE id = r.id;
    RETURN x || CASE WHEN v_skipped THEN jsonb_build_object('result', r.result, 'resultNote', r.result_note) ELSE '{}'::jsonb END;
END $fn$;
COMMENT ON FUNCTION admissions.prelim_migration_row_new(uuid, text) IS
  'V737, V745: the uploader''s word on a row held as a possible same applicant — a new applicant all the same, with the reason (ten characters at least) — and the row checked again. V745: a row the import skipped for that review alone (SKIPPED, REQUIRES_REVIEW) is confirmed in its own batch, imported or finished (never set aside), and imported there and then; the result comes back as result, resultNote, applicationId.';

-- the batch's figures (V737's), with V745's: the old-number-only rows, what is still to import, and the fees a RECONCILE row leaves alone
CREATE OR REPLACE FUNCTION admissions.prelim_migration_summary(p_batch uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'id', b.id, 'reference', b.reference, 'route', b.route, 'routeName', (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = b.route),
        'session', b.session, 'fileName', b.file_name, 'fileSha256', b.file_sha256, 'state', b.state, 'allowUpdate', b.allow_update, 'notify', b.notify,
        'rowsExpected', b.rows_expected, 'rowsStaged', b.rows_staged, 'startedById', b.started_by,
        'startedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.started_by), 'startedOffice', b.started_office, 'startedAt', b.started_at,
        'checkedAt', b.checked_at, 'importStartedAt', b.import_started_at, 'completedAt', b.completed_at,
        'completedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.completed_by),
        'abandonedAt', b.abandoned_at, 'abandonedBy', (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = b.abandoned_by), 'abandonedReason', b.abandoned_reason)
        || jsonb_build_object(
        'rows', count(r.id), 'staged', b.rows_staged, 'checked', count(r.id) FILTER (WHERE r.checked_at IS NOT NULL),
        'ready', count(r.id) FILTER (WHERE r.verdict = 'READY'), 'warning', count(r.id) FILTER (WHERE r.verdict = 'WARNING'),
        'duplicateInFile', count(r.id) FILTER (WHERE r.verdict = 'DUPLICATE_IN_FILE'), 'conflict', count(r.id) FILTER (WHERE r.verdict = 'CONFLICT'),
        'requiresReview', count(r.id) FILTER (WHERE r.verdict = 'REQUIRES_REVIEW'), 'error', count(r.id) FILTER (WHERE r.verdict = 'ERROR'),
        'verdicts', jsonb_build_object('READY', count(r.id) FILTER (WHERE r.verdict = 'READY'), 'WARNING', count(r.id) FILTER (WHERE r.verdict = 'WARNING'),
                                       'DUPLICATE_IN_FILE', count(r.id) FILTER (WHERE r.verdict = 'DUPLICATE_IN_FILE'), 'CONFLICT', count(r.id) FILTER (WHERE r.verdict = 'CONFLICT'),
                                       'REQUIRES_REVIEW', count(r.id) FILTER (WHERE r.verdict = 'REQUIRES_REVIEW'), 'ERROR', count(r.id) FILTER (WHERE r.verdict = 'ERROR')),
        'newApplicants', count(r.id) FILTER (WHERE r.action = 'CREATE' AND r.verdict IN ('READY', 'WARNING')),
        'existing', count(r.id) FILTER (WHERE r.match = 'EXISTING_APPLICANT'),
        'toUpdate', count(r.id) FILTER (WHERE r.action IN ('UPDATE', 'RECONCILE') AND r.verdict IN ('READY', 'WARNING')),
        -- V745: what is still to import (a resumed import's dialog counts these), and the applications made here that keep only the old number
        'newApplicantsToImport', count(r.id) FILTER (WHERE r.action = 'CREATE' AND r.verdict IN ('READY', 'WARNING') AND r.result IS NULL),
        'toUpdateToImport', count(r.id) FILTER (WHERE r.action IN ('UPDATE', 'RECONCILE') AND r.verdict IN ('READY', 'WARNING') AND r.result IS NULL),
        'oldNumberOnly', count(r.id) FILTER (WHERE r.action = 'RECONCILE' AND NOT b.allow_update AND r.verdict IN ('READY', 'WARNING')),
        'skipped', count(r.id) FILTER (WHERE r.verdict IS NOT NULL AND r.verdict NOT IN ('READY', 'WARNING')),
        'invalid', count(r.id) FILTER (WHERE r.verdict = 'ERROR'),
        -- a possible same applicant the officer confirmed as new reads "warning" (prelim_migration_row_new): no longer a duplicate
        'duplicates', count(r.id) FILTER (WHERE r.verdict = 'DUPLICATE_IN_FILE' OR r.problems @> '[{"code":"POSSIBLE_SAME_APPLICANT","level":"review"}]'),
        -- the fees the import holds for the Bursary (prelim_mig_hold's own test): a row imported, its fee not already paid here, and its
        -- application holding no fee of another batch that is held or verified, nor one the Bursary rejected for the same claim; V745: never
        -- a RECONCILE row of an upload that does not fill in missing details (the old number only)
        'paymentsToVerify', count(r.id) FILTER (WHERE admissions.prelim_mig_status('PAYMENT', r.data ->> 'paymentStatus') = 'PAID'
                                                   AND r.verdict IN ('READY', 'WARNING') AND r.action <> 'NONE'
                                                   AND (r.action <> 'RECONCILE' OR b.allow_update)
                                                   AND NOT r.problems @> '[{"code":"FEE_ALREADY_PAID_HERE"}]'
                                                   AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f
                                                                    WHERE f.application_id = r.application_id AND f.batch_id <> r.batch_id
                                                                      AND (f.state <> 'REJECTED' OR r.fee_ref IS NULL
                                                                           OR upper(btrim(f.legacy_reference)) IS NOT DISTINCT FROM r.fee_ref))),
        'programmeConflicts', count(r.id) FILTER (WHERE r.problems @> '[{"code":"PROGRAMME_MISMATCH"}]' OR r.problems @> '[{"code":"PROGRAMME_CONFLICT"}]'),
        'readyToImport', count(r.id) FILTER (WHERE r.verdict IN ('READY', 'WARNING') AND r.result IS NULL))
        || jsonb_build_object(
        'imported', count(r.id) FILTER (WHERE r.result IS NOT NULL),
        'created', count(r.id) FILTER (WHERE r.result = 'CREATED'), 'updated', count(r.id) FILTER (WHERE r.result = 'UPDATED'),
        'reconciled', count(r.id) FILTER (WHERE r.result = 'RECONCILED'), 'unchanged', count(r.id) FILTER (WHERE r.result = 'UNCHANGED'),
        'importSkipped', count(r.id) FILTER (WHERE r.result = 'SKIPPED'), 'failed', count(r.id) FILTER (WHERE r.result = 'FAILED'),
        'results', jsonb_build_object('CREATED', count(r.id) FILTER (WHERE r.result = 'CREATED'), 'UPDATED', count(r.id) FILTER (WHERE r.result = 'UPDATED'),
                                      'RECONCILED', count(r.id) FILTER (WHERE r.result = 'RECONCILED'), 'UNCHANGED', count(r.id) FILTER (WHERE r.result = 'UNCHANGED'),
                                      'SKIPPED', count(r.id) FILTER (WHERE r.result = 'SKIPPED'), 'FAILED', count(r.id) FILTER (WHERE r.result = 'FAILED')),
        'feesHeld', (SELECT count(*) FROM admissions.prelim_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'REQUIRES_REVIEW'),
        'feesVerified', (SELECT count(*) FROM admissions.prelim_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'VERIFIED'),
        'feesRejected', (SELECT count(*) FROM admissions.prelim_legacy_fee x WHERE x.batch_id = b.id AND x.state = 'REJECTED'))
      FROM admissions.prelim_migration_batch b LEFT JOIN admissions.prelim_migration_row r ON r.batch_id = b.id
     WHERE b.id = p_batch
     GROUP BY b.id
$$;

-- ── 7 · the Bursary's decision and the reconciliation ────────────────────────────────────────────────────────────────────
/* V737's, with the amount (V745): a fee that came with no amount is verified at the amount the Bursary gives (p_amount), else at the
   programme's stated application fee; a fee that came with an amount is verified at that amount */
DROP FUNCTION admissions.prelim_legacy_fee_decide(uuid, boolean, text, text);
CREATE FUNCTION admissions.prelim_legacy_fee_decide(p_fee uuid, p_verify boolean, p_note text, p_reference text DEFAULT NULL, p_amount numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
        f admissions.prelim_legacy_fee; b admissions.prelim_migration_batch; a admissions.application; acc admissions.applicant_account; v_route text; v_name text;
        v_ref text; v_ts timestamptz; v_receipt text; v_fr uuid; v_state text; v_channels text[] := ARRAY['PORTAL'];
        v_amount numeric; v_stated numeric;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PRELIMMIG_ACTOR: a fee is verified by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'PRELIMMIG_FEE_OFFICE: the Bursary verifies an application fee paid on the old portal, not %', coalesce(nullif(v_office, ''), 'this office') USING ERRCODE = '42501';
    END IF;
    SELECT * INTO f FROM admissions.prelim_legacy_fee WHERE id = p_fee FOR UPDATE;
    IF f.id IS NULL THEN RAISE EXCEPTION 'no such old-portal fee' USING ERRCODE = '23503'; END IF;
    IF f.state <> 'REQUIRES_REVIEW' THEN
        RAISE EXCEPTION 'PRELIMMIG_FEE_DECIDED: this fee is already %', lower(f.state) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO b FROM admissions.prelim_migration_batch WHERE id = f.batch_id;
    IF b.started_by = v_actor THEN
        RAISE EXCEPTION 'PRELIMMIG_SAME_OFFICER: the officer who uploaded the fee (%) does not verify it; another Bursary officer does', b.reference USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) < 5 THEN
        RAISE EXCEPTION 'PRELIMMIG_FEE_NOTE: say what was checked (the bank statement, the gateway''s record) or why it is not verified' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = f.application_id FOR UPDATE;
    SELECT * INTO acc FROM admissions.applicant_account WHERE id = a.account_id;
    v_route := admissions.applicant_route(a.id);
    v_name := (SELECT pp.name FROM admissions.prelim_programme pp WHERE pp.route = v_route);
    IF acc.email !~* '@migrate\.moau\.local$' THEN v_channels := array_append(v_channels, 'EMAIL'); END IF;
    IF acc.phone ~ '^0[0-9]{10}$' AND acc.phone <> '00000000000' THEN v_channels := array_append(v_channels, 'SMS'); END IF;
    v_state := (SELECT r.state FROM admissions.prelim_review r WHERE r.application_id = a.id);

    IF NOT coalesce(p_verify, false) THEN
        UPDATE admissions.prelim_legacy_fee SET state = 'REJECTED', decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note) WHERE id = f.id;
        PERFORM admissions.prelim_log(a.id, 'OLD_FEE_REJECTED', v_state, v_state, btrim(p_note),
                                      jsonb_strip_nulls(jsonb_build_object('reference', f.legacy_reference, 'amount', f.amount,
                                                                           'alreadyPaidHere', CASE WHEN a.fee_confirmed_at IS NOT NULL THEN true END)));
        -- told to pay only while the fee is unpaid here; an application already paid here is told nothing (the old payment is not counted)
        IF a.fee_confirmed_at IS NULL THEN
            PERFORM platform.tell_applicant(a.id, v_route, 'OLD_FEE_NOT_VERIFIED',
                jsonb_build_object('APPLICATION_NO', a.application_no, 'REFERENCE', coalesce(f.legacy_reference, 'not given'), 'NOTE', btrim(p_note)),
                'prelim-old-fee-rejected:' || f.id, v_channels);
        END IF;
    ELSE
        v_ref := upper(btrim(coalesce(f.legacy_reference, nullif(btrim(coalesce(p_reference, '')), ''))));
        IF v_ref IS NULL THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_REFERENCE: this fee came with no reference; give the reference found on the evidence checked' USING ERRCODE = '23514';
        END IF;
        IF f.legacy_reference IS NOT NULL AND nullif(btrim(coalesce(p_reference, '')), '') IS NOT NULL AND upper(btrim(p_reference)) <> v_ref THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_REFERENCE: the fee carries its old reference %; it is verified under that reference', f.legacy_reference USING ERRCODE = '23514';
        END IF;
        IF length(v_ref) > 80 OR v_ref ~ '[[:cntrl:]]' THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_REFERENCE: % is not a payment reference', left(v_ref, 40) USING ERRCODE = '23514';
        END IF;
        -- V745: the amount — the one the file stated; else the one the Bursary found; else the programme's stated application fee
        IF f.amount IS NOT NULL AND p_amount IS NOT NULL AND p_amount <> f.amount THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_AMOUNT: the fee came with the amount ₦%; it is verified at that amount, or not verified, with a note', to_char(f.amount, 'FM999,999,990.00')
                USING ERRCODE = '23514';
        END IF;
        IF p_amount IS NOT NULL AND (p_amount <= 0 OR p_amount >= 100000000) THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_AMOUNT: % is not an amount paid', p_amount USING ERRCODE = '23514';
        END IF;
        v_stated := (SELECT x.application_fee + x.portal_charge FROM admissions.route_fee_rule(a.session, v_route) x);
        v_amount := coalesce(f.amount, p_amount, CASE WHEN v_stated > 0 THEN v_stated END);
        IF v_amount IS NULL THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_AMOUNT: this fee came with no amount and the programme states none; give the amount found on the evidence checked' USING ERRCODE = '23514';
        END IF;
        IF EXISTS (SELECT 1 FROM admissions.fee_reference fr WHERE fr.reference IN (v_ref, btrim(coalesce(f.legacy_reference, p_reference))))
           OR EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee x WHERE x.id <> f.id AND x.state <> 'REJECTED' AND upper(btrim(x.legacy_reference)) = v_ref)
           OR EXISTS (SELECT 1 FROM admissions.pg_legacy_fee x WHERE x.state <> 'REJECTED' AND upper(btrim(x.legacy_reference)) = v_ref) THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_REFERENCE_TAKEN: reference % is already another payment''s on this portal; a payment is recorded once', v_ref USING ERRCODE = '23514';
        END IF;
        IF a.fee_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'PRELIMMIG_FEE_ALREADY_PAID: application % is already paid on this portal; reject the old payment instead, with a note', a.application_no USING ERRCODE = '23514';
        END IF;
        v_ts := admissions.pg_mig_at(f.paid_on);
        v_receipt := 'RCT-' || left(a.session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', a.session)::text, 5, '0');
        -- the old reference posted as a confirmed fee, as the gateway's confirmation does it (never "Old-portal migration": V175's reset deletes those)
        PERFORM set_config('moaum.prelim_fee_posting', 'on', true);
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, generated_at, expires_at, confirmed_at, confirmed_by, channel, note, receipt_no)
        VALUES (gen_random_uuid(), a.id, 'APPLICATION', v_ref, v_amount, v_ts, v_ts, v_ts, v_actor, 'Old portal',
                'Paid on the old portal; verified by the Bursary: ' || btrim(p_note), v_receipt)
        RETURNING id INTO v_fr;
        PERFORM set_config('moaum.prelim_fee_posting', '', true);
        UPDATE admissions.application SET fee_confirmed_at = coalesce(fee_confirmed_at, v_ts) WHERE id = a.id;
        UPDATE admissions.fee_reference SET expires_at = least(expires_at, now())
         WHERE application_id = a.id AND kind = 'APPLICATION' AND confirmed_at IS NULL AND expires_at > now();
        UPDATE admissions.prelim_legacy_fee
           SET state = 'VERIFIED', fee_reference_id = v_fr, legacy_reference = coalesce(legacy_reference, v_ref), amount = v_amount,
               decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = btrim(p_note)
         WHERE id = f.id;
        PERFORM admissions.prelim_log(a.id, 'OLD_FEE_VERIFIED', v_state, v_state, btrim(p_note),
                                      jsonb_strip_nulls(jsonb_build_object('reference', v_ref, 'amount', v_amount, 'receipt', v_receipt,
                                                                           'amountConfirmed', CASE WHEN f.amount IS NULL THEN CASE WHEN p_amount IS NOT NULL THEN 'GIVEN' ELSE 'STATED_FEE' END END)));
        PERFORM platform.tell_applicant(a.id, v_route, 'PAYMENT_SUCCESSFUL',
            jsonb_build_object('RECEIPT_NUMBER', v_receipt, 'REFERENCE', v_ref, 'PURPOSE', coalesce(v_name, 'Preliminary') || ' application fee',
                               'AMOUNT', 'NGN ' || to_char(v_amount, 'FM999,999,990.00'), 'PAID_ON', to_char(v_ts AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY'),
                               'CHANNEL', 'Old portal'),
            v_route || '_PAYMENT_SUCCESSFUL:' || v_ref, v_channels);
    END IF;
    RETURN (SELECT to_jsonb(x) FROM admissions.prelim_legacy_fee x WHERE x.id = f.id)
           || jsonb_build_object('applicationNo', a.application_no, 'feeConfirmed', (SELECT ap.fee_confirmed_at IS NOT NULL FROM admissions.application ap WHERE ap.id = a.id),
                                 'feeReference', (SELECT fr.reference FROM admissions.fee_reference fr WHERE fr.id = v_fr),
                                 'receiptNo', (SELECT fr.receipt_no FROM admissions.fee_reference fr WHERE fr.id = v_fr),
                                 'applicantTold', coalesce(p_verify, false) OR a.fee_confirmed_at IS NULL,
                                 'outcome', CASE WHEN coalesce(p_verify, false) THEN 'Verified: the old reference is posted as the application fee'
                                                      || CASE WHEN f.amount IS NULL AND p_amount IS NULL THEN ' at the programme''s stated fee (₦' || to_char(v_amount, 'FM999,999,990.00') || '), the file having given no amount'
                                                              WHEN f.amount IS NULL THEN ' at the amount given (₦' || to_char(v_amount, 'FM999,999,990.00') || ')' ELSE '' END
                                                      || ', and the applicant is sent the receipt.'
                                                 WHEN a.fee_confirmed_at IS NOT NULL THEN 'Not verified: the application fee is already paid on this portal, so the old payment is not counted; the applicant is not told to pay.'
                                                 ELSE 'Not verified: the applicant is told to pay the application fee on the portal, or to bring proof to the Bursary.' END);
END $fn$;
COMMENT ON FUNCTION admissions.prelim_legacy_fee_decide(uuid, boolean, text, text, numeric) IS
  'V737, V745: an application fee paid on the old portal, decided by the Bursary (never the officer who uploaded it), with a note of what was checked: verified, the old reference (or, where it came with none, the reference found on the evidence) posted as a confirmed fee — channel Old portal, a receipt, the fee confirmed — and the applicant sent the receipt; or not verified, the applicant told to pay on the portal or see the Bursary — unless the fee is already paid here, when the old payment is not counted and the applicant is told nothing (applicantTold false). A reference already on record, or a fee already paid here, is refused verification. V745: the amount posted is the file''s; where the file gave none, p_amount (the amount on the evidence), else the programme''s stated application fee; a p_amount other than the file''s is refused (PRELIMMIG_FEE_AMOUNT).';

-- the reconciliation's figures: what was migrated, what is held, verified, rejected, and what has no payment at all (V737's, restated)
CREATE OR REPLACE FUNCTION admissions.prelim_legacy_fee_figures(p_route text DEFAULT NULL) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH la AS (SELECT l.application_id, r.route, a.fee_confirmed_at FROM admissions.prelim_legacy_application l
                  JOIN admissions.prelim_review r ON r.application_id = l.application_id JOIN admissions.application a ON a.id = l.application_id
                 WHERE p_route IS NULL OR r.route = upper(btrim(p_route))),
         f AS (SELECT x.*, r.route FROM admissions.prelim_legacy_fee x JOIN admissions.prelim_review r ON r.application_id = x.application_id
                WHERE p_route IS NULL OR r.route = upper(btrim(p_route))),
         -- the latest checked row of each old number not yet migrated, whose payment reference is claimed twice — V745: in any batch,
         -- whatever its state (a claim skipped by a finished import is still unsettled; it needs the Bursary's review)
         dup AS (SELECT DISTINCT ON (rw.legacy_no) rw.legacy_no, b.route, rw.problems
                   FROM admissions.prelim_migration_row rw JOIN admissions.prelim_migration_batch b ON b.id = rw.batch_id
                  WHERE rw.legacy_no IS NOT NULL AND rw.checked_at IS NOT NULL
                    AND (p_route IS NULL OR b.route = upper(btrim(p_route)))
                    AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_application l WHERE upper(btrim(l.legacy_application_no)) = rw.legacy_no)
                  ORDER BY rw.legacy_no, b.started_at DESC, rw.row_no DESC),
         dupf AS (SELECT d.* FROM dup d WHERE d.problems @> '[{"code":"FEE_REFERENCE_IN_FILE"}]' OR d.problems @> '[{"code":"FEE_REFERENCE_ELSEWHERE"}]'),
         per AS (SELECT p.route, p.name,
                        (SELECT count(*) FROM la WHERE la.route = p.route) AS imported,
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.legacy_reference IS NOT NULL) AS with_reference,
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.state = 'VERIFIED') AS verified,
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.state = 'REQUIRES_REVIEW') AS unverified,
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.state = 'REJECTED') AS rejected,
                        (SELECT count(*) FROM la WHERE la.route = p.route AND la.fee_confirmed_at IS NULL
                            AND NOT EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee x WHERE x.application_id = la.application_id)) AS no_payment,
                        (SELECT count(DISTINCT legacy_no) FROM dupf WHERE dupf.route = p.route) AS duplicates,
                        -- V745: held with no amount (the Bursary confirms it)
                        (SELECT count(*) FROM f WHERE f.route = p.route AND f.state = 'REQUIRES_REVIEW' AND f.amount IS NULL) AS to_confirm,
                        (SELECT coalesce(sum(f.amount), 0) FROM f WHERE f.route = p.route AND f.state = 'REQUIRES_REVIEW') AS held,
                        (SELECT coalesce(sum(f.amount), 0) FROM f WHERE f.route = p.route AND f.state = 'VERIFIED') AS verified_amount
                   FROM admissions.prelim_programme p
                  WHERE p.route IN ('PRELIMINARY_SCIENCE', 'PRELIMINARY_TECHNOLOGY') AND (p_route IS NULL OR p.route = upper(btrim(p_route))))
    SELECT jsonb_build_object(
        'imported', coalesce(sum(imported), 0), 'withReference', coalesce(sum(with_reference), 0), 'verified', coalesce(sum(verified), 0),
        'unverified', coalesce(sum(unverified), 0), 'rejected', coalesce(sum(rejected), 0), 'noPaymentRecord', coalesce(sum(no_payment), 0),
        'duplicateReferences', coalesce(sum(duplicates), 0),
        -- V745: every claim the Bursary must settle — held, without any payment record, or claimed twice
        'forReview', coalesce(sum(unverified), 0) + coalesce(sum(no_payment), 0) + coalesce(sum(duplicates), 0),
        'amountToConfirm', coalesce(sum(to_confirm), 0),
        'amountHeld', coalesce(sum(held), 0), 'amountVerified', coalesce(sum(verified_amount), 0),
        'byRoute', coalesce(jsonb_agg(jsonb_build_object('route', route, 'name', name, 'imported', imported, 'withReference', with_reference, 'verified', verified,
                                                         'unverified', unverified, 'rejected', rejected, 'noPaymentRecord', no_payment, 'duplicateReferences', duplicates,
                                                         'forReview', unverified + no_payment + duplicates, 'amountToConfirm', to_confirm,
                                                         'amountHeld', held, 'amountVerified', verified_amount) ORDER BY name), '[]'::jsonb))
      FROM per
$$;
COMMENT ON FUNCTION admissions.prelim_legacy_fee_figures(text) IS
  'V737, V745: the old-portal fee reconciliation of a route (both when NULL): imported, with a reference, verified, unverified (held), rejected, no payment record, duplicate references, for review, amounts held and verified. V745: duplicate references counted from every batch whose old number is still not migrated, whatever its state, and among forReview (held + no payment record + duplicates); amountToConfirm counts fees held with no amount.';

-- ── 8 · the programme corrected: the Office's pending correction kept ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.prelim_change_route_check(p_app uuid, p_to_route text) RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; c admissions.candidate; pf admissions.prelim_programme; pt admissions.prelim_programme;
        v_to text := upper(btrim(coalesce(p_to_route, ''))); v_code text; v_msg text; v_after text; v_missing jsonb := '[]';
        v_fee_status text; v_paid numeric := 0; v_refs text[] := '{}'; h admissions.prelim_legacy_fee; v_from_fee numeric; v_to_fee numeric;
        v_covers boolean := true; v_dup text; v_remap uuid; t admissions.prelim_target; v_from_target text; v_spec text; v_legacy text; v_dob text;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app;
    IF r.application_id IS NULL THEN RAISE EXCEPTION 'PRELIM_NOT_APPLICATION: that is not a preliminary programme application' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO pf FROM admissions.prelim_programme WHERE route = r.route;
    SELECT * INTO pt FROM admissions.prelim_programme WHERE route = v_to;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = r.target_id;
    v_from_target := coalesce((SELECT g.name FROM ref.programme g WHERE g.code = t.programme_code), t.requested_name);
    v_spec := (SELECT s.name FROM admissions.prelim_specialisation s WHERE s.id = r.specialisation_id);
    v_legacy := (SELECT l.legacy_application_no FROM admissions.prelim_legacy_application l WHERE l.application_id = p_app);
    v_dob := (SELECT sa.value FROM admissions.screening_answer sa WHERE sa.application_id = p_app AND sa.field = 'date_of_birth');

    -- the fee as it stands: paid (confirmed references), held (an old-portal fee waiting for the Bursary), nothing to pay, or unpaid
    SELECT coalesce(sum(fr.amount), 0), coalesce(array_agg(fr.reference ORDER BY fr.confirmed_at), '{}') INTO v_paid, v_refs
      FROM admissions.fee_reference fr WHERE fr.application_id = p_app AND fr.kind = 'APPLICATION' AND fr.confirmed_at IS NOT NULL;
    SELECT * INTO h FROM admissions.prelim_legacy_fee f WHERE f.application_id = p_app AND f.state = 'REQUIRES_REVIEW';
    SELECT f.application_fee + f.portal_charge INTO v_from_fee FROM admissions.route_fee_rule(a.session, r.route) f;
    IF pt.route IS NOT NULL THEN
        SELECT f.application_fee + f.portal_charge INTO v_to_fee FROM admissions.route_fee_rule(a.session, pt.route) f;
    END IF;
    IF a.fee_confirmed_at IS NOT NULL AND v_paid > 0 THEN
        v_fee_status := 'PAID';
    ELSIF a.fee_confirmed_at IS NOT NULL THEN
        v_fee_status := 'NOT_REQUIRED';
    ELSIF h.id IS NOT NULL THEN
        v_fee_status := 'HELD'; v_paid := h.amount; v_refs := CASE WHEN h.legacy_reference IS NOT NULL THEN ARRAY[h.legacy_reference] ELSE '{}' END;
    ELSIF v_from_fee = 0 THEN
        v_fee_status := 'NOT_REQUIRED';
    ELSE
        v_fee_status := 'UNPAID'; v_paid := 0;
    END IF;
    -- a fee settled (or held) carries across unless the new programme costs more than the one it settled; V745: a fee held with no
    -- amount (the Bursary confirms it) is read as the programme's own fee
    v_covers := CASE v_fee_status WHEN 'PAID' THEN v_paid >= coalesce(v_to_fee, 0) OR coalesce(v_to_fee, 0) <= coalesce(v_from_fee, 0)
                                  WHEN 'HELD' THEN coalesce(v_paid, v_from_fee, 0) >= coalesce(v_to_fee, 0) OR coalesce(v_to_fee, 0) <= coalesce(v_from_fee, 0)
                                  WHEN 'NOT_REQUIRED' THEN a.fee_confirmed_at IS NULL OR coalesce(v_to_fee, 0) = 0
                                  ELSE true END;

    -- the target kept only where the same programme of the register is a target of the new programme too
    IF pt.route IS NOT NULL AND t.programme_code IS NOT NULL THEN
        SELECT t2.id INTO v_remap FROM admissions.prelim_target t2 WHERE t2.route = pt.route AND t2.programme_code = t.programme_code AND t2.state = 'MAPPED';
    END IF;
    IF pt.route IS NOT NULL THEN v_missing := admissions.prelim_route_missing(p_app, pt.route, v_remap); END IF;
    -- V745: an application the Office sent back for a correction stays with the applicant, whatever the new programme asks
    v_after := CASE WHEN r.state = 'DRAFT' THEN 'DRAFT'
                    WHEN r.state = 'CORRECTION_REQUIRED' THEN 'CORRECTION_REQUIRED'
                    WHEN r.state IN ('SUBMITTED', 'UNDER_REVIEW', 'RECOMMENDED')
                         THEN CASE WHEN jsonb_array_length(v_missing) > 0 THEN 'CORRECTION_REQUIRED' ELSE 'SUBMITTED' END
                    ELSE r.state END;

    -- the same person already on the new programme in the session (the name and birth date, or an O'Level sitting)
    IF pt.route IS NOT NULL THEN
        SELECT ap.application_no INTO v_dup
          FROM admissions.application ap
          JOIN admissions.prelim_review pr ON pr.application_id = ap.id AND pr.route = pt.route AND pr.state <> 'WITHDRAWN'
          JOIN admissions.candidate c2 ON c2.id = ap.candidate_id
          LEFT JOIN admissions.screening_answer sa ON sa.application_id = ap.id AND sa.field = 'date_of_birth'
         WHERE ap.session = a.session AND ap.id <> p_app
           AND ((upper(c2.surname) = upper(c.surname) AND lower(split_part(c2.other_names, ' ', 1)) = lower(split_part(c.other_names, ' ', 1)) AND sa.value = v_dob)
                OR EXISTS (SELECT 1 FROM admissions.screening_olevel o1
                             JOIN admissions.screening_olevel o2 ON o2.application_id = ap.id AND o2.active AND upper(o2.exam_body) = upper(o1.exam_body)
                                  AND o2.exam_year = o1.exam_year
                                  AND upper(regexp_replace(o2.exam_number, '\s', '', 'g')) = upper(regexp_replace(o1.exam_number, '\s', '', 'g'))
                            WHERE o1.application_id = p_app AND o1.active))
         ORDER BY ap.application_no LIMIT 1;
    END IF;

    IF v_to NOT IN ('PRELIMINARY_TECHNOLOGY', 'PRELIMINARY_SCIENCE') OR r.route NOT IN ('PRELIMINARY_TECHNOLOGY', 'PRELIMINARY_SCIENCE') OR v_to = r.route OR pt.route IS NULL THEN
        v_code := 'PRELIM_CHANGE_ROUTE';
        v_msg := 'a preliminary application moves only between Preliminary Technology & Industrial Studies and Preliminary Science, to the other one';
    ELSIF r.published_at IS NOT NULL THEN
        v_code := 'PRELIM_CHANGE_PUBLISHED';
        v_msg := format('the outcome was published on %s and stands; the programme of a published application is not changed', to_char(r.published_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'));
    ELSIF r.state IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED') THEN
        v_code := 'PRELIM_CHANGE_DECIDED';
        v_msg := format('the application is decided (%s); the Academic Office reopens it before its programme is changed', lower(replace(r.state, '_', ' ')));
    ELSIF r.state = 'WITHDRAWN' THEN
        v_code := 'PRELIM_CHANGE_WITHDRAWN';
        v_msg := 'the application was withdrawn; a withdrawn application''s programme is not changed';
    ELSIF v_dup IS NOT NULL THEN
        v_code := 'PRELIM_CHANGE_DUPLICATE';
        v_msg := format('the applicant already has a %s application for %s (%s); one person holds one application', pt.name, a.session, v_dup);
    ELSIF NOT v_covers THEN
        v_code := 'PRELIM_CHANGE_FEE_SHORT';
        v_msg := format('the application fee paid (₦%s) does not cover the %s application fee (₦%s)', to_char(coalesce(v_paid, v_from_fee, 0), 'FM999,999,990.##'), pt.name, to_char(coalesce(v_to_fee, 0), 'FM999,999,990.##'));
    END IF;

    RETURN jsonb_build_object(
        'may', v_code IS NULL, 'refusal', CASE WHEN v_code IS NOT NULL THEN jsonb_build_object('code', v_code, 'message', v_msg) END,
        'applicationId', a.id, 'applicationNo', a.application_no, 'legacyNo', v_legacy, 'applicantName', c.surname || ', ' || c.other_names, 'session', a.session,
        'route', r.route, 'routeName', pf.name, 'toRoute', pt.route, 'toRouteName', pt.name,
        'state', r.state, 'stateAfter', v_after, 'published', r.published_at IS NOT NULL,
        -- V745: the Office's own request, kept with the programme's note added
        'pendingCorrection', CASE WHEN r.state = 'CORRECTION_REQUIRED' THEN r.request_note END,
        'fromTarget', CASE WHEN t.id IS NOT NULL THEN jsonb_build_object('id', t.id, 'name', v_from_target, 'group', t.group_name, 'specialisation', v_spec) END,
        'targetKept', CASE WHEN v_remap IS NOT NULL THEN jsonb_build_object('id', v_remap, 'name', v_from_target) END,
        'feeStatus', v_fee_status, 'feeAmount', v_paid, 'feeReferences', to_jsonb(v_refs), 'heldReference', h.legacy_reference,
        'fromRouteFee', v_from_fee, 'toRouteFee', v_to_fee, 'feeCovers', v_covers, 'missing', v_missing);
END $fn$;
COMMENT ON FUNCTION admissions.prelim_change_route_check(uuid, text) IS
  'V737, V745: whether a preliminary application may move to the other preliminary programme, and why not (PRELIM_CHANGE_ROUTE, _PUBLISHED, _DECIDED, _WITHDRAWN, _DUPLICATE, _FEE_SHORT), with the facts the officer reads first: both numbers, the programme now and after, the state now and after, the fee as it stands (PAID with its references, HELD with the old reference, UNPAID, NOT_REQUIRED) and the new programme''s fee, and what the applicant must complete under the new programme. V745: an application the Office sent back (CORRECTION_REQUIRED) stays so, its request kept (pendingCorrection); a fee held with no amount is read as the old programme''s fee.';

CREATE OR REPLACE FUNCTION admissions.prelim_change_route(p_app uuid, p_to_route text, p_from_route text, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; k jsonb; v_to text := upper(btrim(coalesce(p_to_route, ''))); pt admissions.prelim_programme;
        v_after text; v_note text; v_remap uuid; x admissions.prelim_route_change; v_reason text := btrim(coalesce(p_reason, '')); v_from_name text;
        acc admissions.applicant_account; v_channels text[] := ARRAY['PORTAL']; v_next text; v_fee_note text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_pending boolean;
BEGIN
    PERFORM admissions.prelim_route_officer();
    IF length(v_reason) < 15 OR array_length(regexp_split_to_array(v_reason, '\s+'), 1) < 3 THEN
        RAISE EXCEPTION 'PRELIM_CHANGE_REASON: say why the programme is changed, in a sentence (at least 15 characters and three words)' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app FOR UPDATE;
    IF r.application_id IS NULL THEN RAISE EXCEPTION 'PRELIM_NOT_APPLICATION: that is not a preliminary programme application' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    IF r.route IS DISTINCT FROM upper(btrim(coalesce(p_from_route, ''))) THEN
        RAISE EXCEPTION 'PRELIM_CHANGE_STALE: the application is now under %, not the programme the screen showed; open it again', (SELECT p.name FROM admissions.prelim_programme p WHERE p.route = r.route)
            USING ERRCODE = '23514';
    END IF;
    k := admissions.prelim_change_route_check(p_app, v_to);
    IF NOT (k->>'may')::boolean THEN
        RAISE EXCEPTION '%: %', k->'refusal'->>'code', k->'refusal'->>'message' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO pt FROM admissions.prelim_programme WHERE route = v_to;
    v_from_name := k->>'routeName';
    v_after := k->>'stateAfter';
    v_remap := (k->'targetKept'->>'id')::uuid;
    v_next := (SELECT string_agg(e->>'message', '; ') FROM jsonb_array_elements(k->'missing') e);
    v_note := 'Your application was moved by the University from ' || v_from_name || ' to ' || pt.name || '. Complete under ' || pt.name || ': ' || coalesce(v_next, 'nothing more') || '.';
    -- V745: the Office's request still stands — the programme's note is added to it, never put in its place
    v_pending := r.state = 'CORRECTION_REQUIRED' AND nullif(btrim(coalesce(r.request_note, '')), '') IS NOT NULL;
    UPDATE admissions.prelim_review
       SET route = v_to,
           target_id = v_remap, target_programme = CASE WHEN v_remap IS NOT NULL THEN r.target_programme END, specialisation_id = NULL,
           target_set_at = CASE WHEN v_remap IS NOT NULL THEN r.target_set_at END,
           state = v_after,
           request_note = CASE WHEN v_after <> 'CORRECTION_REQUIRED' THEN request_note
                               WHEN v_pending THEN rtrim(r.request_note) || E'\n\n' || v_note
                               ELSE v_note END,
           requested_at = CASE WHEN v_after = 'CORRECTION_REQUIRED' AND r.state <> 'CORRECTION_REQUIRED' THEN now() ELSE requested_at END,
           requested_by = CASE WHEN v_after = 'CORRECTION_REQUIRED' AND r.state <> 'CORRECTION_REQUIRED' THEN v_actor ELSE requested_by END,
           recommended_at = NULL, recommended_by = NULL, recommendation_note = NULL, review_started_at = NULL, review_started_by = NULL,
           -- the old programme's remediation decision does not settle the new one's: prelim_evaluate reads it afresh (the history keeps it)
           remediation_status = CASE WHEN remediation_status IN ('NOT_REQUIRED', 'REQUIRED') THEN remediation_status END,
           remediation_note = NULL, remediation_set_by = NULL, remediation_set_at = NULL,
           updated_at = now()
     WHERE application_id = p_app;
    UPDATE admissions.candidate SET programme = pt.name WHERE id = a.candidate_id;
    -- a reference drawn for the old programme's fee and not paid is closed where the new fee differs; paid fees and receipts stay
    UPDATE admissions.fee_reference SET expires_at = least(expires_at, now())
     WHERE application_id = p_app AND kind = 'APPLICATION' AND confirmed_at IS NULL AND expires_at > now()
       AND amount IS DISTINCT FROM (k->>'toRouteFee')::numeric;
    PERFORM admissions.prelim_evaluate(p_app);
    x := admissions.prelim_route_change_row(k, v_reason, 'APPLIED', NULL, NULL, v_after);
    PERFORM admissions.prelim_log(p_app, 'ROUTE_CHANGED', r.state, v_after, v_reason,
                                  jsonb_strip_nulls(jsonb_build_object('fromRoute', r.route, 'toRoute', v_to, 'fromTarget', k->'fromTarget',
                                                                       'fee', jsonb_build_object('status', k->>'feeStatus', 'amount', (k->>'feeAmount')::numeric, 'references', k->'feeReferences'),
                                                                       'reference', x.reference, 'missing', k->'missing',
                                                                       'officeRequestKept', CASE WHEN v_pending THEN true END)));
    -- the applicant told under the new programme's own notices, on the channels that are really theirs
    SELECT * INTO acc FROM admissions.applicant_account WHERE id = a.account_id;
    IF acc.email !~* '@migrate\.moau\.local$' THEN v_channels := array_append(v_channels, 'EMAIL'); END IF;
    IF acc.phone ~ '^0[0-9]{10}$' AND acc.phone <> '00000000000' THEN v_channels := array_append(v_channels, 'SMS'); END IF;
    v_fee_note := CASE k->>'feeStatus' WHEN 'PAID' THEN 'The application fee you paid is kept; you do not pay it again.'
                                       WHEN 'HELD' THEN 'The application fee you paid on the old portal is still being verified by the Bursary; you are not asked to pay it again.'
                                       WHEN 'UNPAID' THEN 'Pay the ' || pt.name || ' application fee from your dashboard.' ELSE '' END;
    PERFORM platform.tell_applicant(p_app, v_to, 'PROGRAMME_CHANGED',
        jsonb_build_object('APPLICATION_NO', a.application_no, 'FROM_PROGRAMME', v_from_name, 'FEE_NOTE', v_fee_note,
                           'NEXT_STEP', CASE WHEN v_next IS NOT NULL THEN 'Complete the following under ' || pt.name || ': ' || v_next || '.' ELSE 'Nothing more is needed from you now.' END
                                        -- V745: the Office's correction is still asked of them
                                        || CASE WHEN v_pending THEN ' The correction the Office asked for still stands: provide it as well.' ELSE '' END),
        'prelim-programme-changed:' || x.id, v_channels);
    RETURN jsonb_build_object('id', x.id, 'reference', x.reference, 'applicationId', x.application_id, 'applicationNo', x.application_no, 'legacyNo', x.legacy_application_no,
                              'fromRoute', x.from_route, 'toRoute', x.to_route, 'toRouteName', pt.name, 'fromState', x.from_state, 'toState', x.to_state,
                              'feeStatus', x.fee_status, 'feeAmount', x.fee_amount, 'feeReferences', to_jsonb(x.fee_references), 'missing', x.missing,
                              'targetKept', k->'targetKept', 'result', x.result, 'at', x.at, 'check', k);
END $fn$;
COMMENT ON FUNCTION admissions.prelim_change_route(uuid, text, text, text) IS
  'V737, V745: a preliminary application moved to the other preliminary programme by ICT (admissions.prelim_route_officer), with a reason, from the programme the screen showed: the same application and number; the target cleared (kept only where the same programme is a target there too); a submitted or reviewed application back with the applicant for what the new programme asks (CORRECTION_REQUIRED), else submitted afresh; the review''s recommendation and an officer''s remediation decision cleared; the O''Level, documents, fees and receipts untouched (an unpaid reference for a different amount closed); the eligibility read again; the history written once; the applicant told. V745: an application the Office had sent back stays CORRECTION_REQUIRED and keeps the Office''s request, the programme''s note added after it (and the applicant told it still stands).';

-- ── 9 · the applicant's status and the desk's figures ─────────────────────────────────────────────────────────────────────
/* the applicant's status, in the route's own terms; an unpublished decision is never shown (V701's). V745: a draft whose application fee
   paid on the old portal is held for the Bursary is not told to pay it (the next step is the Bursary's) */
CREATE OR REPLACE FUNCTION admissions.prelim_status(p_app uuid)
RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE r admissions.prelim_review; a admissions.application; p admissions.prelim_programme; t admissions.prelim_target; v_target text; v_spec text; v_office text;
BEGIN
    SELECT * INTO r FROM admissions.prelim_review WHERE application_id = p_app;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO p FROM admissions.prelim_programme WHERE route = r.route;
    SELECT * INTO t FROM admissions.prelim_target WHERE id = r.target_id;
    v_target := coalesce((SELECT pr.name FROM ref.programme pr WHERE pr.code = t.programme_code), t.requested_name);
    v_spec := (SELECT sp.name FROM admissions.prelim_specialisation sp WHERE sp.id = r.specialisation_id);
    v_office := admissions.prelim_office_words(r.route);
    IF r.state = 'WITHDRAWN' THEN RETURN QUERY SELECT 'WITHDRAWN', 'Application withdrawn', NULL::text, '/applicant/preliminary', 'This application was withdrawn.'; RETURN; END IF;
    IF r.state = 'DRAFT' THEN
        RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
            CASE WHEN admissions.prelim_fee_settled(p_app) THEN 'Complete and submit your application'
                 WHEN EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee lf WHERE lf.application_id = p_app AND lf.state = 'REQUIRES_REVIEW')
                      THEN 'Your old-portal payment is being verified by the Bursary'
                 ELSE 'Pay the application fee' END, '/applicant/preliminary',
            CASE WHEN NOT admissions.prelim_fee_settled(p_app)
                      AND EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee lf WHERE lf.application_id = p_app AND lf.state = 'REQUIRES_REVIEW')
                 THEN 'The application fee you paid on the old portal is being verified by the Bursary; you are not asked to pay it again. The form opens to you once it is verified. '
                 ELSE '' END
            || initcap(left(v_office, 1)) || substr(v_office, 2) || ' reviews your application once it is complete and submitted.'; RETURN;
    END IF;
    IF r.state = 'CORRECTION_REQUIRED' THEN
        RETURN QUERY SELECT 'CORRECTION_REQUIRED', 'Correction required', 'Provide what the Office asked for', '/applicant/preliminary', r.request_note; RETURN;
    END IF;
    IF r.published_at IS NULL THEN
        RETURN QUERY SELECT 'PENDING', 'Admission pending', NULL::text, '/applicant/preliminary',
            'Your application is with ' || v_office || '. You are told by email and SMS when the outcome is published.'; RETURN;
    END IF;
    IF r.state = 'ADMITTED' THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted into ' || p.name, 'Print your admission letter', '/applicant/preliminary',
            'You are admitted into ' || p.name || ' for ' || a.session || '.'
            || CASE WHEN t.kind = 'COURSE' THEN coalesce(' Your certificate course is ' || v_target || '.', '')
                    ELSE coalesce(' Your intended progression is ' || v_target || coalesce(' (' || v_spec || ')', '') || '; ' || coalesce(p.target_note, ''), '') END
            || CASE WHEN r.remediation_status = 'REQUIRED' THEN ' Before completing the programme you are to make up: '
                    || array_to_string(r.remediation_subjects || CASE WHEN r.remediation_credits_short > 0 THEN ARRAY[r.remediation_credits_short || ' more O''Level credit pass(es)'] ELSE '{}' END, ', ') || '.' ELSE '' END;
        RETURN;
    END IF;
    RETURN QUERY SELECT 'NOT_ADMITTED', 'Not admitted', NULL::text, '/applicant/preliminary',
        coalesce(a.decision_note, 'Your application for ' || p.name || ' for ' || a.session || ' was not successful.');
END $fn$;

/* the day a preliminary application was made, Lagos: the day it was made here — or, for one a migration created, the old portal's
   Application Date as the old-number record now holds it, NULL where no file gave one (created_at is the day of the first import, and
   stays so when a later "fill in missing details" upload gives the date). An application made here and later given its old number
   (RECONCILE) keeps its own day. The dashboard's "new" and the desk's applied-from/to read it. */
CREATE OR REPLACE FUNCTION admissions.prelim_applied_on(p_app uuid) RETURNS date LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN mr.action = 'CREATE' THEN l.applied_on
                ELSE (a.created_at AT TIME ZONE 'Africa/Lagos')::date END
      FROM admissions.application a
      LEFT JOIN admissions.prelim_legacy_application l ON l.application_id = a.id
      LEFT JOIN admissions.prelim_migration_row mr ON mr.id = l.row_id
     WHERE a.id = p_app
$$;
COMMENT ON FUNCTION admissions.prelim_applied_on(uuid) IS
  'V745: the day (Lagos) a preliminary application was made — its own created_at, except one a migration created: the old portal''s Application Date its old-number record holds (NULL when no file gave one: the day is unknown, never the day of the import). prelim_stats'' "new" counts the last seven days of it.';

/* the dashboard's figures for a session, each the filter of the list behind it (V737's prelim_stats). V745: "new" counts by
   admissions.prelim_applied_on — an application a migration created with no Application Date is not new */
CREATE OR REPLACE FUNCTION admissions.prelim_stats(p_route text, p_session text, p_dept text DEFAULT NULL, p_faculty text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH fee AS (SELECT coalesce((SELECT f.application_fee + f.portal_charge FROM admissions.route_fee_rule(p_session, upper(btrim(p_route))) f), -1) AS total),
         x AS (SELECT r.*, a.fee_confirmed_at, c.offer_state, lgy.application_id IS NOT NULL AS migrated,
                      -- admissions.prelim_applied_on, set-based
                      CASE WHEN mr.action = 'CREATE' THEN lgy.applied_on
                           ELSE (a.created_at AT TIME ZONE 'Africa/Lagos')::date END AS applied_day
                 FROM admissions.prelim_review r JOIN admissions.application a ON a.id = r.application_id
                 JOIN admissions.candidate c ON c.id = a.candidate_id
                 LEFT JOIN ref.programme tp ON tp.code = r.target_programme
                 LEFT JOIN admissions.prelim_legacy_application lgy ON lgy.application_id = r.application_id
                 LEFT JOIN admissions.prelim_migration_row mr ON mr.id = lgy.row_id
                WHERE r.route = upper(btrim(p_route)) AND a.session = p_session
                  AND (p_dept IS NULL OR tp.dept_code = p_dept) AND (p_faculty IS NULL OR tp.faculty_code = p_faculty))
    SELECT jsonb_build_object(
        'total', (SELECT count(*) FROM x),
        'paid', (SELECT count(*) FROM x WHERE fee_confirmed_at IS NOT NULL),
        'submitted', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN'),
        'incomplete', (SELECT count(*) FROM x WHERE state = 'DRAFT'),
        'pendingReview', (SELECT count(*) FROM x WHERE state = 'SUBMITTED'),
        'underReview', (SELECT count(*) FROM x WHERE state IN ('UNDER_REVIEW', 'CORRECTION_REQUIRED', 'RECOMMENDED', 'APPROVED')
                                              OR (state IN ('NOT_ADMITTED', 'REJECTED') AND published_at IS NULL)),
        'correction', (SELECT count(*) FROM x WHERE state = 'CORRECTION_REQUIRED'),
        'eligible', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND eligibility_status IN ('ELIGIBLE', 'ELIGIBLE_WITH_REMEDIATION')),
        'notEligible', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND eligibility_status IN ('NOT_ELIGIBLE', 'RESULT_REQUIRED', 'INVALID_RESULT')),
        'remediationRequired', (SELECT count(*) FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' AND remediation_status IN ('REQUIRED', 'IN_PROGRESS', 'NOT_COMPLETED', 'REQUIRES_REVIEW')),
        'admitted', (SELECT count(*) FROM x WHERE state = 'ADMITTED'),
        'notAdmitted', (SELECT count(*) FROM x WHERE state IN ('NOT_ADMITTED', 'REJECTED') AND published_at IS NOT NULL),
        'withdrawn', (SELECT count(*) FROM x WHERE state = 'WITHDRAWN'),
        -- V737; V745: an application a migration created without an Application Date is not new (made on the old portal, day unknown)
        'new', (SELECT count(*) FROM x WHERE x.applied_day > (now() AT TIME ZONE 'Africa/Lagos')::date - 7),
        'accepted', (SELECT count(*) FROM x WHERE x.offer_state = 'ACCEPTED'),
        'outstanding', (SELECT count(*) FROM x
                         WHERE x.state NOT IN ('WITHDRAWN', 'ADMITTED', 'NOT_ADMITTED', 'REJECTED')
                           AND ((x.fee_confirmed_at IS NULL AND (SELECT total FROM fee) <> 0)
                                OR x.eligibility_status IN ('RESULT_REQUIRED', 'PENDING_REVIEW')
                                OR x.target_id IS NULL
                                OR x.state = 'CORRECTION_REQUIRED'
                                OR EXISTS (SELECT 1 FROM admissions.prelim_document dq
                                            WHERE dq.route = x.route AND dq.required AND (NOT dq.second_sitting_only OR coalesce(x.sittings, 0) >= 2)
                                              AND NOT EXISTS (SELECT 1 FROM admissions.application_document ad
                                                               WHERE ad.application_id = x.application_id AND ad.kind = dq.kind
                                                                 AND ad.superseded_at IS NULL AND ad.status <> 'REJECTED')))),
        'feeHeld', (SELECT count(*) FROM x WHERE EXISTS (SELECT 1 FROM admissions.prelim_legacy_fee f WHERE f.application_id = x.application_id AND f.state = 'REQUIRES_REVIEW')),
        'migrated', (SELECT count(*) FROM x WHERE x.migrated),
        'byTarget', coalesce((SELECT jsonb_agg(jsonb_build_object('targetId', q.id, 'programmeCode', q.code, 'name', q.name, 'group', q.group_name, 'n', q.n) ORDER BY q.n DESC, q.name)
                                FROM (SELECT t.id, t.programme_code AS code, coalesce(p.name, t.requested_name) AS name, t.group_name, count(*) AS n
                                        FROM x JOIN admissions.prelim_target t ON t.id = x.target_id LEFT JOIN ref.programme p ON p.code = t.programme_code
                                       WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY t.id, t.programme_code, p.name, t.requested_name, t.group_name) q), '[]'::jsonb),
        'byGroup', coalesce((SELECT jsonb_agg(jsonb_build_object('group', q.group_name, 'n', q.n) ORDER BY q.n DESC, q.group_name)
                               FROM (SELECT t.group_name, count(*) AS n FROM x JOIN admissions.prelim_target t ON t.id = x.target_id
                                      WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY t.group_name) q), '[]'::jsonb),
        'bySpecialisation', coalesce((SELECT jsonb_agg(jsonb_build_object('name', q.name, 'n', q.n) ORDER BY q.n DESC, q.name)
                                        FROM (SELECT sp.name, count(*) AS n FROM x JOIN admissions.prelim_specialisation sp ON sp.id = x.specialisation_id
                                               WHERE x.submitted_at IS NOT NULL AND x.state <> 'WITHDRAWN' GROUP BY sp.name) q), '[]'::jsonb),
        'bySittings', coalesce((SELECT jsonb_agg(jsonb_build_object('sittings', s.sittings, 'n', s.n) ORDER BY s.sittings)
                                  FROM (SELECT coalesce(sittings, 0) AS sittings, count(*) AS n FROM x WHERE submitted_at IS NOT NULL AND state <> 'WITHDRAWN' GROUP BY 1) s), '[]'::jsonb))
$fn$;

-- ── 10 · the ICT password desk finds a migrated applicant by the old number ───────────────────────────────────────────────
/* the applicant password desk's finder (V687, V706's), restated: a preliminary applicant brought from the old portal is found by the old
   portal's application number too, whatever its case — the number they sign in with and Forgot password knows (as the postgraduate desk
   finds by pg_legacy_application, V710) — and the row carries that number (legacy_application_no, last, so the columns before it stay) */
DROP FUNCTION admissions.applicant_password_find(text, integer);
CREATE FUNCTION admissions.applicant_password_find(p_q text, p_limit integer DEFAULT 50)
RETURNS TABLE (account_id uuid, session text, jamb_key text, application_no text, surname text, other_names text, email text, phone text,
               failed_attempts integer, locked boolean, must_change boolean, temp_expires_at timestamptz, last_signed_in_at timestamptz,
               created_at timestamptz, last_reset_at timestamptz, last_reset_method text, resets bigint, on_default boolean, default_number text,
               legacy_application_no text)
LANGUAGE sql STABLE AS $fn$
    WITH q AS (SELECT btrim(coalesce(p_q, '')) AS raw, upper(btrim(coalesce(p_q, ''))) AS up,
                      CASE WHEN regexp_replace(coalesce(p_q, ''), '[^0-9+]', '', 'g') ~ '^\+?234[0-9]{10}$'
                           THEN '0' || right(regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g'), 10)
                           ELSE regexp_replace(coalesce(p_q, ''), '[^0-9]', '', 'g') END AS digits)
    SELECT a.id, a.session, a.jamb_key, p.application_no, c.surname, c.other_names, a.email, a.phone,
           a.failed_attempts, coalesce(a.locked_until > now(), false), a.must_change_password, a.temp_expires_at, a.last_signed_in_at, a.created_at,
           (SELECT max(r.reset_at) FROM admissions.applicant_password_reset r WHERE r.account_id = a.id),
           (SELECT r.method FROM admissions.applicant_password_reset r WHERE r.account_id = a.id ORDER BY r.reset_at DESC LIMIT 1),
           (SELECT count(*) FROM admissions.applicant_password_reset r WHERE r.account_id = a.id),
           a.password_hash = 'SET_ON_FIRST_LOGIN',
           coalesce(nullif(btrim(a.jamb_key), ''), p.application_no),
           lg.legacy_application_no
      FROM admissions.applicant_account a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.application p ON p.account_id = a.id
      LEFT JOIN admissions.prelim_legacy_application lg ON lg.application_id = p.id
      CROSS JOIN q
     WHERE length(q.raw) >= 3
       AND (a.jamb_key = q.up OR p.application_no = q.up OR upper(btrim(lg.legacy_application_no)) = q.up OR lower(a.email) = lower(q.raw)
            OR (length(q.digits) = 11 AND a.phone = q.digits)
            OR (q.raw ~ '[A-Za-z]' AND q.raw !~ '@' AND (c.surname || ' ' || c.other_names) ILIKE '%' || q.raw || '%')
            OR (q.raw ~ '[A-Za-z]' AND q.raw !~ '@' AND (c.other_names || ' ' || c.surname) ILIKE '%' || q.raw || '%'))
     ORDER BY a.session DESC, c.surname, c.other_names
     LIMIT greatest(least(coalesce(p_limit, 50), 200), 1)
$fn$;
COMMENT ON FUNCTION admissions.applicant_password_find(text, integer) IS
  'V687, V706, V745: applicant accounts for the password desk — by JAMB number, application number, the old portal''s application number of a preliminary applicant brought across (any case), email, phone (0… or +234…) or a name (three characters or more); on_default when the account is on its first password, default_number that number; legacy_application_no the old portal''s number.';


-- ── 11 · the other way round: no postgraduate or JUPEB old number a migrated preliminary applicant signs in with ────────────────
/* V745 (finding 10, the other way round): the preliminary check holds back an old number a postgraduate applicant (V709) or a JUPEB
   application (V718) already signs in with; an old number a migrated preliminary applicant signs in with is likewise never brought in
   afterwards as a postgraduate applicant's old number, nor as a JUPEB application's number or old reference. The sign-in tries the
   postgraduate and JUPEB doors before the preliminary one, so the preliminary applicant would be locked out of their own account (one
   identifier never opens two accounts). The postgraduate import records such a row FAILED with this reason and goes on with the others;
   the JUPEB upload is refused, naming the number. */
CREATE OR REPLACE FUNCTION admissions.prelim_legacy_number_holder(p_no text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(ap.application_no, 'an application')
      FROM admissions.prelim_legacy_application l LEFT JOIN admissions.application ap ON ap.id = l.application_id
     WHERE upper(btrim(l.legacy_application_no)) = upper(btrim(p_no))
$$;
COMMENT ON FUNCTION admissions.prelim_legacy_number_holder(text) IS
  'V745: the application number of the migrated preliminary applicant whose old portal number this is (any case, spaces trimmed), else NULL — an old number another import may not bring in again.';

CREATE OR REPLACE FUNCTION admissions.trg_pg_legacy_not_prelim() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_holder text;
BEGIN
    IF TG_OP = 'UPDATE' AND upper(btrim(NEW.legacy_application_no)) IS NOT DISTINCT FROM upper(btrim(OLD.legacy_application_no)) THEN RETURN NEW; END IF;
    v_holder := admissions.prelim_legacy_number_holder(NEW.legacy_application_no);
    IF v_holder IS NOT NULL THEN
        RAISE EXCEPTION 'LEGACY_NO_IS_PORTAL_NUMBER: old application number % is the old portal number a preliminary applicant (%) signs in with; one number never opens two accounts',
              NEW.legacy_application_no, v_holder USING ERRCODE = '23505';
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION admissions.trg_pg_legacy_not_prelim() IS
  'V745: refuses a postgraduate old application number that a migrated preliminary applicant already signs in with (admissions.prelim_legacy_number_holder).';
CREATE TRIGGER trg_pg_legacy_not_prelim BEFORE INSERT OR UPDATE OF legacy_application_no ON admissions.pg_legacy_application
    FOR EACH ROW EXECUTE FUNCTION admissions.trg_pg_legacy_not_prelim();

CREATE OR REPLACE FUNCTION jupeb.trg_application_not_prelim() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_no text; v_holder text;
BEGIN
    FOREACH v_no IN ARRAY ARRAY[NEW.application_no, NEW.legacy_ref] LOOP
        CONTINUE WHEN v_no IS NULL;
        CONTINUE WHEN TG_OP = 'UPDATE' AND upper(btrim(v_no)) IN (upper(btrim(coalesce(OLD.application_no, ''))), upper(btrim(coalesce(OLD.legacy_ref, ''))));
        v_holder := admissions.prelim_legacy_number_holder(v_no);
        IF v_holder IS NOT NULL THEN
            RAISE EXCEPTION 'LEGACY_NO_IS_PORTAL_NUMBER: % is the old portal number a preliminary applicant (%) signs in with; one number never opens two accounts — leave the row out of the upload',
                  v_no, v_holder USING ERRCODE = '23505';
        END IF;
    END LOOP;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION jupeb.trg_application_not_prelim() IS
  'V745: refuses a JUPEB application number or old reference that a migrated preliminary applicant already signs in with (admissions.prelim_legacy_number_holder).';
CREATE TRIGGER trg_application_not_prelim BEFORE INSERT OR UPDATE OF application_no, legacy_ref ON jupeb.application
    FOR EACH ROW EXECUTE FUNCTION jupeb.trg_application_not_prelim();

COMMIT;

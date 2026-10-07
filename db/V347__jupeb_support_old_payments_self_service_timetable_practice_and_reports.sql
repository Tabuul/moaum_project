-- ═══════════════════════════════════════════════════════════════════════════
-- V347 — JUPEB: ICT Support reaches JUPEB records, the old portal's payments are put on the record, the student keeps their own
--        contact details and asks for corrections, a timetable and practice tests for the subjects, and the office's reports
--
--   · ICT Support for JUPEB records (V346's tools, extended): an agent reaches JUPEB records through a live posting on the
--     JUPEB Support queue, a University-wide posting, or a posting on the JUPEB Office; what they may do is what those postings
--     carry. Every act is on the support ledger (helpdesk.support_action now names a student OR a JUPEB application) and on the
--     JUPEB ticket's timeline. A temporary JUPEB password is random, hashed, good for one sign-in within 24 hours, and changed at it.
--   · The old portal's payments: the JUPEB Office uploads the old portal's payment export. Each row is judged (matched by the
--     old App No or the application number — never by name; a failed or pending payment, an unknown purpose, a reference seen
--     before or a fee already paid is listed, never posted). A posted row becomes a CONFIRMED JUPEB fee reference on the
--     old portal's channel, so the school fee position, the receipts and the reminders read it like any other payment; the
--     old reference is kept, and the same file again posts nothing twice. Fee reminders reach an old-portal student once their
--     old payments are on the record.
--   · The student keeps their own contact details (phone, addresses, guardian, next of kin) after submission; a change of
--     name, sex, date of birth, NIN, nationality, state or LGA is a request (CORRECT_DETAILS) the JUPEB Office decides.
--   · A weekly timetable per session, semester, class and subject; practice tests per subject — questions the office uploads,
--     drawn at random, timed, scored by the server; the answer key is never sent before the attempt is submitted. Practice
--     scores never touch a result.
--   · jupeb.report(session): enrolment, fees, attendance and results, for the office's reports.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V347: JUPEB support, old payments, self-service, timetable, practice, reports', true);

-- ── 1 · the support ledger names a student or a JUPEB application ─────────────────────────────────────────────────
ALTER TABLE helpdesk.support_action ALTER COLUMN student_id DROP NOT NULL;
ALTER TABLE helpdesk.support_action ADD COLUMN jupeb_application_id uuid NULL REFERENCES jupeb.application(id);
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_subject CHECK (num_nonnulls(student_id, jupeb_application_id) = 1);
CREATE INDEX IF NOT EXISTS ix_hd_sa_jupeb ON helpdesk.support_action (jupeb_application_id, at DESC) WHERE jupeb_application_id IS NOT NULL;
COMMENT ON COLUMN helpdesk.support_action.jupeb_application_id IS 'V347: the JUPEB application the support act was done on (student_id is then empty)';

-- the postings that reach JUPEB records: the JUPEB Support queue, a University-wide scope, or the JUPEB Office
CREATE OR REPLACE FUNCTION helpdesk.agent_reaches_jupeb(p_person uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM helpdesk.agent_assignment a
                    WHERE a.person_id = p_person AND a.active
                      AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                      AND (a.queue_code = 'JUPEB_SUPPORT' OR a.scope_kind = 'GLOBAL' OR (a.scope_kind = 'OFFICE' AND lower(a.scope_ref) = 'jupeb')))
$$;

CREATE OR REPLACE FUNCTION helpdesk.agent_jupeb_capabilities(p_person uuid)
RETURNS text[]
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT array_agg(DISTINCT c ORDER BY c)
                       FROM helpdesk.agent_assignment a CROSS JOIN LATERAL unnest(a.capabilities) AS c
                      WHERE a.person_id = p_person AND a.active
                        AND a.effective_from <= current_date AND (a.effective_to IS NULL OR a.effective_to >= current_date)
                        AND (a.queue_code = 'JUPEB_SUPPORT' OR a.scope_kind = 'GLOBAL' OR (a.scope_kind = 'OFFICE' AND lower(a.scope_ref) = 'jupeb'))), '{}'::text[])
$$;
COMMENT ON FUNCTION helpdesk.agent_jupeb_capabilities(uuid) IS 'V347: what an agent may do on JUPEB records — the capabilities of the live postings that reach them (the JUPEB Support queue, a University-wide posting, the JUPEB Office).';

CREATE OR REPLACE FUNCTION helpdesk.record_jupeb_support_action(p_app uuid, p_ticket uuid, p_action text, p_field text, p_old text, p_new text, p_reason text,
                                                                p_detail jsonb DEFAULT '{}'::jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        d jsonb := coalesce(p_detail, '{}'::jsonb); v uuid; v_summary text; v_words text; v_ip inet;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a support act is made by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'SUPPORT_REASON: a support act on a record says why' USING ERRCODE = '23514', HINT = 'Name the ticket, or what the student reported.';
    END IF;
    IF p_ticket IS NOT NULL AND NOT EXISTS (SELECT 1 FROM helpdesk.ticket t WHERE t.id = p_ticket AND t.requester_kind = 'JUPEB' AND t.requester_id = p_app) THEN
        RAISE EXCEPTION 'SUPPORT_TICKET: that ticket is not this JUPEB candidate''s' USING ERRCODE = '23514';
    END IF;
    BEGIN
        v_ip := nullif(current_setting('moaum.source_ip', true), '')::inet;
    EXCEPTION WHEN others THEN v_ip := NULL;
    END;
    v_summary := nullif(btrim(d->>'summary'), '');
    INSERT INTO helpdesk.support_action (student_id, jupeb_application_id, agent_id, agent_office, ticket_id, action, field, old_value, new_value, reason,
                                         summary, outcome, before_state, after_state, method, auth_event_id, payment_reference, source_ip)
    VALUES (NULL, p_app, who, coalesce(office, 'ictagent'), p_ticket, p_action, p_field, p_old, p_new, btrim(p_reason),
            v_summary, coalesce(d->>'outcome', 'COMPLETED'), d->'before', d->'after', d->>'method', nullif(d->>'authEventId', '')::uuid,
            nullif(d->>'paymentReference', ''), v_ip)
    RETURNING id INTO v;
    IF p_ticket IS NOT NULL THEN
        v_words := coalesce('Action taken: ' || v_summary || E'\n', '') || 'Reason: ' || btrim(p_reason);
        INSERT INTO helpdesk.ticket_event (ticket_id, actor_kind, actor_id, actor_name, action, from_value, to_value, detail)
        VALUES (p_ticket, 'AGENT', who, helpdesk.person_name(who), 'SUPPORT_' || p_action, left(p_old, 200), left(p_new, 200), left(v_words, 2000));
        UPDATE helpdesk.ticket SET updated_at = now() WHERE id = p_ticket;
    END IF;
    RETURN v;
END $$;
COMMENT ON FUNCTION helpdesk.record_jupeb_support_action(uuid, uuid, text, text, text, text, text, jsonb) IS 'V347: a support act on a JUPEB record, on the ledger with its reason and on the JUPEB ticket''s timeline; the same ledger as a student''s (V346).';

-- the temporary JUPEB password: random, hashed, 24 hours, one sign-in, changed at it
ALTER TABLE jupeb.account
    ADD COLUMN temp_expires_at timestamptz NULL,
    ADD COLUMN temp_issued_by  uuid        NULL,
    ADD COLUMN temp_used_at    timestamptz NULL;
ALTER TABLE jupeb.account ADD CONSTRAINT ck_jupeb_account_temp CHECK (
    (temp_expires_at IS NULL) = (temp_issued_by IS NULL)
    AND (temp_expires_at IS NULL OR must_change_password)
    AND (temp_used_at IS NULL OR temp_expires_at IS NOT NULL));
COMMENT ON COLUMN jupeb.account.temp_expires_at IS 'V347: the hash is a temporary password ICT Support issued at the desk — good until this time and for one sign-in (temp_used_at), changed at it';

-- ── 2 · the old portal's payments ────────────────────────────────────────────────────────────────────────────────
ALTER TABLE jupeb.import_batch DROP CONSTRAINT IF EXISTS import_batch_kind_check;
ALTER TABLE jupeb.import_batch ADD CONSTRAINT import_batch_kind_check CHECK (kind IN ('EXAM_NUMBERS', 'RESULTS', 'COMBINATIONS', 'OLD_PORTAL_STUDENTS', 'OLD_PORTAL_PAYMENTS'));

CREATE OR REPLACE FUNCTION jupeb.batch_ref(p_kind text)
RETURNS text
LANGUAGE sql AS $$
    SELECT 'JUPEB-' || CASE p_kind WHEN 'EXAM_NUMBERS' THEN 'EXAMNO' WHEN 'RESULTS' THEN 'RESULT' WHEN 'OLD_PORTAL_STUDENTS' THEN 'OLDPORTAL'
                                   WHEN 'OLD_PORTAL_PAYMENTS' THEN 'OLDPAY' ELSE 'COMB' END || '-'
           || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('JUPEB_' || p_kind, 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0')
$$;

CREATE TABLE jupeb.legacy_payment (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_ref        text NOT NULL,
    row_no           int NULL,
    old_reference    text NOT NULL,
    app_no           text NOT NULL,
    application_id   uuid NOT NULL REFERENCES jupeb.application(id),
    kind             text NOT NULL,
    purpose          text NULL,
    amount           numeric(12,2) NOT NULL CHECK (amount > 0),
    paid_on          date NOT NULL,
    fee_reference_id uuid NOT NULL REFERENCES jupeb.fee_reference(id),
    raw              jsonb NULL,
    imported_by      uuid NOT NULL,
    imported_at      timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_jupeb_legacy_payment_ref ON jupeb.legacy_payment (upper(old_reference));
CREATE INDEX ix_jupeb_legacy_payment_app ON jupeb.legacy_payment (application_id);
COMMENT ON TABLE jupeb.legacy_payment IS 'V347: a payment made on the old JUPEB portal, put on the record as a confirmed fee reference (fee_reference_id) on the old portal''s channel; the old reference is kept and posts once.';
SELECT audit.attach('jupeb.legacy_payment');

-- the fee a line of the old portal's export was for, from its purpose
CREATE OR REPLACE FUNCTION jupeb.legacy_kind(p_purpose text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
             WHEN v ~ 'APPLICATION|FORM' THEN 'APPLICATION'
             WHEN v ~ 'CHECK' THEN 'STATUS_CHECKING'
             WHEN v ~ 'ACCEPT' THEN 'ACCEPTANCE'
             WHEN v ~ '(SCHOOL|TUITION|FEE)' AND v ~ '(FIRST|1ST|INSTAL+MENT 1|PART 1|\m1\M)' THEN 'SCHOOL_FIRST'
             WHEN v ~ '(SCHOOL|TUITION|FEE)' AND v ~ '(SECOND|2ND|BALANCE|INSTAL+MENT 2|PART 2|\m2\M)' THEN 'SCHOOL_SECOND'
             WHEN v ~ '(SCHOOL|TUITION)' AND v ~ '(FULL|COMPLETE|WHOLE|ONE.?OFF)' THEN 'SCHOOL_FULL'
             WHEN v ~ '(SCHOOL|TUITION)' THEN 'SCHOOL_ANY'
           END
      FROM (SELECT upper(btrim(coalesce(p_purpose, ''))) AS v) x
$$;

CREATE OR REPLACE FUNCTION jupeb.import_old_portal_payments(p_rows jsonb, p_dmy boolean, p_commit boolean, p_file text, p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE r jsonb; out_rows jsonb := '[]'::jsonb; n_valid int := 0; n_invalid int := 0; n_exists int := 0; n_review int := 0; n_applied int := 0;
        v_row int; v_app jupeb.application; v_appno text; v_ref text; v_purpose text; v_kind text; v_amount numeric; v_date date; v_status text;
        v_state text; v_reason text; v_seen text[] := '{}'; v_batch text; v_fee uuid; v_fee_ref text; v_amount_raw text; v_total numeric;
BEGIN
    IF p_commit THEN v_batch := jupeb.batch_ref('OLD_PORTAL_PAYMENTS'); END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_row := nullif(r->>'row', '')::int;
        v_appno := upper(btrim(coalesce(r->>'appNo', '')));
        v_ref := btrim(coalesce(r->>'reference', ''));
        v_purpose := btrim(coalesce(r->>'purpose', ''));
        v_status := upper(btrim(coalesce(r->>'status', '')));
        v_amount_raw := regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g');
        v_amount := CASE WHEN v_amount_raw ~ '^[0-9]+(\.[0-9]+)?$' THEN v_amount_raw::numeric END;
        BEGIN v_date := jupeb.legacy_date(r->>'date', p_dmy); EXCEPTION WHEN others THEN v_date := NULL; END;
        v_kind := coalesce(nullif(upper(btrim(coalesce(r->>'kind', ''))), ''), jupeb.legacy_kind(v_purpose || ' ' || coalesce(r->>'semester', '')));
        v_app := NULL;
        SELECT * INTO v_app FROM jupeb.application a
         WHERE (upper(a.application_no) = v_appno OR upper(a.legacy_ref) = v_appno) AND v_appno <> ''
         ORDER BY (upper(a.legacy_ref) = v_appno) DESC, a.created_at DESC LIMIT 1;
        -- "school fees" that names no instalment is the full fee only when it covers it; otherwise it is asked which
        v_total := NULL;
        IF v_kind = 'SCHOOL_ANY' AND v_app.id IS NOT NULL AND v_amount IS NOT NULL THEN
            SELECT sf.total INTO v_total FROM jupeb.school_fees(v_app.id) sf;
            IF v_total IS NOT NULL AND v_amount >= v_total THEN v_kind := 'SCHOOL_FULL'; END IF;
        END IF;
        v_state := 'VALID'; v_reason := NULL;
        IF v_appno = '' OR v_ref = '' THEN
            v_state := 'INVALID'; v_reason := 'The App No and the payment reference are required.';
        ELSIF v_status <> '' AND v_status !~ '(SUCCESS|PAID|APPROVED|COMPLETE|CONFIRM)' THEN
            v_state := 'INVALID'; v_reason := 'The old portal says the payment was not successful (' || lower(v_status) || '); only a successful payment is posted.';
        ELSIF v_amount IS NULL OR v_amount <= 0 THEN
            v_state := 'INVALID'; v_reason := 'The amount cannot be read.';
        ELSIF v_date IS NULL THEN
            v_state := 'INVALID'; v_reason := 'The payment date cannot be read.';
        ELSIF v_kind = 'SCHOOL_ANY' AND v_app.id IS NOT NULL THEN
            v_state := 'REVIEW'; v_reason := 'School fees of ' || v_amount::text || ' that do not say which instalment' || coalesce(' and are less than the full fee of ' || v_total::text, '')
                                            || '; write first or second instalment in the Purpose (or Semester) column.';
        ELSIF v_kind IS NULL OR v_kind NOT IN ('APPLICATION', 'STATUS_CHECKING', 'ACCEPTANCE', 'SCHOOL_FIRST', 'SCHOOL_SECOND', 'SCHOOL_FULL', 'SCHOOL_ANY') THEN
            v_state := 'REVIEW'; v_reason := 'What the payment was for cannot be read from "' || v_purpose || '"; correct the purpose (application, acceptance, school fees first or second instalment).';
        ELSIF v_app.id IS NULL THEN
            v_state := 'UNMATCHED'; v_reason := 'No JUPEB student carries App No ' || v_appno || ' (students are matched by the App No only, never by name).';
        ELSIF upper(v_ref) = ANY (v_seen) THEN
            v_state := 'DUPLICATE'; v_reason := 'The same reference appears earlier in the file.';
        ELSIF EXISTS (SELECT 1 FROM jupeb.legacy_payment l WHERE upper(l.old_reference) = upper(v_ref)) THEN
            v_state := 'EXISTS'; v_reason := 'This payment is already on the record.';
        ELSIF EXISTS (SELECT 1 FROM jupeb.fee_reference f WHERE f.application_id = v_app.id AND f.confirmed_at IS NOT NULL
                        AND (f.kind = v_kind OR (v_kind LIKE 'SCHOOL_%' AND f.kind = 'SCHOOL_FULL') OR (v_kind = 'SCHOOL_FULL' AND f.kind LIKE 'SCHOOL_%'))) THEN
            v_state := 'EXISTS'; v_reason := 'This fee already stands paid on the portal; nothing is posted twice.';
        END IF;
        v_seen := v_seen || upper(v_ref);
        IF v_state = 'VALID' THEN n_valid := n_valid + 1; ELSIF v_state = 'REVIEW' THEN n_review := n_review + 1;
        ELSIF v_state IN ('EXISTS', 'DUPLICATE') THEN n_exists := n_exists + 1; ELSE n_invalid := n_invalid + 1; END IF;
        IF p_commit AND v_state = 'VALID' THEN
            v_fee_ref := 'JUPEB-OLD-' || left(upper(regexp_replace(v_ref, '[^A-Za-z0-9]', '', 'g')), 40);
            IF EXISTS (SELECT 1 FROM jupeb.fee_reference f WHERE f.reference = v_fee_ref) THEN
                v_fee_ref := v_fee_ref || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
            END IF;
            INSERT INTO jupeb.fee_reference (application_id, kind, reference, amount, session, semester, expires_at, confirmed_at, channel)
            VALUES (v_app.id, v_kind, v_fee_ref, v_amount, v_app.session, CASE v_kind WHEN 'SCHOOL_FIRST' THEN 1 WHEN 'SCHOOL_SECOND' THEN 2 END,
                    v_date::timestamptz, v_date::timestamptz, 'Old portal')
            RETURNING id INTO v_fee;
            INSERT INTO jupeb.legacy_payment (batch_ref, row_no, old_reference, app_no, application_id, kind, purpose, amount, paid_on, fee_reference_id, raw, imported_by)
            VALUES (v_batch, v_row, v_ref, v_appno, v_app.id, v_kind, nullif(v_purpose, ''), v_amount, v_date, v_fee, r, p_actor);
            PERFORM jupeb.app_event(v_app.id, 'LEGACY_PAYMENT', 'Old-portal payment ' || v_ref || ' (' || lower(replace(v_kind, '_', ' ')) || ', ' || v_amount::text || ') put on the record');
            n_applied := n_applied + 1;
        END IF;
        out_rows := out_rows || jsonb_build_array(jsonb_build_object('row', v_row, 'appNo', v_appno, 'reference', v_ref, 'kind', v_kind, 'amount', v_amount,
                     'date', v_date, 'status', v_state, 'reason', v_reason, 'applicationId', v_app.id,
                     'name', CASE WHEN v_app.id IS NOT NULL THEN v_app.surname || ', ' || v_app.first_name END));
    END LOOP;
    IF p_commit THEN
        INSERT INTO jupeb.import_batch (ref, kind, file_name, rows, applied, result, imported_by, imported_office)
        VALUES (v_batch, 'OLD_PORTAL_PAYMENTS', p_file, jsonb_array_length(coalesce(p_rows, '[]'::jsonb)), n_applied,
                jsonb_build_object('valid', n_valid, 'review', n_review, 'exists', n_exists, 'invalid', n_invalid), p_actor,
                nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN jsonb_build_object('rows', out_rows, 'valid', n_valid, 'review', n_review, 'exists', n_exists, 'invalid', n_invalid,
                              'committed', p_commit, 'ref', v_batch, 'applied', n_applied);
END $$;
COMMENT ON FUNCTION jupeb.import_old_portal_payments(jsonb, boolean, boolean, text, uuid) IS 'V347: the old portal''s JUPEB payments, judged row by row (a preview writes nothing) and, on the upload, posted as confirmed fee references on the old portal''s channel — matched by App No only; failed, unreadable, unknown-purpose, repeated and already-paid rows are listed and never posted.';

-- an old-portal student is spared fee reminders only while their old payments are not on the record
CREATE OR REPLACE FUNCTION jupeb.reminder_exempt(p_app uuid, p_kind text)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_kind IN ('FEE_UNPAID', 'SUBMIT_PENDING', 'CHECKING_OPEN', 'ACCEPTANCE_UNPAID', 'SCHOOL_FEE_UNPAID')
       AND EXISTS (SELECT 1 FROM jupeb.application a WHERE a.id = p_app AND a.legacy_source IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM jupeb.legacy_payment l WHERE l.application_id = p_app)
$$;

-- the second instalment of a school fee is the balance owing: an old-portal instalment of another amount leaves no balance unpayable
CREATE OR REPLACE FUNCTION jupeb.new_fee_reference(p_app uuid, p_kind text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; fs jupeb.fee_setting; st jupeb.setting; sf record; ck record; v_amt numeric; v_ref text; v_sem int;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such JUPEB application' USING ERRCODE = '23503'; END IF;
    fs := jupeb.fee_setting_of(a.session);
    IF p_kind = 'APPLICATION' THEN
        IF a.fee_confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the application fee is already paid' USING ERRCODE = '23514'; END IF;
        v_amt := fs.application_fee;
    ELSIF p_kind = 'STATUS_CHECKING' THEN
        SELECT * INTO ck FROM jupeb.status_checking(p_app);
        IF ck.paid THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the status checking fee is already paid; check your status' USING ERRCODE = '23514'; END IF;
        IF NOT ck.valid THEN RAISE EXCEPTION 'JUPEB_CHECKING_NOT_VALID: status checking is for a submitted application' USING ERRCODE = '23514',
            HINT = 'Complete and submit your application first.'; END IF;
        IF NOT ck.window_open THEN RAISE EXCEPTION 'JUPEB_CHECKING_CLOSED: admission status checking is %', lower(ck.window_state) USING ERRCODE = '23514',
            HINT = 'Watch the University''s website and this portal: the Directorate of ICT opens admission status checking.'; END IF;
        v_amt := fs.checking_fee;
    ELSIF p_kind = 'ACCEPTANCE' THEN
        SELECT * INTO ck FROM jupeb.status_checking(p_app);
        IF ck.accepted THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the acceptance fee is already paid' USING ERRCODE = '23514'; END IF;
        IF NOT ck.may_check OR coalesce(ck.status, '') <> 'ADMITTED' THEN
            RAISE EXCEPTION 'JUPEB_ACCEPTANCE_NOT_YET: the acceptance fee is paid once your admission status shows you admitted' USING ERRCODE = '23514',
                HINT = 'Check your admission status first.';
        END IF;
        v_amt := fs.acceptance_fee;
    ELSIF p_kind IN ('SCHOOL_FIRST', 'SCHOOL_SECOND', 'SCHOOL_FULL') THEN
        IF a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED') THEN
            RAISE EXCEPTION 'JUPEB_FEES_NOT_YET: school fees are paid once you are admitted' USING ERRCODE = '23514';
        END IF;
        IF a.state = 'ADMITTED' AND jupeb.paid_at(p_app, 'ACCEPTANCE') IS NULL THEN
            RAISE EXCEPTION 'JUPEB_ACCEPTANCE_FIRST: pay the acceptance fee first; school fees follow it' USING ERRCODE = '23514';
        END IF;
        st := jupeb.setting_of(a.session);
        IF st.screening_required AND coalesce(a.screening_state, '') <> 'CLEARED' AND a.state = 'ADMITTED' THEN
            RAISE EXCEPTION 'JUPEB_SCREENING_FIRST: school fees open once you are cleared at screening' USING ERRCODE = '23514',
                HINT = 'Attend the screening shown on your JUPEB portal.';
        END IF;
        -- the fee is frozen on the candidate the first time it is charged: a later change by the Bursary does not rewrite it
        IF a.school_fee_total IS NULL THEN
            SELECT * INTO sf FROM jupeb.school_fees(p_app);
            IF sf.total IS NULL THEN
                RAISE EXCEPTION 'JUPEB_FEE_NOT_SET: the Bursary has not stated the JUPEB school fee for %', a.session USING ERRCODE = '23514';
            END IF;
            UPDATE jupeb.application SET school_fee_total = sf.total, fee_category = sf.category, indigene = sf.indigene, first_percent = sf.first_percent
             WHERE id = p_app;
        END IF;
        SELECT * INTO sf FROM jupeb.school_fees(p_app);
        IF p_kind = 'SCHOOL_FIRST' THEN
            IF sf.first_paid THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the first semester''s share is already paid' USING ERRCODE = '23514'; END IF;
            v_amt := sf.first_amount; v_sem := 1;
        ELSIF p_kind = 'SCHOOL_SECOND' THEN
            IF NOT sf.first_paid THEN RAISE EXCEPTION 'JUPEB_FEE_ORDER: the first semester''s share is paid first' USING ERRCODE = '23514'; END IF;
            IF sf.second_paid THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the second semester''s share is already paid' USING ERRCODE = '23514'; END IF;
            -- V347: the second instalment is what the school fee leaves owing — the second share for a first share paid here; for an
            -- instalment paid on the old portal at another amount, the balance (never more than the Bursary's fee, never a balance left unpayable)
            IF sf.outstanding <= 0 THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the school fee is paid in full' USING ERRCODE = '23514'; END IF;
            v_amt := sf.outstanding; v_sem := 2;
        ELSE
            IF NOT sf.allow_full THEN RAISE EXCEPTION 'JUPEB_FULL_NOT_ALLOWED: the Bursary takes the school fee in two instalments' USING ERRCODE = '23514'; END IF;
            IF sf.paid > 0 THEN RAISE EXCEPTION 'JUPEB_FEE_ORDER: part of the fee is paid; pay the remaining instalment' USING ERRCODE = '23514'; END IF;
            v_amt := sf.total;
        END IF;
    ELSE
        RAISE EXCEPTION 'JUPEB_FEE_KIND: unknown JUPEB fee %', p_kind USING ERRCODE = '23514';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN RAISE EXCEPTION 'JUPEB_FEE_NOT_SET: the Bursary has not stated this fee' USING ERRCODE = '23514'; END IF;
    SELECT fr.reference INTO v_ref FROM jupeb.fee_reference fr
     WHERE fr.application_id = p_app AND fr.kind = p_kind AND fr.confirmed_at IS NULL AND fr.expires_at > now() AND fr.amount = v_amt
     ORDER BY fr.created_at DESC LIMIT 1;
    IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    v_ref := 'MOAUM-JUPEB' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'STATUS_CHECKING' THEN 'CHK' WHEN 'ACCEPTANCE' THEN 'ACC'
                                         WHEN 'SCHOOL_FIRST' THEN 'SF1' WHEN 'SCHOOL_SECOND' THEN 'SF2' ELSE 'SFF' END
             /* V342: the session's year is in the reference — the count restarts each session, and V339's references
                (MOAUM-JUPEBAPP-000001) would otherwise collide with the next session's */
             || '-' || substr(a.session, 1, 4) || '-' || lpad(platform.next_number('JUPEB_FEEREF', 'UNIVERSITY', a.session)::text, 6, '0');
    INSERT INTO jupeb.fee_reference (application_id, kind, reference, amount, session, semester, expires_at)
    VALUES (p_app, p_kind, v_ref, v_amt, a.session, v_sem, now() + interval '24 hours');
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION jupeb.new_fee_reference(uuid, text) IS 'V339, V342, V347: a JUPEB fee reference for the candidate, its amount the server''s — the Bursary''s fee, the school fee frozen when first charged, the second instalment the balance it leaves owing.';

-- ── 3 · corrections of identity details: a request the JUPEB Office decides ──────────────────────────────────────
ALTER TABLE jupeb.change_request ADD COLUMN details jsonb NULL;
ALTER TABLE jupeb.change_request DROP CONSTRAINT IF EXISTS change_request_kind_check;
ALTER TABLE jupeb.change_request ADD CONSTRAINT change_request_kind_check CHECK (kind IN ('WITHDRAW', 'DEFER', 'CHANGE_COMBINATION', 'CHANGE_PROGRAMME', 'CORRECT_DETAILS'));
ALTER TABLE jupeb.change_request ADD CONSTRAINT ck_jupeb_change_details CHECK ((kind = 'CORRECT_DETAILS') = (details IS NOT NULL));
COMMENT ON COLUMN jupeb.change_request.details IS 'V347: for CORRECT_DETAILS, each field asked to change with its present and its corrected value: {"surname": {"from": "…", "to": "…"}, …}';

CREATE OR REPLACE FUNCTION jupeb.correction_fields()
RETURNS text[]
LANGUAGE sql IMMUTABLE AS $$
    SELECT ARRAY['surname', 'first_name', 'middle_name', 'sex', 'date_of_birth', 'nin', 'nationality', 'state_of_origin', 'lga']
$$;

CREATE OR REPLACE FUNCTION jupeb.field_word(p_field text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_field WHEN 'surname' THEN 'surname' WHEN 'first_name' THEN 'first name' WHEN 'middle_name' THEN 'middle name' WHEN 'sex' THEN 'sex'
                        WHEN 'date_of_birth' THEN 'date of birth' WHEN 'nin' THEN 'NIN' WHEN 'nationality' THEN 'nationality'
                        WHEN 'state_of_origin' THEN 'state of origin' WHEN 'lga' THEN 'LGA' ELSE p_field END
$$;

CREATE OR REPLACE FUNCTION jupeb.change_check(p_app uuid, p_kind text, p_stream text, p_combination uuid, p_to_session text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; c jupeb.combination; v_stream text;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'JUPEB_NOT_FOUND: no such application' USING ERRCODE = '23514'; END IF;
    IF a.state IN ('DRAFT', 'RETURNED') THEN
        RAISE EXCEPTION 'JUPEB_CHANGE_EDIT_YOURSELF: an application not yet submitted is changed on the application itself' USING ERRCODE = '23514';
    END IF;
    -- V347: a correction of the candidate's details is asked at any point after submission, a completed record included
    IF p_kind = 'CORRECT_DETAILS' THEN
        IF a.state = 'WITHDRAWN' THEN RAISE EXCEPTION 'JUPEB_CHANGE_CLOSED: a withdrawn application takes no change request' USING ERRCODE = '23514'; END IF;
        RETURN;
    END IF;
    IF a.state IN ('COMPLETED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'JUPEB_CHANGE_CLOSED: a % application takes no change request', lower(a.state) USING ERRCODE = '23514';
    END IF;
    IF p_kind = 'WITHDRAW' THEN
        RETURN;
    ELSIF p_kind = 'DEFER' THEN
        IF a.state <> 'ADMITTED' THEN
            RAISE EXCEPTION 'JUPEB_DEFER_STATE: only an admission not yet activated is deferred' USING ERRCODE = '23514';
        END IF;
        IF jupeb.paid_at(p_app, 'ACCEPTANCE') IS NULL THEN
            RAISE EXCEPTION 'JUPEB_DEFER_ACCEPT_FIRST: accept the admission (pay the acceptance fee) before asking to defer it' USING ERRCODE = '23514';
        END IF;
        IF p_to_session IS NULL OR p_to_session !~ '^[0-9]{4}/[0-9]{4}$' OR p_to_session <= a.session
           OR substr(p_to_session, 1, 4)::int > substr(a.session, 1, 4)::int + 2 THEN
            RAISE EXCEPTION 'JUPEB_DEFER_SESSION: an admission is deferred to one of the next two sessions' USING ERRCODE = '23514';
        END IF;
    ELSIF p_kind = 'CHANGE_COMBINATION' THEN
        IF a.state NOT IN ('SUBMITTED', 'ELIGIBLE', 'PENDING', 'ADMITTED', 'STUDENT', 'DEFERRED') THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_STATE: the combination is not changed on a % application', lower(a.state) USING ERRCODE = '23514';
        END IF;
        IF a.exam_no IS NOT NULL OR EXISTS (SELECT 1 FROM jupeb.result r WHERE r.application_id = p_app) THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_EXAM_NO: the Board already holds this candidate''s subjects (an examination number or a result)' USING ERRCODE = '23514';
        END IF;
        SELECT * INTO c FROM jupeb.combination WHERE id = p_combination;
        IF c.id IS NULL OR NOT jupeb.combination_offered(c.id) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION: choose one of the subject combinations the University offers' USING ERRCODE = '23514';
        END IF;
        IF NOT jupeb.combination_suits(c.area, a.stream) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION_STREAM: % is not a % combination', c.code, CASE a.stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END USING ERRCODE = '23514';
        END IF;
        IF c.id = a.combination_id THEN RAISE EXCEPTION 'JUPEB_CHANGE_SAME: that is already the combination' USING ERRCODE = '23514'; END IF;
    ELSIF p_kind = 'CHANGE_PROGRAMME' THEN
        IF a.state NOT IN ('SUBMITTED', 'ELIGIBLE', 'PENDING', 'ADMITTED', 'DEFERRED') THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_STATE: the programme is not changed on a % application', lower(a.state) USING ERRCODE = '23514';
        END IF;
        IF a.school_fee_total IS NOT NULL THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_FEES_CHARGED: a school fee is already charged at this programme''s rate' USING ERRCODE = '23514';
        END IF;
        v_stream := CASE upper(regexp_replace(btrim(coalesce(p_stream, '')), '[- ]', '_', 'g')) WHEN 'SCIENCE' THEN 'SCIENCE' WHEN 'NON_SCIENCE' THEN 'NON_SCIENCE' WHEN 'ARTS' THEN 'NON_SCIENCE' END;
        IF v_stream IS NULL THEN RAISE EXCEPTION 'JUPEB_STREAM: choose Science or Non-Science' USING ERRCODE = '23514'; END IF;
        IF v_stream = a.stream THEN RAISE EXCEPTION 'JUPEB_CHANGE_SAME: that is already the programme' USING ERRCODE = '23514'; END IF;
        IF p_combination IS NOT NULL THEN
            SELECT * INTO c FROM jupeb.combination WHERE id = p_combination;
            IF c.id IS NULL OR NOT jupeb.combination_offered(c.id) THEN
                RAISE EXCEPTION 'JUPEB_COMBINATION: choose one of the subject combinations the University offers' USING ERRCODE = '23514';
            END IF;
            IF NOT jupeb.combination_suits(c.area, v_stream) THEN
                RAISE EXCEPTION 'JUPEB_COMBINATION_STREAM: % is not a % combination', c.code, CASE v_stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END USING ERRCODE = '23514';
            END IF;
        ELSIF EXISTS (SELECT 1 FROM jupeb.combination o WHERE jupeb.combination_offered(o.id) AND jupeb.combination_suits(o.area, v_stream)) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION_CHOOSE: choose the subject combination of the new programme' USING ERRCODE = '23514';
        END IF;
    ELSE
        RAISE EXCEPTION 'JUPEB_CHANGE_KIND: withdraw, defer, change the combination or the programme, or correct your details' USING ERRCODE = '23514';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION jupeb.change_words(p_req uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE r.kind
        WHEN 'WITHDRAW' THEN 'withdraw the application'
        WHEN 'DEFER' THEN 'defer the admission from ' || r.from_session || ' to ' || r.to_session
        WHEN 'CHANGE_COMBINATION' THEN 'change the combination from ' || coalesce(fc.code, 'none') || ' to ' || coalesce(tc.code, '?')
        WHEN 'CHANGE_PROGRAMME' THEN 'change the programme from ' || CASE r.from_stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END
                                     || ' to ' || CASE r.to_stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END || coalesce(' (' || tc.code || ')', '')
        WHEN 'CORRECT_DETAILS' THEN 'correct ' || (SELECT string_agg(jupeb.field_word(e.key) || ' from "' || coalesce(e.value->>'from', '—') || '" to "' || coalesce(e.value->>'to', '') || '"', '; ' ORDER BY e.key)
                                                     FROM jsonb_each(r.details) e) END
      FROM jupeb.change_request r LEFT JOIN jupeb.combination fc ON fc.id = r.from_combination LEFT JOIN jupeb.combination tc ON tc.id = r.to_combination
     WHERE r.id = p_req
$$;

CREATE OR REPLACE FUNCTION jupeb.request_correction(p_app uuid, p_changes jsonb, p_reason text, p_actor uuid, p_office text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; e record; v_to text; v_from text; v_details jsonb := '{}'::jsonb; v_id uuid;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'JUPEB_CHANGE_REASON: give the reason for the request (at least ten characters)' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM jupeb.change_request r WHERE r.application_id = p_app AND r.state = 'PENDING') THEN
        RAISE EXCEPTION 'JUPEB_CHANGE_PENDING: a request is already with the JUPEB Office; cancel it or wait for its decision' USING ERRCODE = '23514';
    END IF;
    PERFORM jupeb.change_check(p_app, 'CORRECT_DETAILS', NULL, NULL, NULL);
    FOR e IN SELECT * FROM jsonb_each_text(coalesce(p_changes, '{}'::jsonb)) LOOP
        IF NOT e.key = ANY (jupeb.correction_fields()) THEN
            RAISE EXCEPTION 'JUPEB_CORRECTION_FIELD: % is not corrected this way', e.key USING ERRCODE = '23514';
        END IF;
        v_to := nullif(btrim(coalesce(e.value, '')), '');
        IF v_to IS NULL AND e.key <> 'middle_name' THEN
            RAISE EXCEPTION 'JUPEB_CORRECTION_VALUE: say what the % should read', jupeb.field_word(e.key) USING ERRCODE = '23514';
        END IF;
        IF e.key = 'sex' AND v_to NOT IN ('F', 'M') THEN RAISE EXCEPTION 'JUPEB_CORRECTION_VALUE: sex is F or M' USING ERRCODE = '23514'; END IF;
        IF e.key = 'nin' AND v_to !~ '^[0-9]{11}$' THEN RAISE EXCEPTION 'JUPEB_CORRECTION_VALUE: a NIN is eleven digits' USING ERRCODE = '23514'; END IF;
        IF e.key = 'date_of_birth' THEN
            IF v_to !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'JUPEB_CORRECTION_VALUE: a date of birth is YYYY-MM-DD' USING ERRCODE = '23514'; END IF;
            PERFORM v_to::date;
        END IF;
        IF e.key IN ('surname', 'first_name') THEN v_to := upper(v_to); END IF;
        v_from := CASE e.key WHEN 'surname' THEN a.surname WHEN 'first_name' THEN a.first_name WHEN 'middle_name' THEN a.middle_name WHEN 'sex' THEN a.sex
                             WHEN 'date_of_birth' THEN a.date_of_birth::text WHEN 'nin' THEN a.nin WHEN 'nationality' THEN a.nationality
                             WHEN 'state_of_origin' THEN a.state_of_origin WHEN 'lga' THEN a.lga END;
        IF v_from IS NOT DISTINCT FROM v_to THEN CONTINUE; END IF;
        v_details := v_details || jsonb_build_object(e.key, jsonb_build_object('from', v_from, 'to', v_to));
    END LOOP;
    IF v_details = '{}'::jsonb THEN
        RAISE EXCEPTION 'JUPEB_CORRECTION_NOTHING: nothing differs from what the record holds' USING ERRCODE = '23514';
    END IF;
    INSERT INTO jupeb.change_request (application_id, kind, from_state, from_stream, from_combination, from_session, reason, requested_by, requested_office, details)
    VALUES (p_app, 'CORRECT_DETAILS', a.state, a.stream, a.combination_id, a.session, btrim(p_reason), p_actor, p_office, v_details)
    RETURNING id INTO v_id;
    PERFORM jupeb.app_event(p_app, 'CHANGE_REQUESTED', jupeb.change_words(v_id) || ' — ' || btrim(p_reason));
    PERFORM jupeb.tell(p_app, 'Your JUPEB request is received',
        'Your request to ' || jupeb.change_words(v_id) || ' is with the JUPEB Office. Keep the evidence (birth certificate, NIN slip, affidavit) at hand; you will be told of its decision.');
    RETURN v_id;
END $$;
COMMENT ON FUNCTION jupeb.request_correction(uuid, jsonb, text, uuid, text) IS 'V347: a correction of the candidate''s identity details (name, sex, date of birth, NIN, nationality, state, LGA) asked of the JUPEB Office; each field kept with its present and corrected value; applied only when the Office approves.';

CREATE OR REPLACE FUNCTION jupeb.decide_change(p_req uuid, p_approve boolean, p_note text, p_actor uuid, p_office text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r jupeb.change_request; a jupeb.application; c jupeb.combination; v_words text;
BEGIN
    SELECT * INTO r FROM jupeb.change_request WHERE id = p_req FOR UPDATE;
    IF r.id IS NULL OR r.state <> 'PENDING' THEN RAISE EXCEPTION 'JUPEB_CHANGE_DECIDED: the request is no longer open' USING ERRCODE = '23514'; END IF;
    v_words := jupeb.change_words(p_req);
    IF NOT p_approve THEN
        IF length(btrim(coalesce(p_note, ''))) = 0 THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_NOTE: say why the request is declined' USING ERRCODE = '23514';
        END IF;
        UPDATE jupeb.change_request SET state = 'DECLINED', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_note = btrim(p_note) WHERE id = p_req;
        PERFORM jupeb.app_event(r.application_id, 'CHANGE_DECLINED', 'Request declined: ' || v_words || ' — ' || btrim(p_note));
        PERFORM jupeb.tell(r.application_id, 'Your JUPEB request is declined', 'The JUPEB Office declined your request to ' || v_words || ': ' || btrim(p_note));
        RETURN;
    END IF;
    PERFORM jupeb.change_check(r.application_id, r.kind, r.to_stream, r.to_combination, r.to_session);
    SELECT * INTO a FROM jupeb.application WHERE id = r.application_id FOR UPDATE;
    IF r.kind = 'WITHDRAW' THEN
        UPDATE jupeb.application SET state = 'WITHDRAWN', withdrawn_at = now() WHERE id = a.id;
    ELSIF r.kind = 'DEFER' THEN
        UPDATE jupeb.application SET state = 'DEFERRED', deferred_from = a.session, deferred_to = r.to_session WHERE id = a.id;
    ELSIF r.kind = 'CHANGE_COMBINATION' THEN
        SELECT * INTO c FROM jupeb.combination WHERE id = r.to_combination;
        UPDATE jupeb.application SET combination_id = c.id WHERE id = a.id;
        IF a.subjects_registered_at IS NOT NULL THEN
            /* no result and no examination number hang on the old subjects (change_check): the registration follows the new combination */
            DELETE FROM jupeb.subject_registration WHERE application_id = a.id;
            INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by)
            SELECT a.id, s, a.session, p_actor FROM unnest(ARRAY[c.subject1, c.subject2, c.subject3]) s;
        END IF;
    ELSIF r.kind = 'CHANGE_PROGRAMME' THEN
        UPDATE jupeb.application SET stream = r.to_stream, combination_id = r.to_combination WHERE id = a.id;
    ELSIF r.kind = 'CORRECT_DETAILS' THEN
        -- V347: each corrected field as the request named it; the request keeps what it read before
        UPDATE jupeb.application x SET
               surname         = CASE WHEN r.details ? 'surname' THEN r.details->'surname'->>'to' ELSE x.surname END,
               first_name      = CASE WHEN r.details ? 'first_name' THEN r.details->'first_name'->>'to' ELSE x.first_name END,
               middle_name     = CASE WHEN r.details ? 'middle_name' THEN nullif(r.details->'middle_name'->>'to', '') ELSE x.middle_name END,
               sex             = CASE WHEN r.details ? 'sex' THEN r.details->'sex'->>'to' ELSE x.sex END,
               date_of_birth   = CASE WHEN r.details ? 'date_of_birth' THEN (r.details->'date_of_birth'->>'to')::date ELSE x.date_of_birth END,
               nin             = CASE WHEN r.details ? 'nin' THEN r.details->'nin'->>'to' ELSE x.nin END,
               nationality     = CASE WHEN r.details ? 'nationality' THEN r.details->'nationality'->>'to' ELSE x.nationality END,
               state_of_origin = CASE WHEN r.details ? 'state_of_origin' THEN r.details->'state_of_origin'->>'to' ELSE x.state_of_origin END,
               lga             = CASE WHEN r.details ? 'lga' THEN r.details->'lga'->>'to' ELSE x.lga END
         WHERE x.id = a.id;
    END IF;
    UPDATE jupeb.change_request SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = p_req;
    PERFORM jupeb.app_event(r.application_id, 'CHANGE_APPROVED', 'Request approved: ' || v_words || coalesce(' — ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    PERFORM jupeb.tell(r.application_id, 'Your JUPEB request is approved', 'The JUPEB Office approved your request to ' || v_words || '.'
        || coalesce(' ' || nullif(btrim(coalesce(p_note, '')), ''), '')
        || CASE r.kind WHEN 'WITHDRAW' THEN ' Your application is withdrawn. Any refund is the Bursary''s decision under its own rules.'
                       WHEN 'DEFER' THEN ' Your admission is held for ' || r.to_session || '; the JUPEB Office resumes it then.'
                       WHEN 'CORRECT_DETAILS' THEN ' Your record now reads as corrected; papers issued from now on carry it.'
                       ELSE ' Sign in to the JUPEB portal to see your record.' END);
END $$;

-- ── 4 · the timetable ────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.timetable_slot (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session     text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    semester    int  NOT NULL CHECK (semester IN (1, 2)),
    class_id    uuid NULL REFERENCES jupeb.class(id),
    subject_id  uuid NOT NULL REFERENCES jupeb.subject(id),
    weekday     int  NOT NULL CHECK (weekday BETWEEN 1 AND 7),
    starts_at   time NOT NULL,
    ends_at     time NOT NULL,
    venue       text NULL CHECK (venue IS NULL OR length(venue) <= 120),
    note        text NULL CHECK (note IS NULL OR length(note) <= 300),
    active      boolean NOT NULL DEFAULT true,
    created_by  uuid NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_slot_time CHECK (ends_at > starts_at)
);
CREATE INDEX ix_jupeb_slot_session ON jupeb.timetable_slot (session, semester, weekday, starts_at) WHERE active;
COMMENT ON TABLE jupeb.timetable_slot IS 'V347: a weekly lecture slot of a JUPEB subject in a session and semester, for one class or (class_id empty) every class; removed by marking it inactive.';
SELECT audit.attach('jupeb.timetable_slot');

-- a class double-booked in the same hour is refused
CREATE OR REPLACE FUNCTION jupeb.slot_clash()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.active AND EXISTS (
        SELECT 1 FROM jupeb.timetable_slot s
         WHERE s.id <> NEW.id AND s.active AND s.session = NEW.session AND s.semester = NEW.semester AND s.weekday = NEW.weekday
           AND (s.class_id IS NULL OR NEW.class_id IS NULL OR s.class_id = NEW.class_id)
           AND s.starts_at < NEW.ends_at AND NEW.starts_at < s.ends_at) THEN
        RAISE EXCEPTION 'JUPEB_SLOT_CLASH: the class already has a lecture at that time' USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;
CREATE TRIGGER trg_jupeb_slot_clash BEFORE INSERT OR UPDATE ON jupeb.timetable_slot FOR EACH ROW EXECUTE FUNCTION jupeb.slot_clash();

-- ── 5 · practice tests ───────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.practice_test (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id             uuid NOT NULL REFERENCES jupeb.subject(id),
    title                  text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 160),
    instructions           text NULL CHECK (instructions IS NULL OR length(instructions) <= 2000),
    duration_minutes       int  NOT NULL DEFAULT 30 CHECK (duration_minutes BETWEEN 5 AND 240),
    questions_per_attempt  int  NOT NULL DEFAULT 20 CHECK (questions_per_attempt BETWEEN 1 AND 200),
    attempts_allowed       int  NOT NULL DEFAULT 3 CHECK (attempts_allowed BETWEEN 1 AND 20),
    show_answers           boolean NOT NULL DEFAULT true,
    open                   boolean NOT NULL DEFAULT false,
    created_by             uuid NULL,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE jupeb.practice_test IS 'V347: a practice test of a JUPEB subject — questions drawn at random from its bank, timed, scored by the server; never part of a result.';
SELECT audit.attach('jupeb.practice_test');

CREATE TABLE jupeb.practice_question (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    test_id      uuid NOT NULL REFERENCES jupeb.practice_test(id),
    ordinal      int  NOT NULL DEFAULT 0,
    stem         text NOT NULL CHECK (length(btrim(stem)) BETWEEN 2 AND 4000),
    option_a     text NOT NULL,
    option_b     text NOT NULL,
    option_c     text NULL,
    option_d     text NULL,
    option_e     text NULL,
    answer       char(1) NOT NULL CHECK (answer IN ('A', 'B', 'C', 'D', 'E')),
    explanation  text NULL CHECK (explanation IS NULL OR length(explanation) <= 4000),
    active       boolean NOT NULL DEFAULT true,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_jupeb_pq_answer CHECK ((answer <> 'C' OR option_c IS NOT NULL) AND (answer <> 'D' OR option_d IS NOT NULL) AND (answer <> 'E' OR option_e IS NOT NULL))
);
CREATE INDEX ix_jupeb_pq_test ON jupeb.practice_question (test_id) WHERE active;
SELECT audit.attach('jupeb.practice_question');

CREATE TABLE jupeb.practice_attempt (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    test_id        uuid NOT NULL REFERENCES jupeb.practice_test(id),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    number         int  NOT NULL,
    question_ids   uuid[] NOT NULL,
    started_at     timestamptz NOT NULL DEFAULT now(),
    ends_at        timestamptz NOT NULL,
    submitted_at   timestamptz NULL,
    answered       int NOT NULL DEFAULT 0,
    score          int NULL,
    total          int NOT NULL,
    percentage     numeric(5,2) NULL,
    UNIQUE (test_id, application_id, number)
);
CREATE UNIQUE INDEX ux_jupeb_pa_open ON jupeb.practice_attempt (test_id, application_id) WHERE submitted_at IS NULL;
CREATE INDEX ix_jupeb_pa_app ON jupeb.practice_attempt (application_id, started_at DESC);
SELECT audit.exempt('jupeb.practice_attempt', 'A practice attempt is the student''s own exercise, never a result; its answers change many times a minute.');

CREATE TABLE jupeb.practice_answer (
    attempt_id   uuid NOT NULL REFERENCES jupeb.practice_attempt(id),
    question_id  uuid NOT NULL REFERENCES jupeb.practice_question(id),
    chosen       char(1) NULL CHECK (chosen IS NULL OR chosen IN ('A', 'B', 'C', 'D', 'E')),
    correct      boolean NULL,
    answered_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (attempt_id, question_id)
);
SELECT audit.exempt('jupeb.practice_answer', 'The answers of a practice attempt; never a result.');

-- the subjects a student practises: the three they registered, else their combination's
CREATE OR REPLACE FUNCTION jupeb.practice_subjects(p_app uuid)
RETURNS TABLE (subject_id uuid)
LANGUAGE sql STABLE AS $$
    SELECT sr.subject_id FROM jupeb.subject_registration sr WHERE sr.application_id = p_app
    UNION
    SELECT s FROM jupeb.application a JOIN jupeb.combination c ON c.id = a.combination_id CROSS JOIN LATERAL unnest(ARRAY[c.subject1, c.subject2, c.subject3]) s
     WHERE a.id = p_app AND NOT EXISTS (SELECT 1 FROM jupeb.subject_registration x WHERE x.application_id = p_app)
$$;

CREATE OR REPLACE FUNCTION jupeb.practice_start(p_app uuid, p_test uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE t jupeb.practice_test; a jupeb.application; v_open uuid; v_used int; v_ids uuid[]; v_id uuid;
BEGIN
    SELECT * INTO t FROM jupeb.practice_test WHERE id = p_test;
    IF t.id IS NULL OR NOT t.open THEN RAISE EXCEPTION 'JUPEB_PRACTICE_CLOSED: the practice test is not open' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED') THEN
        RAISE EXCEPTION 'JUPEB_PRACTICE_STUDENTS: practice tests are for admitted JUPEB students' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.practice_subjects(p_app) x WHERE x.subject_id = t.subject_id) THEN
        RAISE EXCEPTION 'JUPEB_PRACTICE_SUBJECT: this test is for a subject you do not take' USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v_open FROM jupeb.practice_attempt WHERE test_id = p_test AND application_id = p_app AND submitted_at IS NULL;
    IF v_open IS NOT NULL THEN RETURN v_open; END IF;
    SELECT count(*) INTO v_used FROM jupeb.practice_attempt WHERE test_id = p_test AND application_id = p_app;
    IF v_used >= t.attempts_allowed THEN
        RAISE EXCEPTION 'JUPEB_PRACTICE_ATTEMPTS: you have used the % attempts this test allows', t.attempts_allowed USING ERRCODE = '23514';
    END IF;
    v_ids := ARRAY(SELECT q.id FROM jupeb.practice_question q WHERE q.test_id = p_test AND q.active ORDER BY random() LIMIT t.questions_per_attempt);
    IF cardinality(v_ids) = 0 THEN RAISE EXCEPTION 'JUPEB_PRACTICE_EMPTY: the test has no questions yet' USING ERRCODE = '23514'; END IF;
    INSERT INTO jupeb.practice_attempt (test_id, application_id, number, question_ids, ends_at, total)
    VALUES (p_test, p_app, v_used + 1, v_ids, now() + make_interval(mins => t.duration_minutes), cardinality(v_ids))
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION jupeb.practice_answer_set(p_app uuid, p_attempt uuid, p_question uuid, p_choice text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE at jupeb.practice_attempt; v text := nullif(upper(btrim(coalesce(p_choice, ''))), '');
BEGIN
    SELECT * INTO at FROM jupeb.practice_attempt WHERE id = p_attempt AND application_id = p_app;
    IF at.id IS NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_ATTEMPT: no such attempt' USING ERRCODE = '23514'; END IF;
    IF at.submitted_at IS NOT NULL OR at.ends_at < now() THEN RAISE EXCEPTION 'JUPEB_PRACTICE_OVER: the attempt is over' USING ERRCODE = '23514'; END IF;
    IF NOT p_question = ANY (at.question_ids) THEN RAISE EXCEPTION 'JUPEB_PRACTICE_QUESTION: that question is not in this attempt' USING ERRCODE = '23514'; END IF;
    IF v IS NOT NULL AND v NOT IN ('A', 'B', 'C', 'D', 'E') THEN RAISE EXCEPTION 'JUPEB_PRACTICE_CHOICE: choose A to E' USING ERRCODE = '23514'; END IF;
    INSERT INTO jupeb.practice_answer (attempt_id, question_id, chosen) VALUES (p_attempt, p_question, v)
    ON CONFLICT (attempt_id, question_id) DO UPDATE SET chosen = EXCLUDED.chosen, answered_at = now();
END $$;

-- scored by the server, once; an attempt past its time is scored on what was saved
CREATE OR REPLACE FUNCTION jupeb.practice_submit(p_app uuid, p_attempt uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE at jupeb.practice_attempt; v_score int; v_answered int;
BEGIN
    SELECT * INTO at FROM jupeb.practice_attempt WHERE id = p_attempt AND application_id = p_app FOR UPDATE;
    IF at.id IS NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_ATTEMPT: no such attempt' USING ERRCODE = '23514'; END IF;
    IF at.submitted_at IS NOT NULL THEN RETURN; END IF;
    UPDATE jupeb.practice_answer x SET correct = (x.chosen IS NOT NULL AND x.chosen = q.answer)
      FROM jupeb.practice_question q WHERE q.id = x.question_id AND x.attempt_id = p_attempt;
    SELECT count(*) FILTER (WHERE correct), count(*) FILTER (WHERE chosen IS NOT NULL) INTO v_score, v_answered FROM jupeb.practice_answer WHERE attempt_id = p_attempt;
    UPDATE jupeb.practice_attempt SET submitted_at = least(now(), ends_at + interval '1 minute'), score = v_score, answered = v_answered,
           percentage = round(100.0 * v_score / total, 2)
     WHERE id = p_attempt;
END $$;

-- the questions of an attempt as the student may see them: the answer key only once the attempt is over
CREATE OR REPLACE FUNCTION jupeb.practice_paper(p_app uuid, p_attempt uuid)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE at jupeb.practice_attempt; t jupeb.practice_test; v_over boolean;
BEGIN
    SELECT * INTO at FROM jupeb.practice_attempt WHERE id = p_attempt AND application_id = p_app;
    IF at.id IS NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_ATTEMPT: no such attempt' USING ERRCODE = '23514'; END IF;
    IF at.submitted_at IS NULL AND at.ends_at < now() THEN
        PERFORM jupeb.practice_submit(p_app, p_attempt);
        SELECT * INTO at FROM jupeb.practice_attempt WHERE id = p_attempt;
    END IF;
    SELECT * INTO t FROM jupeb.practice_test WHERE id = at.test_id;
    v_over := at.submitted_at IS NOT NULL;
    RETURN jsonb_build_object(
        'attempt', jsonb_build_object('id', at.id, 'number', at.number, 'startedAt', at.started_at, 'endsAt', at.ends_at, 'submittedAt', at.submitted_at,
                                      'score', at.score, 'total', at.total, 'percentage', at.percentage, 'answered', at.answered, 'secondsLeft',
                                      greatest(0, floor(extract(epoch FROM at.ends_at - now())))::int),
        'test', jsonb_build_object('id', t.id, 'title', t.title, 'instructions', t.instructions, 'durationMinutes', t.duration_minutes, 'showAnswers', t.show_answers),
        'questions', (SELECT coalesce(jsonb_agg(
                         jsonb_build_object('id', q.id, 'n', o.n, 'stem', q.stem,
                                            'options', jsonb_strip_nulls(jsonb_build_object('A', q.option_a, 'B', q.option_b, 'C', q.option_c, 'D', q.option_d, 'E', q.option_e)),
                                            'chosen', x.chosen)
                         || CASE WHEN v_over AND t.show_answers THEN jsonb_build_object('answer', q.answer, 'correct', coalesce(x.correct, false), 'explanation', q.explanation)
                                 WHEN v_over THEN jsonb_build_object('correct', coalesce(x.correct, false)) ELSE '{}'::jsonb END
                         ORDER BY o.n), '[]'::jsonb)
                        FROM unnest(at.question_ids) WITH ORDINALITY o(qid, n)
                        JOIN jupeb.practice_question q ON q.id = o.qid
                        LEFT JOIN jupeb.practice_answer x ON x.attempt_id = at.id AND x.question_id = q.id));
END $$;
COMMENT ON FUNCTION jupeb.practice_paper(uuid, uuid) IS 'V347: an attempt''s questions for the student — the options and their own choices; the answer key and the explanations only after the attempt is submitted (and only where the test shows answers).';

-- the office's bank upload: each question checked, the options it names present, the answer one of them
CREATE OR REPLACE FUNCTION jupeb.practice_upload(p_test uuid, p_rows jsonb, p_replace boolean)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_row int; n_ok int := 0; bad jsonb := '[]'::jsonb; v_ans text; v_stem text; v_ord int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM jupeb.practice_test WHERE id = p_test) THEN RAISE EXCEPTION 'JUPEB_PRACTICE_TEST: no such test' USING ERRCODE = '23514'; END IF;
    IF p_replace THEN UPDATE jupeb.practice_question SET active = false WHERE test_id = p_test AND active; END IF;
    SELECT coalesce(max(ordinal), 0) INTO v_ord FROM jupeb.practice_question WHERE test_id = p_test;
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_row := nullif(r->>'row', '')::int;
        v_stem := nullif(btrim(coalesce(r->>'question', '')), '');
        v_ans := upper(left(btrim(coalesce(r->>'answer', '')), 1));
        IF v_stem IS NULL OR nullif(btrim(coalesce(r->>'a', '')), '') IS NULL OR nullif(btrim(coalesce(r->>'b', '')), '') IS NULL THEN
            bad := bad || jsonb_build_array(jsonb_build_object('row', v_row, 'reason', 'A question needs its text and at least options A and B.'));
            CONTINUE;
        END IF;
        IF v_ans NOT IN ('A', 'B', 'C', 'D', 'E') OR nullif(btrim(coalesce(r->>lower(v_ans), '')), '') IS NULL THEN
            bad := bad || jsonb_build_array(jsonb_build_object('row', v_row, 'reason', 'The answer must be the letter of one of the options given.'));
            CONTINUE;
        END IF;
        v_ord := v_ord + 1;
        INSERT INTO jupeb.practice_question (test_id, ordinal, stem, option_a, option_b, option_c, option_d, option_e, answer, explanation)
        VALUES (p_test, v_ord, v_stem, btrim(r->>'a'), btrim(r->>'b'), nullif(btrim(coalesce(r->>'c', '')), ''), nullif(btrim(coalesce(r->>'d', '')), ''),
                nullif(btrim(coalesce(r->>'e', '')), ''), v_ans, nullif(btrim(coalesce(r->>'explanation', '')), ''));
        n_ok := n_ok + 1;
    END LOOP;
    UPDATE jupeb.practice_test SET updated_at = now() WHERE id = p_test;
    RETURN jsonb_build_object('added', n_ok, 'refused', bad, 'active', (SELECT count(*) FROM jupeb.practice_question WHERE test_id = p_test AND active));
END $$;

-- ── 6 · the office's reports ─────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION jupeb.report(p_session text)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    WITH apps AS (SELECT a.* FROM jupeb.application a WHERE a.session = p_session),
    students AS (SELECT * FROM apps WHERE state IN ('STUDENT', 'COMPLETED')),
    fees AS (SELECT f.* FROM jupeb.fee_reference f JOIN apps a ON a.id = f.application_id WHERE f.confirmed_at IS NOT NULL),
    att AS (SELECT m.* FROM students s CROSS JOIN LATERAL attendance.member_summary('JUPEB', s.id, p_session) m),
    res AS (SELECT r.*, s.code, s.title FROM jupeb.result r JOIN apps a ON a.id = r.application_id JOIN jupeb.subject s ON s.id = r.subject_id)
    SELECT jsonb_build_object(
      'session', p_session,
      'enrolment', jsonb_build_object(
          'byState', (SELECT coalesce(jsonb_agg(jsonb_build_object('state', state, 'count', n) ORDER BY n DESC), '[]'::jsonb)
                        FROM (SELECT state, count(*) AS n FROM apps GROUP BY state) x),
          'byStream', (SELECT coalesce(jsonb_agg(jsonb_build_object('stream', coalesce(stream, 'UNSET'), 'applicants', applicants, 'admitted', admitted, 'students', studs) ORDER BY stream), '[]'::jsonb)
                         FROM (SELECT stream, count(*) AS applicants, count(*) FILTER (WHERE state IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED')) AS admitted,
                                      count(*) FILTER (WHERE state IN ('STUDENT', 'COMPLETED')) AS studs FROM apps GROUP BY stream) x),
          'byCombination', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'students', n) ORDER BY n DESC, code), '[]'::jsonb)
                              FROM (SELECT c.code, c.name, count(*) AS n FROM students s JOIN jupeb.combination c ON c.id = s.combination_id GROUP BY c.code, c.name) x),
          'byState_of_origin', (SELECT coalesce(jsonb_agg(jsonb_build_object('state', st, 'students', n) ORDER BY n DESC, st), '[]'::jsonb)
                                  FROM (SELECT coalesce(nullif(btrim(state_of_origin), ''), 'Not stated') AS st, count(*) AS n FROM students GROUP BY 1) x),
          'byClass', (SELECT coalesce(jsonb_agg(jsonb_build_object('class', name, 'students', n, 'capacity', capacity) ORDER BY name), '[]'::jsonb)
                        FROM (SELECT k.name, k.capacity, count(s.id) AS n FROM jupeb.class k LEFT JOIN students s ON s.class_id = k.id
                               WHERE k.session = p_session GROUP BY k.name, k.capacity) x),
          'totals', (SELECT jsonb_build_object('applications', count(*), 'submitted', count(*) FILTER (WHERE submitted_at IS NOT NULL),
                                               'admitted', count(*) FILTER (WHERE state IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED')),
                                               'students', count(*) FILTER (WHERE state IN ('STUDENT', 'COMPLETED')),
                                               'withdrawn', count(*) FILTER (WHERE state = 'WITHDRAWN'), 'fromOldPortal', count(*) FILTER (WHERE legacy_source IS NOT NULL))
                       FROM apps)),
      'fees', jsonb_build_object(
          'byKind', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'payments', n, 'amount', amt, 'oldPortal', old) ORDER BY kind), '[]'::jsonb)
                       FROM (SELECT kind, count(*) AS n, sum(amount) AS amt, count(*) FILTER (WHERE channel = 'Old portal') AS old FROM fees GROUP BY kind) x),
          'byMonth', (SELECT coalesce(jsonb_agg(jsonb_build_object('month', m, 'amount', amt, 'payments', n) ORDER BY m), '[]'::jsonb)
                        FROM (SELECT to_char(confirmed_at, 'YYYY-MM') AS m, sum(amount) AS amt, count(*) AS n FROM fees GROUP BY 1) x),
          'schoolFees', (SELECT jsonb_build_object('students', count(*), 'paidInFull', count(*) FILTER (WHERE sf.status = 'PAID'),
                                                   'partly', count(*) FILTER (WHERE sf.status = 'PARTIALLY_PAID'), 'unpaid', count(*) FILTER (WHERE sf.status = 'NOT_PAID'),
                                                   'charged', coalesce(sum(sf.total), 0), 'paid', coalesce(sum(sf.paid), 0), 'outstanding', coalesce(sum(sf.outstanding), 0))
                           FROM apps a CROSS JOIN LATERAL jupeb.school_fees(a.id) sf WHERE a.state IN ('ADMITTED', 'STUDENT', 'COMPLETED')),
          'total', (SELECT coalesce(sum(amount), 0) FROM fees)),
      'attendance', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', code, 'title', title, 'semester', semester, 'students', n, 'averageRate', avg_rate,
                                                                  'belowMinimum', below, 'atRisk', risk, 'classesHeld', held) ORDER BY title, semester), '[]'::jsonb)
                       FROM (SELECT s.code, s.title, t.semester, count(*) AS n, round(avg(t.rate), 1) AS avg_rate,
                                    count(*) FILTER (WHERE t.verdict = 'NOT_ELIGIBLE') AS below, count(*) FILTER (WHERE t.at_risk) AS risk, max(t.total) AS held
                               FROM att t JOIN jupeb.subject s ON s.id = t.subject_ref GROUP BY s.code, s.title, t.semester) x),
      'results', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', code, 'title', title, 'candidates', n, 'A', ga, 'B', gb, 'C', gc, 'D', gd, 'E', ge, 'F', gf,
                                                               'other', gx, 'passRate', CASE WHEN n - gx > 0 THEN round(100.0 * (n - gf - gx) / (n - gx), 1) END,
                                                               'averagePoints', avg_pts) ORDER BY title), '[]'::jsonb)
                    FROM (SELECT code, title, count(*) AS n, count(*) FILTER (WHERE grade = 'A') AS ga, count(*) FILTER (WHERE grade = 'B') AS gb,
                                 count(*) FILTER (WHERE grade = 'C') AS gc, count(*) FILTER (WHERE grade = 'D') AS gd, count(*) FILTER (WHERE grade = 'E') AS ge,
                                 count(*) FILTER (WHERE grade = 'F') AS gf, count(*) FILTER (WHERE grade IN ('X', 'Q', 'W')) AS gx, round(avg(points), 2) AS avg_pts
                            FROM res GROUP BY code, title) x),
      'practice', (SELECT coalesce(jsonb_agg(jsonb_build_object('title', title, 'code', code, 'attempts', n, 'students', who, 'averagePercent', avg_pct) ORDER BY code, title), '[]'::jsonb)
                     FROM (SELECT t.title, s.code, count(p.id) AS n, count(DISTINCT p.application_id) AS who, round(avg(p.percentage), 1) AS avg_pct
                             FROM jupeb.practice_test t JOIN jupeb.subject s ON s.id = t.subject_id
                             JOIN jupeb.practice_attempt p ON p.test_id = t.id AND p.submitted_at IS NOT NULL
                             JOIN apps a ON a.id = p.application_id GROUP BY t.title, s.code) x))
$$;
COMMENT ON FUNCTION jupeb.report(text) IS 'V347: the JUPEB Office''s report of a session — enrolment (by state, programme, combination, state of origin, class), fees (by kind and month, the school-fee position), attendance and results by subject, practice tests.';

COMMIT;

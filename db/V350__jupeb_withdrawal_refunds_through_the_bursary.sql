-- ═══════════════════════════════════════════════════════════════════════════
-- V350 — A withdrawn JUPEB candidate's fees go to the Bursary's refund workflow
--
--   Until now a JUPEB withdrawal ended with "any refund is the Bursary's decision under its own rules" and nothing more: a
--   refund owed depended on someone writing to the Bursary. Here the withdrawal itself opens a refund claim, in the Bursary's
--   queue, with every fee the candidate paid on the portal; the candidate gives the account to pay; the Bursary decides — it
--   raises a refund against a payment through its own maker–checker workflow (V043, V067: one officer proposes, another
--   approves, then it is marked paid) or declines the claim with a reason the candidate reads. No second refund engine:
--   finance.refund holds the money; jupeb.refund_claim only says which candidate and which payments a refund is for.
--
--   · finance.propose_refund now refuses a refund that, with the refunds already raised against the same payment and not
--     rejected, would exceed what was paid on it (V067 checked each refund alone, so the same payment could be refunded twice).
--   · The Bursary's day book names the JUPEB status checking and acceptance fees (V342 added them; they read as "school fee").
--   · The candidate is told when the claim opens, when it is declined, and when a refund is paid — never the amount or the
--     account in the message.
--   · Practice results for the JUPEB Office: each student's practice tests — attempts, average, best, last, by subject —
--     weakest first, so the Office can advise a student who is struggling; the advice is a notice to that one student
--     (announcement audience STUDENT), on their dashboard and, when asked, by email and text.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V350: JUPEB withdrawal refunds through the Bursary', true);

-- ── 1 · the claim, and the Bursary's refunds raised on it ────────────────────────────────────────────────────────
CREATE TABLE jupeb.refund_claim (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id    uuid NOT NULL UNIQUE REFERENCES jupeb.application(id),
    change_request_id uuid NULL REFERENCES jupeb.change_request(id),
    opened_at         timestamptz NOT NULL DEFAULT now(),
    payments          jsonb NOT NULL,
    paid_total        numeric(14,2) NOT NULL CHECK (paid_total > 0),
    bank_name         text NULL CHECK (bank_name IS NULL OR length(btrim(bank_name)) BETWEEN 2 AND 120),
    account_name      text NULL CHECK (account_name IS NULL OR length(btrim(account_name)) BETWEEN 2 AND 200),
    account_number    text NULL CHECK (account_number IS NULL OR account_number ~ '^[0-9]{10}$'),
    details_at        timestamptz NULL,
    declined_at       timestamptz NULL,
    declined_by       uuid NULL,
    declined_reason   text NULL,
    CONSTRAINT ck_jupeb_claim_account CHECK (num_nulls(bank_name, account_name, account_number) IN (0, 3)),
    CONSTRAINT ck_jupeb_claim_declined CHECK ((declined_at IS NULL) = (declined_reason IS NULL))
);
SELECT audit.attach('jupeb.refund_claim');
COMMENT ON TABLE jupeb.refund_claim IS 'V350: the refund a withdrawn JUPEB candidate may be owed — the fees they paid on the portal (payments, snapshotted when the withdrawal took effect), the account they give, and the Bursary''s refusal if it declines; the money itself is finance.refund (jupeb.refund_claim_refund).';

CREATE TABLE jupeb.refund_claim_refund (
    claim_id  uuid NOT NULL REFERENCES jupeb.refund_claim(id),
    refund_id uuid NOT NULL UNIQUE REFERENCES finance.refund(id) ON DELETE CASCADE,
    reference text NOT NULL,
    PRIMARY KEY (claim_id, refund_id)
);
SELECT audit.attach('jupeb.refund_claim_refund');
COMMENT ON TABLE jupeb.refund_claim_refund IS 'V350: a refund the Bursary raised (finance.refund) on a JUPEB claim, against one of the candidate''s payments (reference); goes with the refund when platform.reset_operational_data clears the refunds.';

-- the candidate's confirmed payments on the portal, for the claim
CREATE OR REPLACE FUNCTION jupeb.refundable_payments(p_app uuid)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(jsonb_build_object('reference', f.reference, 'kind', f.kind, 'amount', f.amount, 'channel', f.channel,
                                                 'paidOn', (f.confirmed_at AT TIME ZONE 'Africa/Lagos')::date) ORDER BY f.confirmed_at), '[]'::jsonb)
      FROM jupeb.fee_reference f WHERE f.application_id = p_app AND f.confirmed_at IS NOT NULL
$$;

-- where a claim stands: declined; a refund paid, approved or awaiting approval; with the Bursary; waiting for the account
CREATE OR REPLACE FUNCTION jupeb.refund_claim_state(p_claim uuid)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT * FROM jupeb.refund_claim WHERE id = p_claim),
    r AS (SELECT f.state, f.amount FROM jupeb.refund_claim_refund x JOIN finance.refund f ON f.id = x.refund_id WHERE x.claim_id = p_claim)
    SELECT jsonb_build_object(
        'status', CASE WHEN c.declined_at IS NOT NULL THEN 'DECLINED'
                       WHEN EXISTS (SELECT 1 FROM r WHERE state = 'PROPOSED') THEN 'REFUND_PROPOSED'
                       WHEN EXISTS (SELECT 1 FROM r WHERE state = 'APPROVED') THEN 'REFUND_APPROVED'
                       WHEN EXISTS (SELECT 1 FROM r WHERE state = 'PAID') THEN 'REFUND_PAID'
                       WHEN c.account_number IS NULL THEN 'AWAITING_DETAILS'
                       ELSE 'WITH_BURSARY' END,
        'raised', (SELECT coalesce(sum(amount), 0) FROM r WHERE state <> 'REJECTED'),
        'paid', (SELECT coalesce(sum(amount), 0) FROM r WHERE state = 'PAID'))
      FROM c
$$;

-- a withdrawal that takes effect opens the claim when the candidate paid anything on the portal
CREATE OR REPLACE FUNCTION jupeb.open_refund_claim(p_app uuid, p_quiet boolean)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_pay jsonb := jupeb.refundable_payments(p_app); v_total numeric; v_id uuid;
BEGIN
    v_total := (SELECT coalesce(sum((e->>'amount')::numeric), 0) FROM jsonb_array_elements(v_pay) e);
    IF v_total <= 0 THEN RETURN NULL; END IF;
    INSERT INTO jupeb.refund_claim (application_id, change_request_id, payments, paid_total)
    VALUES (p_app, (SELECT r.id FROM jupeb.change_request r WHERE r.application_id = p_app AND r.kind = 'WITHDRAW' ORDER BY r.requested_at DESC LIMIT 1), v_pay, v_total)
    ON CONFLICT (application_id) DO NOTHING
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN RETURN NULL; END IF;
    PERFORM jupeb.app_event(p_app, 'REFUND_CLAIM_OPENED', 'Refund claim opened with the Bursary for the fees paid on the portal');
    IF NOT p_quiet THEN
        PERFORM jupeb.tell(p_app, 'Your JUPEB fees: a refund claim is with the Bursary',
            'Your withdrawal from the JUPEB programme has taken effect. The fees you paid on the portal are now before the Bursary, which decides any refund under '
            || 'its own rules. Sign in to the JUPEB portal and give the bank account a refund would be paid into; you will be told of the Bursary''s decision.');
    END IF;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION jupeb.withdrawal_opens_claim()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.state = 'WITHDRAWN' AND OLD.state IS DISTINCT FROM 'WITHDRAWN' THEN
        PERFORM jupeb.open_refund_claim(NEW.id, coalesce(current_setting('moaum.jupeb_quiet', true), '') = 'on');
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_jupeb_withdrawal_claim AFTER UPDATE OF state ON jupeb.application FOR EACH ROW EXECUTE FUNCTION jupeb.withdrawal_opens_claim();

-- the Bursary raises a refund on a claim, against one of the candidate's payments, through its own workflow
CREATE OR REPLACE FUNCTION jupeb.propose_claim_refund(p_claim uuid, p_reference text, p_amount numeric, p_reason text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE c jupeb.refund_claim; a jupeb.application; v_ref text := upper(btrim(coalesce(p_reference, ''))); v_rf text; v_id uuid;
BEGIN
    SELECT * INTO c FROM jupeb.refund_claim WHERE id = p_claim FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'JUPEB_REFUND_CLAIM: no such refund claim' USING ERRCODE = '23514'; END IF;
    IF c.declined_at IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_REFUND_DECLINED: this claim was declined' USING ERRCODE = '23514'; END IF;
    IF c.account_number IS NULL THEN
        RAISE EXCEPTION 'JUPEB_REFUND_DETAILS: the candidate has not given the account a refund is paid into' USING ERRCODE = '23514',
            HINT = 'The candidate gives it on the JUPEB portal; they were told when the claim opened.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.fee_reference f WHERE f.application_id = c.application_id AND f.reference = v_ref AND f.confirmed_at IS NOT NULL) THEN
        RAISE EXCEPTION 'JUPEB_REFUND_REFERENCE: % is not a confirmed payment of this candidate', v_ref USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'JUPEB_REFUND_REASON: say why the refund is owed' USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM jupeb.application WHERE id = c.application_id;
    v_rf := finance.propose_refund(NULL, upper(a.surname) || ' ' || a.first_name || coalesce(' ' || a.middle_name, '') || ' (JUPEB ' || a.application_no || ')',
                                   btrim(p_reason), p_amount, c.bank_name, c.account_name, right(c.account_number, 4), v_ref);
    v_id := (SELECT id FROM finance.refund WHERE reference = v_rf);
    INSERT INTO jupeb.refund_claim_refund (claim_id, refund_id, reference) VALUES (c.id, v_id, v_ref);
    PERFORM jupeb.app_event(c.application_id, 'REFUND_PROPOSED', 'Refund ' || v_rf || ' raised by the Bursary against ' || v_ref || ', awaiting approval');
    RETURN v_id;
END $$;

-- the Bursary declines a claim with its reason, when no refund is raised on it (or every one raised was rejected)
CREATE OR REPLACE FUNCTION jupeb.decline_refund_claim(p_claim uuid, p_reason text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE c jupeb.refund_claim;
BEGIN
    SELECT * INTO c FROM jupeb.refund_claim WHERE id = p_claim FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'JUPEB_REFUND_CLAIM: no such refund claim' USING ERRCODE = '23514'; END IF;
    IF c.declined_at IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_REFUND_DECLINED: this claim was declined already' USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'JUPEB_REFUND_REASON: say why the claim is declined' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM jupeb.refund_claim_refund x JOIN finance.refund f ON f.id = x.refund_id WHERE x.claim_id = c.id AND f.state <> 'REJECTED') THEN
        RAISE EXCEPTION 'JUPEB_REFUND_RAISED: a refund is raised on this claim; reject it in Refunds first, or let it be paid' USING ERRCODE = '23514';
    END IF;
    UPDATE jupeb.refund_claim SET declined_at = now(), declined_by = p_actor, declined_reason = btrim(p_reason) WHERE id = c.id;
    PERFORM jupeb.app_event(c.application_id, 'REFUND_DECLINED', 'Refund claim declined by the Bursary: ' || btrim(p_reason));
    PERFORM jupeb.tell(c.application_id, 'Your JUPEB refund claim: the Bursary''s decision',
        'The Bursary has decided not to refund the JUPEB fees you paid: ' || btrim(p_reason) || ' Sign in to the JUPEB portal for the details.');
END $$;

-- a refund raised on a claim and paid: the candidate is told (without the amount or the account), and the record says so
CREATE OR REPLACE FUNCTION jupeb.claim_refund_paid()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_app uuid;
BEGIN
    IF NEW.state = 'PAID' AND OLD.state IS DISTINCT FROM 'PAID' THEN
        v_app := (SELECT c.application_id FROM jupeb.refund_claim_refund x JOIN jupeb.refund_claim c ON c.id = x.claim_id WHERE x.refund_id = NEW.id);
        IF v_app IS NOT NULL THEN
            PERFORM jupeb.app_event(v_app, 'REFUND_PAID', 'Refund ' || NEW.reference || ' paid by the Bursary');
            PERFORM jupeb.tell(v_app, 'Your JUPEB refund has been paid',
                'The Bursary has paid a refund of the JUPEB fees you paid into the account you gave. Sign in to the JUPEB portal for the details.');
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_jupeb_claim_refund_paid AFTER UPDATE OF state ON finance.refund FOR EACH ROW EXECUTE FUNCTION jupeb.claim_refund_paid();

-- the withdrawals that took effect before this: their claims are opened for the Bursary, quietly
SELECT jupeb.open_refund_claim(a.id, true) FROM jupeb.application a WHERE a.state = 'WITHDRAWN';

-- ── 2 · a payment is never refunded beyond what was paid on it, in all ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.propose_refund(p_student uuid, p_payer text, p_reason text, p_amount numeric,
                                                  p_bank text, p_account_name text, p_account_last4 text,
                                                  p_source text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_ref text; v_src text; st record; v_raised numeric;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a refund is raised by a person' USING ERRCODE = '23514'; END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'a refund is for an amount' USING ERRCODE = '23514'; END IF;
    IF p_payer IS NULL OR btrim(p_payer) = '' THEN RAISE EXCEPTION 'a refund names who it is paid to' USING ERRCODE = '23514'; END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'a refund carries the reason it is owed' USING ERRCODE = '23514'; END IF;

    v_src := nullif(upper(btrim(coalesce(p_source, ''))), '');
    IF v_src IS NOT NULL THEN
        SELECT * INTO st FROM finance.reference_state(v_src);
        IF st IS NULL OR st.amount IS NULL THEN
            RAISE EXCEPTION 'no transaction % was generated by this portal', v_src USING ERRCODE = '23503',
                HINT = 'Refund against a reference this portal issued; a slip from elsewhere is not a transaction here.';
        END IF;
        IF st.confirmed_at IS NULL THEN
            RAISE EXCEPTION 'transaction % is not a confirmed payment; there is nothing paid to refund', v_src USING ERRCODE = '23514';
        END IF;
        -- V350: with the refunds already raised against it and not rejected
        PERFORM 1 FROM finance.refund WHERE source_reference = v_src FOR UPDATE;
        v_raised := (SELECT coalesce(sum(amount), 0) FROM finance.refund WHERE source_reference = v_src AND state <> 'REJECTED');
        IF p_amount + v_raised > st.amount THEN
            RAISE EXCEPTION 'a refund of NGN % with the NGN % already raised exceeds the NGN % paid on %', p_amount, v_raised, st.amount, v_src USING ERRCODE = '23514',
                HINT = 'Refund up to what was received on the transaction, less what is already refunded on it.';
        END IF;
    END IF;

    v_ref := 'RF-' || to_char(current_date, 'YYYY') || '-' ||
             lpad(platform.next_number('REFUND', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0');
    INSERT INTO finance.refund (reference, student_id, payer, reason, amount, bank_name, account_name, account_last4, proposed_by, source_reference)
    VALUES (v_ref, p_student, btrim(p_payer), btrim(p_reason), p_amount,
            nullif(btrim(coalesce(p_bank, '')), ''), nullif(btrim(coalesce(p_account_name, '')), ''), nullif(btrim(coalesce(p_account_last4, '')), ''), who, v_src);
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION finance.propose_refund(uuid, text, text, numeric, text, text, text, text) IS 'V043, V067, V350: a refund proposed (maker); against a named transaction, never more than was paid on it less what is already raised against it and not rejected.';

-- ── 3 · the day book names every JUPEB fee ────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.day_book(p_from date, p_to date)
RETURNS TABLE (reference text, confirmed_at timestamptz, payer text, number text, purpose text, amount numeric, channel text, receipt_no text, note text, session text)
LANGUAGE sql STABLE AS $$
    SELECT r.reference, r.confirmed_at, s.surname || ', ' || s.other_names, coalesce(s.matric_no, s.admission_no), r.purpose, r.amount, r.channel, r.receipt_no, r.note, r.session
      FROM finance.payment_reference r JOIN people.student s ON s.id = r.student_id
     WHERE r.confirmed_at IS NOT NULL AND r.confirmed_at::date BETWEEN p_from AND p_to
    UNION ALL
    SELECT f.reference, f.confirmed_at, c.surname || ', ' || c.other_names, a.application_no,
           CASE f.kind WHEN 'APPLICATION' THEN 'Application fee' ELSE 'Acceptance fee' END, f.amount, f.channel, NULL, f.note, a.session
      FROM admissions.fee_reference f JOIN admissions.application a ON a.id = f.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
     WHERE f.confirmed_at IS NOT NULL AND f.confirmed_at::date BETWEEN p_from AND p_to
    UNION ALL
    SELECT j.reference, j.confirmed_at, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), a.application_no,
           CASE j.kind WHEN 'APPLICATION' THEN 'JUPEB application fee' WHEN 'STATUS_CHECKING' THEN 'JUPEB admission status checking fee'
                       WHEN 'ACCEPTANCE' THEN 'JUPEB acceptance fee' WHEN 'SCHOOL_FIRST' THEN 'JUPEB school fee (first semester)'
                       WHEN 'SCHOOL_SECOND' THEN 'JUPEB school fee (second semester)' WHEN 'SCHOOL_FULL' THEN 'JUPEB school fee (full)'
                       ELSE 'JUPEB ' || lower(replace(j.kind, '_', ' ')) END,
           j.amount, j.channel, NULL, NULL, j.session
      FROM jupeb.fee_reference j JOIN jupeb.application a ON a.id = j.application_id
     WHERE j.confirmed_at IS NOT NULL AND j.confirmed_at::date BETWEEN p_from AND p_to
    ORDER BY 2 DESC
$$;

-- ── 4 · practice results, student by student; a notice to one student ────────────────────────────────────────────
ALTER TABLE jupeb.announcement DROP CONSTRAINT announcement_audience_check;
ALTER TABLE jupeb.announcement ADD CONSTRAINT announcement_audience_check
    CHECK (audience IN ('ALL', 'APPLICANTS', 'ADMITTED', 'STUDENTS', 'CLASS', 'COMBINATION', 'PROGRAMME', 'STUDENT'));
ALTER TABLE jupeb.announcement DROP CONSTRAINT ck_jupeb_ann_ref;
ALTER TABLE jupeb.announcement ADD CONSTRAINT ck_jupeb_ann_ref CHECK ((audience IN ('CLASS', 'COMBINATION', 'PROGRAMME', 'STUDENT')) = (audience_ref IS NOT NULL));

CREATE OR REPLACE FUNCTION jupeb.audience_reaches(p_session text, p_audience text, p_ref text, p_app jupeb.application)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_app.session = p_session AND p_app.state <> 'WITHDRAWN' AND CASE p_audience
        WHEN 'ALL' THEN true
        WHEN 'APPLICANTS' THEN p_app.state IN ('DRAFT', 'SUBMITTED', 'RETURNED', 'UNDER_REVIEW', 'ELIGIBLE', 'PENDING')
        WHEN 'ADMITTED' THEN p_app.state IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED')
        WHEN 'STUDENTS' THEN p_app.state IN ('STUDENT', 'COMPLETED')
        WHEN 'CLASS' THEN p_app.class_id::text = p_ref
        WHEN 'COMBINATION' THEN EXISTS (SELECT 1 FROM jupeb.combination c WHERE c.id = p_app.combination_id AND upper(c.code) = upper(p_ref))
        WHEN 'PROGRAMME' THEN (CASE WHEN p_app.stream = 'ARTS' THEN 'NON_SCIENCE' ELSE p_app.stream END) = p_ref
        WHEN 'STUDENT' THEN p_app.id::text = p_ref
        ELSE false END
$$;

-- each student's practice: the tests taken, the attempts, the average and the best, the last, and each subject's average
CREATE OR REPLACE FUNCTION jupeb.practice_results(p_session text)
RETURNS TABLE (application_id uuid, application_no text, name text, class_name text, combination_code text, tests int, attempts int,
               average numeric, best numeric, last_at timestamptz, subjects jsonb, advised_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH att AS (
        SELECT p.application_id, p.test_id, t.subject_id, p.percentage, p.submitted_at
          FROM jupeb.practice_attempt p JOIN jupeb.practice_test t ON t.id = p.test_id JOIN jupeb.application a ON a.id = p.application_id
         WHERE p.submitted_at IS NOT NULL AND a.session = p_session AND a.state <> 'WITHDRAWN'),
    bysub AS (
        SELECT x.application_id, jsonb_agg(jsonb_build_object('code', s.code, 'title', s.title, 'attempts', x.n, 'average', x.avg_pct) ORDER BY x.avg_pct, s.code) AS subjects
          FROM (SELECT application_id, subject_id, count(*) AS n, round(avg(percentage), 1) AS avg_pct FROM att GROUP BY application_id, subject_id) x
          JOIN jupeb.subject s ON s.id = x.subject_id GROUP BY x.application_id)
    SELECT a.id, a.application_no, upper(a.surname) || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), k.name, c.code,
           count(DISTINCT att.test_id)::int, count(*)::int, round(avg(att.percentage), 1), max(att.percentage), max(att.submitted_at), b.subjects,
           (SELECT max(n.published_at) FROM jupeb.announcement n WHERE n.audience = 'STUDENT' AND n.audience_ref = a.id::text AND n.withdrawn_at IS NULL)
      FROM att JOIN jupeb.application a ON a.id = att.application_id
      LEFT JOIN jupeb.class k ON k.id = a.class_id LEFT JOIN jupeb.combination c ON c.id = a.combination_id
      LEFT JOIN bysub b ON b.application_id = a.id
     GROUP BY a.id, a.application_no, a.surname, a.first_name, a.middle_name, k.name, c.code, b.subjects
$$;
COMMENT ON FUNCTION jupeb.practice_results(text) IS 'V350: each student of a session who practised — tests, attempts, average and best percentage, the last attempt, each subject''s average (weakest first) and when the JUPEB Office last advised them.';

GRANT SELECT ON jupeb.refund_claim, jupeb.refund_claim_refund TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON jupeb.refund_claim, jupeb.refund_claim_refund TO app_admissions, app_finance;

COMMIT;

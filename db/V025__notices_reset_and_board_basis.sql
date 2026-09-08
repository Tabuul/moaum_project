-- ═══════════════════════════════════════════════════════════════════════════
-- V025 — notices on the record, the applicant's password reset, and the
--        basis of the Board's decision
--
--   · Every notice the portal sends — email or SMS — is a row in the outbox
--     first: to whom, what, about which record, and later whether it went.
--     The database queues it at the moment the fact it announces is
--     written, in the same transaction; a provider sends it afterwards. No
--     provider is wired yet, and the outbox says so rather than pretending.
--   · An applicant who forgets the password asks for a reset by email or
--     JAMB number; the token goes out as a notice, is kept only as a hash,
--     expires in an hour and is used once.
--   · The Board's decision carries its basis — National Merit, State Merit,
--     Equality of Local Government, Locality, Persons Living With
--     Disability — as a value, which is what JAMB's admission template
--     wants in its GENERAL REMARKS column, rather than a note the Board
--     types.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the outbox ──────────────────────────────────────────────────────────
CREATE TABLE platform.notice (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    channel      text NOT NULL,
    recipient    text NOT NULL,
    subject      text NOT NULL,
    body         text NOT NULL,
    about_kind   text NULL,
    about_id     uuid NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    state        text NOT NULL DEFAULT 'QUEUED',
    attempts     int  NOT NULL DEFAULT 0,
    sent_at      timestamptz NULL,
    provider_ref text NULL,
    last_error   text NULL,
    CONSTRAINT ck_notice_channel CHECK (channel IN ('EMAIL','SMS')),
    CONSTRAINT ck_notice_state CHECK (state IN ('QUEUED','SENT','FAILED')),
    CONSTRAINT ck_notice_sent CHECK (state <> 'SENT' OR sent_at IS NOT NULL)
);
CREATE INDEX ix_notice_queued ON platform.notice (created_at) WHERE state = 'QUEUED';
CREATE INDEX ix_notice_about ON platform.notice (about_kind, about_id);
SELECT audit.attach('platform.notice');

COMMENT ON TABLE platform.notice IS
  'The outbox: every notice the portal sends, queued in the transaction that '
  'wrote the fact it announces, and marked when a provider has taken it.';

CREATE OR REPLACE FUNCTION platform.queue_notice(p_channel text, p_recipient text, p_subject text, p_body text, p_about_kind text, p_about_id uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    IF p_recipient IS NULL OR btrim(p_recipient) = '' THEN RETURN NULL; END IF;
    INSERT INTO platform.notice (id, channel, recipient, subject, body, about_kind, about_id)
    VALUES (v, p_channel, btrim(p_recipient), p_subject, p_body, p_about_kind, p_about_id);
    RETURN v;
END $$;

-- the applicant's two channels, from the account
CREATE OR REPLACE FUNCTION admissions.notify_applicant(p_app uuid, p_subject text, p_body text, p_sms text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE acc admissions.applicant_account;
BEGIN
    SELECT acc.* INTO acc FROM admissions.applicant_account acc JOIN admissions.application a ON a.account_id = acc.id WHERE a.id = p_app;
    IF NOT FOUND THEN RETURN; END IF;
    PERFORM platform.queue_notice('EMAIL', acc.email, p_subject, p_body, 'application', p_app);
    PERFORM platform.queue_notice('SMS', acc.phone, p_subject, coalesce(p_sms, p_body), 'application', p_app);
END $$;

-- ── the password reset ──────────────────────────────────────────────────
CREATE TABLE admissions.password_reset (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id uuid NOT NULL REFERENCES admissions.applicant_account(id),
    token_hash text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at    timestamptz NULL
);
CREATE INDEX ix_reset_account ON admissions.password_reset (account_id);
SELECT audit.exempt('admissions.password_reset',
    'Carries the hash of a one-hour token; the request and the change of password are on the spine as applicant events.');

-- ── the basis of the Board's decision ──────────────────────────────────
ALTER TABLE admissions.application ADD COLUMN decision_basis text NULL;
ALTER TABLE admissions.application ADD CONSTRAINT ck_app_basis
    CHECK (decision_basis IS NULL OR decision_basis IN ('NM','SM','ELG','LOCALITY','PLWD','OTHER'));
COMMENT ON COLUMN admissions.application.decision_basis IS
  'National Merit, State Merit, Equality of Local Government, Locality, Persons Living With Disability, Other — '
  'the GENERAL REMARKS of JAMB''s admission template.';

CREATE OR REPLACE FUNCTION admissions.decide_application(p_app uuid, p_decision text, p_note text, p_basis text)
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
    IF p_decision = 'OFFERED' AND p_basis IS NULL THEN
        RAISE EXCEPTION 'an offer is made on a basis' USING ERRCODE = '23514',
            HINT = 'National Merit, State Merit, Equality of Local Government, Locality or Persons Living With Disability — it is what goes back to JAMB.';
    END IF;
    UPDATE admissions.application SET decision = p_decision, decision_note = p_note, decision_basis = p_basis, decided_at = now() WHERE id = p_app;
    RETURN p_decision;
END $$;

-- the three-argument form stands for callers that carry no basis (waiting list, not offered)
CREATE OR REPLACE FUNCTION admissions.decide_application(p_app uuid, p_decision text, p_note text)
RETURNS text
LANGUAGE sql AS $$
    SELECT admissions.decide_application(p_app, p_decision, p_note, CASE WHEN p_decision = 'OFFERED' THEN 'OTHER' ELSE NULL END);
$$;

-- ── the acts of V021, now announced ─────────────────────────────────────

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
        PERFORM admissions.notify_applicant(a.id, 'Your application fee is confirmed',
            'Your payment against reference ' || r.reference || ' has been confirmed by the University. Your application form is now open: sign in and complete it.',
            'MOAUM: payment ' || r.reference || ' confirmed. Your application form is open.');
    ELSE
        UPDATE admissions.application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = a.id;
        PERFORM admissions.settle_acceptance(a.id);
    END IF;
    RETURN 'confirmed';
END $$;

CREATE OR REPLACE FUNCTION admissions.assign_screening(p_batch uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE b admissions.screening_batch; taken int; n int := 0; r record; v_seat text;
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
        v_seat := b.label || '-' || lpad((taken + n)::text, 3, '0');
        UPDATE admissions.application SET screening_batch_id = p_batch, seat = v_seat WHERE id = r.id;
        PERFORM admissions.notify_applicant(r.id, 'Your screening slip is ready',
            'You are in batch ' || b.label || ' on ' || to_char(b.held_on, 'FMDay DD FMMonth YYYY') || ', ' || to_char(b.starts_at, 'HH24:MI')
            || ' to ' || to_char(b.ends_at, 'HH24:MI') || ', at ' || b.venue || ', seat ' || v_seat
            || '. Bring the slip and photo identification. Sign in to print the slip.',
            'MOAUM screening: batch ' || b.label || ', ' || to_char(b.held_on, 'DD Mon') || ' ' || to_char(b.starts_at, 'HH24:MI') || ', ' || b.venue || ', seat ' || v_seat || '.');
    END LOOP;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION admissions.release_scores(p_session text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int := 0; r record;
BEGIN
    FOR r IN SELECT id FROM admissions.application
              WHERE session = p_session AND screening_batch_id IS NOT NULL AND score_released_at IS NULL
    LOOP
        UPDATE admissions.application SET score_released_at = now() WHERE id = r.id;
        n := n + 1;
        PERFORM admissions.notify_applicant(r.id, 'Your screening result is released',
            'The post-UTME screening results for ' || p_session || ' have been released. Sign in to see your score and where you stand.',
            'MOAUM: your screening result is on the portal. Sign in to see it.');
    END LOOP;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION admissions.release_decisions(p_session text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int := 0; r record;
BEGIN
    UPDATE admissions.candidate c SET offer_state = 'ADMITTED'
      FROM admissions.application a
     WHERE a.candidate_id = c.id AND a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NULL
       AND c.offer_state = 'PROPOSED';
    FOR r IN SELECT id, decision FROM admissions.application
              WHERE session = p_session AND decision IS NOT NULL AND decision_released_at IS NULL
    LOOP
        UPDATE admissions.application SET decision_released_at = now() WHERE id = r.id;
        n := n + 1;
        PERFORM admissions.notify_applicant(r.id,
            CASE r.decision WHEN 'OFFERED' THEN 'You have been offered provisional admission'
                            WHEN 'WAITING' THEN 'You are on the waiting list' ELSE 'The admission decision on your application' END,
            CASE r.decision
                WHEN 'OFFERED' THEN 'The Admissions Board has offered you a place. Sign in to accept the offer: sign the undertaking and pay the acceptance fee against the reference the portal generates. An offer that lapses cannot be reinstated.'
                WHEN 'WAITING' THEN 'You are above the cut-off but the approved quota is full. You are offered a place only if an offered candidate fails to accept in time; the portal will tell you the moment that happens.'
                ELSE 'The Admissions Board did not offer you a place this session. Sign in to read the decision.' END,
            CASE r.decision
                WHEN 'OFFERED' THEN 'MOAUM: you have been OFFERED admission. Sign in to accept before the offer lapses.'
                WHEN 'WAITING' THEN 'MOAUM: you are on the waiting list. The portal will tell you if a place opens.'
                ELSE 'MOAUM: the admission decision on your application is on the portal.' END);
    END LOOP;
    RETURN n;
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
        PERFORM admissions.notify_applicant(p_app, 'Your place is held',
            'Your acceptance fee is confirmed and your undertaking is on record. Your place is held. Bring your original documents to the Registry for clearance; nothing is paid at clearance.',
            'MOAUM: your place is held. Bring your original documents to the Registry for clearance.');
    END IF;
END $$;

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
        IF a.cleared_at IS NULL THEN
            PERFORM admissions.notify_applicant(p_app, 'You are cleared',
                'Every document has been seen and verified at the Registry. You may now pay your fees and register your courses under your admission number.',
                'MOAUM: you are cleared. Pay your fees and register your courses under your admission number.');
        END IF;
        UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = p_app;
    ELSE
        UPDATE admissions.application SET cleared_at = NULL WHERE id = p_app;
    END IF;
    IF p_state = 'QUERY' THEN
        PERFORM admissions.notify_applicant(p_app, 'A query on your clearance documents',
            'The Registry has a query on one of your documents: ' || coalesce(p_note, '') || ' Sign in to read it.',
            'MOAUM clearance query: ' || left(coalesce(p_note, ''), 100));
    END IF;
    RETURN verified;
END $$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- V262 — digital academic documents: certificates, transcripts, verification
--
--   V005 built the credential store — a statement kept byte for byte, a
--   verification code no stranger can mis-transcribe, a revocation register
--   that names its minute — and nothing ever wrote to it. V013 built the
--   transcript request and its queue, and the request ended at "released"
--   with no document behind it. This joins them:
--     · a document policy per kind (degree certificate, full, sessional and
--       mini transcript, academic statement): billable or free, the fee, the
--       SLA, self-service, the number format, the fields a stranger may see;
--     · templates with a version, so a document issued under one stays under it;
--     · the statement built from the authoritative record — the courses,
--       units, grades, points, GPA and CGPA the result system already holds,
--       the class the policy band gives, Senate's award — for undergraduates
--       and for postgraduates from their own coursework and research;
--     · the request as a pipeline: paid through the existing reference,
--       validated, generated as a versioned document, checked, authorised by
--       a second officer, delivered by an expiring token or by courier;
--     · the degree certificate issued only to a graduated, Senate-approved,
--       cleared student; revoked with its instrument, reissued as a new
--       version with the old kept; flagged when the record it rests on changes;
--     · verification by code or number, rate-limited by the API, logged, and
--       answering VALID, REVOKED, REPLACED or NOT_FOUND with public fields only;
--     · every act on a trail, every student told, every download logged.
--   The signature column holds the SHA-256 digest of the statement: an
--   integrity hash the verifier recomputes, not a cryptographic signature —
--   the University has no signing key in custody, and a pretended one would
--   be worse than none.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V262: digital academic documents', true);

-- ── 1 · the policy per kind, and the templates ───────────────────────────

CREATE TABLE credentials.document_policy (
    kind            text PRIMARY KEY,
    label           text NOT NULL,
    billable        boolean NOT NULL DEFAULT true,
    fee             numeric(12,2) NULL,          -- NULL: the fee schedule's transcript fee (finance.transcript_fee)
    urgent_fee      numeric(12,2) NOT NULL DEFAULT 0,
    physical_fee    numeric(12,2) NOT NULL DEFAULT 0,
    international_fee numeric(12,2) NOT NULL DEFAULT 0,
    currency        text NOT NULL DEFAULT 'NGN',
    self_service    boolean NOT NULL DEFAULT false,   -- a free kind the student generates at once
    sla_days        int NOT NULL DEFAULT 5,
    urgent_sla_days int NOT NULL DEFAULT 2,
    includes        text NOT NULL DEFAULT 'CUMULATIVE', -- mini-transcript scope: CURRENT_SEMESTER · SELECTED_SEMESTER · SELECTED_SESSION · CUMULATIVE
    number_prefix   text NOT NULL,
    public_fields   text[] NOT NULL DEFAULT ARRAY['holder','programme','award','classOfDegree','faculty','department','graduationSession','graduationDate'],
    graduates_only  boolean NOT NULL DEFAULT false,
    active          boolean NOT NULL DEFAULT true,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dp_kind CHECK (kind IN ('DEGREE_CERTIFICATE','TRANSCRIPT','SESSIONAL_TRANSCRIPT','MINI_TRANSCRIPT','ACADEMIC_STATEMENT')),
    CONSTRAINT ck_dp_includes CHECK (includes IN ('CURRENT_SEMESTER','SELECTED_SEMESTER','SELECTED_SESSION','CUMULATIVE')),
    CONSTRAINT ck_dp_prefix CHECK (number_prefix ~ '^[A-Z]{2,6}$')
);
SELECT audit.attach('credentials.document_policy');
INSERT INTO credentials.document_policy (kind, label, billable, fee, self_service, sla_days, number_prefix, graduates_only, public_fields) VALUES
    ('DEGREE_CERTIFICATE', 'Degree certificate', false, 0, false, 10, 'CERT', true, ARRAY['holder','programme','award','classOfDegree','faculty','department','graduationSession','graduationDate']),
    ('TRANSCRIPT', 'Official full transcript', true, NULL, false, 5, 'TRN', false, ARRAY['holder','programme','faculty','department','award','classOfDegree','graduationSession']),
    ('SESSIONAL_TRANSCRIPT', 'Sessional transcript', true, 2000, false, 3, 'STR', false, ARRAY['holder','programme','faculty','department','session']),
    ('MINI_TRANSCRIPT', 'Mini-transcript', false, 0, true, 1, 'MTR', false, ARRAY['holder','programme','faculty','department']),
    ('ACADEMIC_STATEMENT', 'Statement of academic record', false, 0, true, 1, 'ASR', false, ARRAY['holder','programme','faculty','department','level']);

CREATE TABLE credentials.document_template (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind             text NOT NULL REFERENCES credentials.document_policy(kind),
    version          int  NOT NULL,
    title            text NOT NULL,
    subtitle         text NULL,
    signatory_name   text NOT NULL,
    signatory_title  text NOT NULL,
    second_name      text NULL,
    second_title     text NULL,
    footer           text NULL,
    remarks          text NULL,
    active           boolean NOT NULL DEFAULT true,
    created_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (kind, version)
);
SELECT audit.attach('credentials.document_template');
INSERT INTO credentials.document_template (kind, version, title, subtitle, signatory_name, signatory_title, second_name, second_title, footer) VALUES
    ('DEGREE_CERTIFICATE', 1, 'Degree Certificate', 'By authority of the Senate', 'The Registrar', 'Registrar', 'The Vice-Chancellor', 'Vice-Chancellor', 'This certificate is verified by the QR code and the verification reference it carries.'),
    ('TRANSCRIPT', 1, 'Official Academic Transcript', 'Complete record of study', 'The Registrar', 'Registrar', NULL, NULL, 'Not valid without the verification reference. Grades follow the grading scale in force in each session.'),
    ('SESSIONAL_TRANSCRIPT', 1, 'Sessional Transcript', 'Record of one academic session', 'Deputy Registrar (Exams and Records)', 'Deputy Registrar', NULL, NULL, 'Not valid without the verification reference.'),
    ('MINI_TRANSCRIPT', 1, 'Mini-Transcript', 'Summary of academic performance', 'Exams and Records', 'Deputy Registrar', NULL, NULL, 'Issued from the portal; verify by the reference it carries.'),
    ('ACADEMIC_STATEMENT', 1, 'Statement of Academic Record', 'For a student in progress', 'Exams and Records', 'Deputy Registrar', NULL, NULL, 'This statement is not a transcript; it records the standing of a student still in study.');

-- ── 2 · the document store, extended ─────────────────────────────────────

ALTER TABLE credentials.issued
    ALTER COLUMN signed_with DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS number           text NULL,
    ADD COLUMN IF NOT EXISTS version          int  NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS template_version int  NULL,
    ADD COLUMN IF NOT EXISTS content_hash     text NULL,
    ADD COLUMN IF NOT EXISTS request_id       uuid NULL,
    ADD COLUMN IF NOT EXISTS issued_at        timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS flagged_at       timestamptz NULL,
    ADD COLUMN IF NOT EXISTS flag_reason      text NULL,
    ADD COLUMN IF NOT EXISTS note             text NULL;
ALTER TABLE credentials.issued DROP CONSTRAINT ck_issued_kind;
ALTER TABLE credentials.issued ADD CONSTRAINT ck_issued_kind CHECK (kind IN
    ('DEGREE_CERTIFICATE','TRANSCRIPT','STATEMENT_OF_RESULT','MATRICULATION','SESSIONAL_TRANSCRIPT','MINI_TRANSCRIPT','ACADEMIC_STATEMENT'));
CREATE UNIQUE INDEX uq_issued_number ON credentials.issued (number, version) WHERE number IS NOT NULL;   -- a reissue keeps the number under a new version
CREATE INDEX ix_issued_supersedes ON credentials.issued (supersedes);
CREATE INDEX ix_issued_request ON credentials.issued (request_id);

/* REVOKED by the register; REPLACED when a later version supersedes it; else ACTIVE */
CREATE OR REPLACE FUNCTION credentials.document_status(p_id uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM credentials.revocation r WHERE r.credential_id = p_id) THEN 'REVOKED'
                WHEN EXISTS (SELECT 1 FROM credentials.issued x WHERE x.supersedes = p_id) THEN 'REPLACED'
                ELSE 'ACTIVE' END;
$$;

/* a verification code: 128 bits in Crockford base32, five groups of five, as V005 requires */
CREATE OR REPLACE FUNCTION credentials.new_code()
RETURNS text LANGUAGE plpgsql AS $$
DECLARE alphabet text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; b bytea := gen_random_bytes(25); s text := ''; i int;
BEGIN
    FOR i IN 0..24 LOOP
        s := s || substr(alphabet, (get_byte(b, i) % 32) + 1, 1);
        IF i IN (4, 9, 14, 19) THEN s := s || '-'; END IF;
    END LOOP;
    RETURN s;
END $$;

/* PREFIX/YYYY/NNNNNN: a series per kind and year that never reuses a number */
CREATE OR REPLACE FUNCTION credentials.next_document_number(p_kind text)
RETURNS text LANGUAGE sql AS $$
    SELECT p.number_prefix || '/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/'
           || lpad(platform.next_number('DOCUMENT_' || p_kind, 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 6, '0')
      FROM credentials.document_policy p WHERE p.kind = p_kind;
$$;

-- ── 3 · the request, extended into a pipeline ────────────────────────────

ALTER TABLE credentials.transcript_request
    ADD COLUMN IF NOT EXISTS kind                 text NOT NULL DEFAULT 'TRANSCRIPT' REFERENCES credentials.document_policy(kind),
    ADD COLUMN IF NOT EXISTS session              text NULL,
    ADD COLUMN IF NOT EXISTS semester             int  NULL,
    ADD COLUMN IF NOT EXISTS delivery             text NOT NULL DEFAULT 'DIGITAL',
    ADD COLUMN IF NOT EXISTS international        boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS recipient_department text NULL,
    ADD COLUMN IF NOT EXISTS recipient_name       text NULL,
    ADD COLUMN IF NOT EXISTS recipient_email      text NULL,
    ADD COLUMN IF NOT EXISTS recipient_address    text NULL,
    ADD COLUMN IF NOT EXISTS recipient_reference  text NULL,
    ADD COLUMN IF NOT EXISTS purpose              text NULL,
    ADD COLUMN IF NOT EXISTS fee                  numeric(12,2) NULL,
    ADD COLUMN IF NOT EXISTS reference            text NULL,
    ADD COLUMN IF NOT EXISTS started_at           timestamptz NULL,
    ADD COLUMN IF NOT EXISTS validated_at         timestamptz NULL,
    ADD COLUMN IF NOT EXISTS validation           jsonb NULL,
    ADD COLUMN IF NOT EXISTS qc_at                timestamptz NULL,
    ADD COLUMN IF NOT EXISTS qc_by                uuid NULL,
    ADD COLUMN IF NOT EXISTS qc_note              text NULL,
    ADD COLUMN IF NOT EXISTS delivered_at         timestamptz NULL,
    ADD COLUMN IF NOT EXISTS completed_at         timestamptz NULL,
    ADD COLUMN IF NOT EXISTS closed_at            timestamptz NULL,
    ADD COLUMN IF NOT EXISTS closed_reason        text NULL,
    ADD COLUMN IF NOT EXISTS sla_due_on           date NULL;
ALTER TABLE credentials.transcript_request DROP CONSTRAINT ck_tr_stage;
ALTER TABLE credentials.transcript_request ADD CONSTRAINT ck_tr_stage CHECK (stage IN
    ('AWAITING_PAYMENT','HELD_AT_CLEARANCE','READY','PROCESSING','GENERATED','CORRECTION','VERIFIED','RELEASED','DELIVERED','COMPLETED','REJECTED','CANCELLED'));
ALTER TABLE credentials.transcript_request DROP CONSTRAINT ck_tr_dest;
ALTER TABLE credentials.transcript_request ADD CONSTRAINT ck_tr_dest CHECK (destination IN ('SELF','INSTITUTION','EMPLOYER','EMBASSY','PROFESSIONAL_BODY','OTHER'));
ALTER TABLE credentials.transcript_request ADD CONSTRAINT ck_tr_delivery CHECK (delivery IN ('DIGITAL','PHYSICAL','BOTH'));
ALTER TABLE credentials.transcript_request ADD CONSTRAINT ck_tr_email CHECK (recipient_email IS NULL OR recipient_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
UPDATE credentials.transcript_request SET delivery = CASE WHEN mode = 'SEALED' THEN 'PHYSICAL' ELSE 'DIGITAL' END;
ALTER TABLE credentials.issued ADD CONSTRAINT fk_issued_request FOREIGN KEY (request_id) REFERENCES credentials.transcript_request(id);
CREATE INDEX ix_tr_student ON credentials.transcript_request (student_id, requested_at DESC);
CREATE INDEX ix_tr_stage ON credentials.transcript_request (stage, requested_at);

-- ── 4 · the trail, the deliveries, the tokens, the logs ──────────────────

CREATE TABLE credentials.event (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id   uuid NULL REFERENCES credentials.transcript_request(id) ON DELETE CASCADE,
    issued_id    uuid NULL REFERENCES credentials.issued(id) ON DELETE CASCADE,
    student_id   uuid NULL REFERENCES people.student(id) ON DELETE CASCADE,
    action       text NOT NULL,
    from_state   text NULL,
    to_state     text NULL,
    note         text NULL,
    actor_id     uuid NULL,
    actor_office text NULL,
    at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_cev_request ON credentials.event (request_id, at);
CREATE INDEX ix_cev_issued ON credentials.event (issued_id, at);
CREATE INDEX ix_cev_student ON credentials.event (student_id, at);
SELECT audit.attach('credentials.event');
CREATE OR REPLACE FUNCTION credentials.event_is_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN NEW; END IF;
    RAISE EXCEPTION 'the document trail is written once; it is not edited' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_credentials_event_written_once BEFORE UPDATE ON credentials.event FOR EACH ROW EXECUTE FUNCTION credentials.event_is_written_once();

CREATE OR REPLACE FUNCTION credentials.log(p_request uuid, p_issued uuid, p_student uuid, p_action text, p_from text, p_to text, p_note text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO credentials.event (request_id, issued_id, student_id, action, from_state, to_state, note, actor_id, actor_office)
    VALUES (p_request, p_issued, p_student, p_action, p_from, p_to, p_note,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
$$;

CREATE TABLE credentials.delivery (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    request_id    uuid NOT NULL REFERENCES credentials.transcript_request(id) ON DELETE CASCADE,
    issued_id     uuid NULL REFERENCES credentials.issued(id),
    kind          text NOT NULL,
    state         text NOT NULL DEFAULT 'NOT_SENT',
    recipient     text NULL,
    email         text NULL,
    address       text NULL,
    courier       text NULL,
    tracking_no   text NULL,
    dispatched_on date NULL,
    delivered_on  date NULL,
    token_id      uuid NULL,
    note          text NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_dl_kind CHECK (kind IN ('DIGITAL','PHYSICAL')),
    CONSTRAINT ck_dl_state CHECK (state IN ('NOT_SENT','READY','SENT','DELIVERED','FAILED','EXPIRED','RESENT','PROCESSING','DISPATCHED','IN_TRANSIT','RETURNED'))
);
CREATE INDEX ix_dl_request ON credentials.delivery (request_id);
SELECT audit.attach('credentials.delivery');

CREATE TABLE credentials.download_token (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    issued_id   uuid NOT NULL REFERENCES credentials.issued(id) ON DELETE CASCADE,
    token       text NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(24), 'hex'),
    for_kind    text NOT NULL DEFAULT 'RECIPIENT',
    email       text NULL,
    expires_at  timestamptz NOT NULL,
    max_uses    int  NOT NULL DEFAULT 10,
    uses        int  NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now(),
    revoked_at  timestamptz NULL,
    CONSTRAINT ck_dt_for CHECK (for_kind IN ('STUDENT','RECIPIENT'))
);
CREATE INDEX ix_dt_issued ON credentials.download_token (issued_id);
SELECT audit.attach('credentials.download_token');

CREATE TABLE credentials.download_log (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    issued_id  uuid NOT NULL,
    token_id   uuid NULL,
    actor_id   uuid NULL,
    kind       text NOT NULL,           -- STUDENT · OFFICE · RECIPIENT
    ip         text NULL,
    user_agent text NULL,
    at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_dlog_issued ON credentials.download_log (issued_id, at);
SELECT audit.exempt('credentials.download_log', 'A download by a recipient holding a token has no acting office; the log is telemetry about who fetched a document, kept for the Registry.');

CREATE TABLE credentials.verification (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    key        text NOT NULL,
    issued_id  uuid NULL,
    kind       text NULL,
    status     text NOT NULL,
    ip         text NULL,
    user_agent text NULL,
    at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_cver_at ON credentials.verification (at DESC);
CREATE INDEX ix_cver_issued ON credentials.verification (issued_id, at DESC);
SELECT audit.exempt('credentials.verification', 'Written by the public verification endpoint on behalf of an anonymous stranger; no acting office exists to attribute it to, exactly as credentials.lookup_miss.');

-- ── 5 · who is told ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION credentials.tell(p_student uuid, p_subject text, p_body text, p_sms text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE reach record;
BEGIN
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.queue_notice('EMAIL', reach.email, p_subject, p_body, 'student', p_student);
    PERFORM platform.queue_notice('SMS', reach.phone, p_subject, coalesce(p_sms, left(p_body, 150)), 'student', p_student);
END $$;

CREATE OR REPLACE FUNCTION credentials.tell_desk(p_subject text, p_body text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT DISTINCT pe.id, pe.email FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
         WHERE a.office_code IN ('records','academic') AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND pe.email IS NOT NULL
    LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'person', r.id);
    END LOOP;
END $$;

-- ── 6 · the fee, and the request ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION credentials.fee_for(p_kind text, p_session text, p_delivery text, p_express boolean, p_international boolean, p_copies int)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN NOT p.billable THEN 0 ELSE
              (coalesce(p.fee, CASE WHEN p.kind = 'TRANSCRIPT' THEN finance.transcript_fee(p_session) ELSE 0 END) * greatest(1, coalesce(p_copies, 1)))
              + CASE WHEN p_express THEN p.urgent_fee ELSE 0 END
              + CASE WHEN p_delivery IN ('PHYSICAL','BOTH') THEN p.physical_fee + CASE WHEN p_international THEN p.international_fee ELSE 0 END ELSE 0 END END
      FROM credentials.document_policy p WHERE p.kind = p_kind;
$$;

/* the student asks for a document; a free self-service kind is issued at once, the rest wait for payment then the desk */
CREATE OR REPLACE FUNCTION credentials.request_document(
    p_student uuid, p_kind text, p_session text, p_semester int, p_destination text, p_destination_name text, p_department text, p_recipient text,
    p_email text, p_address text, p_recipient_ref text, p_purpose text, p_delivery text, p_express boolean, p_international boolean, p_copies int)
RETURNS TABLE (id uuid, ref text, fee numeric, reference text, stage text)
LANGUAGE plpgsql AS $$
DECLARE pol credentials.document_policy; st people.student; v_id uuid := gen_random_uuid(); v_ref text; v_fee numeric; v_pay text; v_stage text; v_session text; v_yyyy text;
        v_delivery text := coalesce(upper(p_delivery), 'DIGITAL'); v_issued uuid;
BEGIN
    SELECT * INTO pol FROM credentials.document_policy WHERE kind = p_kind AND active;
    IF pol.kind IS NULL THEN RAISE EXCEPTION 'no such document kind: %', p_kind USING ERRCODE = '23514'; END IF;
    SELECT * INTO st FROM people.student WHERE people.student.id = p_student;
    IF st.id IS NULL THEN RAISE EXCEPTION 'no student record' USING ERRCODE = '23503'; END IF;
    IF st.matric_no IS NULL THEN RAISE EXCEPTION 'a document is issued against a matriculation number; the record has none yet' USING ERRCODE = '23514', HINT = 'Matriculation comes first.'; END IF;
    IF pol.graduates_only AND st.status <> 'GRADUATED' THEN RAISE EXCEPTION '% is issued to a graduated student', pol.label USING ERRCODE = '23514'; END IF;
    IF p_kind = 'SESSIONAL_TRANSCRIPT' AND p_session IS NULL THEN RAISE EXCEPTION 'a sessional transcript names its session' USING ERRCODE = '23514'; END IF;
    IF p_kind = 'SESSIONAL_TRANSCRIPT' AND NOT EXISTS (SELECT 1 FROM assessment.student_results(p_student) r WHERE r.session = p_session AND r.published)
       AND NOT EXISTS (SELECT 1 FROM admissions.pg_registration r WHERE r.student_id = p_student AND r.session = p_session) THEN
        RAISE EXCEPTION 'no published result stands for % ', p_session USING ERRCODE = '23514';
    END IF;
    IF p_destination IN ('INSTITUTION','EMPLOYER','EMBASSY','PROFESSIONAL_BODY','OTHER') AND nullif(btrim(coalesce(p_destination_name, '')), '') IS NULL THEN
        RAISE EXCEPTION 'name the recipient' USING ERRCODE = '23514';
    END IF;
    IF v_delivery IN ('PHYSICAL','BOTH') AND nullif(btrim(coalesce(p_address, '')), '') IS NULL THEN RAISE EXCEPTION 'a physical delivery needs an address' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM credentials.transcript_request t WHERE t.student_id = p_student AND t.kind = p_kind AND t.session IS NOT DISTINCT FROM p_session AND t.semester IS NOT DISTINCT FROM p_semester
               AND t.stage IN ('AWAITING_PAYMENT','READY','HELD_AT_CLEARANCE','PROCESSING','GENERATED','CORRECTION','VERIFIED') AND t.requested_at > now() - interval '1 day') THEN
        RAISE EXCEPTION 'the same request was made within the day and is still in hand' USING ERRCODE = '23505';
    END IF;
    v_session := coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), p_session, '2026/2027');
    v_yyyy := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
    v_ref := 'TRN-' || v_yyyy || '-' || lpad(platform.next_number('TRANSCRIPT', 'UNIVERSITY', v_yyyy)::text, 5, '0');
    v_fee := credentials.fee_for(p_kind, v_session, v_delivery, coalesce(p_express, false), coalesce(p_international, false), p_copies);
    v_stage := CASE WHEN v_fee > 0 THEN 'AWAITING_PAYMENT' WHEN p_kind = 'TRANSCRIPT' AND NOT clearance.is_clear(p_student, 'TRANSCRIPT') THEN 'HELD_AT_CLEARANCE' ELSE 'READY' END;
    INSERT INTO credentials.transcript_request (id, ref, student_id, destination, destination_name, mode, express, copies, kind, session, semester, delivery, international,
                                                recipient_department, recipient_name, recipient_email, recipient_address, recipient_reference, purpose, fee, stage, paid_at, sla_due_on)
    VALUES (v_id, v_ref, p_student, coalesce(p_destination, 'SELF'), nullif(btrim(coalesce(p_destination_name, '')), ''), CASE WHEN v_delivery = 'DIGITAL' THEN 'DIGITAL' ELSE 'SEALED' END,
            coalesce(p_express, false), greatest(1, coalesce(p_copies, 1)), p_kind, p_session, p_semester, v_delivery, coalesce(p_international, false),
            nullif(btrim(coalesce(p_department, '')), ''), nullif(btrim(coalesce(p_recipient, '')), ''), nullif(lower(btrim(coalesce(p_email, ''))), ''), nullif(btrim(coalesce(p_address, '')), ''),
            nullif(btrim(coalesce(p_recipient_ref, '')), ''), nullif(btrim(coalesce(p_purpose, '')), ''), v_fee, v_stage, CASE WHEN v_fee = 0 THEN now() END,
            CASE WHEN v_fee = 0 THEN current_date + CASE WHEN coalesce(p_express, false) THEN pol.urgent_sla_days ELSE pol.sla_days END END);
    IF v_fee > 0 THEN
        v_pay := finance.new_purpose_reference(p_student, v_session, v_fee, 'Transcript ' || v_ref);
        UPDATE credentials.transcript_request SET reference = v_pay WHERE credentials.transcript_request.id = v_id;
    END IF;
    PERFORM credentials.log(v_id, NULL, p_student, 'REQUESTED', NULL, v_stage, pol.label || coalesce(' · ' || p_session, '') || coalesce(' · semester ' || p_semester, '') || ' · ' || v_delivery);
    PERFORM credentials.tell(p_student, 'Document request ' || v_ref || ' submitted',
        'Your request for a ' || lower(pol.label) || ' (' || v_ref || ') has been submitted. '
        || CASE WHEN v_fee > 0 THEN 'An invoice of NGN ' || v_fee::text || ' stands against payment reference ' || v_pay || '; processing begins when it is confirmed.'
                WHEN v_stage = 'HELD_AT_CLEARANCE' THEN 'It is held at clearance until every unit signs.'
                ELSE 'It is with the Exams and Records desk.' END,
        'MOAUM: document request ' || v_ref || ' submitted.' || CASE WHEN v_fee > 0 THEN ' Pay NGN ' || v_fee::text || ' ref ' || v_pay ELSE '' END);
    -- a free self-service kind is issued at once, the desk told after the fact
    IF v_fee = 0 AND pol.self_service AND v_stage = 'READY' THEN
        v_issued := credentials.produce_transcript(v_id);
        UPDATE credentials.transcript_request SET stage = 'RELEASED', released_at = now(), qc_at = now(), qc_note = 'Self-service: issued at once under the policy' WHERE credentials.transcript_request.id = v_id;
        PERFORM credentials.log(v_id, v_issued, p_student, 'RELEASED', 'GENERATED', 'RELEASED', 'Self-service under the policy');
        PERFORM credentials.open_delivery(v_id);
    ELSIF v_fee = 0 THEN
        PERFORM credentials.tell_desk('A document request awaits', 'Request ' || v_ref || ' for a ' || lower(pol.label) || ' is ready for processing.');
    END IF;
    RETURN QUERY SELECT v_id, v_ref, v_fee, v_pay, (SELECT t.stage FROM credentials.transcript_request t WHERE t.id = v_id);
END $$;

CREATE OR REPLACE FUNCTION credentials.cancel_request(p_request uuid, p_student uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE t credentials.transcript_request;
BEGIN
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF t.id IS NULL OR (p_student IS NOT NULL AND t.student_id <> p_student) THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF t.stage NOT IN ('AWAITING_PAYMENT','READY','HELD_AT_CLEARANCE') THEN RAISE EXCEPTION 'request % is %; it is past cancelling', t.ref, lower(replace(t.stage, '_', ' ')) USING ERRCODE = '23514'; END IF;
    UPDATE credentials.transcript_request SET stage = 'CANCELLED', closed_at = now(), closed_reason = p_reason WHERE id = t.id;
    PERFORM credentials.log(t.id, NULL, t.student_id, 'CANCELLED', t.stage, 'CANCELLED', p_reason);
    PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ' cancelled', 'Your request ' || t.ref || ' has been cancelled' || coalesce(': ' || p_reason, '') || '. A paid fee is a Bursary matter for refund.', 'MOAUM: request ' || t.ref || ' cancelled.');
END $$;

-- ── 7 · the statement, built from the record ─────────────────────────────

/* what the record says about a student: undergraduate from the result system, postgraduate from coursework and research */
CREATE OR REPLACE FUNCTION credentials.build_statement(p_student uuid, p_kind text, p_session text, p_semester int)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE st record; g record; pol credentials.document_policy; v_sessions jsonb; v_cgpa numeric; v_class text; v_scope text; v_cur text; v_cur_sem int;
        v_pg boolean; v_research jsonb; v_totals record; v_semesters jsonb;
BEGIN
    SELECT s.id, s.surname, s.other_names, s.matric_no, s.admission_no, s.entry_mode, s.entry_session, s.entry_level, s.current_level, s.status, s.programme_code,
           p.name AS programme, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty, coalesce(p.pg_award, p.name) AS award_name
      INTO st FROM people.student s JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE s.id = p_student;
    IF st.id IS NULL THEN RAISE EXCEPTION 'no student record' USING ERRCODE = '23503'; END IF;
    SELECT * INTO pol FROM credentials.document_policy WHERE kind = p_kind;
    SELECT * INTO g FROM records.graduand gg WHERE gg.student_id = p_student AND gg.senate_state = 'APPROVED' ORDER BY gg.session DESC LIMIT 1;
    v_pg := st.entry_mode = 'POSTGRADUATE' OR EXISTS (SELECT 1 FROM admissions.pg_registration r WHERE r.student_id = p_student);
    v_cur := (SELECT name FROM policy.academic_session WHERE state = 'CURRENT');
    v_cur_sem := (SELECT number FROM policy.semester WHERE session = v_cur AND state = 'OPEN' ORDER BY number DESC LIMIT 1);
    -- the scope of the document
    v_scope := CASE p_kind WHEN 'SESSIONAL_TRANSCRIPT' THEN 'SELECTED_SESSION' WHEN 'MINI_TRANSCRIPT' THEN pol.includes ELSE 'CUMULATIVE' END;
    IF NOT v_pg THEN
        SELECT jsonb_agg(jsonb_build_object('session', q.session, 'semesters', q.semesters) ORDER BY q.session) INTO v_sessions
          FROM (SELECT r.session,
                       jsonb_agg(jsonb_build_object('semester', r.semester, 'courses', r.courses, 'units', gp.units, 'gpa', gp.gpa, 'cgpa', gp.cgpa, 'tcr', gp.tcr, 'tce', gp.tce, 'twgp', gp.twgp) ORDER BY r.semester) AS semesters
                  FROM (SELECT x.session, x.semester,
                               jsonb_agg(jsonb_build_object('code', x.course_code, 'title', x.title, 'units', x.units, 'grade', x.grade, 'points', x.points, 'quality', round(coalesce(x.points, 0) * x.units, 2), 'type', x.entry_type, 'outcome', x.outcome) ORDER BY x.course_code) AS courses
                          FROM assessment.student_results(p_student) x
                         WHERE x.published
                           AND (v_scope = 'CUMULATIVE' OR (v_scope = 'SELECTED_SESSION' AND x.session = p_session)
                                OR (v_scope = 'SELECTED_SEMESTER' AND x.session = p_session AND x.semester = p_semester)
                                OR (v_scope = 'CURRENT_SEMESTER' AND x.session = v_cur AND x.semester = coalesce(v_cur_sem, x.semester)))
                         GROUP BY x.session, x.semester) r
                  LEFT JOIN assessment.student_gpa(p_student) gp ON gp.session = r.session AND gp.semester = r.semester
                 GROUP BY r.session) q;
        SELECT coalesce(max(cgpa) FILTER (WHERE (session, semester) = (SELECT session, semester FROM assessment.student_gpa(p_student) ORDER BY session DESC, semester DESC LIMIT 1)), 0) INTO v_cgpa FROM assessment.student_gpa(p_student);
        IF g.cgpa IS NOT NULL THEN v_cgpa := g.cgpa; END IF;
        v_class := CASE WHEN g.student_id IS NOT NULL THEN coalesce(policy.class_of(g.cgpa), 'Pass') ELSE policy.class_of(v_cgpa) END;
        v_research := NULL;
    ELSE
        SELECT jsonb_agg(jsonb_build_object('session', q.session, 'semesters', q.semesters) ORDER BY q.session) INTO v_sessions
          FROM (SELECT r.session,
                       jsonb_agg(jsonb_build_object('semester', r.semester, 'courses', r.courses, 'units', r.units, 'gpa', admissions.pg_gpa(p_student, r.session, r.semester)) ORDER BY r.semester) AS semesters
                  FROM (SELECT reg.session, reg.semester, sum(c.units) FILTER (WHERE c.kind <> 'DEFICIENCY') AS units,
                               jsonb_agg(jsonb_build_object('code', c.code, 'title', c.title, 'units', c.units, 'grade', sc.grade, 'points', sc.points, 'quality', round(sc.points * c.units, 2), 'type', c.kind) ORDER BY c.code) AS courses
                          FROM admissions.pg_registration reg JOIN admissions.pg_registration_entry e ON e.registration_id = reg.id
                          JOIN admissions.pg_course c ON c.id = e.course_id JOIN admissions.pg_score sc ON sc.entry_id = e.id
                         WHERE reg.student_id = p_student
                           AND (v_scope = 'CUMULATIVE' OR (v_scope = 'SELECTED_SESSION' AND reg.session = p_session)
                                OR (v_scope = 'SELECTED_SEMESTER' AND reg.session = p_session AND reg.semester = p_semester)
                                OR (v_scope = 'CURRENT_SEMESTER' AND reg.session = v_cur))
                         GROUP BY reg.session, reg.semester) r
                 GROUP BY r.session) q;
        v_cgpa := coalesce(g.cgpa, admissions.pg_cgpa(p_student));
        v_class := CASE WHEN g.student_id IS NOT NULL THEN 'Awarded' ELSE NULL END;
        SELECT jsonb_build_object('kind', pr.degree_kind, 'topic', pr.topic, 'stage', pr.stage, 'vivaGrade', pr.viva_grade, 'awardedAt', pr.awarded_at) INTO v_research
          FROM admissions.pg_research pr WHERE pr.student_id = p_student;
    END IF;
    RETURN jsonb_strip_nulls(jsonb_build_object(
        'holder', st.surname || ', ' || st.other_names,
        'matricNo', st.matric_no, 'admissionNo', st.admission_no,
        'programme', st.programme, 'programmeCode', st.programme_code, 'department', st.department, 'faculty', st.faculty,
        'award', CASE WHEN g.student_id IS NOT NULL THEN coalesce(g.award, st.award_name) ELSE st.award_name END,
        'entryMode', st.entry_mode, 'entrySession', st.entry_session, 'entryLevel', st.entry_level, 'level', st.current_level, 'status', st.status,
        'postgraduate', v_pg, 'scope', v_scope, 'session', p_session, 'semester', p_semester,
        'sessions', coalesce(v_sessions, '[]'::jsonb),
        'cgpa', v_cgpa, 'classOfDegree', v_class,
        'standing', CASE WHEN g.student_id IS NOT NULL THEN 'Graduated' WHEN st.status = 'GRADUATED' THEN 'Graduated' ELSE initcap(lower(replace(st.status, '_', ' '))) END,
        'graduationSession', g.session, 'graduationMinute', g.senate_minute,
        'graduationDate', CASE WHEN g.student_id IS NOT NULL THEN (SELECT ends_on FROM policy.academic_session WHERE name = g.session) END,
        'research', v_research,
        'gradingScale', (SELECT jsonb_agg(jsonb_build_object('grade', b.grade, 'low', b.low, 'high', b.high, 'points', b.points) ORDER BY b.points DESC)
                           FROM policy.grade_band b WHERE b.version_id = policy.in_force('grading', 'UNIVERSITY', current_date)),
        'classificationBands', (SELECT jsonb_agg(jsonb_build_object('class', b.class, 'low', b.low, 'high', b.high) ORDER BY b.ord)
                                  FROM policy.classification_band b WHERE b.version_id = policy.in_force('classification', 'UNIVERSITY', current_date))
    ));
END $$;

/* what the desk checks before it generates: the findings, and whether they block */
CREATE OR REPLACE FUNCTION credentials.validate_record(p_student uuid, p_kind text, p_session text, p_semester int)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE st people.student; f jsonb := '[]'::jsonb; v_pub int; v_unpub int; g record; v_pg boolean;
BEGIN
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF st.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'findings', jsonb_build_array(jsonb_build_object('severity', 'ERROR', 'message', 'No student record'))); END IF;
    IF st.matric_no IS NULL THEN f := f || jsonb_build_object('severity', 'ERROR', 'message', 'No matriculation number on the record'); END IF;
    IF NOT EXISTS (SELECT 1 FROM ref.programme WHERE code = st.programme_code) THEN f := f || jsonb_build_object('severity', 'ERROR', 'message', 'The programme is not on the reference list'); END IF;
    IF st.status IN ('EXPELLED','RUSTICATED') THEN f := f || jsonb_build_object('severity', 'ERROR', 'message', 'The student is ' || lower(st.status)); END IF;
    v_pg := st.entry_mode = 'POSTGRADUATE' OR EXISTS (SELECT 1 FROM admissions.pg_registration r WHERE r.student_id = p_student);
    IF NOT v_pg THEN
        SELECT count(*) FILTER (WHERE published), count(*) FILTER (WHERE NOT published) INTO v_pub, v_unpub FROM assessment.student_results(p_student) r
         WHERE p_kind <> 'SESSIONAL_TRANSCRIPT' OR r.session = p_session;
    ELSE
        SELECT count(*), 0 INTO v_pub, v_unpub FROM admissions.pg_registration reg JOIN admissions.pg_registration_entry e ON e.registration_id = reg.id JOIN admissions.pg_score sc ON sc.entry_id = e.id
         WHERE reg.student_id = p_student AND (p_kind <> 'SESSIONAL_TRANSCRIPT' OR reg.session = p_session);
    END IF;
    IF coalesce(v_pub, 0) = 0 THEN f := f || jsonb_build_object('severity', 'ERROR', 'message', 'No published result stands on the record' || CASE WHEN p_kind = 'SESSIONAL_TRANSCRIPT' THEN ' for ' || p_session ELSE '' END); END IF;
    IF coalesce(v_unpub, 0) > 0 THEN f := f || jsonb_build_object('severity', 'WARNING', 'message', v_unpub || ' registered course(s) have no published result yet; the document is issued without them'); END IF;
    SELECT * INTO g FROM records.graduand gg WHERE gg.student_id = p_student ORDER BY gg.session DESC LIMIT 1;
    IF p_kind = 'DEGREE_CERTIFICATE' THEN
        IF st.status <> 'GRADUATED' THEN f := f || jsonb_build_object('severity', 'ERROR', 'message', 'The student record is not GRADUATED'); END IF;
        IF g.student_id IS NULL OR g.senate_state <> 'APPROVED' THEN f := f || jsonb_build_object('severity', 'ERROR', 'message', 'No Senate-approved award stands against the student'); END IF;
        IF NOT clearance.is_clear(p_student, 'CONVOCATION') THEN f := f || jsonb_build_object('severity', 'ERROR', 'message', 'Convocation clearance is incomplete'); END IF;
    ELSIF p_kind = 'TRANSCRIPT' THEN
        IF g.student_id IS NULL THEN f := f || jsonb_build_object('severity', 'WARNING', 'message', 'Not yet graduated: the transcript records study to date');
        ELSIF g.senate_state <> 'APPROVED' THEN f := f || jsonb_build_object('severity', 'WARNING', 'message', 'The award is ' || lower(g.senate_state) || ' at Senate'); END IF;
        IF NOT clearance.is_clear(p_student, 'TRANSCRIPT') THEN f := f || jsonb_build_object('severity', 'ERROR', 'message', 'Transcript clearance is incomplete'); END IF;
    END IF;
    RETURN jsonb_build_object('ok', NOT EXISTS (SELECT 1 FROM jsonb_array_elements(f) e WHERE e->>'severity' = 'ERROR'), 'findings', f, 'published', coalesce(v_pub, 0), 'unpublished', coalesce(v_unpub, 0), 'postgraduate', v_pg, 'checkedAt', now());
END $$;

-- ── 8 · issuing: the versioned document with its hash, code and number ────

CREATE OR REPLACE FUNCTION credentials.issue(p_student uuid, p_kind text, p_request uuid, p_session text, p_semester int, p_supersedes uuid, p_note text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := gen_random_uuid(); v_stmt jsonb; v_hash text; v_tpl int; v_number text; v_version int := 1; v_actor uuid; v_office text; prev credentials.issued;
BEGIN
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a document is issued by a person' USING ERRCODE = '23514'; END IF;
    IF v_office IS NULL OR NOT EXISTS (SELECT 1 FROM ref.office WHERE code = v_office) THEN v_office := 'registrar'; END IF;
    v_stmt := credentials.build_statement(p_student, p_kind, p_session, p_semester);
    SELECT version INTO v_tpl FROM credentials.document_template WHERE kind = p_kind AND active ORDER BY version DESC LIMIT 1;
    IF p_supersedes IS NOT NULL THEN
        SELECT * INTO prev FROM credentials.issued WHERE id = p_supersedes;
        IF prev.id IS NULL THEN RAISE EXCEPTION 'no document to supersede' USING ERRCODE = '23503'; END IF;
        v_version := prev.version + 1;
        v_number := prev.number;
    END IF;
    IF v_number IS NULL THEN v_number := credentials.next_document_number(p_kind); END IF;
    v_stmt := v_stmt || jsonb_build_object('kind', p_kind, 'number', v_number, 'version', v_version, 'templateVersion', v_tpl, 'issuedOn', current_date, 'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi');
    v_hash := encode(sha256(convert_to(v_stmt::text, 'UTF8')), 'hex');
    INSERT INTO credentials.issued (id, kind, student_id, verification_code, statement, signature, signed_with, issuing_name, issued_on, issued_by, issued_office, supersedes,
                                    number, version, template_version, content_hash, request_id, note)
    VALUES (v_id, p_kind, p_student, credentials.new_code(), v_stmt, decode(v_hash, 'hex'), NULL, 'Rev. Fr. Moses Orshio Adasu University, Makurdi', current_date, v_actor, v_office, p_supersedes,
            v_number, v_version, v_tpl, v_hash, p_request, p_note);
    IF p_kind = 'DEGREE_CERTIFICATE' THEN
        UPDATE credentials.certificate SET issued_id = v_id WHERE student_id = p_student AND status <> 'REISSUED' AND issued_id IS NULL;
    END IF;
    PERFORM credentials.log(p_request, v_id, p_student, 'ISSUED', NULL, 'ACTIVE', p_kind || ' ' || v_number || ' v' || v_version || coalesce(' · ' || p_note, ''));
    RETURN v_id;
END $$;

/* a degree certificate: only to a graduated, Senate-approved, cleared student, once */
CREATE OR REPLACE FUNCTION credentials.issue_certificate(p_student uuid, p_note text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE st people.student; g record; v uuid; v_check jsonb;
BEGIN
    SELECT * INTO st FROM people.student WHERE id = p_student;
    IF st.id IS NULL THEN RAISE EXCEPTION 'no student record' USING ERRCODE = '23503'; END IF;
    SELECT * INTO g FROM records.graduand gg WHERE gg.student_id = p_student ORDER BY gg.session DESC LIMIT 1;
    PERFORM credentials.assert_issuable('DEGREE_CERTIFICATE', st.status = 'GRADUATED', g.senate_state = 'APPROVED', clearance.is_clear(p_student, 'CONVOCATION'));
    IF EXISTS (SELECT 1 FROM credentials.issued i WHERE i.student_id = p_student AND i.kind = 'DEGREE_CERTIFICATE' AND credentials.document_status(i.id) = 'ACTIVE') THEN
        RAISE EXCEPTION 'an active degree certificate already stands; revoke or reissue it' USING ERRCODE = '23505';
    END IF;
    v := credentials.issue(p_student, 'DEGREE_CERTIFICATE', NULL, NULL, NULL, NULL, p_note);
    PERFORM credentials.tell(p_student, 'Your digital certificate has been issued',
        'Your degree certificate ' || (SELECT number FROM credentials.issued WHERE id = v) || ' has been issued and is available under My Documents on the portal, with its verification reference.',
        'MOAUM: your digital degree certificate is issued. See My Documents on the portal.');
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION credentials.revoke_document(p_issued uuid, p_reason text, p_instrument text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE i credentials.issued; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    SELECT * INTO i FROM credentials.issued WHERE id = p_issued;
    IF i.id IS NULL THEN RAISE EXCEPTION 'no such document' USING ERRCODE = '23503'; END IF;
    IF EXISTS (SELECT 1 FROM credentials.revocation WHERE credential_id = i.id) THEN RAISE EXCEPTION 'document % is already revoked', i.number USING ERRCODE = '23505'; END IF;
    INSERT INTO credentials.revocation (credential_id, revoked_on, reason, instrument, revoked_by, revoked_office) VALUES (i.id, current_date, p_reason, p_instrument, v_actor, v_office);
    UPDATE credentials.download_token SET revoked_at = now() WHERE issued_id = i.id AND revoked_at IS NULL;
    PERFORM credentials.log(i.request_id, i.id, i.student_id, 'REVOKED', 'ACTIVE', 'REVOKED', p_reason || ' · ' || p_instrument);
    PERFORM credentials.tell(i.student_id, 'A document of yours has been revoked', 'Your ' || lower(replace(i.kind, '_', ' ')) || ' ' || coalesce(i.number, i.verification_code) || ' has been revoked: ' || p_reason || '. Verification now answers REVOKED.', 'MOAUM: document ' || coalesce(i.number, '') || ' revoked.');
END $$;

/* a corrected version: the old stays, marked replaced by the new; the number stays, the code and the hash are new */
CREATE OR REPLACE FUNCTION credentials.reissue_document(p_issued uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE i credentials.issued; v uuid; t credentials.transcript_request;
BEGIN
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a reissue carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO i FROM credentials.issued WHERE id = p_issued;
    IF i.id IS NULL THEN RAISE EXCEPTION 'no such document' USING ERRCODE = '23503'; END IF;
    IF EXISTS (SELECT 1 FROM credentials.issued x WHERE x.supersedes = i.id) THEN RAISE EXCEPTION 'document % has already been replaced', i.number USING ERRCODE = '23505'; END IF;
    IF i.request_id IS NOT NULL THEN SELECT * INTO t FROM credentials.transcript_request WHERE id = i.request_id; END IF;
    v := credentials.issue(i.student_id, i.kind, i.request_id, t.session, t.semester, i.id, 'Reissued: ' || btrim(p_reason));
    UPDATE credentials.download_token SET revoked_at = now() WHERE issued_id = i.id AND revoked_at IS NULL;
    UPDATE credentials.issued SET flagged_at = NULL, flag_reason = NULL WHERE id = i.id;
    IF i.request_id IS NOT NULL THEN UPDATE credentials.transcript_request SET issued_id = v WHERE id = i.request_id; END IF;
    PERFORM credentials.log(i.request_id, i.id, i.student_id, 'REPLACED', 'ACTIVE', 'REPLACED', btrim(p_reason));
    PERFORM credentials.tell(i.student_id, 'A document of yours has been reissued', 'Your ' || lower(replace(i.kind, '_', ' ')) || ' ' || coalesce(i.number, '') || ' has been reissued as version ' || (SELECT version FROM credentials.issued WHERE id = v) || ': ' || btrim(p_reason) || '. The earlier version now verifies as REPLACED; the new one is under My Documents.', 'MOAUM: document ' || coalesce(i.number, '') || ' reissued. See My Documents.');
    RETURN v;
END $$;

-- ── 9 · the pipeline: start, generate, check, authorise, deliver ─────────

CREATE OR REPLACE FUNCTION credentials.start_processing(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t credentials.transcript_request; v jsonb;
BEGIN
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF t.paid_at IS NULL THEN RAISE EXCEPTION 'request % is not paid; processing begins at payment', t.ref USING ERRCODE = '23514'; END IF;
    IF t.stage NOT IN ('READY','HELD_AT_CLEARANCE','PROCESSING','CORRECTION') THEN RAISE EXCEPTION 'request % is %', t.ref, lower(replace(t.stage, '_', ' ')) USING ERRCODE = '23514'; END IF;
    v := credentials.validate_record(t.student_id, t.kind, t.session, t.semester);
    UPDATE credentials.transcript_request SET stage = CASE WHEN t.stage = 'CORRECTION' THEN 'CORRECTION' ELSE 'PROCESSING' END, started_at = coalesce(started_at, now()), validated_at = now(), validation = v WHERE id = t.id;
    PERFORM credentials.log(t.id, NULL, t.student_id, 'VALIDATED', t.stage, 'PROCESSING', CASE WHEN (v->>'ok')::boolean THEN 'The record validates' ELSE 'Findings block generation' END);
    IF t.stage IN ('READY','HELD_AT_CLEARANCE') THEN
        PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ' is being processed', 'Your request ' || t.ref || ' is now being processed: the academic record is being validated before the document is generated.', 'MOAUM: request ' || t.ref || ' is being processed.');
    END IF;
    RETURN v;
END $$;

/* generation: the versioned document from the record; V013's name kept, the request going to GENERATED for the quality check */
DROP FUNCTION IF EXISTS credentials.produce_transcript(uuid);
CREATE OR REPLACE FUNCTION credentials.produce_transcript(p_request uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE t credentials.transcript_request; v jsonb; v_id uuid; prev uuid;
BEGIN
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no transcript request %', p_request USING ERRCODE = 'no_data_found'; END IF;
    IF t.paid_at IS NULL THEN
        RAISE EXCEPTION 'request % is not payable yet: the SLA clock runs from payment, and production does', t.ref USING ERRCODE = 'check_violation';
    END IF;
    IF t.kind = 'TRANSCRIPT' AND NOT clearance.is_clear(t.student_id, 'TRANSCRIPT') THEN
        RAISE EXCEPTION 'request % is held at clearance', t.ref USING ERRCODE = 'check_violation',
              HINT = 'A unit holds the candidate. The transcript is blocked while any unit does; the student sees which.';
    END IF;
    IF t.stage NOT IN ('READY','HELD_AT_CLEARANCE','PROCESSING','CORRECTION') THEN
        RAISE EXCEPTION 'request % is %', t.ref, lower(replace(t.stage, '_', ' ')) USING ERRCODE = 'check_violation';
    END IF;
    v := credentials.validate_record(t.student_id, t.kind, t.session, t.semester);
    IF NOT (v->>'ok')::boolean THEN RAISE EXCEPTION 'the record does not validate: %', (SELECT string_agg(e->>'message', '; ') FROM jsonb_array_elements(v->'findings') e WHERE e->>'severity' = 'ERROR') USING ERRCODE = '23514'; END IF;
    prev := t.issued_id;
    v_id := credentials.issue(t.student_id, t.kind, t.id, t.session, t.semester, prev, CASE WHEN prev IS NULL THEN NULL ELSE 'Regenerated after correction' END);
    UPDATE credentials.transcript_request SET stage = 'GENERATED', produced_at = now(), produced_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           validated_at = coalesce(validated_at, now()), validation = coalesce(validation, v), started_at = coalesce(started_at, now()), issued_id = v_id WHERE id = t.id;
    PERFORM credentials.log(t.id, v_id, t.student_id, 'GENERATED', t.stage, 'GENERATED', 'Version ' || (SELECT version FROM credentials.issued WHERE id = v_id));
    PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ': document generated', 'The document for your request ' || t.ref || ' has been generated and is with the quality check before authorisation.', 'MOAUM: request ' || t.ref || ' generated; quality check next.');
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION credentials.qc_transcript(p_request uuid, p_decision text, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE t credentials.transcript_request; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF p_decision NOT IN ('APPROVED','CORRECTION','REJECTED') THEN RAISE EXCEPTION 'the quality check approves, asks for a correction or rejects' USING ERRCODE = '23514'; END IF;
    IF p_decision <> 'APPROVED' AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN RAISE EXCEPTION 'say why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF t.stage <> 'GENERATED' THEN RAISE EXCEPTION 'request % is %; the quality check is of a generated document', t.ref, lower(replace(t.stage, '_', ' ')) USING ERRCODE = '23514'; END IF;
    UPDATE credentials.transcript_request SET stage = CASE p_decision WHEN 'APPROVED' THEN 'VERIFIED' WHEN 'CORRECTION' THEN 'CORRECTION' ELSE 'REJECTED' END, qc_at = now(), qc_by = v_actor, qc_note = p_note,
           closed_at = CASE WHEN p_decision = 'REJECTED' THEN now() END, closed_reason = CASE WHEN p_decision = 'REJECTED' THEN p_note END WHERE id = t.id;
    PERFORM credentials.log(t.id, t.issued_id, t.student_id, 'QUALITY_CHECK', 'GENERATED', p_decision, p_note);
    IF p_decision = 'CORRECTION' THEN
        PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ': correction in hand', 'The quality check on request ' || t.ref || ' asked for a correction: ' || p_note || '. The document will be regenerated.', 'MOAUM: request ' || t.ref || ' — correction in hand.');
    ELSIF p_decision = 'REJECTED' THEN
        PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ' rejected', 'Request ' || t.ref || ' was rejected at the quality check: ' || p_note || '. A paid fee is a Bursary matter.', 'MOAUM: request ' || t.ref || ' rejected: ' || left(p_note, 80));
    ELSE
        PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ' approved', 'The document for request ' || t.ref || ' passed the quality check and awaits the Registrar''s authorisation for release.', 'MOAUM: request ' || t.ref || ' approved; release next.');
    END IF;
END $$;

/* the deliveries a released request needs: a token for the student and one for the recipient, or a courier record */
CREATE OR REPLACE FUNCTION credentials.open_delivery(p_request uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE t credentials.transcript_request; tok uuid; tok_r uuid; v_days int; reach record;
BEGIN
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request;
    IF t.issued_id IS NULL THEN RAISE EXCEPTION 'nothing to deliver' USING ERRCODE = '23514'; END IF;
    v_days := 30;
    IF t.delivery IN ('DIGITAL','BOTH') THEN
        INSERT INTO credentials.download_token (issued_id, for_kind, expires_at, max_uses) VALUES (t.issued_id, 'STUDENT', now() + make_interval(days => v_days), 50) RETURNING id INTO tok;
        INSERT INTO credentials.delivery (request_id, issued_id, kind, state, recipient, email, token_id, note)
        VALUES (t.id, t.issued_id, 'DIGITAL', 'READY', 'Student', NULL, tok, 'Secure download on the portal, ' || v_days || ' days');
        IF t.recipient_email IS NOT NULL THEN
            INSERT INTO credentials.download_token (issued_id, for_kind, email, expires_at, max_uses) VALUES (t.issued_id, 'RECIPIENT', t.recipient_email, now() + make_interval(days => v_days), 10) RETURNING id INTO tok_r;
            INSERT INTO credentials.delivery (request_id, issued_id, kind, state, recipient, email, token_id, note)
            VALUES (t.id, t.issued_id, 'DIGITAL', 'SENT', coalesce(t.recipient_name, t.destination_name), t.recipient_email, tok_r, 'Secure expiring link sent by email');
            PERFORM platform.queue_notice('EMAIL', t.recipient_email, 'An official document from Rev. Fr. Moses Orshio Adasu University',
                'The University has issued an official ' || lower(replace(t.kind, '_', ' ')) || ' at the request of ' || (SELECT surname || ', ' || other_names FROM people.student WHERE id = t.student_id)
                || coalesce(' (your reference ' || t.recipient_reference || ')', '') || '. Open the secure link on the portal under /documents/d/' || (SELECT token FROM credentials.download_token WHERE id = tok_r)
                || ' — it expires in ' || v_days || ' days. Verify the document by its reference on the University''s verification page.', 'document', t.issued_id);
        END IF;
    END IF;
    IF t.delivery IN ('PHYSICAL','BOTH') THEN
        INSERT INTO credentials.delivery (request_id, issued_id, kind, state, recipient, address, note)
        VALUES (t.id, t.issued_id, 'PHYSICAL', 'PROCESSING', coalesce(t.recipient_name, t.destination_name, 'Student'), t.recipient_address, 'Sealed copy to be dispatched');
    END IF;
END $$;

/* authorisation and release, by an officer other than the producer (BR-006); the deliveries open, the student told */
CREATE OR REPLACE FUNCTION credentials.release_transcript(p_request uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE t credentials.transcript_request; v_actor uuid;
BEGIN
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no transcript request %', p_request USING ERRCODE = 'no_data_found'; END IF;
    IF t.stage <> 'VERIFIED' THEN RAISE EXCEPTION 'request % has not been produced and verified', t.ref USING ERRCODE = 'check_violation'; END IF;
    IF t.produced_by = v_actor THEN
        RAISE EXCEPTION 'the officer who produced a transcript does not sign it' USING ERRCODE = 'check_violation', HINT = 'BR-006. The Registrar signs what Exams & Records verified.';
    END IF;
    UPDATE credentials.transcript_request SET stage = 'RELEASED', released_at = now(), released_by = v_actor WHERE id = p_request;
    PERFORM credentials.log(t.id, t.issued_id, t.student_id, 'RELEASED', 'VERIFIED', 'RELEASED', NULL);
    PERFORM credentials.open_delivery(t.id);
    PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ': your document is ready',
        'Your ' || lower(replace(t.kind, '_', ' ')) || ' (' || t.ref || ') has been authorised and is ready for secure download under My Documents on the portal.'
        || CASE WHEN t.recipient_email IS NOT NULL THEN ' A secure expiring link has been sent to ' || t.recipient_email || '.' ELSE '' END
        || CASE WHEN t.delivery IN ('PHYSICAL','BOTH') THEN ' The sealed copy is being prepared for dispatch.' ELSE '' END,
        'MOAUM: your document for ' || t.ref || ' is ready under My Documents.');
END $$;

CREATE OR REPLACE FUNCTION credentials.mark_delivery(p_delivery uuid, p_state text, p_courier text, p_tracking text, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE d credentials.delivery; t credentials.transcript_request; v_open int;
BEGIN
    SELECT * INTO d FROM credentials.delivery WHERE id = p_delivery FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such delivery' USING ERRCODE = '23503'; END IF;
    UPDATE credentials.delivery SET state = p_state, courier = coalesce(p_courier, courier), tracking_no = coalesce(p_tracking, tracking_no), note = coalesce(p_note, note),
           dispatched_on = CASE WHEN p_state IN ('DISPATCHED','IN_TRANSIT','SENT','RESENT') THEN coalesce(dispatched_on, current_date) ELSE dispatched_on END,
           delivered_on = CASE WHEN p_state = 'DELIVERED' THEN coalesce(delivered_on, current_date) ELSE delivered_on END, updated_at = now() WHERE id = d.id;
    SELECT * INTO t FROM credentials.transcript_request WHERE id = d.request_id;
    PERFORM credentials.log(t.id, d.issued_id, t.student_id, 'DELIVERY', d.state, p_state, coalesce(p_note, '') || coalesce(' · ' || p_courier, '') || coalesce(' ' || p_tracking, ''));
    IF p_state = 'FAILED' OR p_state = 'RETURNED' THEN
        PERFORM credentials.tell(t.student_id, 'Delivery of ' || t.ref || ' failed', 'The ' || lower(d.kind) || ' delivery of your document for ' || t.ref || ' did not succeed' || coalesce(': ' || p_note, '') || '. The desk will contact you.', 'MOAUM: delivery of ' || t.ref || ' failed.');
        PERFORM credentials.tell_desk('A document delivery failed', 'Delivery for request ' || t.ref || ' is ' || lower(p_state) || coalesce(': ' || p_note, ''));
    END IF;
    SELECT count(*) INTO v_open FROM credentials.delivery WHERE request_id = t.id AND state NOT IN ('DELIVERED','SENT','READY');
    IF v_open = 0 AND t.stage = 'RELEASED' AND EXISTS (SELECT 1 FROM credentials.delivery WHERE request_id = t.id AND state = 'DELIVERED') THEN
        UPDATE credentials.transcript_request SET stage = 'DELIVERED', delivered_at = now() WHERE id = t.id;
        PERFORM credentials.log(t.id, d.issued_id, t.student_id, 'DELIVERED', 'RELEASED', 'DELIVERED', NULL);
        PERFORM credentials.tell(t.student_id, 'Document request ' || t.ref || ' delivered', 'Every delivery for request ' || t.ref || ' is recorded as delivered.', 'MOAUM: request ' || t.ref || ' delivered.');
    END IF;
END $$;

CREATE OR REPLACE FUNCTION credentials.complete_request(p_request uuid, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE t credentials.transcript_request;
BEGIN
    SELECT * INTO t FROM credentials.transcript_request WHERE id = p_request FOR UPDATE;
    IF t.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF t.stage NOT IN ('RELEASED','DELIVERED') THEN RAISE EXCEPTION 'request % is %', t.ref, lower(replace(t.stage, '_', ' ')) USING ERRCODE = '23514'; END IF;
    UPDATE credentials.transcript_request SET stage = 'COMPLETED', completed_at = now(), closed_at = now(), closed_reason = p_note WHERE id = t.id;
    PERFORM credentials.log(t.id, t.issued_id, t.student_id, 'COMPLETED', t.stage, 'COMPLETED', p_note);
END $$;

/* a payment confirmed (by V033's confirm_payment) is a step on the trail and starts the SLA clock */
CREATE OR REPLACE FUNCTION credentials.request_paid()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pol credentials.document_policy;
BEGIN
    IF NEW.paid_at IS NOT NULL AND OLD.paid_at IS NULL THEN
        SELECT * INTO pol FROM credentials.document_policy WHERE kind = NEW.kind;
        NEW.sla_due_on := coalesce(NEW.sla_due_on, current_date + CASE WHEN NEW.express THEN coalesce(pol.urgent_sla_days, 2) ELSE coalesce(pol.sla_days, 5) END);
        INSERT INTO credentials.event (request_id, student_id, action, from_state, to_state, note, actor_id, actor_office)
        VALUES (NEW.id, NEW.student_id, 'PAID', OLD.stage, NEW.stage, 'Payment confirmed' || coalesce(' · ' || NEW.reference, ''), nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_transcript_request_paid BEFORE UPDATE OF paid_at ON credentials.transcript_request FOR EACH ROW EXECUTE FUNCTION credentials.request_paid();

-- ── 10 · tokens, downloads, verification ─────────────────────────────────

CREATE OR REPLACE FUNCTION credentials.new_download_token(p_issued uuid, p_student uuid, p_days int)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE i credentials.issued; v text;
BEGIN
    SELECT * INTO i FROM credentials.issued WHERE id = p_issued;
    IF i.id IS NULL OR (p_student IS NOT NULL AND i.student_id <> p_student) THEN RAISE EXCEPTION 'no such document' USING ERRCODE = '23503'; END IF;
    IF credentials.document_status(i.id) <> 'ACTIVE' THEN RAISE EXCEPTION 'document % is %; no link is made for it', coalesce(i.number, ''), lower(credentials.document_status(i.id)) USING ERRCODE = '23514'; END IF;
    INSERT INTO credentials.download_token (issued_id, for_kind, expires_at, max_uses) VALUES (i.id, 'STUDENT', now() + make_interval(days => greatest(1, least(coalesce(p_days, 7), 90))), 20) RETURNING token INTO v;
    PERFORM credentials.log(i.request_id, i.id, i.student_id, 'LINK_MADE', NULL, NULL, 'Secure link for ' || greatest(1, least(coalesce(p_days, 7), 90)) || ' day(s)');
    RETURN v;
END $$;

/* a token spent: the statement comes back, or the reason it does not */
CREATE OR REPLACE FUNCTION credentials.consume_token(p_token text, p_ip text, p_agent text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE tk credentials.download_token; i credentials.issued; st text;
BEGIN
    -- a recipient holding a token has no office; the spend is the portal's own act, attributed to it
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true), set_config('moaum.actor_office', 'registrar', true), set_config('moaum.reason', 'Document fetched by a recipient holding a secure link', true);
    END IF;
    SELECT * INTO tk FROM credentials.download_token WHERE token = p_token FOR UPDATE;
    IF tk.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'why', 'NOT_FOUND'); END IF;
    IF tk.revoked_at IS NOT NULL THEN RETURN jsonb_build_object('ok', false, 'why', 'REVOKED'); END IF;
    IF tk.expires_at < now() THEN RETURN jsonb_build_object('ok', false, 'why', 'EXPIRED'); END IF;
    IF tk.uses >= tk.max_uses THEN RETURN jsonb_build_object('ok', false, 'why', 'EXHAUSTED'); END IF;
    SELECT * INTO i FROM credentials.issued WHERE id = tk.issued_id;
    st := credentials.document_status(i.id);
    IF st <> 'ACTIVE' THEN RETURN jsonb_build_object('ok', false, 'why', st); END IF;
    UPDATE credentials.download_token SET uses = uses + 1 WHERE id = tk.id;
    INSERT INTO credentials.download_log (issued_id, token_id, kind, ip, user_agent) VALUES (i.id, tk.id, tk.for_kind, p_ip, p_agent);
    UPDATE credentials.delivery SET state = 'DELIVERED', delivered_on = coalesce(delivered_on, current_date), updated_at = now() WHERE token_id = tk.id AND state IN ('READY','SENT','RESENT');
    RETURN jsonb_build_object('ok', true, 'id', i.id, 'kind', i.kind, 'number', i.number, 'version', i.version, 'code', i.verification_code, 'issuedOn', i.issued_on, 'templateVersion', i.template_version, 'statement', i.statement, 'forKind', tk.for_kind);
END $$;

CREATE OR REPLACE FUNCTION credentials.record_download(p_issued uuid, p_actor uuid, p_kind text, p_ip text, p_agent text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO credentials.download_log (issued_id, actor_id, kind, ip, user_agent) VALUES (p_issued, p_actor, p_kind, p_ip, p_agent);
$$;

/* V005's verify, now also answering REPLACED; the suite's assertions on VALID and REVOKED hold */
CREATE OR REPLACE FUNCTION credentials.verify(p_code text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c credentials.issued; r credentials.revocation; now_name text := 'Rev. Fr. Moses Orshio Adasu University, Makurdi'; v_status text;
BEGIN
    SELECT * INTO c FROM credentials.issued WHERE verification_code = upper(btrim(p_code));
    IF NOT FOUND THEN
        INSERT INTO credentials.lookup_miss (code, looked_up_at) VALUES (left(upper(btrim(p_code)), 40), now());
        RETURN jsonb_build_object('status', 'NOT_FOUND', 'currentInstitutionName', now_name,
            'remedy', 'No credential bears this code. If you hold a document showing it, it was not issued by this University. The Registry will take a report.',
            'verifiedAt', to_jsonb(now()));
    END IF;
    SELECT * INTO r FROM credentials.revocation WHERE credential_id = c.id;
    v_status := CASE WHEN r.credential_id IS NOT NULL THEN 'REVOKED' WHEN EXISTS (SELECT 1 FROM credentials.issued x WHERE x.supersedes = c.id) THEN 'REPLACED' ELSE 'VALID' END;
    RETURN c.statement
        || jsonb_build_object('status', v_status, 'issuingInstitution', c.issuing_name, 'currentInstitutionName', now_name, 'verifiedAt', to_jsonb(now()),
                              'kind', c.kind, 'number', c.number, 'version', c.version, 'issuedOn', c.issued_on, 'contentHash', c.content_hash)
        || CASE WHEN r.credential_id IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('revokedOn', r.revoked_on, 'revokedUnder', r.instrument) END;
END $$;

/* what a stranger sees: by code or by document number; only the fields the policy names, the status, and nothing private */
CREATE OR REPLACE FUNCTION credentials.verify_document(p_key text, p_ip text, p_agent text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE k text := upper(btrim(coalesce(p_key, ''))); c credentials.issued; full_v jsonb; pol credentials.document_policy; out jsonb; f text; v_status text; v_hash_ok boolean;
BEGIN
    IF k = '' THEN RETURN jsonb_build_object('status', 'INVALID'); END IF;
    SELECT * INTO c FROM credentials.issued WHERE verification_code = k;
    IF c.id IS NULL THEN
        -- a document number names every version; the current one answers
        SELECT * INTO c FROM credentials.issued WHERE upper(number) = k ORDER BY version DESC LIMIT 1;
    END IF;
    IF c.id IS NULL THEN
        full_v := credentials.verify(k);
        INSERT INTO credentials.verification (key, status, ip, user_agent) VALUES (left(k, 60), 'NOT_FOUND', p_ip, p_agent);
        RETURN jsonb_build_object('status', 'NOT_FOUND', 'remedy', full_v->>'remedy', 'verifiedAt', now());
    END IF;
    full_v := credentials.verify(c.verification_code);
    v_status := full_v->>'status';
    v_hash_ok := c.content_hash IS NULL OR c.content_hash = encode(sha256(convert_to(c.statement::text, 'UTF8')), 'hex');
    IF NOT v_hash_ok THEN v_status := 'INVALID'; END IF;
    SELECT * INTO pol FROM credentials.document_policy WHERE kind = c.kind;
    out := jsonb_build_object('status', v_status, 'kind', c.kind, 'kindLabel', coalesce(pol.label, c.kind), 'number', c.number, 'version', c.version, 'issuedOn', c.issued_on,
                              'issuingInstitution', c.issuing_name, 'currentInstitutionName', full_v->>'currentInstitutionName', 'issuingAuthority', c.statement->>'issuingAuthority',
                              'verificationCode', c.verification_code, 'verifiedAt', now());
    IF v_status = 'REVOKED' THEN out := out || jsonb_build_object('revokedOn', full_v->'revokedOn', 'revokedUnder', full_v->'revokedUnder'); END IF;
    IF v_status = 'REPLACED' THEN out := out || jsonb_build_object('replacedBy', (SELECT 'version ' || x.version || ' issued ' || x.issued_on FROM credentials.issued x WHERE x.supersedes = c.id LIMIT 1)); END IF;
    FOREACH f IN ARRAY coalesce(pol.public_fields, ARRAY[]::text[]) LOOP
        IF c.statement ? f THEN out := out || jsonb_build_object(f, c.statement->f); END IF;
    END LOOP;
    INSERT INTO credentials.verification (key, issued_id, kind, status, ip, user_agent) VALUES (left(k, 60), c.id, c.kind, v_status, p_ip, p_agent);
    RETURN out;
END $$;

-- ── 11 · a record that changes after issue flags the documents it stands under ──

CREATE OR REPLACE FUNCTION credentials.flag_documents(p_student uuid, p_kinds text[], p_reason text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    UPDATE credentials.issued i SET flagged_at = now(), flag_reason = p_reason
     WHERE i.student_id = p_student AND i.kind = ANY (p_kinds) AND i.flagged_at IS NULL AND credentials.document_status(i.id) = 'ACTIVE';
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN
        PERFORM credentials.log(NULL, i.id, p_student, 'FLAGGED', NULL, NULL, p_reason) FROM credentials.issued i WHERE i.student_id = p_student AND i.kind = ANY (p_kinds) AND i.flag_reason = p_reason AND i.flagged_at >= now() - interval '1 second';
        PERFORM credentials.tell_desk('An issued document may need review', n || ' document(s) of a student are flagged: ' || p_reason || '. Review them on the documents register.');
    END IF;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION credentials.score_changed()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM credentials.issued i WHERE i.student_id = NEW.student_id AND i.kind IN ('TRANSCRIPT','SESSIONAL_TRANSCRIPT','MINI_TRANSCRIPT','ACADEMIC_STATEMENT','DEGREE_CERTIFICATE') AND i.flagged_at IS NULL) THEN
        PERFORM credentials.flag_documents(NEW.student_id, ARRAY['TRANSCRIPT','SESSIONAL_TRANSCRIPT','MINI_TRANSCRIPT','ACADEMIC_STATEMENT'], 'A result of the student changed after issue');
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_score_flags_documents AFTER INSERT OR UPDATE ON assessment.score FOR EACH ROW EXECUTE FUNCTION credentials.score_changed();

CREATE OR REPLACE FUNCTION credentials.graduand_changed()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF (NEW.cgpa IS DISTINCT FROM OLD.cgpa OR NEW.award IS DISTINCT FROM OLD.award OR NEW.session IS DISTINCT FROM OLD.session)
       AND EXISTS (SELECT 1 FROM credentials.issued i WHERE i.student_id = NEW.student_id AND i.kind IN ('DEGREE_CERTIFICATE','TRANSCRIPT') AND i.flagged_at IS NULL) THEN
        PERFORM credentials.flag_documents(NEW.student_id, ARRAY['DEGREE_CERTIFICATE','TRANSCRIPT'], 'The award on the record changed after issue');
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_graduand_flags_documents AFTER UPDATE ON records.graduand FOR EACH ROW EXECUTE FUNCTION credentials.graduand_changed();

CREATE OR REPLACE FUNCTION credentials.clear_flag(p_issued uuid, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE credentials.issued SET flagged_at = NULL, flag_reason = NULL WHERE id = p_issued;
    PERFORM credentials.log(NULL, p_issued, (SELECT student_id FROM credentials.issued WHERE id = p_issued), 'FLAG_CLEARED', NULL, NULL, p_note);
END $$;

-- ── 12 · what the desks read ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION credentials.request_rows(p_session text)
RETURNS TABLE (id uuid, ref text, kind text, kind_label text, stage text, delivery text, destination text, destination_name text, recipient_email text, express boolean, copies int, session text, semester int,
               fee numeric, reference text, paid_at timestamptz, requested_at timestamptz, started_at timestamptz, validated_at timestamptz, produced_at timestamptz, qc_at timestamptz, released_at timestamptz, delivered_at timestamptz, completed_at timestamptz, closed_at timestamptz, closed_reason text,
               sla_due_on date, breaching boolean, issued_id uuid, document_number text, document_version int, document_status text, verification_code text,
               student_id uuid, student_name text, student_number text, programme text, programme_code text, dept_code text, department text, faculty_code text, faculty text, level int, student_status text,
               payment_status text, receipt_no text, deliveries_open int)
LANGUAGE sql STABLE AS $$
    SELECT t.id, t.ref, t.kind, p.label, t.stage, t.delivery, t.destination, t.destination_name, t.recipient_email, t.express, t.copies, t.session, t.semester,
           t.fee, t.reference, t.paid_at, t.requested_at, t.started_at, t.validated_at, t.produced_at, t.qc_at, t.released_at, t.delivered_at, t.completed_at, t.closed_at, t.closed_reason,
           t.sla_due_on, t.sla_due_on IS NOT NULL AND t.sla_due_on < current_date AND t.stage NOT IN ('RELEASED','DELIVERED','COMPLETED','REJECTED','CANCELLED'),
           i.id, i.number, i.version, CASE WHEN i.id IS NULL THEN NULL ELSE credentials.document_status(i.id) END, i.verification_code,
           st.id, st.surname || ', ' || st.other_names, coalesce(st.matric_no, st.admission_no), pr.name, pr.code, d.code, d.name, f.code, f.name, st.current_level, st.status,
           CASE WHEN t.paid_at IS NOT NULL THEN 'PAID' WHEN t.fee = 0 THEN 'FREE' WHEN pf.id IS NOT NULL AND pf.expires_at > now() THEN 'PENDING' WHEN t.fee > 0 THEN 'UNPAID' ELSE 'FREE' END,
           pf.receipt_no,
           (SELECT count(*) FROM credentials.delivery dl WHERE dl.request_id = t.id AND dl.state NOT IN ('DELIVERED','FAILED','RETURNED','EXPIRED'))::int
      FROM credentials.transcript_request t
      JOIN credentials.document_policy p ON p.kind = t.kind
      JOIN people.student st ON st.id = t.student_id
      LEFT JOIN ref.programme pr ON pr.code = st.programme_code LEFT JOIN ref.department d ON d.code = pr.dept_code LEFT JOIN ref.faculty f ON f.code = pr.faculty_code
      LEFT JOIN credentials.issued i ON i.id = t.issued_id
      LEFT JOIN finance.payment_reference pf ON pf.reference = t.reference
     WHERE p_session IS NULL OR t.session = p_session OR to_char(t.requested_at, 'YYYY') = left(p_session, 4)
     ORDER BY st.surname, st.other_names, t.requested_at DESC;
$$;

CREATE OR REPLACE FUNCTION credentials.document_rows()
RETURNS TABLE (id uuid, kind text, kind_label text, number text, version int, status text, verification_code text, issued_on date, issued_at timestamptz, issued_office text, template_version int, flagged_at timestamptz, flag_reason text,
               supersedes uuid, request_id uuid, request_ref text, student_id uuid, student_name text, student_number text, programme text, department text, faculty text,
               holder text, award text, class_of_degree text, graduation_session text, downloads bigint, verifications bigint, revoked_on date, revoked_reason text)
LANGUAGE sql STABLE AS $$
    SELECT i.id, i.kind, coalesce(p.label, i.kind), i.number, i.version, credentials.document_status(i.id), i.verification_code, i.issued_on, i.issued_at, i.issued_office, i.template_version, i.flagged_at, i.flag_reason,
           i.supersedes, i.request_id, t.ref, st.id, st.surname || ', ' || st.other_names, coalesce(st.matric_no, st.admission_no), pr.name, d.name, f.name,
           i.statement->>'holder', i.statement->>'award', i.statement->>'classOfDegree', i.statement->>'graduationSession',
           (SELECT count(*) FROM credentials.download_log l WHERE l.issued_id = i.id), (SELECT count(*) FROM credentials.verification v WHERE v.issued_id = i.id), r.revoked_on, r.reason
      FROM credentials.issued i
      LEFT JOIN credentials.document_policy p ON p.kind = i.kind
      LEFT JOIN credentials.transcript_request t ON t.id = i.request_id
      LEFT JOIN people.student st ON st.id = i.student_id
      LEFT JOIN ref.programme pr ON pr.code = st.programme_code LEFT JOIN ref.department d ON d.code = pr.dept_code LEFT JOIN ref.faculty f ON f.code = pr.faculty_code
      LEFT JOIN credentials.revocation r ON r.credential_id = i.id
     ORDER BY st.surname NULLS LAST, st.other_names, i.issued_at DESC;
$$;

CREATE OR REPLACE FUNCTION credentials.office_dashboard()
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH r AS (SELECT * FROM credentials.request_rows(NULL)), i AS (SELECT * FROM credentials.document_rows())
    SELECT jsonb_build_object(
        'requests', jsonb_build_object(
            'new', (SELECT count(*) FROM r WHERE stage IN ('READY','HELD_AT_CLEARANCE') AND started_at IS NULL),
            'payment_pending', (SELECT count(*) FROM r WHERE stage = 'AWAITING_PAYMENT'),
            'paid', (SELECT count(*) FROM r WHERE paid_at IS NOT NULL AND stage NOT IN ('COMPLETED','REJECTED','CANCELLED')),
            'held', (SELECT count(*) FROM r WHERE stage = 'HELD_AT_CLEARANCE'),
            'processing', (SELECT count(*) FROM r WHERE stage IN ('PROCESSING','CORRECTION')),
            'generated', (SELECT count(*) FROM r WHERE stage = 'GENERATED'),
            'quality_check', (SELECT count(*) FROM r WHERE stage = 'GENERATED'),
            'approved', (SELECT count(*) FROM r WHERE stage = 'VERIFIED'),
            'ready_for_delivery', (SELECT count(*) FROM r WHERE stage = 'RELEASED'),
            'delivered', (SELECT count(*) FROM r WHERE stage = 'DELIVERED'),
            'completed', (SELECT count(*) FROM r WHERE stage = 'COMPLETED'),
            'rejected', (SELECT count(*) FROM r WHERE stage = 'REJECTED'),
            'cancelled', (SELECT count(*) FROM r WHERE stage = 'CANCELLED'),
            'breaching', (SELECT count(*) FROM r WHERE breaching),
            'total', (SELECT count(*) FROM r)),
        'documents', jsonb_build_object(
            'certificates', (SELECT count(*) FROM i WHERE kind = 'DEGREE_CERTIFICATE' AND status = 'ACTIVE'),
            'transcripts', (SELECT count(*) FROM i WHERE kind = 'TRANSCRIPT' AND status = 'ACTIVE'),
            'sessional', (SELECT count(*) FROM i WHERE kind = 'SESSIONAL_TRANSCRIPT' AND status = 'ACTIVE'),
            'mini', (SELECT count(*) FROM i WHERE kind = 'MINI_TRANSCRIPT' AND status = 'ACTIVE'),
            'statements', (SELECT count(*) FROM i WHERE kind = 'ACADEMIC_STATEMENT' AND status = 'ACTIVE'),
            'revoked', (SELECT count(*) FROM i WHERE status = 'REVOKED'),
            'reissued', (SELECT count(*) FROM i WHERE version > 1),
            'flagged', (SELECT count(*) FROM i WHERE flagged_at IS NOT NULL AND status = 'ACTIVE'),
            'certificates_pending', (SELECT count(*) FROM records.graduand g JOIN people.student s ON s.id = g.student_id WHERE g.senate_state = 'APPROVED' AND s.status = 'GRADUATED'
                                       AND NOT EXISTS (SELECT 1 FROM credentials.issued x WHERE x.student_id = g.student_id AND x.kind = 'DEGREE_CERTIFICATE' AND credentials.document_status(x.id) = 'ACTIVE'))),
        'verification', jsonb_build_object(
            'last30', (SELECT count(*) FROM credentials.verification WHERE at > now() - interval '30 days'),
            'valid30', (SELECT count(*) FROM credentials.verification WHERE at > now() - interval '30 days' AND status = 'VALID'),
            'notFound30', (SELECT count(*) FROM credentials.verification WHERE at > now() - interval '30 days' AND status = 'NOT_FOUND'),
            'downloads30', (SELECT count(*) FROM credentials.download_log WHERE at > now() - interval '30 days'),
            'suspected', (SELECT count(*) FROM credentials.suspected_forgeries())),
        'revenue', jsonb_build_object(
            'collected', (SELECT coalesce(sum(pf.amount), 0) FROM finance.payment_reference pf WHERE pf.purpose LIKE 'Transcript TRN-%' AND pf.confirmed_at IS NOT NULL),
            'collected30', (SELECT coalesce(sum(pf.amount), 0) FROM finance.payment_reference pf WHERE pf.purpose LIKE 'Transcript TRN-%' AND pf.confirmed_at > now() - interval '30 days'),
            'outstanding', (SELECT coalesce(sum(t.fee), 0) FROM credentials.transcript_request t WHERE t.stage = 'AWAITING_PAYMENT'),
            'byKind', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', k, 'label', l, 'amount', a, 'n', n) ORDER BY l), '[]')
                         FROM (SELECT t.kind AS k, p.label AS l, sum(pf.amount) AS a, count(*) AS n FROM finance.payment_reference pf JOIN credentials.transcript_request t ON t.reference = pf.reference JOIN credentials.document_policy p ON p.kind = t.kind
                                WHERE pf.confirmed_at IS NOT NULL GROUP BY t.kind, p.label) q),
            'byMonth', (SELECT coalesce(jsonb_agg(jsonb_build_object('month', m, 'amount', a, 'n', n) ORDER BY m), '[]')
                          FROM (SELECT to_char(pf.confirmed_at, 'YYYY-MM') AS m, sum(pf.amount) AS a, count(*) AS n FROM finance.payment_reference pf WHERE pf.purpose LIKE 'Transcript TRN-%' AND pf.confirmed_at > now() - interval '12 months' GROUP BY 1) q)),
        'processing', jsonb_build_object(
            'avgDays', (SELECT round(avg(extract(epoch FROM (released_at - paid_at)) / 86400)::numeric, 1) FROM r WHERE released_at IS NOT NULL AND paid_at IS NOT NULL),
            'byKind', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'label', kind_label, 'n', n, 'open', o) ORDER BY kind_label), '[]')
                         FROM (SELECT kind, kind_label, count(*) AS n, count(*) FILTER (WHERE stage NOT IN ('COMPLETED','REJECTED','CANCELLED','DELIVERED')) AS o FROM r GROUP BY kind, kind_label) q),
            'byStage', (SELECT coalesce(jsonb_agg(jsonb_build_object('stage', stage, 'n', n) ORDER BY stage), '[]') FROM (SELECT stage, count(*) AS n FROM r GROUP BY stage) q),
            'deliveries', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'state', state, 'n', n) ORDER BY kind, state), '[]') FROM (SELECT kind, state, count(*) AS n FROM credentials.delivery GROUP BY kind, state) q))
    );
$$;

-- ── 13 · who may read and write ──────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON credentials.document_policy, credentials.document_template, credentials.event, credentials.delivery, credentials.download_token TO app_credentials, app_student;
GRANT SELECT, INSERT ON credentials.download_log, credentials.verification TO app_credentials, app_student;
GRANT SELECT ON ALL TABLES IN SCHEMA credentials TO app_auditor;

COMMIT;

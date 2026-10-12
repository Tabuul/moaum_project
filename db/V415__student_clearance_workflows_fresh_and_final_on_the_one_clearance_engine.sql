-- ═══════════════════════════════════════
-- V415 — student clearance: fresh and final clearance as workflows on the one clearance engine (V013)
--
--   The University already has one clearance engine (V013): eight units (Bursary, Department, Faculty, Library, Health,
--   Hostel, Works, Alumni) each giving their word on a student for a purpose — CLEARED, or HELD naming the item
--   outstanding — the latest word standing, nothing deleted; clearance.is_clear answers the gates (the transcript, the
--   graduation list and the degree certificate). What it lacked was a workflow: which offices take part in a kind of
--   clearance, in what order, which only when a condition holds (the hostel only for a student who applied for or was
--   given a room), a process per student with a public reference, a richer word than cleared/held, the student's own
--   action and documents, and the record the Registry and the offices read. So, on the same engine:
--
--     · ref.clearance_purpose.gate — the purposes that gate something (the eight of V004) and the workflows that gate
--       nothing by themselves: FRESH (fresh student clearance) and RETURNING (where the University requires it, a
--       session at a time). The Bursar's clearance scheme and the migrated-student clearance (V231–V233, V308) read the
--       gates only, so neither changes;
--     · clearance.workflow — FRESH (CLR/…), RETURNING (RCLR/…, off until the University turns it on) and FINAL (FCLR/…),
--       which IS the CONVOCATION purpose: final clearance is the clearance the graduation list and the degree
--       certificate already ask for, never graduation itself (Senate's approval stays where it is);
--     · clearance.workflow_stage — the offices of each workflow in their order, required or optional, waiting for the
--       earlier ones or not, applying to everyone, to listed programmes, faculties, departments, levels or entry modes,
--       or only when the student applied for or was allocated a hostel; documents the stage asks for; a deadline. Stored
--       in the database, changed by the Registry, never in code;
--     · clearance.process — one per student per workflow (per session for RETURNING) with a stable public reference and
--       a random check code for the certificate's QR; history is never overwritten;
--     · clearance.item gains the words UNDER_REVIEW, NOT_CLEARED, REQUIRES_ACTION, REJECTED and NOT_APPLICABLE (by an
--       override only), the process, an internal note the student never sees, the override, the state it replaced, the
--       office that acted and the evidence read at the moment of the decision;
--     · clearance.position (what every gate reads) follows the workflow for a purpose that has one: only the required
--       stages that apply to the student, so a student who never had a hostel is not held by the Hostel, and a stage
--       made not applicable by an override counts as such; a purpose with no workflow reads the eight units as before;
--     · an office clears against the record, not its own say: the Bursary only when finance.position shows nothing
--       outstanding, the Library only with no item on loan and no fine unpaid, the Hostel (final) only when every stay is
--       checked out, cleared and its damage charges settled, Alumni only when the student has confirmed their details —
--       a senior officer may override with a reason, kept with the state it replaced; nothing here changes a payment,
--       a loan, a result or a room;
--     · clearance.document (and its blob) — what a stage asks the student for, uploaded by the student or an office,
--       approved or rejected with a reason; clearance.alumni_profile — the alumni details the student confirms, beside
--       the contact details people.student_contact already keeps; clearance.reminder — the reminders sent, so a student
--       is reminded at most once in the workflow's interval;
--     · an Alumni Relations Office (office count 42) signs the Alumni stage; the Registry still may.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V415: fresh and final student clearance as workflows on the one clearance engine', true);

-- ── 1 · the purposes: the gates of V004, and the workflows that gate nothing by themselves ─────────────────────────────
ALTER TABLE ref.clearance_purpose ADD COLUMN gate boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN ref.clearance_purpose.gate IS
  'V415: true for a purpose something is released against (the Bursar''s clearance scheme names a rule for each); false for a clearance workflow that releases nothing by itself (FRESH, RETURNING).';
INSERT INTO ref.clearance_purpose (code, label, note, gate) VALUES
    ('FRESH',     'Fresh student clearance',     'Office by office after admission and screening (V415)', false),
    ('RETURNING', 'Returning student clearance', 'A session at a time, where the University requires it (V415)', false);

-- the Bursar's clearance scheme names a rule for every gate, not for a workflow (V394's wording kept)
CREATE OR REPLACE FUNCTION policy.assert_scheme_complete(p_version uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE missing text;
BEGIN
    SELECT string_agg(p.code, ', ' ORDER BY p.code) INTO missing
      FROM ref.clearance_purpose p
     WHERE p.gate
       AND NOT EXISTS (SELECT 1 FROM policy.clearance_rule r
                        WHERE r.version_id = p_version AND r.purpose = p.code);
    IF missing IS NOT NULL THEN
        RAISE EXCEPTION 'incomplete clearance scheme — no rule for: %', missing
        USING ERRCODE = '23514',
              HINT = 'Name every purpose in ref.clearance_purpose.';
    END IF;
END $function$;

-- a student brought over from the old portal arrives cleared for the gates; a workflow is not something they missed
CREATE OR REPLACE FUNCTION clearance.clear_on_migration(p_student uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, officer_id, decided_at, note)
    SELECT gen_random_uuid(), p_student, pu.code, un.code, 'CLEARED', NULL, NULL, now(),
           'Cleared on migration from the old portal — the clearance the old portal held, carried over'
      FROM ref.clearance_purpose pu
     CROSS JOIN clearance.unit un
     WHERE pu.gate
       AND NOT EXISTS (SELECT 1 FROM clearance.item c
                        WHERE c.student_id = p_student AND c.purpose = pu.code AND c.unit = un.code
                          AND c.superseded_by IS NULL);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION clearance.clear_migrated(p_from int DEFAULT 100, p_to int DEFAULT 400)
RETURNS TABLE (students int, positions int)
LANGUAGE plpgsql AS $$
DECLARE po int; st int;
BEGIN
    -- the same bulk as the V231 backfill, audit-light for the same reason: a desk pressing this for a
    -- thousand students must not wait on a million audited rows. The act itself is on the spine — the
    -- request that ran it carries the actor and the reason — and each row says what it is.
    SELECT count(DISTINCT s.id) INTO st
      FROM people.student s
     WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
       AND s.current_level BETWEEN p_from AND p_to
       AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
       AND EXISTS (SELECT 1 FROM ref.clearance_purpose pu CROSS JOIN clearance.unit un
                    WHERE pu.gate
                      AND NOT EXISTS (SELECT 1 FROM clearance.item c
                                       WHERE c.student_id = s.id AND c.purpose = pu.code AND c.unit = un.code AND c.superseded_by IS NULL));
    ALTER TABLE clearance.item DISABLE TRIGGER trg_audit_clearance_item;
    INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, officer_id, decided_at, note)
    SELECT gen_random_uuid(), s.id, pu.code, un.code, 'CLEARED', NULL, NULL, now(),
           'Cleared on migration from the old portal — the clearance the old portal held, carried over'
      FROM people.student s
     CROSS JOIN ref.clearance_purpose pu
     CROSS JOIN clearance.unit un
     WHERE pu.gate
       AND s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
       AND s.current_level BETWEEN p_from AND p_to
       AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
       AND NOT EXISTS (SELECT 1 FROM clearance.item c
                        WHERE c.student_id = s.id AND c.purpose = pu.code AND c.unit = un.code AND c.superseded_by IS NULL);
    GET DIAGNOSTICS po = ROW_COUNT;
    ALTER TABLE clearance.item ENABLE TRIGGER trg_audit_clearance_item;
    students := st; positions := po;
    RETURN NEXT;
END $$;

CREATE OR REPLACE FUNCTION clearance.migrated_summary(p_from integer DEFAULT 100, p_to integer DEFAULT 400)
RETURNS TABLE(migrated bigint, cleared bigint, uncleared bigint)
LANGUAGE sql STABLE AS $$
    WITH m AS (
        SELECT s.id FROM people.student s
         WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
           AND s.current_level BETWEEN p_from AND p_to
           AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
    ),
    latest AS (
        SELECT DISTINCT ON (c.student_id, c.purpose, c.unit) c.student_id, c.purpose, c.unit, c.state
          FROM clearance.item c JOIN m ON m.id = c.student_id
         WHERE c.superseded_by IS NULL
         ORDER BY c.student_id, c.purpose, c.unit, c.decided_at DESC
    ),
    not_clear AS (
        SELECT DISTINCT m.id
          FROM m
          CROSS JOIN ref.clearance_purpose pu
          CROSS JOIN clearance.unit u
          LEFT JOIN latest l ON l.student_id = m.id AND l.purpose = pu.code AND l.unit = u.code
         WHERE pu.gate AND coalesce(l.state, 'HELD') <> 'CLEARED'
    )
    SELECT count(*), count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM not_clear n WHERE n.id = m.id)),
           count(*) FILTER (WHERE EXISTS (SELECT 1 FROM not_clear n WHERE n.id = m.id))
      FROM m
$$;

-- ── 2 · the Alumni Relations Office signs the Alumni stage ────────────────────────────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES ('alumni', 'Alumni Relations Office', 'unit');
UPDATE clearance.unit SET office_code = 'alumni' WHERE code = 'ALUMNI';
UPDATE clearance.unit SET clears_against = 'Alumni details and registration', holds_for = 'Alumni details not confirmed, dues, gown hire'
 WHERE code = 'ALUMNI';

-- ── 3 · the workflows and their stages ───────────────────────────────────────────────────────────────────────────────
CREATE TABLE clearance.workflow (
    code           text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z_]{1,30}$'),
    label          text NOT NULL CHECK (btrim(label) <> '' AND length(label) <= 80),
    purpose        text NOT NULL UNIQUE REFERENCES ref.clearance_purpose(code),
    prefix         text NOT NULL UNIQUE CHECK (prefix ~ '^[A-Z]{2,6}$'),
    per_session    boolean NOT NULL DEFAULT false,
    active         boolean NOT NULL DEFAULT true,
    complete_word  text NOT NULL DEFAULT 'CLEARED' CHECK (complete_word IN ('CLEARED', 'COMPLETED')),
    reminder_days  int NOT NULL DEFAULT 7 CHECK (reminder_days BETWEEN 0 AND 60),
    certificate    boolean NOT NULL DEFAULT true,
    description    text NULL CHECK (description IS NULL OR length(description) <= 500),
    updated_by     uuid NULL,
    updated_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE clearance.workflow IS
  'V415: a kind of clearance run on the one engine — fresh, returning (per session) or final (the CONVOCATION purpose); its stages are clearance.workflow_stage.';
SELECT audit.attach('clearance.workflow');
INSERT INTO clearance.workflow (code, label, purpose, prefix, per_session, active, complete_word, reminder_days, certificate, description) VALUES
    ('FRESH', 'Fresh student clearance', 'FRESH', 'CLR', false, true, 'CLEARED', 7, true,
     'After admission, acceptance and screening: the offices clear a new student before the University counts them fully cleared.'),
    ('RETURNING', 'Returning student clearance', 'RETURNING', 'RCLR', true, false, 'CLEARED', 7, true,
     'A session at a time, where the University requires returning students to clear. Off until the Registry turns it on.'),
    ('FINAL', 'Final clearance', 'CONVOCATION', 'FCLR', false, true, 'COMPLETED', 7, true,
     'For a finalist: the clearance the graduation list and the degree certificate ask for. It does not graduate anyone; Senate does.');

CREATE TABLE clearance.workflow_stage (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow       text NOT NULL REFERENCES clearance.workflow(code),
    unit           text NOT NULL REFERENCES clearance.unit(code),
    ord            int  NOT NULL CHECK (ord BETWEEN 1 AND 99),
    required       boolean NOT NULL DEFAULT true,
    waits          boolean NOT NULL DEFAULT true,
    condition      text NOT NULL DEFAULT 'ALWAYS' CHECK (condition IN ('ALWAYS', 'HOSTEL_THIS_SESSION', 'HOSTEL_EVER_ALLOCATED')),
    programmes     text[] NOT NULL DEFAULT '{}',
    faculties      text[] NOT NULL DEFAULT '{}',
    departments    text[] NOT NULL DEFAULT '{}',
    levels         int[]  NOT NULL DEFAULT '{}',
    entry_modes    text[] NOT NULL DEFAULT '{}',
    documents      text[] NOT NULL DEFAULT '{}' CHECK (cardinality(documents) <= 10),
    deadline_days  int NULL CHECK (deadline_days IS NULL OR deadline_days BETWEEN 1 AND 365),
    instructions   text NULL CHECK (instructions IS NULL OR length(instructions) <= 500),
    active         boolean NOT NULL DEFAULT true,
    updated_by     uuid NULL,
    updated_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workflow, unit)
);
COMMENT ON TABLE clearance.workflow_stage IS
  'V415: an office''s stage in a workflow — its order, whether required, whether it waits for every earlier required stage (sequential) or not (parallel), when it applies (always; only for a student who applied for or was allocated a hostel in the session; only for a student ever allocated a room; only for the programmes, faculties, departments, levels or entry modes listed), the documents it asks for, a deadline. Never deleted: a stage taken out is made inactive.';
COMMENT ON COLUMN clearance.workflow_stage.waits IS
  'V415: true — the stage opens only when every earlier required stage that applies is cleared (sequential); false — it opens at once (parallel).';
SELECT audit.attach('clearance.workflow_stage');
INSERT INTO clearance.workflow_stage (workflow, unit, ord, required, waits, condition) VALUES
    ('FRESH', 'BURSARY', 1, true, true, 'ALWAYS'),
    ('FRESH', 'DEPARTMENT', 2, true, true, 'ALWAYS'),
    ('FRESH', 'FACULTY', 3, true, true, 'ALWAYS'),
    ('FRESH', 'LIBRARY', 4, true, true, 'ALWAYS'),
    ('FRESH', 'HEALTH', 5, true, true, 'ALWAYS'),
    ('FRESH', 'HOSTEL', 6, true, true, 'HOSTEL_THIS_SESSION'),
    ('RETURNING', 'BURSARY', 1, true, false, 'ALWAYS'),
    ('RETURNING', 'DEPARTMENT', 2, true, false, 'ALWAYS'),
    ('RETURNING', 'LIBRARY', 3, true, false, 'ALWAYS'),
    ('RETURNING', 'HOSTEL', 4, true, false, 'HOSTEL_THIS_SESSION'),
    ('FINAL', 'BURSARY', 1, true, true, 'ALWAYS'),
    ('FINAL', 'DEPARTMENT', 2, true, true, 'ALWAYS'),
    ('FINAL', 'FACULTY', 3, true, true, 'ALWAYS'),
    ('FINAL', 'LIBRARY', 4, true, true, 'ALWAYS'),
    ('FINAL', 'HEALTH', 5, true, true, 'ALWAYS'),
    ('FINAL', 'HOSTEL', 6, true, true, 'HOSTEL_EVER_ALLOCATED'),
    ('FINAL', 'WORKS', 7, true, true, 'ALWAYS'),
    ('FINAL', 'ALUMNI', 8, true, true, 'ALWAYS');

-- ── 4 · the process: one per student per workflow (per session where the workflow says so) ───────────────────────────
CREATE TABLE clearance.reference_counter (
    prefix  text NOT NULL,
    year    int  NOT NULL,
    last    int  NOT NULL,
    PRIMARY KEY (prefix, year)
);
SELECT audit.exempt('clearance.reference_counter', 'the last number drawn for a clearance reference prefix and year; the process it numbers is audited');

CREATE OR REPLACE FUNCTION clearance.next_reference(p_prefix text)
RETURNS text LANGUAGE sql AS $$
    INSERT INTO clearance.reference_counter AS c (prefix, year, last)
    VALUES (p_prefix, extract(year FROM current_date)::int, 1)
    ON CONFLICT (prefix, year) DO UPDATE SET last = c.last + 1
    RETURNING c.prefix || '/' || c.year || '/' || lpad(c.last::text, 6, '0')
$$;
COMMENT ON FUNCTION clearance.next_reference(text) IS 'V415: the next public clearance reference — CLR/2026/000001 — never the row''s id';

CREATE TABLE clearance.process (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference       text NOT NULL UNIQUE CHECK (reference ~ '^[A-Z]{2,6}/[0-9]{4}/[0-9]{6,}$'),
    workflow        text NOT NULL REFERENCES clearance.workflow(code),
    student_id      uuid NOT NULL REFERENCES people.student(id),
    session         text NOT NULL REFERENCES policy.academic_session(name),
    started_at      timestamptz NOT NULL DEFAULT now(),
    started_by      uuid NULL,
    started_office  text NULL,
    start_basis     text NOT NULL CHECK (start_basis IN ('ELIGIBLE', 'BULK', 'MANUAL', 'OVERRIDE')),
    start_reason    text NULL CHECK (start_reason IS NULL OR length(start_reason) <= 500),
    completed_at    timestamptz NULL,
    cancelled_at    timestamptz NULL,
    cancelled_by    uuid NULL,
    cancel_reason   text NULL,
    verify_code     text NOT NULL DEFAULT encode(gen_random_bytes(9), 'hex') CHECK (verify_code ~ '^[0-9a-f]{18}$'),
    certificate_at  timestamptz NULL,
    CONSTRAINT ck_clr_process_cancel CHECK ((cancelled_at IS NULL) = (cancel_reason IS NULL)),
    CONSTRAINT ck_clr_process_override CHECK (start_basis <> 'OVERRIDE' OR (start_reason IS NOT NULL AND btrim(start_reason) <> ''))
);
COMMENT ON TABLE clearance.process IS
  'V415: a student''s clearance under a workflow — its public reference, the session it belongs to, who started it and on what basis, when it completed or was cancelled (with the reason), and the random check code its certificate''s QR carries. Never deleted.';
CREATE UNIQUE INDEX ux_clr_process_live ON clearance.process (workflow, student_id, session) WHERE cancelled_at IS NULL;
CREATE INDEX ix_clr_process_session ON clearance.process (workflow, session) WHERE cancelled_at IS NULL;
CREATE INDEX ix_clr_process_student ON clearance.process (student_id);
SELECT audit.attach('clearance.process');

-- ── 5 · the word of a stage: richer states, the process, the override, the evidence ──────────────────────────────────
ALTER TABLE clearance.item DROP CONSTRAINT ck_clr_state;
ALTER TABLE clearance.item ADD CONSTRAINT ck_clr_state
    CHECK (state IN ('HELD', 'CLEARED', 'UNDER_REVIEW', 'NOT_CLEARED', 'REQUIRES_ACTION', 'REJECTED', 'NOT_APPLICABLE')) NOT VALID;
ALTER TABLE clearance.item VALIDATE CONSTRAINT ck_clr_state;
ALTER TABLE clearance.item DROP CONSTRAINT ck_clr_hold_names_item;
ALTER TABLE clearance.item ADD CONSTRAINT ck_clr_hold_names_item
    CHECK (state IN ('CLEARED', 'UNDER_REVIEW') OR (item IS NOT NULL AND btrim(item) <> '')) NOT VALID;
ALTER TABLE clearance.item VALIDATE CONSTRAINT ck_clr_hold_names_item;
ALTER TABLE clearance.item
    ADD COLUMN process_id     uuid NULL REFERENCES clearance.process(id),
    ADD COLUMN internal_note  text NULL,
    ADD COLUMN override       boolean NOT NULL DEFAULT false,
    ADD COLUMN previous_state text NULL,
    ADD COLUMN office         text NULL,
    ADD COLUMN evidence       jsonb NULL;
CREATE INDEX ix_clr_item_process ON clearance.item (process_id) WHERE process_id IS NOT NULL;
COMMENT ON COLUMN clearance.item.item IS
  'What is outstanding (a hold, NOT_CLEARED), what the student must do (REQUIRES_ACTION), why it was rejected (REJECTED) or why it was overridden — the student sees it.';
COMMENT ON COLUMN clearance.item.note IS 'V415: the official remark the student sees beside the word.';
COMMENT ON COLUMN clearance.item.internal_note IS 'V415: the office''s own note on the decision — never shown to the student.';
COMMENT ON COLUMN clearance.item.override IS 'V415: the word was given past a check the engine makes (a stage not yet open or not applicable, an outstanding obligation), by a senior officer with a reason.';
COMMENT ON COLUMN clearance.item.evidence IS 'V415: what the engine read from the authoritative record at the moment of the decision (balance, loans, stays, alumni details) — never a medical record.';

-- ── 6 · the documents a stage asks for ───────────────────────────────────────────────────────────────────────────────
CREATE TABLE clearance.document (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    process_id      uuid NOT NULL REFERENCES clearance.process(id),
    unit            text NOT NULL REFERENCES clearance.unit(code),
    label           text NOT NULL CHECK (btrim(label) <> '' AND length(label) <= 120),
    file_name       text NOT NULL CHECK (btrim(file_name) <> '' AND length(file_name) <= 200),
    content_type    text NOT NULL CHECK (content_type IN ('application/pdf', 'image/jpeg', 'image/png')),
    size_bytes      int  NOT NULL CHECK (size_bytes BETWEEN 1 AND 5242880),
    object_id       uuid NULL REFERENCES platform.file_object(id),
    state           text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'REQUIRES_REUPLOAD')),
    reason          text NULL,
    uploaded_at     timestamptz NOT NULL DEFAULT now(),
    uploaded_by     uuid NULL,
    uploaded_office text NULL,
    reviewed_at     timestamptz NULL,
    reviewed_by     uuid NULL,
    superseded_by   uuid NULL REFERENCES clearance.document(id),
    CONSTRAINT ck_clr_document_reason CHECK (state NOT IN ('REJECTED', 'REQUIRES_REUPLOAD') OR (reason IS NOT NULL AND btrim(reason) <> ''))
);
COMMENT ON TABLE clearance.document IS
  'V415: a document a clearance stage asked for, uploaded by the student or an office through the portal''s file store (object_id, or clearance.document_blob when no store is configured), reviewed with a reason when rejected; a re-upload supersedes the earlier one, which is kept.';
CREATE INDEX ix_clr_document_process ON clearance.document (process_id, unit) WHERE superseded_by IS NULL;
SELECT audit.attach('clearance.document');

CREATE TABLE clearance.document_blob (
    document_id  uuid PRIMARY KEY REFERENCES clearance.document(id),
    content      bytea NOT NULL
);
SELECT audit.exempt('clearance.document_blob', 'the bytes of a clearance document kept in the database when no file store is configured; the document row is audited');

-- ── 7 · the alumni details the student confirms (contact details stay in people.student_contact) ──────────────────────
CREATE TABLE clearance.alumni_profile (
    student_id         uuid PRIMARY KEY REFERENCES people.student(id),
    state_of_residence text NULL CHECK (state_of_residence IS NULL OR length(state_of_residence) <= 80),
    country            text NULL CHECK (country IS NULL OR length(country) <= 80),
    employment_status  text NULL CHECK (employment_status IS NULL OR employment_status IN
                           ('EMPLOYED', 'SELF_EMPLOYED', 'SEEKING', 'FURTHER_STUDY', 'NATIONAL_SERVICE', 'OTHER')),
    employer           text NULL CHECK (employer IS NULL OR length(employer) <= 160),
    occupation         text NULL CHECK (occupation IS NULL OR length(occupation) <= 120),
    linkedin           text NULL CHECK (linkedin IS NULL OR length(linkedin) <= 200),
    association_member boolean NOT NULL DEFAULT false,
    membership_no      text NULL CHECK (membership_no IS NULL OR length(membership_no) <= 40),
    confirmed_at       timestamptz NULL,
    verified_at        timestamptz NULL,
    verified_by        uuid NULL,
    updated_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE clearance.alumni_profile IS
  'V415: what the Alumni stage of final clearance reads beyond the student record — where the graduand will live, their work, the association — and the student''s confirmation that their details (with the e-mail, phone and address of people.student_contact) are current. No field beyond the confirmation is required.';
SELECT audit.attach('clearance.alumni_profile');

-- ── 8 · reminders sent, so none is sent twice in the interval ────────────────────────────────────────────────────────
CREATE TABLE clearance.reminder (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    process_id  uuid NOT NULL REFERENCES clearance.process(id),
    units       text[] NOT NULL,
    queued      int NOT NULL,
    sent_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_clr_reminder_process ON clearance.reminder (process_id, sent_at DESC);
SELECT audit.exempt('clearance.reminder', 'a reminder queued to a student about stages still outstanding; written once, read to keep from reminding twice in the interval');

-- ── 9 · the stages of students under a purpose, set-based ────────────────────────────────────────────────────────────
-- One row per student and stage: whether it applies to them, whether it is open (a sequential stage waits for every
-- earlier required stage that applies), and its word — the latest decision, NOT_APPLICABLE where the stage does not
-- apply (or an override said so), PENDING where it is open and undecided, WAITING where it is not yet open.
CREATE OR REPLACE FUNCTION clearance.stage_rows(p_purpose text, p_session text, p_students uuid[])
RETURNS TABLE (student_id uuid, process_id uuid, unit text, label text, office_code text, ord int, required boolean,
               waits boolean, applies boolean, opened boolean, state text, item text, note text, officer_id uuid,
               decided_at timestamptz, overridden boolean, documents text[], deadline_days int, instructions text)
LANGUAGE sql STABLE AS $$
    WITH w AS (
        SELECT * FROM clearance.workflow WHERE purpose = p_purpose
    ),
    st AS (
        SELECT s.id, s.programme_code, s.entry_mode, s.current_level, p.dept_code, p.faculty_code,
               pr.id AS process_id, coalesce(pr.session, p_session, s.entry_session) AS session, w.per_session, w.code AS workflow
          FROM unnest(p_students) x(id)
          JOIN people.student s ON s.id = x.id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          CROSS JOIN w
          LEFT JOIN LATERAL (SELECT q.id, q.session FROM clearance.process q
                              WHERE q.workflow = w.code AND q.student_id = s.id AND q.cancelled_at IS NULL
                                AND (NOT w.per_session OR p_session IS NULL OR q.session = p_session)
                              ORDER BY q.started_at DESC LIMIT 1) pr ON true
    ),
    stg AS (
        SELECT st.id AS student_id, st.process_id, st.per_session, ws.unit, u.label, u.office_code, ws.ord, ws.required, ws.waits,
               ws.documents, ws.deadline_days, ws.instructions,
               (cardinality(ws.programmes) = 0 OR st.programme_code = ANY (ws.programmes))
           AND (cardinality(ws.faculties) = 0 OR st.faculty_code = ANY (ws.faculties))
           AND (cardinality(ws.departments) = 0 OR st.dept_code = ANY (ws.departments))
           AND (cardinality(ws.levels) = 0 OR st.current_level = ANY (ws.levels))
           AND (cardinality(ws.entry_modes) = 0 OR st.entry_mode = ANY (ws.entry_modes))
           AND CASE ws.condition
                 WHEN 'HOSTEL_THIS_SESSION' THEN
                      EXISTS (SELECT 1 FROM hostel.application a
                               WHERE a.student_id = st.id AND a.session = st.session AND a.state IN ('APPLIED', 'ALLOCATED', 'CONFIRMED'))
                   OR EXISTS (SELECT 1 FROM hostel.allocation al
                               WHERE al.student_id = st.id AND al.session = st.session
                                 AND al.state IN ('HELD', 'CONFIRMED', 'ACCEPTED', 'CHECKED_IN', 'CHECKED_OUT', 'TRANSFERRED'))
                 WHEN 'HOSTEL_EVER_ALLOCATED' THEN
                      EXISTS (SELECT 1 FROM hostel.allocation al
                               WHERE al.student_id = st.id AND al.state IN ('CONFIRMED', 'ACCEPTED', 'CHECKED_IN', 'CHECKED_OUT', 'TRANSFERRED'))
                 ELSE true END AS in_scope
          FROM st
          JOIN clearance.workflow_stage ws ON ws.workflow = st.workflow AND ws.active
          JOIN clearance.unit u ON u.code = ws.unit
    ),
    dec AS (
        SELECT stg.*, d.state AS d_state, d.item AS d_item, d.note AS d_note, d.officer_id AS d_officer, d.decided_at AS d_at,
               coalesce(d.override, false) AS d_override
          FROM stg
          LEFT JOIN LATERAL (SELECT c.state, c.item, c.note, c.officer_id, c.decided_at, c.override FROM clearance.item c
                              WHERE c.student_id = stg.student_id AND c.purpose = p_purpose AND c.unit = stg.unit
                                AND c.superseded_by IS NULL
                                AND (NOT stg.per_session OR c.process_id IS NOT DISTINCT FROM stg.process_id)
                              ORDER BY c.decided_at DESC LIMIT 1) d ON true
    ),
    base AS (
        SELECT dec.*,
               CASE WHEN d_state = 'NOT_APPLICABLE' OR NOT in_scope THEN 'NOT_APPLICABLE'
                    WHEN d_state = 'HELD' THEN 'NOT_CLEARED'
                    ELSE d_state END AS b_state
          FROM dec
    ),
    gated AS (
        SELECT base.*,
               coalesce(bool_or(base.required AND coalesce(base.b_state, '') NOT IN ('CLEARED', 'NOT_APPLICABLE'))
                        OVER (PARTITION BY base.student_id ORDER BY base.ord ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), false) AS blocked
          FROM base
    )
    SELECT g.student_id, g.process_id, g.unit, g.label, g.office_code, g.ord, g.required, g.waits,
           g.b_state IS DISTINCT FROM 'NOT_APPLICABLE' AS applies,
           g.b_state IS DISTINCT FROM 'NOT_APPLICABLE' AND (NOT g.waits OR NOT g.blocked) AS opened,
           coalesce(g.b_state, CASE WHEN NOT g.waits OR NOT g.blocked THEN 'PENDING' ELSE 'WAITING' END) AS state,
           CASE WHEN g.b_state = 'NOT_APPLICABLE' AND NOT g.in_scope THEN NULL ELSE g.d_item END AS item,
           CASE WHEN g.b_state = 'NOT_APPLICABLE' AND NOT g.in_scope THEN NULL ELSE g.d_note END AS note,
           CASE WHEN g.b_state = 'NOT_APPLICABLE' AND NOT g.in_scope THEN NULL ELSE g.d_officer END AS officer_id,
           CASE WHEN g.b_state = 'NOT_APPLICABLE' AND NOT g.in_scope THEN NULL ELSE g.d_at END AS decided_at,
           g.d_override AS overridden, g.documents, g.deadline_days, g.instructions
      FROM gated g
     ORDER BY g.student_id, g.ord
$$;
COMMENT ON FUNCTION clearance.stage_rows(text, text, uuid[]) IS
  'V415: the stages of the workflow on a purpose for each student given, set-based: applies (in scope and the condition holds, unless an override said NOT_APPLICABLE), opened (not waiting on an earlier required stage), and the word — the latest decision, NOT_APPLICABLE, PENDING or WAITING.';

-- every gate reads this: a purpose with a workflow is held only by the required stages that apply to the student
CREATE OR REPLACE FUNCTION clearance.position(p_student uuid, p_purpose text)
RETURNS TABLE (unit text, label text, state text, item text, officer_id uuid, decided_at timestamptz, ord int)
LANGUAGE sql STABLE AS $$
    SELECT r.unit, r.label, r.state, r.item, r.officer_id, r.decided_at, r.ord
      FROM clearance.stage_rows(p_purpose, NULL, ARRAY[p_student]) r
     WHERE EXISTS (SELECT 1 FROM clearance.workflow w WHERE w.purpose = p_purpose AND w.active)
       AND r.required AND r.applies
    UNION ALL
    SELECT u.code, u.label, coalesce(i.state, 'HELD'), i.item, i.officer_id, i.decided_at, u.ord
      FROM clearance.unit u
      LEFT JOIN LATERAL (SELECT * FROM clearance.item c
                          WHERE c.student_id = p_student AND c.purpose = p_purpose AND c.unit = u.code
                            AND c.superseded_by IS NULL
                          ORDER BY c.decided_at DESC LIMIT 1) i ON true
     WHERE NOT EXISTS (SELECT 1 FROM clearance.workflow w WHERE w.purpose = p_purpose AND w.active)
     ORDER BY 7
$$;
COMMENT ON FUNCTION clearance.position(uuid, text) IS
  'The position of one candidate for a purpose (V013): for a purpose with an active workflow (V415), the required stages that apply to the student — a hostel stage is no hold on a student who never had a hostel; for any other purpose, the latest word of each of the eight units.';

-- the overall word of a process
CREATE OR REPLACE FUNCTION clearance.overall(p_process uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH p AS (
        SELECT q.id, q.student_id, q.session, q.cancelled_at, w.purpose, w.complete_word
          FROM clearance.process q JOIN clearance.workflow w ON w.code = q.workflow WHERE q.id = p_process
    ),
    r AS (
        SELECT r.state FROM p CROSS JOIN LATERAL clearance.stage_rows(p.purpose, p.session, ARRAY[p.student_id]) r
         WHERE r.required AND r.applies
    )
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM p) THEN NULL
                WHEN (SELECT cancelled_at FROM p) IS NOT NULL THEN 'CANCELLED'
                WHEN NOT EXISTS (SELECT 1 FROM r WHERE state <> 'CLEARED') THEN (SELECT complete_word FROM p)
                WHEN EXISTS (SELECT 1 FROM r WHERE state = 'REJECTED') THEN 'REJECTED'
                WHEN EXISTS (SELECT 1 FROM r WHERE state = 'NOT_CLEARED') THEN 'NOT_CLEARED'
                WHEN EXISTS (SELECT 1 FROM r WHERE state = 'REQUIRES_ACTION') THEN 'PENDING_ACTION'
                WHEN EXISTS (SELECT 1 FROM r WHERE state = 'CLEARED') THEN 'PARTIALLY_CLEARED'
                ELSE 'IN_PROGRESS' END
$$;
COMMENT ON FUNCTION clearance.overall(uuid) IS
  'V415: CANCELLED; the workflow''s complete word (CLEARED, COMPLETED) when every required stage that applies is cleared; else REJECTED, NOT_CLEARED or PENDING_ACTION when a stage says so; PARTIALLY_CLEARED once any is cleared; IN_PROGRESS.';

-- ── 10 · who may start: eligibility from the authoritative records ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.eligibility_rows(p_workflow text, p_session text, p_students uuid[] DEFAULT NULL)
RETURNS TABLE (student_id uuid, eligible boolean, reasons text[])
LANGUAGE sql STABLE AS $$
    WITH s AS (
        SELECT st.*, p.final_level, p.duration_years,
               (st.matric_no IS NOT NULL AND st.matriculation_run IS NULL AND st.candidate_id IS NULL) AS migrated,
               a.acceptance_confirmed_at, a.cleared_at, a.id AS application_id,
               EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = st.id) AS graduand
          FROM people.student st
          LEFT JOIN ref.programme p ON p.code = st.programme_code
          LEFT JOIN LATERAL (SELECT ap.id, ap.acceptance_confirmed_at, ap.cleared_at FROM admissions.application ap
                              WHERE ap.candidate_id = st.candidate_id AND st.candidate_id IS NOT NULL
                              ORDER BY ap.accepted_at DESC NULLS LAST, ap.created_at DESC LIMIT 1) a ON true
         WHERE (p_students IS NULL AND (
                    (p_workflow = 'FRESH' AND st.entry_session = p_session)
                 OR (p_workflow = 'FINAL' AND st.status IN ('ACTIVE', 'PROBATION', 'GRADUATED')
                     AND (st.current_level >= coalesce(p.final_level, p.duration_years * 100, 9999)
                          OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = st.id)))
                 OR (p_workflow = 'RETURNING' AND st.status IN ('ACTIVE', 'PROBATION') AND st.entry_session <> p_session)))
            OR st.id = ANY (p_students)
    ),
    r AS (
        SELECT s.id,
               array_remove(ARRAY[
                   CASE WHEN p_workflow = 'FRESH' AND s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                        THEN 'The student is ' || lower(replace(s.status, '_', ' ')) END,
                   CASE WHEN p_workflow = 'FRESH' AND s.entry_session IS DISTINCT FROM p_session
                        THEN 'Not a fresh student of ' || p_session END,
                   CASE WHEN p_workflow = 'FRESH' AND s.migrated THEN 'Brought over from the old portal' END,
                   CASE WHEN p_workflow = 'FRESH' AND NOT s.migrated AND s.application_id IS NULL
                        THEN 'No admission on the portal: start by hand' END,
                   CASE WHEN p_workflow = 'FRESH' AND s.application_id IS NOT NULL AND s.acceptance_confirmed_at IS NULL
                        THEN 'Acceptance fee not confirmed' END,
                   CASE WHEN p_workflow = 'FRESH' AND s.application_id IS NOT NULL AND s.cleared_at IS NULL
                        THEN 'Screening not cleared' END,
                   CASE WHEN p_workflow = 'FINAL' AND s.status NOT IN ('ACTIVE', 'PROBATION', 'GRADUATED')
                        THEN 'The student is ' || lower(replace(s.status, '_', ' ')) END,
                   CASE WHEN p_workflow = 'FINAL' AND NOT s.graduand AND s.final_level IS NULL AND s.duration_years IS NULL
                        THEN 'The programme''s final level is not recorded' END,
                   CASE WHEN p_workflow = 'FINAL' AND NOT s.graduand
                         AND s.current_level < coalesce(s.final_level, s.duration_years * 100, 0)
                        THEN 'Not yet at the final level (' || coalesce(s.final_level, s.duration_years * 100) || ')' END,
                   CASE WHEN p_workflow = 'RETURNING' AND s.status NOT IN ('ACTIVE', 'PROBATION')
                        THEN 'The student is ' || lower(replace(s.status, '_', ' ')) END,
                   CASE WHEN p_workflow = 'RETURNING' AND s.entry_session = p_session THEN 'A fresh student of ' || p_session END,
                   CASE WHEN p_workflow NOT IN ('FRESH', 'FINAL', 'RETURNING') THEN 'No such clearance' END
               ], NULL) AS reasons
          FROM s
    )
    SELECT r.id, cardinality(r.reasons) = 0, r.reasons FROM r
$$;
COMMENT ON FUNCTION clearance.eligibility_rows(text, text, uuid[]) IS
  'V415: who may start a clearance, read from the records that decide it — fresh: admitted or active, of the session''s intake, acceptance fee confirmed and screening cleared on the admission (a student with no admission on the portal is started by hand); final: active, on probation or graduated, at the programme''s final level (ref.programme.final_level, else its duration) or on the graduand list; returning: active and not of the session''s intake. With no students given, the candidates of the session.';

-- the students who would be reminded, notified or listed: their contact, read once
CREATE OR REPLACE FUNCTION clearance.tell(p_student uuid, p_subject text, p_body text, p_sms text)
RETURNS int LANGUAGE sql AS $$
    SELECT count(*)::int FROM (
        SELECT platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'student', p_student) AS n FROM people.student_reach(p_student) r
        UNION ALL
        SELECT platform.queue_notice('SMS', r.phone, p_subject, p_sms, 'student', p_student) FROM people.student_reach(p_student) r
    ) x WHERE x.n IS NOT NULL
$$;
COMMENT ON FUNCTION clearance.tell(uuid, text, text, text) IS 'V415: a clearance notice to a student by e-mail and SMS on the notice queue (shown on the portal''s notifications too); never a medical detail.';

CREATE OR REPLACE FUNCTION clearance.signature()
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT 'Office of the Registrar, ' || coalesce((SELECT name FROM platform.institution_profile ORDER BY updated_at DESC LIMIT 1), 'the University')
$$;

-- ── 11 · starting a clearance ────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.start(p_workflow text, p_student uuid, p_session text, p_basis text, p_reason text,
                                           p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE w clearance.workflow; v_id uuid; v_ref text; e record; v_first text; v_who text;
BEGIN
    SELECT * INTO w FROM clearance.workflow WHERE code = upper(p_workflow);
    IF w.code IS NULL THEN RAISE EXCEPTION 'CLR_NO_WORKFLOW: no such clearance' USING ERRCODE = '23514'; END IF;
    IF NOT w.active THEN RAISE EXCEPTION 'CLR_WORKFLOW_OFF: % is not in use', lower(w.label) USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'CLR_NO_SESSION: no session %', p_session USING ERRCODE = '23514';
    END IF;
    IF p_basis NOT IN ('ELIGIBLE', 'BULK', 'MANUAL', 'OVERRIDE') THEN
        RAISE EXCEPTION 'CLR_BASIS: % is not a basis for starting', p_basis USING ERRCODE = '23514';
    END IF;
    SELECT q.reference INTO v_ref FROM clearance.process q
     WHERE q.workflow = w.code AND q.student_id = p_student AND q.cancelled_at IS NULL AND (NOT w.per_session OR q.session = p_session)
     LIMIT 1;
    IF v_ref IS NOT NULL THEN
        RAISE EXCEPTION 'CLR_ALREADY_STARTED: % is already under way (%)', lower(w.label), v_ref USING ERRCODE = '23514';
    END IF;
    SELECT * INTO e FROM clearance.eligibility_rows(w.code, p_session, ARRAY[p_student]);
    IF e.student_id IS NULL THEN RAISE EXCEPTION 'CLR_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    IF NOT e.eligible AND p_basis <> 'OVERRIDE' THEN
        RAISE EXCEPTION 'CLR_NOT_ELIGIBLE: %', array_to_string(e.reasons, '; ') USING ERRCODE = '23514';
    END IF;
    IF p_basis = 'OVERRIDE' AND (p_reason IS NULL OR btrim(p_reason) = '') THEN
        RAISE EXCEPTION 'CLR_REASON: starting past the eligibility check needs a reason' USING ERRCODE = '23514';
    END IF;
    v_ref := clearance.next_reference(w.prefix);
    INSERT INTO clearance.process (reference, workflow, student_id, session, started_by, started_office, start_basis, start_reason)
    VALUES (v_ref, w.code, p_student, p_session, p_actor, p_office, p_basis, nullif(btrim(coalesce(p_reason, '')), ''))
    RETURNING id INTO v_id;
    SELECT string_agg(r.label, ', ' ORDER BY r.ord) INTO v_first
      FROM clearance.stage_rows(w.purpose, p_session, ARRAY[p_student]) r WHERE r.opened AND r.applies;
    SELECT surname || ', ' || other_names INTO v_who FROM people.student WHERE id = p_student;
    PERFORM clearance.tell(p_student, w.label || ' started — ' || v_ref,
        'Dear ' || coalesce(v_who, 'student') || ',' || E'\n\n' || 'Your ' || lower(w.label) || ' for the ' || p_session || ' session has started (reference '
        || v_ref || ').' || E'\n\n' || 'Open now: ' || coalesce(v_first, 'none') || '.' || E'\n\n'
        || 'Follow each office under My Clearance on the portal.' || E'\n\n' || clearance.signature(),
        'MOAUM: your ' || lower(w.label) || ' has started (' || v_ref || '). See My Clearance on the portal.');
    RETURN v_id;
END $$;
COMMENT ON FUNCTION clearance.start(text, uuid, text, text, text, uuid, text) IS
  'V415: starts a student''s clearance under a workflow — refused when one is under way or the student is not eligible (an OVERRIDE needs a reason) — with the next public reference, and tells the student what is open.';

CREATE OR REPLACE FUNCTION clearance.start_eligible(p_workflow text, p_session text, p_actor uuid, p_office text, p_limit int DEFAULT 500)
RETURNS TABLE (started int, remaining int) LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0; w clearance.workflow;
BEGIN
    SELECT * INTO w FROM clearance.workflow WHERE code = upper(p_workflow);
    IF w.code IS NULL OR NOT w.active THEN RAISE EXCEPTION 'CLR_WORKFLOW_OFF: no such clearance in use' USING ERRCODE = '23514'; END IF;
    FOR r IN
        SELECT e.student_id FROM clearance.eligibility_rows(w.code, p_session) e
         WHERE e.eligible
           AND NOT EXISTS (SELECT 1 FROM clearance.process q WHERE q.workflow = w.code AND q.student_id = e.student_id
                            AND q.cancelled_at IS NULL AND (NOT w.per_session OR q.session = p_session))
         ORDER BY e.student_id
         LIMIT greatest(1, least(coalesce(p_limit, 500), 2000))
    LOOP
        PERFORM clearance.start(w.code, r.student_id, p_session, 'BULK', NULL, p_actor, p_office);
        n := n + 1;
    END LOOP;
    started := n;
    SELECT count(*) INTO remaining FROM clearance.eligibility_rows(w.code, p_session) e
     WHERE e.eligible
       AND NOT EXISTS (SELECT 1 FROM clearance.process q WHERE q.workflow = w.code AND q.student_id = e.student_id
                        AND q.cancelled_at IS NULL AND (NOT w.per_session OR q.session = p_session));
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION clearance.start_eligible(text, text, uuid, text, int) IS
  'V415: starts the clearance of up to p_limit (at most 2,000) eligible students of the session who have none under way, each told once; says how many remain.';

-- ── 12 · what the record says, office by office, and what stops a clearance ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.evidence(p_process uuid, p_unit text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE q record; v jsonb := '{}'::jsonb;
BEGIN
    SELECT p.*, w.purpose, w.code AS wf FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow
     WHERE p.id = p_process INTO q;
    IF q.id IS NULL THEN RETURN NULL; END IF;
    CASE upper(p_unit)
    WHEN 'BURSARY' THEN
        IF q.wf = 'FINAL' THEN
            SELECT jsonb_build_object(
                     'sessions', coalesce(jsonb_agg(jsonb_build_object('session', x.session, 'stated', x.stated, 'due', x.due, 'paid', x.paid,
                                                                       'balance', x.balance) ORDER BY x.session), '[]'::jsonb),
                     'outstanding', coalesce(sum(greatest(x.balance, 0)) FILTER (WHERE x.stated), 0))
              INTO v
              FROM (SELECT ss.session, finance.fee_stated(q.student_id, ss.session) AS stated, pos.due, pos.paid, pos.balance
                      FROM (SELECT DISTINCT e.session FROM people.enrolment e WHERE e.student_id = q.student_id
                            UNION SELECT q.session) ss
                      CROSS JOIN LATERAL finance.position(q.student_id, ss.session) pos) x;
        ELSE
            SELECT jsonb_build_object('session', q.session, 'stated', finance.fee_stated(q.student_id, q.session),
                                      'due', pos.due, 'paid', pos.paid, 'balance', pos.balance,
                                      'outstanding', CASE WHEN finance.fee_stated(q.student_id, q.session) THEN greatest(pos.balance, 0) ELSE NULL END)
              INTO v FROM finance.position(q.student_id, q.session) pos;
        END IF;
    WHEN 'LIBRARY' THEN
        SELECT jsonb_build_object(
                 'openLoans', count(*) FILTER (WHERE l.returned_at IS NULL),
                 'loans', coalesce(jsonb_agg(jsonb_build_object('accession', l.accession, 'title', i.title, 'dueOn', l.due_on) ORDER BY l.due_on)
                                   FILTER (WHERE l.returned_at IS NULL), '[]'::jsonb),
                 'unpaidFines', count(*) FILTER (WHERE coalesce(l.fine, 0) > 0 AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL),
                 'fines', coalesce(sum(l.fine) FILTER (WHERE coalesce(l.fine, 0) > 0 AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL), 0))
          INTO v
          FROM library.loan l
          LEFT JOIN library.copy c ON c.accession = l.accession
          LEFT JOIN library.item i ON i.id = c.item_id
         WHERE l.student_id = q.student_id;
    WHEN 'HOSTEL' THEN
        SELECT jsonb_build_object(
                 'stays', coalesce(jsonb_agg(jsonb_build_object('reference', al.reference_no, 'session', al.session, 'state', al.state,
                                                                'feeStatus', al.fee_status, 'checkedOut', al.checked_out_at IS NOT NULL,
                                                                'clearance', hc.state) ORDER BY al.session) , '[]'::jsonb),
                 'checkedIn', count(*) FILTER (WHERE al.state = 'CHECKED_IN'),
                 'clearancePending', count(*) FILTER (WHERE al.state = 'CHECKED_OUT' AND coalesce(hc.state, 'PENDING') <> 'CLEARED'),
                 'unsettledCharges', (SELECT count(*) FROM hostel.damage_charge dc JOIN hostel.allocation a2 ON a2.id = dc.allocation_id
                                       WHERE a2.student_id = q.student_id AND dc.settled_at IS NULL AND dc.waived_at IS NULL AND coalesce(dc.charge, 0) > 0),
                 'charges', (SELECT coalesce(sum(dc.charge), 0) FROM hostel.damage_charge dc JOIN hostel.allocation a2 ON a2.id = dc.allocation_id
                              WHERE a2.student_id = q.student_id AND dc.settled_at IS NULL AND dc.waived_at IS NULL))
          INTO v
          FROM hostel.allocation al
          LEFT JOIN hostel.clearance hc ON hc.allocation_id = al.id
         WHERE al.student_id = q.student_id AND al.state IN ('HELD', 'CONFIRMED', 'ACCEPTED', 'CHECKED_IN', 'CHECKED_OUT', 'TRANSFERRED');
    WHEN 'HEALTH' THEN
        -- the fitness finding and its date only: never a diagnosis, a visit or an allergy
        SELECT jsonb_build_object('fitness', hp.fitness, 'fitnessOn', hp.fitness_on) INTO v
          FROM health.profile hp WHERE hp.student_id = q.student_id;
        v := coalesce(v, jsonb_build_object('fitness', NULL, 'fitnessOn', NULL));
    WHEN 'DEPARTMENT' THEN
        IF q.wf = 'FINAL' THEN
            SELECT jsonb_build_object('graduand', jsonb_build_object('session', g.session, 'cgpa', g.cgpa, 'award', g.award, 'unmet', g.unmet,
                                                                     'senate', g.senate_state))
              INTO v FROM records.graduand g WHERE g.student_id = q.student_id ORDER BY g.session DESC LIMIT 1;
            v := coalesce(v, jsonb_build_object('graduand', NULL));
        ELSE
            SELECT jsonb_build_object('registrations', coalesce(jsonb_agg(jsonb_build_object('semester', r.semester, 'status', r.status) ORDER BY r.semester), '[]'::jsonb))
              INTO v FROM registration.course_registration r WHERE r.student_id = q.student_id AND r.session = q.session;
        END IF;
    WHEN 'ALUMNI' THEN
        SELECT jsonb_build_object('email', coalesce(btrim(c.email), '') <> '', 'phone', coalesce(btrim(c.phone), '') <> '',
                                  'address', coalesce(btrim(c.address), '') <> '',
                                  'confirmed', ap.confirmed_at IS NOT NULL, 'confirmedAt', ap.confirmed_at,
                                  'member', coalesce(ap.association_member, false))
          INTO v
          FROM people.student s
          LEFT JOIN people.student_contact c ON c.student_id = s.id
          LEFT JOIN clearance.alumni_profile ap ON ap.student_id = s.id
         WHERE s.id = q.student_id;
    ELSE
        v := '{}'::jsonb;
    END CASE;
    -- every stage: the documents it holds, by state
    v := coalesce(v, '{}'::jsonb) || jsonb_build_object('documents',
           (SELECT coalesce(jsonb_object_agg(d.label, d.state), '{}'::jsonb) FROM clearance.document d
             WHERE d.process_id = p_process AND d.unit = upper(p_unit) AND d.superseded_by IS NULL));
    RETURN v;
END $$;
COMMENT ON FUNCTION clearance.evidence(uuid, text) IS
  'V415: what the authoritative record says for a stage — the Bursary''s positions (finance.position), the Library''s loans and fines, the hostel stays with their checkout clearance and charges, the clinic''s fitness finding (never a diagnosis), the department''s registrations or graduand audit, the alumni details — and the stage''s documents.';

CREATE OR REPLACE FUNCTION clearance.naira(p numeric)
RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT '₦' || to_char(coalesce(p, 0), 'FM999,999,999,990') $$;

-- what keeps a stage from being cleared on the record; null when nothing does
CREATE OR REPLACE FUNCTION clearance.blocker(p_process uuid, p_unit text, p_evidence jsonb)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE q record; v_docs text;
BEGIN
    SELECT p.*, w.code AS wf FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow WHERE p.id = p_process INTO q;
    -- a document the stage asks for and does not hold approved
    SELECT string_agg(x.label, ', ') INTO v_docs
      FROM clearance.workflow_stage ws CROSS JOIN LATERAL unnest(ws.documents) x(label)
     WHERE ws.workflow = q.wf AND ws.unit = upper(p_unit) AND ws.active
       AND NOT EXISTS (SELECT 1 FROM clearance.document d WHERE d.process_id = p_process AND d.unit = ws.unit
                        AND d.label = x.label AND d.superseded_by IS NULL AND d.state = 'APPROVED');
    IF v_docs IS NOT NULL THEN RETURN 'Not yet approved: ' || v_docs; END IF;
    CASE upper(p_unit)
    WHEN 'BURSARY' THEN
        IF q.wf = 'FINAL' THEN
            IF coalesce((p_evidence->>'outstanding')::numeric, 0) > 0 THEN
                RETURN 'Outstanding fees: ' || clearance.naira((p_evidence->>'outstanding')::numeric) || ' across the sessions stated';
            END IF;
        ELSE
            IF NOT coalesce((p_evidence->>'stated')::boolean, false) THEN
                RETURN 'The ' || q.session || ' fees are not stated for the student, so nothing can be verified';
            END IF;
            IF coalesce((p_evidence->>'outstanding')::numeric, 0) > 0 THEN
                RETURN 'Outstanding fees: ' || clearance.naira((p_evidence->>'outstanding')::numeric) || ' for ' || q.session;
            END IF;
        END IF;
    WHEN 'LIBRARY' THEN
        IF coalesce((p_evidence->>'openLoans')::int, 0) > 0 THEN
            RETURN (p_evidence->>'openLoans') || ' item(s) on loan not returned';
        END IF;
        IF coalesce((p_evidence->>'unpaidFines')::int, 0) > 0 THEN
            RETURN 'Library fines unpaid: ' || clearance.naira((p_evidence->>'fines')::numeric);
        END IF;
    WHEN 'HOSTEL' THEN
        IF coalesce((p_evidence->>'unsettledCharges')::int, 0) > 0 THEN
            RETURN 'Hostel damage charges unpaid: ' || clearance.naira((p_evidence->>'charges')::numeric);
        END IF;
        IF q.wf = 'FINAL' AND coalesce((p_evidence->>'checkedIn')::int, 0) > 0 THEN
            RETURN 'Still checked in: the stay must be checked out first';
        END IF;
        IF q.wf = 'FINAL' AND coalesce((p_evidence->>'clearancePending')::int, 0) > 0 THEN
            RETURN 'The hostel checkout clearance is not complete';
        END IF;
    WHEN 'ALUMNI' THEN
        IF NOT coalesce((p_evidence->>'confirmed')::boolean, false) THEN
            RETURN 'The student has not confirmed their alumni details';
        END IF;
    ELSE
        NULL;
    END CASE;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION clearance.blocker(uuid, text, jsonb) IS
  'V415: what the record says stands between a stage and CLEARED — a document not approved, fees outstanding or not stated, an item on loan or a fine unpaid, a hostel stay not checked out or charged, alumni details not confirmed; null when nothing does. An override names its reason instead.';

-- ── 13 · the word of an office ───────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.decide(p_process uuid, p_unit text, p_state text, p_item text, p_note text,
                                            p_internal text, p_override boolean, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE q record; r record; v_ev jsonb; v_block text; v_unit text := upper(btrim(p_unit)); v_state text := upper(btrim(p_state));
        v_item text := nullif(btrim(coalesce(p_item, '')), ''); v_overall text; v_before text; v_next text; v_subject text; v_body text;
        v_who text; v_label text; v_override boolean := coalesce(p_override, false);
BEGIN
    SELECT p.*, w.purpose, w.label AS wf_label, w.complete_word, w.code AS wf FROM clearance.process p
      JOIN clearance.workflow w ON w.code = p.workflow WHERE p.id = p_process FOR UPDATE OF p INTO q;
    IF q.id IS NULL THEN RAISE EXCEPTION 'CLR_NO_PROCESS: no such clearance' USING ERRCODE = '23503'; END IF;
    IF q.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'CLR_CANCELLED: % was cancelled', q.reference USING ERRCODE = '23514'; END IF;
    IF v_state NOT IN ('CLEARED', 'UNDER_REVIEW', 'NOT_CLEARED', 'REQUIRES_ACTION', 'REJECTED', 'NOT_APPLICABLE') THEN
        RAISE EXCEPTION 'CLR_STATE: % is not a word a stage takes', p_state USING ERRCODE = '23514';
    END IF;
    IF v_state = 'NOT_APPLICABLE' AND NOT v_override THEN
        RAISE EXCEPTION 'CLR_OVERRIDE_ONLY: a stage is made not applicable only by an override, with a reason' USING ERRCODE = '23514';
    END IF;
    IF (v_state IN ('NOT_CLEARED', 'REQUIRES_ACTION', 'REJECTED') OR v_override) AND v_item IS NULL THEN
        RAISE EXCEPTION 'CLR_REASON: % needs a reason the student can act on', CASE WHEN v_override THEN 'an override' ELSE lower(replace(v_state, '_', ' ')) END
            USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM clearance.stage_rows(q.purpose, q.session, ARRAY[q.student_id]) x WHERE x.unit = v_unit;
    IF r.unit IS NULL THEN RAISE EXCEPTION 'CLR_NO_STAGE: % has no % stage', lower(q.wf_label), lower(v_unit) USING ERRCODE = '23514'; END IF;
    IF q.completed_at IS NOT NULL AND NOT v_override THEN
        RAISE EXCEPTION 'CLR_COMPLETED: % is complete; a change now is an override', q.reference USING ERRCODE = '23514';
    END IF;
    IF NOT r.applies AND NOT v_override THEN
        RAISE EXCEPTION 'CLR_NOT_APPLICABLE: the % stage does not apply to this student', lower(r.label) USING ERRCODE = '23514';
    END IF;
    IF NOT r.opened AND r.applies AND NOT v_override THEN
        SELECT string_agg(x.label, ', ' ORDER BY x.ord) INTO v_before FROM clearance.stage_rows(q.purpose, q.session, ARRAY[q.student_id]) x
         WHERE x.ord < r.ord AND x.required AND x.applies AND x.state <> 'CLEARED';
        RAISE EXCEPTION 'CLR_STAGE_WAITING: % comes after %', r.label, coalesce(v_before, 'the earlier stages') USING ERRCODE = '23514';
    END IF;
    v_ev := clearance.evidence(p_process, v_unit);
    IF v_state = 'CLEARED' AND NOT v_override THEN
        v_block := clearance.blocker(p_process, v_unit, v_ev);
        IF v_block IS NOT NULL THEN
            RAISE EXCEPTION 'CLR_OUTSTANDING: %', v_block USING ERRCODE = '23514';
        END IF;
    END IF;
    INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, officer_id, decided_at, note, process_id, internal_note,
                                override, previous_state, office, evidence)
    VALUES (gen_random_uuid(), q.student_id, q.purpose, v_unit, v_state, v_item, p_actor, clock_timestamp(),
            nullif(btrim(coalesce(p_note, '')), ''), q.id, nullif(btrim(coalesce(p_internal, '')), ''), v_override, r.state, p_office, v_ev);

    v_overall := clearance.overall(q.id);
    IF v_overall = q.complete_word AND q.completed_at IS NULL THEN
        UPDATE clearance.process SET completed_at = clock_timestamp() WHERE id = q.id;
    ELSIF v_overall <> q.complete_word AND q.completed_at IS NOT NULL THEN
        UPDATE clearance.process SET completed_at = NULL WHERE id = q.id;   -- an override reopened it
    END IF;

    -- the student is told: cleared, not cleared, action required, rejected; never a medical detail
    IF v_state <> 'UNDER_REVIEW' THEN
        SELECT surname || ', ' || other_names INTO v_who FROM people.student WHERE id = q.student_id;
        v_label := r.label;
        SELECT string_agg(x.label, ', ' ORDER BY x.ord) INTO v_next FROM clearance.stage_rows(q.purpose, q.session, ARRAY[q.student_id]) x
         WHERE x.opened AND x.applies AND x.state IN ('PENDING') AND x.unit <> v_unit;
        v_subject := v_label || ' clearance: ' || CASE v_state WHEN 'CLEARED' THEN 'cleared' WHEN 'NOT_CLEARED' THEN 'not cleared'
                                                              WHEN 'REQUIRES_ACTION' THEN 'action required' WHEN 'REJECTED' THEN 'rejected'
                                                              ELSE 'not applicable' END || ' (' || q.reference || ')';
        v_body := 'Dear ' || coalesce(v_who, 'student') || ',' || E'\n\n'
               || CASE v_state
                    WHEN 'CLEARED' THEN 'The ' || v_label || ' has cleared you for your ' || lower(q.wf_label) || '.'
                    WHEN 'NOT_APPLICABLE' THEN 'The ' || v_label || ' stage of your ' || lower(q.wf_label) || ' no longer applies to you.'
                    ELSE 'The ' || v_label || ' has not cleared you for your ' || lower(q.wf_label) || '.'
                         || CASE WHEN v_unit = 'HEALTH' THEN ' Please see the Health Centre.'
                                 ELSE E'\n\n' || CASE v_state WHEN 'REQUIRES_ACTION' THEN 'What to do: ' WHEN 'REJECTED' THEN 'Reason: ' ELSE 'Outstanding: ' END || v_item END
                  END
               || CASE WHEN v_overall = q.complete_word THEN E'\n\n' || 'Every office has cleared you: your ' || lower(q.wf_label) || ' is ' || lower(q.complete_word) || '.'
                       WHEN v_next IS NOT NULL THEN E'\n\n' || 'Open now: ' || v_next || '.' ELSE '' END
               || E'\n\n' || 'See My Clearance on the portal (reference ' || q.reference || ').' || E'\n\n' || clearance.signature();
        PERFORM clearance.tell(q.student_id, v_subject, v_body,
            'MOAUM: ' || v_label || ' clearance ' || CASE v_state WHEN 'CLEARED' THEN 'cleared' WHEN 'REQUIRES_ACTION' THEN 'needs your action'
                                                               WHEN 'REJECTED' THEN 'rejected' WHEN 'NOT_CLEARED' THEN 'not cleared' ELSE 'updated' END
            || CASE WHEN v_overall = q.complete_word THEN '; your ' || lower(q.wf_label) || ' is ' || lower(q.complete_word) ELSE '' END
            || '. See My Clearance on the portal.');
    END IF;
    RETURN v_overall;
END $$;
COMMENT ON FUNCTION clearance.decide(uuid, text, text, text, text, text, boolean, uuid, text) IS
  'V415: an office''s word on a stage — refused when the clearance is cancelled or complete, the stage does not apply or is not yet open, or (for CLEARED) the record shows something outstanding; an override passes those checks with a reason and is kept as one, with the state it replaced. A reason is required for not cleared, action required and rejected. The evidence read is kept with the word; the process completes (or reopens) on the overall word; the student is told.';

CREATE OR REPLACE FUNCTION clearance.cancel(p_process uuid, p_reason text, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'CLR_REASON: a clearance is cancelled with a reason' USING ERRCODE = '23514';
    END IF;
    UPDATE clearance.process SET cancelled_at = clock_timestamp(), cancelled_by = p_actor, cancel_reason = btrim(p_reason)
     WHERE id = p_process AND cancelled_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'CLR_NO_PROCESS: no such clearance under way' USING ERRCODE = '23514'; END IF;
END $$;
COMMENT ON FUNCTION clearance.cancel(uuid, text, uuid) IS 'V415: cancels a clearance with a reason; its decisions and documents are kept.';

-- ── 14 · documents ───────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.add_document(p_process uuid, p_unit text, p_label text, p_file text, p_type text, p_size int,
                                                  p_object uuid, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE q record; v_id uuid; v_unit text := upper(btrim(p_unit));
BEGIN
    SELECT p.*, w.purpose FROM clearance.process p JOIN clearance.workflow w ON w.code = p.workflow WHERE p.id = p_process INTO q;
    IF q.id IS NULL OR q.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'CLR_NO_PROCESS: no such clearance under way' USING ERRCODE = '23514'; END IF;
    IF q.completed_at IS NOT NULL THEN RAISE EXCEPTION 'CLR_COMPLETED: % is complete', q.reference USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM clearance.workflow_stage ws WHERE ws.workflow = q.workflow AND ws.unit = v_unit AND ws.active) THEN
        RAISE EXCEPTION 'CLR_NO_STAGE: no % stage', lower(v_unit) USING ERRCODE = '23514';
    END IF;
    INSERT INTO clearance.document (process_id, unit, label, file_name, content_type, size_bytes, object_id, uploaded_by, uploaded_office)
    VALUES (p_process, v_unit, btrim(p_label), btrim(p_file), p_type, p_size, p_object, p_actor, p_office)
    RETURNING id INTO v_id;
    UPDATE clearance.document SET superseded_by = v_id
     WHERE process_id = p_process AND unit = v_unit AND label = btrim(p_label) AND id <> v_id AND superseded_by IS NULL;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION clearance.add_document(uuid, text, text, text, text, int, uuid, uuid, text) IS
  'V415: a document for a stage, by the student or an office; one of the same label already there is superseded (kept).';

CREATE OR REPLACE FUNCTION clearance.review_document(p_document uuid, p_state text, p_reason text, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE d record; v_state text := upper(btrim(p_state));
BEGIN
    SELECT x.*, p.student_id, p.reference, w.label AS wf_label, u.label AS unit_label
      FROM clearance.document x JOIN clearance.process p ON p.id = x.process_id JOIN clearance.workflow w ON w.code = p.workflow
      JOIN clearance.unit u ON u.code = x.unit
     WHERE x.id = p_document INTO d;
    IF d.id IS NULL THEN RAISE EXCEPTION 'CLR_NO_DOCUMENT: no such document' USING ERRCODE = '23503'; END IF;
    IF d.superseded_by IS NOT NULL THEN RAISE EXCEPTION 'CLR_DOCUMENT_REPLACED: a newer upload replaced it' USING ERRCODE = '23514'; END IF;
    IF v_state NOT IN ('UNDER_REVIEW', 'APPROVED', 'REJECTED', 'REQUIRES_REUPLOAD') THEN
        RAISE EXCEPTION 'CLR_STATE: % is not a word a document takes', p_state USING ERRCODE = '23514';
    END IF;
    IF v_state IN ('REJECTED', 'REQUIRES_REUPLOAD') AND (p_reason IS NULL OR btrim(p_reason) = '') THEN
        RAISE EXCEPTION 'CLR_REASON: a rejected document needs a reason' USING ERRCODE = '23514';
    END IF;
    UPDATE clearance.document SET state = v_state, reason = nullif(btrim(coalesce(p_reason, '')), ''), reviewed_at = clock_timestamp(), reviewed_by = p_actor
     WHERE id = p_document;
    IF v_state IN ('REJECTED', 'REQUIRES_REUPLOAD') THEN
        PERFORM clearance.tell(d.student_id, d.unit_label || ' clearance: document ' || CASE v_state WHEN 'REJECTED' THEN 'rejected' ELSE 'to upload again' END,
            'Your ' || d.label || ' for the ' || d.unit_label || ' stage of your ' || lower(d.wf_label) || ' (' || d.reference || ') was '
            || CASE v_state WHEN 'REJECTED' THEN 'rejected' ELSE 'returned for a new upload' END || '.' || E'\n\n'
            || CASE WHEN d.unit = 'HEALTH' THEN 'Please see the Health Centre.' ELSE 'Reason: ' || btrim(p_reason) END
            || E'\n\n' || 'Upload it again under My Clearance on the portal.' || E'\n\n' || clearance.signature(),
            'MOAUM: your ' || d.label || ' for ' || d.unit_label || ' clearance needs a new upload. See My Clearance.');
    END IF;
END $$;
COMMENT ON FUNCTION clearance.review_document(uuid, text, text, uuid) IS
  'V415: an office''s review of a clearance document — under review, approved, rejected or to upload again (with a reason); the student is told of a rejection.';

-- ── 15 · configuration: the Registry states a workflow and its stages ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.set_workflow(p_code text, p_label text, p_active boolean, p_reminder_days int,
                                                  p_certificate boolean, p_description text, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE clearance.workflow
       SET label = coalesce(nullif(btrim(p_label), ''), label), active = coalesce(p_active, active),
           reminder_days = coalesce(p_reminder_days, reminder_days), certificate = coalesce(p_certificate, certificate),
           description = coalesce(p_description, description), updated_by = p_actor, updated_at = now()
     WHERE code = upper(p_code);
    IF NOT FOUND THEN RAISE EXCEPTION 'CLR_NO_WORKFLOW: no such clearance' USING ERRCODE = '23514'; END IF;
END $$;

CREATE OR REPLACE FUNCTION clearance.set_stages(p_workflow text, p_stages jsonb, p_actor uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE s jsonb; n int := 0; v_units text[] := '{}'; v_ords int[] := '{}'; v_unit text; v_ord int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM clearance.workflow WHERE code = upper(p_workflow)) THEN
        RAISE EXCEPTION 'CLR_NO_WORKFLOW: no such clearance' USING ERRCODE = '23514';
    END IF;
    IF p_stages IS NULL OR jsonb_typeof(p_stages) <> 'array' OR jsonb_array_length(p_stages) = 0 THEN
        RAISE EXCEPTION 'CLR_STAGES: a clearance has at least one stage' USING ERRCODE = '23514';
    END IF;
    FOR s IN SELECT * FROM jsonb_array_elements(p_stages) LOOP
        v_unit := upper(btrim(s->>'unit'));
        v_ord := (s->>'ord')::int;
        IF NOT EXISTS (SELECT 1 FROM clearance.unit WHERE code = v_unit) THEN
            RAISE EXCEPTION 'CLR_NO_UNIT: no clearance office %', s->>'unit' USING ERRCODE = '23514';
        END IF;
        IF v_unit = ANY (v_units) THEN RAISE EXCEPTION 'CLR_STAGES: % is named twice', v_unit USING ERRCODE = '23514'; END IF;
        IF v_ord = ANY (v_ords) THEN RAISE EXCEPTION 'CLR_STAGES: two stages share the place %', v_ord USING ERRCODE = '23514'; END IF;
        v_units := v_units || v_unit; v_ords := v_ords || v_ord;
        INSERT INTO clearance.workflow_stage AS ws (workflow, unit, ord, required, waits, condition, programmes, faculties, departments, levels,
                                                    entry_modes, documents, deadline_days, instructions, active, updated_by, updated_at)
        VALUES (upper(p_workflow), v_unit, v_ord, coalesce((s->>'required')::boolean, true), coalesce((s->>'waits')::boolean, true),
                coalesce(nullif(s->>'condition', ''), 'ALWAYS'),
                coalesce(ARRAY(SELECT jsonb_array_elements_text(s->'programmes')), '{}'), coalesce(ARRAY(SELECT jsonb_array_elements_text(s->'faculties')), '{}'),
                coalesce(ARRAY(SELECT jsonb_array_elements_text(s->'departments')), '{}'), coalesce(ARRAY(SELECT jsonb_array_elements_text(s->'levels'))::int[], '{}'),
                coalesce(ARRAY(SELECT jsonb_array_elements_text(s->'entryModes')), '{}'),
                coalesce(ARRAY(SELECT btrim(x) FROM jsonb_array_elements_text(s->'documents') x WHERE btrim(x) <> ''), '{}'),
                nullif(s->>'deadlineDays', '')::int, nullif(btrim(coalesce(s->>'instructions', '')), ''), true, p_actor, now())
        ON CONFLICT (workflow, unit) DO UPDATE
           SET ord = EXCLUDED.ord, required = EXCLUDED.required, waits = EXCLUDED.waits, condition = EXCLUDED.condition,
               programmes = EXCLUDED.programmes, faculties = EXCLUDED.faculties, departments = EXCLUDED.departments, levels = EXCLUDED.levels,
               entry_modes = EXCLUDED.entry_modes, documents = EXCLUDED.documents, deadline_days = EXCLUDED.deadline_days,
               instructions = EXCLUDED.instructions, active = true, updated_by = p_actor, updated_at = now();
        n := n + 1;
    END LOOP;
    -- a stage left out is taken out of use, never deleted
    UPDATE clearance.workflow_stage SET active = false, updated_by = p_actor, updated_at = now()
     WHERE workflow = upper(p_workflow) AND active AND NOT (unit = ANY (v_units));
    RETURN n;
END $$;
COMMENT ON FUNCTION clearance.set_stages(text, jsonb, uuid) IS
  'V415: states a workflow''s stages — order, required, sequential or parallel, condition, scope, documents, deadline, instructions; a stage left out is made inactive, never deleted.';

-- ── 16 · reminders: at most once per process in the workflow's interval ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.remind(p_limit int DEFAULT 2000)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE w record; pr record; n int := 0; v_lines text; v_units text[]; v_q int; v_who text;
BEGIN
    FOR w IN SELECT * FROM clearance.workflow WHERE active AND reminder_days > 0 LOOP
        FOR pr IN
            SELECT p.* FROM clearance.process p
             WHERE p.workflow = w.code AND p.cancelled_at IS NULL AND p.completed_at IS NULL
               AND p.started_at < now() - make_interval(days => w.reminder_days)
               AND NOT EXISTS (SELECT 1 FROM clearance.reminder r WHERE r.process_id = p.id
                                AND r.sent_at > now() - make_interval(days => w.reminder_days))
             ORDER BY p.started_at
             LIMIT greatest(1, p_limit)
        LOOP
            SELECT string_agg(r.label || ': ' || CASE r.state WHEN 'PENDING' THEN 'pending' WHEN 'REQUIRES_ACTION' THEN 'requires your action'
                                                              WHEN 'NOT_CLEARED' THEN 'not cleared' WHEN 'REJECTED' THEN 'rejected'
                                                              ELSE lower(r.state) END, E'\n' ORDER BY r.ord),
                   array_agg(r.unit ORDER BY r.ord)
              INTO v_lines, v_units
              FROM clearance.stage_rows(w.purpose, pr.session, ARRAY[pr.student_id]) r
             WHERE r.required AND r.applies AND r.opened AND r.state IN ('PENDING', 'REQUIRES_ACTION', 'NOT_CLEARED', 'REJECTED');
            CONTINUE WHEN v_lines IS NULL;
            SELECT surname || ', ' || other_names INTO v_who FROM people.student WHERE id = pr.student_id;
            v_q := clearance.tell(pr.student_id, 'Reminder: your ' || lower(w.label) || ' is incomplete (' || pr.reference || ')',
                'Dear ' || coalesce(v_who, 'student') || ',' || E'\n\n' || 'Your ' || lower(w.label) || ' is not yet complete:' || E'\n\n' || v_lines
                || E'\n\n' || 'See My Clearance on the portal for what each office needs.' || E'\n\n' || clearance.signature(),
                'MOAUM reminder: your ' || lower(w.label) || ' is incomplete. See My Clearance on the portal.');
            INSERT INTO clearance.reminder (process_id, units, queued) VALUES (pr.id, v_units, v_q);
            n := n + 1;
        END LOOP;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION clearance.remind(int) IS
  'V415: reminds each student whose clearance has open stages outstanding — once per process in the workflow''s interval (reminder_days, 0 for none), never in its first interval; returns how many were reminded.';

-- ── 17 · the certificate's public check ──────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.verify(p_reference text, p_code text)
RETURNS TABLE (reference text, clearance text, session text, status text, completed_at timestamptz, student_name text,
               student_number text, programme text, faculty text, department text)
LANGUAGE sql STABLE AS $$
    SELECT p.reference, w.label, p.session, clearance.overall(p.id), p.completed_at, s.surname || ', ' || s.other_names,
           coalesce(s.matric_no, s.admission_no), pg.name, f.name, d.name
      FROM clearance.process p
      JOIN clearance.workflow w ON w.code = p.workflow
      JOIN people.student s ON s.id = p.student_id
      LEFT JOIN ref.programme pg ON pg.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = pg.dept_code
      LEFT JOIN ref.faculty f ON f.code = pg.faculty_code
     WHERE upper(p.reference) = upper(btrim(p_reference))
       AND p_code IS NOT NULL AND p.verify_code = lower(btrim(p_code))
$$;
COMMENT ON FUNCTION clearance.verify(text, text) IS
  'V415: the public check of a clearance certificate — only with the check code its QR carries; the reference, the clearance, the session, the status and the student''s name, number and programme, nothing more.';

-- ── 18 · the go-live data reset clears the clearance processes, their documents, reminders and alumni details too ──────
-- (V386's definition, restated from the database, with the five tables of V415 after clearance.item)
CREATE OR REPLACE FUNCTION platform.reset_operational_data(p_confirm text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a data reset is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm clearing all uploaded data' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a data reset names its reason' USING ERRCODE = '23514';
    END IF;

    SELECT jsonb_build_object(
        'students',     (SELECT count(*) FROM people.student),
        'candidates',   (SELECT count(*) FROM admissions.candidate),
        'applications', (SELECT count(*) FROM admissions.application),
        'results',      (SELECT count(*) FROM assessment.score),
        'courses',      (SELECT count(*) FROM catalogue.course),
        'fee_lines',    (SELECT count(*) FROM finance.fee_schedule),
        'payments',     (SELECT count(*) FROM finance.payment_reference),
        'wallet_entries', (SELECT count(*) FROM finance.wallet_entry),
        'staff_profiles', (SELECT count(*) FROM hrm.staff_profile),
        'pg_applications', (SELECT count(*) FROM admissions.pg_application),
        'college_enrolments', (SELECT count(*) FROM college.enrolment),
        'deferments', (SELECT count(*) FROM people.deferment)
    ) INTO r;

    PERFORM set_config('moaum.maintenance', 'on', true);
    UPDATE people.deferment SET fee_id = NULL WHERE fee_id IS NOT NULL;
    UPDATE credentials.issued SET request_id = NULL WHERE request_id IS NOT NULL;
    DELETE FROM admissions.caps_row_excluded;
    DELETE FROM admissions.eligibility_event;
    DELETE FROM admissions.programme_change_request;
    DELETE FROM admissions.eligibility_run;
    DELETE FROM admissions.pg_fee_reference;
    DELETE FROM admissions.pg_application;
    DELETE FROM admissions.pg_registration;
    DELETE FROM extexam.event;
    DELETE FROM extexam.assessment_score;
    DELETE FROM extexam.assessment;
    DELETE FROM extexam.assignment;
    DELETE FROM extexam.project_document_blob;
    DELETE FROM extexam.project_document;
    DELETE FROM extexam.project;
    DELETE FROM admissions.pg_research;
    DELETE FROM admissions.putme_event;
    DELETE FROM admissions.screening_answer;
    DELETE FROM admissions.screening_assignment;
    DELETE FROM admissions.screening_event;
    DELETE FROM admissions.screening_form;
    DELETE FROM admissions.screening_institution;
    DELETE FROM admissions.screening_olevel;
    DELETE FROM assessment.held_script;
    DELETE FROM assessment.siwes_supervisor;
    DELETE FROM college.assessment_score;
    DELETE FROM college.attendance_record;
    DELETE FROM college.carry_over;
    DELETE FROM college.case_clerking;
    DELETE FROM college.enrolment_semester;
    DELETE FROM college.enrolment;
    DELETE FROM college.event_attendance;
    DELETE FROM college.exam_result;
    DELETE FROM college.posting_allocation;
    DELETE FROM college.procedure_log;
    DELETE FROM college.progression_decision;
    DELETE FROM college.project;
    DELETE FROM credentials.delivery;
    DELETE FROM hostel.sanction;
    DELETE FROM hostel.incident;
    DELETE FROM hostel.swap_request;
    DELETE FROM hostel.transfer_request;
    DELETE FROM people.deferred_course;
    DELETE FROM people.deferment_fee;
    DELETE FROM people.deferment;
    DELETE FROM people.student_username_change;
    DELETE FROM people.matric_batch_edit;
    DELETE FROM people.matric_broadcast;
    DELETE FROM people.matric_reservation;
    DELETE FROM people.matric_batch_row;
    DELETE FROM people.matric_batch;
    DELETE FROM people.matric_history;

    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;
    DELETE FROM clearance.reminder;
    DELETE FROM clearance.document_blob;
    DELETE FROM clearance.document;
    DELETE FROM clearance.process;
    DELETE FROM clearance.alumni_profile;

    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;

    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;

    -- the wallet and its funding trail (the funding SOURCES and the wallet POLICY, settings, are kept)
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.legacy_nelfund_reconciliation;   -- V327: the reconciliation hangs on the wallet entries and the students
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.legacy_nelfund_payment;
    DELETE FROM finance.legacy_nelfund_import;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;

    DELETE FROM library.reservation;
    DELETE FROM library.loan;

    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;

    -- V358: the amendments of published results, and their decisions, before the queries and sheets they hang on
    DELETE FROM assessment.amendment_decision;
    DELETE FROM assessment.amendment;
    -- V359: the reminders and escalations of score sheets, before the sheets
    DELETE FROM assessment.sheet_chase;
    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    DELETE FROM finance.legacy_gst_reconciliation;
    DELETE FROM finance.legacy_gst_payment;
    DELETE FROM finance.legacy_gst_import;
    DELETE FROM finance.legacy_student_crosswalk;
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule;

    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office IN ('student', 'applicant');

    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;

    DELETE FROM assessment.sheet_upload;
    DELETE FROM assessment.score;
    DELETE FROM assessment.decision;
    DELETE FROM assessment.score_sheet;
    DELETE FROM assessment.exam_session;
    DELETE FROM assessment.cbt_event;
    DELETE FROM assessment.cbt_answer;
    DELETE FROM assessment.cbt_result;
    DELETE FROM assessment.cbt_attempt;
    DELETE FROM assessment.cbt_exam_question;
    DELETE FROM assessment.cbt_exam;
    DELETE FROM assessment.question;
    DELETE FROM registration.entry;
    DELETE FROM registration.course_registration;
    DELETE FROM catalogue.offering;
    DELETE FROM catalogue.course_alias;   -- V386: a merged code goes with the course it answers for
    DELETE FROM catalogue.course_offer;
    DELETE FROM catalogue.course;

    DELETE FROM people.faculty_list_query;
    DELETE FROM people.faculty_list;
    DELETE FROM people.biodata_change;
    DELETE FROM people.biodata;
    DELETE FROM people.document;
    DELETE FROM people.status_change;
    DELETE FROM people.enrolment;
    DELETE FROM people.search_log;
    DELETE FROM people.transfer_application;
    DELETE FROM people.student;
    DELETE FROM people.matriculation_run;

    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.lookup_miss;

    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.jamb_admission;
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    PERFORM set_config('moaum.maintenance', '', true);
    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $function$;

-- ── 19 · the Quick Operational Manual ────────────────────────────────────────────────────────────────────────────────
SELECT manual.seed('clearance-office-desk', 'Clear students at your office''s stage', 'STUDENTS',
    ARRAY['bursar', 'hod', 'dean', 'library', 'services', 'housing', 'alumni', 'registrar', 'dregistrar', 'academic']::text[], 't/clearance', NULL,
    'Give your office''s word on a student''s fresh or final clearance, against the record.',
    ARRAY['Open {menu:t/clearance}; choose `Fresh student clearance` or `Final clearance` and the `Session`.',
          'Use the tiles (`Awaiting you`, `Requires action`, `Not cleared`, `Cleared`) or `Search` by name, matric, JAMB or application number, or the clearance reference.',
          'Click `Open` on a student: read what the record says for your office (balance, loans, stays) and the documents.',
          'Click `Clear` when nothing is outstanding; the portal refuses while the record shows something outstanding.',
          'Otherwise choose `Not cleared` (name the item), `Requires action` (say what to do) or `Reject` (the reason); add an `Official remark` the student sees and an `Internal note` they never see.',
          'Approve or reject each uploaded document with a reason; tick several students and click `Clear the selected` for many.'],
    'The student is told by e-mail and SMS; the next office opens; every word is kept with its officer, time and evidence.', '{}'::text[], 70);
SELECT manual.seed('clearance-manage', 'Run fresh and final clearance', 'STUDENTS', ARRAY['academic', 'registrar', 'dregistrar', 'super', 'admin']::text[], 't/clearancemanage', NULL,
    'Start clearance for the eligible students, watch every office, and set the workflows.',
    ARRAY['Open {menu:t/clearancemanage}; choose the clearance and the `Session`.',
          'Read the figures (not started, in progress, cleared, requires action) and each office''s breakdown; click a figure for the students.',
          'Click `Start for the eligible students` — each is told once; or start one student by number with a reason.',
          'Under `Workflow`, set each office''s order, `Required`, `Waits for the earlier offices`, the condition (hostel only if applied or allocated), documents and deadline; click `Save the workflow`.',
          'Click `Export (Excel)` or `PDF` for the clearance report.'],
    'Each clearance carries a reference (CLR/…, FCLR/…); a stage taken out of the workflow is kept, not deleted.', '{}'::text[], 71);
SELECT manual.seed('student-my-clearance', 'Complete your clearance', 'STUDENTS', ARRAY['student']::text[], 's/clearance', NULL,
    'Follow each office''s word on your fresh or final clearance and do what it asks.',
    ARRAY['Open {menu:s/clearance}.',
          'Read each office: cleared, pending, requires action, not cleared or not required.',
          'Click an office for its remark and what to do; for a document it asks for, click `Upload …` and choose the file (PDF, JPEG or PNG, up to 5 MB).',
          'For final clearance, complete `Alumni details` and click `Confirm my details`.',
          'When every office has cleared you, click `Download the clearance certificate`.'],
    'The office sees your upload on its desk; you are told by e-mail and SMS when an office decides.', '{}'::text[], 20);

COMMIT;

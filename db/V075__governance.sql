-- ═══════════════════════════════════════════════════════════════════════════
-- V075 — data governance (Nigeria Data Protection Act 2023)
--
--   Three real records the office keeps: the register of processing activities
--   (what personal data the University processes, on what lawful basis, for how
--   long, and whether a DPIA is done); the log of data-subject rights requests
--   (access, rectification, erasure, portability, objection), each with its
--   statutory due date; and the disaster-recovery drill log. The register is the
--   University's own processing record and is seeded; the request log holds
--   personal data and starts empty; drills are recorded as they are run.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'registrar', true);
    PERFORM set_config('moaum.reason', 'V075: data governance register', true);
END $seed$;

CREATE TABLE governance.processing_activity (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    activity     text NOT NULL,
    lawful_basis text NOT NULL,
    sensitive    boolean NOT NULL DEFAULT false,
    retention    text NOT NULL,
    dpia_state   text NOT NULL DEFAULT 'NOT_REQUIRED',
    note         text NULL,
    CONSTRAINT ck_pa_dpia CHECK (dpia_state IN ('NOT_REQUIRED','OUTSTANDING','COMPLETE')),
    CONSTRAINT ck_pa_activity CHECK (btrim(activity) <> '')
);
SELECT audit.attach('governance.processing_activity');

CREATE TABLE governance.dsr (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference   text NOT NULL UNIQUE,
    kind        text NOT NULL,
    requester   text NOT NULL,
    received_on date NOT NULL DEFAULT current_date,
    due_on      date NOT NULL,
    state       text NOT NULL DEFAULT 'RECEIVED',
    note        text NULL,
    CONSTRAINT ck_dsr_kind CHECK (kind IN ('ACCESS','RECTIFICATION','ERASURE','PORTABILITY','OBJECTION')),
    CONSTRAINT ck_dsr_state CHECK (state IN ('RECEIVED','IN_PROGRESS','COMPLETED','REFUSED'))
);
CREATE INDEX ix_dsr_state ON governance.dsr (state, due_on);
SELECT audit.attach('governance.dsr');

CREATE TABLE governance.dr_drill (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind        text NOT NULL,
    ran_on      date NOT NULL,
    rpo_minutes int NULL,
    rto_minutes int NULL,
    outcome     text NOT NULL DEFAULT 'PASSED',
    note        text NULL,
    CONSTRAINT ck_drill_kind CHECK (kind IN ('RESTORE_VERIFY','FULL_DR','FAILOVER','BACKUP')),
    CONSTRAINT ck_drill_outcome CHECK (outcome IN ('PASSED','FAILED','PARTIAL'))
);
CREATE INDEX ix_drill_ran ON governance.dr_drill (ran_on DESC);
SELECT audit.attach('governance.dr_drill');

-- the University's record of processing activities (the register itself, not metrics)
INSERT INTO governance.processing_activity (activity, lawful_basis, sensitive, retention, dpia_state) VALUES
 ('Student academic records',                 'Legal obligation · public task',        false, 'Permanent',                    'NOT_REQUIRED'),
 ('Staff personnel and payroll records',      'Contract · legal obligation',           false, 'Duration of service + statutory','NOT_REQUIRED'),
 ('Payment and financial records',            'Legal obligation',                      false, 'Statutory (tax) retention',    'NOT_REQUIRED'),
 ('Biometric identity verification at CBT',   'Explicit consent',                      true,  'Duration of study + 1 year',   'COMPLETE'),
 ('Health records (University clinic)',        'Vital interests · explicit consent',    true,  '7 years after last contact',   'COMPLETE'),
 ('Automated admission scoring',              'Public task',                           false, '7 years',                      'OUTSTANDING'),
 ('CBT proctoring and session logging',       'Public task · legitimate interest',     true,  '5 years',                      'OUTSTANDING');

COMMIT;

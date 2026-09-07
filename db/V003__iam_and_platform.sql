-- ═══════════════════════════════════════════════════════════════════════════
-- V003 — the first module on the spine, and the platform machinery
--
-- `iam.office_assignment` is built first deliberately. It is the table the
-- whole authorisation model rests on, and it carries the one constraint that
-- closes the loop between Human Resource Management and every other office:
--
--   instrument text NOT NULL
--
-- Every office in this University is held by virtue of a letter or a Council
-- minute. An acting appointment nobody authorised cannot be typed into
-- existence, because there would be nothing to cite. Approved is not
-- implemented until the instrument is issued (I-IAM-9), and the database is
-- where that is true rather than a screen.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE iam.person (
    id           uuid PRIMARY KEY,
    staff_number text UNIQUE,
    surname      text NOT NULL,
    given_names  text NOT NULL,
    ended_on     date NULL,          -- D11: ended, never deleted
    ended_reason text NULL,
    CONSTRAINT ck_person_ended CHECK (ended_on IS NULL OR ended_reason IS NOT NULL)
);

CREATE TABLE iam.office_assignment (
    id           uuid PRIMARY KEY,
    person_id    uuid NOT NULL REFERENCES iam.person(id) ON DELETE RESTRICT,
    office_code  text NOT NULL REFERENCES ref.office(code) ON DELETE RESTRICT,
    scope_kind   text NOT NULL,
    scope_id     text NULL,
    instrument   text NOT NULL,      -- the letter or minute. NOT NULL is the rule.
    granted_by   uuid NOT NULL,
    valid_from   date NOT NULL,
    valid_to     date NULL,          -- an acting appointment is dated at both ends
    CONSTRAINT ck_grant_instrument CHECK (length(btrim(instrument)) > 0),
    CONSTRAINT ck_grant_dates      CHECK (valid_to IS NULL OR valid_to >= valid_from),
    CONSTRAINT ck_grant_scope      CHECK (scope_kind IN
        ('institution','college','faculty','department','programme',
         'course','unit','platform'))
);

COMMENT ON COLUMN iam.office_assignment.instrument IS
  'The letter or Council minute the office is held by. NOT NULL, so an office '
  'nobody authorised cannot come into existence. An acting appointment with no '
  'end date is the commonest real privilege escalation there is — hence valid_to.';

-- An office is ADDED to a person, never substituted: a Head of Department is
-- still a lecturer and keeps both rows. So the key is (person, office, scope,
-- from) and not (person, office).
CREATE UNIQUE INDEX uq_grant_one_live
    ON iam.office_assignment (person_id, office_code, coalesce(scope_id, ''))
 WHERE valid_to IS NULL;

SELECT audit.attach('iam.person');
SELECT audit.attach('iam.office_assignment');

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA iam TO app_iam;
GRANT SELECT ON ALL TABLES IN SCHEMA iam TO app_auditor;

-- ── platform machinery ────────────────────────────────────────────────────

-- ADR-017: server-side sessions. Revocation is the requirement, and a JWT
-- cannot be un-issued. The cookie carries a 256-bit opaque id and nothing else.
CREATE TABLE platform.session (
    id            bytea       PRIMARY KEY,
    person_id     uuid        NOT NULL,
    active_office text        NOT NULL REFERENCES ref.office(code),
    issued_at     timestamptz NOT NULL DEFAULT now(),
    last_seen_at  timestamptz NOT NULL DEFAULT now(),
    absolute_end  timestamptz NOT NULL,
    ended_at      timestamptz NULL,
    ended_reason  text        NULL,
    CONSTRAINT ck_session_id_len CHECK (octet_length(id) = 32)
);
CREATE INDEX ix_session_person ON platform.session (person_id) WHERE ended_at IS NULL;

-- NFR-AVA-007. A retried request must not do the thing twice.
CREATE TABLE platform.idempotency_key (
    key          text        PRIMARY KEY,
    scope        text        NOT NULL,
    response     jsonb       NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);

-- Delivery is at-least-once (ADR-005), so every handler is idempotent AND
-- records what it has already processed. The registry retries; this refuses
-- the second application.
CREATE TABLE platform.processed_event (
    consumer     text        NOT NULL,
    event_id     uuid        NOT NULL,
    processed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (consumer, event_id)
);

-- BR-007: a matriculation number is permanent and never reused, and a run
-- allocates every number or none. One sequence per (kind, scope, session).
CREATE TABLE platform.number_series (
    kind        text     NOT NULL,
    scope       text     NOT NULL,
    session     text     NOT NULL,
    next_value  bigint   NOT NULL,
    PRIMARY KEY (kind, scope, session),
    CONSTRAINT ck_series_next CHECK (next_value > 0)
);

SELECT audit.exempt('platform.session',
    'Session rows are written and touched on every request; auditing a '
    'last_seen_at update would bury the entries somebody actually needs to '
    'find. Sign-in, sign-out and every failure are logged separately.');
SELECT audit.exempt('platform.idempotency_key',
    'A retry key is machinery, not a decision. The act it protects is on the '
    'spine; recording the key as well records the same event twice.');
SELECT audit.exempt('platform.processed_event',
    'Consumer-side dedupe. The event was audited where it was published; a '
    'handler noting that it has seen it is bookkeeping about bookkeeping.');
SELECT audit.exempt('platform.number_series',
    'The counter moves; what matters is the number issued and to whom, which '
    'is audited on the record that received it (BR-007).');

GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform TO app_platform;
GRANT SELECT ON ALL TABLES IN SCHEMA platform TO app_auditor;

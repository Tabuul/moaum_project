-- ═══════════════════════════════════════════════════════════════════════════
-- V002 — the audit spine
--
-- The design set contradicted itself here, and this file is the resolution.
--
--   ARC §12 and ADR-016 say an ASPECT writes the audit row and the
--   application role holds INSERT.
--   DSN D12, SEC §8 and I-SEC-1 say the application has NO write path:
--   "It is appended by the persistence layer and by database triggers, and
--   no service — however privileged — exposes a method that writes to it."
--
-- These are not the same design, and the second is strictly stronger on both
-- properties that matter. An aspect can be escaped by a repository call
-- written outside a command service, and a role holding INSERT can write a
-- FALSE audit row. A trigger can be escaped by neither.
--
-- But a trigger sees a row, not an intent. It cannot know the acting office,
-- the reason or the correlation id, because none of them is a column on the
-- business table — and that is exactly why the aspect existed.
--
-- So both documents were describing half of one mechanism, and the whole is:
--
--   · the application sets the audit context on the TRANSACTION
--     (SET LOCAL moaum.actor_id / moaum.actor_office / …), which is what the
--     aspect now does, and is all it does;
--   · the trigger reads that context and writes the row;
--   · the trigger REFUSES the write when the context is absent.
--
-- The last line is the one worth having. D6 says "there is no unattributed
-- state change"; P5 says every state change is attributable. Until now both
-- were promises kept by discipline. Here they are kept by the database: a
-- service that forgets the context cannot write to a business table at all.
-- It fails in the first developer's first test, not in an investigation
-- three years later.
--
-- Prevention against a database superuser is not achievable. DETECTION is,
-- and it is cheap (ADR-018) — hence the chain.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── the entries ───────────────────────────────────────────────────────────
CREATE TABLE audit.entries (
    id              uuid        NOT NULL,
    occurred_at     timestamptz NOT NULL,
    period          date        NOT NULL,      -- first day of the month
    shard           smallint    NOT NULL,
    seq             bigint      NOT NULL,      -- position within (period, shard)
    actor_id        uuid        NOT NULL,
    actor_office    text        NOT NULL,
    action          text        NOT NULL,
    subject_type    text        NOT NULL,
    subject_id      uuid        NOT NULL,
    before_state    jsonb       NULL,
    after_state     jsonb       NULL,
    reason          text        NULL,
    correlation_id  uuid        NULL,
    source_ip       inet        NULL,
    prev_hash       bytea       NULL,
    entry_hash      bytea       NOT NULL,
    PRIMARY KEY (occurred_at, id),
    CONSTRAINT ck_entries_shard CHECK (shard BETWEEN 0 AND 15),
    CONSTRAINT ck_entries_office
        CHECK (actor_office <> '' AND length(actor_office) <= 32)
) PARTITION BY RANGE (occurred_at);

COMMENT ON COLUMN audit.entries.actor_office IS
  'The capacity the act was made in, not the offices the person holds today. '
  'A person holding two offices acts in exactly one at a time, and an approval '
  'recorded without saying which cannot be checked against BR-006 afterwards.';

CREATE INDEX ix_entries_subject ON audit.entries (subject_type, subject_id, occurred_at DESC);
CREATE INDEX ix_entries_actor   ON audit.entries (actor_id, occurred_at DESC);

-- ── the chain heads ───────────────────────────────────────────────────────
-- A chain per (month, shard). DBD §5.2 specifies a chain per partition; a
-- single head row per month would serialise every state change in the
-- University through one row, and NFR-PER-002 asks for 8,000 concurrent
-- registrations. Sixteen shards keep the detection property — every entry is
-- still linked to a predecessor and a break is still found — and give the
-- writes somewhere to go. Verification walks sixteen chains per month
-- instead of one.
-- The genesis link. The writer seeds a new chain with this value and the
-- verifier starts from it; they were different constants in the first cut
-- (NULL here, '\x00' there) and every chain read as broken on the first
-- entry. A chain is a shared convention between two pieces of code, so the
-- convention is named once and both read it.
CREATE OR REPLACE FUNCTION audit.genesis() RETURNS bytea
LANGUAGE sql IMMUTABLE AS $$ SELECT '\x00'::bytea $$;

-- The primary key of each attached table, resolved once at attach time
-- rather than by a catalogue lookup on every row. The trigger originally
-- assumed a column called `id`; the first table keyed on anything else
-- (policy.grade_band, on (version_id, grade)) produced a NULL subject and
-- took the shard down with it. An assumption about somebody else's table is
-- exactly the kind that holds until it doesn't.
CREATE TABLE audit.subject_key (
    relid oid    PRIMARY KEY,
    cols  text[] NOT NULL
);

CREATE TABLE audit.chain_head (
    period     date     NOT NULL,
    shard      smallint NOT NULL,
    last_hash  bytea    NOT NULL,
    last_seq   bigint   NOT NULL DEFAULT 0,
    PRIMARY KEY (period, shard)
);

-- ── partitions ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION audit.ensure_partition(p_at timestamptz)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, audit
AS $$
DECLARE
    p_start date := date_trunc('month', p_at)::date;
    p_end   date := (date_trunc('month', p_at) + interval '1 month')::date;
    p_name  text := 'entries_' || to_char(p_start, 'YYYYMM');
BEGIN
    IF to_regclass('audit.' || quote_ident(p_name)) IS NULL THEN
        EXECUTE format(
            'CREATE TABLE audit.%I PARTITION OF audit.entries '
            'FOR VALUES FROM (%L) TO (%L)', p_name, p_start, p_end);
        EXECUTE format('REVOKE ALL ON audit.%I FROM PUBLIC', p_name);
    END IF;
END $$;

DO $$
DECLARE m int;
BEGIN
    FOR m IN 0..23 LOOP
        PERFORM audit.ensure_partition(
            (date '2026-09-01' + (m || ' months')::interval)::timestamptz);
    END LOOP;
END $$;

-- ── the canonical form a hash is taken over ───────────────────────────────
-- jsonb renders with sorted keys and normalised whitespace, so two equal
-- values always produce the same text. That is what makes the chain
-- recomputable years later by somebody who no longer has this code.
CREATE OR REPLACE FUNCTION audit.canonical(e audit.entries)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT convert_to(
        concat_ws('|',
            e.id::text,
            to_char(e.occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
            e.seq::text,
            e.actor_id::text,
            e.actor_office,
            e.action,
            e.subject_type,
            e.subject_id::text,
            coalesce(e.before_state::text, ''),
            coalesce(e.after_state::text, ''),
            coalesce(e.reason, ''),
            coalesce(e.correlation_id::text, '')
        ), 'UTF8');
$$;

-- ── the writer ────────────────────────────────────────────────────────────
-- SECURITY DEFINER: it runs as the owner of this schema, which is the only
-- role with INSERT on audit.entries. The calling application role has none,
-- and cannot acquire any by being privileged in its own schema.
CREATE OR REPLACE FUNCTION audit.record()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, audit, public
AS $$
DECLARE
    v_actor   uuid;
    v_office  text;
    v_reason  text;
    v_corr    uuid;
    v_ip      inet;
    v_before  jsonb;
    v_after   jsonb;
    v_subject uuid;
    v_at      timestamptz := clock_timestamp();
    v_period  date;
    v_shard   smallint;
    v_prev    bytea;
    v_seq     bigint;
    v_id      uuid := gen_random_uuid();
    v_cols    text[];
    v_row     jsonb;
    e         audit.entries;
BEGIN
    -- 1. the context, or a refusal
    v_actor  := nullif(current_setting('moaum.actor_id',     true), '')::uuid;
    v_office := nullif(current_setting('moaum.actor_office', true), '');

    IF v_actor IS NULL OR v_office IS NULL THEN
        RAISE EXCEPTION
            'unattributed change to %.% — no audit context on this transaction',
            TG_TABLE_SCHEMA, TG_TABLE_NAME
        USING ERRCODE = '23514',
              HINT = 'SET LOCAL moaum.actor_id and moaum.actor_office before writing. '
                     'Every state change is attributable (P5, D6); there is no exemption.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ref.office WHERE code = v_office) THEN
        RAISE EXCEPTION 'no such office: %', v_office
        USING ERRCODE = '23514',
              HINT = 'The acting office must be one of the twenty-five in ref.office.';
    END IF;

    v_reason := nullif(current_setting('moaum.reason',         true), '');
    v_corr   := nullif(current_setting('moaum.correlation_id', true), '')::uuid;
    v_ip     := nullif(current_setting('moaum.source_ip',      true), '')::inet;

    -- 2. what changed
    IF TG_OP = 'DELETE' THEN
        -- D11: nothing is deleted. If a DELETE reaches here at all, it is
        -- recorded before it is refused elsewhere — the record is the point.
        v_before := to_jsonb(OLD); v_after := NULL;          v_row := to_jsonb(OLD);
    ELSIF TG_OP = 'UPDATE' THEN
        v_before := to_jsonb(OLD); v_after := to_jsonb(NEW); v_row := to_jsonb(NEW);
    ELSE
        v_before := NULL;          v_after := to_jsonb(NEW); v_row := to_jsonb(NEW);
    END IF;

    -- The subject is the row's own id where it has one, and otherwise a
    -- deterministic uuid over its primary key — stable across an update, so
    -- the before and after of one row share a subject and sort together.
    SELECT k.cols INTO v_cols FROM audit.subject_key k WHERE k.relid = TG_RELID;
    IF v_cols = ARRAY['id'] THEN
        v_subject := (v_row->>'id')::uuid;
    ELSE
        v_subject := md5(TG_RELID::text || '|' ||
                         (SELECT string_agg(coalesce(v_row->>c, ''), '|' ORDER BY o)
                            FROM unnest(v_cols) WITH ORDINALITY AS t(c, o)))::uuid;
    END IF;

    -- 3. the chain this entry joins
    v_period := date_trunc('month', v_at)::date;
    v_shard  := (abs(hashtext(v_subject::text)) % 16)::smallint;

    PERFORM audit.ensure_partition(v_at);

    INSERT INTO audit.chain_head (period, shard, last_hash, last_seq)
    VALUES (v_period, v_shard, audit.genesis(), 0)
    ON CONFLICT (period, shard) DO NOTHING;

    SELECT last_hash, last_seq INTO v_prev, v_seq
      FROM audit.chain_head
     WHERE period = v_period AND shard = v_shard
     FOR UPDATE;                      -- serialises this chain, and only this one

    v_seq := v_seq + 1;

    -- 4. the entry, and its link to the one before it
    e := ROW(v_id, v_at, v_period, v_shard, v_seq, v_actor, v_office,
             coalesce(TG_ARGV[0], TG_OP), TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
             v_subject, v_before, v_after, v_reason, v_corr, v_ip,
             v_prev, '\x00'::bytea);

    INSERT INTO audit.entries (
        id, occurred_at, period, shard, seq, actor_id, actor_office, action,
        subject_type, subject_id, before_state, after_state, reason,
        correlation_id, source_ip, prev_hash, entry_hash)
    VALUES (
        e.id, e.occurred_at, e.period, e.shard, e.seq, e.actor_id, e.actor_office,
        e.action, e.subject_type, e.subject_id, e.before_state, e.after_state,
        e.reason, e.correlation_id, e.source_ip, v_prev,
        digest(audit.canonical(e) || coalesce(v_prev, ''::bytea), 'sha256'));

    UPDATE audit.chain_head
       SET last_hash = digest(audit.canonical(e) || coalesce(v_prev, ''::bytea), 'sha256'),
           last_seq  = v_seq
     WHERE period = v_period AND shard = v_shard;

    RETURN COALESCE(NEW, OLD);
END $$;

-- ── attaching it ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION audit.attach(p_table regclass, p_action text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    t text := p_table::text;
    n text := 'trg_audit_' || replace(replace(t, '.', '_'), '"', '');
    k text[];
BEGIN
    SELECT array_agg(a.attname ORDER BY x.ord) INTO k
      FROM pg_index i
      JOIN LATERAL unnest(i.indkey) WITH ORDINALITY AS x(attnum, ord) ON true
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = x.attnum
     WHERE i.indrelid = p_table AND i.indisprimary;

    IF k IS NULL THEN
        RAISE EXCEPTION 'cannot attach the audit spine to % — it has no primary key', t
        USING HINT = 'A row with no identity cannot be the subject of an audit entry.';
    END IF;

    INSERT INTO audit.subject_key (relid, cols) VALUES (p_table::oid, k)
    ON CONFLICT (relid) DO UPDATE SET cols = excluded.cols;

    EXECUTE format(
        'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %s '
        'FOR EACH ROW EXECUTE FUNCTION audit.record(%s)',
        n, t, CASE WHEN p_action IS NULL THEN '' ELSE quote_literal(p_action) END);
END $$;

COMMENT ON FUNCTION audit.attach(regclass, text) IS
  'Attach the audit spine to a business table. A table that holds state and '
  'is not attached is the defect this function exists to make visible: the '
  'nightly check in audit.unattached() lists them.';

-- ── the two checks ────────────────────────────────────────────────────────

-- I-SEC-2: a nightly job recomputes the chain and reports discrepancies to
-- the Registrar and the Director of ICT — not to ICT alone. The office that
-- runs the system is not the only office told when its log is wrong.
CREATE OR REPLACE FUNCTION audit.verify_chain(p_period date DEFAULT NULL)
RETURNS TABLE (period date, shard smallint, entries bigint, ok boolean,
               first_break uuid, broke_at timestamptz)
LANGUAGE plpgsql
AS $$
DECLARE
    c        record;
    e        audit.entries;
    v_prev   bytea;
    v_bad    uuid;
    v_badat  timestamptz;
    v_n      bigint;
BEGIN
    FOR c IN SELECT ch.period AS p, ch.shard AS s FROM audit.chain_head ch
             WHERE p_period IS NULL OR ch.period = p_period
             ORDER BY ch.period, ch.shard
    LOOP
        v_prev := audit.genesis(); v_bad := NULL; v_badat := NULL; v_n := 0;
        FOR e IN SELECT * FROM audit.entries en
                  WHERE en.period = c.p AND en.shard = c.s
                  ORDER BY en.seq
        LOOP
            v_n := v_n + 1;
            IF v_bad IS NULL THEN
                IF e.prev_hash IS DISTINCT FROM v_prev
                   OR e.entry_hash <> digest(audit.canonical(e) ||
                                             coalesce(v_prev, ''::bytea), 'sha256')
                THEN
                    v_bad := e.id; v_badat := e.occurred_at;
                END IF;
            END IF;
            v_prev := e.entry_hash;
        END LOOP;
        period := c.p; shard := c.s; entries := v_n;
        ok := (v_bad IS NULL); first_break := v_bad; broke_at := v_badat;
        RETURN NEXT;
    END LOOP;
END $$;

-- Some tables genuinely should not be on the spine. The first version of
-- this file expressed that as a hardcoded list of schemas, and the list
-- silently swallowed `policy` the moment those tables were added — so a
-- change to what a fee instalment unlocks went unrecorded while the check
-- reported "none unattached".
--
-- An exemption is therefore a ROW, and it carries a reason. A table is on the
-- spine, or it is exempt for a written reason, or it is a defect. There is no
-- fourth state and no list to fall out of.
CREATE TABLE audit.exemption (
    relid  oid  PRIMARY KEY,
    reason text NOT NULL,
    CONSTRAINT ck_exemption_reason CHECK (length(btrim(reason)) > 20)
);

CREATE OR REPLACE FUNCTION audit.exempt(p_table regclass, p_reason text)
RETURNS void
LANGUAGE sql
AS $$
    INSERT INTO audit.exemption (relid, reason) VALUES (p_table::oid, p_reason)
    ON CONFLICT (relid) DO UPDATE SET reason = excluded.reason;
$$;

COMMENT ON FUNCTION audit.exempt(regclass, text) IS
  'Exempt a table from the audit spine, with a reason somebody has to write. '
  'The reason is the point: an exemption nobody had to justify is how the '
  'policy tables went unaudited for a version.';

-- A table that holds state and is neither attached nor exempted is a silent
-- hole in the spine. Silence is the failure mode this system exists to
-- remove, so the hole is enumerated rather than assumed absent.
CREATE OR REPLACE FUNCTION audit.unattached()
RETURNS TABLE (missing text)
LANGUAGE sql
AS $$
    SELECT (c.relnamespace::regnamespace || '.' || c.relname)::text
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind = 'r'
       -- Two schemas are exempt wholesale and each for a stated reason:
       --   audit     — the spine cannot audit itself; it is chained instead
       --   reporting — derived read models, refreshed from events already audited
       -- Everything else earns its exemption one table at a time, in
       -- audit.exemption, with a reason.
       AND n.nspname NOT IN ('audit','reporting','pg_catalog','information_schema')
       AND n.nspname NOT LIKE 'pg\_temp%'
       AND n.nspname NOT LIKE 'pg\_toast%'
       AND NOT EXISTS (SELECT 1 FROM audit.exemption e WHERE e.relid = c.oid)
       AND NOT EXISTS (SELECT 1 FROM pg_trigger tg
                        WHERE tg.tgrelid = c.oid AND NOT tg.tgisinternal
                          AND tg.tgname LIKE 'trg_audit_%')
     ORDER BY 1;
$$;

-- ── permissions: the whole point of the file ──────────────────────────────
REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM PUBLIC;
REVOKE ALL ON SCHEMA audit FROM PUBLIC;

-- Every application role may execute the trigger function and read nothing.
-- USAGE on the schema is required for the SECURITY DEFINER call to resolve;
-- it grants no access to any table in it.
DO $$
DECLARE r text;
BEGIN
    FOR r IN SELECT rolname FROM pg_roles WHERE rolname LIKE 'app\_%'
    LOOP
        EXECUTE format('GRANT USAGE ON SCHEMA audit TO %I', r);
        EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA audit FROM %I', r);
    END LOOP;
END $$;

-- Internal Audit reads. It writes nothing, anywhere, and that is a property
-- of what exists rather than of a permission somebody could grant later.
GRANT SELECT ON ALL TABLES IN SCHEMA audit TO app_auditor;
GRANT EXECUTE ON FUNCTION audit.verify_chain(date) TO app_auditor;
GRANT EXECUTE ON FUNCTION audit.unattached() TO app_auditor;

-- Nobody, including the owner's application roles, may amend or remove an
-- entry. The retention role is the only role in the estate with DELETE, and
-- it does not have it here: audit is kept 7 years and archived by partition,
-- not deleted row by row.
REVOKE UPDATE, DELETE ON audit.entries FROM PUBLIC;

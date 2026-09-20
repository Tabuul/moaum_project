-- ═══════════════════════════════════════════════════════════════════════════
-- V194 — audit spine tolerates an audited table whose primary key is not a uuid
--
--   audit.record() computed the entry's subject as (row->>'id')::uuid whenever
--   the primary key was the single column "id". Every audited table has had a
--   uuid id — except finance.fee_setting (V083), whose id is the integer 1 and
--   which was attached to the spine in V086. Any write to it therefore raised
--   "invalid input syntax for type uuid: 1", so the Bursary could never set the
--   transfer fee or the home State, and a property that writes it errors.
--
--   The fix: take the uuid fast path only when the id actually is a uuid; a
--   non-uuid single-column key falls to the same deterministic md5-over-the-key
--   path the composite keys already use. Nothing else in audit.record() changes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

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

    -- The subject is the row's own id where it has one AND that id is a uuid, and
    -- otherwise a deterministic uuid over its primary key — stable across an update,
    -- so the before and after of one row share a subject and sort together. A single
    -- integer key (finance.fee_setting) takes the md5 path, not the uuid cast.
    SELECT k.cols INTO v_cols FROM audit.subject_key k WHERE k.relid = TG_RELID;
    IF v_cols = ARRAY['id']
       AND (v_row->>'id') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
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

COMMIT;

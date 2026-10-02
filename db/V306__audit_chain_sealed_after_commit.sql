-- ═══════════════════════════════════════════════════════════════════════════
-- V306 — the audit chain is sealed after commit, not locked during the write
--
--   Until now audit.record() took a row lock on audit.chain_head (period, shard)
--   for every audited write and held it to the end of the transaction, because the
--   entry's hash links to the previous entry of that shard. A transaction writing
--   fifty rows holds all sixteen shards for as long as it runs: production showed a
--   student's sign-in UPDATE waiting 17 minutes behind an import, a payment
--   confirmation waiting 4 minutes, and 23,988 deadlocks in 25 days (two
--   multi-row transactions taking shards in different orders). A deadlock aborts
--   one side, which is how an import batch is "refused".
--
--   Now the trigger only INSERTS: no lock, no chain_head. Each entry carries a
--   number from a global sequence (its canonical form, and so its hash, still
--   includes it). audit.seal_chain() runs every few seconds (the API's sealer) and
--   at the start of every verification: it takes the committed, unsealed entries
--   of each shard in insertion order, gives each its position in the chain
--   (chain_seq) and its hashes exactly as before (prev_hash, entry_hash =
--   sha256(canonical || prev)), and moves chain_head on. The hash formula and the
--   stored hashes of every existing entry are unchanged, so the chain built so far
--   verifies as it did, and the new tail continues it.
--
--   What this trades: an entry is tamper-evident from the moment it is sealed —
--   seconds after commit — rather than from the commit itself. The verifier reports
--   how many entries are still unsealed, and the sealer is single-threaded by an
--   advisory lock. Nothing an application role may do has changed: it still cannot
--   insert, update or delete an audit row (check.sql §13, §14).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE audit.entries ALTER COLUMN entry_hash DROP NOT NULL;
ALTER TABLE audit.entries ADD COLUMN IF NOT EXISTS chain_seq bigint NULL;
COMMENT ON COLUMN audit.entries.chain_seq IS
  'Position in the (period, shard) chain, given when the entry is sealed (V306). Entries sealed before V306 '
  'keep their position in seq; the chain is walked by coalesce(chain_seq, seq). NULL with a NULL entry_hash = not yet sealed.';
COMMENT ON COLUMN audit.entries.seq IS
  'Before V306: the position in the (period, shard) chain. From V306: a global insertion number (audit.entry_seq), '
  'part of the canonical form the hash is taken over; the chain position is chain_seq.';

-- the insertion number: above every chain position so far, so the two never read alike
CREATE SEQUENCE IF NOT EXISTS audit.entry_seq AS bigint;
SELECT setval('audit.entry_seq', greatest(coalesce((SELECT max(last_seq) FROM audit.chain_head), 0), 0) + 1000000, false);

-- ── the writer: an insert, and nothing held ───────────────────────────────
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
    v_id      uuid := gen_random_uuid();
    v_cols    text[];
    v_row     jsonb;
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
    -- integer key (finance.fee_setting) takes the md5 path, not the uuid cast (V194).
    SELECT k.cols INTO v_cols FROM audit.subject_key k WHERE k.relid = TG_RELID;
    IF v_cols = ARRAY['id']
       AND (v_row->>'id') ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        v_subject := (v_row->>'id')::uuid;
    ELSE
        v_subject := md5(TG_RELID::text || '|' ||
                         (SELECT string_agg(coalesce(v_row->>c, ''), '|' ORDER BY o)
                            FROM unnest(v_cols) WITH ORDINALITY AS t(c, o)))::uuid;
    END IF;

    -- 3. the chain this entry will join, once sealed
    v_period := date_trunc('month', v_at)::date;
    v_shard  := (abs(hashtext(v_subject::text)) % 16)::smallint;

    PERFORM audit.ensure_partition(v_at);

    -- 4. the entry; its link to the one before it is made by audit.seal_chain()
    INSERT INTO audit.entries (
        id, occurred_at, period, shard, seq, actor_id, actor_office, action,
        subject_type, subject_id, before_state, after_state, reason,
        correlation_id, source_ip, prev_hash, entry_hash, chain_seq)
    VALUES (
        v_id, v_at, v_period, v_shard, nextval('audit.entry_seq'), v_actor, v_office,
        coalesce(TG_ARGV[0], TG_OP), TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        v_subject, v_before, v_after, v_reason, v_corr, v_ip,
        NULL, NULL, NULL);

    RETURN COALESCE(NEW, OLD);
END $$;

-- ── the sealer: committed entries join their shard's chain, in insertion order ─
CREATE OR REPLACE FUNCTION audit.seal_chain(p_limit int DEFAULT 50000)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, audit, public
AS $$
DECLARE
    c       record;
    e       audit.entries;
    v_prev  bytea;
    v_seq   bigint;
    v_hash  bytea;
    n       int := 0;
BEGIN
    -- one sealer at a time; a second caller simply finds nothing to do
    IF NOT pg_try_advisory_xact_lock(hashtext('audit.seal_chain')) THEN
        RETURN 0;
    END IF;

    FOR c IN SELECT DISTINCT en.period, en.shard FROM audit.entries en
              WHERE en.entry_hash IS NULL ORDER BY 1, 2
    LOOP
        INSERT INTO audit.chain_head (period, shard, last_hash, last_seq)
        VALUES (c.period, c.shard, audit.genesis(), 0)
        ON CONFLICT (period, shard) DO NOTHING;

        SELECT last_hash, last_seq INTO v_prev, v_seq
          FROM audit.chain_head
         WHERE period = c.period AND shard = c.shard
         FOR UPDATE;

        FOR e IN SELECT * FROM audit.entries en
                  WHERE en.period = c.period AND en.shard = c.shard AND en.entry_hash IS NULL
                  ORDER BY en.seq
                  LIMIT p_limit
        LOOP
            v_seq  := v_seq + 1;
            v_hash := digest(audit.canonical(e) || coalesce(v_prev, ''::bytea), 'sha256');
            UPDATE audit.entries
               SET prev_hash = v_prev, entry_hash = v_hash, chain_seq = v_seq
             WHERE occurred_at = e.occurred_at AND id = e.id;
            v_prev := v_hash;
            n := n + 1;
        END LOOP;

        UPDATE audit.chain_head
           SET last_hash = v_prev, last_seq = v_seq
         WHERE period = c.period AND shard = c.shard;
    END LOOP;

    RETURN n;
END $$;

COMMENT ON FUNCTION audit.seal_chain(int) IS
  'Links every committed, not-yet-sealed audit entry into its (period, shard) hash chain, in insertion order: '
  'prev_hash, entry_hash = sha256(canonical || prev), chain_seq. Run by the API every few seconds and by '
  'audit.verify_chain() before it walks. Single-threaded by an advisory lock. Returns the entries sealed.';

-- ── the verifier: seal what is committed, then walk every chain ───────────
DROP FUNCTION IF EXISTS audit.verify_chain(date);

CREATE FUNCTION audit.verify_chain(p_period date DEFAULT NULL)
RETURNS TABLE (period date, shard smallint, entries bigint, ok boolean,
               first_break uuid, broke_at timestamptz, pending bigint)
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
    PERFORM audit.seal_chain(2000000000);

    FOR c IN SELECT ch.period AS p, ch.shard AS s FROM audit.chain_head ch
             WHERE p_period IS NULL OR ch.period = p_period
             ORDER BY ch.period, ch.shard
    LOOP
        v_prev := audit.genesis(); v_bad := NULL; v_badat := NULL; v_n := 0;
        FOR e IN SELECT * FROM audit.entries en
                  WHERE en.period = c.p AND en.shard = c.s AND en.entry_hash IS NOT NULL
                  ORDER BY coalesce(en.chain_seq, en.seq)
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
        pending := (SELECT count(*) FROM audit.entries en
                     WHERE en.period = c.p AND en.shard = c.s AND en.entry_hash IS NULL);
        RETURN NEXT;
    END LOOP;
END $$;

COMMENT ON FUNCTION audit.verify_chain(date) IS
  'I-SEC-2: seals the committed tail, then recomputes every (period, shard) chain from genesis and reports '
  'the first entry whose link does not hold. pending = entries committed but not yet sealed (normally 0 after '
  'the call itself; a transaction still open at the time is counted on the next run).';

COMMIT;

-- ── the sealer's index: only the unsealed tail, so finding it costs nothing ──
-- Built outside a transaction so the one large existing partition is indexed
-- CONCURRENTLY (no writes blocked); a partition made later by ensure_partition
-- inherits the parent index automatically.
CREATE INDEX IF NOT EXISTS ix_entries_unsealed ON ONLY audit.entries (period, shard, seq) WHERE entry_hash IS NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202609 ON audit.entries_202609 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202609;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202610 ON audit.entries_202610 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202610;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202611 ON audit.entries_202611 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202611;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202612 ON audit.entries_202612 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202612;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202701 ON audit.entries_202701 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202701;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202702 ON audit.entries_202702 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202702;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202703 ON audit.entries_202703 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202703;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202704 ON audit.entries_202704 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202704;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202705 ON audit.entries_202705 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202705;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202706 ON audit.entries_202706 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202706;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202707 ON audit.entries_202707 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202707;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202708 ON audit.entries_202708 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202708;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202709 ON audit.entries_202709 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202709;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202710 ON audit.entries_202710 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202710;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202711 ON audit.entries_202711 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202711;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202712 ON audit.entries_202712 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202712;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202801 ON audit.entries_202801 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202801;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202802 ON audit.entries_202802 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202802;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202803 ON audit.entries_202803 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202803;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202804 ON audit.entries_202804 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202804;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202805 ON audit.entries_202805 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202805;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202806 ON audit.entries_202806 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202806;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202807 ON audit.entries_202807 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202807;
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_entries_unsealed_202808 ON audit.entries_202808 (period, shard, seq) WHERE entry_hash IS NULL;
ALTER INDEX audit.ix_entries_unsealed ATTACH PARTITION audit.ix_entries_unsealed_202808;

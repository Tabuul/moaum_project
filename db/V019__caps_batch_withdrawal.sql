-- ═══════════════════════════════════════════════════════════════════════════
-- V019 — a CAPS list loaded in error is withdrawn, not deleted
--
-- The first real season showed the case: a file in the office's own layout,
-- loaded before the raw CAPS download was to hand, or the wrong kind of
-- list under the right button. The batch is evidence of what was loaded and
-- by whom, so it stays. It is WITHDRAWN: dated, by a person, for a reason
-- that is on the record. Its rows stay beside it, marked withdrawn, and
-- count for nothing — the reconciliation does not see them, the batch cannot
-- be committed, and the registration numbers on it are free for the list
-- that should have been loaded.
--
-- A list whose candidates already hold admission numbers is not withdrawn:
-- each of those is a status change on the register, made one by one.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE admissions.caps_batch
    ADD COLUMN IF NOT EXISTS withdrawn_at     timestamptz NULL,
    ADD COLUMN IF NOT EXISTS withdrawn_by     uuid        NULL,
    ADD COLUMN IF NOT EXISTS withdrawn_reason text        NULL;

ALTER TABLE admissions.caps_batch
    DROP CONSTRAINT IF EXISTS ck_batch_withdrawn,
    ADD CONSTRAINT ck_batch_withdrawn CHECK (
        withdrawn_at IS NULL
        OR (withdrawn_by IS NOT NULL AND withdrawn_reason IS NOT NULL AND btrim(withdrawn_reason) <> ''));

COMMENT ON COLUMN admissions.caps_batch.withdrawn_at IS
  'A list loaded in error is withdrawn, never deleted: the upload happened, '
  'and the record says so, by whom, and why. Its rows stay, marked, and '
  'count for nothing.';

-- the rows of a withdrawn list are kept, marked, and out of every count
ALTER TABLE admissions.caps_row
    ADD COLUMN IF NOT EXISTS withdrawn boolean NOT NULL DEFAULT false;

-- The registration numbers on a withdrawn list belong to the list that
-- replaces it. Uniqueness therefore holds over the live rows only; the
-- withdrawn rows are evidence, not a cohort.
ALTER TABLE admissions.caps_row DROP CONSTRAINT IF EXISTS uq_caps_row_per_session;
DROP INDEX IF EXISTS admissions.uq_caps_row_key_per_session;
CREATE UNIQUE INDEX uq_caps_row_per_session
    ON admissions.caps_row (session, jamb_reg_no) WHERE NOT withdrawn;
CREATE UNIQUE INDEX uq_caps_row_key_per_session
    ON admissions.caps_row (session, jamb_key) WHERE NOT withdrawn;

-- the rows that count: what JAMB sent, on a list that stands
CREATE OR REPLACE VIEW admissions.caps_row_live AS
    SELECT r.* FROM admissions.caps_row r WHERE NOT r.withdrawn;

-- ── the reconciliation, over the lists that stand ─────────────────────────
-- The same five findings as V006, word for word, read over the live rows.
CREATE OR REPLACE FUNCTION admissions.reconcile(p_session text)
RETURNS TABLE (finding text, n bigint, owner text, what_it_means text)
LANGUAGE sql
STABLE
AS $$
    SELECT 'On the CAPS list, no candidate record'::text, count(*)::bigint,
           'Academic Office'::text,
           'JAMB admitted them and the University has no record. They arrive '
           'at registration with a CAPS printout and nobody can find them.'::text
      FROM admissions.caps_row_live r
     WHERE r.session = p_session
       AND NOT EXISTS (SELECT 1 FROM admissions.candidate c
                        WHERE c.session = r.session AND c.jamb_reg_no = r.jamb_reg_no)
    UNION ALL
    SELECT 'Admitted here, not on the CAPS list', count(*)::bigint,
           'Registrar',
           'An admission JAMB did not approve. Left alone it becomes a '
           'matriculation number issued to somebody who was never admitted, '
           'and that number is permanent.'
      FROM admissions.candidate c
     WHERE c.session = p_session
       AND c.offer_state IN ('ADMITTED','ACCEPTED')
       AND NOT EXISTS (SELECT 1 FROM admissions.caps_row_live r
                        WHERE r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no)
    UNION ALL
    SELECT 'Matched, programme differs from CAPS', count(*)::bigint,
           'Academic Office',
           'The candidate is admitted to the programme CAPS says, not the one '
           'we offered. A student taught for a year under the wrong programme '
           'graduates under a degree JAMB has no record of.'
      FROM admissions.candidate c
      JOIN admissions.caps_row_live r
        ON r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no
      JOIN ref.programme j ON j.code = r.jamb_code
     WHERE c.session = p_session AND c.programme <> j.name
    UNION ALL
    SELECT 'JAMB course code the University does not run', count(DISTINCT r.jamb_code)::bigint,
           'Academic Office',
           'The code is on the CAPS list and not in the University programme '
           'table, or is archived, or is not an undergraduate programme. '
           'It is refused rather than guessed: the candidate would otherwise '
           'be taught for a year under a programme nobody chose for them.'
      FROM admissions.caps_row_live r
     WHERE r.session = p_session
       AND NOT EXISTS (SELECT 1 FROM ref.programme p
                        WHERE p.code = r.jamb_code
                          AND NOT p.archived
                          AND p.category = 'UNDER GRADUATE')
    UNION ALL
    SELECT 'Direct Entry candidate entered at the wrong level', count(*)::bigint,
           'Academic Office',
           'A Direct Entry candidate at 100 Level repeats a year the University '
           'admitted them past, and it surfaces at the end of the session.'
      FROM admissions.candidate c
      JOIN admissions.caps_row_live r
        ON r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no
     WHERE c.session = p_session
       AND r.entry_mode <> 'UTME' AND c.entry_level = 100;
$$;

-- ── a withdrawn list is not committed ─────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.commit_batch(p_batch uuid)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    b admissions.caps_batch;
    outstanding text;
    total bigint;
BEGIN
    SELECT * INTO b FROM admissions.caps_batch WHERE id = p_batch;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503';
    END IF;
    IF b.committed_at IS NOT NULL THEN
        RETURN 'already committed';           -- idempotent, not an error
    END IF;
    IF b.withdrawn_at IS NOT NULL THEN
        RAISE EXCEPTION 'the list was withdrawn on %: %', b.withdrawn_at::date, b.withdrawn_reason
        USING ERRCODE = '23514',
              HINT = 'A withdrawn list is kept as evidence of what was loaded and is never '
                     'committed. Load the list that should have been loaded, and commit that.';
    END IF;

    SELECT string_agg(x.finding || ' (' || x.n || ')', '; '), coalesce(sum(x.n), 0)
      INTO outstanding, total
      FROM admissions.reconcile(b.session) x WHERE x.n > 0;

    IF total > 0 THEN
        RAISE EXCEPTION 'the admission list does not reconcile: %', outstanding
        USING ERRCODE = '23514',
              HINT = 'Every finding is a named person and carries an office. '
                     'A list committed with either count non-zero looks '
                     'complete at every desk it passes afterwards.';
    END IF;

    UPDATE admissions.caps_batch SET committed_at = now() WHERE id = p_batch;
    RETURN 'committed';
END $$;

-- ── the withdrawal ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.withdraw_batch(p_batch uuid, p_reason text)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    b admissions.caps_batch;
    v_actor uuid;
    v_on_register bigint;
BEGIN
    SELECT * INTO b FROM admissions.caps_batch WHERE id = p_batch;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503';
    END IF;
    IF b.withdrawn_at IS NOT NULL THEN
        RETURN 'already withdrawn';           -- idempotent, not an error
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'a list is withdrawn for a reason, and none was given'
        USING ERRCODE = '23514',
              HINT = 'Say why the list is withdrawn — the wrong file, the wrong kind of list, '
                     'the wrong session — so the record explains the space it leaves.';
    END IF;

    SELECT count(*) INTO v_on_register
      FROM people.student s
      JOIN admissions.candidate c ON c.id = s.candidate_id
      JOIN admissions.caps_row r ON r.id = c.admitted_from
     WHERE r.batch_id = p_batch;
    IF v_on_register > 0 THEN
        RAISE EXCEPTION '% student(s) admitted from this list already hold an admission number', v_on_register
        USING ERRCODE = '23514',
              HINT = 'A list whose candidates are on the register is not withdrawn: each of them is a '
                     'change of status on the register, made one at a time with its reason.';
    END IF;

    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'a list is withdrawn by a person, and none is acting'
        USING ERRCODE = '23514', HINT = 'The request must carry the person and office withdrawing the list.';
    END IF;

    -- offers that stood only on this list are withdrawn with it
    UPDATE admissions.candidate c
       SET offer_state = 'WITHDRAWN'
      FROM admissions.caps_row r
     WHERE r.id = c.admitted_from AND r.batch_id = p_batch
       AND c.offer_state NOT IN ('DECLINED','LAPSED','WITHDRAWN');

    UPDATE admissions.caps_row SET withdrawn = true WHERE batch_id = p_batch;
    UPDATE admissions.caps_batch
       SET withdrawn_at = now(), withdrawn_by = v_actor, withdrawn_reason = btrim(p_reason)
     WHERE id = p_batch;
    RETURN 'withdrawn';
END $$;

COMMENT ON FUNCTION admissions.withdraw_batch(uuid, text) IS
  'Withdraws a CAPS list loaded in error: the batch and its rows are kept and '
  'marked, the offers that stood only on it are withdrawn, and nothing of it '
  'counts again. Refused for a list whose candidates are on the register.';

COMMIT;

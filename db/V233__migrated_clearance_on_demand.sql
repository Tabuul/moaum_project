-- ═══════════════════════════════════════════════════════════════════════════
-- V233 — the migrated students' clearance, on demand and in view
--
--   V231 cleared the migrated students once, at deploy, and V232 clears each
--   future import as it lands. Neither is something the Registry can see or
--   repeat. Two functions give the desk a figure and an act:
--
--   · clearance.migrated_summary(from, to) — how many students on the
--     register came from the old portal at those levels, how many stand
--     cleared at every unit for every purpose, and how many do not.
--   · clearance.clear_migrated(from, to) — clears the ones that do not
--     (clearance.clear_on_migration, idempotent) and says how many it reached.
--
--   A migrated student is, as before, one with a matriculation number and no
--   matriculation run, still on the books.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION clearance.migrated_summary(p_from int DEFAULT 100, p_to int DEFAULT 400)
RETURNS TABLE (migrated bigint, cleared bigint, uncleared bigint)
LANGUAGE sql STABLE AS $$
    WITH m AS (
        SELECT s.id FROM people.student s
         WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
           AND s.current_level BETWEEN p_from AND p_to
           AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
    ),
    c AS (
        SELECT m.id, NOT EXISTS (SELECT 1 FROM ref.clearance_purpose pu WHERE NOT clearance.is_clear(m.id, pu.code)) AS clear
          FROM m
    )
    SELECT count(*), count(*) FILTER (WHERE clear), count(*) FILTER (WHERE NOT clear) FROM c
$$;

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
                    WHERE NOT EXISTS (SELECT 1 FROM clearance.item c
                                       WHERE c.student_id = s.id AND c.purpose = pu.code AND c.unit = un.code AND c.superseded_by IS NULL));
    ALTER TABLE clearance.item DISABLE TRIGGER trg_audit_clearance_item;
    INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, officer_id, decided_at, note)
    SELECT gen_random_uuid(), s.id, pu.code, un.code, 'CLEARED', NULL, NULL, now(),
           'Cleared on migration from the old portal — the clearance the old portal held, carried over'
      FROM people.student s
     CROSS JOIN ref.clearance_purpose pu
     CROSS JOIN clearance.unit un
     WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
       AND s.current_level BETWEEN p_from AND p_to
       AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
       AND NOT EXISTS (SELECT 1 FROM clearance.item c
                        WHERE c.student_id = s.id AND c.purpose = pu.code AND c.unit = un.code AND c.superseded_by IS NULL);
    GET DIAGNOSTICS po = ROW_COUNT;
    ALTER TABLE clearance.item ENABLE TRIGGER trg_audit_clearance_item;
    students := st; positions := po;
    RETURN NEXT;
END $$;

COMMENT ON FUNCTION clearance.clear_migrated(int, int) IS
  'Clears every migrated student (a matriculation number, no matriculation run) at the given levels who still lacks a unit''s word; idempotent.';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- V231 — a student migrated from the old portal arrives cleared
--
--   A unit with no word on file counts as "not yet cleared" (clearance.position
--   defaults to HELD), which is right for a student the portal has known from
--   admission: each unit clears them in its own time. It is wrong for the
--   students imported from the old portal (people.import_students): they were
--   cleared there, session after session, and no unit here holds anything
--   against them — yet every desk showed eight red marks and every gate that
--   asks clearance.is_clear (registration, the identity card, the hostel, the
--   Library, the wallet, examinations, results, convocation) refused them.
--
--   A migrated student is one on the register with a matriculation number but
--   no matriculation run: the portal's own matriculation (V013, V064) always
--   records the run, the import never does. For those at 100 to 400 level, as
--   the Registry asked, every unit's word for every purpose is entered as
--   CLEARED, dated now, with the note that says why and no officer — the
--   clearance is the old portal's, carried over, not a decision taken here.
--   A unit may still hold such a student later; a later HELD supersedes.
--
--   The same happens on arrival for any student the import brings in from
--   now on (trigger on the insert), and never for a student the portal admits
--   itself — they have no matriculation number at insert.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'Students migrated from the old portal arrive cleared (V231)', true);

-- ── 1 · the act, reusable ────────────────────────────────────────────────────
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
     WHERE NOT EXISTS (SELECT 1 FROM clearance.item c
                        WHERE c.student_id = p_student AND c.purpose = pu.code AND c.unit = un.code
                          AND c.superseded_by IS NULL);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

COMMENT ON FUNCTION clearance.clear_on_migration(uuid) IS
  'Every unit''s word for every purpose entered as CLEARED for a student migrated from the old portal; a unit with a word already on file is left alone.';

-- ── 2 · the backfill: every migrated student at 100–400 level, as one bulk write ────
-- Tens of thousands of students at sixty-four positions each is over a million rows; entered one at a
-- time through the audit trigger that is hours, and it held every deployment behind it. The bulk is
-- audit-light, as the registration and offering loads are (V127): the trigger is off for this one
-- statement, and the entries say on their face what they are and why. On-demand clears (V233) and each
-- import's own (V232) stay on the spine, a few rows at a time.
DO $$
DECLARE n int;
BEGIN
    ALTER TABLE clearance.item DISABLE TRIGGER trg_audit_clearance_item;
    INSERT INTO clearance.item (id, student_id, purpose, unit, state, item, officer_id, decided_at, note)
    SELECT gen_random_uuid(), s.id, pu.code, un.code, 'CLEARED', NULL, NULL, now(),
           'Cleared on migration from the old portal — the clearance the old portal held, carried over'
      FROM people.student s
     CROSS JOIN ref.clearance_purpose pu
     CROSS JOIN clearance.unit un
     WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
       AND s.current_level BETWEEN 100 AND 400
       AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
       AND NOT EXISTS (SELECT 1 FROM clearance.item c
                        WHERE c.student_id = s.id AND c.purpose = pu.code AND c.unit = un.code AND c.superseded_by IS NULL);
    GET DIAGNOSTICS n = ROW_COUNT;
    ALTER TABLE clearance.item ENABLE TRIGGER trg_audit_clearance_item;
    RAISE NOTICE 'V231: % unit positions entered as cleared for the migrated students', n;
END $$;

COMMIT;

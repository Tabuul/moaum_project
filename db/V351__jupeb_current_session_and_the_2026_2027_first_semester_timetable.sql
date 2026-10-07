-- ═══════════════════════════════════════════════════════════════════════════
-- V351 — The JUPEB programme's own current session (2026/2027), and its first-semester lecture timetable
--
--   · The JUPEB session followed the University's current academic session (policy.academic_session, still 2025/2026 while
--     2026/2027 is planned). The JUPEB programme runs to its own calendar: the JUPEB Office now names its current session
--     (jupeb.setting, the default row): new applications are filed under it (so its windows and its fees apply to them) and
--     every JUPEB screen opens on it; without one, the University's still applies. Set to 2026/2027, as the JUPEB Office asked —
--     the 2025/2026 JUPEB session is over. Students already filed under a session stay there. The University's own current
--     session is not touched.
--   · A timetable slot names the course as the Board's timetable prints it (GEO 001, MAT 002 …) and whether it is a practical.
--     Parallel lectures of different subjects are the rule (each student takes three); what is refused is a room holding two
--     lectures at once, or one class (when a slot names it) booked twice — V347 refused any two slots for every class at the
--     same hour, which no real timetable passes.
--   · The 2026/2027 first-semester lecture timetable, as the JUPEB Office gave it, is put on the record (once, and only where
--     that semester has no slot yet). The timetable writes MAT and VSA where the subjects are MTH (Mathematics) and VAR (Visual
--     Art), and CRS where it is CRS/ISS. On Wednesday 12:00–1:00 it puts ACC 002 and GOV 002 both in LR8: ACC 002 keeps LR8
--     (it continues from 11:00) and GOV 002's room is left to be confirmed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'jupeb', true),
       set_config('moaum.reason', 'V351: JUPEB current session 2026/2027 and the first-semester timetable', true);

-- ── 1 · the JUPEB programme's current session ────────────────────────────────────────────────────────────────────
ALTER TABLE jupeb.setting ADD COLUMN current_session text NULL;
ALTER TABLE jupeb.setting ADD CONSTRAINT ck_jupeb_setting_current CHECK (current_session IS NULL OR (session = '*' AND current_session ~ '^[0-9]{4}/[0-9]{4}$'));
COMMENT ON COLUMN jupeb.setting.current_session IS 'V351: the JUPEB programme''s current session, named by the JUPEB Office on the default row (*); empty, the University''s current academic session applies.';

CREATE OR REPLACE FUNCTION policy.application_session(p_type text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN admissions.pg_current_session()
                WHEN p_type LIKE 'JUPEB%' AND (SELECT current_session FROM jupeb.setting WHERE session = '*') IS NOT NULL
                    THEN (SELECT current_session FROM jupeb.setting WHERE session = '*')
                ELSE coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1),
                              (SELECT max(name) FROM policy.academic_session WHERE state <> 'PLANNED'),
                              (SELECT max(name) FROM policy.academic_session)) END
$fn$;
COMMENT ON FUNCTION policy.application_session(text) IS
  'The session a new application of this kind would be filed under today (V312): the current academic session for Post-UTME; the postgraduate school''s current session for postgraduate; for JUPEB the JUPEB Office''s current session when it names one (V351).';

UPDATE jupeb.setting SET current_session = '2026/2027' WHERE session = '*';

-- ── 2 · the timetable: the course code, practicals, and clashes of a room or a class ─────────────────────────────
ALTER TABLE jupeb.timetable_slot ADD COLUMN course_code text NULL;
ALTER TABLE jupeb.timetable_slot ADD COLUMN practical boolean NOT NULL DEFAULT false;
ALTER TABLE jupeb.timetable_slot ADD CONSTRAINT ck_jupeb_slot_course CHECK (course_code IS NULL OR course_code ~ '^[A-Z]{2,4}(/[A-Z]{2,4})? [0-9]{3}$');
COMMENT ON COLUMN jupeb.timetable_slot.course_code IS 'V351: the course as the Board''s timetable prints it (GEO 001); the subject is subject_id.';

CREATE OR REPLACE FUNCTION jupeb.slot_clash()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.course_code IS NOT NULL THEN NEW.course_code := upper(regexp_replace(btrim(NEW.course_code), '^([A-Z/]+) ?([0-9]{3})$', '\1 \2', 'i')); END IF;
    IF NEW.active AND EXISTS (
        SELECT 1 FROM jupeb.timetable_slot s
         WHERE s.id <> NEW.id AND s.active AND s.session = NEW.session AND s.semester = NEW.semester AND s.weekday = NEW.weekday
           AND s.starts_at < NEW.ends_at AND NEW.starts_at < s.ends_at
           AND ((NEW.venue IS NOT NULL AND s.venue IS NOT NULL
                 AND upper(regexp_replace(s.venue, '\s', '', 'g')) = upper(regexp_replace(NEW.venue, '\s', '', 'g')))
                OR (NEW.class_id IS NOT NULL AND s.class_id = NEW.class_id))) THEN
        RAISE EXCEPTION 'JUPEB_SLOT_CLASH: the room (or the class) already has a lecture at that time' USING ERRCODE = '23514';
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- ── 3 · the 2026/2027 first-semester lecture timetable ───────────────────────────────────────────────────────────
DO $$
DECLARE r record; v_subject uuid; n int := 0;
BEGIN
    IF EXISTS (SELECT 1 FROM jupeb.timetable_slot WHERE session = '2026/2027' AND semester = 1 AND active) THEN RETURN; END IF;
    FOR r IN SELECT * FROM (VALUES
        -- Monday
        (1, '08:00', '09:00', 'GEO', 'GEO 001', 'LR8', false, NULL), (1, '08:00', '09:00', 'VAR', 'VSA 002', 'LR9', false, NULL),
        (1, '09:00', '11:00', 'PHY', 'PHY 001', 'LR15', false, NULL), (1, '09:00', '11:00', 'GOV', 'GOV 001', 'LR7', false, NULL),
        (1, '11:00', '13:00', 'CHM', 'CHM 001', 'LR16', false, NULL), (1, '11:00', '13:00', 'BUS', 'BUS 001', 'LR10', false, NULL),
        (1, '14:00', '15:00', 'GEO', 'GEO 002', 'LR8', false, NULL), (1, '14:00', '15:00', 'VAR', 'VSA 002', 'LR9', false, NULL),
        (1, '15:00', '17:00', 'PHY', NULL, 'LAB', true, 'Physics practical'),
        (1, '15:00', '17:00', 'LIT', 'LIT 001', 'LR8', false, NULL), (1, '15:00', '17:00', 'ACC', 'ACC 001', 'LR7', false, NULL),
        -- Tuesday
        (2, '08:00', '09:00', 'VAR', 'VSA 001', 'LR9', false, NULL),
        (2, '09:00', '11:00', 'MTH', 'MAT 001', 'LR10', false, NULL), (2, '09:00', '10:00', 'ACC', 'ACC 002', 'LR11', false, NULL),
        (2, '10:00', '12:00', 'BIO', 'BIO 001', 'LR17', false, NULL), (2, '11:00', '12:00', 'LIT', 'LIT 001', 'LR8', false, NULL),
        (2, '12:00', '13:00', 'BUS', 'BUS 002', 'LR11', false, NULL), (2, '12:00', '13:00', 'PHY', 'PHY 002', 'LR15', false, NULL),
        (2, '14:00', '15:00', 'GEO', 'GEO 002', 'LR8', false, NULL), (2, '14:00', '15:00', 'CRS/ISS', 'CRS 001', 'LR10', false, NULL),
        (2, '15:00', '17:00', 'BIO', NULL, 'LAB', true, 'Biology practical'), (2, '15:00', '17:00', 'ECO', 'ECO 001', 'LR9', false, NULL),
        -- Wednesday
        (3, '08:00', '09:00', 'GEO', 'GEO 001', 'LR8', false, NULL), (3, '08:00', '09:00', 'VAR', 'VSA 001', 'LR9', false, NULL),
        (3, '09:00', '11:00', 'PHY', 'PHY 002', 'LR15', false, NULL), (3, '09:00', '10:00', 'ECO', 'ECO 002', 'LR8', false, NULL),
        (3, '10:00', '12:00', 'CRS/ISS', 'CRS 001', 'LR10', false, NULL),
        (3, '11:00', '13:00', 'ACC', 'ACC 002', 'LR8', false, NULL), (3, '11:00', '12:00', 'CHM', 'CHM 001', 'LR16', false, NULL),
        (3, '12:00', '13:00', 'MTH', 'MAT 002', 'LR10', false, NULL),
        (3, '12:00', '13:00', 'GOV', 'GOV 002', NULL, false, 'Venue to confirm: the timetable gives LR8, where ACC 002 is at this hour'),
        (3, '14:00', '15:00', 'ACC', 'ACC 001', 'LR11', false, NULL), (3, '14:00', '15:00', 'LIT', 'LIT 002', 'LR7', false, NULL),
        (3, '15:00', '17:00', 'CHM', NULL, 'LAB', true, 'Chemistry practical'),
        -- Thursday
        (4, '08:00', '10:00', 'ECO', 'ECO 002', 'LR8', false, NULL), (4, '08:00', '09:00', 'CRS/ISS', 'CRS 002', 'LR9', false, NULL),
        (4, '09:00', '10:00', 'MTH', 'MAT 002', 'LR9', false, NULL),
        (4, '10:00', '12:00', 'GOV', 'GOV 002', 'LR9', false, NULL), (4, '10:00', '11:00', 'MTH', 'MAT 002', 'LR10', false, NULL),
        (4, '11:00', '13:00', 'BIO', 'BIO 002', 'LR17', false, NULL), (4, '12:00', '13:00', 'BUS', 'BUS 001', 'LR10', false, NULL),
        (4, '14:00', '15:00', 'GEO', 'GEO 002', 'LR8', false, NULL), (4, '14:00', '15:00', 'VAR', 'VSA 002', 'LR9', false, NULL),
        (4, '15:00', '17:00', 'CHM', 'CHM 002', 'LR16', false, NULL), (4, '15:00', '16:00', 'VAR', 'VSA 001', 'LR10', false, NULL),
        (4, '16:00', '17:00', 'ECO', 'ECO 001', 'LR8', false, NULL),
        -- Friday
        (5, '08:00', '09:00', 'GEO', 'GEO 001', 'LR8', false, NULL),
        (5, '09:00', '11:00', 'BUS', 'BUS 002', 'LR7', false, NULL), (5, '09:00', '10:00', 'PHY', 'PHY 001', 'LR15', false, NULL),
        (5, '10:00', '11:00', 'MTH', 'MAT 001', 'LR10', false, NULL),
        (5, '11:00', '13:00', 'LIT', 'LIT 002', 'LR8', false, NULL), (5, '11:00', '12:00', 'CHM', 'CHM 002', 'LR16', false, NULL),
        (5, '12:00', '13:00', 'BIO', 'BIO 001', 'LR17', false, NULL),
        (5, '14:00', '15:00', 'BIO', 'BIO 002', 'LR17', false, NULL), (5, '14:00', '16:00', 'CRS/ISS', 'CRS 002', 'LR8', false, NULL),
        (5, '15:00', '16:00', 'GOV', 'GOV 001', 'LR10', false, NULL)
    ) AS t(weekday, starts, ends, subject, course, venue, practical, note) LOOP
        v_subject := (SELECT id FROM jupeb.subject WHERE code = r.subject);
        IF v_subject IS NULL THEN
            RAISE NOTICE 'V351: no JUPEB subject %, slot % % % skipped', r.subject, r.course, r.weekday, r.starts;
            CONTINUE;
        END IF;
        INSERT INTO jupeb.timetable_slot (session, semester, class_id, subject_id, course_code, practical, weekday, starts_at, ends_at, venue, note)
        VALUES ('2026/2027', 1, NULL, v_subject, r.course, r.practical, r.weekday, r.starts::time, r.ends::time, r.venue, r.note);
        n := n + 1;
    END LOOP;
    RAISE NOTICE 'V351: % lecture slots put on the 2026/2027 first-semester timetable', n;
END $$;

COMMIT;

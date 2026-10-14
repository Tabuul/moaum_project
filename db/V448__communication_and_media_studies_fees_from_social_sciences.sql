-- ═══════════════════════════════════════
-- V448 — Communication and Media Studies charged the Social Sciences fees
--
-- The faculty of Communication and Media Studies (CM: Mass Communication, Advertising, Public Relations, Broadcasting,
-- Development Communication, Journalism and Media Studies, Strategic Communication) had no line on the fee schedule for
-- 2025/2026, while the old portal billed its students as Social Sciences (a 200-level non-indigene paid the Social Sciences
-- ₦112,735 for the first semester). On the new portal the matcher (finance.charges_of_as) reads a student's own faculty, found
-- nothing, and showed CM students no second-semester fee to pay; about 4,100 active students, 2,600 of whom paid the first
-- semester on the old portal.
--
-- At the University's word (14 Oct 2026) CM is charged what Social Sciences is charged. finance.copy_faculty_fees copies the
-- live faculty-wide lines of one faculty to another for a session — every kind (fee, late payment, late registration),
-- semester, level, entry mode, indigene, spillover and fee group as they stand — and only into a faculty that has no live line
-- in that session, so a line the Bursary has already stated is never doubled or overwritten. The amounts are each database's
-- own Social Sciences lines, never figures written here. It runs for the current session and every planned one; a session the
-- Bursary states later is stated for CM as for any faculty, on the Fee Schedule screen or by the upload (or by this function).
-- A line copied here is an ordinary line: the Bursary edits or ends it on the Fee Schedule screen like any other.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V448: Communication and Media Studies charged the Social Sciences fees', true);

CREATE FUNCTION finance.copy_faculty_fees(p_from text, p_to text, p_session text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to
       OR NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_from) OR NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_to) THEN
        RETURN 0;
    END IF;
    -- a faculty the Bursary has already stated for the session is left as it is
    IF EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_session AND f.faculty_code = p_to AND f.ended_at IS NULL) THEN
        RETURN 0;
    END IF;
    INSERT INTO finance.fee_schedule (id, session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, kind)
    SELECT gen_random_uuid(), f.session, f.item, f.amount, f.level, f.entry_mode, p_to, NULL, f.ord, f.fee_group, f.semester, f.indigene, f.spillover, f.kind
      FROM finance.fee_schedule f
     WHERE f.session = p_session AND f.faculty_code = p_from AND f.programme_code IS NULL AND f.ended_at IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;
COMMENT ON FUNCTION finance.copy_faculty_fees(text, text, text) IS
  'V448: the live faculty-wide fee lines of one faculty copied to another for a session (every kind, semester, level, entry mode, indigene, spillover and fee group), only when the receiving faculty has no live line in that session; returns the lines copied.';

-- Communication and Media Studies charged as Social Sciences: the current session and every planned one
DO $$
DECLARE s record; n int; total int := 0;
BEGIN
    FOR s IN SELECT a.name FROM policy.academic_session a
              WHERE a.name = policy.university_current_session() OR a.state = 'PLANNED'
              ORDER BY a.name LOOP
        n := finance.copy_faculty_fees('SS', 'CM', s.name);
        IF n > 0 THEN
            RAISE NOTICE 'V448: % Social Sciences fee line(s) of % copied to Communication and Media Studies', n, s.name;
        END IF;
        total := total + n;
    END LOOP;
    RAISE NOTICE 'V448: % fee line(s) copied in all', total;
END $$;

COMMIT;

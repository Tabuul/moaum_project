-- ═══════════════════════════════════════
-- V450 — Technology and Industrial Studies charged the Education fees
--
-- Like Communication and Media Studies before V448, the faculty of Technology and Industrial Studies (TI: Technology
-- Education, Business Education, Home Economics; some 630 active students) had no line on the fee schedule for 2025/2026, so
-- its students were shown no second-semester fee. What they paid on the old portal for the first semester is what the Arts,
-- Education, Sciences and Social Sciences lines say (those four schedules are identical, line for line, on the 13 Oct copy),
-- and its degrees are Education degrees: at the University's word (14 Oct 2026) TI is charged the Education lines, copied by
-- finance.copy_faculty_fees (V448) — each database's own Education amounts, only where TI has no line in the session, for the
-- current session and every planned one.
--
-- Basic and Applied Medical Sciences (BAMS) is not copied from anywhere: what its students paid differs by programme (MBBS,
-- Nursing, Medical Laboratory Science, Radiography, Biochemistry, Anatomy, Physiology) and matches no other faculty's lines, so
-- its schedule is the Bursary's to state.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V450: Technology and Industrial Studies charged the Education fees', true);

DO $$
DECLARE s record; n int; total int := 0;
BEGIN
    FOR s IN SELECT a.name FROM policy.academic_session a
              WHERE a.name = policy.university_current_session() OR a.state = 'PLANNED'
              ORDER BY a.name LOOP
        n := finance.copy_faculty_fees('ED', 'TI', s.name);
        IF n > 0 THEN
            RAISE NOTICE 'V450: % Education fee line(s) of % copied to Technology and Industrial Studies', n, s.name;
        END IF;
        total := total + n;
    END LOOP;
    RAISE NOTICE 'V450: % fee line(s) copied in all', total;
END $$;

COMMIT;

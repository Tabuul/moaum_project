-- V634: Industrial Chemistry is a five-year programme — the University's word of 22 October 2026 ("Industrial Chemistry is a 5 years
-- course not 4 years"). B.Sc Industrial Chemistry (C22229) kept the four-year length seeded at V331, as the six programmes V598
-- corrected had; its students at 500 stood above the programme's last level and a 400-level student in the fifth session was
-- read as in spillover. It ends at 500 from now, set in one statement so the cohort engine recomputes every position once
-- (trg_position_programme); the levels a student may be progressed or corrected to, the rollover, the spillover years and the
-- graduation candidates follow (100 → … → 500, then SP1, SP2). The Faculty of Science's 500-level fee lines already stand, so no
-- fee gap opens; the Bursary's gap report (V584) would show one if it did.
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V634: Industrial Chemistry is a five-year programme (the University, 22 October 2026)', true);
UPDATE ref.programme
   SET final_level = 500,
       final_level_note = 'V634: five years, as the University runs the programme (22 October 2026); was 400 from the rule seeded at V331'
 WHERE code = 'C22229'
   AND final_level IS DISTINCT FROM 500;
COMMIT;

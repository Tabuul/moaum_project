-- ════════════════════════════════════════════════════════════════════════
--  V012  ·  What JAMB actually calls four of the programmes.
--
--  The alias list (V006) was transcribed from the 2025/2026 guidelines,
--  which give JAMB's name for 56 programmes and nothing for the rest; for
--  those the seed fell back to the University's own name. The first real
--  2026/2027 CAPS download named four of them in JAMB's words, and the
--  intake screen refused 748 candidates rather than guess. These are the
--  words JAMB used, taken from that file.
--
--  Every alias JAMB uses that is still missing is mapped on the screen by
--  the Academic Office, with the act recorded; this migration only fixes
--  what one file has already shown.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- the spine refuses an unattributed write, including this one
DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason',
        'JAMB course names as they appear in the 2026/2027 CAPS download, Academic Office', true);
END $seed$;

UPDATE ref.jamb_alias SET jamb_name = 'Broadcasting'                     WHERE code = 'C60514';
UPDATE ref.jamb_alias SET jamb_name = 'Strategic Communications'         WHERE code = 'C98602';
UPDATE ref.jamb_alias SET jamb_name = 'Development Communication Studies' WHERE code = 'C62073';
UPDATE ref.jamb_alias SET jamb_name = 'Landscape Architecture'           WHERE code = 'C72222';

COMMIT;

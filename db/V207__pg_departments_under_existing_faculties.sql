-- ═══════════════════════════════════════════════════════════════════════════
-- V207 — the postgraduate departments belong under existing faculties
--
--   V206 created two new faculties (Clinical Sciences, Postgraduate Centres) for
--   a handful of postgraduate departments. That pushed the faculty count to 14
--   and drew those faculties into undergraduate admissions (a cut-off is stated
--   per faculty). The correction: move those departments under the closest
--   existing faculty, repoint their programmes, and drop the two empty faculties.
--   V206 stays as it was applied; this is the follow-up correction.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'Move PG departments under existing faculties and drop the mistaken PG faculties (V207)', true);

-- the departments V206 added, moved under the closest existing faculty
UPDATE ref.department SET faculty_code = 'BAMS' WHERE code IN ('EPI', 'OBG') AND faculty_code = 'CLS';
UPDATE ref.department SET faculty_code = 'SS'   WHERE code IN ('PDS', 'GND') AND faculty_code = 'CTR';
UPDATE ref.department SET faculty_code = 'SC'   WHERE code = 'CSP'          AND faculty_code = 'CTR';

-- repoint the programmes to their department's (now corrected) faculty
UPDATE ref.programme p SET faculty_code = d.faculty_code
  FROM ref.department d
 WHERE d.code = p.dept_code AND p.faculty_code IN ('CLS', 'CTR');

-- the two faculties are now unreferenced; remove them so the faculty set is the undergraduate twelve again
DELETE FROM ref.faculty WHERE code IN ('CLS', 'CTR')
   AND NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.faculty_code = ref.faculty.code)
   AND NOT EXISTS (SELECT 1 FROM ref.programme g WHERE g.faculty_code = ref.faculty.code);

COMMIT;

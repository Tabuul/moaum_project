-- ═══════════════════════════════════════
-- V470 — Score reads stay fast
--
-- Every reading of a class's results goes through assessment.latest_scores (results, broadsheets, transcripts, the GPA, the
-- GST/EPS course engine and so the registration menu). For every score it called policy.grading_scope, assessment.grace_total
-- and policy.grade_of, and grace_total found the lowest passing band by scanning the grade bands with the version in force
-- worked out inside the scan — one or two calls of policy.in_force for every band of every score. Those calls were most of
-- the cost: on the live-shaped copy, in a fresh session, the 15,223 scores of the 21 GST/EPS sheets took 1.4 s to read, one
-- student's GST/EPS owing (finance.gst_eps_rows) 0.13–1.27 s, and the registration menu 0.27–0.39 s.
--
-- latest_scores now resolves the class's grading once a sheet, by joins: the version in force (the School's for a PG class
-- while one is in force, else the University's) and its passing floor; each score's grade is then the band of that version
-- its total falls in. The grace rule is assessment.grace_apply(total, floor), a plain expression; assessment.pass_floor(date,
-- scope) is the lowest passing mark of the grading in force, the version found once a call (policy.grading_version), and
-- both forms of grace_total are restated on them. The grades are unchanged — every score on the copy's 1,042 sheets (143,043
-- readings) and every total 0..100 under each scope come out as before — and the same reads take 35–50 ms, 22–39 ms and
-- 32–76 ms.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'exams', true),
       set_config('moaum.reason', 'V470: score reads stay fast in a long-lived session', true);

CREATE OR REPLACE FUNCTION policy.grading_version(p_at date, p_scope text)
RETURNS uuid LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(policy.in_force('grading', coalesce(p_scope, 'UNIVERSITY'), p_at), policy.in_force('grading', 'UNIVERSITY', p_at))
$fn$;

COMMENT ON FUNCTION policy.grading_version(date, text) IS
    'V470: the grading version in force on the day for the scope — the scope''s own (the School''s for POSTGRADUATE), else the University''s — as policy.grade_of and assessment.grace_total resolve it.';

CREATE OR REPLACE FUNCTION assessment.pass_floor(p_at date, p_scope text)
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT min(b.low) FROM policy.grade_band b
     WHERE b.version_id = (SELECT policy.grading_version(p_at, p_scope))
       AND b.points > 0
$fn$;

COMMENT ON FUNCTION assessment.pass_floor(date, text) IS
    'V470: the lowest passing mark of the grading in force on the day for the scope (the University''s where the scope has none) — the version found once a call.';

CREATE OR REPLACE FUNCTION assessment.grace_apply(p_raw integer, p_floor integer)
RETURNS integer LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN p_raw IS NULL THEN NULL WHEN p_raw = p_floor - 1 THEN p_raw + 1 ELSE p_raw END
$fn$;

COMMENT ON FUNCTION assessment.grace_apply(integer, integer) IS
    'V470: the grace mark rule — a total one short of the lowest passing mark is raised to it; any other total is returned as it is.';

-- V238's form: the University's grading
CREATE OR REPLACE FUNCTION assessment.grace_total(p_raw int, p_at date DEFAULT current_date)
RETURNS int LANGUAGE sql STABLE AS $fn$
    SELECT assessment.grace_apply(p_raw, assessment.pass_floor(p_at, 'UNIVERSITY'))
$fn$;

COMMENT ON FUNCTION assessment.grace_total(int, date) IS
  'A total one short of the lowest passing band in force is raised to it (39 → 40 under the 2015 scheme); any other total is returned as it is. V470: read through assessment.pass_floor and assessment.grace_apply.';

-- V389's form: the grading of the class's scope (the School's for a PG class), the University's where the scope has none
CREATE OR REPLACE FUNCTION assessment.grace_total(p_raw integer, p_at date, p_scope text)
RETURNS integer LANGUAGE sql STABLE AS $fn$
    SELECT assessment.grace_apply(p_raw, assessment.pass_floor(p_at, p_scope))
$fn$;

-- V389's latest_scores, its grading read once a sheet and by joins, not by calling functions: the version in force (the
-- School's for a PG class while one is in force, else the University's — policy.grading_scope and policy.grading_version;
-- one version a kind, scope and day, ex_version_no_overlap) and its passing floor, then each score's grade from the bands
-- of that version (the bands never overlap — ex_band_no_overlap — so a mark has one band or none), as grace_total and
-- grade_of give them. With no version in force the scores still come, ungraded, as before.
CREATE OR REPLACE FUNCTION assessment.latest_scores(p_sheet uuid)
 RETURNS TABLE(student_id uuid, ca integer, exam integer, total integer, grade text, points numeric, outcome text, version integer, amended boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.student_id, s.ca, s.exam, t.total,
           g.grade, g.points, s.outcome, s.version, s.version > 1
      FROM (SELECT DISTINCT ON (student_id) * FROM assessment.score
             WHERE sheet_id = p_sheet ORDER BY student_id, version DESC) s
      -- V389: the class's grading — the School's for a PG class, the University's for every other; V470: read once a sheet
      CROSS JOIN (SELECT v.id AS version_id,
                         (SELECT min(b.low) FROM policy.grade_band b WHERE b.version_id = v.id AND b.points > 0) AS floor
                    FROM assessment.score_sheet sh
                    LEFT JOIN catalogue.offering o ON o.id = sh.offering_id
                    LEFT JOIN LATERAL (SELECT pv.id FROM policy.version pv
                                        WHERE pv.kind = 'grading' AND pv.validity @> current_date
                                          AND pv.scope IN (CASE WHEN o.stream = 'PG' THEN 'POSTGRADUATE' END, 'UNIVERSITY')
                                        ORDER BY (pv.scope = 'UNIVERSITY') LIMIT 1) v ON true
                   WHERE sh.id = p_sheet) gv
      CROSS JOIN LATERAL (SELECT CASE WHEN s.outcome <> 'GRADED' THEN NULL
                                      WHEN s.ca IS NOT NULL AND s.exam IS NOT NULL AND NOT s.imported THEN assessment.grace_apply(s.ca + s.exam, gv.floor)
                                      ELSE coalesce(s.ca + s.exam, s.total) END AS total) t
      LEFT JOIN policy.grade_band g ON g.version_id = gv.version_id AND t.total BETWEEN g.low AND g.high
$function$;

COMMIT;

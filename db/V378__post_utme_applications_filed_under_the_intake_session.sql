-- V378: Post-UTME registration is filed under the intake session — the session candidates are admitted INTO — not the
--       session the University's returning students are in.
--
-- Since V312 policy.application_session('POST_UTME_REGISTRATION') gave the current academic session, so while 2025/2026
-- runs the public Post-UTME page read "Admissions 2025/2026" — an exercise already done, its students already in session —
-- when the candidates applying now are for 2026/2027. The admissions screens already default to the intake session (the
-- planned session after the current one); the public page, the login page, the University's website and the Director of
-- ICT's application desk now read the same session.
--
--   policy.university_current_session()  the current academic session (else the latest that is not planned, else the latest):
--                                        what application_session gave before, and still what JUPEB falls back to when its
--                                        office names no session of its own (V351)
--   policy.intake_session()              the first planned session after the University's current one, else the current one
--                                        (a planned session older than the current one, or a later one beyond the next, is
--                                        not the intake)
--
-- Nothing already filed moves: an applicant account keeps the session it was registered under, and a window the Director of
-- ICT set for a session stays that session's. Asked for a session by name (?session=), every reader still gets that session.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V378: Post-UTME registration filed under the intake session', true);

CREATE OR REPLACE FUNCTION policy.university_current_session()
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1),
                    (SELECT max(name) FROM policy.academic_session WHERE state <> 'PLANNED'),
                    (SELECT max(name) FROM policy.academic_session))
$fn$;
COMMENT ON FUNCTION policy.university_current_session() IS
  'The University''s current academic session (V378): the CURRENT one, else the latest that is not planned, else the latest.';

CREATE OR REPLACE FUNCTION policy.intake_session()
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT s.name FROM policy.academic_session s
                      WHERE s.state = 'PLANNED'
                        AND s.starts_on > (SELECT c.starts_on FROM policy.academic_session c WHERE c.name = policy.university_current_session())
                      ORDER BY s.starts_on LIMIT 1),
                    policy.university_current_session())
$fn$;
COMMENT ON FUNCTION policy.intake_session() IS
  'The intake session (V378): the session candidates are admitted into — the first planned session after the University''s current one, else the current one. The admissions screens default to the same session.';

CREATE OR REPLACE FUNCTION policy.application_session(p_type text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN admissions.pg_current_session()
                WHEN p_type LIKE 'JUPEB%'
                    THEN coalesce((SELECT current_session FROM jupeb.setting WHERE session = '*'), policy.university_current_session())
                ELSE policy.intake_session() END
$fn$;
COMMENT ON FUNCTION policy.application_session(text) IS
  'The session a new application of this kind would be filed under today: the intake session for Post-UTME (V378; the current academic session before it); the postgraduate school''s current session for postgraduate; for JUPEB the JUPEB Office''s current session when it names one, else the University''s current session (V351).';

COMMIT;

-- V661: the 2019/2020 session merged into 2020/2021. The University's word of 26 October 2026: "students from 2019, are on spill 2 not
-- spill three because in between a session was merged … all the students that have /19/ and are doing a 4 years course are on spill
-- two while the ones on 5 years are on spill 1".
--
-- The calendar began at 2021/2022, so the cohort engine (people.academic_position_rows_of, V331/V595) counted the 2019 entrants from
-- 2019/2020 straight through: a four-year programme ended in 2022/2023 and 2025/2026 read as a third spillover year (past the limit of
-- two), a five-year programme as the second. The portal already carries a merged session (V331): a session CANCELLED and merged into
-- the one that carried its students — its entrants are carried by the merged-into cohort (policy.effective_session), and it is not
-- counted for anyone in study across it (policy.session_after, policy.sessions_elapsed). The University chose that reading for every
-- student in study then, the 2017/2018 and 2018/2019 entrants included, and to leave the Direct Entry 2019 entrants (three years of
-- study) where the count puts them.
--
-- So: 2019/2020 and 2020/2021 put on the calendar where missing (past, closed), and 2019/2020 merged into 2020/2021 through
-- policy.merge_session, with the reason. trg_position_session recomputes every student's position on the merger. Only on a calendar that
-- has run (a session current, closed or archived): a database that has never run one — a fresh build, the tests — is left as it is, so
-- its fallback current session (policy.university_current_session) stays its own.
--
-- On the live-shaped copy (rolled back): of the /19/ students in study, the four-year 2,375 past the limit → 2,349 SP2 (52 SP1, 9 in
-- the final year), the five-year → 610 SP1 (13 SP2), the six-year 83 in the final year; 55 Direct Entry stay past the limit; earlier
-- entrants: 2017/2018 72 and 2018/2019 309 from past the limit to SP2, 79 from SP2 to SP1. Undone, should it be needed, by
-- Student Cohorts → Policy → Academic sessions → Undo merger (policy.unmerge_session).
BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V661: the 2019/2020 session merged into 2020/2021 — the two were run as one', true);

DO $$
BEGIN
    -- a calendar that has never run a session is left as it is
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE state IN ('CURRENT', 'CLOSED', 'ARCHIVED')) THEN
        RAISE NOTICE 'V661: no session has run on this calendar; nothing merged';
        RETURN;
    END IF;
    -- the two sessions on the calendar where they are missing: past and closed
    INSERT INTO policy.academic_session (id, name, starts_on, ends_on, semesters, state)
    SELECT gen_random_uuid(), x.name, x.s, x.e, 2, 'CLOSED'
      FROM (VALUES ('2019/2020', DATE '2019-09-01', DATE '2020-08-31'),
                   ('2020/2021', DATE '2020-09-01', DATE '2021-08-31')) AS x(name, s, e)
     WHERE NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x.name);
    -- merged once: left as it is where it already is, or where 2020/2021 is itself cancelled
    IF EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2019/2020' AND merged_into IS NULL AND state <> 'CURRENT')
       AND EXISTS (SELECT 1 FROM policy.academic_session WHERE name = '2020/2021' AND state <> 'CANCELLED') THEN
        PERFORM policy.merge_session('2019/2020', '2020/2021',
            'The 2019/2020 and 2020/2021 sessions were run as one: the 2019 entrants are carried by the 2020/2021 cohort and the merged session '
            || 'is counted once for every student in study then (the University''s word of 26 October 2026)', NULL);
    END IF;
END $$;

COMMIT;

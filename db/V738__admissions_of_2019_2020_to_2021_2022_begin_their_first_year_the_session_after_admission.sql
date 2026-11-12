-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V738 · Admissions of 2019/2020, 2020/2021 and 2021/2022 begin their first year in the session after admission
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University, 12 November 2026, over a student's Outstanding school fees: "remember a session was merged … this outstanding
--  should not affect student for that merged session". The student, admitted 2021/2022, was billed 100 Level fees for 2021/2022
--  (₦178,294.74) and one level high after it (2023/2024 at 300 Level).
--
--  What the record shows (the late-October copy of live, counts only): no student admitted 2019/2020, 2020/2021 or 2021/2022 —
--  10,716 of them — holds a registration or an enrolment in the session they were admitted in. 2021/2022 admits registered 100 Level
--  in 2022/2023 and 300 Level in 2024/2025, exactly as 2022/2023 admits did; 2020/2021 admits registered 200 Level in 2022/2023 and
--  400 Level in 2024/2025; 2019/2020 admits 300 Level in 2022/2023. Each of those three admissions began its first year the session
--  after it was admitted in — the calendar caught up at 2022/2023, which took two admissions at once. V661 merged 2019/2020 into
--  2020/2021, which is right for 2019/2020 admits and for everyone in study across it, but counted 2020/2021 and 2021/2022 admits
--  from their admission session.
--
--  The rule (the University's choice, 12 November 2026): for admissions of 2019/2020, 2020/2021 and 2021/2022 the first year of study
--  is the session after the admission session — nothing assessed before it, levels counted from it. Recorded as policy data,
--  policy.cohort_start (admission session → first session), with its reason, on a calendar that has run those sessions (as V661: a
--  fresh or CI calendar of PLANNED sessions is left alone). Read through people.first_session / people.counted_from_entry by every
--  reader that counts a level from admission for a session with no registration or enrolment: the outstanding-fees (historical)
--  engine — its first assessed session and its levels — people.level_in, people.receipt_level, the payments view and the three set
--  readers of the cancelled years (the 7-argument reporting.level_in_session given the admission session shifted inline, so it stays
--  inlined). A registration or enrolment's own level still stands; a postgraduate's and a CCE student's calendar is their own.
--
--  Left as they are (they follow registrations, not the count, and are another decision): the cohort engine's effective cohort
--  (people.academic_position, spillover), people.roll_over_session's promotion cap, people.align_level_reached, college.min_years_met,
--  people.cohort_cap (a cohort override is the office's own). people.counted_sessions is unchanged: some callers pass a registration's
--  session or an override's cohort, never an admission.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V738: admissions of 2019/2020 to 2021/2022 begin their first year the session after admission', true);

-- ── 1 · the rule, as data ──────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE policy.cohort_start (
    admission_session text PRIMARY KEY REFERENCES policy.academic_session(name) ON UPDATE CASCADE,
    first_session     text NOT NULL REFERENCES policy.academic_session(name) ON UPDATE CASCADE,
    reason            text NOT NULL CHECK (length(btrim(reason)) >= 10),
    set_by            uuid,
    set_office        text,
    set_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_cohort_start_after CHECK (policy.session_year(first_session) > policy.session_year(admission_session))
);
COMMENT ON TABLE policy.cohort_start IS
  'V738: an admission whose first year of study began in a later session (the University: admissions of 2019/2020, 2020/2021 and 2021/2022 began the session after, the calendar catching up at 2022/2023) — nothing assessed before the first session, levels counted from it, wherever a level is counted from admission (people.first_session, people.counted_from_entry).';
SELECT audit.attach('policy.cohort_start');

-- the session a student's first year of study is in: the policy's first session for their admission (an undergraduate of the
-- University's calendar), else the admission session as the cohort engine reads it (a merged session followed to its end)
CREATE FUNCTION people.first_session(p_entry_session text, p_entry_mode text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_entry_mode IN ('CCE', 'POSTGRADUATE') THEN policy.effective_session(policy.session_normal(p_entry_session))
                ELSE coalesce((SELECT c.first_session FROM policy.cohort_start c WHERE c.admission_session = policy.session_normal(p_entry_session)),
                              policy.effective_session(policy.session_normal(p_entry_session))) END
$$;
COMMENT ON FUNCTION people.first_session(text, text) IS
  'V738: the session a student''s first year of study is in — policy.cohort_start''s first session for the admission (not a CCE or postgraduate student''s own calendar), else the admission session as policy.effective_session reads it.';

-- the sessions studied from the first year to a session (negative before it), a merged session once
CREATE FUNCTION people.counted_from_entry(p_entry_session text, p_entry_mode text, p_session text) RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT policy.sessions_elapsed(people.first_session(p_entry_session, p_entry_mode), policy.effective_session(policy.session_normal(p_session)))
$$;
COMMENT ON FUNCTION people.counted_from_entry(text, text, text) IS
  'V738: people.counted_sessions counted from the first year of study (people.first_session) rather than the admission session; negative for a session before it.';

-- the rule as two arrays, read once by a set reader (admission sessions, and their first sessions)
CREATE FUNCTION policy.cohort_starts(OUT admissions text[], OUT firsts text[]) RETURNS record LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(c.admission_session ORDER BY c.admission_session), '{}'::text[]),
           coalesce(array_agg(c.first_session ORDER BY c.admission_session), '{}'::text[])
      FROM policy.cohort_start c
$$;

-- a change to the rule makes the outstanding-fees account of every student admitted in that session stale
CREATE FUNCTION policy.cohort_start_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s record; v_old text; v_new text;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old := OLD.admission_session; END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new := NEW.admission_session; END IF;
    FOR s IN SELECT st.id FROM people.student st
              WHERE st.entry_session IN (v_old, v_new)
                AND finance.historical_population(st.status, st.id, st.entry_session)
    LOOP
        PERFORM finance.historical_mark(s.id);
    END LOOP;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_cohort_start_changed AFTER INSERT OR UPDATE OR DELETE ON policy.cohort_start
    FOR EACH ROW EXECUTE FUNCTION policy.cohort_start_changed();

-- ── 2 · the readers that count a level from admission ─────────────────────────────────────────────────────────────────────────
DO $$
DECLARE d text;
BEGIN
    -- the level in a session with no registration or enrolment, and the receipt's level: counted from the first year
    FOREACH d IN ARRAY ARRAY['people.level_in(uuid,text,integer)', 'people.receipt_level(uuid,text)'] LOOP
        d := pg_get_functiondef(d::regprocedure);
        IF position('CROSS JOIN LATERAL (SELECT people.counted_sessions(st.entry_session, p_session) AS n) n' IN d) = 0 THEN
            RAISE EXCEPTION 'V738: a level reader is not as V725 left it';
        END IF;
        d := replace(d, 'CROSS JOIN LATERAL (SELECT people.counted_sessions(st.entry_session, p_session) AS n) n',
                        'CROSS JOIN LATERAL (SELECT people.counted_from_entry(st.entry_session, st.entry_mode, p_session) AS n) n   -- V738');
        EXECUTE d;
    END LOOP;

    -- the outstanding-fees engine: nothing assessed before the first year; a period's level counted from it
    d := pg_get_functiondef('finance.historical_rows_read(uuid[])'::regprocedure);
    IF position('    st AS MATERIALIZED (' IN d) = 0
       OR position('greatest(s.entry_session, b.start) AS first_session,' IN d) = 0
       OR position('          CROSS JOIN bounds b' IN d) = 0
       OR position('    coh AS MATERIALIZED (SELECT d.entry_session, d.session, people.counted_sessions(d.entry_session, d.session) AS n' IN d) = 0
       OR position('                           FROM (SELECT DISTINCT p0.entry_session, p0.session FROM per0 p0 WHERE NOT p0.pg) d),' IN d) = 0
       OR position('          LEFT JOIN coh ch ON ch.entry_session = p0.entry_session AND ch.session = p0.session' IN d) = 0 THEN
        RAISE EXCEPTION 'V738: finance.historical_rows_read is not as V733 left it';
    END IF;
    d := replace(d, '    st AS MATERIALIZED (',
                    '    -- V738: the session a student''s first year is in, read once an admission session and entry mode
    fst AS MATERIALIZED (SELECT x.entry_session, x.entry_mode, people.first_session(x.entry_session, x.entry_mode) AS first_session
                           FROM (SELECT DISTINCT s0.entry_session, s0.entry_mode FROM people.student s0 WHERE s0.id = ANY (p_students)) x),
    st AS MATERIALIZED (');
    d := replace(d, 'greatest(s.entry_session, b.start) AS first_session,',
                    'greatest(coalesce(f.first_session, s.entry_session), b.start) AS first_session,   -- V738: nothing before the first year');
    d := replace(d, '          CROSS JOIN bounds b',
                    '          CROSS JOIN bounds b
          LEFT JOIN fst f ON f.entry_session = s.entry_session AND f.entry_mode IS NOT DISTINCT FROM s.entry_mode');
    d := replace(d, '    coh AS MATERIALIZED (SELECT d.entry_session, d.session, people.counted_sessions(d.entry_session, d.session) AS n',
                    '    coh AS MATERIALIZED (SELECT d.entry_session, d.entry_mode, d.session, people.counted_from_entry(d.entry_session, d.entry_mode, d.session) AS n   -- V738');
    d := replace(d, '                           FROM (SELECT DISTINCT p0.entry_session, p0.session FROM per0 p0 WHERE NOT p0.pg) d),',
                    '                           FROM (SELECT DISTINCT p0.entry_session, p0.entry_mode, p0.session FROM per0 p0 WHERE NOT p0.pg) d),');
    d := replace(d, '          LEFT JOIN coh ch ON ch.entry_session = p0.entry_session AND ch.session = p0.session',
                    '          LEFT JOIN coh ch ON ch.entry_session = p0.entry_session AND ch.entry_mode IS NOT DISTINCT FROM p0.entry_mode AND ch.session = p0.session');
    EXECUTE d;

    -- the old-fees reconciliation and the overpaid list: the admission session shifted to the first year, inline
    FOREACH d IN ARRAY ARRAY['finance.old_fees_reconciliation(text)', 'finance.overpaid(text)'] LOOP
        d := pg_get_functiondef(d::regprocedure);
        IF position('reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years)' IN d) = 0
           OR position('CROSS JOIN policy.cancelled_years() cy(years, into_years)' IN d) = 0 THEN
            RAISE EXCEPTION 'V738: a set reader of the cancelled years is not as V725 left it';
        END IF;
        d := replace(d, 'reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years)',
                        'reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, s.entry_session)], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years)');
        d := replace(d, 'CROSS JOIN policy.cancelled_years() cy(years, into_years)',
                        'CROSS JOIN policy.cancelled_years() cy(years, into_years)
      CROSS JOIN policy.cohort_starts() cs(admissions, firsts)   -- V738');
        EXECUTE d;
    END LOOP;

    -- the old-fees import: the rule read once a call
    d := pg_get_functiondef('finance.import_legacy_payments(jsonb)'::regprocedure);
    IF position('v_cy_years integer[]; v_cy_into integer[];' IN d) = 0
       OR position('    SELECT c.years, c.into_years INTO v_cy_years, v_cy_into FROM policy.cancelled_years() c;' IN d) = 0
       OR position('reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into)' IN d) = 0 THEN
        RAISE EXCEPTION 'V738: finance.import_legacy_payments is not as V725 left it';
    END IF;
    d := replace(d, 'v_cy_years integer[]; v_cy_into integer[];', 'v_cy_years integer[]; v_cy_into integer[]; v_cs_adm text[]; v_cs_first text[];');
    d := replace(d, '    SELECT c.years, c.into_years INTO v_cy_years, v_cy_into FROM policy.cancelled_years() c;',
                    '    SELECT c.years, c.into_years INTO v_cy_years, v_cy_into FROM policy.cancelled_years() c;
    SELECT c.admissions, c.firsts INTO v_cs_adm, v_cs_first FROM policy.cohort_starts() c;   -- V738');
    d := replace(d, 'reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into)',
                    'reporting.level_in_session(st.entry_level, CASE WHEN st.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN st.entry_session ELSE coalesce(v_cs_first[array_position(v_cs_adm, st.entry_session)], st.entry_session) END, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into)');
    EXECUTE d;

    -- the payments view (its level column)
    d := pg_get_viewdef('reporting.payments'::regclass, true);
    IF position('reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, r.session, cy.years, cy.into_years) AS level' IN d) = 0
       OR position('CROSS JOIN policy.cancelled_years() cy(years, into_years)' IN d) = 0 THEN
        RAISE EXCEPTION 'V738: reporting.payments is not as V725 left it';
    END IF;
    d := replace(d, 'reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, r.session, cy.years, cy.into_years) AS level',
                    'reporting.level_in_session(st.entry_level, CASE WHEN st.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN st.entry_session ELSE COALESCE(cs.firsts[array_position(cs.admissions, st.entry_session)], st.entry_session) END, st.current_level, st.entry_mode, r.session, cy.years, cy.into_years) AS level');
    d := replace(d, 'CROSS JOIN policy.cancelled_years() cy(years, into_years)',
                    'CROSS JOIN policy.cancelled_years() cy(years, into_years)
     CROSS JOIN policy.cohort_starts() cs(admissions, firsts)');
    EXECUTE 'CREATE OR REPLACE VIEW reporting.payments AS ' || d;
END $$;

-- the 5-argument form (a scalar caller): the admission session shifted to the first year
CREATE OR REPLACE FUNCTION reporting.level_in_session(p_entry_level integer, p_entry_session text, p_current_level integer, p_entry_mode text, p_session text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT reporting.level_in_session(p_entry_level,
                                      CASE WHEN p_entry_mode IN ('CCE', 'POSTGRADUATE') THEN p_entry_session
                                           ELSE coalesce(cs.firsts[array_position(cs.admissions, p_entry_session)], p_entry_session) END,   -- V738
                                      p_current_level, p_entry_mode, p_session, c.years, c.into_years)
      FROM policy.cancelled_years() c CROSS JOIN policy.cohort_starts() cs
$function$;

-- ── 3 · the University's rule, on a calendar that has run those sessions ───────────────────────────────────────────────────────
INSERT INTO policy.cohort_start (admission_session, first_session, reason, set_by, set_office)
SELECT x.adm, x.first, 'The University, 12 November 2026: admissions of 2019/2020, 2020/2021 and 2021/2022 began their first year of study in the session after admission (the merged session; the calendar caught up at 2022/2023) — nothing is assessed before the first year, and levels are counted from it.',
       '00000000-0000-0000-0000-000000000000'::uuid, 'registrar'
  FROM (VALUES ('2019/2020', '2020/2021'), ('2020/2021', '2021/2022'), ('2021/2022', '2022/2023')) x(adm, first)
 WHERE EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x.adm)
   AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = x.first AND a.state IN ('CLOSED', 'CURRENT', 'ARCHIVED'))
ON CONFLICT (admission_session) DO NOTHING;

SELECT 'V738: ' || count(*) || ' admission session(s) begin the session after' FROM policy.cohort_start;
COMMIT;

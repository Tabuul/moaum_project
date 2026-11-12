-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V740 · The review of V738 (admissions of 2019/2020 to 2021/2022 begin the session after) applied
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  An adversarial review of V738 (two readers, each finding put to a refuter) confirmed nine defects:
--    · Money on the admission session dropped out of the outstanding-fees account. A school-fee payment, an approved assessment or a
--      waiver recorded on the session a student was admitted in (now before their first year) counted on no period, as no credit, and
--      was not flagged. The engine now keeps such a session as a period with nothing assessed, so its payment stands as a credit (an
--      approved assessment, an officer's own act, still stands); the migration counts them, and closes the open references drawn
--      for those sessions.
--    · A session before the first year read a made-up level: people.level_in gave today's level, receipts and the payments view 100
--      for a Direct Entry student. Such a session reads the entry level everywhere; a school-fee payment is not moved into it.
--    · The set readers, the 5-argument level and the stale-marking trigger matched the admission session as written, while
--      people.first_session reads it as the calendar writes it ('2021/22' is 2021/2022): all now read it alike.
--    · The cohort engine still counted a 2021/2022 admit from admission: before a final-level registration they read as Spillover Year
--      1 in 2025/2026, and the current session was billed spillover lines. The engine's effective cohort is now the first year
--      (cohort source COHORT_START); the affected admits' positions are recomputed.
--    · The programme timeline (deferment page and letter) counted completion from admission: now from the first year.
--    · V738 newly assessed the admission session of a student whose admission session is not written as the calendar writes it; their
--      outstanding-fees accounts are marked stale so the desks read what the student reads.
--    · The outstanding-fees card's "sessions before X are not yet assessed" is decided from the first year (the API).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V740: the review of V738 applied', true);

DO $$
DECLARE d text;
BEGIN
    -- ── the level of a session at or after admission and before the first year: the entry level ──
    d := pg_get_functiondef('people.level_in(uuid,text,integer)'::regprocedure);
    IF position('WHEN n.n >= 0 THEN least(600, st.entry_level + 100 * n.n)' IN d) = 0 THEN
        RAISE EXCEPTION 'V740: people.level_in is not as V738 left it';
    END IF;
    d := replace(d, 'WHEN n.n >= 0 THEN least(600, st.entry_level + 100 * n.n)',
                    'WHEN n.n >= 0 THEN least(600, st.entry_level + 100 * n.n)
                             -- V740: admitted, the first year not begun (policy.cohort_start): the entry level
                             WHEN people.counted_sessions(st.entry_session, p_session) >= 0 THEN st.entry_level');
    EXECUTE d;
    d := pg_get_functiondef('people.receipt_level(uuid,text)'::regprocedure);
    IF position('THEN least(600, greatest(100, st.entry_level + 100 * n.n))' IN d) = 0 THEN
        RAISE EXCEPTION 'V740: people.receipt_level is not as V725 left it';
    END IF;
    d := replace(d, 'THEN least(600, greatest(100, st.entry_level + 100 * n.n))',
                    'THEN least(600, greatest(coalesce(st.entry_level, 100), st.entry_level + 100 * n.n))   -- V740: never below the entry level');
    EXECUTE d;

    -- ── the set readers: the admission session read as the calendar writes it; never below the entry level ──
    FOREACH d IN ARRAY ARRAY['finance.old_fees_reconciliation(text)', 'finance.overpaid(text)'] LOOP
        d := pg_get_functiondef(d::regprocedure);
        IF position('reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, s.entry_session)], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years)' IN d) = 0 THEN
            RAISE EXCEPTION 'V740: a set reader is not as V738 left it';
        END IF;
        d := replace(d, 'reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, s.entry_session)], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years)',
                        'greatest(coalesce(s.entry_level, 100), reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, policy.session_normal(s.entry_session))], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years))');
        EXECUTE d;
    END LOOP;
    d := pg_get_functiondef('finance.import_legacy_payments(jsonb)'::regprocedure);
    IF position('v_level := reporting.level_in_session(st.entry_level, CASE WHEN st.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN st.entry_session ELSE coalesce(v_cs_first[array_position(v_cs_adm, st.entry_session)], st.entry_session) END, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into);' IN d) = 0 THEN
        RAISE EXCEPTION 'V740: finance.import_legacy_payments is not as V738 left it';
    END IF;
    d := replace(d, 'v_level := reporting.level_in_session(st.entry_level, CASE WHEN st.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN st.entry_session ELSE coalesce(v_cs_first[array_position(v_cs_adm, st.entry_session)], st.entry_session) END, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into);',
                    'v_level := greatest(coalesce(st.entry_level, 100), reporting.level_in_session(st.entry_level, CASE WHEN st.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN st.entry_session ELSE coalesce(v_cs_first[array_position(v_cs_adm, policy.session_normal(st.entry_session))], st.entry_session) END, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into));   -- V740');
    EXECUTE d;
    d := pg_get_viewdef('reporting.payments'::regclass, true);
    IF position('    reporting.level_in_session(st.entry_level,' IN d) = 0
       OR position('ELSE COALESCE(cs.firsts[array_position(cs.admissions, st.entry_session)], st.entry_session)' IN d) = 0
       OR position(' r.session, cy.years, cy.into_years) AS level,' IN d) = 0 THEN
        RAISE EXCEPTION 'V740: reporting.payments is not as V738 left it';
    END IF;
    d := replace(d, '    reporting.level_in_session(st.entry_level,', '    GREATEST(COALESCE(st.entry_level, 100), reporting.level_in_session(st.entry_level,');
    d := replace(d, 'ELSE COALESCE(cs.firsts[array_position(cs.admissions, st.entry_session)], st.entry_session)',
                    'ELSE COALESCE(cs.firsts[array_position(cs.admissions, policy.session_normal(st.entry_session))], st.entry_session)');
    d := replace(d, ' r.session, cy.years, cy.into_years) AS level,', ' r.session, cy.years, cy.into_years)) AS level,');
    EXECUTE 'CREATE OR REPLACE VIEW reporting.payments AS ' || d;

    -- ── the outstanding-fees engine: a session before the first year that holds money, an approved assessment or a waiver is kept, with
    --    nothing assessed on it, so the money stands as a credit ──
    d := pg_get_functiondef('finance.historical_rows_read(uuid[])'::regprocedure);
    IF position('    fst AS MATERIALIZED (SELECT x.entry_session, x.entry_mode, people.first_session(x.entry_session, x.entry_mode) AS first_session' IN d) = 0
       OR position('               greatest(coalesce(f.first_session, s.entry_session), b.start) AS first_session,' IN d) = 0
       OR position('        SELECT st.*, fl.final_level, a.name AS session, sm.n AS semester' IN d) = 0
       OR position('          JOIN cal a ON a.name >= st.first_session AND a.name <= st.last_session AND a.state NOT IN (''CANCELLED'', ''DRAFT'')' IN d) = 0
       OR position('                              CASE WHEN p0.pg THEN p0.current_level' IN d) = 0
       OR position('         WHERE f.spillover = pr.is_spill' IN d) = 0
       OR position('               coalesce(ap.amount, CASE WHEN sd.session IS NOT NULL THEN coalesce(sr.amount, 0) END) AS assessed,' IN d) = 0
       OR position('               CASE WHEN ap.id IS NOT NULL THEN ''ASSESSMENT'' WHEN sd.session IS NOT NULL THEN ''STRUCTURE'' ELSE ''NONE'' END AS source,' IN d) = 0
       OR position('                    WHEN sd.session IS NOT NULL THEN pr.session || '' fee structure''' IN d) = 0 THEN
        RAISE EXCEPTION 'V740: finance.historical_rows_read is not as V738 left it';
    END IF;
    d := replace(d, '    fst AS MATERIALIZED (SELECT x.entry_session, x.entry_mode, people.first_session(x.entry_session, x.entry_mode) AS first_session',
                    '    fst AS MATERIALIZED (SELECT x.entry_session, x.entry_mode, people.first_session(x.entry_session, x.entry_mode) AS first_session,
                                policy.effective_session(policy.session_normal(x.entry_session)) AS admitted_in   -- V740');
    d := replace(d, '               greatest(coalesce(f.first_session, s.entry_session), b.start) AS first_session,',
                    '               greatest(coalesce(f.first_session, s.entry_session), b.start) AS first_session,
               greatest(coalesce(f.admitted_in, s.entry_session), b.start) AS admitted_from,   -- V740');
    d := replace(d, '        SELECT st.*, fl.final_level, a.name AS session, sm.n AS semester',
                    '        SELECT st.*, fl.final_level, a.name AS session, sm.n AS semester, a.name < st.first_session AS before_first');
    d := replace(d, '          JOIN cal a ON a.name >= st.first_session AND a.name <= st.last_session AND a.state NOT IN (''CANCELLED'', ''DRAFT'')',
                    '          JOIN cal a ON a.name <= st.last_session AND a.state NOT IN (''CANCELLED'', ''DRAFT'')
                    AND (a.name >= st.first_session
                         -- V740: a session admitted in, before the first year, that holds a school-fee payment, an approved assessment
                         -- or a waiver: kept with nothing assessed, so the money stands as a credit
                         OR (a.name >= st.admitted_from AND a.name < st.first_session
                             AND (EXISTS (SELECT 1 FROM finance.payment_reference r WHERE r.student_id = st.id AND r.session = a.name AND r.confirmed_at IS NOT NULL
                                             AND r.archived_at IS NULL AND r.purpose LIKE ''School fees%'')
                                  OR EXISTS (SELECT 1 FROM finance.historical_assessment h WHERE h.student_id = st.id AND h.session = a.name AND h.state = ''APPROVED'')
                                  OR EXISTS (SELECT 1 FROM finance.historical_waiver w WHERE w.student_id = st.id AND w.session = a.name AND w.state = ''APPROVED''))))');
    d := replace(d, '                              CASE WHEN p0.pg THEN p0.current_level',
                    '                              CASE WHEN p0.pg THEN p0.current_level
                                   WHEN p0.before_first THEN p0.entry_level   -- V740');
    d := replace(d, '         WHERE f.spillover = pr.is_spill',
                    '         WHERE f.spillover = pr.is_spill AND NOT pr.before_first   -- V740: nothing is due before the first year');
    d := replace(d, '               coalesce(ap.amount, CASE WHEN sd.session IS NOT NULL THEN coalesce(sr.amount, 0) END) AS assessed,',
                    '               coalesce(ap.amount, CASE WHEN pr.before_first THEN 0 WHEN sd.session IS NOT NULL THEN coalesce(sr.amount, 0) END) AS assessed,');
    d := replace(d, '               CASE WHEN ap.id IS NOT NULL THEN ''ASSESSMENT'' WHEN sd.session IS NOT NULL THEN ''STRUCTURE'' ELSE ''NONE'' END AS source,',
                    '               CASE WHEN ap.id IS NOT NULL THEN ''ASSESSMENT'' WHEN pr.before_first OR sd.session IS NOT NULL THEN ''STRUCTURE'' ELSE ''NONE'' END AS source,');
    d := replace(d, '                    WHEN sd.session IS NOT NULL THEN pr.session || '' fee structure''',
                    '                    WHEN pr.before_first THEN pr.session || '' — before the first year of study, nothing due''
                    WHEN sd.session IS NOT NULL THEN pr.session || '' fee structure''');
    EXECUTE d;

    -- ── a school-fee payment is not moved into a session before the first year ──
    d := pg_get_functiondef('finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)'::regprocedure);
    IF position('            IF v_code = ''SCHOOL_FEES'' AND NOT (v_dst->>''stated'')::boolean THEN' IN d) = 0 THEN
        RAISE EXCEPTION 'V740: finance.payment_reallocation_check is not as V727 left it';
    END IF;
    d := replace(d, '            IF v_code = ''SCHOOL_FEES'' AND NOT (v_dst->>''stated'')::boolean THEN',
                    '            IF v_code = ''SCHOOL_FEES'' AND v_session < people.first_session(s.entry_session, s.entry_mode)
               AND v_session >= policy.effective_session(policy.session_normal(s.entry_session)) THEN   -- V740
                refusals := refusals || (''REALLOC_BEFORE_FIRST_YEAR: '' || v_session || '' is before the student''''s first year of study ('' || people.first_session(s.entry_session, s.entry_mode) || ''); nothing is due for it'');
            END IF;
            IF v_code = ''SCHOOL_FEES'' AND NOT (v_dst->>''stated'')::boolean THEN');
    EXECUTE d;

    -- ── the programme timeline counts completion from the first year ──
    d := pg_get_functiondef('people.programme_timeline(uuid)'::regprocedure);
    IF position('policy.effective_session(policy.session_normal(s.entry_session))' IN d) = 0 THEN
        RAISE EXCEPTION 'V740: people.programme_timeline is not as V725 left it';
    END IF;
    d := replace(d, 'policy.effective_session(policy.session_normal(s.entry_session))', 'people.first_session(s.entry_session, s.entry_mode)');
    EXECUTE d;

    -- ── the cohort engine: the effective cohort is the first year ──
    d := pg_get_functiondef('people.academic_position_rows_of(uuid[])'::regprocedure);
    IF position('               coalesce(st.override_cohort, policy.effective_session(st.entry_session)) AS effective_cohort,' IN d) = 0
       OR position('               CASE WHEN st.override_cohort IS NOT NULL THEN ''OVERRIDE'' WHEN st.merged_into IS NOT NULL THEN ''MERGED'' ELSE ''ENTRY'' END AS cohort_source,' IN d) = 0 THEN
        RAISE EXCEPTION 'V740: people.academic_position_rows_of is not as V661 left it';
    END IF;
    d := replace(d, '               coalesce(st.override_cohort, policy.effective_session(st.entry_session)) AS effective_cohort,',
                    '               coalesce(st.override_cohort, people.first_session(st.entry_session, st.entry_mode)) AS effective_cohort,   -- V740');
    d := replace(d, '               CASE WHEN st.override_cohort IS NOT NULL THEN ''OVERRIDE'' WHEN st.merged_into IS NOT NULL THEN ''MERGED'' ELSE ''ENTRY'' END AS cohort_source,',
                    '               CASE WHEN st.override_cohort IS NOT NULL THEN ''OVERRIDE''
                    WHEN st.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'') AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(st.entry_session)) THEN ''COHORT_START''
                    WHEN st.merged_into IS NOT NULL THEN ''MERGED'' ELSE ''ENTRY'' END AS cohort_source,');
    EXECUTE d;
END $$;

-- the 5-argument form: the admission session read as the calendar writes it; never below the entry level
CREATE OR REPLACE FUNCTION reporting.level_in_session(p_entry_level integer, p_entry_session text, p_current_level integer, p_entry_mode text, p_session text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT greatest(coalesce(p_entry_level, 100),
                    reporting.level_in_session(p_entry_level,
                                               CASE WHEN p_entry_mode IN ('CCE', 'POSTGRADUATE') THEN p_entry_session
                                                    ELSE coalesce(cs.firsts[array_position(cs.admissions, policy.session_normal(p_entry_session))], p_entry_session) END,   -- V738, V740
                                               p_current_level, p_entry_mode, p_session, c.years, c.into_years))
      FROM policy.cancelled_years() c CROSS JOIN policy.cohort_starts() cs
$function$;

-- the rule's change marks the accounts of every student admitted in that session, however the session is written
CREATE OR REPLACE FUNCTION policy.cohort_start_changed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s record; v_old text; v_new text;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old := OLD.admission_session; END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new := NEW.admission_session; END IF;
    FOR s IN SELECT st.id FROM people.student st
              WHERE policy.session_normal(st.entry_session) IN (v_old, v_new)   -- V740
                AND finance.historical_population(st.status, st.id, st.entry_session)
    LOOP
        PERFORM finance.historical_mark(s.id);
    END LOOP;
    RETURN NULL;
END $$;

-- ── what V738 left: counted for the Bursary, references closed, accounts and positions read again ───────────────────────────────
DO $$
DECLARE n_pay int; n_amt numeric; n_apr int; n_wv int; n_ref int; n_stale int; n_pos int; v_ids uuid[];
BEGIN
    -- the students the rule reaches
    SELECT array_agg(st.id) INTO v_ids FROM people.student st
     WHERE st.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
       AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(st.entry_session));
    -- money and decisions on a session before the first year (now kept as a period with nothing assessed)
    SELECT count(*), coalesce(sum(r.amount), 0) INTO n_pay, n_amt
      FROM finance.payment_reference r JOIN people.student st ON st.id = r.student_id
     WHERE st.id = ANY (coalesce(v_ids, '{}')) AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
       AND r.session < people.first_session(st.entry_session, st.entry_mode);
    SELECT count(*) INTO n_apr FROM finance.historical_assessment h JOIN people.student st ON st.id = h.student_id
     WHERE st.id = ANY (coalesce(v_ids, '{}')) AND h.state = 'APPROVED' AND h.session < people.first_session(st.entry_session, st.entry_mode);
    SELECT count(*) INTO n_wv FROM finance.historical_waiver w JOIN people.student st ON st.id = w.student_id
     WHERE st.id = ANY (coalesce(v_ids, '{}')) AND w.state = 'APPROVED' AND w.session < people.first_session(st.entry_session, st.entry_mode);
    -- an open school-fee reference drawn for a session before the first year pays for nothing: closed
    UPDATE finance.payment_reference r SET expires_at = now()
      FROM people.student st
     WHERE st.id = r.student_id AND st.id = ANY (coalesce(v_ids, '{}')) AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
       AND r.purpose LIKE 'School fees%' AND r.session < people.first_session(st.entry_session, st.entry_mode);
    GET DIAGNOSTICS n_ref = ROW_COUNT;
    -- the accounts read again: the students the rule reaches, and those whose admission session is not written as the calendar writes it
    SELECT count(*) INTO n_stale FROM (
        SELECT finance.historical_mark(st.id) FROM people.student st
         WHERE finance.historical_population(st.status, st.id, st.entry_session)
           AND (st.id = ANY (coalesce(v_ids, '{}')) OR policy.session_normal(st.entry_session) IS DISTINCT FROM st.entry_session)) x;
    -- the positions of the students the rule reaches, counted from the first year
    IF coalesce(cardinality(v_ids), 0) > 0 THEN
        PERFORM people.refresh_academic_positions(v_ids);
    END IF;
    SELECT count(*) INTO n_pos FROM people.academic_position ap WHERE ap.student_id = ANY (coalesce(v_ids, '{}')) AND ap.cohort_source = 'COHORT_START';
    RAISE NOTICE 'V740: % school-fee payments (₦%), % approved assessments and % waivers on a session before the first year, kept as credits for the Bursary; % open references closed; % accounts marked to be read again; % positions counted from the first year',
        n_pay, n_amt, n_apr, n_wv, n_ref, n_stale, n_pos;
END $$;

COMMIT;

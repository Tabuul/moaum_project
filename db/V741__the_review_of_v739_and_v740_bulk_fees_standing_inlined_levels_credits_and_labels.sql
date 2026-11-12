-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V741 · The review of V739 and V740 applied
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  A review of the fixes (three readers, each finding put to a refuter) confirmed 13; the database's are answered here.
--    · The bulk fee readers still counted a Summer registration as a school-fee semester (finance.fee_profiles feeds the School Fees
--      Report, the Spillover desk, Student Accounts, the College and HOD views): it now leaves the Summer out, as reg_semesters does.
--    · Restoring standing_of for semester 3 made the Summer broadsheet pronounce probation or advice to withdraw on the Summer alone.
--      V735's rule is back (no standing on a Summer alone); student_standing still reads the last regular semester.
--    · V740's entry-level floor and name normalisation stopped the payments view and the set readers from inlining the 7-argument level
--      reader (about twenty times slower), and floored a postgraduate's own level at the entry level. The floor now sits inside the
--      count (a counted level never below the entry level); the admission session is matched by its year, which costs nothing.
--    · A Summer credit stayed OPEN after its payment was moved or archived: such a payment is neither moved nor archived while an open
--      credit names it, and a credit whose payment no longer stands as a Summer payment is not shown as the student's.
--    · Drawing a reference after taking back every chosen course raised, and rolled the take-back back: it now commits and answers
--      that nothing is owed. A course passed since it was chosen — an authorised one too — is taken back, and never revived by a late
--      payment. A late payment no longer revives the programme fee alone, with no course: the money stands as credit.
--    · Assessments made at a level the first-year count superseded are counted for the Bursary; an assessment on a session before the
--      first year is neither made nor approved.
--    · The cohort engine names a merged admission (2019/2020) MERGED again, and the lifecycle and graduation readers know COHORT_START.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V741: the review of V739 and V740 applied', true);

-- the rule's admissions by their year: matched against the first four characters of an admission session as written (as
-- policy.session_normal reads any name starting with a year), at no cost to an inlined reader
CREATE OR REPLACE FUNCTION policy.cohort_starts(OUT admissions text[], OUT firsts text[]) RETURNS record LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(left(c.admission_session, 4) ORDER BY c.admission_session), '{}'::text[]),
           coalesce(array_agg(c.first_session ORDER BY c.admission_session), '{}'::text[])
      FROM policy.cohort_start c
$$;
COMMENT ON FUNCTION policy.cohort_starts() IS
  'V738, V741: the rule for set readers, read once a query — the admission years (the first four characters of the admission session) and their first sessions; a reader matches left(entry_session, 4).';

CREATE OR REPLACE FUNCTION reporting.level_in_session(p_entry_level integer, p_entry_session text, p_current_level integer, p_entry_mode text, p_session text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT reporting.level_in_session(p_entry_level,
                                      CASE WHEN p_entry_mode IN ('CCE', 'POSTGRADUATE') THEN p_entry_session
                                           ELSE coalesce(cs.firsts[array_position(cs.admissions, left(p_entry_session, 4))], p_entry_session) END,   -- V738, V741
                                      p_current_level, p_entry_mode, p_session, c.years, c.into_years)
      FROM policy.cancelled_years() c CROSS JOIN policy.cohort_starts() cs
$function$;

DO $$
DECLARE d text;
BEGIN
    -- ── the bulk fee readers: a Summer registration is no school-fee semester ──
    d := pg_get_functiondef('finance.fee_profiles(text)'::regprocedure);
    IF position('                 WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN (''DROPPED'', ''WITHDRAWN''))' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: finance.fee_profiles is not as V697 left it';
    END IF;
    d := replace(d, '                 WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN (''DROPPED'', ''WITHDRAWN''))',
                    '                 WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN (''DROPPED'', ''WITHDRAWN''))
                   AND NOT (cr.semester = 3 AND EXISTS (SELECT 1 FROM registration.summer_period sp WHERE sp.session = p_session))   -- V741: the Summer');
    EXECUTE d;

    -- ── no standing pronounced on a Summer alone (the Summer broadsheet); student_standing reads the last regular semester ──
    d := pg_get_functiondef('assessment.standing_of(integer,integer,numeric,numeric,boolean)'::regprocedure);
    IF position('        WHEN p_cgpa IS NULL OR p_cgpa >= t.below THEN NULL' IN d) = 0 OR position('WHEN p_semester = 3' IN d) > 0 THEN
        RAISE EXCEPTION 'V741: assessment.standing_of is not as V739 left it';
    END IF;
    d := replace(d, '        WHEN p_cgpa IS NULL OR p_cgpa >= t.below THEN NULL',
                    '        WHEN p_cgpa IS NULL OR p_cgpa >= t.below THEN NULL
        -- V735, V741: the Summer Semester (semester 3): no standing is pronounced on it alone — no rule of the University''s says it
        WHEN p_semester = 3 THEN NULL');
    EXECUTE d;

    -- ── the 7-argument level: a counted level never below the entry level (the floor V740 put round every caller, now inside the count) ──
    d := pg_get_functiondef('reporting.level_in_session(integer,text,integer,text,text,integer[],integer[])'::regprocedure);
    IF position('ELSE least(600, greatest(100, coalesce(p_entry_level, 100) + 100 * (' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: reporting.level_in_session (7) is not as V725 left it';
    END IF;
    d := replace(d, 'ELSE least(600, greatest(100, coalesce(p_entry_level, 100) + 100 * (', 'ELSE least(600, greatest(coalesce(p_entry_level, 100), coalesce(p_entry_level, 100) + 100 * (');
    EXECUTE d;

    FOREACH d IN ARRAY ARRAY['finance.old_fees_reconciliation(text)', 'finance.overpaid(text)'] LOOP
        d := pg_get_functiondef(d::regprocedure);
        IF position('greatest(coalesce(s.entry_level, 100), reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, policy.session_normal(s.entry_session))], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years))' IN d) = 0 THEN
            RAISE EXCEPTION 'V741: a set reader is not as V740 left it';
        END IF;
        d := replace(d, 'greatest(coalesce(s.entry_level, 100), reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, policy.session_normal(s.entry_session))], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years))',
                        'reporting.level_in_session(s.entry_level, CASE WHEN s.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN s.entry_session ELSE coalesce(cs.firsts[array_position(cs.admissions, left(s.entry_session, 4))], s.entry_session) END, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years)');
        EXECUTE d;
    END LOOP;
    d := pg_get_functiondef('finance.import_legacy_payments(jsonb)'::regprocedure);
    IF position('v_level := greatest(coalesce(st.entry_level, 100), reporting.level_in_session(st.entry_level, CASE WHEN st.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN st.entry_session ELSE coalesce(v_cs_first[array_position(v_cs_adm, policy.session_normal(st.entry_session))], st.entry_session) END, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into));' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: finance.import_legacy_payments is not as V740 left it';
    END IF;
    d := replace(d, 'v_level := greatest(coalesce(st.entry_level, 100), reporting.level_in_session(st.entry_level, CASE WHEN st.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN st.entry_session ELSE coalesce(v_cs_first[array_position(v_cs_adm, policy.session_normal(st.entry_session))], st.entry_session) END, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into));',
                    'v_level := reporting.level_in_session(st.entry_level, CASE WHEN st.entry_mode IN (''CCE'', ''POSTGRADUATE'') THEN st.entry_session ELSE coalesce(v_cs_first[array_position(v_cs_adm, left(st.entry_session, 4))], st.entry_session) END, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into);   -- V741');
    EXECUTE d;
    d := pg_get_viewdef('reporting.payments'::regclass, true);
    IF position('    GREATEST(COALESCE(st.entry_level, 100), reporting.level_in_session(st.entry_level,' IN d) = 0
       OR position('COALESCE(cs.firsts[array_position(cs.admissions, policy.session_normal(st.entry_session))], st.entry_session)' IN d) = 0
       OR position(' r.session, cy.years, cy.into_years)) AS level,' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: reporting.payments is not as V740 left it';
    END IF;
    d := replace(d, '    GREATEST(COALESCE(st.entry_level, 100), reporting.level_in_session(st.entry_level,', '    reporting.level_in_session(st.entry_level,');
    d := replace(d, 'COALESCE(cs.firsts[array_position(cs.admissions, policy.session_normal(st.entry_session))], st.entry_session)',
                    'COALESCE(cs.firsts[array_position(cs.admissions, "left"(st.entry_session, 4))], st.entry_session)');
    d := replace(d, ' r.session, cy.years, cy.into_years)) AS level,', ' r.session, cy.years, cy.into_years) AS level,');
    EXECUTE 'CREATE OR REPLACE VIEW reporting.payments AS ' || d;

    -- ── a Summer payment an open credit names is neither moved nor archived ──
    d := pg_get_functiondef('finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)'::regprocedure);
    IF position('    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: finance.payment_reallocation_check is not as V739 left it';
    END IF;
    d := replace(d, '    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739',
                    '    IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.reference_id = r.id AND x.state = ''OPEN'') THEN   -- V741
        refusals := refusals || ''REALLOC_LINKED: an unapplied Summer credit names this payment; the Bursar settles it on Summer Semester Fees first''::text;
    END IF;
    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739');
    EXECUTE d;
    d := pg_get_functiondef('finance.payment_archive_refusals(uuid)'::regprocedure);
    IF position('    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: finance.payment_archive_refusals is not as V739 left it';
    END IF;
    d := replace(d, '    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739',
                    '    IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.reference_id = r.id AND x.state = ''OPEN'') THEN   -- V741
        refusals := refusals || ''PAR_LINKED: an unapplied Summer credit names this payment; the Bursar settles it on Summer Semester Fees first''::text;
    END IF;
    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739');
    EXECUTE d;

    -- ── an assessment on a session before the first year is neither made nor approved ──
    d := pg_get_functiondef('finance.historical_assessment_save(uuid,uuid,text,integer,numeric,jsonb,text,text,text,text,uuid,boolean)'::regprocedure);
    IF position('    SELECT x.* INTO per FROM finance.historical_account(p_student) x WHERE x.session = p_session AND x.semester = p_semester;' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: finance.historical_assessment_save is not as V720 left it';
    END IF;
    d := replace(d, '    SELECT x.* INTO per FROM finance.historical_account(p_student) x WHERE x.session = p_session AND x.semester = p_semester;',
                    '    IF EXISTS (SELECT 1 FROM people.student st WHERE st.id = p_student AND st.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'')
                  AND p_session < people.first_session(st.entry_session, st.entry_mode)) THEN   -- V741
        RAISE EXCEPTION ''HFA_BEFORE_FIRST_YEAR: % is before the student''''s first year of study; nothing is assessed for it'', p_session USING ERRCODE = ''23514'';
    END IF;
    SELECT x.* INTO per FROM finance.historical_account(p_student) x WHERE x.session = p_session AND x.semester = p_semester;');
    EXECUTE d;
    d := pg_get_functiondef('finance.historical_assessment_decide(uuid,text,text)'::regprocedure);
    IF position('    IF v_dec = ''APPROVE'' THEN
        IF a.corrects IS NOT NULL THEN' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: finance.historical_assessment_decide is not as V654 left it';
    END IF;
    d := replace(d, '    IF v_dec = ''APPROVE'' THEN
        IF a.corrects IS NOT NULL THEN',
                    '    IF v_dec = ''APPROVE'' AND EXISTS (SELECT 1 FROM people.student st WHERE st.id = a.student_id AND st.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'')
                                         AND a.session < people.first_session(st.entry_session, st.entry_mode)) THEN   -- V741
        RAISE EXCEPTION ''HFA_BEFORE_FIRST_YEAR: % is before the student''''s first year of study; reject the assessment'', a.session USING ERRCODE = ''23514'';
    END IF;
    IF v_dec = ''APPROVE'' THEN
        IF a.corrects IS NOT NULL THEN');
    EXECUTE d;

    -- ── the cohort engine: a merged admission stays MERGED; the readers know COHORT_START ──
    d := pg_get_functiondef('people.academic_position_rows_of(uuid[])'::regprocedure);
    IF position('                    WHEN st.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'') AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(st.entry_session)) THEN ''COHORT_START''
                    WHEN st.merged_into IS NOT NULL THEN ''MERGED'' ELSE ''ENTRY'' END AS cohort_source,' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: people.academic_position_rows_of is not as V740 left it';
    END IF;
    d := replace(d, '                    WHEN st.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'') AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(st.entry_session)) THEN ''COHORT_START''
                    WHEN st.merged_into IS NOT NULL THEN ''MERGED'' ELSE ''ENTRY'' END AS cohort_source,',
                    '                    WHEN st.merged_into IS NOT NULL THEN ''MERGED''   -- V741: a merged admission is named as before
                    WHEN st.entry_mode NOT IN (''CCE'', ''POSTGRADUATE'') AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(st.entry_session)) THEN ''COHORT_START''
                    ELSE ''ENTRY'' END AS cohort_source,');
    EXECUTE d;
    d := pg_get_functiondef((SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'people' AND p.proname = 'graduation_candidates'));
    IF position('fr.matric_year_differs AND fr.cohort_source = ''ENTRY'' THEN' IN d) = 0 OR position('fr.matric_year_differs AND fr.cohort_source <> ''ENTRY'' THEN' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: people.graduation_candidates is not as V638 left it';
    END IF;
    d := replace(d, 'fr.matric_year_differs AND fr.cohort_source = ''ENTRY'' THEN', 'fr.matric_year_differs AND fr.cohort_source IN (''ENTRY'', ''COHORT_START'') THEN');
    d := replace(d, 'fr.matric_year_differs AND fr.cohort_source <> ''ENTRY'' THEN', 'fr.matric_year_differs AND fr.cohort_source NOT IN (''ENTRY'', ''COHORT_START'') THEN');
    EXECUTE d;
    d := pg_get_viewdef('people.lifecycle_recommendation'::regclass, true);
    IF position('                    WHEN ''OVERRIDE''::text THEN ('' (cohort set by the Registry to ''::text || b.effective_cohort) || '')''::text' IN d) = 0 THEN
        RAISE EXCEPTION 'V741: people.lifecycle_recommendation is not as V558 left it';
    END IF;
    d := replace(d, '                    WHEN ''OVERRIDE''::text THEN ('' (cohort set by the Registry to ''::text || b.effective_cohort) || '')''::text',
                    '                    WHEN ''OVERRIDE''::text THEN ('' (cohort set by the Registry to ''::text || b.effective_cohort) || '')''::text
                    WHEN ''COHORT_START''::text THEN ('' (first year in ''::text || b.effective_cohort) || '', the session after admission)''::text');
    EXECUTE 'CREATE OR REPLACE VIEW people.lifecycle_recommendation AS ' || d;
END $$;

-- ── the Summer: a credit shown only while its payment stands as a Summer payment; a take-back that commits; nothing passed billed;
--    the programme fee never revived alone ──
CREATE OR REPLACE FUNCTION registration.summer_account(p_student uuid, p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH ref AS (SELECT r.reference, r.amount FROM finance.payment_reference r
                  WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Summer semester fees%'
                    AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
                    AND registration.summer_reference_payable(r.reference)
                  ORDER BY r.generated_at DESC LIMIT 1)
    SELECT jsonb_build_object(
        'session', p_session,
        'programmeFee', (SELECT c.amount FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'PROGRAMME' AND c.state <> 'CANCELLED' ORDER BY c.created_at DESC LIMIT 1),
        'programmeFeeState', (SELECT c.state FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'PROGRAMME' AND c.state <> 'CANCELLED' ORDER BY c.created_at DESC LIMIT 1),
        'coursesSelected', (SELECT count(*) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'DUE'),
        'coursesPaid', (SELECT count(*) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'PAID'),
        'courseFeesDue', (SELECT coalesce(sum(c.amount), 0) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'DUE'),
        'programmeFeeDue', (SELECT coalesce(sum(c.amount), 0) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'PROGRAMME' AND c.state = 'DUE'),
        'due', (SELECT coalesce(sum(c.amount), 0) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'DUE'),
        'paid', (SELECT coalesce(sum(c.amount), 0) FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'PAID'),
        'openReference', (SELECT ref.reference FROM ref),
        'openAmount', (SELECT ref.amount FROM ref),
        'credit', (SELECT coalesce(sum(x.amount), 0) FROM registration.summer_credit x JOIN finance.payment_reference pr ON pr.id = x.reference_id
                    WHERE x.student_id = p_student AND x.session = p_session AND x.state = 'OPEN'
                      AND pr.archived_at IS NULL AND pr.purpose LIKE 'Summer semester fees%'),   -- V741: while the payment stands as a Summer payment
        'registration', (SELECT jsonb_build_object('id', r.id, 'status', r.status, 'approvedAt', r.approved_at,
                                                  'courses', (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')))
                           FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session AND r.semester = 3));
$$;

/* the reference for everything owed. A course chosen and no longer outstanding (passed since, an authorised one too) or no longer taught
   is taken back first; when that leaves nothing owed, the take-back stands and no reference is drawn (NULL) */
CREATE OR REPLACE FUNCTION registration.summer_reference(p_student uuid, p_session text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_due numeric; v_ref text; v_id uuid; v_courses int; v_prog boolean; v_taken int := 0; n int;
BEGIN
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT registration.summer_open(p_session) THEN
        RAISE EXCEPTION 'SUMMER_CLOSED: registration for the Summer Semester of % is not open', p_session USING ERRCODE = '23514';
    END IF;
    UPDATE registration.summer_charge c SET state = 'CANCELLED', cancelled_at = now()
     WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'DUE'
       AND (EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = c.course_code AND k.state = 'ENDED')
            OR NOT EXISTS (SELECT 1 FROM registration.summer_courses(p_student, p_session) sc WHERE sc.course_code = c.course_code AND coalesce(sc.reason, '') <> 'PASSED'));
    GET DIAGNOSTICS v_taken = ROW_COUNT;
    UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now()
     WHERE student_id = p_student AND session = p_session AND kind = 'PROGRAMME' AND state = 'DUE'
       AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session
                         AND c.kind = 'COURSE' AND c.state IN ('DUE', 'PAID'));
    GET DIAGNOSTICS n = ROW_COUNT;
    v_taken := v_taken + n;
    PERFORM registration.summer_close_stale_references(p_student, p_session);
    SELECT coalesce(sum(amount), 0), count(*) FILTER (WHERE kind = 'COURSE'), bool_or(kind = 'PROGRAMME')
      INTO v_due, v_courses, v_prog FROM registration.summer_charge
     WHERE student_id = p_student AND session = p_session AND state = 'DUE';
    IF v_due <= 0 THEN
        IF v_taken > 0 THEN RETURN NULL; END IF;   -- V741: what was chosen is no longer owed; the take-back stands
        RAISE EXCEPTION 'SUMMER_NOTHING_DUE: nothing is owed for the Summer Semester of %', p_session USING ERRCODE = '23514',
            HINT = 'Select your courses first; what is paid stays registered.';
    END IF;
    SELECT r.reference INTO v_ref FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Summer semester fees%'
       AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.amount = v_due
     ORDER BY r.generated_at DESC LIMIT 1;
    IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    v_ref := finance.new_purpose_reference(p_student, p_session, v_due,
        'Summer semester fees, ' || p_session || ': ' || concat_ws(' and ',
            CASE WHEN v_prog THEN 'programme fee' END,
            CASE WHEN v_courses > 0 THEN v_courses || ' course' || CASE WHEN v_courses = 1 THEN '' ELSE 's' END END));
    SELECT id INTO v_id FROM finance.payment_reference WHERE reference = v_ref;
    INSERT INTO registration.summer_reference_charge (reference_id, charge_id)
    SELECT v_id, c.id FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'DUE';
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION registration.summer_reference_confirmed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_applied numeric := 0; c registration.summer_charge; v_err text; v_prog uuid; v_prog_amount numeric;
BEGIN
    IF NEW.student_id IS NULL THEN RETURN NULL; END IF;
    WITH u AS (UPDATE registration.summer_charge ch SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id
                 FROM registration.summer_reference_charge rc
                WHERE rc.reference_id = NEW.id AND rc.charge_id = ch.id AND ch.state = 'DUE'
               RETURNING ch.amount)
    SELECT coalesce(sum(u.amount), 0) INTO v_applied FROM u;
    FOR c IN SELECT ch.* FROM registration.summer_reference_charge rc JOIN registration.summer_charge ch ON ch.id = rc.charge_id
              WHERE rc.reference_id = NEW.id AND ch.state = 'CANCELLED' ORDER BY (ch.kind = 'PROGRAMME') DESC, ch.created_at
    LOOP
        CONTINUE WHEN NEW.amount - v_applied < c.amount;
        CONTINUE WHEN EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.student_id = c.student_id AND x.session = c.session AND x.kind = c.kind
                                 AND x.course_code IS NOT DISTINCT FROM c.course_code AND x.state <> 'CANCELLED');
        -- V741: a course passed since (an authorised one too) is never revived
        CONTINUE WHEN c.kind = 'COURSE' AND NOT EXISTS (SELECT 1 FROM registration.summer_courses(c.student_id, c.session) sc
                                                           WHERE sc.course_code = c.course_code AND coalesce(sc.reason, '') <> 'PASSED');
        CONTINUE WHEN c.kind = 'COURSE' AND NOT EXISTS (SELECT 1 FROM registration.summer_charge y WHERE y.student_id = c.student_id AND y.session = c.session
                                                           AND y.kind = 'PROGRAMME' AND y.state = 'PAID');
        UPDATE registration.summer_charge SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id, cancelled_at = NULL WHERE id = c.id;
        IF c.kind = 'PROGRAMME' THEN v_prog := c.id; v_prog_amount := c.amount; END IF;
        v_applied := v_applied + c.amount;
    END LOOP;
    FOR c IN SELECT x.* FROM registration.summer_charge x WHERE x.student_id = NEW.student_id AND x.session = NEW.session AND x.state = 'DUE'
              ORDER BY (x.kind = 'PROGRAMME') DESC, x.created_at
    LOOP
        EXIT WHEN c.kind = 'COURSE' AND EXISTS (SELECT 1 FROM registration.summer_charge y WHERE y.student_id = NEW.student_id AND y.session = NEW.session
                                                   AND y.kind = 'PROGRAMME' AND y.state = 'DUE');
        CONTINUE WHEN NEW.amount - v_applied < c.amount;
        UPDATE registration.summer_charge SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id WHERE id = c.id;
        v_applied := v_applied + c.amount;
    END LOOP;
    -- V741: the programme fee revived with no course of the Summer standing beside it goes back: its money stands as credit
    IF v_prog IS NOT NULL AND NOT EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.student_id = NEW.student_id AND x.session = NEW.session
                                             AND x.kind = 'COURSE' AND x.state IN ('DUE', 'PAID')) THEN
        UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now(), paid_at = NULL, paid_reference_id = NULL WHERE id = v_prog;
        v_applied := v_applied - v_prog_amount;
    END IF;
    IF NEW.amount - v_applied >= 1 THEN
        INSERT INTO registration.summer_credit (student_id, session, reference_id, amount) VALUES (NEW.student_id, NEW.session, NEW.id, NEW.amount - v_applied);
    END IF;
    PERFORM registration.summer_close_stale_references(NEW.student_id, NEW.session);
    BEGIN
        PERFORM registration.summer_materialize(NEW.student_id, NEW.session);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
        INSERT INTO registration.summer_issue (student_id, session, reference_id, error) VALUES (NEW.student_id, NEW.session, NEW.id, v_err);
    END;
    RETURN NULL;
END $$;

-- ── what the Bursary and the Registry are told ──────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_ids uuid[]; n_level int; n_before int; n_merged int;
BEGIN
    SELECT array_agg(st.id) INTO v_ids FROM people.student st
     WHERE st.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
       AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(st.entry_session));
    -- assessments made, or being made, at a level the first-year count now reads otherwise (V725 told the Bursary the same)
    SELECT count(*) INTO n_level FROM finance.historical_assessment h
     WHERE h.student_id = ANY (coalesce(v_ids, '{}')) AND h.state IN ('DRAFT', 'PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'APPROVED')
       AND h.level IS DISTINCT FROM people.level_in(h.student_id, h.session, h.semester);
    -- assessments being made on a session before the first year (none may now be approved: reject them)
    SELECT count(*) INTO n_before FROM finance.historical_assessment h JOIN people.student st ON st.id = h.student_id
     WHERE st.id = ANY (coalesce(v_ids, '{}')) AND h.state IN ('DRAFT', 'PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION')
       AND h.session < people.first_session(st.entry_session, st.entry_mode);
    -- the merged admissions read MERGED again
    SELECT array_agg(st.id) INTO v_ids FROM people.student st JOIN policy.academic_session a ON a.name = st.entry_session
     WHERE a.merged_into IS NOT NULL AND st.id = ANY (coalesce(v_ids, '{}'));
    IF coalesce(cardinality(v_ids), 0) > 0 THEN PERFORM people.refresh_academic_positions(v_ids); END IF;
    n_merged := coalesce(cardinality(v_ids), 0);
    RAISE NOTICE 'V741: % historical assessments at a level the first-year count now reads otherwise, % being made on a session before the first year (to be rejected); % merged admissions read MERGED again',
        n_level, n_before, n_merged;
END $$;

COMMIT;

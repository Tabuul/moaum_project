-- V366: GST & EPS owed only for a course the student must take.
--
-- The brief: "A STUDENT SHOULD NEVER SEE A GST OR EPS FEE SIMPLY BECAUSE THEY ARE A STUDENT." The fee, the gate, the offices'
-- figures and the CBT candidate list must follow the student's ACTUAL GST/EPS course requirement for the session — the
-- programme's own offerings at their level, a carryover not yet passed — enforced in the database, not by hiding a card.
--
-- What V314 did, and why it was wrong. finance.gst_required asked one thing: does the student's programme list any course of
-- kind GST at their current level? It never asked whether the course runs in the session (catalogue.offering), whether the
-- student has already passed it, or whether they carry one over from an earlier level. So:
--   * a student whose programme lists a GST/EPS course at their level was held to the fee even in a session that does not run
--     it, or after passing it;
--   * a 300- or 400-level student carrying GST 101 over read NOT_REQUIRED on the dashboard, while the gate on the carryover
--     entry still demanded the fee — the student was told both "nothing owed" and "pay before you register";
--   * with the whole-registration rule on (finance.gst_setting.required_for_all — on in production since 6 Oct 2026) that
--     over-broad answer held back every course of every student it misjudged;
--   * finance.new_gst_reference never asked at all: any student could open a GST fee reference for themselves.
--
-- What V366 does. One engine — finance.gst_eps_rows(session, student) — reads, for each undergraduate in good standing, the
-- GST-kind courses that concern them in a session, from the records the University already keeps:
--   COURSE_OFFERING  the programme offers the course at the student's level (catalogue.course_offer, track and curriculum as the
--                    registration menu reads them) — counted only when it runs in the session (catalogue.offering) and the
--                    student has not already passed it in an earlier session;
--   CARRYOVER        failed before the session (a published, graded F, not passed since — registration.carryovers_at's rule,
--                    electives never carried) — counted when it runs in the session, whatever the student's level now;
--   REGISTERED       on the student's registration for the session — taken, so counted.
-- Results are resolved exactly as assessment.course_final resolves them (a published special or re-sit over the main sitting),
-- read set-based so the offices' population is counted in one pass. The level is the student's current level for the current
-- and later sessions (as the menu reads it) and the level they registered at for an earlier one; never guessed.
--
-- On that one answer: finance.gst_eps_eligibility (the student's GST and EPS requirement, with a reason code), finance.gst_required,
-- finance.gst_entitlement (NOT_REQUIRED unless a course requires it; EXEMPT for a stated ₦0; a payment that no course requires
-- flagged for the Bursary's review — never deleted, never refunded here), finance.new_gst_reference (refused when nothing is
-- owed), registration.gst_gate (holds only a student who owes the fee), registration.student_menu (a GST/EPS course already
-- passed is not offered again), finance.gst_population (the offices' counts: eligible, carryover, completed, not applicable),
-- finance.gst_eps_explain (the "why is this student paying GST/EPS?" view) and finance.entitlement_state (the support desk).
-- The fee stays the Bursar's (finance.gst_fee) and the one GST payment still covers EPS where finance.gst_setting says so.
-- Nothing is cached: a change of programme, level, offering, registration, result or payment is read the next time it is asked.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V366: GST & EPS owed only for a course the student must take', true);

-- ── 1 · the engine: the GST/EPS courses that concern each student in a session, and why ─────────────────────────

CREATE OR REPLACE FUNCTION finance.gst_eps_rows(p_session text, p_student uuid DEFAULT NULL)
RETURNS TABLE (student_id uuid, course_code text, title text, units int, office text, level int, semesters int[], offering_id uuid,
               source text, counts boolean, status text, registered boolean, failed_in text, last_grade text, passed_in text)
LANGUAGE sql STABLE AS $$
    WITH cur AS (SELECT coalesce(max(name), '') AS name FROM policy.academic_session WHERE state = 'CURRENT'),
    -- the undergraduates in good standing it may concern, at the level the session reads them at
    base AS (
        SELECT s.id, s.programme_code, s.curriculum_track, s.curriculum_version,
               CASE WHEN p_session >= cur.name THEN s.current_level
                    ELSE (SELECT max(cr.level) FROM registration.course_registration cr WHERE cr.student_id = s.id AND cr.session = p_session) END AS level
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          CROSS JOIN cur
         WHERE (p_student IS NULL OR s.id = p_student) AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    gc AS (SELECT c.code, c.title, c.units, c.level, c.general_office, c.curriculum, c.state
             FROM catalogue.course c WHERE c.kind = 'GST' AND c.code NOT LIKE 'DMO %'),
    -- the GST/EPS courses the session runs, in which semesters
    offered AS (SELECT o.course_code, array_agg(o.semester ORDER BY o.semester) AS semesters, (array_agg(o.id ORDER BY o.semester))[1] AS offering_id
                  FROM catalogue.offering o JOIN gc ON gc.code = o.course_code
                 WHERE o.session = p_session
                 GROUP BY o.course_code),
    -- every GST/EPS registration entry of these students up to the session
    ent AS (SELECT cr.student_id, cr.session, cr.semester, cr.status AS reg_status, e.status AS entry_status, o.id AS offering_id, o.course_code
              FROM base b
              JOIN registration.course_registration cr ON cr.student_id = b.id AND cr.session <= p_session
              JOIN registration.entry e ON e.registration_id = cr.id
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN gc ON gc.code = o.course_code),
    -- the record's results: the entries of approved registrations, as assessment.student_results reads them
    rec AS (SELECT DISTINCT x.student_id, x.session, x.semester, x.offering_id, x.course_code FROM ent x
             WHERE x.reg_status IN ('APPROVED', 'LOCKED') AND x.entry_status IN ('REGISTERED', 'APPROVED')),
    sheets AS (SELECT sh.id, sh.offering_id, sh.stage, coalesce(es.kind, 'MAIN') AS kind
                 FROM assessment.score_sheet sh
                 LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                WHERE sh.offering_id IN (SELECT r.offering_id FROM rec r)),
    -- each sheet's latest scores read once, not once per student
    scores AS MATERIALIZED (SELECT sh.id AS sheet_id, ls.student_id, ls.points, ls.outcome, ls.grade
                              FROM sheets sh CROSS JOIN LATERAL assessment.latest_scores(sh.id) ls),
    sitting AS (SELECT r.student_id, r.session, r.semester, r.offering_id, r.course_code, sh.stage, sh.kind, sc.points, sc.outcome, sc.grade,
                       CASE sh.kind WHEN 'SPECIAL' THEN 1 WHEN 'RESIT' THEN 2 ELSE 3 END AS pr
                  FROM rec r JOIN sheets sh ON sh.offering_id = r.offering_id
                  LEFT JOIN scores sc ON sc.sheet_id = sh.id AND sc.student_id = r.student_id),
    -- assessment.course_final's resolution: a published special or re-sit the student sat supersedes the main sitting
    fin AS (SELECT DISTINCT ON (x.student_id, x.offering_id) x.*
                FROM sitting x
               WHERE (x.kind IN ('SPECIAL', 'RESIT') AND x.stage = 'PUBLISHED' AND x.outcome IS NOT NULL) OR x.kind = 'MAIN'
               ORDER BY x.student_id, x.offering_id, x.pr),
    res AS (SELECT f.student_id, f.course_code, f.session, f.semester, f.grade,
                   coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points > 0, false) AS passed,
                   coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points = 0, false) AS failed
              FROM fin f),
    -- registration.carryovers_at's rule as of the session's start: failed, not passed since, never an elective
    carry AS (SELECT DISTINCT ON (f.student_id, f.course_code) f.student_id, f.course_code, f.session || ' semester ' || f.semester AS failed_in, f.grade
                FROM res f JOIN base b ON b.id = f.student_id
               WHERE f.failed AND f.session < p_session
                 AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co
                                  WHERE co.course_code = f.course_code AND co.programme_code = b.programme_code AND co.basis = 'Elective')
                 AND NOT EXISTS (SELECT 1 FROM res g
                                  WHERE g.student_id = f.student_id AND g.course_code = f.course_code AND g.passed
                                    AND (g.session, g.semester) > (f.session, f.semester) AND g.session < p_session)
               ORDER BY f.student_id, f.course_code, f.session, f.semester),
    pass AS (SELECT r.student_id, r.course_code, bool_or(r.session < p_session) AS before, bool_or(r.session = p_session) AS now,
                    max(r.session || ' semester ' || r.semester) AS passed_in
               FROM res r WHERE r.passed GROUP BY r.student_id, r.course_code),
    fail_now AS (SELECT DISTINCT r.student_id, r.course_code FROM res r WHERE r.failed AND r.session = p_session),
    reg AS (SELECT x.student_id, x.course_code FROM ent x WHERE x.session = p_session AND x.entry_status <> 'DROPPED' GROUP BY x.student_id, x.course_code),
    -- the programme's own GST/EPS courses at the student's level, read as the registration menu reads them
    curric AS (SELECT b.id AS student_id, co.course_code, co.level
                 FROM base b
                 JOIN catalogue.course_offer co ON co.programme_code = b.programme_code AND co.level = b.level
                                               AND (co.track IS NULL OR b.curriculum_track IS NULL OR co.track = b.curriculum_track)
                 JOIN gc ON gc.code = co.course_code AND gc.state <> 'ENDED'
                WHERE gc.curriculum IS NULL OR b.curriculum_version IS NULL OR gc.curriculum = b.curriculum_version),
    src AS (SELECT c.student_id, c.course_code, 'CARRYOVER'::text AS source, 1 AS pr, NULL::int AS level FROM carry c
            UNION ALL SELECT c.student_id, c.course_code, 'COURSE_OFFERING', 2, c.level FROM curric c
            UNION ALL SELECT r.student_id, r.course_code, 'REGISTERED', 3, NULL FROM reg r),
    one AS (SELECT DISTINCT ON (s.student_id, s.course_code) s.* FROM src s ORDER BY s.student_id, s.course_code, s.pr)
    SELECT o.student_id, o.course_code, gc.title, gc.units, coalesce(gc.general_office, 'GST'), coalesce(o.level, gc.level), off.semesters, off.offering_id, o.source,
           -- owed this session: being taken; or run this session and still owed (a carryover, or the programme's course not yet passed)
           (rg.course_code IS NOT NULL OR (off.course_code IS NOT NULL AND (o.source = 'CARRYOVER' OR NOT coalesce(ps.before, false)))),
           CASE WHEN coalesce(ps.now, false) THEN 'COMPLETED'
                WHEN fn.course_code IS NOT NULL THEN 'FAILED'
                WHEN rg.course_code IS NOT NULL THEN 'REGISTERED'
                WHEN o.source = 'COURSE_OFFERING' AND coalesce(ps.before, false) THEN 'ALREADY_PASSED'
                WHEN off.course_code IS NULL THEN 'NOT_OFFERED'
                ELSE 'OUTSTANDING' END,
           rg.course_code IS NOT NULL, ca.failed_in, ca.grade, ps.passed_in
      FROM one o
      JOIN gc ON gc.code = o.course_code
      LEFT JOIN offered off ON off.course_code = o.course_code
      LEFT JOIN reg rg ON rg.student_id = o.student_id AND rg.course_code = o.course_code
      LEFT JOIN pass ps ON ps.student_id = o.student_id AND ps.course_code = o.course_code
      LEFT JOIN fail_now fn ON fn.student_id = o.student_id AND fn.course_code = o.course_code
      LEFT JOIN carry ca ON ca.student_id = o.student_id AND ca.course_code = o.course_code
$$;
COMMENT ON FUNCTION finance.gst_eps_rows(text, uuid) IS
  'V366: the GST-kind courses (GST and EPS) that concern each undergraduate in good standing in a session — one student, or all when none is named. '
  'source COURSE_OFFERING (the programme offers it at the student''s level), CARRYOVER (failed before the session, not passed since, never an elective) or REGISTERED (on the session''s registration); '
  'counts = owed this session (taken, or run this session and still owed); status OUTSTANDING, REGISTERED, COMPLETED, FAILED, ALREADY_PASSED or NOT_OFFERED. '
  'Results resolved as assessment.course_final resolves them. The one source of every GST/EPS obligation.';

-- the reason code an office's answer is given with
CREATE OR REPLACE FUNCTION finance.gst_eps_reason(p_office text, p_offering boolean, p_carry boolean, p_registered boolean, p_completed boolean, p_not_offered boolean)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT p_office || CASE WHEN p_offering THEN '_REQUIRED_COURSE_OFFERING'
                            WHEN p_carry THEN '_REQUIRED_CARRYOVER'
                            WHEN p_registered THEN '_REQUIRED_REGISTERED'
                            WHEN p_completed THEN '_ALREADY_COMPLETED'
                            WHEN p_not_offered THEN '_COURSE_NOT_OFFERED'
                            ELSE '_NOT_APPLICABLE' END
$$;
COMMENT ON FUNCTION finance.gst_eps_reason(text, boolean, boolean, boolean, boolean, boolean) IS
  'V366: GST_ or EPS_ + REQUIRED_COURSE_OFFERING | REQUIRED_CARRYOVER | REQUIRED_REGISTERED | ALREADY_COMPLETED | COURSE_NOT_OFFERED | NOT_APPLICABLE, in that order of precedence.';

-- ── 2 · one student's answer: GST, EPS, and whether the GST fee is owed ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION finance.gst_eps_eligibility(p_student uuid, p_session text)
RETURNS TABLE (applicable boolean, required boolean, covers_eps boolean, level int,
               gst_required boolean, eps_required boolean, gst_reason text, eps_reason text, reason text,
               gst_courses text[], eps_courses text[], gst_carryovers text[], eps_carryovers text[], gst_completed text[], eps_completed text[])
LANGUAGE sql STABLE AS $$
    WITH st AS (SELECT s.status, s.current_level, p.category FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = p_student),
    one AS (SELECT (st.category = 'UNDER GRADUATE') AS ug, (st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')) AS active, st.current_level
              FROM (SELECT 1) x LEFT JOIN st ON true),
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    r AS (SELECT * FROM finance.gst_eps_rows(p_session, p_student)),
    lvl AS (SELECT max(r.level) FILTER (WHERE r.source = 'COURSE_OFFERING') AS level FROM r),
    o AS (SELECT k.office,
                 coalesce(bool_or(r.counts), false) AS req,
                 coalesce(bool_or(r.counts AND r.source = 'COURSE_OFFERING'), false) AS by_offering,
                 coalesce(bool_or(r.counts AND r.source = 'CARRYOVER'), false) AS by_carry,
                 coalesce(bool_or(r.counts AND r.source = 'REGISTERED'), false) AS by_reg,
                 coalesce(bool_or(r.status = 'ALREADY_PASSED'), false) AS done,
                 coalesce(bool_or(r.status = 'NOT_OFFERED'), false) AS not_offered,
                 coalesce(array_agg(r.course_code ORDER BY r.course_code) FILTER (WHERE r.counts), '{}') AS courses,
                 coalesce(array_agg(r.course_code ORDER BY r.course_code) FILTER (WHERE r.counts AND r.source = 'CARRYOVER'), '{}') AS carry,
                 coalesce(array_agg(r.course_code ORDER BY r.course_code) FILTER (WHERE r.status IN ('ALREADY_PASSED', 'COMPLETED')), '{}') AS completed
            FROM (VALUES ('GST'), ('EPS')) k(office) LEFT JOIN r ON r.office = k.office
           GROUP BY k.office),
    g AS (SELECT * FROM o WHERE office = 'GST'),
    e AS (SELECT * FROM o WHERE office = 'EPS'),
    why AS (SELECT CASE WHEN one.ug IS NOT TRUE THEN 'PROGRAMME_NOT_ELIGIBLE' WHEN one.active IS NOT TRUE THEN 'STUDENT_NOT_ACTIVE' END AS out FROM one)
    SELECT coalesce(one.ug AND one.active, false),
           g.req OR (e.req AND cfg.covers_eps),
           cfg.covers_eps,
           coalesce(lvl.level, one.current_level),
           g.req, e.req,
           coalesce(why.out, finance.gst_eps_reason('GST', g.by_offering, g.by_carry, g.by_reg, g.done, g.not_offered)),
           coalesce(why.out, finance.gst_eps_reason('EPS', e.by_offering, e.by_carry, e.by_reg, e.done, e.not_offered)),
           coalesce(why.out, CASE WHEN g.req THEN finance.gst_eps_reason('GST', g.by_offering, g.by_carry, g.by_reg, g.done, g.not_offered)
                                  WHEN e.req AND cfg.covers_eps THEN finance.gst_eps_reason('EPS', e.by_offering, e.by_carry, e.by_reg, e.done, e.not_offered)
                                  WHEN e.req THEN 'EPS_NOT_COVERED_BY_GST_FEE'
                                  ELSE finance.gst_eps_reason('GST', g.by_offering, g.by_carry, g.by_reg, g.done, g.not_offered) END),
           g.courses, e.courses, g.carry, e.carry, g.completed, e.completed
      FROM one CROSS JOIN cfg CROSS JOIN g CROSS JOIN e CROSS JOIN why CROSS JOIN lvl
$$;
COMMENT ON FUNCTION finance.gst_eps_eligibility(uuid, text) IS
  'V366: one student''s GST and EPS requirement for a session from finance.gst_eps_rows — required (the GST fee is owed: a GST course, or an EPS course where the GST payment covers EPS), '
  'each office''s answer with its reason code, the courses owed, the carryovers among them and the ones completed. PROGRAMME_NOT_ELIGIBLE for a programme not undergraduate; STUDENT_NOT_ACTIVE otherwise out of standing.';

CREATE OR REPLACE FUNCTION finance.gst_required(p_student uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT e.required FROM finance.gst_eps_eligibility(p_student, p_session) e), false)
$$;
COMMENT ON FUNCTION finance.gst_required(uuid, text) IS
  'V366 (was V314''s "the programme lists a GST course at the level"): whether the GST fee is owed for the session — a GST course the student must take, or an EPS course where the GST payment covers EPS (finance.gst_eps_eligibility).';

-- ── 3 · the entitlement: NOT_REQUIRED unless a course requires it; a ₦0 statement is an exemption; a needless payment is reviewed ─

DROP FUNCTION IF EXISTS finance.gst_entitlement(uuid, text);
CREATE FUNCTION finance.gst_entitlement(p_student uuid, p_session text)
RETURNS TABLE (required boolean, stated boolean, fee numeric, covers_eps boolean, paid numeric, entitled boolean, state text,
               reference text, receipt_no text, paid_at timestamptz, open_reference text, open_amount numeric, open_expires_at timestamptz,
               source text, channel text, legacy_reference text,
               gst_required boolean, eps_required boolean, reason text, gst_reason text, eps_reason text, review boolean)
LANGUAGE sql STABLE AS $$
    WITH f AS (SELECT * FROM finance.gst_fee_for(p_student, p_session)),
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    pays AS (SELECT r.id, r.reference, r.receipt_no, r.amount, r.confirmed_at, r.channel
               FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))),
    agg AS (SELECT coalesce(sum(amount), 0) AS paid, max(confirmed_at) AS paid_at, count(*) AS n FROM pays),
    last AS (SELECT p.id, p.reference, p.receipt_no, p.channel FROM pays p ORDER BY p.confirmed_at DESC LIMIT 1),
    open AS (SELECT r.reference, r.amount, r.expires_at
               FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()
              ORDER BY r.generated_at DESC LIMIT 1),
    el AS (SELECT * FROM finance.gst_eps_eligibility(p_student, p_session)),
    -- whether this portal runs GST/EPS in the session at all: a payment no course requires is only questioned where it does
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session) AS gst_run)
    SELECT el.required, f.stated, f.amount, cfg.covers_eps, agg.paid,
           -- a confirmed reference was generated for the fee as it stood: a later change of the fee does not unmake the payment
           (agg.n > 0 OR (f.stated AND f.amount = 0)) AS entitled,
           CASE WHEN agg.n > 0 THEN 'PAID'
                WHEN NOT el.required THEN 'NOT_REQUIRED'
                WHEN f.stated AND f.amount = 0 THEN 'EXEMPT'
                WHEN NOT f.stated THEN 'NOT_STATED'
                WHEN open.reference IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           last.reference, last.receipt_no, agg.paid_at, open.reference, open.amount, open.expires_at,
           CASE WHEN last.id IS NULL THEN NULL WHEN last.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           last.channel,
           (SELECT coalesce(lp.source_reference, lp.source_transaction_id) FROM finance.legacy_gst_reconciliation rc JOIN finance.legacy_gst_payment lp ON lp.id = rc.payment_id WHERE rc.payment_reference_id = last.id),
           el.gst_required, el.eps_required, el.reason, el.gst_reason, el.eps_reason,
           (agg.n > 0 AND NOT el.required AND run.gst_run)
      FROM f CROSS JOIN cfg CROSS JOIN agg CROSS JOIN el CROSS JOIN run LEFT JOIN last ON true LEFT JOIN open ON true
$$;
COMMENT ON FUNCTION finance.gst_entitlement(uuid, text) IS
  'The authoritative answer (V314; source V323; V366: required from the student''s GST/EPS courses): entitled when a CONFIRMED reference of purpose ''GST fee <session>'' stands for the student, net of approved or paid refunds. '
  'state PAID, NOT_REQUIRED (no course requires the fee), EXEMPT (a ₦0 fee stated for the student), NOT_STATED, PENDING or NOT_PAID. review: paid, yet no GST/EPS course requires it in a session this portal runs — the Bursary''s to review; the payment is never deleted or refunded here.';

-- the reference: only a student who owes the fee opens one
CREATE OR REPLACE FUNCTION finance.new_gst_reference(p_student uuid, p_session text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE e record;
BEGIN
    SELECT * INTO e FROM finance.gst_entitlement(p_student, p_session);
    IF e.state = 'PAID' THEN
        RAISE EXCEPTION 'GST_ALREADY_PAID: the GST fee for % is paid in full (receipt %)', p_session, coalesce(e.receipt_no, e.reference) USING ERRCODE = '23514',
            HINT = 'It is paid once and covers both GST and EPS.';
    END IF;
    IF NOT e.required THEN
        RAISE EXCEPTION 'GST_NOT_REQUIRED: no GST or EPS course requires the GST fee of you in %', p_session USING ERRCODE = '23514',
            HINT = 'The fee is owed for a GST course (or an EPS course the GST payment covers) offered to your programme at your level, or a GST/EPS carryover. If you believe a course is missing, ask ICT Support to check your eligibility.';
    END IF;
    IF e.stated AND e.fee = 0 THEN
        RAISE EXCEPTION 'GST_EXEMPT: the GST fee stated for you in % is nothing; there is nothing to pay', p_session USING ERRCODE = '23514';
    END IF;
    IF NOT e.stated THEN
        RAISE EXCEPTION 'GST_FEE_NOT_STATED: no GST fee is stated for %', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the GST fee for the session before it is paid.';
    END IF;
    IF e.open_reference IS NOT NULL THEN RETURN e.open_reference; END IF;
    RETURN finance.new_purpose_reference(p_student, p_session, e.fee - e.paid, 'GST fee ' || p_session);
END $$;

-- ── 4 · the gate holds only a student who owes the fee ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION registration.gst_gate(p_student uuid, p_session text, p_course text)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT kind, general_office FROM catalogue.course WHERE code = p_course),
         g AS (SELECT * FROM finance.gst_setting WHERE id = 1),
         e AS (SELECT * FROM finance.gst_entitlement(p_student, p_session))
    SELECT CASE WHEN e.required AND e.stated AND e.fee > 0 AND NOT e.entitled
                     AND ((g.required_for_gst_eps AND c.kind = 'GST' AND (coalesce(c.general_office, 'GST') = 'GST' OR g.covers_eps))
                          OR g.required_for_all)
                THEN 'GST_PAYMENT_REQUIRED: you are required to pay the GST fee of NGN ' || to_char(e.fee, 'FM999,999,999,990.00') || ' for ' || p_session
                     || ' before you can register ' || CASE WHEN c.kind = 'GST' THEN coalesce(c.general_office, 'GST') || ' courses' ELSE 'your courses' END
                     || '. GST payment covers both GST and EPS requirements.'
                ELSE NULL END
      FROM g CROSS JOIN e LEFT JOIN c ON true
$$;
COMMENT ON FUNCTION registration.gst_gate(uuid, text, text) IS
  'The GST gate on one course (V314; V366: only a student whose GST/EPS courses require the fee): the refusal while the stated GST fee is unpaid, for a GST/EPS course (required_for_gst_eps) or for any course (required_for_all); NULL when the student may go on. '
  'A student no GST/EPS course concerns is never held, whatever the rule.';

-- ── 5 · the registration menu: a GST/EPS course already passed is not offered again ─────────────────────────────
-- Restated as V264 left it, with one condition in "eligible": a course of kind GST the student passed in an earlier session.

CREATE OR REPLACE FUNCTION registration.student_menu(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (offering_id uuid, course_code text, title text, units int, kind text, basis text, owner_dept text,
               carryover boolean, failed_in text, lecturer text, deferred boolean, deferred_from text)
LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    -- V366: the GST/EPS courses of the programme at this level the student has already passed
    gst_passed AS (SELECT x.course_code FROM finance.gst_eps_rows(p_session, p_student) x WHERE x.status = 'ALREADY_PASSED'),
    eligible AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, co.basis, c.dept_code
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
          JOIN catalogue.course c ON c.code = co.course_code AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
         WHERE (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
           AND NOT (c.kind = 'GST' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))),
    carry AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Carryover'::text AS basis, c.dept_code, cv.failed_in
          FROM registration.carryovers(p_student) cv
          JOIN catalogue.course c ON c.code = cv.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)),
    -- a course set aside by an approved deferment, due since the student returned, offered this semester and not yet passed
    deferred AS (
        SELECT o.id AS offering_id, c.code, c.title, c.units, c.kind, 'Deferred'::text AS basis, c.dept_code,
               dc.original_session || ' semester ' || dc.original_semester AS deferred_from
          FROM people.deferred_courses(p_student) dc
          JOIN catalogue.course c ON c.code = dc.course_code AND c.code NOT LIKE 'DMO %'
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester
          CROSS JOIN s
         WHERE dc.status = 'DEFERRED' AND dc.due
           AND (dc.original_session, dc.original_semester) < (p_session, p_semester)
           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code))
    SELECT x.offering_id, x.code, x.title, x.units, x.kind, x.basis, d.name,
           (x.basis IN ('Carryover','Deferred')), x.failed_in, p.surname || ', ' || p.given_names,
           (x.basis = 'Deferred'), x.deferred_from
      FROM (SELECT e.*, NULL::text AS failed_in, NULL::text AS deferred_from FROM eligible e
            WHERE NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.offering_id = e.offering_id)
              AND NOT EXISTS (SELECT 1 FROM deferred df WHERE df.offering_id = e.offering_id)
            UNION ALL SELECT cv.*, NULL::text AS deferred_from FROM carry cv
            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df) x
      JOIN ref.department d ON d.code = x.dept_code
      JOIN catalogue.offering o ON o.id = x.offering_id
      LEFT JOIN iam.person p ON p.id = o.lecturer_id
     ORDER BY (x.basis = 'Carryover') DESC, (x.basis = 'Deferred') DESC, x.kind, x.code;
$$;

-- ── 6 · what the offices read: the population counted on the same answer ────────────────────────────────────────

DROP FUNCTION IF EXISTS finance.gst_population(text, int);
CREATE FUNCTION finance.gst_population(p_session text, p_semester int)
RETURNS TABLE (student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text,
               programme_code text, programme text, level int, status text, entry_mode text,
               required boolean, fee numeric, stated boolean, paid numeric, entitled boolean, pay_state text, reference text, paid_at timestamptz,
               gst_registered boolean, eps_registered boolean, gst_courses int, eps_courses int, registered_at timestamptz, pay_source text,
               gst_required boolean, eps_required boolean, gst_reason text, eps_reason text,
               gst_carryover boolean, eps_carryover boolean, gst_completed boolean, eps_completed boolean,
               gst_owed text, eps_owed text, review boolean)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex,
               p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, s.programme_code, p.name AS programme,
               s.current_level AS level, s.status, s.entry_mode
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = d.faculty_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session) AS gst_run),
    -- the engine over the whole register at once; a semester asked for narrows what is owed to the courses run in it
    eng AS (SELECT r.student_id, r.office, r.source, r.status, r.course_code,
                   (r.counts AND (p_semester IS NULL OR p_semester = ANY (r.semesters))) AS due
              FROM finance.gst_eps_rows(p_session, NULL) r),
    req AS (SELECT x.student_id,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'GST'), false) AS g_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'GST'), false) AS g_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'GST'), false) AS g_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'GST'), false) AS g_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'GST'), false) AS g_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'GST'), false) AS g_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'GST' AND x.due), false) AS g_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'GST' AND x.due) AS g_owed,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'EPS'), false) AS e_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'EPS'), false) AS e_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'EPS'), false) AS e_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'EPS'), false) AS e_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'EPS'), false) AS e_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'EPS'), false) AS e_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'EPS' AND x.due), false) AS e_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'EPS' AND x.due) AS e_owed
              FROM eng x GROUP BY x.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM finance.gst_fee f WHERE f.session = p_session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    pays AS (SELECT r.student_id, sum(r.amount) AS paid, max(r.confirmed_at) AS paid_at, count(*) AS n,
                    (array_agg(r.reference ORDER BY r.confirmed_at DESC))[1] AS reference,
                    (array_agg(r.channel ORDER BY r.confirmed_at DESC))[1] AS channel
               FROM finance.payment_reference r
              WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.reference = r.reference AND rf.state IN ('APPROVED', 'PAID'))
              GROUP BY r.student_id),
    pend AS (SELECT DISTINCT r.student_id FROM finance.payment_reference r
              WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()),
    regs AS (SELECT cr.student_id,
                    count(*) FILTER (WHERE c.general_office = 'GST') AS gst_courses,
                    count(*) FILTER (WHERE c.general_office = 'EPS') AS eps_courses,
                    min(cr.submitted_at) AS registered_at
               FROM registration.course_registration cr
               JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
               JOIN catalogue.offering o ON o.id = e.offering_id
               JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
              WHERE cr.session = p_session AND (p_semester IS NULL OR cr.semester = p_semester)
              GROUP BY cr.student_id),
    j AS (SELECT b.*, coalesce(q.g_req, false) AS g_req, coalesce(q.e_req, false) AS e_req,
                 (coalesce(q.g_req, false) OR (coalesce(q.e_req, false) AND cfg.covers_eps)) AS req,
                 q.g_off, q.g_carry, q.g_reg, q.g_done, q.g_none, q.g_complete, q.g_owed,
                 q.e_off, q.e_carry, q.e_reg, q.e_done, q.e_none, q.e_complete, q.e_owed,
                 fr.id AS fee_id, fr.amount AS fee_amount, py.paid, py.paid_at, py.n, py.reference, py.channel, pd.student_id AS pending,
                 rg.gst_courses, rg.eps_courses, rg.registered_at, run.gst_run AS run_on
            FROM base b
            CROSS JOIN cfg CROSS JOIN run
            LEFT JOIN req q ON q.student_id = b.id
            LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                  AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                LIMIT 1) fr ON true
            LEFT JOIN pays py ON py.student_id = b.id
            LEFT JOIN pend pd ON pd.student_id = b.id
            LEFT JOIN regs rg ON rg.student_id = b.id)
    SELECT j.id, j.number, j.surname, j.other_names, j.sex, j.faculty_code, j.faculty, j.dept_code, j.department, j.programme_code, j.programme,
           j.level, j.status, j.entry_mode,
           j.req,
           coalesce(j.fee_amount, 0), (j.fee_id IS NOT NULL),
           coalesce(j.paid, 0),
           (coalesce(j.n, 0) > 0 OR (j.fee_id IS NOT NULL AND j.fee_amount = 0)),
           CASE WHEN coalesce(j.n, 0) > 0 THEN 'PAID'
                WHEN NOT j.req THEN 'NOT_REQUIRED'
                WHEN j.fee_id IS NOT NULL AND j.fee_amount = 0 THEN 'EXEMPT'
                WHEN j.fee_id IS NULL THEN 'NOT_STATED'
                WHEN j.pending IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           j.reference, j.paid_at,
           coalesce(j.gst_courses, 0) > 0, coalesce(j.eps_courses, 0) > 0, coalesce(j.gst_courses, 0)::int, coalesce(j.eps_courses, 0)::int, j.registered_at,
           CASE WHEN j.n IS NULL THEN NULL WHEN j.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           j.g_req, j.e_req,
           finance.gst_eps_reason('GST', coalesce(j.g_off, false), coalesce(j.g_carry, false), coalesce(j.g_reg, false), coalesce(j.g_done, false), coalesce(j.g_none, false)),
           finance.gst_eps_reason('EPS', coalesce(j.e_off, false), coalesce(j.e_carry, false), coalesce(j.e_reg, false), coalesce(j.e_done, false), coalesce(j.e_none, false)),
           coalesce(j.g_carry, false), coalesce(j.e_carry, false), coalesce(j.g_complete, false), coalesce(j.e_complete, false),
           j.g_owed, j.e_owed,
           (coalesce(j.n, 0) > 0 AND NOT j.req AND j.run_on)
      FROM j
$$;
COMMENT ON FUNCTION finance.gst_population(text, int) IS
  'One row per undergraduate in good standing for a session (V314; source V323; V366: required from finance.gst_eps_rows, the whole register in one pass): the GST fee owed or not, '
  'each office''s requirement with its reason code, carryover, completed, the courses owed, the fee, what was paid and from which portal, the registrations, and review (paid, yet no course requires it). '
  'A semester narrows what is owed to the courses run in it. The one source of the GST and EPS dashboards, lists, exports and the Bursary''s standing.';

-- ── 7 · "why is this student paying GST/EPS?": the whole answer, for the student, the offices and the support desk ─

CREATE OR REPLACE FUNCTION finance.gst_eps_explain(p_student uuid, p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'session', p_session,
        'student', (SELECT jsonb_build_object('id', s.id, 'number', coalesce(s.matric_no, s.admission_no), 'surname', s.surname, 'otherNames', s.other_names,
                                              'level', s.current_level, 'status', s.status, 'entryMode', s.entry_mode,
                                              'programmeCode', p.code, 'programme', p.name, 'category', p.category,
                                              'deptCode', d.code, 'department', d.name, 'facultyCode', f.code, 'faculty', f.name)
                      FROM people.student s
                      LEFT JOIN ref.programme p ON p.code = s.programme_code
                      LEFT JOIN ref.department d ON d.code = p.dept_code
                      LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
                     WHERE s.id = p_student),
        'semesters', (SELECT coalesce(jsonb_agg(jsonb_build_object('number', sm.number, 'state', sm.state) ORDER BY sm.number), '[]'::jsonb)
                        FROM policy.semester sm WHERE sm.session = p_session),
        'eligibility', (SELECT to_jsonb(e) FROM finance.gst_eps_eligibility(p_student, p_session) e),
        'entitlement', (SELECT to_jsonb(g) FROM finance.gst_entitlement(p_student, p_session) g),
        'courses', (SELECT coalesce(jsonb_agg(to_jsonb(r) - 'student_id' ORDER BY r.office DESC, r.counts DESC, r.course_code), '[]'::jsonb)
                      FROM finance.gst_eps_rows(p_session, p_student) r))
$$;
COMMENT ON FUNCTION finance.gst_eps_explain(uuid, text) IS
  'V366: the whole GST/EPS answer for one student in a session — who they are (programme, department, faculty, level), the eligibility with reasons, the entitlement, and every GST/EPS course that concerns them with its source and status. '
  'Read by the student for themselves, by the GST/EPS offices, the Bursary, the Academic Office and the ICT Support desk; it changes nothing.';

-- ── 8 · the support desk's diagnosis carries the requirement and its reason ─────────────────────────────────────

CREATE OR REPLACE FUNCTION finance.entitlement_state(p_student uuid, p_session text)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    WITH g AS (SELECT * FROM finance.gst_entitlement(p_student, p_session))
    SELECT jsonb_build_object(
        'session', p_session, 'due', pos.due, 'paid', pos.paid, 'balance', pos.balance, 'paidInFull', pos.paid_in_full, 'hasArrears', pos.has_arrears,
        'clearsRegistration', finance.clears_or_null(p_student, p_session, 'REGISTRATION'),
        'semester1Cleared', finance.semester_cleared(p_student, p_session, 1),
        'semester2Cleared', finance.semester_cleared(p_student, p_session, 2),
        'gstEntitled', (SELECT g.entitled FROM g),
        'gstState', (SELECT g.state FROM g),
        'gstRequired', (SELECT g.gst_required FROM g),
        'epsRequired', (SELECT g.eps_required FROM g),
        'gstFeeRequired', (SELECT g.required FROM g),
        'gstReason', (SELECT g.reason FROM g),
        'gstReview', (SELECT g.review FROM g),
        'positionComputedAt', (SELECT ap.computed_at FROM people.academic_position ap WHERE ap.student_id = p_student))
      FROM finance.position(p_student, p_session) pos
$$;
COMMENT ON FUNCTION finance.entitlement_state(uuid, text) IS 'V346 (V366: the GST/EPS requirement and its reason added): the student''s entitlement in a session as the engine reads it from confirmed payments — the position, registration clearance, each semester, the GST entitlement — for the support desk''s diagnosis.';

COMMIT;

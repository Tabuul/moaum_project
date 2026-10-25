-- ═══════════════════════════════════════
-- V650 — The Master University Report: one dataset, one summary, PDF, Excel and the dashboard from it
--
--   The University's master prompt of 23 October 2026 ("COMPREHENSIVE UNIVERSITY ACADEMIC, FINANCE, GST/EPS & STUDENT PAYMENT
--   REPORTING ENGINE"): one report package — student population, school fees, transactions, GST, EPS, course registration, the
--   examination card and the GST & EPS permit, by faculty, department, programme, level, gender, session and semester — from the
--   portal's own data, the PDF and the Excel from one dataset, every scoped office held to its own.
--
--   Nothing is rebuilt; every figure is an existing engine's:
--     · the students: reporting.exam_readiness (V640) on reporting.student_positions (V257) — the classification (V469), the fee
--       position (finance.session_positions: payable, paid, outstanding, FULLY_PAID / PART_PAYMENT / NOT_PAID / NO_CHARGE), the
--       registration across the postgraduate, College and University registers, the examination card's own rule (V567);
--     · GST and EPS: finance.gst_population (V468) — owed, registered, paid (the GST engine's entitlement, V366), the GST fee and what
--       is paid of it; the EPS fee is the GST fee where the Bursar's setting says it covers EPS, else a payment of its own;
--     · the examination card issued: registration.exam_card_issue (V501), the portal's record of each card the student drew;
--     · the GST & EPS permit: registration.gst_eps_permit (V492) — generated, downloaded and printed counts, revoked;
--     · the transactions: reporting.payments (V409), every payment of the one ledger with its classification, each with its status
--       as the finance engine holds it — SUCCESSFUL (confirmed), PENDING, FAILED (expired unpaid), REVERSED (Interswitch's reversal),
--       REFUNDED (a refund paid against it) — and its net amount (less any refund paid); a reallocated payment (V649) is one row.
--
--   reporting.master_rows — one row a student, the filters a jsonb the API builds on the server (the scope it holds the office to,
--   never the browser's); reporting.master_summary — one pass over the same rows, grouped by the University, faculty, department,
--   programme, level, gender, programme type and study mode (GROUPING SETS: a faculty is the sum of its departments by
--   construction); reporting.master_payments — the transactions; the report's reference RPT/YYYY/NNNNNN on the official report
--   register (V640, kind MASTER), with its status and formats.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V650: the master university report (the University, 23 October 2026)', true);

-- ── 1 · the student dataset ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION reporting.master_rows(p_session text, p_semester int, p_f jsonb)
RETURNS TABLE (
    student_id uuid, matric_no text, jamb_no text, surname text, other_names text, sex text, status text, academic_status text,
    programme_type text, admission_route text, study_mode text, centre_code text,
    faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level int, entry_session text,
    fee_status text, payable numeric, paid_amount numeric, outstanding numeric, last_paid_at timestamptz, school_fees_paid boolean,
    registered boolean, registration_status text, carryovers int, courses int, units int, paid_not_registered boolean,
    gst_status text, gst_registered boolean, gst_required boolean, gst_fee numeric, gst_paid_amount numeric, gst_outstanding numeric, gst_paid_at timestamptz,
    gst_reference text, eps_status text, eps_registered boolean, eps_required boolean,
    card_eligible boolean, card_issued boolean, card_issued_at timestamptz, card_times int,
    permit_eligible boolean, permit_generated boolean, permit_printed boolean, permit_reference text, permit_generated_at timestamptz,
    permit_printed_times int)
LANGUAGE sql STABLE AS $$
    WITH f AS (SELECT nullif(btrim(p_f->>'fac'), '') AS fac, nullif(btrim(p_f->>'dept'), '') AS dept, nullif(btrim(p_f->>'prog'), '') AS prog,
                      (nullif(btrim(p_f->>'level'), ''))::int AS lvl, nullif(btrim(p_f->>'type'), '') AS typ),
         cfg AS (SELECT coalesce((SELECT covers_eps FROM finance.gst_setting WHERE id = 1), true) AS covers_eps),
         r AS (SELECT x.* FROM f CROSS JOIN LATERAL reporting.exam_readiness(p_session, p_semester, f.fac, f.dept, f.prog, f.lvl, f.typ, NULL, 'CARD') x),
         g AS (SELECT * FROM finance.gst_population(p_session, p_semester)),
         -- a payment of the EPS fee of its own, where the GST fee does not cover it
         eps_pay AS (SELECT pr.student_id, sum(pr.amount) AS paid FROM finance.payment_reference pr
                      WHERE pr.session = p_session AND pr.confirmed_at IS NOT NULL AND pr.purpose ~* '^eps'
                        AND NOT (SELECT covers_eps FROM cfg) GROUP BY pr.student_id),
         card AS (SELECT c.student_id, c.first_at, c.times FROM registration.exam_card_issue c WHERE c.session = p_session AND c.semester = p_semester),
         pm AS (SELECT p.student_id, p.reference, p.generated_at, p.printed FROM registration.gst_eps_permit p
                 WHERE p.session = p_session AND p.semester = p_semester AND p.revoked_at IS NULL),
         m AS (
            SELECT r.student_id, r.matric_no, r.jamb_no, r.surname, r.other_names, r.sex, r.status, r.academic_status, r.programme_type, r.admission_route,
                   r.study_mode, st.centre_code, r.faculty_code, r.faculty, r.dept_code, r.department, r.programme_code, r.programme, r.level, r.entry_session,
                   r.fee_status, r.payable, r.paid_amount, r.outstanding, r.last_paid_at, coalesce(r.school_fees_paid, false) AS school_fees_paid,
                   coalesce(r.registered, false) AS registered, r.registration_status, coalesce(r.carryovers, 0) AS carryovers, coalesce(r.courses, 0) AS courses,
                   coalesce(r.units, 0) AS units,
                   coalesce(r.school_fees_paid, false) AND NOT coalesce(r.registered, false) AS paid_not_registered,
                   CASE WHEN g.student_id IS NULL OR NOT (coalesce(g.gst_required, false) OR coalesce(g.gst_registered, false) OR coalesce(g.paid, 0) > 0) THEN 'NOT_APPLICABLE'
                        WHEN g.entitled THEN 'PAID' WHEN coalesce(g.paid, 0) > 0 THEN 'PART_PAID' ELSE 'NOT_PAID' END AS gst_status,
                   coalesce(g.gst_registered, false) AS gst_registered, coalesce(g.gst_required, false) AS gst_required,
                   CASE WHEN coalesce(g.required, false) OR coalesce(g.paid, 0) > 0 THEN g.fee END AS gst_fee,
                   coalesce(g.paid, 0) AS gst_paid_amount,
                   CASE WHEN coalesce(g.required, false) AND NOT coalesce(g.entitled, false) THEN greatest(coalesce(g.fee, 0) - coalesce(g.paid, 0), 0) ELSE 0 END AS gst_outstanding,
                   g.paid_at AS gst_paid_at, g.reference AS gst_reference,
                   CASE WHEN g.student_id IS NULL OR NOT (coalesce(g.eps_required, false) OR coalesce(g.eps_registered, false)) THEN 'NOT_APPLICABLE'
                        WHEN (SELECT covers_eps FROM cfg) AND coalesce(g.entitled, false) THEN 'PAID'
                        WHEN NOT (SELECT covers_eps FROM cfg) AND ep.paid > 0 THEN 'PAID'
                        ELSE 'NOT_PAID' END AS eps_status,
                   coalesce(g.eps_registered, false) AS eps_registered, coalesce(g.eps_required, false) AS eps_required,
                   coalesce(r.exam_card, false) AS card_eligible, c.student_id IS NOT NULL AS card_issued, c.first_at AS card_issued_at, coalesce(c.times, 0) AS card_times,
                   -- the permit's own rule read on the register: a GST/EPS course on a submitted registration of the semester, the school fees
                   -- paid by the card's test, the GST fee paid where it is owed (V492, V589)
                   (coalesce(g.gst_registered, false) OR coalesce(g.eps_registered, false)) AND coalesce(r.school_fees_paid, false)
                       AND (NOT coalesce(g.required, false) OR coalesce(g.entitled, false)) AS permit_eligible,
                   pm.student_id IS NOT NULL AS permit_generated, coalesce(pm.printed, 0) > 0 AS permit_printed, pm.reference AS permit_reference,
                   pm.generated_at AS permit_generated_at, coalesce(pm.printed, 0) AS permit_printed_times
              FROM r
              JOIN people.student st ON st.id = r.student_id
              LEFT JOIN g ON g.student_id = r.student_id
              LEFT JOIN eps_pay ep ON ep.student_id = r.student_id
              LEFT JOIN card c ON c.student_id = r.student_id
              LEFT JOIN pm ON pm.student_id = r.student_id)
    SELECT m.* FROM m
     WHERE (nullif(p_f->>'sex', '') IS NULL OR upper(coalesce(m.sex, 'U')) = upper(p_f->>'sex'))
       AND (nullif(p_f->>'astatus', '') IS NULL OR m.academic_status = upper(p_f->>'astatus'))
       AND (nullif(p_f->>'route', '') IS NULL OR m.admission_route = upper(p_f->>'route'))
       AND (nullif(p_f->>'mode', '') IS NULL OR upper(coalesce(m.study_mode, '')) = upper(p_f->>'mode'))
       AND (nullif(p_f->>'centre', '') IS NULL OR upper(coalesce(m.centre_code, '')) = upper(p_f->>'centre'))
       AND (nullif(p_f->>'fee', '') IS NULL OR CASE upper(p_f->>'fee')
                WHEN 'PAID' THEN m.fee_status = 'FULLY_PAID' WHEN 'PART_PAID' THEN m.fee_status = 'PART_PAYMENT'
                WHEN 'NOT_PAID' THEN m.fee_status = 'NOT_PAID' WHEN 'NO_FEE_STATED' THEN m.fee_status = 'NO_CHARGE'
                WHEN 'ANY_PAYMENT' THEN m.school_fees_paid ELSE true END)
       AND (nullif(p_f->>'reg', '') IS NULL OR CASE upper(p_f->>'reg')
                WHEN 'REGISTERED' THEN m.registered WHEN 'NOT_REGISTERED' THEN NOT m.registered
                WHEN 'PAID_NOT_REGISTERED' THEN m.paid_not_registered WHEN 'CARRYOVER' THEN m.registered AND m.carryovers > 0 ELSE true END)
       AND (nullif(p_f->>'gst', '') IS NULL OR CASE upper(p_f->>'gst')
                WHEN 'PAID' THEN m.gst_status = 'PAID' WHEN 'NOT_PAID' THEN m.gst_status IN ('NOT_PAID', 'PART_PAID')
                WHEN 'REGISTERED' THEN m.gst_registered WHEN 'NOT_REGISTERED' THEN m.gst_status <> 'NOT_APPLICABLE' AND NOT m.gst_registered
                WHEN 'APPLICABLE' THEN m.gst_status <> 'NOT_APPLICABLE' ELSE true END)
       AND (nullif(p_f->>'eps', '') IS NULL OR CASE upper(p_f->>'eps')
                WHEN 'PAID' THEN m.eps_status = 'PAID' WHEN 'NOT_PAID' THEN m.eps_status = 'NOT_PAID'
                WHEN 'REGISTERED' THEN m.eps_registered WHEN 'NOT_REGISTERED' THEN m.eps_status <> 'NOT_APPLICABLE' AND NOT m.eps_registered
                WHEN 'APPLICABLE' THEN m.eps_status <> 'NOT_APPLICABLE' ELSE true END)
       AND (nullif(p_f->>'card', '') IS NULL OR CASE upper(p_f->>'card')
                WHEN 'ELIGIBLE' THEN m.card_eligible WHEN 'NOT_ELIGIBLE' THEN NOT m.card_eligible
                WHEN 'ISSUED' THEN m.card_issued WHEN 'NOT_ISSUED' THEN m.card_eligible AND NOT m.card_issued ELSE true END)
       AND (nullif(p_f->>'permit', '') IS NULL OR CASE upper(p_f->>'permit')
                WHEN 'ELIGIBLE' THEN m.permit_eligible WHEN 'GENERATED' THEN m.permit_generated WHEN 'PRINTED' THEN m.permit_printed
                WHEN 'NOT_PRINTED' THEN m.permit_eligible AND NOT m.permit_printed ELSE true END)
$$;
COMMENT ON FUNCTION reporting.master_rows(text, int, jsonb) IS
  'V650: the master report''s students for a session and semester — one row a student on reporting.exam_readiness (classification, fee position, registration, the examination card''s rule), with GST and EPS from finance.gst_population (owed, registered, paid), the card issued (registration.exam_card_issue) and the GST & EPS permit generated and printed (registration.gst_eps_permit); filtered by a jsonb (fac, dept, prog, level, type, sex, astatus, route, mode, centre, fee, reg, gst, eps, card, permit) the API builds on the server';

-- ── 2 · the summary: one pass over the same rows, by every dimension ───────────────────────────────────────────────────
CREATE FUNCTION reporting.master_summary(p_session text, p_semester int, p_f jsonb)
RETURNS TABLE (
    dim text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level int, sex text,
    programme_type text, study_mode text,
    departments bigint, programmes bigint, total bigint, male bigint, female bigint, sex_unknown bigint,
    fees_paid bigint, fees_part bigint, fees_not_paid bigint, no_fee bigint, any_payment bigint, paid_not_registered bigint,
    registered bigint, not_registered bigint, carryover_registered bigint, reg_approved bigint, reg_pending bigint,
    payable numeric, paid_amount numeric, outstanding numeric,
    gst_applicable bigint, gst_registered bigint, gst_paid bigint, gst_not_paid bigint, gst_paid_amount numeric, gst_outstanding numeric,
    eps_applicable bigint, eps_registered bigint, eps_paid bigint, eps_not_paid bigint,
    card_eligible bigint, card_issued bigint, card_not_issued bigint, card_not_eligible bigint,
    permit_eligible bigint, permit_generated bigint, permit_printed bigint, permit_not_printed bigint,
    registered_not_paid bigint, gst_registered_not_paid bigint, card_issued_not_eligible bigint, permit_generated_not_eligible bigint)
LANGUAGE sql STABLE AS $$
    WITH m AS MATERIALIZED (SELECT * FROM reporting.master_rows(p_session, p_semester, p_f))
    SELECT CASE GROUPING(m.faculty_code, m.dept_code, m.programme_code, m.level, m.sex, m.programme_type, m.study_mode)
                WHEN 127 THEN 'ALL' WHEN 63 THEN 'FACULTY' WHEN 31 THEN 'DEPARTMENT' WHEN 15 THEN 'PROGRAMME' WHEN 7 THEN 'PROGRAMME_LEVEL'
                WHEN 119 THEN 'LEVEL' WHEN 123 THEN 'GENDER' WHEN 125 THEN 'PROGRAMME_TYPE' WHEN 126 THEN 'STUDY_MODE'
                WHEN 59 THEN 'FACULTY_GENDER' END,
           m.faculty_code, max(m.faculty), m.dept_code, max(m.department), m.programme_code, max(m.programme), m.level, m.sex, m.programme_type, m.study_mode,
           count(DISTINCT m.dept_code), count(DISTINCT m.programme_code), count(*),
           count(*) FILTER (WHERE upper(m.sex) IN ('M', 'MALE')), count(*) FILTER (WHERE upper(m.sex) IN ('F', 'FEMALE')),
           count(*) FILTER (WHERE m.sex IS NULL OR upper(m.sex) NOT IN ('M', 'MALE', 'F', 'FEMALE')),
           count(*) FILTER (WHERE m.fee_status = 'FULLY_PAID'), count(*) FILTER (WHERE m.fee_status = 'PART_PAYMENT'),
           count(*) FILTER (WHERE m.fee_status = 'NOT_PAID'), count(*) FILTER (WHERE m.fee_status = 'NO_CHARGE'),
           count(*) FILTER (WHERE m.school_fees_paid), count(*) FILTER (WHERE m.paid_not_registered),
           count(*) FILTER (WHERE m.registered), count(*) FILTER (WHERE NOT m.registered), count(*) FILTER (WHERE m.registered AND m.carryovers > 0),
           count(*) FILTER (WHERE m.registration_status IN ('APPROVED', 'LOCKED', 'ENDORSED')), count(*) FILTER (WHERE m.registration_status = 'SUBMITTED'),
           coalesce(sum(m.payable), 0), coalesce(sum(m.paid_amount), 0), coalesce(sum(m.outstanding), 0),
           count(*) FILTER (WHERE m.gst_status <> 'NOT_APPLICABLE'), count(*) FILTER (WHERE m.gst_registered),
           count(*) FILTER (WHERE m.gst_status = 'PAID'), count(*) FILTER (WHERE m.gst_status IN ('NOT_PAID', 'PART_PAID')),
           coalesce(sum(m.gst_paid_amount), 0), coalesce(sum(m.gst_outstanding), 0),
           count(*) FILTER (WHERE m.eps_status <> 'NOT_APPLICABLE'), count(*) FILTER (WHERE m.eps_registered),
           count(*) FILTER (WHERE m.eps_status = 'PAID'), count(*) FILTER (WHERE m.eps_status = 'NOT_PAID'),
           count(*) FILTER (WHERE m.card_eligible), count(*) FILTER (WHERE m.card_issued), count(*) FILTER (WHERE m.card_eligible AND NOT m.card_issued),
           count(*) FILTER (WHERE NOT m.card_eligible),
           count(*) FILTER (WHERE m.permit_eligible), count(*) FILTER (WHERE m.permit_generated), count(*) FILTER (WHERE m.permit_printed),
           count(*) FILTER (WHERE m.permit_eligible AND NOT m.permit_printed),
           -- the exceptions the data-quality section lists (never put right here)
           count(*) FILTER (WHERE m.registered AND m.fee_status = 'NOT_PAID'),
           count(*) FILTER (WHERE m.gst_registered AND m.gst_status IN ('NOT_PAID', 'PART_PAID')),
           count(*) FILTER (WHERE m.card_issued AND NOT m.card_eligible),
           count(*) FILTER (WHERE m.permit_generated AND NOT m.permit_eligible)
      FROM m
     GROUP BY GROUPING SETS ((), (m.faculty_code), (m.faculty_code, m.dept_code), (m.faculty_code, m.dept_code, m.programme_code),
                            (m.faculty_code, m.dept_code, m.programme_code, m.level), (m.level), (m.sex), (m.programme_type), (m.study_mode),
                            (m.faculty_code, m.sex))
$$;
COMMENT ON FUNCTION reporting.master_summary(text, int, jsonb) IS
  'V650: the master report''s figures in one pass over reporting.master_rows — the University (ALL), each faculty, department, programme, programme and level, level, gender, programme type, study mode and faculty by gender: students, gender, school fees (paid in full, part paid, not paid, no fee stated, any payment, paid but not registered, amounts), registration, GST and EPS (applicable, registered, paid, not paid, amounts), the examination card (eligible, issued) and the GST & EPS permit (eligible, generated, printed)';

-- ── 3 · the transactions ────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION reporting.master_payments(p_session text, p_from date, p_to date, p_f jsonb)
RETURNS TABLE (
    payment_id uuid, reference text, gateway_reference text, receipt_no text, source text, student_id uuid, number text, surname text, other_names text,
    sex text, jamb_reg_no text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text,
    programme_type text, level int, session text, semester int, purpose text, purpose_code text, purpose_label text, amount numeric,
    refunded numeric, net_amount numeric, generated_at timestamptz, confirmed_at timestamptz, channel text, status text, on_day date)
LANGUAGE sql STABLE AS $$
    WITH v AS (
        SELECT p.* FROM reporting.payments p
         WHERE (p_session IS NULL OR p.session = p_session)
           AND (p_from IS NULL OR (coalesce(p.confirmed_at, p.generated_at) AT TIME ZONE 'Africa/Lagos')::date >= p_from)
           AND (p_to IS NULL OR (coalesce(p.confirmed_at, p.generated_at) AT TIME ZONE 'Africa/Lagos')::date <= p_to)
           AND (nullif(p_f->>'fac', '') IS NULL OR p.faculty_code = p_f->>'fac')
           AND (nullif(p_f->>'dept', '') IS NULL OR p.dept_code = p_f->>'dept')
           AND (nullif(p_f->>'prog', '') IS NULL OR p.programme_code = p_f->>'prog')
           AND (nullif(p_f->>'level', '') IS NULL OR p.level = (p_f->>'level')::int)
           AND (nullif(p_f->>'type', '') IS NULL OR p.programme_type = p_f->>'type')
           AND (nullif(p_f->>'sex', '') IS NULL OR upper(coalesce(p.sex, 'U')) = upper(p_f->>'sex'))
           AND (nullif(p_f->>'semester', '') IS NULL OR p.semester = (p_f->>'semester')::int)
           AND (nullif(p_f->>'purpose', '') IS NULL OR p.purpose_code = upper(p_f->>'purpose'))
           AND (nullif(p_f->>'channel', '') IS NULL OR p.channel ILIKE (p_f->>'channel'))
           AND (nullif(p_f->>'source', '') IS NULL OR p.source = upper(p_f->>'source'))),
    refunds AS (SELECT r.source_reference, sum(r.amount) AS amount FROM finance.refund r
                 WHERE r.state = 'PAID' AND r.source_reference IN (SELECT v.reference FROM v) GROUP BY r.source_reference),
    reversed AS (SELECT DISTINCT x.reference FROM finance.paydirect_inbox x WHERE x.is_reversal AND x.reference IN (SELECT v.reference FROM v)),
    gw AS (SELECT DISTINCT ON (e.reference) e.reference, e.gateway_ref FROM finance.gateway_event e
            WHERE e.reference IN (SELECT v.reference FROM v) AND e.outcome IN ('SETTLED', 'ALREADY_SETTLED') AND e.gateway_ref IS NOT NULL
            ORDER BY e.reference, e.received_at DESC),
    t AS (
        SELECT v.payment_id, v.reference, gw.gateway_ref, v.receipt_no, v.source, v.student_id, v.number, v.surname, v.other_names, v.sex, v.jamb_reg_no,
               v.faculty_code, v.faculty, v.dept_code, v.department, v.programme_code, v.programme, v.programme_type, v.level, v.session, v.semester,
               v.purpose, v.purpose_code, pp.label AS purpose_label, v.amount, coalesce(rf.amount, 0) AS refunded,
               CASE WHEN v.confirmed_at IS NULL OR rv.reference IS NOT NULL THEN 0 ELSE greatest(v.amount - coalesce(rf.amount, 0), 0) END AS net_amount,
               v.generated_at, v.confirmed_at, v.channel,
               CASE WHEN rv.reference IS NOT NULL THEN 'REVERSED'
                    WHEN v.confirmed_at IS NOT NULL AND coalesce(rf.amount, 0) >= v.amount THEN 'REFUNDED'
                    WHEN v.confirmed_at IS NOT NULL THEN 'SUCCESSFUL'
                    WHEN v.expires_at IS NOT NULL AND v.expires_at <= now() THEN 'FAILED'
                    ELSE 'PENDING' END AS status,
               (coalesce(v.confirmed_at, v.generated_at) AT TIME ZONE 'Africa/Lagos')::date AS on_day
          FROM v
          LEFT JOIN refunds rf ON rf.source_reference = v.reference
          LEFT JOIN reversed rv ON rv.reference = v.reference
          LEFT JOIN gw ON gw.reference = v.reference
          LEFT JOIN finance.payment_purpose pp ON pp.code = v.purpose_code)
    SELECT t.* FROM t
     WHERE nullif(p_f->>'status', '') IS NULL OR t.status = upper(p_f->>'status')
$$;
COMMENT ON FUNCTION reporting.master_payments(text, date, date, jsonb) IS
  'V650: the master report''s transactions — reporting.payments for a session and a period (the day confirmed, else generated, in Lagos), filtered by a jsonb the API builds on the server, each with its gateway reference, the refund paid against it, its net amount and its status as the finance engine holds it: SUCCESSFUL (confirmed), PENDING, FAILED (expired unpaid), REVERSED (Interswitch), REFUNDED (refunded in full); only a successful payment''s net amount is revenue';

-- ── 4 · the report's reference and its history, on the official report register (V640) ───────────────────────────────────
ALTER TABLE reporting.official_report DROP CONSTRAINT official_report_reference_check;
ALTER TABLE reporting.official_report ADD CONSTRAINT official_report_reference_check
    CHECK (reference ~ '^DBO/[A-Z]{2,10}/[0-9]{4}/[0-9]{6}$' OR reference ~ '^RPT/[0-9]{4}/[0-9]{6}$');
ALTER TABLE reporting.official_report DROP CONSTRAINT official_report_kind_check;
ALTER TABLE reporting.official_report ADD CONSTRAINT official_report_kind_check
    CHECK (kind IN ('EXAM', 'STUDENT', 'PAYMENT', 'REG', 'COURSE', 'QUERY', 'QUALITY', 'MASTER'));
ALTER TABLE reporting.official_report
    ADD COLUMN status text NOT NULL DEFAULT 'COMPLETED' CHECK (status IN ('GENERATING', 'COMPLETED', 'FAILED', 'CANCELLED')),
    ADD COLUMN formats text[] NOT NULL DEFAULT '{}',
    ADD COLUMN completed_at timestamptz NULL;
COMMENT ON COLUMN reporting.official_report.status IS 'V650: a master report is GENERATING from its reference until the browser has written its PDF and Excel (COMPLETED), or it failed or was cancelled';

CREATE OR REPLACE FUNCTION reporting.issue_report(p_kind text, p_title text, p_filters jsonb, p_scope text, p_figures jsonb, p_rows integer, p_parts jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        y int := extract(year FROM (now() AT TIME ZONE 'Africa/Lagos'))::int; n int; v_ref text;
BEGIN
    IF who IS NULL OR office IS NULL THEN
        RAISE EXCEPTION 'REPORT_PERSON: an official report is issued by a person acting in an office' USING ERRCODE = '42501';
    END IF;
    IF p_kind IS NULL OR p_kind NOT IN ('EXAM', 'STUDENT', 'PAYMENT', 'REG', 'COURSE', 'QUERY', 'QUALITY', 'MASTER') THEN
        RAISE EXCEPTION 'REPORT_KIND: % is not a kind of official report', coalesce(p_kind, 'nothing') USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_title, ''))) < 3 THEN
        RAISE EXCEPTION 'REPORT_TITLE: an official report says what it is' USING ERRCODE = '23514';
    END IF;
    INSERT INTO reporting.report_counter AS c (kind, year, last) VALUES (p_kind, y, 1)
    ON CONFLICT (kind, year) DO UPDATE SET last = c.last + 1
    RETURNING c.last INTO n;
    -- V650: the master report's own series, RPT/YYYY/NNNNNN; every other kind DBO/<KIND>/YYYY/NNNNNN as before
    v_ref := CASE WHEN p_kind = 'MASTER' THEN 'RPT/' || y || '/' || lpad(n::text, 6, '0')
                  ELSE 'DBO/' || p_kind || '/' || y || '/' || lpad(n::text, 6, '0') END;
    INSERT INTO reporting.official_report (reference, kind, title, filters, scope, figures, row_count, parts, generated_by, actor_office, status)
    VALUES (v_ref, p_kind, btrim(p_title), coalesce(p_filters, '{}'::jsonb), p_scope, p_figures, p_rows, p_parts, who, office,
            CASE WHEN p_kind = 'MASTER' THEN 'GENERATING' ELSE 'COMPLETED' END);
    RETURN v_ref;
END $function$;

-- the browser has written the report (or could not): its formats, the rows it carries, the status — by the person who issued it
CREATE FUNCTION reporting.finish_report(p_reference text, p_status text, p_formats text[], p_rows int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; x reporting.official_report;
BEGIN
    SELECT * INTO x FROM reporting.official_report WHERE reference = p_reference FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'REPORT_NOT_FOUND: no report %', p_reference USING ERRCODE = 'P0002'; END IF;
    IF x.generated_by IS DISTINCT FROM who THEN
        RAISE EXCEPTION 'REPORT_PERSON: a report is finished by the person who issued it' USING ERRCODE = '42501';
    END IF;
    IF x.status <> 'GENERATING' THEN
        RAISE EXCEPTION 'REPORT_FINISHED: report % is already %', p_reference, lower(x.status) USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_status, '') NOT IN ('COMPLETED', 'FAILED', 'CANCELLED') THEN
        RAISE EXCEPTION 'REPORT_STATUS: a report is completed, failed or cancelled' USING ERRCODE = '23514';
    END IF;
    UPDATE reporting.official_report
       SET status = p_status, formats = coalesce((SELECT array_agg(DISTINCT upper(f)) FROM unnest(p_formats) f WHERE upper(f) IN ('PDF', 'XLSX')), '{}'),
           row_count = coalesce(p_rows, row_count), completed_at = now()
     WHERE reference = p_reference;
END $$;

COMMIT;

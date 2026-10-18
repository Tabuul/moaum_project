-- V537: the slowest screens on the live portal read their figures in one pass.
--
-- A crawl of every menu page against the live-shaped copy (54,573 students, 13,200 applications; 17–18 Oct 2026, each page loaded
-- twice with nothing else running) found 22 pages over 5 s, the worst well past the 30 s at which CloudFront answers 504 on AWS:
--   /college/payments 29 s · /admissions 38 s · /admissions/putme 37 s · /ict/admission-checking 18 s · the Registrar's overview,
--   the Bursar's dashboard and /audit/revenue 16–19 s · /stats 15 s (its first load) · the Registrar's dashboard 7 s.
-- Each spent its time in a function called once for every row of a large set — finance.payment_position for each of the College's
-- 8,193 students, finance.position for each of 6,233 admitted applicants, a plpgsql eligibility for each of 12,649 Post-UTME
-- applicants (read three times over), finance.final_level twice for each of 54,573 students, a programme-name lookup for each
-- applicant — or in one set planned into another so that it ran once per row (the registration windows inside the check made for
-- every student). On a connection PostgreSQL 18 has served a while — every connection of the portal's pool — such per-row calls
-- cost several times what they cost on a fresh one (finance.fee_sums: 0.6 s, then 4.5 s from its fifth run; the Post-UTME counts:
-- 1.2 s, then 8–9 s from the third), so the screens were slower on the live portal than any single test showed.
--
-- Restated here, each with the same answers (compared row by row on the live-shaped copy, every row the same unless noted):
--   finance.fee_profiles               the final level read once for each programme                      (54,573 rows the same)
--   finance.session_charges            its parts held (MATERIALIZED)                       (109,146 rows the same, two sessions)
--   finance.collection_by_faculty      its parts held                                             ~15 s → 0.6–2.7 s, the same
--   finance.session_positions          its parts held and V454's rule (short by under ₦1 is paid), so it is
--                                      finance.payment_position for every student — 6,000 students × 2 sessions × 3 ways
--                                      of asking compared: every amount, status and count the same; the last reference
--                                      differed only where two payments were confirmed at the same moment, now broken the
--                                      same way in both (finance.session_payments, finance.payment_position)  10 s → 1.4–2.3 s
--   admissions.putme_candidates        admissions.putme_eligibility's rule asked by joins             9 s → 12 ms (13,200 rows the same)
--   admissions.pipeline_stats          the offered held, fees paid in full read for the session      24 s → 1.4 s, the same
--   admissions.status_checking_rows    the programme name's code read once                       4.4 s → 30 ms (12,649 rows the same)
-- The API reads the College payment report from finance.session_positions, the Post-UTME desk's three counts in one read, and the
-- programmes' JAMB and candidate counts grouped (V537 in the API).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'super', true);
SELECT set_config('moaum.reason', 'V537: the slowest screens read their figures in one pass', true);

-- ── the fee profiles: each programme's final level read once ──
CREATE OR REPLACE FUNCTION finance.fee_profiles()
RETURNS TABLE (student_id uuid, status text, programme_code text, faculty_code text, category text,
               current_level int, entry_mode text, state text, is_spill boolean, profile_key text)
LANGUAGE sql STABLE AS $$
    -- V537: each programme's final level read once (456 calls), not twice for every student: on a connection the portal has
    -- used a while, PostgreSQL 18 reads finance.final_level by a cached generic plan that costs about seven times as much a call
    WITH fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr)
    SELECT s.id, s.status, s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
           lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
           coalesce(s.current_level > fl.final AND s.status <> 'GRADUATED', false) AS is_spill,
           concat_ws('|', s.programme_code, s.current_level, s.entry_mode,
                     lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))),
                     coalesce(s.current_level > fl.final AND s.status <> 'GRADUATED', false)) AS profile_key
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN fl ON fl.code = s.programme_code
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
$$;


-- ── the session's charges: the windows, the payments in time, the profiles and their sums each read once and held ──
CREATE OR REPLACE FUNCTION finance.session_charges(p_session text)
 RETURNS TABLE(student_id uuid, fee numeric, late_payment boolean, late_registration boolean, total numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS MATERIALIZED (SELECT * FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL)),
    -- V537: read once, not inside the check made for every student
    reg_windows AS MATERIALIZED (
        SELECT sem, rw.phase, rw.closes_at
          FROM generate_series(1, 3) sem
          CROSS JOIN LATERAL policy.window_state('COURSE_REGISTRATION', p_session, sem) rw
         WHERE rw.configured AND rw.late_fee_enabled),
    paid_in_time AS MATERIALIZED (
        SELECT r.student_id, sum(r.amount) AS total
          FROM finance.payment_reference r CROSS JOIN w
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
           AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)
         GROUP BY r.student_id),
    prof AS MATERIALIZED (SELECT fp.student_id, fp.profile_key FROM finance.fee_profiles() fp),
    sums AS MATERIALIZED (SELECT x.profile_key, x.fee, x.late_payment, x.late_registration FROM finance.fee_sums(p_session, NULL) x),
    each AS (
        SELECT pr.student_id, coalesce(s.fee, 0) AS fee, coalesce(s.late_payment, 0) AS lp, coalesce(s.late_registration, 0) AS lr,
               (SELECT w.late_fee_enabled AND w.phase = 'LATE' FROM w) AND coalesce(pit.total, 0) < coalesce(s.fee, 0) AS late_payment,
               EXISTS (
                   SELECT 1 FROM reg_windows rw
                    WHERE (rw.phase = 'LATE' AND NOT EXISTS (
                               SELECT 1 FROM registration.course_registration cr
                                WHERE cr.student_id = pr.student_id AND cr.session = p_session AND cr.semester = rw.sem
                                  AND cr.submitted_at IS NOT NULL AND (rw.closes_at IS NULL OR cr.submitted_at <= rw.closes_at))
                          OR EXISTS (
                               SELECT 1 FROM registration.course_registration cr
                                WHERE cr.student_id = pr.student_id AND cr.session = p_session AND cr.semester = rw.sem
                                  AND cr.submitted_at IS NOT NULL AND rw.closes_at IS NOT NULL AND cr.submitted_at > rw.closes_at))) AS late_registration
          FROM prof pr
          LEFT JOIN sums s ON s.profile_key = pr.profile_key
          LEFT JOIN paid_in_time pit ON pit.student_id = pr.student_id)
    SELECT e.student_id, e.fee, coalesce(e.late_payment, false), e.late_registration,
           e.fee + CASE WHEN coalesce(e.late_payment, false) THEN e.lp ELSE 0 END + CASE WHEN e.late_registration THEN e.lr ELSE 0 END
      FROM each e
$function$;


-- ── the collection by faculty: the enrolled, the paid and the charged each read once and held ──
CREATE OR REPLACE FUNCTION finance.collection_by_faculty(p_session text)
 RETURNS TABLE(faculty_code text, faculty_name text, students bigint, paid_students bigint, collected numeric, due numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH enrolled AS MATERIALIZED (
        SELECT s.id, p.faculty_code FROM people.enrolment e JOIN people.student s ON s.id = e.student_id JOIN ref.programme p ON p.code = s.programme_code
         WHERE e.session = p_session),
    paid AS MATERIALIZED (
        SELECT r.student_id, sum(r.amount) AS amount FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%' GROUP BY r.student_id),
    -- V537: each read once and held, not planned into one another (the session's charges are read for every student)
    charged AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c)
    SELECT f.code, f.name, count(en.id), count(pd.student_id), coalesce(sum(pd.amount), 0), coalesce(sum(coalesce(ch.total, 0)), 0)
      FROM ref.faculty f LEFT JOIN enrolled en ON en.faculty_code = f.code LEFT JOIN paid pd ON pd.student_id = en.id
      LEFT JOIN charged ch ON ch.student_id = en.id
     GROUP BY f.code, f.name HAVING count(en.id) > 0 ORDER BY f.name
$function$;


-- ── the session's payments: of two confirmed at the same moment, the later reference is the last (as finance.payment_position reads it) ──
CREATE OR REPLACE FUNCTION finance.session_payments(p_session text)
 RETURNS TABLE(student_id uuid, total numeric, n integer, last_paid_at timestamp with time zone, last_reference text, last_channel text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH p AS (
        SELECT r.student_id, r.amount, r.confirmed_at, r.reference, r.channel
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'),
    agg AS (SELECT p.student_id, sum(p.amount) AS total, count(*)::int AS n FROM p GROUP BY p.student_id),
    last AS (SELECT DISTINCT ON (p.student_id) p.student_id, p.confirmed_at, p.reference, p.channel FROM p ORDER BY p.student_id, p.confirmed_at DESC, p.reference DESC)
    SELECT agg.student_id, agg.total, agg.n, last.confirmed_at, last.reference, last.channel
      FROM agg JOIN last ON last.student_id = agg.student_id
$function$;


-- ── a student's payment position: the same tie broken the same way ──
CREATE OR REPLACE FUNCTION finance.payment_position(p_student uuid, p_session text, p_semester integer)
 RETURNS TABLE(payable numeric, paid numeric, outstanding numeric, status text, last_paid_at timestamp with time zone, last_reference text, last_channel text, payments integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH due AS (
        SELECT finance.due_for_semester(p_student, p_session, 3) AS total,
               CASE WHEN p_semester IS NULL OR p_semester <= 1 THEN 0 ELSE finance.due_for_semester(p_student, p_session, p_semester - 1) END AS before,
               CASE WHEN p_semester IS NULL THEN finance.due_for_semester(p_student, p_session, 3) ELSE finance.due_for_semester(p_student, p_session, p_semester) END AS upto
    ),
    pay AS (
        SELECT coalesce(sum(r.amount), 0) AS total, count(*)::int AS n
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
    ),
    last AS (
        SELECT r.confirmed_at, r.reference, r.channel
          FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
         ORDER BY r.confirmed_at DESC, r.reference DESC LIMIT 1   -- V537: of two confirmed at once, the later reference
    ),
    pos AS (
        SELECT greatest(due.upto - due.before, 0) AS payable,
               -- the session's payments cover the earlier semesters first; what is left applies to this one
               least(greatest(pay.total - due.before, 0), greatest(due.upto - due.before, 0)) AS applied,
               pay.total AS paid_all, pay.n
          FROM due, pay
    )
    SELECT pos.payable,
           CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END,
           finance.fee_owed(pos.payable, CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END),
           CASE WHEN pos.payable = 0 THEN 'NO_CHARGE'
                WHEN NOT finance.fee_short(pos.payable, CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) THEN 'FULLY_PAID'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) > 0 THEN 'PART_PAYMENT'
                ELSE 'NOT_PAID' END,
           last.confirmed_at, last.reference, last.channel, pos.n
      FROM pos LEFT JOIN last ON true;
$function$;


-- ── every student's payment position at once: the profiles, sums and payments held, and V454's under-one-naira rule, so it is finance.payment_position for every student ──
CREATE OR REPLACE FUNCTION finance.session_positions(p_session text, p_semester int)
RETURNS TABLE (student_id uuid, payable numeric, paid numeric, outstanding numeric, status text,
               last_paid_at timestamptz, last_reference text, last_channel text, payments int, cleared_upto boolean)
LANGUAGE sql STABLE AS $$
    WITH prof AS MATERIALIZED (SELECT fp.student_id, fp.profile_key FROM finance.fee_profiles() fp),
    sums AS MATERIALIZED (SELECT s.profile_key, s.due_before, s.due_upto FROM finance.fee_sums(p_session, p_semester) s),
    pay AS MATERIALIZED (SELECT p.* FROM finance.session_payments(p_session) p),
    pos AS (
        SELECT pr.student_id,
               greatest(coalesce(s.due_upto, 0) - coalesce(s.due_before, 0), 0) AS payable,
               least(greatest(coalesce(pay.total, 0) - coalesce(s.due_before, 0), 0),
                     greatest(coalesce(s.due_upto, 0) - coalesce(s.due_before, 0), 0)) AS applied,
               coalesce(pay.total, 0) AS paid_all, coalesce(pay.n, 0) AS n,
               coalesce(s.due_upto, 0) AS upto,
               pay.last_paid_at, pay.last_reference, pay.last_channel
          FROM prof pr
          LEFT JOIN sums s ON s.profile_key = pr.profile_key
          LEFT JOIN pay ON pay.student_id = pr.student_id),
    judged AS (SELECT pos.*, CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END AS paid_now FROM pos)
    SELECT j.student_id, j.payable, j.paid_now,
           finance.fee_owed(j.payable, j.paid_now),
           CASE WHEN j.payable = 0 THEN 'NO_CHARGE'
                WHEN NOT finance.fee_short(j.payable, j.paid_now) THEN 'FULLY_PAID'
                WHEN j.paid_now > 0 THEN 'PART_PAYMENT'
                ELSE 'NOT_PAID' END,
           j.last_paid_at, j.last_reference, j.last_channel, j.n,
           NOT finance.fee_short(j.upto, j.paid_all)
      FROM judged j
$$;


-- ── the Post-UTME candidates: where each stands read by joins in one pass ──
-- the session's applicants with where each stands for the Post-UTME, read in one pass: the rule of admissions.putme_eligibility,
-- asked of every application at once by joins (V537), not by the function once per application
CREATE OR REPLACE FUNCTION admissions.putme_candidates(p_session text)
RETURNS TABLE (
    application_id uuid, application_no text, surname text, other_names text, jamb_reg_no text, utme int, entry_mode text,
    programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text,
    fee_confirmed_at timestamptz, submitted_at timestamptz, status text, why text, schedule_review boolean, putme_token text,
    batch_id uuid, batch text, held_on date, starts_at time, ends_at time, centre text, room text, seat text, workstation text,
    attendance text, exam_status text, checked_in_at timestamptz, screening_score numeric, score_released_at timestamptz
)
LANGUAGE sql STABLE AS $$
    WITH screened AS MATERIALIZED (SELECT DISTINCT e.programme_code FROM admissions.screening_exam_programme e WHERE e.session = p_session),
    any_screened AS (SELECT EXISTS (SELECT 1 FROM screened) AS yes),
    named AS MATERIALIZED (   -- the programme a candidate's programme name is, as admissions.putme_programme_code reads it
        SELECT DISTINCT ON (pp.name) pp.name, pp.code FROM ref.programme pp ORDER BY pp.name, pp.archived, pp.code),
    earlier AS MATERIALIZED (
        SELECT x.application_id, true AS seated_before, bool_or(x.reason LIKE 'POSTPONED%') AS postponed
          FROM admissions.screening_assignment x JOIN admissions.application ap ON ap.id = x.application_id
         WHERE x.state <> 'ACTIVE' AND ap.session = p_session GROUP BY x.application_id),
    base AS (
        SELECT a.id, a.application_no, a.session, a.fee_confirmed_at, a.submitted_at, a.schedule_review, a.putme_token, a.screening_batch_id,
               a.seat, a.screening_score, a.score_released_at, c.surname, c.other_names, c.jamb_reg_no, c.entry_mode, c.programme AS programme_name, c.offer_state, r.aggregate,
               nm.code AS named_code, sc.programme_code IS NOT NULL AS screened, ax.yes AS any_screened,
               sa.id AS sa_id, sa.attendance, sa.exam_status, sa.remarks, sa.checked_in_at, sa.workstation_id,
               coalesce(er.seated_before, false) AS seated_before, coalesce(er.postponed, false) AS postponed
          FROM admissions.application a
          JOIN admissions.candidate c ON c.id = a.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN named nm ON nm.name = c.programme
          LEFT JOIN screened sc ON sc.programme_code = nm.code
          CROSS JOIN any_screened ax
          LEFT JOIN admissions.screening_assignment sa ON sa.application_id = a.id AND sa.state = 'ACTIVE'
          LEFT JOIN earlier er ON er.application_id = a.id
         WHERE a.session = p_session),
    judged AS (
        SELECT b.*,
               CASE WHEN b.offer_state IN ('WITHDRAWN', 'DECLINED', 'LAPSED') THEN 1
                    WHEN b.any_screened AND NOT b.screened THEN 2
                    WHEN NOT b.any_screened THEN 3
                    WHEN b.sa_id IS NOT NULL AND b.attendance = 'DISQUALIFIED' THEN 4
                    WHEN b.screening_score IS NOT NULL OR (b.sa_id IS NOT NULL AND b.exam_status = 'COMPLETED') THEN 5
                    WHEN b.sa_id IS NOT NULL AND b.attendance = 'ABSENT' THEN 6
                    WHEN b.sa_id IS NOT NULL AND b.seated_before THEN 7
                    WHEN b.sa_id IS NOT NULL THEN 8
                    WHEN b.fee_confirmed_at IS NULL THEN 9
                    WHEN b.submitted_at IS NULL THEN 10
                    WHEN b.postponed THEN 11
                    ELSE 12 END AS k
          FROM base b)
    SELECT j.id, j.application_no, j.surname, j.other_names, j.jamb_reg_no, j.aggregate, j.entry_mode,
           p.code, coalesce(p.name, j.programme_name), d.code, d.name, f.code, f.name,
           j.fee_confirmed_at, j.submitted_at,
           (ARRAY['NOT_ELIGIBLE', 'NOT_ELIGIBLE', 'NOT_ELIGIBLE', 'DISQUALIFIED', 'EXAM_COMPLETED', 'ABSENT', 'RESCHEDULED', 'SCHEDULED',
                  'PAYMENT_PENDING', 'DOCUMENT_PENDING', 'RESCHEDULE_REQUIRED', 'READY_FOR_SCHEDULING'])[j.k],
           CASE j.k WHEN 1 THEN 'The candidate is ' || lower(j.offer_state)
                    WHEN 2 THEN 'The programme is not screened by the Post-UTME examination this session'
                    WHEN 3 THEN 'No programme is named as screened by examination for ' || j.session || ' yet'
                    WHEN 4 THEN coalesce(j.remarks, 'Disqualified at the examination')
                    WHEN 5 THEN 'The examination has been sat'
                    WHEN 6 THEN 'Marked absent from the examination'
                    WHEN 7 THEN 'Seated again after an earlier seating'
                    WHEN 8 THEN 'Seated in a batch'
                    WHEN 9 THEN 'The screening fee is not confirmed'
                    WHEN 10 THEN 'The application is not yet submitted'
                    WHEN 11 THEN 'The batch was postponed; a new seating is needed'
                    ELSE 'Submitted, paid, programme screened by examination' END,
           j.schedule_review, j.putme_token,
           b.id, b.label, b.held_on, b.starts_at, b.ends_at, coalesce(cc.name, b.venue), cr.name, j.seat, w.label,
           coalesce(j.attendance, 'NOT_CHECKED_IN'), coalesce(j.exam_status, 'NOT_STARTED'), j.checked_in_at, j.screening_score, j.score_released_at
      FROM judged j
      LEFT JOIN ref.programme p ON p.code = j.named_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN admissions.screening_batch b ON b.id = j.screening_batch_id
      LEFT JOIN admissions.cbt_centre cc ON cc.id = b.centre_id
      LEFT JOIN admissions.cbt_room cr ON cr.id = b.room_id
      LEFT JOIN admissions.cbt_workstation w ON w.id = j.workstation_id
$$;


-- ── the admissions pipeline: the offered applicants held, and the fees paid in full read for the session at once ──
CREATE OR REPLACE FUNCTION admissions.pipeline_stats(p_session text)
 RETURNS TABLE(jamb_uploaded bigint, matched bigint, unmatched bigint, admitted bigint, acceptance_pending bigint, acceptance_paid bigint, screening_pending bigint, screening_submitted bigint, screening_successful bigint, screening_unsuccessful bigint, screening_returned bigint, change_requested bigint, change_approved bigint, fees_paid bigint, registered bigint, ready_for_matric bigint, matriculated bigint)
 LANGUAGE sql
 STABLE
AS $function$

    WITH offered AS MATERIALIZED (
        SELECT a.id, a.candidate_id, a.session, a.accepted_at, (SELECT e.paid FROM admissions.acceptance_entitlement(a.id) e) AS acc_paid, f.state AS scr,
               s.id AS student_id, s.matric_no,
               s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED')) AS reg
          FROM admissions.application a
          LEFT JOIN admissions.screening_form f ON f.application_id = a.id
          LEFT JOIN people.student s ON s.candidate_id = a.candidate_id
         WHERE a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL),
    -- V537: the school fees paid in full read for the session at once — finance.position's test (nothing due, or short by under one
    -- naira) on the session's charges and payments — not finance.position once for every admitted student (24 s on the live-shaped copy)
    fees AS MATERIALIZED (
        SELECT c.student_id, c.total = 0 OR NOT finance.fee_short(c.total, coalesce(pay.total, 0)) AS paid_in_full
          FROM finance.session_charges(p_session) c
          LEFT JOIN finance.session_payments(p_session) pay ON pay.student_id = c.student_id),
    apps AS MATERIALIZED (
        SELECT o.*, coalesce(fe.paid_in_full, false) AS paid
          FROM offered o LEFT JOIN fees fe ON fe.student_id = o.student_id)

    SELECT (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session),

           (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session AND j.matched),

           (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session AND NOT j.matched),

           count(*), count(*) FILTER (WHERE accepted_at IS NULL), count(*) FILTER (WHERE acc_paid),

           count(*) FILTER (WHERE accepted_at IS NOT NULL AND (scr IS NULL OR scr = 'PENDING') AND admissions.screening_required(id)),

           count(*) FILTER (WHERE scr = 'IN_REVIEW'), count(*) FILTER (WHERE scr = 'SUCCESSFUL'), count(*) FILTER (WHERE scr = 'UNSUCCESSFUL'), count(*) FILTER (WHERE scr = 'CORRECTION_REQUIRED'),

           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'REQUESTED'),

           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'APPROVED'),

           count(*) FILTER (WHERE paid), count(*) FILTER (WHERE reg),

           count(*) FILTER (WHERE paid AND reg AND matric_no IS NULL AND admissions.screening_ok(id)), count(*) FILTER (WHERE matric_no IS NOT NULL)

      FROM apps;

$function$;


-- ── the admission status checking rows: each programme name's code read once ──
CREATE OR REPLACE FUNCTION admissions.status_checking_rows(p_session text, p_cce boolean)
 RETURNS TABLE(application_id uuid, application_no text, jamb_reg_no text, name text, sex text, programme text, programme_code text, faculty_code text, faculty text, dept_code text, department text, valid boolean, paid boolean, paid_at timestamp with time zone, reference text, amount numeric, checked boolean, checks bigint, first_checked_at timestamp with time zone, last_checked_at timestamp with time zone, last_result text, result text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V537: each programme name's code read once (as admissions.programme_code_of reads it), not by that function for every applicant
    WITH named AS MATERIALIZED (SELECT DISTINCT ON (pp.name) pp.name, pp.code FROM ref.programme pp ORDER BY pp.name, pp.archived, pp.code)
    SELECT a.id, a.application_no, c.jamb_reg_no, c.surname || ', ' || c.other_names, r.sex, c.programme, p.code,
           p.faculty_code, fa.name, p.dept_code, d.name,
           (a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL),
           (a.checking_confirmed_at IS NOT NULL OR ck.confirmed_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL),
           coalesce(a.checking_confirmed_at, ck.confirmed_at), ck.reference, ck.amount,
           (k.n > 0 OR a.status_checked_at IS NOT NULL), k.n, coalesce(k.first_at, a.status_checked_at), coalesce(k.last_at, a.status_checked_at), k.last_result,
           CASE WHEN a.decision_released_at IS NULL OR a.decision IS NULL THEN 'PENDING'
                WHEN a.decision = 'OFFERED' THEN 'ADMITTED' WHEN a.decision = 'WAITING' THEN 'WAITING_LIST' ELSE 'NOT_ADMITTED' END
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
      LEFT JOIN named nm ON nm.name = c.programme
      LEFT JOIN ref.programme p ON p.code = nm.code
      LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN LATERAL (SELECT x.reference, x.amount, x.confirmed_at FROM admissions.fee_reference x
                          WHERE x.application_id = a.id AND x.kind = 'CHECKING' AND x.confirmed_at IS NOT NULL ORDER BY x.confirmed_at LIMIT 1) ck ON true
      LEFT JOIN LATERAL (SELECT count(*) AS n, min(s.checked_at) AS first_at, max(s.checked_at) AS last_at,
                                (array_agg(s.result ORDER BY s.checked_at DESC))[1] AS last_result
                           FROM admissions.status_check s WHERE s.application_id = a.id) k ON true
     WHERE a.session = p_session
       -- V412: the CCE applicants apart from the rest (their checking is not the ICT window's); V446: Preliminary Science has none
       AND (coalesce(c.entry_mode, '') = 'CCE') = coalesce(p_cce, false)
       AND coalesce(c.entry_mode, '') <> 'PRELIMINARY'
$function$;

COMMIT;

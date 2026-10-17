-- V524: the registrations made without the semester's fees cleared, read once for each fee profile.
--
-- finance.registrations_without_fees (V362) asked finance.semester_cleared, finance.fee_stated and finance.due_for_semester of every
-- registration of the session in turn: 4,398 registrations of 2025/2026 on the live-shaped copy, 7.4 s, each call a SQL function
-- whose plan PostgreSQL 18 caches and, after some thousands of calls, settles slower (as V515 found for the examination cards).
--
-- What the fee schedule says of a student depends only on the student's fee profile: the programme (and so its faculty, the faculty
-- it is charged as and its category), the level, the entry mode, the state of origin and whether the student is a spillover — the
-- profile finance.fee_profiles() names and finance.fee_sums() reads. So the schedule's answers (stated, the semesters not stated,
-- the semester's cumulative due) are now asked once of one student of each profile among the registered (335 profiles for 4,398
-- registrations) with the very same functions, and each registration's own confirmed school-fee payments are summed once. The
-- semester is cleared exactly as finance.semester_cleared decides it: stated, not short of the semester's due by a naira or more
-- (V454), and not an open semester whose own fees are not stated while another's are (V461). The list is the same row for row.
--
-- A student with no fee profile (no programme on ref.programme) is its own profile.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.reason', 'V524: the unpaid registrations read once for each fee profile', true);

CREATE OR REPLACE FUNCTION finance.registrations_without_fees(p_session text)
 RETURNS TABLE(registration_id uuid, student_id uuid, number text, name text, programme text, faculty text, level integer, semester integer, status text, submitted_at timestamp with time zone, approved_at timestamp with time zone, stated boolean, due numeric, paid numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH reg AS MATERIALIZED (
        SELECT r.id, r.student_id, r.session, r.level, r.semester, r.status, r.submitted_at, r.approved_at
          FROM registration.course_registration r
         WHERE r.session = p_session AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    -- V524: the fee profile of each registered student (what the schedule's answers depend on)
    prof AS MATERIALIZED (
        SELECT DISTINCT r.student_id,
               CASE WHEN fp.student_id IS NULL THEN r.student_id::text
                    ELSE row(fp.programme_code, fp.current_level, fp.entry_mode, fp.state, fp.is_spill)::text END AS k
          FROM reg r LEFT JOIN finance.fee_profiles() fp ON fp.student_id = r.student_id),
    rep AS MATERIALIZED (SELECT DISTINCT ON (p.k) p.k, p.student_id FROM prof p ORDER BY p.k, p.student_id),
    said AS MATERIALIZED (
        SELECT rp.k, finance.fee_stated(rp.student_id, p_session) AS stated,
               finance.fee_unstated_semesters(rp.student_id, p_session) AS unstated
          FROM rep rp),
    owed AS MATERIALIZED (
        SELECT ks.k, ks.semester, finance.due_for_semester(rp.student_id, p_session, ks.semester) AS due
          FROM (SELECT DISTINCT p.k, r.semester FROM reg r JOIN prof p ON p.student_id = r.student_id) ks
          JOIN rep rp ON rp.k = ks.k),
    paid AS MATERIALIZED (
        SELECT pr.student_id, sum(pr.amount) AS paid
          FROM finance.payment_reference pr
         WHERE pr.session = p_session AND pr.confirmed_at IS NOT NULL AND pr.purpose LIKE 'School fees%'
           AND pr.student_id IN (SELECT p.student_id FROM prof p)
         GROUP BY pr.student_id),
    open_ AS (SELECT coalesce(array_agg(sm.number), '{}'::int[]) AS n FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN')
    SELECT r.id, s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, p.name, f.name, r.level, r.semester,
           r.status, r.submitted_at, r.approved_at, sd.stated,
           CASE WHEN sd.stated THEN ow.due END,
           coalesce(pd.paid, 0)
      FROM reg r
      JOIN people.student s ON s.id = r.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      JOIN prof pf ON pf.student_id = r.student_id
      JOIN said sd ON sd.k = pf.k
      JOIN owed ow ON ow.k = pf.k AND ow.semester = r.semester
      LEFT JOIN paid pd ON pd.student_id = r.student_id
      CROSS JOIN open_ o
     -- not cleared, as finance.semester_cleared decides it
     WHERE NOT (sd.stated
                AND NOT finance.fee_short(ow.due, coalesce(pd.paid, 0))
                AND NOT (r.semester = ANY (o.n) AND r.semester = ANY (sd.unstated)))
     ORDER BY f.name, p.name, s.surname, s.other_names, r.semester
$function$;

COMMIT;

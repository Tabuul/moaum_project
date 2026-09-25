-- ═══════════════════════════════════════════════════════════════════════════
-- V256 · The student payment position, by session or by semester
--
--   The Finance Controller of the College of Health Sciences asked (letter of
--   21 September 2026) for a Student Payment Report: each student's amount
--   payable, amount paid, amount outstanding, payment status and last payment,
--   searchable and filterable, with totals, exported to Excel and PDF.
--
--   The register already holds all of it — the fee schedule, the confirmed
--   payment references, the semester split the College registers on. What was
--   missing is one function that answers the position for a period: the whole
--   session, or one semester, with payments applied to the first semester's
--   charge before the second's, as finance.semester_cleared already reads them.
--   Nothing here charges or confirms anything; it reads.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.payment_position(p_student uuid, p_session text, p_semester int)
RETURNS TABLE (payable numeric, paid numeric, outstanding numeric, status text, last_paid_at timestamptz, last_reference text, last_channel text, payments int)
LANGUAGE sql STABLE AS $$
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
         ORDER BY r.confirmed_at DESC LIMIT 1
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
           greatest(pos.payable - CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END, 0),
           CASE WHEN pos.payable = 0 THEN 'NO_CHARGE'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) >= pos.payable THEN 'FULLY_PAID'
                WHEN (CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END) > 0 THEN 'PART_PAYMENT'
                ELSE 'NOT_PAID' END,
           last.confirmed_at, last.reference, last.channel, pos.n
      FROM pos LEFT JOIN last ON true;
$$;

COMMENT ON FUNCTION finance.payment_position(uuid, text, int) IS
  'A student''s school-fee position for a session (semester NULL) or one semester of it: payable, paid, '
  'outstanding, status (FULLY_PAID, PART_PAYMENT, NOT_PAID, NO_CHARGE) and the last confirmed payment. '
  'Payments apply to the earlier semester''s charge first, as registration reads them.';

COMMIT;

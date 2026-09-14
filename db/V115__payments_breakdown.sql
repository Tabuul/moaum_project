-- ═══════════════════════════════════════════════════════════════════════════
-- V115 — the payments query, broken down
--
--   Alongside the list (V112), the Bursary sees the same filtered set summed by
--   payment category and by faculty. The totals are over the WHOLE match, not
--   the page shown. Same filters as finance.payments_query; read-only.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.payments_breakdown(
        p_session text DEFAULT NULL, p_faculty text DEFAULT NULL, p_dept text DEFAULT NULL,
        p_programme text DEFAULT NULL, p_level int DEFAULT NULL, p_category text DEFAULT NULL,
        p_channel text DEFAULT NULL, p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS TABLE (dim text, label text, cnt bigint, total numeric)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT r.amount, finance.payment_category(r.purpose) AS category, f.name AS faculty
          FROM finance.payment_reference r
          JOIN people.student s ON s.id = r.student_id
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = p.faculty_code
         WHERE r.confirmed_at IS NOT NULL
           AND (p_session   IS NULL OR r.session = p_session)
           AND (p_faculty   IS NULL OR f.code = p_faculty)
           AND (p_dept      IS NULL OR d.code = p_dept)
           AND (p_programme IS NULL OR p.code = p_programme)
           AND (p_level     IS NULL OR s.current_level = p_level)
           AND (p_channel   IS NULL OR r.channel = p_channel)
           AND (p_category  IS NULL OR finance.payment_category(r.purpose) = p_category)
           AND (p_from      IS NULL OR r.confirmed_at::date >= p_from)
           AND (p_to        IS NULL OR r.confirmed_at::date <= p_to))
    SELECT 'category', category, count(*), coalesce(sum(amount), 0) FROM base GROUP BY category
    UNION ALL
    SELECT 'faculty', faculty, count(*), coalesce(sum(amount), 0) FROM base GROUP BY faculty
    ORDER BY 1, 4 DESC
$$;

COMMENT ON FUNCTION finance.payments_breakdown(text, text, text, text, int, text, text, date, date) IS
  'The payments query summed by category and by faculty over the whole filtered set (not the page).';

COMMIT;

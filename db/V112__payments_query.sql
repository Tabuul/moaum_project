-- ═══════════════════════════════════════════════════════════════════════════
-- V112 — a well-defined payments query for the Bursary
--
--   The day book (V037) lists confirmed payments by date. This adds a query the
--   Bursary can slice by the academic dimensions of the payer: session, faculty,
--   department, programme, level, the payment's category and its channel — newest
--   first. It is over confirmed student payments (finance.payment_reference joined
--   to the register), which is what carries a faculty and a level; applicant
--   application/acceptance fees keep to the day book. The full-match count and
--   total ride on each row through a window, so one call fills the header too.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.payment_category(p_purpose text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_purpose IS NULL THEN 'Other'
        WHEN p_purpose ILIKE '%school fee%' OR p_purpose ILIKE '%tuition%' THEN 'School fees'
        WHEN p_purpose ILIKE '%accept%' THEN 'Acceptance fee'
        WHEN p_purpose ILIKE '%applicat%' THEN 'Application fee'
        WHEN p_purpose ILIKE '%hostel%' OR p_purpose ILIKE '%accommodation%' THEN 'Hostel'
        WHEN p_purpose ILIKE '%transcript%' THEN 'Transcript'
        WHEN p_purpose ILIKE '%portal%' OR p_purpose ILIKE '%ict%' THEN 'Portal and ICT charge'
        WHEN p_purpose ILIKE '%id %' OR p_purpose ILIKE '%identity%' OR p_purpose ILIKE '%card%' THEN 'Identity card'
        WHEN p_purpose ILIKE '%transfer%' THEN 'Transfer fee'
        ELSE 'Other' END
$$;

CREATE OR REPLACE FUNCTION finance.payments_query(
        p_session text DEFAULT NULL, p_faculty text DEFAULT NULL, p_dept text DEFAULT NULL,
        p_programme text DEFAULT NULL, p_level int DEFAULT NULL, p_category text DEFAULT NULL,
        p_channel text DEFAULT NULL, p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_limit int DEFAULT 500)
RETURNS TABLE (reference text, confirmed_at timestamptz, payer text, number text, programme_code text,
               programme text, dept_code text, dept text, faculty_code text, faculty text, level int,
               purpose text, category text, channel text, amount numeric, receipt_no text, session text,
               match_count bigint, match_total numeric)
LANGUAGE sql STABLE AS $$
    SELECT r.reference, r.confirmed_at,
           s.surname || ', ' || s.other_names AS payer,
           coalesce(s.matric_no, s.admission_no) AS number,
           p.code, p.name, d.code, d.name, f.code, f.name, s.current_level,
           r.purpose, finance.payment_category(r.purpose), r.channel, r.amount, r.receipt_no, r.session,
           count(*) OVER () AS match_count, coalesce(sum(r.amount) OVER (), 0) AS match_total
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
       AND (p_to        IS NULL OR r.confirmed_at::date <= p_to)
     ORDER BY r.confirmed_at DESC
     LIMIT greatest(1, least(coalesce(p_limit, 500), 2000))
$$;

COMMENT ON FUNCTION finance.payments_query(text, text, text, text, int, text, text, date, date, int) IS
  'Confirmed student payments, newest first, sliced by session/faculty/department/programme/level/category/channel; '
  'match_count and match_total (window over the whole filtered set) give the header even though rows are limited.';

COMMIT;

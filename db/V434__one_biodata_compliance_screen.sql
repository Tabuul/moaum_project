-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V434 — one biodata compliance screen
--
--   Two screens had grown for the same question: Biodata compliance under Portal Management (V423: the ICT Director's
--   switch, the required items and their impact, the exceptions, counting every student live) and the offices' Biodata
--   compliance (V426: the four statuses, the data quality and the students behind each count, from the quarter-hourly
--   reading people.biodata_status_snapshot). Four offices saw both in their menus, and the two could show different
--   counts for the same students. They are now one screen reading one calculation — the reading — and these are the two
--   things the reading still had to answer:
--
--   1. people.biodata_status_list takes the missing item and the sex as filters as well, so "the students missing their
--      next of kin's phone" is a list, not a count. The V426 form (eleven arguments) is kept and calls the new one.
--   2. people.biodata_missing_items and people.biodata_compliance_units — how many students miss each required item, and
--      the counts by faculty (or by department within a faculty) — from the same reading, within the office's bound.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION people.biodata_status_list(p_status text, p_faculty text, p_department text, p_programme text, p_level int, p_session text,
                                                      p_entry_mode text, p_migrated boolean, p_q text, p_limit int, p_offset int,
                                                      p_missing text, p_sex text)
RETURNS TABLE(student_id uuid, matric_no text, jamb_reg_no text, surname text, other_names text, faculty text, department text, programme text,
              level int, entry_session text, status text, email text, phone text, missing_labels text[], last_updated timestamptz,
              confirmed_at timestamptz, last_reminded_at timestamptz, total bigint)
LANGUAGE sql STABLE AS $$
    SELECT s.id, s.matric_no, s.jamb_reg_no, s.surname, s.other_names, f.name, d.name, p.name, s.current_level, s.entry_session,
           x.status, x.email, x.phone, x.missing_labels, x.last_updated, x.confirmed_at, x.last_reminded_at, count(*) OVER ()
      FROM people.biodata_status_snapshot x
      JOIN people.student s ON s.id = x.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE (p_status IS NULL OR x.status = p_status)
       AND (p_migrated IS NULL OR x.migrated = p_migrated)
       AND (p_faculty IS NULL OR p.faculty_code = p_faculty)
       AND (p_department IS NULL OR p.dept_code = p_department)
       AND (p_programme IS NULL OR s.programme_code = p_programme)
       AND (p_level IS NULL OR s.current_level = p_level)
       AND (p_session IS NULL OR s.entry_session = p_session)
       AND (p_entry_mode IS NULL OR s.entry_mode = p_entry_mode)
       AND (p_missing IS NULL OR p_missing = ANY (x.missing))
       AND (p_sex IS NULL OR s.sex = p_sex)
       AND (p_q IS NULL OR btrim(p_q) = '' OR s.surname ILIKE '%' || btrim(p_q) || '%' OR s.other_names ILIKE '%' || btrim(p_q) || '%'
            OR coalesce(s.matric_no, '') ILIKE '%' || btrim(p_q) || '%' OR coalesce(s.jamb_reg_no, '') ILIKE '%' || btrim(p_q) || '%'
            OR coalesce(s.admission_no, '') ILIKE '%' || btrim(p_q) || '%'
            OR coalesce(x.email, '') ILIKE '%' || btrim(p_q) || '%' OR coalesce(x.phone, '') ILIKE '%' || btrim(p_q) || '%')
     ORDER BY s.surname, s.other_names, s.id
     LIMIT greatest(1, p_limit) OFFSET greatest(0, p_offset)
$$;
COMMENT ON FUNCTION people.biodata_status_list(text, text, text, text, int, text, text, boolean, text, int, int, text, text) IS
  'V434: the students behind a compliance count, from the latest reading — filtered by status, faculty, department, programme, level, entry session, entry mode, came-over, the required item missing and the sex, and searched by name, number, e-mail or phone; paged, with the total.';

-- the V426 form, kept for its callers
CREATE OR REPLACE FUNCTION people.biodata_status_list(p_status text, p_faculty text, p_department text, p_programme text, p_level int, p_session text,
                                                      p_entry_mode text, p_migrated boolean, p_q text, p_limit int, p_offset int)
RETURNS TABLE(student_id uuid, matric_no text, jamb_reg_no text, surname text, other_names text, faculty text, department text, programme text,
              level int, entry_session text, status text, email text, phone text, missing_labels text[], last_updated timestamptz,
              confirmed_at timestamptz, last_reminded_at timestamptz, total bigint)
LANGUAGE sql STABLE AS $$
    SELECT * FROM people.biodata_status_list(p_status, p_faculty, p_department, p_programme, p_level, p_session, p_entry_mode, p_migrated, p_q,
                                             p_limit, p_offset, NULL::text, NULL::text)
$$;

-- how many students on the register miss each required item, within a faculty or department when given
CREATE OR REPLACE FUNCTION people.biodata_missing_items(p_faculty text DEFAULT NULL, p_department text DEFAULT NULL)
RETURNS TABLE(item text, label text, students int)
LANGUAGE sql STABLE AS $$
    SELECT m.item, min(m.label), count(*)::int
      FROM people.biodata_status_snapshot x
      JOIN people.student s ON s.id = x.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
     CROSS JOIN LATERAL unnest(x.missing, x.missing_labels) AS m(item, label)
     WHERE (p_faculty IS NULL OR p.faculty_code = p_faculty)
       AND (p_department IS NULL OR p.dept_code = p_department)
     GROUP BY m.item
     ORDER BY count(*) DESC, m.item
$$;
COMMENT ON FUNCTION people.biodata_missing_items(text, text) IS
  'V434: from the latest reading, how many students miss each required item (within a faculty or department when given).';

-- the counts by faculty, or by department within a faculty, from the same reading
CREATE OR REPLACE FUNCTION people.biodata_compliance_units(p_faculty text DEFAULT NULL, p_department text DEFAULT NULL)
RETURNS TABLE(code text, name text, faculty_code text, total int, incomplete int, up_to_date int)
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_faculty IS NULL THEN p.faculty_code ELSE p.dept_code END,
           coalesce(CASE WHEN p_faculty IS NULL THEN f.name ELSE d.name END, CASE WHEN p_faculty IS NULL THEN 'No faculty on record' ELSE 'No department on record' END),
           p.faculty_code,
           count(*)::int, count(*) FILTER (WHERE x.status = 'INCOMPLETE')::int, count(*) FILTER (WHERE x.status = 'UP_TO_DATE')::int
      FROM people.biodata_status_snapshot x
      JOIN people.student s ON s.id = x.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE (p_faculty IS NULL OR p.faculty_code = p_faculty)
       AND (p_department IS NULL OR p.dept_code = p_department)
     GROUP BY 1, 2, 3
     ORDER BY 2
$$;
COMMENT ON FUNCTION people.biodata_compliance_units(text, text) IS
  'V434: from the latest reading, the students and how many are incomplete or up to date, by faculty — or by department within the faculty given.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V753 · The review of V751 applied
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The review of V751 (two readers, each finding put to a refuter) confirmed five, all answered here.
--    · A staff card's department from a unit-scoped office read only an exact unit code, but Users & roles stores the unit as typed
--      ("Medical Library", "Transport"): a Librarian bounded to the Medical Library printed the main Library, Support Services bounded
--      to Transport printed a dash. The typed unit is resolved as the nominal roll resolves it (ref.resolve_unit: a known spelling,
--      a department, a faculty, a unit by name), before the office's own unit.
--    · A programme-scoped office (an Examinations Officer, as Users & roles bounds one by default) and a course-scoped one (a lecturer
--      given one course) printed a dash: the programme's or the course's department is read.
--    · registration.summer_code_after followed a code, not the course: after a rename it accepted whatever course now held the new
--      code, so a later course that took an intermediate code won. It now follows the course renamed (its id) to the code it bears
--      today, or, merged away since, to the course kept; a merge alias to the course kept (its code kept current by the alias's key).
--    · The comparison of V746's repair with the trail from the grant compared V746's choice as it was then with today's code, so later
--      renames and merges counted as V746's errors. Both V746's and V751's choices are now brought forward to today before they are
--      compared, and the notices count authorisations, not codes.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V753: the review of V751 applied', true);

-- ── a staff card's department: the HR record, else the office held — any scope it is bounded by ─────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.staff_card_department(p_person uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT coalesce(d.name, ref.unit_card_name(sr.home_unit), nullif(btrim(sr.unit_as_given), ''))
           FROM hrm.staff_record sr LEFT JOIN ref.department d ON d.code = sr.home_department
          WHERE sr.person_id = p_person),
        -- V751, V753: the office the person holds today, read by its scope — a department (or a programme's or a course's), a unit (as
        -- typed, resolved as the roll resolves it), a faculty, a college — else the unit a central office belongs to
        (SELECT x.v FROM (
            SELECT CASE a.scope_kind
                       WHEN 'department' THEN (SELECT d.name FROM ref.department d WHERE d.code = a.scope_id)
                       WHEN 'programme' THEN (SELECT d.name FROM ref.programme p JOIN ref.department d ON d.code = p.dept_code WHERE p.code = a.scope_id)
                       WHEN 'course' THEN (SELECT d.name FROM catalogue.course k JOIN ref.department d ON d.code = k.dept_code WHERE k.code = a.scope_id)
                       WHEN 'unit' THEN coalesce(
                           (SELECT ref.unit_card_name(u.code) FROM ref.unit u WHERE u.code = a.scope_id),
                           (SELECT coalesce(ref.unit_card_name(r.unit_code),
                                            (SELECT d.name FROM ref.department d WHERE d.code = r.dept_code),
                                            (SELECT CASE WHEN f.name ILIKE 'faculty%' THEN f.name ELSE 'Faculty of ' || f.name END FROM ref.faculty f WHERE f.code = r.faculty_code))
                              FROM ref.resolve_unit(a.scope_id) r LIMIT 1))
                       WHEN 'faculty' THEN (SELECT CASE WHEN f.name ILIKE 'faculty%' THEN f.name ELSE 'Faculty of ' || f.name END FROM ref.faculty f WHERE f.code = a.scope_id)
                       WHEN 'college' THEN (SELECT c.name FROM ref.college c WHERE c.code = a.scope_id)
                   END AS scoped,
                   ref.unit_card_name(o.unit_code) AS central,
                   CASE a.scope_kind WHEN 'department' THEN 1 WHEN 'programme' THEN 2 WHEN 'course' THEN 3 WHEN 'unit' THEN 4
                                     WHEN 'faculty' THEN 5 WHEN 'college' THEN 6 ELSE 7 END AS rank,
                   a.valid_from
              FROM iam.office_assignment a JOIN ref.office o ON o.code = a.office_code
             WHERE a.person_id = p_person AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
        ) y CROSS JOIN LATERAL (SELECT coalesce(y.scoped, y.central) AS v) x
          WHERE x.v IS NOT NULL
          ORDER BY y.rank, y.valid_from DESC LIMIT 1));
$$;
COMMENT ON FUNCTION credentials.staff_card_department(uuid) IS
    'V748, V751, V753: the department a staff identity card prints — the academic department the HR record names, else the unit''s card name, else the unit as the roll spelled it; else the office the person holds (a department, programme or course scope''s department; a unit scope, as typed, resolved as the roll resolves it; a faculty; a college; or the unit a central office belongs to); NULL when nothing resolves (the card prints a dash, never an office''s title).';

-- ── a course followed from a date, not its code ──────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.summer_code_after(p_code text, p_since timestamptz) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, ''))); v_at timestamptz := coalesce(p_since, '-infinity'); ch record; al record; v_now text;
BEGIN
    -- the first thing that happened to the course bearing the code at p_since: a rename of it, or its merge into another
    SELECT c.course_id, c.changed_at INTO ch FROM catalogue.course_change c
     WHERE c.field = 'CODE' AND upper(c.old_value) = v_code AND c.changed_at >= v_at ORDER BY c.changed_at LIMIT 1;
    SELECT a.course_code, a.merged_at INTO al FROM catalogue.course_alias a WHERE a.alias_code = v_code AND a.merged_at >= v_at;
    IF ch.course_id IS NULL AND al.course_code IS NULL THEN
        -- nothing happened to it: the course bearing it then bears it now
        RETURN (SELECT k.code FROM catalogue.course k WHERE k.code = v_code);
    END IF;
    IF ch.course_id IS NOT NULL AND (al.course_code IS NULL OR ch.changed_at <= al.merged_at) THEN
        -- renamed: that course, by its id, to the code it bears today; merged away since, the course kept
        SELECT k.code INTO v_now FROM catalogue.course k WHERE k.id = ch.course_id;
        IF v_now IS NOT NULL THEN RETURN v_now; END IF;
        RETURN (SELECT a.course_code FROM catalogue.course_alias a WHERE a.absorbed_id = ch.course_id ORDER BY a.merged_at DESC LIMIT 1);
    END IF;
    -- merged away: the course kept (the alias's code follows the kept course's renames and merges by its key)
    RETURN al.course_code;
END $$;
COMMENT ON FUNCTION registration.summer_code_after(text, timestamptz) IS
    'V751, V753: the code that the course bearing p_code at p_since bears now — the course followed by its id through its renames, and through a merge to the course kept; never a later course that took one of its codes. NULL when that course is gone and nothing kept it.';

-- ── put right, and told ──────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record; v_new text; v_courses text[]; n_auth int := 0; n_dead int; n_wrong int;
BEGIN
    -- authorisations still naming a dead code: each authorisation once, every dead code in it followed from its grant
    FOR r IN SELECT sa.session, sa.student_id, sa.courses, sa.granted_at FROM registration.summer_authorisation sa
              WHERE EXISTS (SELECT 1 FROM unnest(sa.courses) x WHERE NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x)))) LOOP
        v_courses := ARRAY(SELECT DISTINCT coalesce(CASE WHEN NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x)))
                                                         THEN registration.summer_code_after(x, r.granted_at) END, upper(btrim(x)))
                             FROM unnest(r.courses) x ORDER BY 1);
        IF v_courses IS DISTINCT FROM ARRAY(SELECT DISTINCT upper(btrim(x)) FROM unnest(r.courses) x ORDER BY 1) THEN
            UPDATE registration.summer_authorisation SET courses = v_courses WHERE session = r.session AND student_id = r.student_id;
            n_auth := n_auth + 1;
        END IF;
    END LOOP;
    SELECT count(*) INTO n_dead FROM registration.summer_authorisation sa
     WHERE EXISTS (SELECT 1 FROM unnest(sa.courses) x WHERE NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x))));
    -- authorisations V746's or V751's repair rewrote to another course than the trail from the grant gives — each choice brought
    -- forward to today before it is compared (for the Academic Office; not changed)
    SELECT count(DISTINCT (e.after_state ->> 'student_id', e.after_state ->> 'session')) INTO n_wrong
      FROM audit.entries e
      CROSS JOIN LATERAL (SELECT upper(btrim(b)) AS old_code FROM jsonb_array_elements_text(e.before_state -> 'courses') b
                           WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(e.after_state -> 'courses') a WHERE upper(btrim(a)) = upper(btrim(b)))) o
     WHERE e.subject_type = 'registration.summer_authorisation' AND (e.reason LIKE 'V746:%' OR e.reason LIKE 'V751:%')
       AND registration.summer_code_after(o.old_code, (e.before_state ->> 'granted_at')::timestamptz) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(e.after_state -> 'courses') a
                        WHERE coalesce(registration.summer_code_after(upper(btrim(a)), e.occurred_at), upper(btrim(a)))
                              = registration.summer_code_after(o.old_code, (e.before_state ->> 'granted_at')::timestamptz));
    RAISE NOTICE 'V753: % Summer authorisations put right from the date they were granted (% still name a course no longer on the catalogue); % authorisations V746 or V751 rewrote to another course than the trail from the grant gives (for the Academic Office, not changed)',
        n_auth, n_dead, n_wrong;
END $$;

COMMIT;

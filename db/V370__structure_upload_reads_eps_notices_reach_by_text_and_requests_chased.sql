-- V370: the programme structure upload reads EPS; the offices' notices reach a holder with no email by text; a request
--       between the GST and EPS offices that nobody answers is chased.
--
-- 1  EPS read. The structure upload took a row's status by its first letter, so a status of EPS loaded the course as E —
--    Elective — and nothing in the file could say a course is the EPS office's. Now the status is read whole: EPS (or a
--    Classification column of EPS) makes the course general and files it with the EPS office when no office holds it yet;
--    GST (or a Classification of GST) is G as before. An office's course stays the office's — the other office asks for it.
--    catalogue.structure_placements, the preview, reads the same and names a course the file says is EPS but the GST office
--    holds (or the reverse).
-- 2  Reached. A notice to an office went to the holders with an email and to nobody else. Now a holder with no email but a
--    phone gets a short text instead (no course detail beyond the code); catalogue.general_office_reach lists every holder
--    and how they are reached, for the dashboards to name those who cannot be.
-- 3  Chased. A request between the offices waits for the office that holds the course. Each morning the office is reminded
--    once of a request older than the reminder days, and a request older than the escalation days is put to the Academic
--    Office (and both offices told). The days are the Academic Office's to set (3 and 7 to begin with).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V370: structure upload reads EPS; office notices reach by text; requests between the offices chased', true);

-- ── 1 · the structure upload reads EPS (V338's loader otherwise) ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION catalogue.import_courses_rows(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL::text)
RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text; v_owner text; v_status_raw text; v_class text; v_eps boolean;
        n int := 0; nc int := 0; no int := 0; nnd int := 0; nb int := 0; ns int := 0; ne int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a course upload is made by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: course code, title, units, status, level, semester' USING ERRCODE = '23514';
    END IF;
    v_curr := upper(nullif(btrim(coalesce(p_curriculum, '')), ''));
    IF v_curr IS NOT NULL AND v_curr NOT IN ('CCMAS', 'BMAS') THEN v_curr := NULL; END IF;
    SELECT code, dept_code INTO v_prog, v_dept FROM ref.programme
     WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'no programme is coded or named %', p_programme USING ERRCODE = '23503'; END IF;
    IF v_dept IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department WHERE code = v_dept) THEN
        RAISE EXCEPTION 'the programme % has no department on the register to own its courses', v_prog USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_code := regexp_replace(upper(btrim(coalesce(r->>'code', r->>'courseCode', r->>'course_code', ''))), '\s+', ' ', 'g');
        IF v_code = '' OR v_code ~* '^course\s*code$' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN nb := nb + 1; CONTINUE; END IF;

        BEGIN
            v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', '')), '');
            IF v_title IS NULL THEN v_title := v_code; END IF;
            v_units := least(coalesce(nullif(regexp_replace(coalesce(r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 0), 12);
            v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, 100);
            IF v_level NOT IN (100,200,300,400,500,600) THEN v_level := 100; END IF;
            v_sem := coalesce(nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int, 1);
            IF v_sem NOT IN (1,2,3) THEN v_sem := 1; END IF;
            v_lh := nullif(regexp_replace(coalesce(r->>'lh', r->>'LH', ''), '[^0-9]', '', 'g'), '')::int;
            v_ph := nullif(regexp_replace(coalesce(r->>'ph', r->>'PH', ''), '[^0-9]', '', 'g'), '')::int;
            -- V370: the status is read whole before its first letter, so EPS is not taken for E (Elective); EPS, or a GST/EPS
            -- classification column, makes the course general, and EPS files it with the EPS office
            v_status_raw := upper(btrim(coalesce(r->>'status', 'C')));
            v_class := upper(nullif(btrim(coalesce(r->>'classification', r->>'gstEps', '')), ''));
            v_eps := v_status_raw = 'EPS' OR v_class = 'EPS';
            v_status := CASE WHEN v_status_raw IN ('GST', 'EPS') OR v_class IN ('GST', 'EPS') THEN 'G' ELSE upper(left(v_status_raw, 1)) END;
            v_kind := CASE WHEN v_code LIKE 'GST %' OR v_code LIKE 'GST%' THEN 'GST'
                           WHEN v_status = 'G' THEN 'GST'  -- GST/EPS courses carried by status, not a GST code
                           WHEN v_status = 'R' THEN 'Required' WHEN v_status = 'E' THEN 'Elective' ELSE 'Core' END;
            v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Core' END;

            SELECT dept_code INTO v_owner FROM catalogue.course WHERE code = v_code;
            IF v_owner IS NOT NULL AND v_owner <> v_dept THEN
                -- V332: another department's course, carried by this programme: one course, bound as Borrowed
                -- (or on the basis the row says where it is GST or Elective); its title, units and level are its owner's to set
                v_basis := CASE WHEN v_kind = 'GST' THEN 'GST' WHEN v_kind = 'Elective' THEN 'Elective' ELSE 'Borrowed' END;
                ne := ne + 1;
            ELSE
                INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state, general_office)
                VALUES (v_code, v_title, v_units, v_sem, v_level, v_dept, v_kind, v_lh, v_ph, v_curr, 'LIVE', CASE WHEN v_eps THEN 'EPS' END)
                ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units, semester = EXCLUDED.semester,
                    level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours,
                    curriculum = coalesce(EXCLUDED.curriculum, catalogue.course.curriculum),
                    state = CASE WHEN catalogue.course.state IN ('BOARD', 'SENATE') OR catalogue.course.reset_batch_id IS NOT NULL THEN 'LIVE' ELSE catalogue.course.state END,
                    ended_on = CASE WHEN catalogue.course.reset_batch_id IS NOT NULL THEN NULL ELSE catalogue.course.ended_on END,
                    reset_batch_id = NULL,
                    -- V370: EPS files a course no office holds with the EPS office; an office's course stays the office's
                    general_office = CASE WHEN catalogue.course.general_office IS NULL THEN EXCLUDED.general_office ELSE catalogue.course.general_office END;
                nc := nc + 1;
            END IF;

            INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, added_by, source)
            VALUES (v_code, v_prog, v_level, v_basis, v_actor, 'IMPORT')
            ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;

            no := no + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_code || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, no, nnd, nb, ns, v_firsterr, ne;
END $$;
COMMENT ON FUNCTION catalogue.import_courses_rows(text, jsonb, text) IS
  'V338/V370: one programme''s structure rows loaded — a status of EPS (or a Classification column of GST or EPS) is read whole and makes the course general, EPS filing it with the EPS office when no office holds it.';

CREATE OR REPLACE FUNCTION catalogue.structure_placements(p_groups jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
WITH g AS (
    SELECT gn::int AS gn, x AS j FROM jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) WITH ORDINALITY AS t(x, gn)
), gp AS (
    SELECT g.gn, g.j, p.code AS prog, p.dept_code AS dept
      FROM g LEFT JOIN LATERAL (SELECT x.code, x.dept_code FROM ref.programme x
                                 WHERE upper(x.code) = upper(btrim(coalesce(g.j->>'programme', ''))) OR upper(x.name) = upper(btrim(coalesce(g.j->>'programme', '')))
                                 ORDER BY x.archived, x.code LIMIT 1) p ON true
), r AS (
    SELECT gp.gn, rn::int AS rn, gp.prog, gp.dept,
           regexp_replace(upper(btrim(coalesce(x->>'code', x->>'courseCode', x->>'course_code', ''))), '\s+', ' ', 'g') AS code,
           nullif(btrim(coalesce(x->>'title', x->>'courseTitle', '')), '') AS title,
           upper(btrim(coalesce(x->>'status', 'C'))) AS status_raw,
           upper(nullif(btrim(coalesce(x->>'classification', x->>'gstEps', '')), '')) AS class
      FROM gp CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(gp.j->'rows') = 'array' THEN gp.j->'rows' ELSE '[]'::jsonb END) WITH ORDINALITY AS t(x, rn)
     WHERE gp.prog IS NOT NULL AND gp.dept IS NOT NULL
), s AS (
    SELECT r.*, (r.status_raw = 'EPS' OR r.class = 'EPS') AS eps,
           CASE WHEN r.status_raw IN ('GST', 'EPS') OR r.class IN ('GST', 'EPS') THEN 'G' ELSE left(r.status_raw, 1) END AS status
      FROM r
), k AS (
    SELECT s.*, CASE WHEN s.code LIKE 'GST%' THEN 'GST' WHEN s.status = 'G' THEN 'GST' WHEN s.status = 'R' THEN 'Required'
                     WHEN s.status = 'E' THEN 'Elective' ELSE 'Core' END AS kind
      FROM s WHERE s.code ~ '^[A-Z][A-Z0-9 /-]{2,19}$' AND s.code !~* '^course\s*code$'
), owner AS (
    SELECT DISTINCT ON (k.code) k.code, coalesce(c.dept_code, k.dept) AS dept
      FROM k LEFT JOIN catalogue.course c ON c.code = k.code ORDER BY k.code, k.gn, k.rn
), last AS (
    SELECT DISTINCT ON (k.code) k.code, k.kind, k.eps, coalesce(k.title, k.code) AS title, coalesce(k.class, k.status_raw) AS said, k.prog, k.dept
      FROM k JOIN owner o ON o.code = k.code AND o.dept = k.dept ORDER BY k.code, k.gn DESC, k.rn DESC
), p AS (
    SELECT l.code, l.title, l.said, l.eps, l.prog, l.dept, c.code IS NOT NULL AS existing, c.kind AS before_kind, c.general_office AS before_office,
           c.general_released_at IS NOT NULL AS released, c.title AS before_title, l.kind AS file_kind,
           CASE WHEN c.code IS NOT NULL AND c.kind = 'GST' AND c.general_office IS NOT NULL AND l.kind <> 'GST' THEN c.kind
                WHEN c.code IS NOT NULL AND c.general_released_at IS NOT NULL AND l.kind = 'GST' AND c.kind <> 'GST' THEN c.kind
                ELSE l.kind END AS after_kind
      FROM last l LEFT JOIN catalogue.course c ON c.code = l.code
), q AS (
    SELECT p.*, CASE WHEN p.after_kind = 'GST'
                     THEN coalesce(p.before_office, CASE WHEN p.eps THEN 'EPS' END, catalogue.general_office_of(p.code, p.title, 'GST')) END AS after_office
      FROM p
), z AS (
    SELECT q.*, d.name AS department,
           CASE WHEN NOT q.existing AND q.after_office IS NOT NULL THEN 'NEW_TO_OFFICE'
                WHEN NOT q.existing AND q.after_kind = 'GST' THEN 'NEW_NO_OFFICE'
                WHEN q.existing AND q.before_office IS NOT NULL AND q.before_kind = 'GST' AND q.file_kind <> 'GST' THEN 'KEPT_WITH_OFFICE'
                WHEN q.existing AND q.before_office = 'GST' AND q.eps THEN 'OTHER_OFFICE_HOLDS'
                WHEN q.existing AND q.released AND q.file_kind = 'GST' AND q.before_kind <> 'GST' THEN 'KEPT_WITH_DEPARTMENT'
                WHEN q.existing AND q.before_office IS NULL AND q.after_office IS NOT NULL THEN 'TO_OFFICE'
                WHEN q.existing AND q.before_kind <> 'GST' AND q.after_kind = 'GST' THEN 'MARKED_GENERAL_NO_OFFICE'
                WHEN q.existing AND q.before_kind = 'GST' AND q.after_kind <> 'GST' THEN 'BACK_TO_DEPARTMENT' END AS change
      FROM q LEFT JOIN ref.department d ON d.code = q.dept
)
SELECT jsonb_build_object(
    'placements', coalesce(jsonb_agg(jsonb_build_object(
        'code', z.code, 'title', coalesce(z.before_title, z.title), 'programme', z.prog, 'status', z.said, 'department', z.department,
        'beforeOffice', z.before_office, 'beforeKind', z.before_kind, 'afterOffice', z.after_office, 'afterKind', z.after_kind, 'change', z.change)
        ORDER BY z.change, z.code) FILTER (WHERE z.change IS NOT NULL), '[]'::jsonb),
    'counts', jsonb_build_object(
        'toGst', count(*) FILTER (WHERE z.change IN ('NEW_TO_OFFICE', 'TO_OFFICE') AND z.after_office = 'GST'),
        'toEps', count(*) FILTER (WHERE z.change IN ('NEW_TO_OFFICE', 'TO_OFFICE') AND z.after_office = 'EPS'),
        'noOffice', count(*) FILTER (WHERE z.change IN ('NEW_NO_OFFICE', 'MARKED_GENERAL_NO_OFFICE')),
        'backToDepartment', count(*) FILTER (WHERE z.change = 'BACK_TO_DEPARTMENT'),
        'keptWithOffice', count(*) FILTER (WHERE z.change = 'KEPT_WITH_OFFICE'),
        'otherOffice', count(*) FILTER (WHERE z.change = 'OTHER_OFFICE_HOLDS'),
        'keptWithDepartment', count(*) FILTER (WHERE z.change = 'KEPT_WITH_DEPARTMENT')))
  FROM z;
$$;

-- ── 2 · a notice to an office reaches every holder it can: email, or a text when there is no email ─────────────────

DROP FUNCTION catalogue.tell_general_office(text, text, text);
DROP FUNCTION catalogue.general_office_holders(text);

/* every holder of an office today, with what the record holds to reach them by */
CREATE OR REPLACE FUNCTION catalogue.general_office_reach(p_office text)
RETURNS TABLE(id uuid, name text, email text, phone text) LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (p.id) p.id, btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, ''), ', '),
           nullif(btrim(coalesce(p.email, '')), ''), nullif(btrim(coalesce(p.phone, '')), '')
      FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id
     WHERE a.office_code = lower(p_office) AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
       AND p.ended_on IS NULL
     ORDER BY p.id;
$$;
COMMENT ON FUNCTION catalogue.general_office_reach(text) IS 'V370: the holders of an office today and the email and phone on their record — whom a notice to the office reaches, and how.';

/* the email to each holder with one; a short text to each holder with a phone and no email; returns how many were reached */
CREATE OR REPLACE FUNCTION catalogue.tell_general_office(p_office text, p_subject text, p_body text, p_sms text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE h record; n int := 0;
BEGIN
    FOR h IN SELECT * FROM catalogue.general_office_reach(p_office) LOOP
        IF h.email IS NOT NULL THEN
            PERFORM platform.queue_notice('EMAIL', h.email, p_subject, p_body, 'person', h.id);
            n := n + 1;
        ELSIF h.phone IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', h.phone, p_subject,
                                          coalesce(p_sms, 'MOAUM: ' || p_subject || '. Sign in to the portal to see it.'), 'person', h.id);
            n := n + 1;
        END IF;
    END LOOP;
    RETURN n;
END $$;

-- ── 3 · a request nobody answers is chased: the holding office reminded once, then the Academic Office asked ────────

CREATE TABLE catalogue.general_transfer_setting (
    id                  int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    remind_after_days   int NOT NULL DEFAULT 3 CHECK (remind_after_days BETWEEN 1 AND 60),
    escalate_after_days int NOT NULL DEFAULT 7 CHECK (escalate_after_days BETWEEN 2 AND 120),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    updated_by          uuid NULL,
    CONSTRAINT ck_general_transfer_setting_order CHECK (escalate_after_days > remind_after_days)
);
COMMENT ON TABLE catalogue.general_transfer_setting IS
  'V370: after how many days a request between the GST and EPS offices is reminded to the office that holds the course, and after how many it is put to the Academic Office — the Academic Office''s to set.';
SELECT audit.attach('catalogue.general_transfer_setting');
INSERT INTO catalogue.general_transfer_setting (id) VALUES (1);
GRANT SELECT ON catalogue.general_transfer_setting TO app_auditor;

ALTER TABLE catalogue.general_transfer ADD COLUMN reminded_at timestamptz NULL;
ALTER TABLE catalogue.general_transfer ADD COLUMN escalated_at timestamptz NULL;
COMMENT ON COLUMN catalogue.general_transfer.reminded_at IS 'V370: when the office that holds the course was reminded of the request (once).';
COMMENT ON COLUMN catalogue.general_transfer.escalated_at IS 'V370: when the request was put to the Academic Office for a decision (once).';

CREATE OR REPLACE FUNCTION catalogue.set_general_transfer_setting(p_remind int, p_escalate int)
RETURNS catalogue.general_transfer_setting
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := lower(coalesce(nullif(current_setting('moaum.actor_office', true), ''), ''));
        s catalogue.general_transfer_setting;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a setting is changed by a person' USING ERRCODE = '23514'; END IF;
    IF actor NOT IN ('academic', 'super') THEN
        RAISE EXCEPTION 'GEN_TRANSFER_SETTING: the Academic Office sets when requests are chased' USING ERRCODE = '23514';
    END IF;
    IF p_remind IS NULL OR p_escalate IS NULL OR p_remind < 1 OR p_escalate <= p_remind OR p_remind > 60 OR p_escalate > 120 THEN
        RAISE EXCEPTION 'GEN_TRANSFER_SETTING: remind after 1 to 60 days, and ask the Academic Office later than that, within 120 days' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.general_transfer_setting SET remind_after_days = p_remind, escalate_after_days = p_escalate, updated_at = now(), updated_by = who
     WHERE id = 1 RETURNING * INTO s;
    RETURN s;
END $$;

/* run each morning: a reminder to the office that holds the course, once; later, the request put to the Academic Office, once.
   Marked only when somebody was reached, so a request nobody could be told of is tried again the next morning. */
CREATE OR REPLACE FUNCTION catalogue.chase_general_transfers()
RETURNS TABLE(reminded int, escalated int)
LANGUAGE plpgsql AS $$
DECLARE s catalogue.general_transfer_setting; t record; n int; r int := 0; e int := 0; v_on text; v_days int;
BEGIN
    SELECT * INTO s FROM catalogue.general_transfer_setting WHERE id = 1;
    FOR t IN SELECT x.*, c.title FROM catalogue.general_transfer x JOIN catalogue.course c ON c.code = x.course_code
              WHERE x.state = 'PENDING' AND x.reminded_at IS NULL AND x.escalated_at IS NULL
                AND x.requested_at <= now() - make_interval(days => s.remind_after_days)
                AND x.requested_at > now() - make_interval(days => s.escalate_after_days)
              ORDER BY x.requested_at FOR UPDATE OF x SKIP LOCKED LOOP
        v_on := to_char(t.requested_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY');
        n := catalogue.tell_general_office(t.from_office, 'Reminder: the ' || t.to_office || ' office asks for ' || t.course_code,
            'On ' || v_on || ' the ' || t.to_office || ' office asked for ' || t.course_code || ' ' || t.title || ', which is the ' || t.from_office
            || ' office''s course, and the request is still waiting for an answer.' || E'\n\n' || 'Its reason: ' || t.reason || E'\n\n'
            || 'Sign in to the portal and open ' || t.from_office || ' Courses: under "Requests between the GST and EPS offices", accept to pass the course, '
            || 'or decline and say why. If it is still unanswered ' || s.escalate_after_days || ' days after it was made, it goes to the Academic Office to decide.' || E'\n');
        IF n > 0 THEN
            UPDATE catalogue.general_transfer SET reminded_at = now() WHERE id = t.id;
            r := r + 1;
        END IF;
    END LOOP;
    FOR t IN SELECT x.*, c.title FROM catalogue.general_transfer x JOIN catalogue.course c ON c.code = x.course_code
              WHERE x.state = 'PENDING' AND x.escalated_at IS NULL
                AND x.requested_at <= now() - make_interval(days => s.escalate_after_days)
              ORDER BY x.requested_at FOR UPDATE OF x SKIP LOCKED LOOP
        v_on := to_char(t.requested_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY');
        v_days := greatest(1, (current_date - (t.requested_at AT TIME ZONE 'Africa/Lagos')::date));
        n := catalogue.tell_general_office('academic', 'A request between the GST and EPS offices waits for your decision: ' || t.course_code,
            'On ' || v_on || ' the ' || t.to_office || ' office asked the ' || t.from_office || ' office for ' || t.course_code || ' ' || t.title
            || '. The ' || t.from_office || ' office has not answered in ' || v_days || ' days.' || E'\n\n' || 'The reason given: ' || t.reason || E'\n\n'
            || 'Sign in to the portal and open All Courses: under "Requests between the GST and EPS offices", accept the request to pass the course, '
            || 'or decline it and say why.' || E'\n');
        IF n > 0 THEN
            UPDATE catalogue.general_transfer SET escalated_at = now() WHERE id = t.id;
            e := e + 1;
            PERFORM catalogue.tell_general_office(t.from_office, 'The request for ' || t.course_code || ' has gone to the Academic Office',
                'The ' || t.to_office || ' office''s request for ' || t.course_code || ' was not answered in ' || v_days
                || ' days and has gone to the Academic Office to decide. You may still answer it on ' || t.from_office || ' Courses until it does.' || E'\n');
            PERFORM catalogue.tell_general_office(t.to_office, 'Your request for ' || t.course_code || ' has gone to the Academic Office',
                'The ' || t.from_office || ' office has not answered your request for ' || t.course_code || ' in ' || v_days
                || ' days, so it has gone to the Academic Office to decide. You will be told the answer.' || E'\n');
        END IF;
    END LOOP;
    RETURN QUERY SELECT r, e;
END $$;
COMMENT ON FUNCTION catalogue.chase_general_transfers() IS
  'V370: run each morning — a request between the GST and EPS offices reminded once to the office that holds the course, and put to the Academic Office once it is older than the escalation days.';

COMMIT;

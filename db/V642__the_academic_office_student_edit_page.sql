-- V642: the Academic Office student edit page — the University's master prompt of 23 October 2026 ("ACADEMIC OFFICE FULL STUDENT EDIT
-- PAGE": one interface where the Academic Office views, corrects and manages a student's academic and master record, every
-- important change validated, transactional, audited and traceable; no second student system, no history deleted, no financial
-- transaction changed).
--   · people.student_edit_grant: what each office may do on the page — EDIT_STUDENT_ACADEMIC_RECORD, the major permission, carries
--     the parts (biodata, admission, placement, programme, level, session, status, matriculation, classification, graduation,
--     carry-over, spillover, registration, the registration override) and VIEW_STUDENT_EDIT_HISTORY; the Academic Office and the
--     Registry hold the major one, Records, ICT, the platform and Audit read the history. The API checks every act against it.
--   · people.student_edit: every edit kept, one row per field or act, under STU-EDIT/YYYY/NNNNNN — the value before and after, the
--     reason, the severity (NORMAL, IMPORTANT, CRITICAL), the effective session and semester, the evidence, who and when. Never
--     changed; removed only with the record by the go-live reset (moaum.maintenance).
--   · people.student_edit_version: the reading of the record an edit is made on; an edit on an older reading is refused
--     (STU_EDIT_STALE) — two officers never overwrite each other silently.
--   · people.student_edit_reason_refused: a reason is a sentence — fifteen characters, three words — never "test", "update" or
--     "correction".
--   · people.student_edit_apply: the identity (names, sex, date of birth), admission (JAMB registration and admission numbers,
--     admission session, entry mode, entry level) and placement (study mode, centre, curriculum track) corrections, all checked —
--     the permission per field, the reason, the version, uniqueness of the numbers, the session on the calendar, the level within
--     the programme — and then all written, or none; a JAMB or admission number is critical and confirmed.
--   · people.student_edit_history: every change of the record from every workflow that makes one — the edits, status changes,
--     completed programme swaps, level changes, completed matriculation corrections, graduation reconciliations and classification
--     decisions — for the page's searchable change history.
--   · people.support_set_level and people.support_set_spillover restated exactly as they stand with the Academic Office and the
--     Registry beside ICT Support and the Students Account Officer: the page corrects the level and sets SP1/SP2 through them, so
--     the programme's levels, the status, the registration's carry (V641) and the cohort decision history are the same.
-- The programme (faculty, department), the classification, the matriculation number and graduation keep their own workflows; the
-- page calls them.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V642: the Academic Office student edit page (the University, 23 October 2026)', true);

-- ── who may edit what: the Academic Office's major permission and the parts it is made of, by office ──
CREATE TABLE people.student_edit_grant (
    office_code text NOT NULL,
    permission text NOT NULL CHECK (permission IN (
        'EDIT_STUDENT_ACADEMIC_RECORD', 'EDIT_STUDENT_BIODATA', 'EDIT_STUDENT_ADMISSION', 'EDIT_STUDENT_ACADEMIC_PLACEMENT',
        'EDIT_STUDENT_PROGRAMME', 'EDIT_STUDENT_DEPARTMENT', 'EDIT_STUDENT_FACULTY', 'EDIT_STUDENT_LEVEL', 'EDIT_STUDENT_SESSION',
        'EDIT_STUDENT_STATUS', 'EDIT_STUDENT_MATRICULATION', 'EDIT_STUDENT_CLASSIFICATION', 'EDIT_STUDENT_ENROLLMENT',
        'EDIT_STUDENT_ACADEMIC_HISTORY', 'EDIT_STUDENT_GRADUATION_STATUS', 'EDIT_STUDENT_CARRYOVER', 'EDIT_STUDENT_SPILLOVER',
        'EDIT_STUDENT_REGISTRATION', 'OVERRIDE_STUDENT_REGISTRATION', 'VIEW_STUDENT_EDIT_HISTORY')),
    granted_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (office_code, permission)
);
SELECT audit.attach('people.student_edit_grant');
COMMENT ON TABLE people.student_edit_grant IS
  'V642: what each office may do on the Academic Office student edit page. EDIT_STUDENT_ACADEMIC_RECORD is the major permission and carries every other; the API checks the active office against this table on every read and write.';

INSERT INTO people.student_edit_grant (office_code, permission) VALUES
    ('academic', 'EDIT_STUDENT_ACADEMIC_RECORD'), ('registrar', 'EDIT_STUDENT_ACADEMIC_RECORD'),
    ('dregistrar', 'EDIT_STUDENT_ACADEMIC_RECORD'), ('super', 'EDIT_STUDENT_ACADEMIC_RECORD'),
    ('records', 'VIEW_STUDENT_EDIT_HISTORY'), ('ict', 'VIEW_STUDENT_EDIT_HISTORY'), ('admin', 'VIEW_STUDENT_EDIT_HISTORY'),
    ('audit', 'VIEW_STUDENT_EDIT_HISTORY'), ('deputyaudit', 'VIEW_STUDENT_EDIT_HISTORY')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION people.student_edit_permissions(p_office text)
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM people.student_edit_grant g WHERE g.office_code = p_office AND g.permission = 'EDIT_STUDENT_ACADEMIC_RECORD')
                THEN ARRAY['EDIT_STUDENT_ACADEMIC_RECORD', 'EDIT_STUDENT_BIODATA', 'EDIT_STUDENT_ADMISSION', 'EDIT_STUDENT_ACADEMIC_PLACEMENT',
                           'EDIT_STUDENT_PROGRAMME', 'EDIT_STUDENT_DEPARTMENT', 'EDIT_STUDENT_FACULTY', 'EDIT_STUDENT_LEVEL', 'EDIT_STUDENT_SESSION',
                           'EDIT_STUDENT_STATUS', 'EDIT_STUDENT_MATRICULATION', 'EDIT_STUDENT_CLASSIFICATION', 'EDIT_STUDENT_ENROLLMENT',
                           'EDIT_STUDENT_ACADEMIC_HISTORY', 'EDIT_STUDENT_GRADUATION_STATUS', 'EDIT_STUDENT_CARRYOVER', 'EDIT_STUDENT_SPILLOVER',
                           'EDIT_STUDENT_REGISTRATION', 'OVERRIDE_STUDENT_REGISTRATION', 'VIEW_STUDENT_EDIT_HISTORY']
                ELSE coalesce((SELECT array_agg(g.permission ORDER BY g.permission) FROM people.student_edit_grant g WHERE g.office_code = p_office), '{}') END
$$;

CREATE OR REPLACE FUNCTION people.student_edit_may(p_office text, p_permission text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT p_permission = ANY (people.student_edit_permissions(coalesce(p_office, '')))
$$;

-- ── every edit, kept: the field, before and after, the reason, how serious, who, when — under its own reference ──
CREATE TABLE people.student_edit (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference text NOT NULL UNIQUE,
    student_id uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    section text NOT NULL,
    field text NOT NULL,
    old_value text,
    new_value text,
    reason text,
    severity text NOT NULL CHECK (severity IN ('NORMAL', 'IMPORTANT', 'CRITICAL')),
    change_type text NOT NULL CHECK (change_type IN ('EDIT', 'LEVEL', 'SPILLOVER', 'STATUS', 'REGISTRATION', 'REGISTRATION_OVERRIDE', 'FINANCIAL_ISSUE')),
    effective_session text,
    effective_semester integer,
    evidence text,
    related_kind text,
    related_id uuid,
    actor uuid,
    actor_office text,
    at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_student_edit_student ON people.student_edit (student_id, at DESC);
SELECT audit.attach('people.student_edit');
CREATE INDEX ix_student_edit_actor ON people.student_edit (actor, at DESC);
COMMENT ON TABLE people.student_edit IS
  'V642: the Academic Office student edit page''s changes, one row per field (or act), each under STU-EDIT/YYYY/NNNNNN, with the value before and after, the reason, the severity, the effective session and semester, and who made it. Kept: never changed, removed only with the record by the go-live reset.';

CREATE OR REPLACE FUNCTION people.student_edit_kept()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'STU_EDIT_KEPT: a student edit is kept as it was made; a later edit corrects it' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_student_edit_kept BEFORE UPDATE OR DELETE ON people.student_edit
    FOR EACH ROW EXECUTE FUNCTION people.student_edit_kept();

-- the reference an edit is known by
CREATE OR REPLACE FUNCTION people.student_edit_reference()
RETURNS text
LANGUAGE sql
AS $$
    SELECT 'STU-EDIT/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/'
           || lpad(platform.next_number('STU_EDIT', 'UNIVERSITY', to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'))::text, 6, '0')
$$;

-- one edit written down, in the officer's name (moaum.actor_id / moaum.actor_office)
CREATE OR REPLACE FUNCTION people.student_edit_note(p_student uuid, p_section text, p_field text, p_old text, p_new text, p_reason text,
                                                    p_severity text, p_type text, p_session text, p_semester integer, p_evidence text,
                                                    p_related_kind text DEFAULT NULL, p_related_id uuid DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE v_ref text := people.student_edit_reference();
BEGIN
    INSERT INTO people.student_edit (reference, student_id, section, field, old_value, new_value, reason, severity, change_type,
                                     effective_session, effective_semester, evidence, related_kind, related_id, actor, actor_office)
    VALUES (v_ref, p_student, p_section, p_field, p_old, p_new, nullif(btrim(coalesce(p_reason, '')), ''), p_severity, p_type,
            nullif(btrim(coalesce(p_session, '')), ''), p_semester, nullif(btrim(coalesce(p_evidence, '')), ''), p_related_kind, p_related_id,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
    RETURN v_ref;
END $$;

-- the record as it was read: an edit made on an older reading is refused, never laid over another officer's
CREATE OR REPLACE FUNCTION people.student_edit_version(p_student uuid)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT md5(coalesce((SELECT row(s.*)::text FROM people.student s WHERE s.id = p_student), ''))
$$;

-- a reason worth keeping: a sentence, not "test", "update" or "correction"
CREATE OR REPLACE FUNCTION people.student_edit_reason_refused(p_reason text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN p_reason IS NULL OR length(btrim(p_reason)) < 15 THEN 'say why in fifteen characters or more'
        WHEN (SELECT count(DISTINCT w) FROM regexp_split_to_table(lower(btrim(p_reason)), '[^a-z0-9]+') w WHERE length(w) > 1) < 3
            THEN 'say why in a sentence: what was wrong and where the right value comes from'
        WHEN lower(regexp_replace(btrim(p_reason), '[^A-Za-z]+', '', 'g')) ~ '^(test|testing|abc|abcd|correction|corrections|update|updated|change|changed|edit|edited|fix|fixed|ok|none|na|nil|asdf|qwerty|xyz)+$'
            THEN 'say what was wrong and where the right value comes from, not only that it was corrected'
    END
$$;

-- ── the corrections made straight on the record: identity, admission and placement, all in one transaction or none ──
CREATE OR REPLACE FUNCTION people.student_edit_apply(p_student uuid, p_changes jsonb, p_reason text, p_version text, p_confirm_critical boolean,
                                                     p_effective_session text, p_effective_semester integer, p_evidence text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; k text; v text; v_new text; v_old text; v_perm text; v_sev text; v_section text;
        v_refs jsonb := '[]'::jsonb; v_refused text; v_critical boolean := false; v_needs_reason boolean := false; v_final int; v_other uuid;
        v_known constant text[] := ARRAY['surname', 'other_names', 'sex', 'date_of_birth', 'jamb_reg_no', 'admission_no', 'entry_session',
                                         'entry_mode', 'entry_level', 'study_mode', 'centre_code', 'curriculum_track'];
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'STU_EDIT_STUDENT: no such student' USING ERRCODE = 'P0002';
    END IF;
    IF p_version IS NULL OR p_version <> people.student_edit_version(p_student) THEN
        RAISE EXCEPTION 'STU_EDIT_STALE: this student record was updated by another user; refresh the record before saving your changes' USING ERRCODE = '23514';
    END IF;
    IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'object' OR p_changes = '{}'::jsonb THEN
        RAISE EXCEPTION 'STU_EDIT_NOTHING: nothing was changed' USING ERRCODE = '23514';
    END IF;
    IF p_effective_session IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_effective_session) THEN
        RAISE EXCEPTION 'STU_EDIT_SESSION: % is not a session on the calendar', p_effective_session USING ERRCODE = '23514';
    END IF;
    IF p_effective_semester IS NOT NULL AND p_effective_semester NOT IN (1, 2) THEN
        RAISE EXCEPTION 'STU_EDIT_SEMESTER: a semester is the first or the second' USING ERRCODE = '23514';
    END IF;

    -- what each field asks: the permission, how serious a change it is, the section it belongs to
    FOR k IN SELECT jsonb_object_keys(p_changes) LOOP
        IF NOT k = ANY (v_known) THEN
            RAISE EXCEPTION 'STU_EDIT_FIELD: % is not corrected here (a programme, level, status, matriculation number or graduation has its own section)', k
                USING ERRCODE = '23514';
        END IF;
        v_perm := CASE WHEN k IN ('surname', 'other_names', 'sex', 'date_of_birth') THEN 'EDIT_STUDENT_BIODATA'
                       WHEN k IN ('jamb_reg_no', 'admission_no', 'entry_mode', 'entry_level') THEN 'EDIT_STUDENT_ADMISSION'
                       WHEN k = 'entry_session' THEN 'EDIT_STUDENT_SESSION'
                       ELSE 'EDIT_STUDENT_ACADEMIC_PLACEMENT' END;
        IF NOT people.student_edit_may(v_office, v_perm) THEN
            RAISE EXCEPTION 'STU_EDIT_PERMISSION: your office does not hold % for %', v_perm, k USING ERRCODE = '42501';
        END IF;
        IF k IN ('jamb_reg_no', 'admission_no') THEN v_critical := true; END IF;
        v_needs_reason := true;   -- every field corrected here is IMPORTANT or CRITICAL: the record's identity, admission or placement
    END LOOP;
    IF v_needs_reason THEN
        v_refused := people.student_edit_reason_refused(p_reason);
        IF v_refused IS NOT NULL THEN
            RAISE EXCEPTION 'STU_EDIT_REASON: %', v_refused USING ERRCODE = '23514';
        END IF;
    END IF;
    IF v_critical AND NOT coalesce(p_confirm_critical, false) THEN
        RAISE EXCEPTION 'STU_EDIT_CONFIRM: a JAMB registration or admission number is a critical change; confirm it to go on' USING ERRCODE = '23514';
    END IF;

    FOR k, v IN SELECT key, value #>> '{}' FROM jsonb_each(p_changes) ORDER BY key LOOP
        v_new := nullif(btrim(coalesce(v, '')), '');
        v_section := CASE WHEN k IN ('surname', 'other_names', 'sex', 'date_of_birth') THEN 'IDENTITY'
                          WHEN k IN ('jamb_reg_no', 'admission_no', 'entry_session', 'entry_mode', 'entry_level') THEN 'ADMISSION'
                          ELSE 'PLACEMENT' END;
        v_sev := CASE WHEN k IN ('jamb_reg_no', 'admission_no') THEN 'CRITICAL' ELSE 'IMPORTANT' END;
        CASE k
            WHEN 'surname' THEN
                v_old := s.surname;
                IF v_new IS NULL OR length(v_new) > 80 OR v_new !~ '^[A-Za-z][A-Za-z'' .-]*$' THEN
                    RAISE EXCEPTION 'STU_EDIT_NAME: a surname is letters, with a hyphen, apostrophe or space, up to 80' USING ERRCODE = '23514';
                END IF;
                v_new := upper(v_new);
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET surname = v_new WHERE id = p_student; END IF;
            WHEN 'other_names' THEN
                v_old := s.other_names;
                IF v_new IS NULL OR length(v_new) > 120 OR v_new !~ '^[A-Za-z][A-Za-z'' .-]*$' THEN
                    RAISE EXCEPTION 'STU_EDIT_NAME: other names are letters, with a hyphen, apostrophe or space, up to 120' USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET other_names = v_new WHERE id = p_student; END IF;
            WHEN 'sex' THEN
                v_old := s.sex;
                v_new := upper(v_new);
                IF v_new IS NULL OR v_new NOT IN ('F', 'M') THEN
                    RAISE EXCEPTION 'STU_EDIT_SEX: sex is F or M' USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET sex = v_new WHERE id = p_student; END IF;
            WHEN 'date_of_birth' THEN
                v_old := s.date_of_birth::text;
                IF v_new IS NULL OR v_new !~ '^\d{4}-\d{2}-\d{2}$' THEN
                    RAISE EXCEPTION 'STU_EDIT_DOB: a date of birth is YYYY-MM-DD' USING ERRCODE = '23514';
                END IF;
                IF v_new::date < DATE '1930-01-01' OR v_new::date > (current_date - interval '10 years')::date THEN
                    RAISE EXCEPTION 'STU_EDIT_DOB: % is not a date of birth for a student', v_new USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET date_of_birth = v_new::date WHERE id = p_student; END IF;
            WHEN 'jamb_reg_no' THEN
                v_old := s.jamb_reg_no;
                v_new := upper(regexp_replace(coalesce(v_new, ''), '\s', '', 'g'));
                IF v_new !~ '^[0-9]{8,14}[A-Z]{2}$' THEN
                    RAISE EXCEPTION 'STU_EDIT_JAMB: a JAMB registration number is eight to fourteen digits and two letters' USING ERRCODE = '23514';
                END IF;
                -- another person's: the same number on one person's other enrolment is that person's own
                SELECT x.id INTO v_other FROM people.student x
                 WHERE upper(x.jamb_reg_no) = v_new AND x.id <> p_student AND x.duplicate_of IS NULL
                   AND (s.person_id IS NULL OR x.person_id IS DISTINCT FROM s.person_id) LIMIT 1;
                IF v_other IS NOT NULL THEN
                    RAISE EXCEPTION 'STU_EDIT_JAMB_TAKEN: % is another student''s JAMB registration number', v_new USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET jamb_reg_no = v_new WHERE id = p_student; END IF;
            WHEN 'admission_no' THEN
                v_old := s.admission_no;
                v_new := upper(v_new);
                IF v_new IS NULL OR v_new !~ '^MOAUM/ADM/[0-9]{2}/[0-9]{6}$' THEN
                    RAISE EXCEPTION 'STU_EDIT_ADMISSION_NO: an admission number is MOAUM/ADM/YY/NNNNNN' USING ERRCODE = '23514';
                END IF;
                IF EXISTS (SELECT 1 FROM people.student x WHERE x.admission_no = v_new AND x.id <> p_student) THEN
                    RAISE EXCEPTION 'STU_EDIT_ADMISSION_TAKEN: % is another student''s admission number', v_new USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET admission_no = v_new WHERE id = p_student; END IF;
            WHEN 'entry_session' THEN
                v_old := s.entry_session;
                IF v_new IS NULL OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_new) THEN
                    RAISE EXCEPTION 'STU_EDIT_SESSION: % is not a session on the calendar', coalesce(v_new, 'nothing') USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET entry_session = v_new WHERE id = p_student; END IF;
            WHEN 'entry_mode' THEN
                v_old := s.entry_mode;
                v_new := upper(v_new);
                IF v_new IS NULL OR v_new NOT IN ('UTME', 'DIRECT_ENTRY', 'TRANSFER', 'POSTGRADUATE', 'JUPEB', 'SANDWICH', 'CCE') THEN
                    RAISE EXCEPTION 'STU_EDIT_ENTRY_MODE: an entry mode is UTME, DIRECT_ENTRY, TRANSFER, POSTGRADUATE, JUPEB, SANDWICH or CCE' USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET entry_mode = v_new WHERE id = p_student; END IF;
            WHEN 'entry_level' THEN
                v_old := s.entry_level::text;
                SELECT p.final_level INTO v_final FROM ref.programme p WHERE p.code = s.programme_code;
                IF v_new IS NULL OR v_new !~ '^[1-9]00$' OR v_new::int > coalesce(v_final, 900) THEN
                    RAISE EXCEPTION 'STU_EDIT_ENTRY_LEVEL: an entry level is one of the programme''s levels (100 to %)', coalesce(v_final, 900) USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET entry_level = v_new::int WHERE id = p_student; END IF;
            WHEN 'study_mode' THEN
                v_old := s.study_mode;
                v_new := upper(v_new);
                IF v_new IS NOT NULL AND v_new NOT IN ('FULL_TIME', 'PART_TIME', 'SANDWICH', 'EVENING', 'WEEKEND', 'DISTANCE_LEARNING', 'OTHER') THEN
                    RAISE EXCEPTION 'STU_EDIT_STUDY_MODE: % is not a study mode', v_new USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET study_mode = v_new WHERE id = p_student; END IF;
            WHEN 'centre_code' THEN
                v_old := s.centre_code;
                v_new := upper(v_new);
                IF v_new IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ref.centre c WHERE c.code = v_new) THEN
                    RAISE EXCEPTION 'STU_EDIT_CENTRE: % is not one of the University''s centres', v_new USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET centre_code = v_new WHERE id = p_student; END IF;
            WHEN 'curriculum_track' THEN
                v_old := s.curriculum_track;
                IF v_new IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.curriculum_track t WHERE t.code = v_new) THEN
                    RAISE EXCEPTION 'STU_EDIT_TRACK: % is not a curriculum track', v_new USING ERRCODE = '23514';
                END IF;
                IF v_new IS DISTINCT FROM v_old THEN UPDATE people.student SET curriculum_track = v_new WHERE id = p_student; END IF;
        END CASE;
        IF v_new IS DISTINCT FROM v_old THEN
            v_refs := v_refs || jsonb_build_object('field', k, 'from', v_old, 'to', v_new, 'severity', v_sev,
                'reference', people.student_edit_note(p_student, v_section, k, v_old, v_new, p_reason, v_sev, 'EDIT',
                                                      p_effective_session, p_effective_semester, p_evidence));
        END IF;
    END LOOP;
    IF jsonb_array_length(v_refs) = 0 THEN
        RAISE EXCEPTION 'STU_EDIT_NOTHING: every value given is the record''s own already' USING ERRCODE = '23514';
    END IF;
    RETURN jsonb_build_object('changed', jsonb_array_length(v_refs), 'edits', v_refs, 'version', people.student_edit_version(p_student));
END $$;
COMMENT ON FUNCTION people.student_edit_apply(uuid, jsonb, text, text, boolean, text, integer, text) IS
  'V642: the identity, admission and placement corrections the Academic Office makes on the student edit page — all checked, then all written, or none: the version read must be the record''s own (STU_EDIT_STALE otherwise), the office must hold each field''s permission, the reason must say why, and a JAMB or admission number needs confirming. Each changed field is kept on people.student_edit under its STU-EDIT reference; the audit spine keeps the row before and after.';

-- ── the record's history of changes, from every workflow that changes it: the edits, the status changes, the programme swaps,
--    the level changes, the matriculation corrections, the graduation reconciliations and the classification decisions ──
CREATE OR REPLACE FUNCTION people.student_edit_history(p_student uuid)
RETURNS TABLE (at timestamptz, reference text, change_type text, severity text, section text, field text, old_value text, new_value text,
               reason text, by_name text, office text, source text)
LANGUAGE sql
STABLE
AS $$
    SELECT e.at, e.reference, e.change_type, e.severity, e.section, e.field, e.old_value, e.new_value, e.reason,
           helpdesk.person_name(e.actor), e.actor_office, 'Academic Office Student Edit'
      FROM people.student_edit e WHERE e.student_id = p_student
    UNION ALL
    SELECT sc.effective_on::timestamptz, NULL, 'STATUS', 'CRITICAL', 'STATUS', 'status', sc.from_status, sc.to_status,
           coalesce(nullif(btrim(coalesce(sc.reason, '')), '') || ' (' || sc.instrument || ')', sc.instrument), NULL, NULL, 'Status change'
      FROM people.status_change sc
     WHERE sc.student_id = p_student
       AND NOT EXISTS (SELECT 1 FROM people.student_edit e WHERE e.related_kind = 'status_change' AND e.related_id = sc.id)
    UNION ALL
    SELECT ps.decided_at, ps.swap_ref, 'PROGRAMME', 'IMPORTANT', 'PLACEMENT', 'programme',
           ps.from_programme || ' · ' || ps.from_level || ' Level', ps.to_programme || ' · ' || ps.to_level || ' Level', ps.reason,
           helpdesk.person_name(ps.prepared_by), ps.prepared_office, 'Programme swap (' || lower(ps.kind) || ')'
      FROM people.programme_swap ps WHERE ps.student_id = p_student AND ps.status = 'COMPLETED'
    UNION ALL
    SELECT cd.decided_at, cd.batch_ref, 'LEVEL', 'IMPORTANT', 'LEVEL', 'current_level', cd.previous_level::text, cd.new_level::text, cd.reason,
           helpdesk.person_name(cd.officer), cd.actor_office, 'Level change (' || coalesce(cd.rule, 'decision') || ')'
      FROM people.cohort_decision cd
     WHERE cd.student_id = p_student AND cd.new_level IS NOT NULL
       AND (cd.previous_level IS DISTINCT FROM cd.new_level OR cd.rule = 'LEVEL_SPILLOVER_YEAR')
       AND NOT EXISTS (SELECT 1 FROM people.student_edit e WHERE e.related_kind = 'cohort_decision' AND e.related_id = cd.id)
    UNION ALL
    SELECT coalesce(mc.completed_at, mc.decided_at), mc.ref, 'MATRICULATION', 'CRITICAL', 'MATRICULATION', 'matric_no', mc.old_no, mc.new_no, mc.reason,
           helpdesk.person_name(mc.decided_by), mc.decided_office, 'Matriculation correction'
      FROM people.matric_correction mc WHERE mc.student_id = p_student AND mc.state = 'COMPLETED'
    UNION ALL
    SELECT g.reconciled_at, g.batch_ref, 'GRADUATION', 'CRITICAL', 'GRADUATION', 'status', g.previous_status, g.new_status, g.reason,
           helpdesk.person_name(g.reconciled_by), g.actor_office, 'Graduation reconciliation'
      FROM people.graduation_reconciliation g WHERE g.student_id = p_student
    UNION ALL
    SELECT d.decided_at, NULL, 'CLASSIFICATION', 'IMPORTANT', 'CLASSIFICATION', 'programme_type',
           lag(d.programme_type || coalesce(' · ' || d.admission_route, '')) OVER (ORDER BY d.decided_at),
           d.programme_type || coalesce(' · ' || d.admission_route, ''), d.reason, helpdesk.person_name(d.decided_by), d.decided_office,
           'Student classification'
      FROM people.classification_decision d WHERE d.student_id = p_student
$$;
COMMENT ON FUNCTION people.student_edit_history(uuid) IS
  'V642: every change of a student''s record, from the workflow that made it — the student edit page''s own edits (STU-EDIT references), status changes, completed programme swaps, level changes, completed matriculation corrections, graduation reconciliations and classification decisions — one row each, newest filtered and paged by the API. A level or status change made on the edit page is shown once, under its STU-EDIT reference.';

CREATE OR REPLACE FUNCTION people.support_set_level(p_student uuid, p_action text, p_level integer, p_expected integer, p_reason text, p_session text, p_semester integer, p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_action text := upper(btrim(coalesce(p_action, '')));
        s people.student; o jsonb; v_target int; v_refusal text; v_last people.cohort_decision; ap people.academic_position; v_id uuid; v_rule text; v_carried jsonb;
BEGIN
    -- V591: the Students Account Officer holds the level desk beside ICT Support
    IF coalesce(v_office, '') NOT IN ('ictagent', 'helpdeskhead', 'ict', 'admin', 'super', 'studentaccounts', 'academic', 'registrar', 'dregistrar') THEN
        RAISE EXCEPTION 'LEVEL_SUPPORT_OFFICE: a level is changed by ICT Support, the Students Account Officer, the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF v_action NOT IN ('PROGRESS', 'CORRECTION') THEN
        RAISE EXCEPTION 'LEVEL_ACTION: a level is progressed (PROGRESS) or corrected (CORRECTION)' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL OR length(v_reason) < 10 THEN
        RAISE EXCEPTION 'LEVEL_REASON: say why the level is changed, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    -- one change at a time on a student: the row is held until the change is written
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEVEL_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    o := people.level_options(p_student);
    v_target := CASE WHEN v_action = 'PROGRESS' THEN (o->>'nextLevel')::int ELSE p_level END;
    v_rule := CASE WHEN v_action = 'PROGRESS' THEN 'LEVEL_PROGRESS' ELSE 'LEVEL_CORRECTION' END;

    -- the level read on the screen is no longer the record's: the same change a moment ago by the same person is that change,
    -- anything else is refused, so a stale screen never moves a student twice
    IF p_expected IS DISTINCT FROM s.current_level THEN
        SELECT * INTO v_last FROM people.cohort_decision d
         WHERE d.student_id = p_student AND d.rule IN ('LEVEL_PROGRESS', 'LEVEL_CORRECTION') ORDER BY d.decided_at DESC LIMIT 1;
        IF v_last.id IS NOT NULL AND v_last.decided_at > now() - interval '1 minute' AND v_last.officer IS NOT DISTINCT FROM v_actor
           AND v_last.previous_level = p_expected AND v_last.new_level = s.current_level
           AND v_last.rule = v_rule AND (v_action = 'PROGRESS' OR p_level = s.current_level) THEN
            RETURN jsonb_build_object('alreadyDone', true, 'previousLevel', v_last.previous_level, 'newLevel', v_last.new_level, 'decisionId', v_last.id,
                                      'action', v_last.rule);
        END IF;
        RAISE EXCEPTION 'LEVEL_CHANGED: the record''s level is now %, not %; read the student again', s.current_level, coalesce(p_expected::text, 'what was shown')
            USING ERRCODE = '23514';
    END IF;

    v_refusal := CASE WHEN v_action = 'PROGRESS' THEN o->>'progressRefusal' ELSE o->>'correctRefusal' END;
    IF v_refusal IS NOT NULL THEN RAISE EXCEPTION '%', v_refusal USING ERRCODE = '23514'; END IF;
    IF v_action = 'PROGRESS' AND p_level IS NOT NULL AND p_level IS DISTINCT FROM v_target THEN
        RAISE EXCEPTION 'LEVEL_NOT_NEXT: the next level after % is %, not %; a different level is a correction', s.current_level, v_target, p_level USING ERRCODE = '23514';
    END IF;
    IF v_target IS NULL OR NOT (v_target = ANY (SELECT jsonb_array_elements_text(o->'levels')::int)) THEN
        RAISE EXCEPTION 'LEVEL_NOT_IN_PROGRAMME: % is not one of the levels of the student''s programme (%)', coalesce(v_target::text, 'no level'),
            (SELECT string_agg(x, ', ') FROM jsonb_array_elements_text(o->'levels') x) USING ERRCODE = '23514';
    END IF;
    IF v_target = s.current_level THEN
        RAISE EXCEPTION 'LEVEL_UNCHANGED: the student is already at % Level', v_target USING ERRCODE = '23514';
    END IF;

    PERFORM set_config('moaum.reason', v_reason, true);
    SELECT * INTO ap FROM people.academic_position WHERE student_id = p_student;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                        previous_level, new_level, rule, reason, officer, actor_office, session, semester, ticket_id)
    VALUES (p_student, s.status, s.status, s.status, ap.classification, ap.entry_session, ap.effective_cohort,
            s.current_level, v_target, v_rule, v_reason, v_actor, v_office,
            p_session, p_semester, p_ticket)
    RETURNING id INTO v_id;
    UPDATE people.student SET current_level = v_target WHERE id = p_student;
    -- V641: a correction carries into the session's course registrations and enrolment still at the level corrected from — the
    -- level the examination card, the GST & EPS permit, the receipt, the results and the transcript read for the session
    IF v_action = 'CORRECTION' THEN
        v_carried := people.carry_level_to_session(p_student, s.current_level, v_target, coalesce(p_session, policy.university_current_session()));
    END IF;
    -- V628: below the final level the student is not past the programme's length, so an expected completion pinned before this
    -- session (by the level desk's spillover year or the Registry) no longer stands
    IF v_target < (o->>'finalLevel')::int AND EXISTS (
            SELECT 1 FROM people.completion_override c
             WHERE c.student_id = p_student
               AND policy.session_year(c.expected_completion) < policy.session_year(coalesce(ap.current_session, policy.university_current_session()))) THEN
        PERFORM people.set_completion_override(p_student, NULL, 'Level corrected to ' || v_target || ', below the final level: ' || v_reason);
    END IF;
    RETURN jsonb_build_object('alreadyDone', false, 'previousLevel', s.current_level, 'newLevel', v_target, 'decisionId', v_id, 'action', v_rule,
                              'carried', v_carried);
END $function$;

CREATE OR REPLACE FUNCTION people.support_set_spillover(p_student uuid, p_year integer, p_expected integer, p_reason text, p_session text, p_semester integer, p_ticket uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        s people.student; o jsonb; v_final int; v_completion text; v_word text; v_last people.cohort_decision; ap people.academic_position; v_id uuid;
BEGIN
    IF coalesce(v_office, '') NOT IN ('ictagent', 'helpdeskhead', 'ict', 'admin', 'super', 'studentaccounts', 'academic', 'registrar', 'dregistrar') THEN
        RAISE EXCEPTION 'LEVEL_SUPPORT_OFFICE: a level is changed by ICT Support, the Students Account Officer, the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF p_year IS NULL OR p_year NOT IN (0, 1, 2) THEN
        RAISE EXCEPTION 'LEVEL_SPILLOVER_YEAR: the desk sets spillover year 1 (SP1), year 2 (SP2), or the final year (0)' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL OR length(v_reason) < 10 THEN
        RAISE EXCEPTION 'LEVEL_REASON: say why the level is changed, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'LEVEL_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    o := people.level_options(p_student);
    v_final := (o->>'finalLevel')::int;
    v_word := CASE p_year WHEN 0 THEN 'the final year' ELSE 'SP' || p_year END;

    -- a stale screen never moves a student twice: the same act a moment ago by the same person is that act
    IF p_expected IS DISTINCT FROM s.current_level THEN
        SELECT * INTO v_last FROM people.cohort_decision d WHERE d.student_id = p_student AND d.rule = 'LEVEL_SPILLOVER_YEAR'
         ORDER BY d.decided_at DESC LIMIT 1;
        IF v_last.id IS NOT NULL AND v_last.decided_at > now() - interval '1 minute' AND v_last.officer IS NOT DISTINCT FROM v_actor
           AND v_last.previous_level = p_expected AND v_last.new_level = s.current_level AND v_last.reason LIKE v_word || ' %' THEN
            RETURN jsonb_build_object('alreadyDone', true, 'previousLevel', v_last.previous_level, 'newLevel', v_last.new_level, 'decisionId', v_last.id,
                                      'action', v_last.rule, 'spilloverYear', p_year);
        END IF;
        RAISE EXCEPTION 'LEVEL_CHANGED: the record''s level is now %, not %; read the student again', s.current_level, coalesce(p_expected::text, 'what was shown')
            USING ERRCODE = '23514';
    END IF;
    IF o->>'correctRefusal' IS NOT NULL THEN RAISE EXCEPTION '%', o->>'correctRefusal' USING ERRCODE = '23514'; END IF;
    IF (o->>'postgraduate')::boolean THEN
        RAISE EXCEPTION 'LEVEL_PG_SPILLOVER: a postgraduate student has no spillover year on this desk' USING ERRCODE = '23514';
    END IF;
    SELECT (c->>'completion') INTO v_completion FROM jsonb_array_elements(o->'spilloverChoices') c WHERE (c->>'year')::int = p_year;
    IF v_completion IS NULL THEN
        RAISE EXCEPTION 'LEVEL_SPILLOVER_UNAVAILABLE: % cannot be set for this student now (already so, or no session on the calendar to count it from)', v_word
            USING ERRCODE = '23514';
    END IF;

    PERFORM set_config('moaum.reason', v_reason, true);
    SELECT * INTO ap FROM people.academic_position WHERE student_id = p_student;
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                        previous_level, new_level, rule, reason, officer, actor_office, session, semester, ticket_id)
    VALUES (p_student, s.status, s.status, s.status, ap.classification, ap.entry_session, ap.effective_cohort,
            s.current_level, v_final, 'LEVEL_SPILLOVER_YEAR',
            v_word || ' (expected completion pinned to ' || v_completion || '): ' || v_reason, v_actor, v_office, p_session, p_semester, p_ticket)
    RETURNING id INTO v_id;
    IF s.current_level IS DISTINCT FROM v_final THEN
        UPDATE people.student SET current_level = v_final WHERE id = p_student;
    END IF;
    PERFORM people.set_completion_override(p_student, v_completion, v_word || ' set on the level desk: ' || v_reason);
    PERFORM people.refresh_academic_position(p_student);
    RETURN jsonb_build_object('alreadyDone', false, 'previousLevel', s.current_level, 'newLevel', v_final, 'decisionId', v_id,
                              'action', 'LEVEL_SPILLOVER_YEAR', 'spilloverYear', p_year, 'expectedCompletion', v_completion,
                              'spilloverState', (SELECT spillover_state FROM people.academic_position WHERE student_id = p_student));
END $function$;

COMMIT;

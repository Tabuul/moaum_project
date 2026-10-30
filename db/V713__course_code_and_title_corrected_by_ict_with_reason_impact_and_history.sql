-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V713 · A course's code and title corrected by the Director of ICT and the ICT Support Desk: one course, its reason, its impact
--         shown first, never over another person's change, and every change kept
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's brief of 30 October 2026 ("ICT Director & ICT Support — course code and course title change management"),
--  read against what stands: one canonical course (catalogue.course, its stable id; the code its key, V332), a rename that carries
--  every class, registration, result, binding, CBT examination and posting with it (V332/V333: 17 keys follow the code), a course
--  of the same code under another title kept as a separate course (V646), the course's usage (V332), its history from the audit
--  spine (V445), and the support desk changing a course within its postings on a ticket (V471, Oct 2026). What was missing:
--
--  1 · A change of code or title had no reason of its own: the course page sent "CSC 401 renamed" as the reason. Now
--      catalogue.correct_course takes the reason (one of the University's list) and remarks, and refuses without them.
--  2 · Two people correcting one course: the second silently overwrote the first. A correction names the version it was made
--      against (catalogue.course_version) and is refused, COURSE_CHANGED_SINCE, when the course has changed since.
--  3 · A rename onto a code another course holds under another title was refused ("a code is unique across the University"),
--      though the University keeps the same code under another title as a separate course (V646). A correction now keeps it as
--      that separate course (catalogue.variant_key); the same code and the same title is the same course and is refused —
--      a correction never merges (the duplicates desk does, V386).
--  4 · A renamed course lost the history it had under its old code: the audit spine keys a course by its code. Every change of
--      code or title is now written to catalogue.course_change (never altered, never removed) whoever makes it — the correction,
--      the department's desk, an upload, a migration — with the reason; the changes already on the audit spine are copied in;
--      catalogue.course_history reads every code the course has had.
--  5 · A corrected title reached only the classes nothing hung on (V338), so results, broadsheets and transcripts kept the old
--      title. A correction now reaches every class of the course too unless the person correcting keeps the past classes' title
--      (p_past_classes false — a course renamed by the curriculum, not mistyped). Units are never touched by a correction.
--  6 · The impact before the change: catalogue.course_impact (registrations, this session's, students, carry-overs, results and
--      published results, score sheets, classes, lecturer allocations, programme bindings, CBT examinations, questions, deferred
--      and old-portal results, broadsheet omissions, GST/EPS office), and catalogue.correction_check (the courses already under the
--      new code, the courses of the same title, what refuses it) — both changing nothing.
--  7 · The ICT Support Desk's postings may carry EDIT_COURSE_CODE and EDIT_COURSE_TITLE (EDIT_COURSES carries both).
--  8 · A broadsheet omission (V624, held by code) follows a rename too (catalogue.follow_code, used by rename_course).
--  Who may correct is the API's: the Director of ICT and the Head of the ICT Support Desk any course, an agent with the capability
--  within the posting's faculties and departments, the academic offices and the School as they edit courses today.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V713: a course''s code and title corrected with its reason, its impact and its history (the University''s brief of 30 October 2026)', true);

-- ── 1 · the support desk's capabilities: the code, the title ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE',
                 'VIEW_PROGRAMME_STRUCTURE', 'EDIT_COURSES', 'BIND_COURSES', 'MANAGE_PREREQUISITES',
                 'PROGRESS_LEVEL', 'CORRECT_LEVEL', 'VIEW_LEVEL_HISTORY', 'VIEW_RESET_HISTORY',
                 'VIEW_STUDENT_PORTAL',
                 -- V559: many students reset to the default credential in one operation, within the posting's scope
                 'BULK_RESET_PASSWORD',
                 -- V582: the students of the login and password tickets the agent ticks, reset from the desk's queue
                 'BULK_RESET_FROM_TICKETS',
                 -- V713: a course's code, a course's title — corrected with a reason (EDIT_COURSES carries both)
                 'EDIT_COURSE_CODE', 'EDIT_COURSE_TITLE']
$function$;

-- ── 2 · every change of a course's code or title, kept ─────────────────────────────────────────────────────────────────────
CREATE TABLE catalogue.course_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id      uuid NOT NULL,                     -- the course's stable id; no key, so a course merged away (V386) keeps its trail
    field          text NOT NULL CHECK (field IN ('CODE', 'TITLE')),
    old_value      text NOT NULL,
    new_value      text NOT NULL,
    reason_kind    text NULL CHECK (reason_kind IN ('OFFICIAL_CORRECTION', 'TYPOGRAPHICAL_ERROR', 'ACADEMIC_OFFICE_INSTRUCTION',
                                                    'CURRICULUM_CORRECTION', 'MIGRATION_CORRECTION', 'DUPLICATE_DATA_CORRECTION',
                                                    'COURSE_APPROVAL_UPDATE', 'LEGACY_DATA_CORRECTION', 'ICT_SUPPORT_CORRECTION', 'OTHER')),
    remarks        text NULL CHECK (remarks IS NULL OR length(remarks) <= 2000),
    ticket_id      uuid NULL REFERENCES helpdesk.ticket (id),
    past_classes   boolean NULL,                      -- a title: whether the classes already registered or examined took it too
    source         text NOT NULL CHECK (source IN ('CORRECTION', 'EDIT', 'MIGRATION', 'AUDIT')),
    reason         text NULL,                         -- the request's own reason, as the audit spine has it
    changed_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    changed_by     uuid NULL,
    changed_office text NULL,
    CHECK (source <> 'CORRECTION' OR reason_kind IS NOT NULL)
);
CREATE INDEX ix_course_change_course ON catalogue.course_change (course_id, changed_at DESC);
CREATE INDEX ix_course_change_at ON catalogue.course_change (changed_at DESC);
CREATE INDEX ix_course_change_values ON catalogue.course_change (field, old_value);
COMMENT ON TABLE catalogue.course_change IS
  'V713: every change of a course''s code or title — by a correction (its reason and remarks, the ticket, whether past classes took the title), '
  'by the department''s desk, an upload or a migration (EDIT, MIGRATION: the request''s reason), or before V713 (AUDIT, copied from the audit spine). '
  'Never altered or removed; read by catalogue.course_history and the course changes report.';

CREATE OR REPLACE FUNCTION catalogue.course_change_kept() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    RAISE EXCEPTION 'COURSE_CHANGE_KEPT: a course''s change history is kept as it was written; it is never altered or removed' USING ERRCODE = '23514';
END $fn$;
CREATE TRIGGER trg_course_change_kept BEFORE UPDATE OR DELETE ON catalogue.course_change
FOR EACH ROW EXECUTE FUNCTION catalogue.course_change_kept();

-- the words of a reason
CREATE OR REPLACE FUNCTION catalogue.course_change_reason_words(p_kind text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE p_kind
        WHEN 'OFFICIAL_CORRECTION' THEN 'Official course correction'
        WHEN 'TYPOGRAPHICAL_ERROR' THEN 'Typographical error'
        WHEN 'ACADEMIC_OFFICE_INSTRUCTION' THEN 'Academic Office instruction'
        WHEN 'CURRICULUM_CORRECTION' THEN 'Curriculum correction'
        WHEN 'MIGRATION_CORRECTION' THEN 'Migration correction'
        WHEN 'DUPLICATE_DATA_CORRECTION' THEN 'Duplicate data correction'
        WHEN 'COURSE_APPROVAL_UPDATE' THEN 'Course approval update'
        WHEN 'LEGACY_DATA_CORRECTION' THEN 'Legacy data correction'
        WHEN 'ICT_SUPPORT_CORRECTION' THEN 'ICT Support correction'
        WHEN 'OTHER' THEN 'Other'
    END
$$;

-- the changes already on the audit spine, before this trail existed (a rename's entry sits under the new code; the course's id is in both states)
INSERT INTO catalogue.course_change (course_id, field, old_value, new_value, source, reason, changed_at, changed_by, changed_office)
SELECT (e.after_state->>'id')::uuid, f.field, f.o, f.n, 'AUDIT', e.reason, e.occurred_at, e.actor_id, e.actor_office
  FROM audit.entries e
 CROSS JOIN LATERAL (VALUES ('CODE', e.before_state->>'code', e.after_state->>'code'),
                            ('TITLE', e.before_state->>'title', e.after_state->>'title')) AS f(field, o, n)
 WHERE e.subject_type = 'catalogue.course' AND e.action = 'UPDATE'
   AND f.o IS NOT NULL AND f.n IS NOT NULL AND f.o IS DISTINCT FROM f.n
   AND e.after_state->>'id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 ORDER BY e.occurred_at;

SELECT audit.attach('catalogue.course_change');
GRANT SELECT ON catalogue.course_change TO app_auditor, app_acrecords, app_reporting;

-- whoever changes a code or a title, the trail has it: a correction names its reason (set by correct_course), anything else the request's
CREATE OR REPLACE FUNCTION catalogue.course_change_record() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_actor  uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_src    text := nullif(current_setting('moaum.course_change_source', true), '');
        v_kind   text := nullif(current_setting('moaum.course_change_kind', true), '');
        v_rem    text := nullif(current_setting('moaum.course_change_remarks', true), '');
        v_ticket uuid := nullif(current_setting('moaum.course_change_ticket', true), '')::uuid;
        v_past   boolean := nullif(current_setting('moaum.course_change_past', true), '')::boolean;
        v_reason text := nullif(current_setting('moaum.reason', true), '');
BEGIN
    IF v_src IS NULL THEN
        v_src := CASE WHEN v_actor = '00000000-0000-0000-0000-000000000000' THEN 'MIGRATION' ELSE 'EDIT' END;
        v_kind := NULL; v_rem := NULL; v_ticket := NULL; v_past := NULL;
    END IF;
    IF NEW.code IS DISTINCT FROM OLD.code THEN
        INSERT INTO catalogue.course_change (course_id, field, old_value, new_value, reason_kind, remarks, ticket_id, source, reason, changed_by, changed_office)
        VALUES (NEW.id, 'CODE', OLD.code, NEW.code, v_kind, v_rem, v_ticket, v_src, v_reason, v_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    IF NEW.title IS DISTINCT FROM OLD.title THEN
        INSERT INTO catalogue.course_change (course_id, field, old_value, new_value, reason_kind, remarks, ticket_id, past_classes, source, reason, changed_by, changed_office)
        VALUES (NEW.id, 'TITLE', OLD.title, NEW.title, v_kind, v_rem, v_ticket, coalesce(v_past, false), v_src, v_reason, v_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN NULL;
END $fn$;
CREATE TRIGGER trg_course_change_record AFTER UPDATE OF code, title ON catalogue.course
FOR EACH ROW EXECUTE FUNCTION catalogue.course_change_record();
COMMENT ON FUNCTION catalogue.course_change_record() IS
  'V713: a change of a course''s code or title is written to catalogue.course_change, whoever makes it — a correction with its reason, anything else with the request''s.';

-- ── 3 · the version a correction is made against ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.course_version(c catalogue.course) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT md5(c.code || '|' || c.title || '|' || coalesce(extract(epoch FROM c.updated_at)::text, ''))
$$;
COMMENT ON FUNCTION catalogue.course_version(catalogue.course) IS
  'V713: the version of a course as a screen read it — its code, its title and when it was last changed; a correction made against an older version is refused.';

-- ── 4 · the codes a rename leaves behind in records held by code alone ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.follow_code(p_old text, p_new text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
    UPDATE college.posting_course SET course_code = p_new WHERE course_code = p_old;
    UPDATE assessment.legacy_result_holding SET course_code = p_new WHERE course_code = p_old;
    UPDATE admissions.pg_legacy_holding SET course_code = p_new WHERE course_code = p_old;
    UPDATE assessment.broadsheet_omission SET course_code = p_new WHERE course_code = p_old;   -- V713: V624's omission follows too
END $fn$;
COMMENT ON FUNCTION catalogue.follow_code(text, text) IS
  'V713: the records that name a course by its code without a key (clinical postings, old-portal results and PG results held, broadsheet omissions) follow a rename; every keyed record follows by itself.';

CREATE OR REPLACE FUNCTION catalogue.rename_course(p_old text, p_new text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_old text := upper(btrim(coalesce(p_old, ''))); v_new text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is renamed by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_old) THEN RAISE EXCEPTION 'no course is coded %', p_old USING ERRCODE = '23503'; END IF;
    v_new := catalogue.normal_code(p_new);
    IF v_new IS NULL THEN
        RAISE EXCEPTION 'CAT_CODE: a course code is three letters and three digits (CSC 311), or a prefix, a hyphen, the subject and the number (MOAU-CHM 101) — % fits neither', coalesce(p_new, '')
            USING ERRCODE = '23514', HINT = 'Letters, digits, one space before the number, a hyphen after the prefix.';
    END IF;
    IF v_new = v_old THEN RETURN v_new; END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_new) THEN
        RAISE EXCEPTION 'a course with the code % already exists', v_new USING ERRCODE = '23505',
            HINT = 'Use "Change code or title" on the course: a course of that code under another title is kept as a separate course; the same course under two codes is merged on the duplicates desk.';
    END IF;
    UPDATE catalogue.course SET code = v_new WHERE code = v_old;
    PERFORM catalogue.follow_code(v_old, v_new);
    RETURN v_new;
END $$;
COMMENT ON FUNCTION catalogue.rename_course(text, text) IS 'V332/V333, V713: change a course''s code to any form the catalogue keys — the same course (its id unchanged); its bindings, offerings, registrations, results, questions, CBT examinations, deferred courses, postings, old-portal results and broadsheet omissions follow the new code; the change is on catalogue.course_change.';

-- ── 5 · what hangs on a course, before its code or title is corrected ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.course_impact(p_code text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT * FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, '')))),
    cls AS (SELECT o.* FROM catalogue.offering o JOIN c ON o.course_code = c.code),
    ent AS (SELECT e.entry_type, e.status, cr.student_id, cr.session
              FROM registration.entry e JOIN cls ON cls.id = e.offering_id
              JOIN registration.course_registration cr ON cr.id = e.registration_id),
    sc AS (SELECT sh.published_at FROM assessment.score s JOIN assessment.score_sheet sh ON sh.id = s.sheet_id JOIN cls ON cls.id = sh.offering_id),
    held AS (SELECT cls.id, cls.title FROM cls
              WHERE EXISTS (SELECT 1 FROM registration.entry e WHERE e.offering_id = cls.id)
                 OR EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.offering_id = cls.id))
    SELECT jsonb_build_object(
        'registrations', (SELECT count(*) FROM ent),
        'currentRegistrations', (SELECT count(*) FROM ent WHERE ent.session = policy.university_current_session() AND ent.status NOT IN ('DROPPED', 'WITHDRAWN')),
        'currentSession', policy.university_current_session(),
        'students', (SELECT count(DISTINCT ent.student_id) FROM ent),
        'carryOvers', (SELECT count(*) FROM ent WHERE ent.entry_type = 'CARRYOVER'),
        'results', (SELECT count(*) FROM sc),
        'publishedResults', (SELECT count(*) FROM sc WHERE sc.published_at IS NOT NULL),
        'scoreSheets', (SELECT count(*) FROM assessment.score_sheet sh JOIN cls ON cls.id = sh.offering_id),
        'classes', (SELECT count(*) FROM cls),
        'lecturerAllocations', (SELECT count(*) FROM cls WHERE cls.lecturer_id IS NOT NULL) + (SELECT count(*) FROM cls WHERE cls.second_examiner_id IS NOT NULL)
                               + (SELECT count(*) FROM catalogue.offering_teacher t JOIN cls ON cls.id = t.offering_id),
        'programmeBindings', (SELECT count(*) FROM catalogue.course_offer co JOIN c ON co.course_code = c.code),
        'programmes', (SELECT count(DISTINCT co.programme_code) FROM catalogue.course_offer co JOIN c ON co.course_code = c.code),
        'cbtExams', (SELECT count(*) FROM assessment.cbt_exam x JOIN c ON x.course_code = c.code),
        'questions', (SELECT count(*) FROM assessment.question q JOIN c ON q.course_code = c.code),
        'deferred', (SELECT count(*) FROM people.deferred_course d JOIN c ON d.course_code = c.code),
        'oldPortalResults', (SELECT count(*) FROM assessment.legacy_result_holding l JOIN c ON l.course_code = c.code),
        'broadsheetOmissions', (SELECT count(*) FROM assessment.broadsheet_omission b JOIN c ON b.course_code = c.code),
        'pastClasses', (SELECT count(*) FROM held),
        'pastClassesOtherTitle', (SELECT count(*) FROM held, c WHERE held.title IS DISTINCT FROM c.title),
        'generalOffice', (SELECT c.general_office FROM c),
        'changes', (SELECT count(*) FROM catalogue.course_change ch JOIN c ON ch.course_id = c.id))
$$;
COMMENT ON FUNCTION catalogue.course_impact(text) IS
  'V713: what hangs on a course — every registration and this session''s, the students, the carry-overs, the results and those published, the score sheets, the classes and their lecturers, the programmes that bind it, CBT examinations, questions, deferred and old-portal results, broadsheet omissions, its GST/EPS office — shown before its code or title is corrected. Changes nothing.';

-- ── 6 · what a correction would be, and why it would be refused — changing nothing ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.correction_check(p_code text, p_new_code text, p_new_title text) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE c catalogue.course; v_code text; v_title text; v_key text; v_sep boolean := false; v_code_changed boolean; v_title_changed boolean;
        r_code text; r_msg text; v_other catalogue.course; v_alias text; v_base text; v_same jsonb; v_titled jsonb;
BEGIN
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, '')));
    IF c.code IS NULL THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    v_title := regexp_replace(btrim(coalesce(p_new_title, c.title)), '\s+', ' ', 'g');
    v_code := CASE WHEN nullif(btrim(coalesce(p_new_code, '')), '') IS NULL THEN catalogue.shown_code(c.code) ELSE catalogue.normal_code(p_new_code) END;
    IF v_code = c.code THEN v_code := catalogue.shown_code(c.code); END IF;   -- the course's own key, typed as it is held, is its code unchanged
    v_key := c.code;
    v_code_changed := v_code IS NOT NULL AND v_code <> catalogue.shown_code(c.code);
    v_title_changed := v_title <> c.title;

    IF v_title = '' THEN
        r_code := 'CAT_TITLE'; r_msg := 'A course has a title; a blank one is not a title.';
    ELSIF length(v_title) > 120 THEN
        r_code := 'CAT_TITLE'; r_msg := 'A course''s title is at most 120 characters.';
    ELSIF v_code IS NULL THEN
        r_code := 'CAT_CODE'; r_msg := format('A course code is three letters and three digits (CSC 311), or a prefix, a hyphen, the subject and the number (MOAU-CHM 101); %s fits neither.', btrim(p_new_code));
    ELSIF NOT v_code_changed AND NOT v_title_changed THEN
        r_code := 'COURSE_UNCHANGED'; r_msg := 'The code and the title are as they stand; nothing would change.';
    END IF;

    IF r_code IS NULL AND v_code_changed THEN
        SELECT a.course_code INTO v_alias FROM catalogue.course_alias a WHERE a.alias_code = v_code;
        SELECT * INTO v_other FROM catalogue.course o
         WHERE catalogue.code_key(o.code) = catalogue.code_key(v_code) AND o.code <> v_code AND o.id <> c.id LIMIT 1;
        v_base := catalogue.session_copy_base(v_code);
        IF v_alias IS NOT NULL THEN
            r_code := 'COURSE_CODE_MERGED'; r_msg := format('%s was merged into %s; the code answers for that course.', v_code, v_alias);
        ELSIF v_other.code IS NOT NULL THEN
            r_code := 'COURSE_DUPLICATE_CODE'; r_msg := format('%s is %s written differently; the pool holds a code once.', v_code, v_other.code);
        ELSIF v_base IS NOT NULL AND EXISTS (SELECT 1 FROM catalogue.course o WHERE catalogue.code_key(o.code) = catalogue.code_key(v_base) AND o.id <> c.id) THEN
            r_code := 'COURSE_SESSION_COPY'; r_msg := format('%s copies %s for a session; a course is held once, for every session.', v_code, v_base);
        ELSIF EXISTS (SELECT 1 FROM catalogue.course o WHERE o.code = v_code AND o.id <> c.id) THEN
            -- the University's rule (V646): the same code under another title is a separate course, under a key of its own
            BEGIN
                v_key := catalogue.variant_key(v_code, c.curriculum);
                v_sep := true;
            EXCEPTION WHEN check_violation THEN
                r_code := 'COURSE_CODE_FULL'; r_msg := format('No further course can be held under %s: it holds its first course and eight more.', v_code);
            END;
        ELSE
            v_key := v_code;
        END IF;
    END IF;

    IF r_code IS NULL THEN
        SELECT * INTO v_other FROM catalogue.course o
         WHERE catalogue.shown_code(o.code) = catalogue.shown_code(v_key) AND catalogue.title_key(o.title) = catalogue.title_key(v_title) AND o.id <> c.id LIMIT 1;
        IF v_other.code IS NOT NULL THEN
            r_code := 'COURSE_SAME_CODE_AND_TITLE';
            r_msg := format('%s — %s is already a course (Course ID %s). The same code and title is the same course; a correction never merges two courses — merge them on the duplicates desk if they are one.',
                            catalogue.shown_code(v_other.code), v_other.title, v_other.id);
        END IF;
    END IF;

    SELECT coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'code', o.code, 'shown', catalogue.shown_code(o.code), 'title', o.title, 'state', o.state,
                                                 'dept_code', o.dept_code, 'dept_name', d.name, 'level', o.level, 'units', o.units,
                                                 'programmes', (SELECT count(*) FROM catalogue.course_offer co WHERE co.course_code = o.code),
                                                 'sameTitle', catalogue.title_key(o.title) = catalogue.title_key(v_title))
                              ORDER BY o.code), '[]'::jsonb)
      INTO v_same
      FROM catalogue.course o LEFT JOIN ref.department d ON d.code = o.dept_code
     WHERE o.id <> c.id AND v_code IS NOT NULL AND catalogue.shown_code(o.code) = v_code;

    SELECT coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'code', x.code, 'shown', catalogue.shown_code(x.code), 'title', x.title, 'state', x.state,
                                                 'dept_code', x.dept_code, 'dept_name', x.dept_name, 'level', x.level, 'units', x.units,
                                                 'possibleDuplicate', x.units = c.units AND x.level = c.level AND x.dept_code IS NOT DISTINCT FROM c.dept_code)
                              ORDER BY x.code), '[]'::jsonb)
      INTO v_titled
      FROM (SELECT o.*, d.name AS dept_name FROM catalogue.course o LEFT JOIN ref.department d ON d.code = o.dept_code
             WHERE o.id <> c.id AND v_title <> '' AND catalogue.title_key(o.title) = catalogue.title_key(v_title)
               AND (v_code IS NULL OR catalogue.shown_code(o.code) <> v_code)
             ORDER BY o.code LIMIT 25) x;

    RETURN jsonb_build_object(
        'id', c.id, 'code', c.code, 'shown', catalogue.shown_code(c.code), 'title', c.title, 'version', catalogue.course_version(c),
        'newCode', v_code, 'newTitle', v_title, 'key', v_key, 'codeChanged', coalesce(v_code_changed, false), 'titleChanged', v_title_changed,
        'separate', v_sep, 'generalOffice', c.general_office,
        'refusal', CASE WHEN r_code IS NULL THEN NULL ELSE jsonb_build_object('code', r_code, 'message', r_msg) END,
        'sameCode', v_same, 'sameTitle', v_titled);
END $$;
COMMENT ON FUNCTION catalogue.correction_check(text, text, text) IS
  'V713: what a correction of a course''s code and title would be — the code as it would be held (or the key of a separate course under a code another course holds, V646), the courses already under that code, those of the same title (possible duplicates: the same units, level and department), and why it would be refused. Changes nothing.';

-- ── 7 · the correction ─────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.correct_course(p_code text, p_new_code text, p_new_title text, p_reason_kind text, p_remarks text,
                                                    p_version text, p_past_classes boolean DEFAULT true, p_ticket uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; c catalogue.course; chk jsonb; v_kind text; v_rem text;
        v_key text; v_title text; v_retitled int := 0; v_shown_was text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is corrected by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF c.code IS NULL THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF p_version IS NULL OR p_version <> catalogue.course_version(c) THEN
        RAISE EXCEPTION 'COURSE_CHANGED_SINCE: % has been updated by another user since you opened it. Reload the latest version before making your change.', catalogue.shown_code(c.code)
            USING ERRCODE = '23514', HINT = 'Reload the course; your change was not saved.';
    END IF;
    v_kind := upper(btrim(coalesce(p_reason_kind, '')));
    IF catalogue.course_change_reason_words(v_kind) IS NULL THEN
        RAISE EXCEPTION 'COURSE_CHANGE_REASON: a change of a course''s code or title is made for a reason — choose one from the list' USING ERRCODE = '23514';
    END IF;
    v_rem := nullif(regexp_replace(btrim(coalesce(p_remarks, '')), '\s+', ' ', 'g'), '');
    IF v_kind = 'OTHER' AND (v_rem IS NULL OR length(v_rem) < 5) THEN
        RAISE EXCEPTION 'COURSE_CHANGE_REASON: "Other" is explained in the remarks' USING ERRCODE = '23514';
    END IF;
    IF v_rem IS NOT NULL AND length(v_rem) > 2000 THEN
        RAISE EXCEPTION 'COURSE_CHANGE_REASON: the remarks are at most 2000 characters' USING ERRCODE = '23514';
    END IF;

    chk := catalogue.correction_check(c.code, p_new_code, p_new_title);
    IF chk->'refusal' IS NOT NULL AND jsonb_typeof(chk->'refusal') = 'object' THEN
        RAISE EXCEPTION '%: %', chk->'refusal'->>'code', chk->'refusal'->>'message' USING ERRCODE = '23514';
    END IF;
    v_key := chk->>'key';
    v_title := chk->>'newTitle';
    v_shown_was := catalogue.shown_code(c.code);

    PERFORM set_config('moaum.course_change_source', 'CORRECTION', true),
            set_config('moaum.course_change_kind', v_kind, true),
            set_config('moaum.course_change_remarks', coalesce(v_rem, ''), true),
            set_config('moaum.course_change_ticket', coalesce(p_ticket::text, ''), true),
            set_config('moaum.course_change_past', CASE WHEN coalesce(p_past_classes, true) THEN 'true' ELSE 'false' END, true);
    -- one statement: the code and the title are judged together by the keys (the same code and title held once, V646)
    UPDATE catalogue.course SET code = v_key, title = v_title WHERE id = c.id;
    IF v_key <> c.code THEN PERFORM catalogue.follow_code(c.code, v_key); END IF;
    -- the classes already registered or examined take the corrected title too, unless they keep theirs; their units never change
    IF v_title <> c.title AND coalesce(p_past_classes, true) THEN
        UPDATE catalogue.offering o SET title = v_title WHERE o.course_code = v_key AND o.title IS DISTINCT FROM v_title;
        GET DIAGNOSTICS v_retitled = ROW_COUNT;
    END IF;
    PERFORM set_config('moaum.course_change_source', '', true), set_config('moaum.course_change_kind', '', true),
            set_config('moaum.course_change_remarks', '', true), set_config('moaum.course_change_ticket', '', true),
            set_config('moaum.course_change_past', '', true);

    SELECT * INTO c FROM catalogue.course WHERE id = c.id;
    RETURN jsonb_build_object('id', c.id, 'code', c.code, 'shown', catalogue.shown_code(c.code), 'title', c.title,
                              'was', v_shown_was, 'wasTitle', chk->>'title', 'separate', (chk->>'separate')::boolean,
                              'classesRetitled', v_retitled, 'version', catalogue.course_version(c),
                              'reason', catalogue.course_change_reason_words(v_kind), 'remarks', v_rem);
END $$;
COMMENT ON FUNCTION catalogue.correct_course(text, text, text, text, text, text, boolean, uuid) IS
  'V713: a course''s code and title corrected in place — the same course (its id unchanged), against the version the person read, for a reason from the list (remarks for Other), '
  'refused as catalogue.correction_check refuses; a code another course holds under another title becomes this course''s own key (V646); the title reaches every class unless p_past_classes is false; '
  'units never change; written to catalogue.course_change with the ticket.';

-- ── 8 · the course's history reads every code it has had ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.course_history(p_code text, p_limit int DEFAULT 200)
RETURNS TABLE (at timestamptz, action text, field text, old_value text, new_value text, actor text, actor_office text, reason text, source text)
LANGUAGE sql STABLE AS $$
    WITH ids AS (
        SELECT c.id FROM catalogue.course c WHERE c.code = p_code
        UNION SELECT a.absorbed_id FROM catalogue.course_alias a WHERE a.course_code = p_code
    ),
    codes AS (
        SELECT p_code AS code
        UNION SELECT a.alias_code FROM catalogue.course_alias a WHERE a.course_code = p_code
        UNION SELECT ch.old_value FROM catalogue.course_change ch WHERE ch.field = 'CODE' AND ch.course_id IN (SELECT id FROM ids)
    ),
    subjects AS (SELECT md5('catalogue.course'::regclass::oid::text || '|' || code)::uuid AS id FROM codes),
    e AS (
        SELECT e.occurred_at, e.action, e.before_state, e.after_state, e.actor_id, e.actor_office, e.reason
          FROM audit.entries e
         WHERE e.subject_type = 'catalogue.course' AND e.subject_id IN (SELECT id FROM subjects)
           -- a code another course took later is that course's history, not this one's
           AND (coalesce(e.after_state->>'id', e.before_state->>'id') IS NULL
                OR coalesce(e.after_state->>'id', e.before_state->>'id') IN (SELECT id::text FROM ids))
         ORDER BY e.occurred_at DESC LIMIT greatest(1, p_limit)
    ),
    changes AS (
        SELECT e.occurred_at, 'CHANGED'::text AS action, k AS field, e.before_state->>k AS old_value, e.after_state->>k AS new_value, e.actor_id, e.actor_office, e.reason
          FROM e, LATERAL jsonb_object_keys(coalesce(e.after_state, '{}'::jsonb)) k
         WHERE e.action = 'UPDATE' AND e.before_state->>k IS DISTINCT FROM e.after_state->>k
           AND k NOT IN ('updated_at', 'updated_by', 'reset_batch_id', 'review_note', 'reviewed_by', 'reviewed_office', 'reviewed_at',
                         'code', 'title')   -- V713: the code and the title from catalogue.course_change, with their reasons
        UNION ALL
        SELECT e.occurred_at, 'CREATED', NULL, NULL, e.after_state->>'code', e.actor_id, e.actor_office, e.reason FROM e WHERE e.action = 'INSERT'
    )
    SELECT ch.occurred_at, ch.action, ch.field, ch.old_value, ch.new_value,
           coalesce(helpdesk.person_name(ch.actor_id), CASE WHEN ch.actor_id = '00000000-0000-0000-0000-000000000000' THEN 'the migration' END, 'Unknown'),
           ch.actor_office, ch.reason, 'AUDIT'
      FROM changes ch
    UNION ALL
    SELECT k.changed_at, 'CHANGED', lower(k.field), k.old_value, k.new_value,
           coalesce(helpdesk.person_name(k.changed_by), CASE WHEN k.changed_by = '00000000-0000-0000-0000-000000000000' THEN 'the migration' END, 'Unknown'),
           k.changed_office,
           nullif(concat_ws(' — ', catalogue.course_change_reason_words(k.reason_kind), k.remarks,
                            CASE WHEN k.reason_kind IS NULL THEN k.reason END,
                            (SELECT 'ticket ' || t.number FROM helpdesk.ticket t WHERE t.id = k.ticket_id),
                            CASE WHEN k.source = 'CORRECTION' AND k.field = 'TITLE' AND NOT k.past_classes THEN 'the classes already registered or examined keep the title they had' END), ''),
           CASE k.source WHEN 'AUDIT' THEN 'AUDIT' ELSE k.source END
      FROM catalogue.course_change k WHERE k.course_id IN (SELECT id FROM ids)
    UNION ALL
    SELECT h.changed_at, 'OWNER_CHANGED', 'dept_code', h.from_dept, h.to_dept, coalesce(helpdesk.person_name(h.changed_by), 'Unknown'), h.changed_office, h.reason, h.source
      FROM catalogue.course_owner_history h JOIN catalogue.course c ON c.id = h.course_id WHERE c.code = p_code
    UNION ALL
    SELECT h.ended_at, 'OFFER_ENDED', 'programme', h.programme_code || ' at ' || h.level, NULL, coalesce(helpdesk.person_name(h.ended_by), 'Unknown'), h.ended_office, h.reason, h.source
      FROM catalogue.course_offer_history h WHERE h.course_code = p_code AND h.ended_at IS NOT NULL
    UNION ALL
    SELECT co.added_at, 'OFFER_ADDED', 'programme', NULL, co.programme_code || ' at ' || co.level, coalesce(helpdesk.person_name(co.added_by), 'Unknown'), NULL, NULL, co.source
      FROM catalogue.course_offer co WHERE co.course_code = p_code
    ORDER BY 1 DESC
$$;
COMMENT ON FUNCTION catalogue.course_history(text, int) IS
  'V445, V713: what changed on a course and when — every field from the audit spine under every code the course has had (and its merged codes''), '
  'its code and title from catalogue.course_change with their reasons, each owner change, each binding added or ended — by whom, as which office, why.';

COMMIT;

-- V386 — One course, held once, whatever the session: the course pool kept whole.
--
-- A course is a permanent record of the University's course pool; a session's class (catalogue.offering), a student's
-- registration, a result, an examination and a CBT paper carry the session, never the course. Three gaps are closed:
--
--   1 · The programme-structure upload matches the course already in the pool however its code is written (CSC101,
--       CSC-101, a code merged into another, a code with a session tacked on), as the catalogue upload already did by
--       its normal form; a new course is written in the University's form. catalogue.resolve_course_code is the one rule.
--   2 · A course may be taught in both semesters (catalogue.course.both_semesters): its class is opened in each, it
--       counts for each semester's SIWES, deferment and GST/EPS openings, and a student registers it once a session
--       (REGISTRATION_ONCE_A_SESSION). The course stays one record.
--   3 · Duplicates: the pool refuses a new code that is an existing course written differently (COURSE_DUPLICATE_CODE),
--       a copy of a course for a session (COURSE_SESSION_COPY) or a code already merged (COURSE_CODE_MERGED); the codes
--       already twinned are listed (catalogue.duplicate_codes) and merged by the Academic Office or the Registry with a
--       reason (catalogue.merge_course): a dry run first; every class, registration, result, sheet, examination, CBT
--       paper, question, binding, prerequisite, deferral and held legacy result moves to the course kept; the merged code
--       stays an alias of it, with the merged record as it was. Nothing is deleted but the twin record itself. The BSU-
--       and MOAU- codes, and a BMAS course and its CCMAS counterpart, are kept apart on purpose and never merged.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V386: one course held once — the structure upload matches the pool, courses in both semesters, duplicate codes merged', true);

-- ── 1 · a course taught in both semesters ───────────────────────────────────────────────────────────────────────
ALTER TABLE catalogue.course ADD COLUMN both_semesters boolean NOT NULL DEFAULT false;
ALTER TABLE catalogue.course ADD CONSTRAINT ck_course_both CHECK (NOT both_semesters OR semester IN (1, 2));
COMMENT ON COLUMN catalogue.course.both_semesters IS
  'V386: the course is taught in the first and the second semester alike — one course, a class opened in each semester, registered once a session.';

/* the semesters a course is taught in */
CREATE FUNCTION catalogue.course_semesters(p_semester integer, p_both boolean)
RETURNS integer[] LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN coalesce(p_both, false) THEN ARRAY[1, 2] ELSE ARRAY[p_semester] END
$fn$;
CREATE FUNCTION catalogue.runs_in(p_course_semester integer, p_both boolean, p_semester integer)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
    SELECT p_semester = ANY (catalogue.course_semesters(p_course_semester, p_both))
$fn$;
/* a semester written as both: "Both", "B", "1 & 2", "1/2", "First and Second" */
CREATE FUNCTION catalogue.both_semesters_text(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
    SELECT coalesce(btrim(p), '') ~* '^(both( semesters?)?|b|1\s*(&|and|/|,|\+)\s*2|(first|1st)( semester)?\s*(&|and|/|,|\+)\s*(second|2nd)( semesters?)?)$'
$fn$;
COMMENT ON FUNCTION catalogue.runs_in(integer, boolean, integer) IS
  'V386: whether a course is taught in a semester — its own semester, or the first and second when it is taught in both.';

/* a student registers a course taught in both semesters once a session */
CREATE FUNCTION registration.entry_once_a_session()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_code text; v_session text; v_semester int; v_both boolean; v_student uuid;
BEGIN
    IF NEW.status NOT IN ('REGISTERED', 'APPROVED') THEN RETURN NEW; END IF;
    SELECT o.course_code, o.session, o.semester, c.both_semesters INTO v_code, v_session, v_semester, v_both
      FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = NEW.offering_id;
    IF NOT coalesce(v_both, false) THEN RETURN NEW; END IF;
    SELECT r.student_id INTO v_student FROM registration.course_registration r WHERE r.id = NEW.registration_id;
    IF EXISTS (SELECT 1 FROM registration.entry e
                 JOIN registration.course_registration r ON r.id = e.registration_id
                 JOIN catalogue.offering o ON o.id = e.offering_id
                WHERE r.student_id = v_student AND o.course_code = v_code AND o.session = v_session AND o.semester <> v_semester
                  AND e.status IN ('REGISTERED', 'APPROVED')) THEN
        RAISE EXCEPTION 'REGISTRATION_ONCE_A_SESSION: % is taught in both semesters and is registered once a session; it is already on your other semester''s registration for %', v_code, v_session
            USING ERRCODE = '23514', HINT = 'Drop it from the other semester first to take it in this one.';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_entry_once_a_session BEFORE INSERT OR UPDATE OF offering_id, status ON registration.entry
    FOR EACH ROW EXECUTE FUNCTION registration.entry_once_a_session();

-- ── 2 · one course, one code ─────────────────────────────────────────────────────────────────────────────────────
/* a code with its spacing and punctuation taken out: CSC 101, CSC101 and CSC-101 are one key */
CREATE FUNCTION catalogue.code_key(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g')
$fn$;
CREATE INDEX ix_course_code_key ON catalogue.course (catalogue.code_key(code));

/* the course a code copies for a session — CSC 101 of "CSC 101 2025/2026", "CSC 101-2025", "CSC 101 (2025/26)" — or null */
CREATE FUNCTION catalogue.session_copy_base(p text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE m text[];
BEGIN
    m := regexp_match(upper(btrim(coalesce(p, ''))), '^(.*?[0-9][A-Z]?)\s*[ /_.(-]\s*\(?\s*(19|20)[0-9]{2}(\s*[/-]\s*((19|20)?[0-9]{2}))?\s*\)?$');
    IF m IS NULL OR btrim(m[1]) !~ '^[A-Z][A-Z0-9 /-]{1,18}[0-9][A-Z]?$' THEN RETURN NULL; END IF;
    RETURN btrim(m[1]);
END $fn$;

/* the codes merged into another course: the old code answers for the course kept */
CREATE TABLE catalogue.course_alias (
    alias_code    text PRIMARY KEY,
    course_code   text NOT NULL REFERENCES catalogue.course (code) ON UPDATE CASCADE,
    absorbed_id   uuid NOT NULL,
    absorbed      jsonb NOT NULL,
    evidence      text NOT NULL CHECK (evidence IN ('SAME_CODE_WRITTEN_DIFFERENTLY', 'SESSION_COPY', 'SAME_TITLE_AND_LEVEL')),
    moved         jsonb NOT NULL,
    reason        text NOT NULL CHECK (length(btrim(reason)) > 0),
    merged_at     timestamptz NOT NULL DEFAULT now(),
    merged_by     uuid,
    merged_office text REFERENCES ref.office (code)
);
CREATE INDEX ix_course_alias_course ON catalogue.course_alias (course_code);
COMMENT ON TABLE catalogue.course_alias IS
  'V386: a code merged into the course kept — the old code resolves to it in every upload, and the merged record is kept as it was, with what moved and why.';
SELECT audit.attach('catalogue.course_alias');

/* the course a code names: the code itself, its normal form, a merged code''s course, the one course written the same
   way, the course a session copy copies — else the normal form of a new course */
CREATE FUNCTION catalogue.resolve_course_code(p_code text)
RETURNS text LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_clean text := nullif(regexp_replace(upper(btrim(coalesce(p_code, ''))), '\s+', ' ', 'g'), '');
        v_norm text; v_hit text; v_base text; n int;
BEGIN
    IF v_clean IS NULL THEN RETURN NULL; END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_clean) THEN RETURN v_clean; END IF;
    v_norm := catalogue.normal_code(v_clean);
    IF v_norm IS NOT NULL AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_norm) THEN RETURN v_norm; END IF;
    SELECT a.course_code INTO v_hit FROM catalogue.course_alias a WHERE a.alias_code IN (v_clean, v_norm) LIMIT 1;
    IF v_hit IS NOT NULL THEN RETURN v_hit; END IF;
    SELECT min(c.code), count(*) INTO v_hit, n FROM catalogue.course c WHERE catalogue.code_key(c.code) = catalogue.code_key(v_clean);
    IF n = 1 THEN RETURN v_hit; END IF;
    v_base := catalogue.session_copy_base(v_clean);
    IF v_base IS NOT NULL THEN
        v_hit := catalogue.resolve_course_code(v_base);
        IF v_hit IS NOT NULL AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_hit) THEN RETURN v_hit; END IF;
    END IF;
    RETURN coalesce(v_norm, v_clean);
END $fn$;
COMMENT ON FUNCTION catalogue.resolve_course_code(text) IS
  'V386: the course a code names in the pool — never a second course for the same code written differently, merged, or copied for a session.';

/* the pool refuses a second record of a course: a code written differently, a session copy, a merged code */
CREATE FUNCTION catalogue.course_code_guard()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_twin text; v_base text; v_alias text;
BEGIN
    IF TG_OP = 'INSERT' AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = NEW.code) THEN RETURN NEW; END IF;   -- an upsert of a course held
    IF TG_OP = 'UPDATE' AND NEW.code = OLD.code THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = NEW.code AND id <> NEW.id) THEN RETURN NEW; END IF;   -- the code is taken: the key says so
    SELECT a.course_code INTO v_alias FROM catalogue.course_alias a WHERE a.alias_code = NEW.code;
    IF v_alias IS NOT NULL THEN
        RAISE EXCEPTION 'COURSE_CODE_MERGED: % was merged into %; the pool holds that course once', NEW.code, v_alias USING ERRCODE = '23514';
    END IF;
    SELECT c.code INTO v_twin FROM catalogue.course c
     WHERE catalogue.code_key(c.code) = catalogue.code_key(NEW.code) AND c.code <> NEW.code AND (TG_OP = 'INSERT' OR c.id <> NEW.id) LIMIT 1;
    IF v_twin IS NOT NULL THEN
        RAISE EXCEPTION 'COURSE_DUPLICATE_CODE: % is % written differently; the pool holds a course once', NEW.code, v_twin USING ERRCODE = '23514';
    END IF;
    v_base := catalogue.session_copy_base(NEW.code);
    IF v_base IS NOT NULL THEN
        SELECT c.code INTO v_twin FROM catalogue.course c WHERE catalogue.code_key(c.code) = catalogue.code_key(v_base) AND (TG_OP = 'INSERT' OR c.id <> NEW.id) LIMIT 1;
        IF v_twin IS NOT NULL THEN
            RAISE EXCEPTION 'COURSE_SESSION_COPY: % copies % for a session; a course is held once and the session is its class''s, its registration''s and its result''s', NEW.code, v_twin
                USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_course_code_guard BEFORE INSERT OR UPDATE OF code ON catalogue.course FOR EACH ROW EXECUTE FUNCTION catalogue.course_code_guard();

/* the University's offices that merge courses */
CREATE FUNCTION catalogue.merge_office_ok()
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') IN ('academic', 'registrar', 'dregistrar', 'super')
$fn$;

/* the courses the pool holds twice: the same code written differently, or a copy of a course for a session; each pair
   with the code to keep (the University's form, then the live one, then the one more used) and what each carries */
CREATE FUNCTION catalogue.duplicate_codes()
RETURNS TABLE (evidence text, keep_code text, merge_code text, keep_title text, merge_title text, keep_dept text, merge_dept text,
               keep_state text, merge_state text, keep_uses bigint, merge_uses bigint, differences text[])
LANGUAGE sql STABLE AS $fn$
    WITH c AS (
        SELECT x.code, x.title, x.units, x.semester, x.both_semesters, x.level, x.kind, x.dept_code, x.state, x.curriculum,
               catalogue.code_key(x.code) AS k,
               (x.code = catalogue.normal_code(x.code) AND x.code ~ '^[A-Z]{2,4}(-[A-Z]{2,4})? [0-9]{3}[A-Z]?$') AS clean,
               (SELECT count(*) FROM catalogue.offering o WHERE o.course_code = x.code)
             + (SELECT count(*) FROM catalogue.course_offer co WHERE co.course_code = x.code) AS uses
          FROM catalogue.course x WHERE x.code NOT LIKE 'DMO %'),
    pairs AS (
        SELECT 'SAME_CODE_WRITTEN_DIFFERENTLY'::text AS evidence, a.code AS a, b.code AS b
          FROM c a JOIN c b ON b.k = a.k AND a.code < b.code
        UNION
        SELECT 'SESSION_COPY', base.code, cp.code
          FROM c cp JOIN c base ON base.k = catalogue.code_key(catalogue.session_copy_base(cp.code)) AND base.code <> cp.code
         WHERE catalogue.session_copy_base(cp.code) IS NOT NULL),
    chosen AS (
        SELECT p.evidence,
               CASE WHEN p.evidence = 'SESSION_COPY' THEN p.a
                    WHEN (ca.clean, ca.state <> 'ENDED', ca.uses, -length(ca.code)) >= (cb.clean, cb.state <> 'ENDED', cb.uses, -length(cb.code)) THEN p.a ELSE p.b END AS keep,
               CASE WHEN p.evidence = 'SESSION_COPY' THEN p.b
                    WHEN (ca.clean, ca.state <> 'ENDED', ca.uses, -length(ca.code)) >= (cb.clean, cb.state <> 'ENDED', cb.uses, -length(cb.code)) THEN p.b ELSE p.a END AS other
          FROM pairs p JOIN c ca ON ca.code = p.a JOIN c cb ON cb.code = p.b)
    SELECT ch.evidence, k.code, m.code, k.title, m.title, k.dept_code, m.dept_code, k.state, m.state, k.uses, m.uses,
           array_remove(ARRAY[
               CASE WHEN lower(btrim(k.title)) <> lower(btrim(m.title)) THEN 'TITLE' END,
               CASE WHEN k.units <> m.units THEN 'UNITS' END,
               CASE WHEN k.semester <> m.semester OR k.both_semesters <> m.both_semesters THEN 'SEMESTER' END,
               CASE WHEN k.level <> m.level THEN 'LEVEL' END,
               CASE WHEN k.dept_code IS DISTINCT FROM m.dept_code THEN 'OWNER' END,
               CASE WHEN k.curriculum IS DISTINCT FROM m.curriculum THEN 'CURRICULUM' END], NULL)
      FROM chosen ch JOIN c k ON k.code = ch.keep JOIN c m ON m.code = ch.other
     ORDER BY k.code, m.code
$fn$;
COMMENT ON FUNCTION catalogue.duplicate_codes() IS
  'V386: the pairs of codes that are one course — the same code written differently, or a copy for a session — with the code to keep; read-only.';

/* merge one course into another: a dry run by default; the real merge by the Academic Office or the Registry, with a reason */
CREATE FUNCTION catalogue.merge_course(p_keep text, p_merge text, p_reason text, p_dry boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE k catalogue.course; m catalogue.course; v_evidence text; v_block text; v_warn text[] := '{}'; v_moved jsonb := '{}'::jsonb;
        v_clash text; n int; v_bind int := 0; v_pre int := 0; fk record; v_out jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO k FROM catalogue.course WHERE code = upper(btrim(coalesce(p_keep, '')));
    SELECT * INTO m FROM catalogue.course WHERE code = upper(btrim(coalesce(p_merge, '')));
    IF k.code IS NULL THEN RAISE EXCEPTION 'MERGE_KEEP_UNKNOWN: no course is coded %', p_keep USING ERRCODE = '23514'; END IF;
    IF m.code IS NULL THEN RAISE EXCEPTION 'MERGE_UNKNOWN: no course is coded %', p_merge USING ERRCODE = '23514'; END IF;
    IF k.code = m.code THEN RAISE EXCEPTION 'MERGE_SAME: a course is not merged into itself' USING ERRCODE = '23514'; END IF;

    -- the evidence that the two are one course
    v_evidence := CASE
        WHEN catalogue.code_key(k.code) = catalogue.code_key(m.code) THEN 'SAME_CODE_WRITTEN_DIFFERENTLY'
        WHEN catalogue.code_key(catalogue.session_copy_base(m.code)) = catalogue.code_key(k.code) THEN 'SESSION_COPY'
        WHEN lower(regexp_replace(btrim(k.title), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(m.title), '\s+', ' ', 'g'))
             AND k.level = m.level AND k.semester = m.semester AND k.dept_code IS NOT DISTINCT FROM m.dept_code THEN 'SAME_TITLE_AND_LEVEL' END;

    -- what keeps two codes apart on purpose, or blocks the merge
    v_block := CASE
        WHEN v_evidence IS NULL THEN format('MERGE_NOT_SAME: %s and %s are not one course by their codes, nor by title, level, semester and owner', k.code, m.code)
        WHEN (k.code ~ '^BSU-' AND m.code ~ '^MOAU-') OR (k.code ~ '^MOAU-' AND m.code ~ '^BSU-') THEN 'MERGE_FAMILY: the BSU- and MOAU- codes of a course are kept apart on purpose'
        WHEN k.curriculum IS NOT NULL AND m.curriculum IS NOT NULL AND k.curriculum <> m.curriculum THEN format('MERGE_CURRICULUM: %s is %s and %s is %s; the two curricula are kept apart', k.code, k.curriculum, m.code, m.curriculum)
        WHEN k.general_office IS DISTINCT FROM m.general_office AND k.general_office IS NOT NULL AND m.general_office IS NOT NULL THEN 'MERGE_GENERAL_OFFICE: the two are held by different general-studies offices'
        WHEN k.state = 'ENDED' THEN format('MERGE_KEEP_ENDED: %s is ended; keep the live course', k.code) END;
    IF v_block IS NULL THEN
        SELECT string_agg(DISTINCT format('%s %s semester %s', mo.session, CASE WHEN mo.stream = 'CCE' THEN 'CCE' ELSE '' END, mo.semester), '; ') INTO v_clash
          FROM catalogue.offering mo JOIN catalogue.offering ko ON ko.course_code = k.code AND ko.session = mo.session AND ko.semester = mo.semester AND ko.stream = mo.stream
         WHERE mo.course_code = m.code;
        IF v_clash IS NOT NULL THEN
            v_block := format('MERGE_CLASS_CLASH: both codes have a class in %s; their students and sheets are two classes and are not joined here', v_clash);
        END IF;
    END IF;
    IF NOT p_dry AND v_block IS NULL AND NOT catalogue.merge_office_ok() THEN
        v_block := 'MERGE_OFFICE: a course is merged by the Academic Office or the Registry';
    END IF;
    IF NOT p_dry AND v_block IS NULL AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        v_block := 'MERGE_REASON: a merge is recorded with its reason';
    END IF;
    v_warn := array_remove(ARRAY[
        CASE WHEN lower(btrim(k.title)) <> lower(btrim(m.title)) THEN format('the titles differ: %s / %s', k.title, m.title) END,
        CASE WHEN k.units <> m.units THEN format('the units differ: %s / %s (each registration and result keeps its own)', k.units, m.units) END,
        CASE WHEN k.semester <> m.semester OR k.both_semesters <> m.both_semesters THEN 'the semesters differ' END,
        CASE WHEN k.level <> m.level THEN format('the levels differ: %s / %s', k.level, m.level) END,
        CASE WHEN k.dept_code IS DISTINCT FROM m.dept_code THEN format('the owners differ: %s / %s', k.dept_code, m.dept_code) END,
        CASE WHEN m.state <> 'ENDED' AND k.state <> m.state THEN format('%s is %s and %s is %s', k.code, k.state, m.code, m.state) END], NULL);
    v_out := jsonb_build_object('keep', k.code, 'merge', m.code, 'keepTitle', k.title, 'mergeTitle', m.title, 'evidence', v_evidence,
                                'warnings', to_jsonb(v_warn), 'dry', p_dry, 'blocked', v_block);
    IF v_block IS NOT NULL THEN
        IF p_dry THEN RETURN v_out; END IF;
        RAISE EXCEPTION '%', v_block USING ERRCODE = '23514';
    END IF;

    BEGIN
        -- a binding the course kept already holds (the same programme and level) stays the kept course's own
        DELETE FROM catalogue.course_offer mo WHERE mo.course_code = m.code
           AND EXISTS (SELECT 1 FROM catalogue.course_offer ko WHERE ko.course_code = k.code AND ko.programme_code = mo.programme_code AND ko.level = mo.level);
        GET DIAGNOSTICS v_bind = ROW_COUNT;
        -- a prerequisite that would make the course require itself, or that the course kept holds already
        DELETE FROM catalogue.course_prerequisite p
         WHERE (p.course_code = m.code AND p.requires_code = k.code) OR (p.course_code = k.code AND p.requires_code = m.code)
            OR (p.course_code = m.code AND EXISTS (SELECT 1 FROM catalogue.course_prerequisite q WHERE q.course_code = k.code AND q.requires_code = p.requires_code))
            OR (p.requires_code = m.code AND EXISTS (SELECT 1 FROM catalogue.course_prerequisite q WHERE q.course_code = p.course_code AND q.requires_code = k.code));
        GET DIAGNOSTICS v_pre = ROW_COUNT;
        -- every record that names the merged course names the course kept
        FOR fk IN SELECT c.conrelid::regclass::text AS tbl, a.attname::text AS col
                    FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
                   WHERE c.contype = 'f' AND c.confrelid = 'catalogue.course'::regclass AND cardinality(c.conkey) = 1
                   ORDER BY 1, 2 LOOP
            BEGIN
                EXECUTE format('UPDATE %s SET %I = $1 WHERE %I = $2', fk.tbl, fk.col, fk.col) USING k.code, m.code;
                GET DIAGNOSTICS n = ROW_COUNT;
            EXCEPTION WHEN unique_violation THEN
                RAISE EXCEPTION 'MERGE_CONFLICT: % holds both % and % where only one may stand (%)', fk.tbl, k.code, m.code, SQLERRM USING ERRCODE = '23514';
            END;
            IF n > 0 THEN v_moved := v_moved || jsonb_build_object(fk.tbl || '.' || fk.col, n); END IF;
        END LOOP;
        UPDATE assessment.legacy_result_holding SET course_code = k.code WHERE course_code = m.code;
        GET DIAGNOSTICS n = ROW_COUNT;
        IF n > 0 THEN v_moved := v_moved || jsonb_build_object('assessment.legacy_result_holding.course_code', n); END IF;
        UPDATE catalogue.course_owner_history SET course_code = k.code WHERE course_code = m.code;
        GET DIAGNOSTICS n = ROW_COUNT;
        IF n > 0 THEN v_moved := v_moved || jsonb_build_object('catalogue.course_owner_history.course_code', n); END IF;
        UPDATE catalogue.course_reset_item SET course_code = k.code WHERE course_code = m.code;
        v_moved := v_moved || jsonb_build_object('bindingsAlreadyHeld', v_bind, 'prerequisitesAlreadyHeld', v_pre);

        -- the merged code stays an alias of the course kept, with the merged record as it was; the twin record goes
        INSERT INTO catalogue.course_alias (alias_code, course_code, absorbed_id, absorbed, evidence, moved, reason, merged_by, merged_office)
        VALUES (m.code, k.code, m.id, to_jsonb(m), v_evidence, v_moved, coalesce(nullif(btrim(p_reason), ''), 'dry run'), v_actor,
                nullif(current_setting('moaum.actor_office', true), ''));
        DELETE FROM catalogue.course WHERE code = m.code;
        v_out := v_out || jsonb_build_object('moved', v_moved);
        IF p_dry THEN RAISE EXCEPTION 'MERGE_DRY_RUN' USING ERRCODE = 'P0001'; END IF;
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'MERGE_DRY_RUN' THEN RAISE; END IF;
    END;
    RETURN v_out;
END $fn$;
COMMENT ON FUNCTION catalogue.merge_course(text, text, text, boolean) IS
  'V386: merges a twin course into the course kept — a dry run unless p_dry is false; the real merge by the Academic Office or the Registry with a reason; every reference moves, the merged code becomes an alias, nothing else is deleted.';

-- ── 3 · a course taught in both semesters is opened, counted and offered in each ─────────────────────────────
CREATE OR REPLACE FUNCTION registration.open_course_registration(p_session text, p_semester integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'catalogue', 'registration', 'ref', 'policy'
AS $function$
DECLARE v_count int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'course registration is opened by a person' USING ERRCODE = '23514';
    END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'no academic session % on the calendar — open the session first', p_session USING ERRCODE = '23503';
    END IF;

    -- 1 · decide, before any lock: the courses of this semester that some structure row offers for any
    --     track, or for a track that still has a student in that programme
    CREATE TEMP TABLE IF NOT EXISTS to_offer (course_code text PRIMARY KEY) ON COMMIT DROP;
    TRUNCATE to_offer;
    WITH live AS (
        SELECT DISTINCT st.programme_code, st.curriculum_track
          FROM people.student st
         WHERE st.status IN ('ACTIVE','PROBATION','ADMITTED')
    )
    INSERT INTO to_offer (course_code)
    SELECT DISTINCT c.code
      FROM catalogue.course c
      JOIN catalogue.course_offer co ON co.course_code = c.code
     WHERE catalogue.runs_in(c.semester, c.both_semesters, p_semester)   -- V386: a course taught in both semesters too
       AND c.state <> 'ENDED'
       AND (co.track IS NULL
            OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track))
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o   -- V380: the full-time classes; the Centre opens its own
                        WHERE o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = 'REGULAR');

    -- 2 · insert the rows already chosen, with the audit trigger off for exactly that long
    ALTER TABLE catalogue.offering DISABLE TRIGGER trg_audit_catalogue_offering;
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), t.course_code, p_session, p_semester FROM to_offer t;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    ALTER TABLE catalogue.offering ENABLE TRIGGER trg_audit_catalogue_offering;

    RETURN v_count;
END $function$;
CREATE OR REPLACE FUNCTION catalogue.cce_open_classes(p_session text, p_semester integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'opening the Centre''s classes');
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'CCE_CLASS_SEMESTER: a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    PERFORM catalogue.cce_class_session(p_session);
    WITH live AS (SELECT DISTINCT st.programme_code, st.curriculum_track FROM people.student st
                   WHERE st.entry_mode = 'CCE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    offered AS (
        SELECT DISTINCT c.code
          FROM catalogue.course c
          JOIN catalogue.course_offer co ON co.course_code = c.code
          JOIN ref.programme_route pr ON pr.programme_code = co.programme_code AND pr.route = 'CCE' AND pr.active
         WHERE catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'   -- V386
           AND (co.track IS NULL OR EXISTS (SELECT 1 FROM live l WHERE l.programme_code = co.programme_code AND l.curriculum_track = co.track))
        UNION
        SELECT DISTINCT c.code
          FROM people.student st
          CROSS JOIN LATERAL registration.carryovers(st.id) cv
          JOIN catalogue.course c ON c.code = cv.course_code
         WHERE st.entry_mode = 'CCE' AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
           AND catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %')
    INSERT INTO catalogue.offering (id, course_code, session, semester, stream)
    SELECT gen_random_uuid(), o.code, p_session, p_semester, 'CCE' FROM offered o
    ON CONFLICT (course_code, session, semester, stream) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $function$;
CREATE OR REPLACE FUNCTION registration.siwes_units(p_programme text, p_level integer, p_semester integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT max(c.units)::int
      FROM catalogue.course_offer co
      JOIN catalogue.course c ON c.code = co.course_code
     WHERE co.programme_code = p_programme AND co.level = p_level
       AND catalogue.runs_in(c.semester, c.both_semesters, p_semester) AND c.industrial_training AND c.state <> 'ENDED';
$function$;
CREATE OR REPLACE FUNCTION people.deferment_apply_effect(p_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE d people.deferment; s people.student; v_sems int; v_sem int; v_level int; reg registration.course_registration; n int := 0; m int; e record; c record;
        tl_after record; v_ext int;
BEGIN
    SELECT * INTO d FROM people.deferment WHERE id = p_id FOR UPDATE;
    IF d.effect_applied_at IS NOT NULL THEN RETURN d.courses_affected; END IF;
    SELECT * INTO s FROM people.student WHERE id = d.student_id;
    v_sems := coalesce((SELECT semesters FROM policy.academic_session WHERE name = d.session), 2);
    v_level := coalesce((SELECT en.level FROM people.enrolment en WHERE en.student_id = s.id AND en.session = d.session), s.current_level);
    FOR v_sem IN 1..v_sems LOOP
        IF d.kind = 'SEMESTER' AND v_sem <> d.semester THEN CONTINUE; END IF;
        m := 0;
        SELECT * INTO reg FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = d.session AND r.semester = v_sem;
        IF reg.id IS NOT NULL THEN
            FOR e IN SELECT en.*, o.course_code FROM registration.entry en JOIN catalogue.offering o ON o.id = en.offering_id
                      WHERE en.registration_id = reg.id AND en.status IN ('REGISTERED','APPROVED') LOOP
                UPDATE registration.entry SET status = 'DEFERRED' WHERE registration_id = e.registration_id AND offering_id = e.offering_id;
                INSERT INTO people.deferred_course (deferment_id, student_id, course_code, offering_id, units, entry_type, original_session, original_semester, source)
                VALUES (d.id, s.id, e.course_code, e.offering_id, e.units, e.entry_type, d.session, v_sem, 'REGISTRATION')
                ON CONFLICT (deferment_id, course_code) DO NOTHING;
                m := m + 1;
            END LOOP;
        END IF;
        IF m = 0 THEN
            FOR c IN SELECT DISTINCT ON (cc.code) cc.code, cc.units
                       FROM catalogue.course_offer co
                       JOIN catalogue.course cc ON cc.code = co.course_code AND cc.state <> 'ENDED' AND cc.code NOT LIKE 'DMO %'
                      WHERE co.programme_code = s.programme_code AND co.level = v_level
                        AND (co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
                        AND (cc.curriculum IS NULL OR s.curriculum_version IS NULL OR cc.curriculum = s.curriculum_version)
                        AND catalogue.runs_in(cc.semester, cc.both_semesters, v_sem)   -- V386
                        AND coalesce(co.basis, cc.kind) IN ('Core','GST','Compulsory','Required')
                      ORDER BY cc.code LOOP
                INSERT INTO people.deferred_course (deferment_id, student_id, course_code, units, original_session, original_semester, source)
                VALUES (d.id, s.id, c.code, c.units, d.session, v_sem, 'CURRICULUM')
                ON CONFLICT (deferment_id, course_code) DO NOTHING;
                m := m + 1;
            END LOOP;
        END IF;
        n := n + m;
    END LOOP;
    v_ext := people.deferment_semesters(d.kind, d.session);
    UPDATE people.deferment SET extension_semesters = v_ext, courses_affected = n, effect_applied_at = now(), updated_at = now() WHERE id = d.id;
    SELECT * INTO tl_after FROM people.programme_timeline(s.id);
    PERFORM people.deferment_log(d.id, 'EFFECT_APPLIED', 'APPROVED', 'APPROVED',
        'Period ' || d.session || coalesce(' semester ' || d.semester, ' (whole session)') || ' marked DEFERRED · ' || n || ' course(s) set aside, none failed · '
        || 'programme timeline +' || v_ext || ' semester(s): ' || tl_after.original_semesters || ' → ' || tl_after.adjusted_semesters
        || ' semesters, expected completion ' || tl_after.original_completion_session || ' semester ' || tl_after.original_completion_semester
        || ' → ' || tl_after.adjusted_completion_session || ' semester ' || tl_after.adjusted_completion_semester
        || ' · entry session ' || s.entry_session || ' and matriculation number unchanged');
    RETURN n;
END $function$;
CREATE OR REPLACE FUNCTION catalogue.gst_offering_gaps(p_session text, p_office text)
 RETURNS TABLE(course_code text, title text, level integer, semester integer, office text, programmes bigint, levels text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT c.code, c.title, c.level, s.sem, c.general_office, count(DISTINCT co.programme_code),
           string_agg(DISTINCT co.level::text, ', ')
      FROM catalogue.course c
      CROSS JOIN LATERAL unnest(catalogue.course_semesters(c.semester, c.both_semesters)) s(sem)   -- V386: each semester it is taught in
      JOIN catalogue.course_offer co ON co.course_code = c.code
      JOIN ref.programme p ON p.code = co.programme_code AND NOT coalesce(p.archived, false) AND p.category = 'UNDER GRADUATE'
     WHERE c.kind = 'GST' AND c.general_office IS NOT NULL AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
       AND (p_office IS NULL OR c.general_office = p_office)
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = p_session AND o.semester = s.sem AND o.stream = 'REGULAR')
     GROUP BY c.code, c.title, c.level, s.sem, c.general_office
     ORDER BY c.general_office, c.level, c.code, s.sem
$function$;

-- ── 4 · the uploads match the course the pool holds; a semester may be both ──────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.import_courses_rows(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL::text)
 RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text; v_owner text; v_status_raw text; v_class text; v_eps boolean; v_both boolean;
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
        -- V386: the course the pool holds, however the code is written (CSC101, a merged code, a session copy); a new one in the normal form
        v_code := coalesce(catalogue.resolve_course_code(v_code), v_code);
        n := n + 1;
        IF v_code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN nb := nb + 1; CONTINUE; END IF;

        BEGIN
            v_title := nullif(btrim(coalesce(r->>'title', r->>'courseTitle', '')), '');
            IF v_title IS NULL THEN v_title := v_code; END IF;
            v_units := least(coalesce(nullif(regexp_replace(coalesce(r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 0), 12);
            v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, 100);
            IF v_level NOT IN (100,200,300,400,500,600) THEN v_level := 100; END IF;
            v_both := catalogue.both_semesters_text(r->>'semester');   -- V386: "Both", "1 & 2"
            v_sem := CASE WHEN v_both THEN 1 ELSE coalesce(nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int, 1) END;
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
                INSERT INTO catalogue.course (code, title, units, semester, both_semesters, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state, general_office)
                VALUES (v_code, v_title, v_units, v_sem, v_both, v_level, v_dept, v_kind, v_lh, v_ph, v_curr, 'LIVE', CASE WHEN v_eps THEN 'EPS' END)
                ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units, semester = EXCLUDED.semester, both_semesters = EXCLUDED.both_semesters,
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
END $function$;
CREATE OR REPLACE FUNCTION catalogue.import_catalogue_rows(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
WITH raw AS (
    SELECT ord::int AS n, r AS j FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) WITH ORDINALITY AS t(r, ord)
), norm AS (
    SELECT n,
           nullif(btrim(coalesce(j->>'code', '')), '') AS code_raw,
           catalogue.resolve_course_code(j->>'code') AS code,   -- V386: the course the pool holds, however written
           nullif(btrim(coalesce(j->>'title', '')), '') AS title,
           nullif(btrim(coalesce(j->>'units', '')), '') AS units_raw,
           nullif(btrim(coalesce(j->>'level', '')), '') AS level_raw,
           nullif(btrim(coalesce(j->>'semester', '')), '') AS sem_raw,
           nullif(btrim(coalesce(j->>'courseType', '')), '') AS type_raw,
           nullif(btrim(coalesce(j->>'ownerFaculty', '')), '') AS ofa_raw,
           nullif(btrim(coalesce(j->>'ownerDepartment', '')), '') AS od_raw,
           nullif(btrim(coalesce(j->>'ownerProgramme', '')), '') AS op_raw,
           nullif(btrim(coalesce(j->>'offeringFaculty', '')), '') AS ffa_raw,
           nullif(btrim(coalesce(j->>'offeringDepartment', '')), '') AS fd_raw,
           nullif(btrim(coalesce(j->>'offeringProgramme', '')), '') AS fp_raw,
           upper(nullif(btrim(coalesce(j->>'offeringType', '')), '')) AS otype_raw,
           upper(nullif(btrim(coalesce(j->>'status', '')), '')) AS status_raw,
           nullif(btrim(coalesce(j->>'session', '')), '') AS session_raw,
           nullif(btrim(coalesce(j->>'description', '')), '') AS description,
           nullif(btrim(coalesce(j->>'prerequisite', '')), '') AS prereq_raw,
           upper(nullif(btrim(coalesce(j->>'classification', '')), '')) AS class_raw,
           nullif(btrim(coalesce(j->>'remarks', '')), '') AS remarks
      FROM raw
     WHERE coalesce(btrim(j->>'code'), '') <> '' OR coalesce(btrim(j->>'title'), '') <> '' OR coalesce(btrim(j->>'offeringProgramme'), '') <> ''
), res AS (
    SELECT x.*,
           CASE WHEN x.units_raw ~ '^[0-9]{1,2}$' AND x.units_raw::int <= 12 THEN x.units_raw::int END AS units,
           CASE WHEN regexp_replace(coalesce(x.level_raw, ''), '[^0-9]', '', 'g') ~ '^[1-9]00$' THEN regexp_replace(x.level_raw, '[^0-9]', '', 'g')::int END AS level,
           CASE WHEN catalogue.both_semesters_text(x.sem_raw) THEN 1
                WHEN x.sem_raw ~* '^(1|1st|first)' THEN 1 WHEN x.sem_raw ~* '^(2|2nd|second)' THEN 2 WHEN x.sem_raw ~* '^(3|3rd|third)' THEN 3 END AS semester,
           CASE WHEN x.sem_raw IS NOT NULL THEN catalogue.both_semesters_text(x.sem_raw) END AS both_sems,
           CASE WHEN x.type_raw IS NULL THEN NULL WHEN upper(x.type_raw) = 'GST' THEN 'GST'
                WHEN upper(x.type_raw) IN ('CORE', 'COMPULSORY') THEN 'Core' WHEN upper(x.type_raw) = 'REQUIRED' THEN 'Required'
                WHEN upper(x.type_raw) = 'ELECTIVE' THEN 'Elective' END AS course_type,
           ofa.code AS ofa, od.code AS od, od.faculty_code AS od_fac, op.code AS op, op.dept_code AS op_dept,
           ffa.code AS ffa, fd.code AS fd, fp.code AS fp, fp.dept_code AS fp_dept, fp.faculty_code AS fp_fac, coalesce(fp.archived, false) AS fp_archived,
           ec.code AS existing, ec.state AS existing_state, ec.reset_batch_id AS existing_reset, ec.dept_code AS existing_dept,
           ec.owner_programme AS existing_prog, ec.general_office AS existing_office,
           EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = x.session_raw) AS session_ok
      FROM norm x
      LEFT JOIN LATERAL (SELECT f.code FROM ref.faculty f
                          WHERE x.ofa_raw IS NOT NULL AND (upper(f.code) = upper(x.ofa_raw) OR upper(f.name) = catalogue.bare_name(x.ofa_raw) OR upper(f.name) = upper(x.ofa_raw)) LIMIT 1) ofa ON true
      LEFT JOIN LATERAL (SELECT d.code, d.faculty_code FROM ref.department d
                          WHERE x.od_raw IS NOT NULL AND d.ended_on IS NULL
                            AND (upper(d.code) = upper(x.od_raw) OR upper(d.name) = catalogue.bare_name(x.od_raw) OR upper(d.name) = upper(x.od_raw)) LIMIT 1) od ON true
      LEFT JOIN LATERAL (SELECT p.code, p.dept_code FROM ref.programme p
                          WHERE x.op_raw IS NOT NULL AND NOT coalesce(p.archived, false) AND (upper(p.code) = upper(x.op_raw) OR upper(p.name) = upper(x.op_raw))
                          ORDER BY (p.dept_code = od.code) DESC NULLS LAST LIMIT 1) op ON true
      LEFT JOIN LATERAL (SELECT f.code FROM ref.faculty f
                          WHERE x.ffa_raw IS NOT NULL AND (upper(f.code) = upper(x.ffa_raw) OR upper(f.name) = catalogue.bare_name(x.ffa_raw) OR upper(f.name) = upper(x.ffa_raw)) LIMIT 1) ffa ON true
      LEFT JOIN LATERAL (SELECT d.code FROM ref.department d
                          WHERE x.fd_raw IS NOT NULL AND d.ended_on IS NULL
                            AND (upper(d.code) = upper(x.fd_raw) OR upper(d.name) = catalogue.bare_name(x.fd_raw) OR upper(d.name) = upper(x.fd_raw)) LIMIT 1) fd ON true
      LEFT JOIN LATERAL (SELECT p.code, p.dept_code, p.faculty_code, p.archived FROM ref.programme p
                          WHERE x.fp_raw IS NOT NULL AND (upper(p.code) = upper(x.fp_raw) OR upper(p.name) = upper(x.fp_raw))
                          ORDER BY coalesce(p.archived, false), (p.dept_code = fd.code) DESC NULLS LAST LIMIT 1) fp ON true
      LEFT JOIN catalogue.course ec ON ec.code = x.code
), judged AS (
    SELECT r.*,
           coalesce(r.od, r.existing_dept) AS owner_dept,
           CASE WHEN r.class_raw IN ('GST', 'EPS') THEN 'GST' WHEN r.otype_raw IN ('CORE', 'C') THEN 'Core' WHEN r.otype_raw IN ('ELECTIVE', 'E') THEN 'Elective' END AS basis,
           row_number() OVER (PARTITION BY r.code, r.fp, r.level ORDER BY r.n) AS dup_rank,
           a.titles, a.unitss, a.sems, a.owners, a.owner_progs,
           ARRAY(SELECT catalogue.resolve_course_code(q)
                   FROM unnest(regexp_split_to_array(coalesce(r.prereq_raw, ''), '\s*[,;/]\s*')) q WHERE btrim(q) <> '') AS prereqs
      FROM res r
      JOIN (SELECT code,
                   count(DISTINCT upper(title)) FILTER (WHERE title IS NOT NULL) AS titles,
                   count(DISTINCT units) FILTER (WHERE units IS NOT NULL) AS unitss,
                   count(DISTINCT (semester, both_sems)) FILTER (WHERE semester IS NOT NULL) AS sems,
                   count(DISTINCT od) FILTER (WHERE od IS NOT NULL) AS owners,
                   count(DISTINCT op) FILTER (WHERE op IS NOT NULL) AS owner_progs
              FROM res GROUP BY code) a ON a.code IS NOT DISTINCT FROM r.code
), checked AS (
    SELECT j.*,
           array_remove(ARRAY[
             CASE WHEN j.code_raw IS NULL THEN 'CODE_MISSING: the course code is blank'
                  WHEN j.code !~ '^[A-Z][A-Z0-9 /-]{2,19}$' THEN 'CODE_INVALID: ' || j.code_raw || ' is not a course code' END,
             CASE WHEN j.title IS NULL AND j.existing IS NULL THEN 'TITLE_MISSING: a new course needs its title' END,
             CASE WHEN j.units_raw IS NOT NULL AND j.units IS NULL THEN 'UNITS_INVALID: units are a whole number from 0 to 12'
                  WHEN j.units IS NULL AND j.existing IS NULL THEN 'UNITS_INVALID: a new course needs its units' END,
             CASE WHEN j.level IS NULL THEN 'LEVEL_INVALID: the level is 100 to 900' END,
             CASE WHEN j.sem_raw IS NOT NULL AND j.semester IS NULL THEN 'SEMESTER_INVALID: the semester is 1, 2 or 3'
                  WHEN j.semester IS NULL AND j.existing IS NULL THEN 'SEMESTER_INVALID: a new course needs its semester' END,
             CASE WHEN j.type_raw IS NOT NULL AND j.course_type IS NULL THEN 'COURSE_TYPE_INVALID: the course type is Core, Required, Elective or GST' END,
             CASE WHEN j.od_raw IS NULL AND j.existing IS NULL THEN 'OWNER_DEPARTMENT_MISSING: a new course needs the department that owns it'
                  WHEN j.od_raw IS NOT NULL AND j.od IS NULL THEN 'OWNER_DEPARTMENT_UNKNOWN: no live department is coded or named ' || j.od_raw END,
             CASE WHEN j.ofa_raw IS NOT NULL AND j.ofa IS NULL THEN 'OWNER_FACULTY_UNKNOWN: no faculty is coded or named ' || j.ofa_raw
                  WHEN j.ofa IS NOT NULL AND j.od IS NOT NULL AND j.od_fac IS DISTINCT FROM j.ofa THEN 'OWNER_FACULTY_MISMATCH: the owner department is not in that faculty' END,
             CASE WHEN j.op_raw IS NOT NULL AND j.op IS NULL THEN 'OWNER_PROGRAMME_UNKNOWN: no live programme is coded or named ' || j.op_raw
                  WHEN j.op IS NOT NULL AND j.op_dept IS DISTINCT FROM coalesce(j.od, j.existing_dept) THEN 'OWNER_PROGRAMME_NOT_IN_DEPARTMENT: the owner programme is not a programme of the owner department' END,
             CASE WHEN j.fp_raw IS NULL THEN 'OFFERING_PROGRAMME_MISSING: name the programme that offers the course'
                  WHEN j.fp IS NULL THEN 'OFFERING_PROGRAMME_UNKNOWN: no programme is coded or named ' || j.fp_raw
                  WHEN j.fp_archived THEN 'OFFERING_PROGRAMME_ARCHIVED: ' || j.fp || ' is archived' END,
             CASE WHEN j.fd_raw IS NOT NULL AND j.fd IS NULL THEN 'OFFERING_DEPARTMENT_UNKNOWN: no live department is coded or named ' || j.fd_raw
                  WHEN j.fd IS NOT NULL AND j.fp IS NOT NULL AND j.fp_dept IS DISTINCT FROM j.fd THEN 'OFFERING_PROGRAMME_NOT_IN_DEPARTMENT: the offering programme is not a programme of that department' END,
             CASE WHEN j.ffa_raw IS NOT NULL AND j.ffa IS NULL THEN 'OFFERING_FACULTY_UNKNOWN: no faculty is coded or named ' || j.ffa_raw
                  WHEN j.ffa IS NOT NULL AND j.fp IS NOT NULL AND j.fp_fac IS DISTINCT FROM j.ffa THEN 'OFFERING_FACULTY_MISMATCH: the offering programme is not in that faculty' END,
             CASE WHEN j.class_raw IS NOT NULL AND j.class_raw NOT IN ('GST', 'EPS') THEN 'CLASSIFICATION_INVALID: the GST/EPS classification is GST, EPS or blank'
                  WHEN j.basis IS NULL THEN 'OFFERING_TYPE_INVALID: the offering type is CORE or ELECTIVE' END,
             CASE WHEN j.status_raw IS NOT NULL AND j.status_raw NOT IN ('ACTIVE', 'INACTIVE') THEN 'STATUS_INVALID: the status is ACTIVE or INACTIVE' END,
             CASE WHEN j.session_raw IS NOT NULL AND NOT j.session_ok THEN 'SESSION_UNKNOWN: no academic session is named ' || j.session_raw END,
             CASE WHEN j.existing IS NOT NULL AND j.existing_state = 'ENDED' AND j.existing_reset IS NULL THEN 'COURSE_ENDED: ' || j.code || ' was ended on its department''s desk; restore it there first' END,
             CASE WHEN j.dup_rank > 1 THEN 'DUPLICATE_OFFERING: ' || j.code || ' is offered to ' || j.fp || ' at ' || j.level || ' level on an earlier row' END,
             CASE WHEN j.titles > 1 OR j.unitss > 1 OR j.sems > 1 OR j.owners > 1 OR j.owner_progs > 1
                  THEN 'COURSE_CONFLICT: the rows of ' || j.code || ' disagree on its title, units, semester or owner' END,
             CASE WHEN EXISTS (SELECT 1 FROM unnest(j.prereqs) q WHERE q = j.code) THEN 'PREREQUISITE_INVALID: a course does not require itself'
                  WHEN EXISTS (SELECT 1 FROM unnest(j.prereqs) q
                                WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = q)
                                  AND NOT EXISTS (SELECT 1 FROM res r2 WHERE r2.code = q))
                  THEN 'PREREQUISITE_UNKNOWN: ' || (SELECT string_agg(q, ', ') FROM unnest(j.prereqs) q
                                                     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = q) AND NOT EXISTS (SELECT 1 FROM res r2 WHERE r2.code = q)) || ' is not a course' END
           ], NULL) AS errors
      FROM judged j
)
SELECT coalesce(jsonb_agg(jsonb_build_object(
           'n', c.n, 'code', c.code, 'codeAsWritten', c.code_raw, 'title', c.title, 'units', c.units, 'level', c.level, 'semester', c.semester, 'bothSemesters', c.both_sems,
           'ownerDepartment', c.owner_dept, 'ownerProgramme', coalesce(c.op, CASE WHEN c.od IS NULL OR c.od = c.existing_dept THEN c.existing_prog END),
           'offeringProgramme', c.fp, 'offeringDepartment', c.fp_dept, 'basis', c.basis, 'classification', c.class_raw, 'courseType', c.course_type, 'description', c.description,
           'prerequisites', to_jsonb(c.prereqs), 'remarks', c.remarks, 'session', c.session_raw,
           'state', CASE WHEN cardinality(c.errors) > 0 THEN 'INVALID' WHEN c.status_raw = 'INACTIVE' THEN 'SKIPPED' ELSE 'VALID' END,
           'errors', to_jsonb(c.errors),
           'existing', c.existing IS NOT NULL, 'general', c.existing_office IS NOT NULL,
           'revived', c.existing IS NOT NULL AND c.existing_state = 'ENDED' AND c.existing_reset IS NOT NULL,
           'ownerChange', c.existing IS NOT NULL AND c.existing_office IS NULL AND c.od IS NOT NULL AND c.od <> c.existing_dept,
           'existingOffering', EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = c.fp AND co.level = c.level)
       ) ORDER BY c.n), '[]'::jsonb)
  FROM checked c;
$function$;
CREATE OR REPLACE FUNCTION catalogue.import_catalogue(p_rows jsonb, p_commit boolean, p_file text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_rows jsonb; v_sum jsonb; v_id uuid; v_ref text; v_valid jsonb;
        n_new int := 0; n_upd int := 0; n_rev int := 0; n_own int := 0; n_bnew int := 0; n_bupd int := 0; n_pre int := 0;
BEGIN
    v_rows := catalogue.import_catalogue_rows(p_rows);
    SELECT jsonb_build_object(
        'total', count(*),
        'valid', count(*) FILTER (WHERE x->>'state' = 'VALID'),
        'invalid', count(*) FILTER (WHERE x->>'state' = 'INVALID'),
        'skipped', count(*) FILTER (WHERE x->>'state' = 'SKIPPED'),
        'newCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND NOT (x->>'existing')::boolean),
        'existingCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'existing')::boolean),
        'revivedCourses', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'revived')::boolean),
        'ownerChanges', count(DISTINCT x->>'code') FILTER (WHERE x->>'state' = 'VALID' AND (x->>'ownerChange')::boolean),
        'newOfferings', count(*) FILTER (WHERE x->>'state' = 'VALID' AND NOT (x->>'existingOffering')::boolean),
        'existingOfferings', count(*) FILTER (WHERE x->>'state' = 'VALID' AND (x->>'existingOffering')::boolean),
        'duplicateOfferings', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "DUPLICATE_OFFERING")'),
        'conflicts', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "COURSE_CONFLICT")' OR x->'errors' @? '$[*] ? (@ starts with "COURSE_ENDED")'),
        'ownerErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "OWNER_")'),
        'programmeErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "PROGRAMME_")'),
        'departmentErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "DEPARTMENT_")'),
        'facultyErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ like_regex "FACULTY_")'),
        'typeErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "OFFERING_TYPE" || @ starts with "CLASSIFICATION" || @ starts with "COURSE_TYPE")'),
        'prerequisiteErrors', count(*) FILTER (WHERE x->'errors' @? '$[*] ? (@ starts with "PREREQUISITE")'))
      INTO v_sum
      FROM jsonb_array_elements(v_rows) x;
    IF NOT coalesce(p_commit, false) THEN
        RETURN jsonb_build_object('committed', false, 'summary', v_sum, 'rows', v_rows);
    END IF;

    IF who IS NULL THEN RAISE EXCEPTION 'a catalogue upload is committed by a person' USING ERRCODE = '23514'; END IF;
    IF (v_sum->>'invalid')::int > 0 THEN
        RAISE EXCEPTION 'CAT_IMPORT_INVALID: % row(s) are invalid; nothing was written', v_sum->>'invalid' USING ERRCODE = '23514',
            HINT = 'Download the error report, correct the rows and upload the file again.';
    END IF;
    IF (v_sum->>'valid')::int = 0 THEN
        RAISE EXCEPTION 'CAT_IMPORT_EMPTY: the file has no row to import' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('catalogue.course_catalogue'));
    v_ref := 'COURSE-IMPORT-' || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('COURSE_IMPORT', 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0');
    PERFORM set_config('moaum.reason', 'Course catalogue upload ' || v_ref, true);
    PERFORM set_config('moaum.owner_source', 'IMPORT', true);
    v_valid := (SELECT jsonb_agg(x) FROM jsonb_array_elements(v_rows) x WHERE x->>'state' = 'VALID');

    -- one course per code: its title, units, semester and owner from its rows; its level from the owner programme's row
    WITH per AS (
        SELECT x->>'code' AS code,
               (array_agg(x->>'title' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'title' IS NOT NULL))[1] AS title,
               (array_agg((x->>'units')::int ORDER BY (x->>'n')::int) FILTER (WHERE x->>'units' IS NOT NULL))[1] AS units,
               (array_agg((x->>'semester')::int ORDER BY (x->>'n')::int) FILTER (WHERE x->>'semester' IS NOT NULL))[1] AS semester,
               coalesce(bool_or((x->>'bothSemesters')::boolean) FILTER (WHERE x->>'semester' IS NOT NULL), false) AS both_sems,   -- V386
               (array_agg((x->>'level')::int ORDER BY coalesce(x->>'offeringProgramme' = x->>'ownerProgramme', false) DESC, (x->>'level')::int))[1] AS level,
               (array_agg(x->>'ownerDepartment' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'ownerDepartment' IS NOT NULL))[1] AS dept,
               (array_agg(x->>'ownerProgramme' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'ownerProgramme' IS NOT NULL))[1] AS prog,
               (array_agg(x->>'courseType' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'courseType' IS NOT NULL))[1] AS ctype,
               bool_or(x->>'basis' = 'GST') AS gst,
               -- V368: a row classified EPS files the course under the EPS office; GST is left to the code families
               bool_or(x->>'classification' = 'EPS') AS eps,
               (array_agg(x->>'description' ORDER BY (x->>'n')::int) FILTER (WHERE x->>'description' IS NOT NULL))[1] AS description,
               bool_or((x->>'existing')::boolean) AS existing, bool_or((x->>'general')::boolean) AS general,
               bool_or((x->>'revived')::boolean) AS revived, bool_or((x->>'ownerChange')::boolean) AS owner_change
          FROM jsonb_array_elements(v_valid) x GROUP BY x->>'code'
    ), ins AS (
        INSERT INTO catalogue.course (code, title, units, semester, both_semesters, level, dept_code, owner_programme, kind, description, state, general_office)
        SELECT p.code, p.title, p.units, p.semester, p.both_sems, p.level, p.dept, p.prog,
               CASE WHEN p.gst THEN 'GST' ELSE coalesce(p.ctype, 'Core') END, p.description, 'LIVE', CASE WHEN p.gst AND p.eps THEN 'EPS' END
          FROM per p WHERE NOT p.existing
        RETURNING 1
    ), upd AS (
        UPDATE catalogue.course c
           SET title = coalesce(p.title, c.title), units = coalesce(p.units, c.units), semester = coalesce(p.semester, c.semester),
               both_semesters = CASE WHEN p.semester IS NOT NULL THEN p.both_sems ELSE c.both_semesters END,
               dept_code = coalesce(p.dept, c.dept_code),
               owner_programme = CASE WHEN p.prog IS NOT NULL THEN p.prog WHEN p.dept IS NOT NULL AND p.dept <> c.dept_code THEN NULL ELSE c.owner_programme END,
               kind = CASE WHEN p.gst THEN 'GST' ELSE coalesce(p.ctype, c.kind) END,
               general_office = CASE WHEN p.gst AND p.eps THEN 'EPS' ELSE c.general_office END,
               description = coalesce(p.description, c.description),
               state = CASE WHEN c.reset_batch_id IS NOT NULL OR c.state IN ('BOARD', 'SENATE') THEN 'LIVE' ELSE c.state END,
               ended_on = CASE WHEN c.reset_batch_id IS NOT NULL THEN NULL ELSE c.ended_on END,
               reset_batch_id = NULL
          FROM per p
         WHERE c.code = p.code AND p.existing AND NOT p.general
        RETURNING 1
    )
    SELECT (SELECT count(*) FROM ins), (SELECT count(*) FROM upd),
           (SELECT count(*) FROM per WHERE revived), (SELECT count(*) FROM per WHERE owner_change)
      INTO n_new, n_upd, n_rev, n_own;

    -- the offerings: one binding per course, programme and level, Core / Elective / GST as the row says
    SELECT count(*) FILTER (WHERE NOT (x->>'existingOffering')::boolean), count(*) FILTER (WHERE (x->>'existingOffering')::boolean)
      INTO n_bnew, n_bupd FROM jsonb_array_elements(v_valid) x;
    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, added_by, source)
    SELECT x->>'code', x->>'offeringProgramme', (x->>'level')::int, x->>'basis', who, 'IMPORT'
      FROM jsonb_array_elements(v_valid) x
    ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis;

    -- the prerequisites
    WITH p AS (
        INSERT INTO catalogue.course_prerequisite (course_code, requires_code, added_by)
        SELECT DISTINCT x->>'code', q, who
          FROM jsonb_array_elements(v_valid) x CROSS JOIN LATERAL jsonb_array_elements_text(x->'prerequisites') q
        ON CONFLICT DO NOTHING
        RETURNING 1
    ) SELECT count(*) INTO n_pre FROM p;

    INSERT INTO catalogue.course_import (ref, file_name, rows, courses_created, courses_updated, courses_revived, owner_changes,
                                         offerings_created, offerings_updated, prerequisites, result, imported_by, imported_office)
    VALUES (v_ref, nullif(btrim(coalesce(p_file, '')), ''), (v_sum->>'total')::int, n_new, n_upd, n_rev, n_own, n_bnew, n_bupd, n_pre, v_rows, who, office)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('committed', true, 'id', v_id, 'ref', v_ref, 'summary', v_sum || jsonb_build_object(
               'coursesCreated', n_new, 'coursesUpdated', n_upd, 'coursesRevived', n_rev, 'ownerChangesMade', n_own,
               'offeringsCreated', n_bnew, 'offeringsUpdated', n_bupd, 'prerequisitesAdded', n_pre), 'rows', v_rows);
END $function$;

-- ── 5 · the course edited: its semester, or both ─────────────────────────────────────────────────────────────
DROP FUNCTION catalogue.update_course(text, text, integer, integer, integer, text);
CREATE OR REPLACE FUNCTION catalogue.update_course(p_code text, p_title text, p_units integer, p_semester integer, p_level integer, p_kind text, p_both boolean DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_code text := upper(btrim(coalesce(p_code, ''))); v_both boolean;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is edited by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF nullif(btrim(coalesce(p_title, '')), '') IS NULL OR length(btrim(p_title)) > 120 THEN
        RAISE EXCEPTION 'CAT_TITLE: a course has a title of up to 120 characters' USING ERRCODE = '23514';
    END IF;
    IF p_units IS NULL OR p_units < 0 OR p_units > 12 THEN
        RAISE EXCEPTION 'CAT_UNITS: a course is worth between 0 and 12 units' USING ERRCODE = '23514', HINT = 'Most courses are 2 or 3 units.';
    END IF;
    IF p_semester IS NULL OR p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'CAT_SEMESTER: a course is taught in the first, second or third semester' USING ERRCODE = '23514'; END IF;
    -- V386: or in both the first and the second
    v_both := coalesce(p_both, (SELECT both_semesters FROM catalogue.course WHERE code = v_code));
    IF v_both AND p_semester NOT IN (1, 2) THEN
        RAISE EXCEPTION 'CAT_SEMESTER_BOTH: a course taught in both semesters is taught in the first and the second' USING ERRCODE = '23514';
    END IF;
    IF p_level IS NULL OR p_level NOT BETWEEN 100 AND 900 OR p_level % 100 <> 0 THEN RAISE EXCEPTION 'CAT_LEVEL: a course is at a level from 100 to 900' USING ERRCODE = '23514'; END IF;
    IF coalesce(nullif(btrim(p_kind), ''), 'Core') NOT IN ('Core', 'Required', 'Elective', 'GST') THEN
        RAISE EXCEPTION 'CAT_KIND: a course is Core, Required, Elective or GST' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.course
       SET title = btrim(p_title), units = p_units, semester = CASE WHEN v_both THEN 1 ELSE p_semester END, both_semesters = v_both, level = p_level,
           kind = coalesce(nullif(btrim(p_kind), ''), 'Core')
     WHERE code = v_code;
END $function$;

-- ── 6 · the go-live reset clears the aliases with the courses ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION platform.reset_operational_data(p_confirm text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        r jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a data reset is made by a person' USING ERRCODE = '23514'; END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'RESET' THEN
        RAISE EXCEPTION 'type RESET to confirm clearing all uploaded data' USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a data reset names its reason' USING ERRCODE = '23514';
    END IF;

    SELECT jsonb_build_object(
        'students',     (SELECT count(*) FROM people.student),
        'candidates',   (SELECT count(*) FROM admissions.candidate),
        'applications', (SELECT count(*) FROM admissions.application),
        'results',      (SELECT count(*) FROM assessment.score),
        'courses',      (SELECT count(*) FROM catalogue.course),
        'fee_lines',    (SELECT count(*) FROM finance.fee_schedule),
        'payments',     (SELECT count(*) FROM finance.payment_reference),
        'wallet_entries', (SELECT count(*) FROM finance.wallet_entry),
        'staff_profiles', (SELECT count(*) FROM hrm.staff_profile),
        'pg_applications', (SELECT count(*) FROM admissions.pg_application),
        'college_enrolments', (SELECT count(*) FROM college.enrolment),
        'deferments', (SELECT count(*) FROM people.deferment)
    ) INTO r;

    PERFORM set_config('moaum.maintenance', 'on', true);
    UPDATE people.deferment SET fee_id = NULL WHERE fee_id IS NOT NULL;
    UPDATE credentials.issued SET request_id = NULL WHERE request_id IS NOT NULL;
    DELETE FROM admissions.caps_row_excluded;
    DELETE FROM admissions.eligibility_event;
    DELETE FROM admissions.programme_change_request;
    DELETE FROM admissions.eligibility_run;
    DELETE FROM admissions.pg_fee_reference;
    DELETE FROM admissions.pg_application;
    DELETE FROM admissions.pg_registration;
    DELETE FROM extexam.event;
    DELETE FROM extexam.assessment_score;
    DELETE FROM extexam.assessment;
    DELETE FROM extexam.assignment;
    DELETE FROM extexam.project_document_blob;
    DELETE FROM extexam.project_document;
    DELETE FROM extexam.project;
    DELETE FROM admissions.pg_research;
    DELETE FROM admissions.putme_event;
    DELETE FROM admissions.screening_answer;
    DELETE FROM admissions.screening_assignment;
    DELETE FROM admissions.screening_event;
    DELETE FROM admissions.screening_form;
    DELETE FROM admissions.screening_institution;
    DELETE FROM admissions.screening_olevel;
    DELETE FROM assessment.held_script;
    DELETE FROM assessment.siwes_supervisor;
    DELETE FROM college.assessment_score;
    DELETE FROM college.attendance_record;
    DELETE FROM college.carry_over;
    DELETE FROM college.case_clerking;
    DELETE FROM college.enrolment_semester;
    DELETE FROM college.enrolment;
    DELETE FROM college.event_attendance;
    DELETE FROM college.exam_result;
    DELETE FROM college.posting_allocation;
    DELETE FROM college.procedure_log;
    DELETE FROM college.progression_decision;
    DELETE FROM college.project;
    DELETE FROM credentials.delivery;
    DELETE FROM hostel.sanction;
    DELETE FROM hostel.incident;
    DELETE FROM hostel.swap_request;
    DELETE FROM hostel.transfer_request;
    DELETE FROM people.deferred_course;
    DELETE FROM people.deferment_fee;
    DELETE FROM people.deferment;
    DELETE FROM people.student_username_change;
    DELETE FROM people.matric_batch_edit;
    DELETE FROM people.matric_broadcast;
    DELETE FROM people.matric_reservation;
    DELETE FROM people.matric_batch_row;
    DELETE FROM people.matric_batch;
    DELETE FROM people.matric_history;

    DELETE FROM credentials.certificate;
    DELETE FROM credentials.stationery_batch;
    DELETE FROM credentials.transcript_request;
    DELETE FROM records.graduand;
    DELETE FROM clearance.item;

    DELETE FROM lms.submission_blob;
    DELETE FROM lms.submission;
    DELETE FROM lms.access;
    DELETE FROM lms.material_blob;
    DELETE FROM lms.material;
    DELETE FROM lms.assignment;
    DELETE FROM platform.request_document_blob;
    DELETE FROM platform.request_document;
    DELETE FROM platform.service_request;

    DELETE FROM health.note;
    DELETE FROM health.record_access;
    DELETE FROM health.visit;
    DELETE FROM health.appointment;
    DELETE FROM health.profile;

    -- the wallet and its funding trail (the funding SOURCES and the wallet POLICY, settings, are kept)
    DELETE FROM finance.paydirect_collection;
    DELETE FROM finance.wallet_withdrawal;
    DELETE FROM finance.legacy_nelfund_reconciliation;   -- V327: the reconciliation hangs on the wallet entries and the students
    DELETE FROM finance.wallet_entry;
    DELETE FROM finance.legacy_nelfund_payment;
    DELETE FROM finance.legacy_nelfund_import;
    DELETE FROM finance.nelfund_row;
    DELETE FROM finance.nelfund_batch;
    DELETE FROM finance.nelfund_status;

    DELETE FROM library.reservation;
    DELETE FROM library.loan;

    DELETE FROM hostel.maintenance_request;
    DELETE FROM hostel.allocation;
    DELETE FROM hostel.application;

    -- V358: the amendments of published results, and their decisions, before the queries and sheets they hang on
    DELETE FROM assessment.amendment_decision;
    DELETE FROM assessment.amendment;
    -- V359: the reminders and escalations of score sheets, before the sheets
    DELETE FROM assessment.sheet_chase;
    DELETE FROM assessment.result_query;
    DELETE FROM assessment.exam_timetable;
    DELETE FROM registration.attendance;
    DELETE FROM catalogue.class_slot;
    DELETE FROM credentials.identity_card;

    DELETE FROM finance.gateway_event;
    DELETE FROM finance.gateway_attempt;
    DELETE FROM finance.bank_credit;
    DELETE FROM finance.payment_reconciliation;
    DELETE FROM finance.refund;
    DELETE FROM finance.legacy_gst_reconciliation;
    DELETE FROM finance.legacy_gst_payment;
    DELETE FROM finance.legacy_gst_import;
    DELETE FROM finance.legacy_student_crosswalk;
    DELETE FROM finance.payment_reference;
    DELETE FROM finance.fee_schedule;

    DELETE FROM iam.student_account;
    DELETE FROM iam.student_event;
    DELETE FROM people.student_contact;
    DELETE FROM platform.session WHERE active_office IN ('student', 'applicant');

    DELETE FROM hrm.staff_photo;
    DELETE FROM hrm.staff_profile;

    DELETE FROM assessment.sheet_upload;
    DELETE FROM assessment.score;
    DELETE FROM assessment.decision;
    DELETE FROM assessment.score_sheet;
    DELETE FROM assessment.exam_session;
    DELETE FROM assessment.cbt_event;
    DELETE FROM assessment.cbt_answer;
    DELETE FROM assessment.cbt_result;
    DELETE FROM assessment.cbt_attempt;
    DELETE FROM assessment.cbt_exam_question;
    DELETE FROM assessment.cbt_exam;
    DELETE FROM assessment.question;
    DELETE FROM registration.entry;
    DELETE FROM registration.course_registration;
    DELETE FROM catalogue.offering;
    DELETE FROM catalogue.course_alias;   -- V386: a merged code goes with the course it answers for
    DELETE FROM catalogue.course_offer;
    DELETE FROM catalogue.course;

    DELETE FROM people.faculty_list_query;
    DELETE FROM people.faculty_list;
    DELETE FROM people.biodata_change;
    DELETE FROM people.biodata;
    DELETE FROM people.document;
    DELETE FROM people.status_change;
    DELETE FROM people.enrolment;
    DELETE FROM people.search_log;
    DELETE FROM people.transfer_application;
    DELETE FROM people.student;
    DELETE FROM people.matriculation_run;

    DELETE FROM credentials.revocation;
    DELETE FROM credentials.issued;
    DELETE FROM credentials.lookup_miss;

    DELETE FROM platform.notice;
    DELETE FROM admissions.password_reset;
    DELETE FROM admissions.clearance_document;
    DELETE FROM admissions.application_document_blob;
    DELETE FROM admissions.application_document;
    DELETE FROM admissions.fee_reference;
    DELETE FROM admissions.suggestion_sent;
    DELETE FROM admissions.application;
    DELETE FROM admissions.applicant_account;
    DELETE FROM admissions.applicant_event;
    DELETE FROM admissions.screening_batch;
    DELETE FROM admissions.jamb_admission;
    DELETE FROM admissions.olevel_grade;
    DELETE FROM admissions.olevel_sitting;
    DELETE FROM admissions.candidate_photo;
    DELETE FROM admissions.attachment;
    DELETE FROM admissions.candidate;
    DELETE FROM admissions.caps_row;
    DELETE FROM admissions.caps_batch;

    PERFORM set_config('moaum.maintenance', '', true);
    RETURN r || jsonb_build_object('reset', true, 'reason', btrim(p_reason));
END $function$;

COMMENT ON FUNCTION catalogue.update_course(text, text, integer, integer, integer, text, boolean) IS
  'V386: a course edited in place — its title, units, semester (or both the first and the second), level and kind; the same course, never a copy.';

COMMIT;

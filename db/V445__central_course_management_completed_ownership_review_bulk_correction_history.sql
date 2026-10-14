-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V445 — central course management, completed: the ownership review, the bulk correction, the history
--
--   The University asked for one authoritative place to see every course, verify that each belongs to the right
--   department, and let the same course be offered by other departments and programmes without a second record. Most
--   of that already stands: one canonical course (catalogue.course, V013/V332/V386), its owner department and owner
--   programme (V338), its offerings as programme bindings (catalogue.course_offer — the departments offering a course are
--   the departments of the programmes bound to it), proposals across departments (V332), the All courses list with
--   server-side search, filters, sorting and paging, the course page with its offerings, usage, owner history, Change
--   owner with a reason, merges of a code written twice (V386), and the code-names-the-owner rule (V443). What was
--   missing is added here, and nothing is duplicated:
--
--   1 · a REVIEW STATUS on the course — NOT_REVIEWED, REVIEWED, CORRECT, INCORRECT_OWNER, REQUIRES_REVIEW — set by the
--       central offices or the owning department's Head, with a note; and the ISSUES the review flags without deciding
--       anything: the code names another department (rule or map), the owner offers it to no programme of its own, it is
--       in no structure, it was moved by the V443 rule (to confirm or revert), it may be a duplicate, its owner has ended.
--   2 · CREATED/UPDATED stamps on the course, kept by trigger and backfilled from the audit spine, so a list can say when a
--       course last changed and by whom.
--   3 · POSSIBLE DUPLICATES by title (V386 found the same code written twice): the same title under two codes at the same
--       level and semester — flagged, never merged by themselves; V386's merge stays the road for a confirmed pair.
--   4 · a FIELD-LEVEL HISTORY of a course read from the audit spine (what changed, from what, to what, by whom, why),
--       beside the owner trail and the offer history the course page already shows.
--   5 · the BULK owner correction: many courses to one department in one transaction with one reason, each change on the
--       owner trail (V338's change_owner, course by course; one refusal undoes all).
--   The review never changes an owner by itself: the owner is set by a person, with a reason, on the trail.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'V445: central course management completed', true);
END $seed$;

-- ── 1 · the review status, and the stamps ───────────────────────────────────────────────────────────────────────────
ALTER TABLE catalogue.course
    ADD COLUMN review_status  text NOT NULL DEFAULT 'NOT_REVIEWED',
    ADD COLUMN review_note    text NULL,
    ADD COLUMN reviewed_by    uuid NULL,
    ADD COLUMN reviewed_office text NULL,
    ADD COLUMN reviewed_at    timestamptz NULL,
    ADD COLUMN created_at     timestamptz NULL,
    ADD COLUMN created_by     uuid NULL,
    ADD COLUMN updated_at     timestamptz NULL,
    ADD COLUMN updated_by     uuid NULL,
    ADD CONSTRAINT ck_course_review CHECK (review_status IN ('NOT_REVIEWED', 'REVIEWED', 'CORRECT', 'INCORRECT_OWNER', 'REQUIRES_REVIEW'));
CREATE INDEX ix_course_review ON catalogue.course (review_status);
CREATE INDEX ix_course_updated ON catalogue.course (updated_at DESC);
COMMENT ON COLUMN catalogue.course.review_status IS 'V445: the ownership review''s word on the course — NOT_REVIEWED until a person says CORRECT, INCORRECT_OWNER, REQUIRES_REVIEW or simply REVIEWED; never set by a rule.';

-- the stamps, backfilled from the audit spine (the subject of a course row is md5(relid|code), V002)
UPDATE catalogue.course c
   SET created_at = x.first_at, created_by = x.first_by, updated_at = coalesce(x.last_at, x.first_at), updated_by = coalesce(x.last_by, x.first_by)
  FROM (SELECT c2.code,
               (SELECT e.occurred_at FROM audit.entries e WHERE e.subject_type = 'catalogue.course' AND e.subject_id = md5('catalogue.course'::regclass::oid::text || '|' || c2.code)::uuid ORDER BY e.occurred_at LIMIT 1) AS first_at,
               (SELECT e.actor_id FROM audit.entries e WHERE e.subject_type = 'catalogue.course' AND e.subject_id = md5('catalogue.course'::regclass::oid::text || '|' || c2.code)::uuid ORDER BY e.occurred_at LIMIT 1) AS first_by,
               (SELECT e.occurred_at FROM audit.entries e WHERE e.subject_type = 'catalogue.course' AND e.subject_id = md5('catalogue.course'::regclass::oid::text || '|' || c2.code)::uuid ORDER BY e.occurred_at DESC LIMIT 1) AS last_at,
               (SELECT e.actor_id FROM audit.entries e WHERE e.subject_type = 'catalogue.course' AND e.subject_id = md5('catalogue.course'::regclass::oid::text || '|' || c2.code)::uuid ORDER BY e.occurred_at DESC LIMIT 1) AS last_by
          FROM catalogue.course c2) x
 WHERE x.code = c.code;

CREATE OR REPLACE FUNCTION catalogue.course_stamp()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_at := coalesce(NEW.created_at, now());
        NEW.created_by := coalesce(NEW.created_by, nullif(current_setting('moaum.actor_id', true), '')::uuid);
    END IF;
    NEW.updated_at := now();
    NEW.updated_by := coalesce(nullif(current_setting('moaum.actor_id', true), '')::uuid, NEW.updated_by);
    RETURN NEW;
END $$;
CREATE TRIGGER trg_course_stamp BEFORE INSERT OR UPDATE ON catalogue.course
FOR EACH ROW EXECUTE FUNCTION catalogue.course_stamp();

CREATE OR REPLACE FUNCTION catalogue.set_course_review(p_code text, p_status text, p_note text, p_actor uuid, p_office text, p_office_dept text)
RETURNS catalogue.course LANGUAGE plpgsql AS $$
DECLARE c catalogue.course;
BEGIN
    IF p_status IS NULL OR p_status NOT IN ('NOT_REVIEWED', 'REVIEWED', 'CORRECT', 'INCORRECT_OWNER', 'REQUIRES_REVIEW') THEN
        RAISE EXCEPTION 'REVIEW_STATUS: a review is NOT_REVIEWED, REVIEWED, CORRECT, INCORRECT_OWNER or REQUIRES_REVIEW' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = regexp_replace(upper(btrim(coalesce(p_code, ''))), '\s+', ' ', 'g') FOR UPDATE;
    IF c.code IS NULL THEN
        RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503';
    END IF;
    -- the central offices review any course; a Head of Department or Dean the courses their department (faculty) owns
    IF p_office IS NULL OR p_office NOT IN ('academic', 'registrar', 'dregistrar', 'admin', 'super', 'hod', 'dean') THEN
        RAISE EXCEPTION 'REVIEW_OFFICE: a course is reviewed by the Academic Office, the Registry, an administrator, or the Head of the department that owns it' USING ERRCODE = '23514';
    END IF;
    IF p_office IN ('hod', 'dean') AND (p_office_dept IS NULL
            OR NOT (c.dept_code = p_office_dept OR EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c.dept_code AND d.faculty_code = p_office_dept))) THEN
        RAISE EXCEPTION 'REVIEW_SCOPE: % belongs to %, outside your department', c.code, c.dept_code USING ERRCODE = '23514';
    END IF;
    IF p_status IN ('INCORRECT_OWNER', 'REQUIRES_REVIEW') AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'REVIEW_NOTE: say what is wrong, or what must be looked at' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.course
       SET review_status = p_status, review_note = nullif(btrim(coalesce(p_note, '')), ''),
           reviewed_by = CASE WHEN p_status = 'NOT_REVIEWED' THEN NULL ELSE p_actor END,
           reviewed_office = CASE WHEN p_status = 'NOT_REVIEWED' THEN NULL ELSE p_office END,
           reviewed_at = CASE WHEN p_status = 'NOT_REVIEWED' THEN NULL ELSE now() END
     WHERE code = c.code
    RETURNING * INTO c;
    RETURN c;
END $$;

-- ── 2 · the issues the review flags, never deciding ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.title_key(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p, '')), '\mintro\M', 'introduction', 'g'), '\m&\M', 'and', 'g'), '[^a-z0-9]', '', 'g')
$$;
CREATE INDEX ix_course_title_key ON catalogue.course (catalogue.title_key(title));
COMMENT ON FUNCTION catalogue.title_key(text) IS 'V445: a title reduced to its letters and digits, "Intro" read as "Introduction" and "&" as "and", so that the same course under two codes is found by its title.';

CREATE OR REPLACE FUNCTION catalogue.course_issues(p_code text)
RETURNS text[] LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT * FROM catalogue.course WHERE code = p_code)
    SELECT array_remove(ARRAY[
        CASE WHEN c.general_office IS NULL AND coalesce(c.kind, '') <> 'GST'
              AND catalogue.course_owner_by_code(c.code) IS NOT NULL AND catalogue.course_owner_by_code(c.code) <> c.dept_code THEN 'CODE_NAMES_OTHER' END,
        CASE WHEN c.general_office IS NULL
              AND EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)
              AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code
                               WHERE co.course_code = c.code AND p.dept_code = c.dept_code) THEN 'OWNER_OFFERS_NOTHING' END,
        CASE WHEN c.state <> 'ENDED' AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code) THEN 'NOT_IN_STRUCTURE' END,
        CASE WHEN (SELECT h.source FROM catalogue.course_owner_history h WHERE h.course_id = c.id ORDER BY h.changed_at DESC LIMIT 1) = 'CODE'
              AND c.review_status = 'NOT_REVIEWED' THEN 'MOVED_BY_RULE' END,
        CASE WHEN EXISTS (SELECT 1 FROM catalogue.course o
                           WHERE o.code <> c.code AND o.code NOT LIKE 'DMO %' AND o.state <> 'ENDED'
                             AND (catalogue.code_key(o.code) = catalogue.code_key(c.code)
                                  OR (catalogue.title_key(o.title) = catalogue.title_key(c.title) AND o.level = c.level AND o.semester = c.semester))) THEN 'POSSIBLE_DUPLICATE' END,
        CASE WHEN NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = c.dept_code AND d.ended_on IS NULL) THEN 'OWNER_NOT_LIVE' END
    ], NULL)
      FROM c
$$;
COMMENT ON FUNCTION catalogue.course_issues(text) IS
  'V445: what the ownership review flags on a course — CODE_NAMES_OTHER, OWNER_OFFERS_NOTHING, NOT_IN_STRUCTURE, MOVED_BY_RULE, POSSIBLE_DUPLICATE, OWNER_NOT_LIVE — for a person to judge; nothing is changed by a flag.';

-- the review's dashboard: one pass over the pool
CREATE OR REPLACE FUNCTION catalogue.review_summary()
RETURNS TABLE (total bigint, live bigint, ended bigint, not_reviewed bigint, reviewed bigint, correct bigint, incorrect_owner bigint, requires_review bigint,
               with_issues bigint, code_names_other bigint, owner_offers_nothing bigint, not_in_structure bigint, moved_by_rule bigint, possible_duplicates bigint,
               departments bigint)
LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT code, state, review_status, dept_code, catalogue.course_issues(code) AS issues FROM catalogue.course WHERE code NOT LIKE 'DMO %')
    SELECT count(*), count(*) FILTER (WHERE state <> 'ENDED'), count(*) FILTER (WHERE state = 'ENDED'),
           count(*) FILTER (WHERE review_status = 'NOT_REVIEWED'), count(*) FILTER (WHERE review_status = 'REVIEWED'),
           count(*) FILTER (WHERE review_status = 'CORRECT'), count(*) FILTER (WHERE review_status = 'INCORRECT_OWNER'), count(*) FILTER (WHERE review_status = 'REQUIRES_REVIEW'),
           count(*) FILTER (WHERE cardinality(issues) > 0),
           count(*) FILTER (WHERE 'CODE_NAMES_OTHER' = ANY (issues)), count(*) FILTER (WHERE 'OWNER_OFFERS_NOTHING' = ANY (issues)),
           count(*) FILTER (WHERE 'NOT_IN_STRUCTURE' = ANY (issues)), count(*) FILTER (WHERE 'MOVED_BY_RULE' = ANY (issues)),
           count(*) FILTER (WHERE 'POSSIBLE_DUPLICATE' = ANY (issues)),
           count(DISTINCT dept_code)
      FROM c
$$;

-- ── 3 · possible duplicates by title ────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.possible_duplicates()
RETURNS TABLE (evidence text, keep_code text, merge_code text, keep_title text, merge_title text, keep_dept text, merge_dept text,
               keep_state text, merge_state text, keep_uses bigint, merge_uses bigint, differences text[])
LANGUAGE sql STABLE AS $$
    WITH c AS (
        SELECT x.code, x.title, x.units, x.semester, x.level, x.kind, x.dept_code, x.state, catalogue.title_key(x.title) AS t, catalogue.code_key(x.code) AS k,
               (SELECT count(*) FROM catalogue.offering o WHERE o.course_code = x.code)
             + (SELECT count(*) FROM catalogue.course_offer co WHERE co.course_code = x.code) AS uses
          FROM catalogue.course x WHERE x.code NOT LIKE 'DMO %' AND x.state <> 'ENDED' AND length(x.title) >= 8)
    SELECT 'SAME_TITLE_LEVEL_AND_SEMESTER'::text,
           CASE WHEN a.uses >= b.uses THEN a.code ELSE b.code END, CASE WHEN a.uses >= b.uses THEN b.code ELSE a.code END,
           CASE WHEN a.uses >= b.uses THEN a.title ELSE b.title END, CASE WHEN a.uses >= b.uses THEN b.title ELSE a.title END,
           CASE WHEN a.uses >= b.uses THEN a.dept_code ELSE b.dept_code END, CASE WHEN a.uses >= b.uses THEN b.dept_code ELSE a.dept_code END,
           CASE WHEN a.uses >= b.uses THEN a.state ELSE b.state END, CASE WHEN a.uses >= b.uses THEN b.state ELSE a.state END,
           greatest(a.uses, b.uses), least(a.uses, b.uses),
           array_remove(ARRAY[CASE WHEN a.units <> b.units THEN 'UNITS' END, CASE WHEN a.kind IS DISTINCT FROM b.kind THEN 'KIND' END,
                              CASE WHEN a.dept_code <> b.dept_code THEN 'OWNER' END], NULL)
      FROM c a JOIN c b ON b.t = a.t AND b.level = a.level AND b.semester = a.semester AND b.k <> a.k AND a.code < b.code
     ORDER BY 4, 2
$$;
COMMENT ON FUNCTION catalogue.possible_duplicates() IS
  'V445: pairs of live courses under different codes with the same title (read loosely), level and semester — possible duplicates for a person to investigate; V386''s merge is the road for a confirmed pair, never this.';

-- ── 4 · a course's history, field by field, from the audit spine ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.course_history(p_code text, p_limit int DEFAULT 200)
RETURNS TABLE (at timestamptz, action text, field text, old_value text, new_value text, actor text, actor_office text, reason text, source text)
LANGUAGE sql STABLE AS $$
    WITH codes AS (
        SELECT p_code AS code
        UNION SELECT a.alias_code FROM catalogue.course_alias a WHERE a.course_code = p_code
    ),
    subjects AS (SELECT md5('catalogue.course'::regclass::oid::text || '|' || code)::uuid AS id FROM codes),
    e AS (
        SELECT e.occurred_at, e.action, e.before_state, e.after_state, e.actor_id, e.actor_office, e.reason
          FROM audit.entries e
         WHERE e.subject_type = 'catalogue.course' AND e.subject_id IN (SELECT id FROM subjects)
         ORDER BY e.occurred_at DESC LIMIT greatest(1, p_limit)
    ),
    changes AS (
        SELECT e.occurred_at, 'CHANGED'::text AS action, k AS field, e.before_state->>k AS old_value, e.after_state->>k AS new_value, e.actor_id, e.actor_office, e.reason
          FROM e, LATERAL jsonb_object_keys(coalesce(e.after_state, '{}'::jsonb)) k
         WHERE e.action = 'UPDATE' AND e.before_state->>k IS DISTINCT FROM e.after_state->>k
           AND k NOT IN ('updated_at', 'updated_by', 'reset_batch_id', 'review_note', 'reviewed_by', 'reviewed_office', 'reviewed_at')
        UNION ALL
        SELECT e.occurred_at, 'CREATED', NULL, NULL, e.after_state->>'code', e.actor_id, e.actor_office, e.reason FROM e WHERE e.action = 'INSERT'
    )
    SELECT ch.occurred_at, ch.action, ch.field, ch.old_value, ch.new_value,
           coalesce(helpdesk.person_name(ch.actor_id), CASE WHEN ch.actor_id = '00000000-0000-0000-0000-000000000000' THEN 'the migration' END, 'Unknown'),
           ch.actor_office, ch.reason, 'AUDIT'
      FROM changes ch
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
  'V445: what changed on a course and when — every field from the audit spine (the code''s own entries and its merged codes''), each owner change from the trail, each binding added or ended — by whom, as which office, why.';

-- ── 5 · many courses to one owner, in one transaction ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.change_owner_bulk(p_codes text[], p_dept text, p_programme text, p_reason text)
RETURNS TABLE (code text, from_dept text, to_dept text)
LANGUAGE plpgsql AS $$
DECLARE v_code text; v_from text; v_to text; n int := 0;
BEGIN
    IF p_codes IS NULL OR cardinality(p_codes) = 0 THEN
        RAISE EXCEPTION 'CAT_OWNER_BULK_EMPTY: choose the courses to move' USING ERRCODE = '23514';
    END IF;
    IF cardinality(p_codes) > 500 THEN
        RAISE EXCEPTION 'CAT_OWNER_BULK_LIMIT: at most 500 courses move in one act' USING ERRCODE = '23514';
    END IF;
    FOREACH v_code IN ARRAY p_codes LOOP
        v_code := regexp_replace(upper(btrim(coalesce(v_code, ''))), '\s+', ' ', 'g');
        SELECT c.dept_code INTO v_from FROM catalogue.course c WHERE c.code = v_code;
        IF v_from IS NULL THEN
            RAISE EXCEPTION 'no course is coded %', v_code USING ERRCODE = '23503';
        END IF;
        PERFORM set_config('moaum.owner_source', 'BULK', true);
        PERFORM catalogue.change_owner(v_code, p_dept, p_programme, p_reason);   -- V338: validated, on the trail; a refusal undoes the whole act
        SELECT c.dept_code INTO v_to FROM catalogue.course c WHERE c.code = v_code;
        code := v_code; from_dept := v_from; to_dept := v_to;
        RETURN NEXT;
    END LOOP;
    PERFORM set_config('moaum.owner_source', '', true);   -- a change after this, in the same session, is the desk's own again
END $$;
COMMENT ON FUNCTION catalogue.change_owner_bulk(text[], text, text, text) IS
  'V445: the owner of many courses changed to one department (and optionally one programme) with one reason, course by course through change_owner — all or none; each on the owner trail as BULK.';

-- ── 6 · change_owner (V338) restated: a source already named by the caller (BULK, IMPORT) stays on the trail; DESK otherwise ──
CREATE OR REPLACE FUNCTION catalogue.change_owner(p_code text, p_dept text, p_programme text, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; c catalogue.course; v_dept text; v_prog text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course''s owner is changed by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'CAT_OWNER_REASON: say why the course changes owner' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF c.code IS NULL THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF c.general_office IS NOT NULL THEN
        RAISE EXCEPTION 'CAT_OWNER_GENERAL: % is a % course; its office keeps it', c.code, upper(c.general_office) USING ERRCODE = '23514',
            HINT = 'The GST/EPS office changes its own course''s department on its desk.';
    END IF;
    SELECT d.code INTO v_dept FROM ref.department d
     WHERE d.ended_on IS NULL AND (upper(d.code) = upper(btrim(coalesce(p_dept, ''))) OR upper(d.name) = upper(btrim(coalesce(p_dept, '')))) LIMIT 1;
    IF v_dept IS NULL THEN RAISE EXCEPTION 'CAT_OWNER_DEPT: no live department is coded or named %', p_dept USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_programme, '')), '') IS NOT NULL THEN
        SELECT p.code INTO v_prog FROM ref.programme p
         WHERE NOT coalesce(p.archived, false) AND (upper(p.code) = upper(btrim(p_programme)) OR upper(p.name) = upper(btrim(p_programme)))
         ORDER BY (p.dept_code = v_dept) DESC LIMIT 1;
        IF v_prog IS NULL THEN RAISE EXCEPTION 'CAT_OWNER_PROGRAMME: no live programme is coded or named %', p_programme USING ERRCODE = '23514'; END IF;
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    -- V445: the bulk correction names its source before each call and clears it after; any other caller's change is the desk's own
    PERFORM set_config('moaum.owner_source', CASE WHEN nullif(current_setting('moaum.owner_source', true), '') = 'BULK' THEN 'BULK' ELSE 'DESK' END, true);
    UPDATE catalogue.course SET dept_code = v_dept, owner_programme = v_prog WHERE code = c.code;
END $$;

COMMIT;

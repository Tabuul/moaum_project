-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V771 · A past result keeps the course as it was taken: its code, title, credit units and category from the upload template
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The user's master prompt of 15 November 2026 ("historical course unit preservation, result re-upload correction ..." and its §12,
--  "historical course code, course title and unit version control"), and the University's decisions the same day:
--    D1 credit units are read only from a column naming them ("Credit Units"); the old portal's "Units" was a status code (1 GST,
--       2 core, 3 elective, 0 carry-over — V123), so a file whose only units column is a bare "Units" is stopped on the screen;
--    D2 the Past results AND Course registration uploads carry Course Title and Credit Units on every row; a row without them (or with
--       an invalid one) is refused and listed, never filled from today's catalogue;
--    D3 a Senate-approved graduate whose units a corrected template changes keeps the approved CGPA and class of degree; they are
--       listed in the upload's report for the Registry (the graduation audit no longer recomputes an approved graduand — Java);
--    D5 (the user's own suggestion) every row carries its Category — Core, Elective, GST, Carry-over (the old portal's 2, 3, 1, 0) —
--       recorded on the student's registration as taken, so a failed elective is never owed as a carry-over.
--
--  What was wrong (assessment.legacy_semester_load, V672 + V752): the loader never read the file's units or title. A new registration
--  took catalogue.units_for(code, the student's CURRENT programme, level), a class it created took today's title and units
--  (catalogue.offering_snapshot), an entry on record was never corrected (UNITS_DIFFER compared it with today's catalogue), and a
--  renamed code reached every past class (offering.course_code cascades). Every GPA, CGPA, broadsheet and transcript reads the frozen
--  registration.entry.units, so today's catalogue became history.
--
--  Now:
--    · catalogue.course_as_taken — the class (offering: course, session, semester, stream) as a student took it: the code as written in
--      the file (kept when the course is later renamed), the title and the credit units; one row per distinct (class, code, title,
--      units), never updated, never overwriting another; the programme it was first taken under is recorded, not part of its identity.
--      registration.entry.as_taken_id points at it, and entry.units always equals its units (registration.entry_as_taken_follows: a
--      Senate units amendment, or a class move, re-points the entry to a version with the new units or class — the Senate route wins,
--      history keeps both). The current catalogue is never touched.
--    · assessment.legacy_semester_load restated (DROP + CREATE: two trailing parameters, p_upload and p_as_taken; the old five-argument
--      calls resolve through the defaults). As taken (the API always): title, credit units and category are required per row and
--      checked before anything else, a held row included; the course is identified by its code AND title (a code alone never decides
--      between courses that share it — V646 variants, a former code a rename left behind: COURSE_AMBIGUOUS, listed); a new entry takes
--      the file's units, title, code and category; an entry on record is corrected (units, code/title as taken, category) by the
--      Directorate of ICT's offices only, never over a result entered on the portal (UNITS_ON_PORTAL), never over a Senate units
--      amendment (UNITS_BY_AMENDMENT), never onto a course removed from the registration (REMOVED_ON_RECORD / REMOVAL_PENDING), never by
--      a second entry when the record holds the course under another of its codes (COURSE_ON_RECORD_ELSEWHERE); duplicates of one
--      student's course in the file are refused when they disagree; the result goes on the class's main sitting.
--    · Every change an upload makes is written to its ledger (assessment.past_upload_change: the backup — what was there before),
--      with each student's CGPA before and after (assessment.past_upload_student: the reconciliation), graduates marked.
--    · The check returns, per row, the code/title/units uploaded, the current title and units, the course matched and how, the version
--      used and the action; per course as taken; and each student's GPA and CGPA before and after.
--    · Readers: assessment.student_results (transcripts, statements, the student's results, verification, the full record) and
--      assessment.result_records (the ICT result viewer) give the title as taken and a new code_as_taken; the transcript prints it.
--    · catalogue.reflect_units and its impact readers leave a course as taken alone, and ARCHIVED/CANCELLED sessions as CLOSED ones.
--    · An issued transcript is flagged when the printed code or title of a course changes, not only its units.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V771: a past result keeps the course as it was taken', true);

-- presence: every function restated whole here is as the earlier migrations left it (another change since would be overwritten)
DO $$
DECLARE f text; h text; want text;
BEGIN
    FOR f, want IN VALUES
        ('assessment.legacy_semester_load(text,integer,jsonb,boolean,boolean)', '96acc11f72fac37fea16747100b26007'),
        ('assessment.student_results(uuid)', '0bdde2f33312adfa163050f6b0756b41'),
        ('assessment.result_records(text,integer,text,text,text,integer,text)', 'c2dc7f288a732f014055fba5ed646573'),
        ('catalogue.reflect_units(text,text,integer)', '0ba5a1e70362e4cd070923b435cc58a5'),
        ('catalogue.units_change_rows(text,text,integer,integer)', '90effbd9eae86406a52a24eb5809e139'),
        ('catalogue.course_units_change_rows(text,integer)', 'a906a6338ebd5a4c30e18a6dc63ba32b'),
        ('assessment.reconcile_legacy_holding()', '7a12fe56b9e50c567fa7d1fd648e692b'),
        ('credentials.entry_units_changed()', 'b72dc23715ed534b55461bac6a1ded36')
    LOOP
        SELECT md5(replace(p.prosrc, E'\r', '')) INTO h FROM pg_proc p WHERE p.oid = to_regprocedure(f);
        IF h IS DISTINCT FROM want THEN
            RAISE EXCEPTION 'V771: % is not as the earlier migrations left it (restate this migration from its live text)', f;
        END IF;
    END LOOP;
END $$;

-- ── the code and the title as written ───────────────────────────────────────────────────────────────────────────────────────────
-- the code as the file wrote it, spaced as the catalogue spaces codes, an old portal's session-copy year ("CSC 301 (2019)") dropped
CREATE FUNCTION catalogue.code_as_written(p text)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE v_clean text := nullif(regexp_replace(upper(btrim(coalesce(p, ''))), '\s+', ' ', 'g'), ''); v_base text;
BEGIN
    IF v_clean IS NULL THEN RETURN NULL; END IF;
    v_base := coalesce(catalogue.session_copy_base(v_clean), v_clean);
    RETURN coalesce(catalogue.normal_code(v_base), regexp_replace(v_base, '^([A-Z]{2,4})\s*([0-9]{3})$', '\1 \2'));
END $$;
COMMENT ON FUNCTION catalogue.code_as_written(text) IS
  'V771: a course code as a file wrote it — upper case, single spaces, ABC123 as ABC 123, an old portal''s session-copy year dropped; kept on a course as taken even when the course is later renamed.';

CREATE FUNCTION catalogue.title_as_written(p text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT nullif(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'), '') $$;
COMMENT ON FUNCTION catalogue.title_as_written(text) IS
  'V771: a course title as a file wrote it, trimmed, spaces single — kept exactly (a corrected spelling is a different title).';

-- ── the upload, its ledger and its students ─────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE assessment.past_upload (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref text NOT NULL UNIQUE CHECK (ref ~ '^PRU-[0-9]{4}-[0-9]{5,}$'),
    kind text NOT NULL CHECK (kind IN ('RESULTS', 'REGISTRATION')),
    file_name text,
    rows int NOT NULL CHECK (rows >= 0),
    reason text NOT NULL CHECK (length(btrim(reason)) >= 10),
    state text NOT NULL DEFAULT 'RUNNING' CHECK (state IN ('RUNNING', 'COMPLETE', 'INCOMPLETE', 'REVERTED')),
    counts jsonb,
    created_by uuid NOT NULL,
    created_office text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    finished_by uuid,
    reverted_at timestamptz, reverted_by uuid, reverted_office text, revert_reason text, revert_counts jsonb
);
COMMENT ON TABLE assessment.past_upload IS
  'V771: one confirmed old-portal upload (Past results or Course registration) — PRU-YYYY-NNNNN, the reason given on confirming, the person and office; its changes are in past_upload_change, its students'' CGPA before and after in past_upload_student.';
SELECT audit.attach('assessment.past_upload');

CREATE TABLE assessment.past_upload_change (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    seq bigint GENERATED ALWAYS AS IDENTITY,
    upload_id uuid NOT NULL REFERENCES assessment.past_upload (id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('ENTRY_ADDED', 'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED',
                                       'ENTRY_REAPPROVED', 'RESULT_POSTED', 'RESULT_REPLACED', 'CLASS_HEADER_CORRECTED',
                                       'REGISTRATION_ADDED', 'ENROLMENT_ADDED')),
    student_id uuid REFERENCES people.student (id) ON DELETE CASCADE,
    -- snapshots: the record as it stood, never keys (they outlive renames, merges and the go-live reset)
    registration_id uuid, offering_id uuid, course_code text, session text, semester int, line text,
    was_units int, now_units int, was_as_taken uuid, now_as_taken uuid, was_code text, now_code text, was_title text, now_title text,
    was_entry_type text, now_entry_type text, was_basis text, now_basis text, was_status text, now_status text,
    sheet_id uuid, was_score_version int, now_score_version int, undo_score_version int, level int, course_kind text,
    graduate boolean NOT NULL DEFAULT false,
    changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    reverted_at timestamptz, revert_note text
);
CREATE INDEX ix_past_upload_change ON assessment.past_upload_change (upload_id, seq);
CREATE INDEX ix_past_upload_change_student ON assessment.past_upload_change (student_id);
CREATE INDEX ix_past_upload_change_entry ON assessment.past_upload_change (registration_id, offering_id) WHERE registration_id IS NOT NULL;
CREATE INDEX ix_past_upload_change_header ON assessment.past_upload_change (offering_id) WHERE kind = 'CLASS_HEADER_CORRECTED';
CREATE INDEX ix_past_upload_change_reverted ON assessment.past_upload_change (reverted_at) WHERE reverted_at IS NOT NULL;
COMMENT ON TABLE assessment.past_upload_change IS
  'V771: what an old-portal upload changed, one row a change, with what was there before (the backup) and what the file put — an entry added or re-approved, units / code and title as taken / category corrected, a result posted or replaced (score versions), a class''s header set to the version all its students took.';
COMMENT ON COLUMN assessment.past_upload_change.course_kind IS
  'V771: the course''s kind in the catalogue when the change was made (a GST course reads GST whatever its entry says) — kept so the upload''s report reads the same after a rename or a reclassification.';
COMMENT ON COLUMN assessment.past_upload_change.undo_score_version IS
  'V771: the mark a rollback wrote to put the earlier marks back when it undid this RESULT_REPLACED — a restoration, never a change made since.';
SELECT audit.exempt('assessment.past_upload_change', 'V771: evidence written once with its upload; the upload (assessment.past_upload) is the audited act and every row it changes is audited on its own table');

CREATE TABLE assessment.past_upload_student (
    upload_id uuid NOT NULL REFERENCES assessment.past_upload (id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    cgpa_before numeric, tcr_before int, cgpa_after numeric, tcr_after int,
    graduate boolean NOT NULL DEFAULT false,
    changes int NOT NULL DEFAULT 0,
    PRIMARY KEY (upload_id, student_id)
);
COMMENT ON TABLE assessment.past_upload_student IS
  'V771: the reconciliation of an upload — each student it changed, their CGPA (and units counted) before its first change and after its last, and whether they are a Senate-approved graduate (D3: the approved CGPA and class of degree stay; the Registry is shown them).';
SELECT audit.exempt('assessment.past_upload_student', 'V771: evidence written with its upload; the upload (assessment.past_upload) is the audited act');

CREATE TABLE assessment.past_upload_row (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    upload_id uuid NOT NULL REFERENCES assessment.past_upload (id) ON DELETE CASCADE,
    session text NOT NULL, semester int NOT NULL, line text, matric text NOT NULL, course text NOT NULL,
    status text NOT NULL, detail text,
    facts jsonb NOT NULL DEFAULT '{}'::jsonb,
    loaded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX ux_past_upload_row ON assessment.past_upload_row (upload_id, session, semester, (coalesce(line, '')), matric, course);
CREATE INDEX ix_past_upload_row_status ON assessment.past_upload_row (upload_id, status);
COMMENT ON TABLE assessment.past_upload_row IS
  'V771: every row of a confirmed upload and what became of it — loaded, corrected, left as on record, or refused (missing or invalid title, credit units or category; an ambiguous code; a conflicting copy; a removal) with the detail and the required action — kept so the upload accounts for the whole file and what it did not load stays listed for review. A batch sent again (a retry, a resumed upload) never rewrites a row the upload loaded or changed; a held row posted later, or a refused row sent again, is updated.';
SELECT audit.exempt('assessment.past_upload_row', 'V771: evidence written with its upload; the upload (assessment.past_upload) is the audited act');

-- ── the course as taken ─────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE catalogue.course_as_taken (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    offering_id uuid NOT NULL REFERENCES catalogue.offering (id) ON DELETE CASCADE,
    course_id uuid NOT NULL,
    programme_code text,
    code_as_taken text NOT NULL CHECK (code_as_taken <> '' AND code_as_taken = upper(btrim(code_as_taken))),
    title text NOT NULL CHECK (title = catalogue.title_as_written(title) AND length(title) <= 200),
    units int NOT NULL CHECK (units BETWEEN 0 AND 12),
    source text NOT NULL CHECK (source IN ('UPLOAD', 'AMENDMENT', 'MOVED', 'CHANGED')),
    upload_id uuid REFERENCES assessment.past_upload (id) ON DELETE SET NULL,
    amendment_ref text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    created_by uuid,
    created_office text
);
CREATE UNIQUE INDEX ux_course_as_taken ON catalogue.course_as_taken (offering_id, code_as_taken, title, units);
CREATE INDEX ix_course_as_taken_course ON catalogue.course_as_taken (course_id);
COMMENT ON TABLE catalogue.course_as_taken IS
  'V771: a class (catalogue.offering: course, session, semester, stream) as students took it — the code as written in the file (kept when the course is renamed), the title and the credit units. One row per distinct (class, code, title, units); never updated, never deleted but with its class; course_id is catalogue.course.id when made (no key: a merged course row goes); programme_code the programme it was first taken under (information, not identity). source: UPLOAD (an old-portal file), AMENDMENT (a Senate units amendment), MOVED (an entry moved to its cohort''s class), CHANGED (another writer changed the units).';
SELECT audit.attach('catalogue.course_as_taken');

CREATE FUNCTION catalogue.course_as_taken_kept()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF pg_trigger_depth() > 1 OR coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN RETURN OLD; END IF;
        RAISE EXCEPTION 'AS_TAKEN_KEPT: a course as taken is history and is not deleted' USING ERRCODE = '23514';
    END IF;
    IF (NEW.offering_id, NEW.course_id, NEW.programme_code, NEW.code_as_taken, NEW.title, NEW.units, NEW.source)
       IS DISTINCT FROM (OLD.offering_id, OLD.course_id, OLD.programme_code, OLD.code_as_taken, OLD.title, OLD.units, OLD.source) THEN
        RAISE EXCEPTION 'AS_TAKEN_KEPT: a course as taken is never changed; a different code, title or units is another version' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_course_as_taken_kept BEFORE UPDATE OR DELETE ON catalogue.course_as_taken
    FOR EACH ROW EXECUTE FUNCTION catalogue.course_as_taken_kept();

-- a version of a class, found or made (the caller has looked for it first when it needs to know which)
CREATE FUNCTION catalogue.as_taken_for(p_offering uuid, p_programme text, p_code text, p_title text, p_units int, p_source text,
                                      p_upload uuid, p_amendment text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid; v_code text := upper(btrim(p_code)); v_title text := catalogue.title_as_written(p_title);
BEGIN
    SELECT a.id INTO v FROM catalogue.course_as_taken a
     WHERE a.offering_id = p_offering AND a.code_as_taken = v_code AND a.title = v_title AND a.units = p_units;
    IF v IS NOT NULL THEN RETURN v; END IF;
    INSERT INTO catalogue.course_as_taken (offering_id, course_id, programme_code, code_as_taken, title, units, source, upload_id, amendment_ref,
                                           created_by, created_office)
    SELECT p_offering, c.id, p_programme, v_code, v_title, p_units, p_source, p_upload, p_amendment,
           nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), '')
      FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = p_offering
    ON CONFLICT (offering_id, code_as_taken, title, units) DO NOTHING
    RETURNING id INTO v;
    IF v IS NULL THEN
        SELECT a.id INTO v FROM catalogue.course_as_taken a
         WHERE a.offering_id = p_offering AND a.code_as_taken = v_code AND a.title = v_title AND a.units = p_units;
    END IF;
    RETURN v;
END $$;
COMMENT ON FUNCTION catalogue.as_taken_for(uuid, text, text, text, int, text, uuid, text) IS
  'V771: the version of a class with this code, title and units — found, else made (source and upload recorded on the new row only).';

ALTER TABLE registration.entry ADD COLUMN as_taken_id uuid REFERENCES catalogue.course_as_taken (id) ON DELETE SET NULL;
CREATE INDEX ix_entry_as_taken ON registration.entry (as_taken_id) WHERE as_taken_id IS NOT NULL;
COMMENT ON COLUMN registration.entry.as_taken_id IS
  'V771: the course as the student took it (catalogue.course_as_taken) — its units are always this entry''s units; NULL where no file stated it.';

-- the entry and its version agree: same class, same units. Another writer (a Senate units amendment, a move to the cohort's class) re-points
-- the entry to a version with the new units or class, so the Senate route wins and history keeps both
CREATE FUNCTION registration.entry_as_taken_follows()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE a catalogue.course_as_taken; v_src text := coalesce(current_setting('moaum.units_source', true), ''); v_code text; v_kind text;
BEGIN
    IF NEW.as_taken_id IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO a FROM catalogue.course_as_taken WHERE id = NEW.as_taken_id;
    IF a.id IS NULL OR (a.offering_id = NEW.offering_id AND a.units = NEW.units) THEN RETURN NEW; END IF;
    IF a.offering_id <> NEW.offering_id THEN
        SELECT catalogue.code_as_written(o.course_code) INTO v_code FROM catalogue.offering o WHERE o.id = NEW.offering_id;
        v_kind := 'MOVED';
    ELSE
        v_code := a.code_as_taken;
        v_kind := CASE WHEN v_src LIKE 'AMENDMENT%' THEN 'AMENDMENT' ELSE 'CHANGED' END;
    END IF;
    NEW.as_taken_id := catalogue.as_taken_for(NEW.offering_id, a.programme_code, v_code, a.title, NEW.units, v_kind, NULL,
                                              CASE WHEN v_src LIKE 'AMENDMENT:%' THEN substr(v_src, 11) END);
    RETURN NEW;
END $$;
CREATE TRIGGER trg_entry_as_taken BEFORE INSERT OR UPDATE OF units, offering_id, as_taken_id ON registration.entry
    FOR EACH ROW EXECUTE FUNCTION registration.entry_as_taken_follows();

-- held rows remember how they were uploaded and under which upload
ALTER TABLE assessment.legacy_result_holding
    ADD COLUMN as_taken boolean NOT NULL DEFAULT false,
    ADD COLUMN upload_id uuid REFERENCES assessment.past_upload (id) ON DELETE SET NULL,
    ADD COLUMN prior jsonb;
COMMENT ON COLUMN assessment.legacy_result_holding.prior IS
  'V771: the hold this one replaced when a later upload carried the same row — {upload_id, raw, as_taken, loaded_at, prior}, nearest first. A rollback hands the row back to the nearest earlier upload still standing; the reconcile posts each standing holder''s result in turn, under its own upload.';
COMMENT ON COLUMN assessment.legacy_result_holding.as_taken IS
  'V771: the row came in an upload that states the course as taken (title, credit units, category); it is posted the same way. Rows held before V771 are posted under the old rule.';

-- ── the rules the loader reads ──────────────────────────────────────────────────────────────────────────────────────────────────
-- the offices that correct what is on record from a file: the Directorate of ICT, a Database Operator granted over the University, super
CREATE FUNCTION assessment.past_results_may()
RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_office IS NULL OR v_office IN ('ict', 'super') THEN RETURN true; END IF;
    RETURN v_office = 'dbops' AND coalesce((SELECT s.kind FROM iam.dbops_scope(v_actor) s), '') = 'institution';
END $$;
COMMENT ON FUNCTION assessment.past_results_may() IS
  'V771: whether the acting office may correct a registration already on record from an old-portal file (units, code and title as taken, category) — ict, super, or dbops granted over the University; the other migrating offices add only what is not on record.';

-- a course taken off the registration and not to be brought back by a file: V702's duplicate resolution (V772 adds the Director of
-- ICT's removals). REMOVED:<ref> or PENDING:<ref>, else NULL
CREATE FUNCTION registration.entry_held_out(p_registration uuid, p_offering uuid, p_student uuid, p_session text, p_semester int)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT 'REMOVED:' || coalesce('the duplicate resolution of ' || d.base_code, 'a duplicate resolution')
      FROM assessment.duplicate_resolution d
     WHERE d.student_id = p_student AND d.session = p_session AND d.semester = p_semester AND d.dropped_offering = p_offering
       AND d.undone_at IS NULL
     LIMIT 1
$$;
COMMENT ON FUNCTION registration.entry_held_out(uuid, uuid, uuid, text, int) IS
  'V771: why a course must not be put back on a registration by an upload — REMOVED:<what> (a V702 duplicate resolution; V772 the Director of ICT''s removal) or PENDING:<ref>; NULL when nothing holds it out.';

-- the Senate's units for a class and programme: the latest applied units amendment (its ref) when the entry still carries its units
CREATE FUNCTION assessment.units_by_senate(p_offering uuid, p_programme text, p_units int)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT m.ref || coalesce(' (Senate minute ' || m.senate_minute || ')', '')
      FROM assessment.amendment m JOIN assessment.score_sheet sh ON sh.id = m.sheet_id
     WHERE m.kind = 'UNITS' AND m.stage = 'APPLIED' AND sh.offering_id = p_offering AND m.programme_code = p_programme AND m.units = p_units
     ORDER BY m.applied_at DESC NULLS LAST LIMIT 1
$$;
CREATE FUNCTION assessment.entry_units_by_senate(p_offering uuid, p_programme text, p_units int, p_as_taken uuid, p_student uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    -- the Senate's units are the STUDENT's fact: an applied units amendment of the class at the entry's units for the programme the
    -- student is in or has held. The entry's version says nothing by itself (a version is shared by every student of the class who
    -- took the same code, title and units, whatever their programme), except one an amendment made that can no longer be named
    WITH held AS MATERIALIZED (
        SELECT p_programme AS code
        UNION SELECT h.programme_code FROM people.programme_history(p_student) h WHERE p_student IS NOT NULL AND h.programme_code IS NOT NULL
        UNION SELECT h.from_programme FROM people.programme_history(p_student) h WHERE p_student IS NOT NULL AND h.from_programme IS NOT NULL)
    SELECT coalesce(assessment.units_by_senate(p_offering, p_programme, p_units),
                    (SELECT m.ref || coalesce(' (Senate minute ' || m.senate_minute || ')', '')
                       FROM assessment.amendment m JOIN assessment.score_sheet sh ON sh.id = m.sheet_id
                      WHERE m.kind = 'UNITS' AND m.stage = 'APPLIED' AND sh.offering_id = p_offering AND m.units = p_units
                        AND m.programme_code IN (SELECT code FROM held)
                      ORDER BY m.applied_at DESC NULLS LAST LIMIT 1),
                    (SELECT coalesce(a.amendment_ref, 'a Senate units amendment')
                       FROM catalogue.course_as_taken a
                      WHERE a.id = p_as_taken AND a.source = 'AMENDMENT'
                        AND NOT EXISTS (SELECT 1 FROM assessment.amendment m WHERE m.ref = a.amendment_ref AND m.kind = 'UNITS'
                                           AND m.programme_code NOT IN (SELECT code FROM held))))
$$;
COMMENT ON FUNCTION assessment.entry_units_by_senate(uuid, text, int, uuid, uuid) IS
  'V771: whether the Senate set an entry''s units — an applied units amendment of the class at these units for the programme the student is in or has held (so a programme change, a transfer or a merge does not lose it), or a version an amendment made that can no longer be named. A student who was never in the amended programme is not held to it, whatever version the entry points at. An upload never writes over the Senate''s units, nor does a rollback. Known limit: "has held" is not "held when the amendment was applied" — the safe direction.';
COMMENT ON FUNCTION assessment.units_by_senate(uuid, text, int) IS
  'V771: the applied Senate units amendment that set these units for this class and programme, if any — an upload never undoes it.';

-- the course a file means, by its code AND its title: the course the code resolves to, every course sharing its shown code (V646
-- variants) and every course that held the code before a rename (catalogue.course_change); one candidate is it, several are decided by
-- the title (its current title, a title it had, a title its classes or versions carry); a code alone never decides between courses
CREATE FUNCTION catalogue.course_for_as_taken(p_raw text, p_title text)
RETURNS jsonb
LANGUAGE plpgsql STABLE AS $$
DECLARE v_clean text := nullif(regexp_replace(upper(btrim(coalesce(p_raw, ''))), '\s+', ' ', 'g'), '');
        v_as text := catalogue.code_as_written(p_raw); v_key text := catalogue.title_key(p_title);
        v_res text; v_cands text[]; v_former text[]; v_hit text[]; v_pick text; v_match text; v_cur text;
BEGIN
    IF v_clean IS NULL THEN RETURN jsonb_build_object('status', 'NONE'); END IF;
    IF catalogue.code_variant(v_clean) IS NOT NULL AND EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_clean) THEN
        -- a variant key written in full names that course; its family (every course under the shown code) stays the candidates, so a
        -- registration holding the course under another of them is found (COURSE_ON_RECORD_ELSEWHERE), never added beside it
        v_pick := v_clean;
        SELECT array_agg(c.code ORDER BY c.code) INTO v_cands FROM catalogue.course c WHERE catalogue.shown_code(c.code) = catalogue.shown_code(v_clean);
    ELSE
        v_res := catalogue.resolve_course_code(v_clean);
        IF v_res IS NOT NULL AND NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_res) THEN v_res := NULL; END IF;
        SELECT array_agg(DISTINCT x.code ORDER BY x.code) INTO v_cands FROM (
            SELECT c.code FROM catalogue.course c WHERE v_res IS NOT NULL AND catalogue.shown_code(c.code) = catalogue.shown_code(v_res)
            UNION
            SELECT c.code FROM catalogue.course c
             WHERE c.id IN (SELECT cc.course_id FROM catalogue.course_change cc
                             WHERE cc.field = 'CODE' AND catalogue.code_as_written(cc.old_value) IN (v_clean, v_as))) x;
        SELECT array_agg(c.code) INTO v_former FROM catalogue.course c
         WHERE c.code = ANY (coalesce(v_cands, '{}')) AND c.id IN (SELECT cc.course_id FROM catalogue.course_change cc
                                                                     WHERE cc.field = 'CODE' AND catalogue.code_as_written(cc.old_value) IN (v_clean, v_as));
    END IF;
    IF v_cands IS NULL OR cardinality(v_cands) = 0 THEN RETURN jsonb_build_object('status', 'NONE'); END IF;
    SELECT array_agg(c.code ORDER BY c.code) INTO v_hit FROM catalogue.course c
     WHERE c.code = ANY (v_cands) AND v_key IS NOT NULL AND (
           catalogue.title_key(c.title) = v_key
        OR EXISTS (SELECT 1 FROM catalogue.course_change cc WHERE cc.course_id = c.id AND cc.field = 'TITLE'
                      AND v_key IN (catalogue.title_key(cc.old_value), catalogue.title_key(cc.new_value)))
        OR EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND catalogue.title_key(o.title) = v_key)
        OR EXISTS (SELECT 1 FROM catalogue.course_as_taken a WHERE a.course_id = c.id AND catalogue.title_key(a.title) = v_key));
    IF v_pick IS NOT NULL THEN
        NULL;
    ELSIF cardinality(v_cands) = 1 THEN
        v_pick := v_cands[1];
    ELSIF cardinality(coalesce(v_hit, '{}')) = 1 THEN
        v_pick := v_hit[1];
    ELSE
        RETURN jsonb_build_object('status', 'AMBIGUOUS', 'candidates',
            (SELECT jsonb_agg(jsonb_build_object('code', c.code, 'title', c.title) ORDER BY c.code) FROM catalogue.course c WHERE c.code = ANY (v_cands)));
    END IF;
    SELECT c.title INTO v_cur FROM catalogue.course c WHERE c.code = v_pick;
    v_match := CASE WHEN v_pick = ANY (coalesce(v_former, '{}')) AND v_pick IS DISTINCT FROM v_res THEN 'FORMER_CODE'
                    WHEN catalogue.title_key(v_cur) = v_key THEN 'CODE_AND_TITLE'
                    WHEN v_pick = ANY (coalesce(v_hit, '{}')) THEN 'TITLE_FROM_HISTORY'
                    ELSE 'CODE_ONLY_NEW_TITLE' END;
    RETURN jsonb_build_object('status', 'MATCH', 'code', v_pick, 'match', v_match, 'currentTitle', v_cur, 'candidates', to_jsonb(v_cands));
END $$;
COMMENT ON FUNCTION catalogue.course_for_as_taken(text, text) IS
  'V771: the course an old-portal row means, by code and title — {status MATCH|AMBIGUOUS|NONE, code, match CODE_AND_TITLE|TITLE_FROM_HISTORY|FORMER_CODE|CODE_ONLY_NEW_TITLE, currentTitle, candidates}. Several courses under one code (variants, a former code) are told apart by the title, else AMBIGUOUS.';

-- a student's GPA picture: units counted and weighted points to date, CGPA, and each semester's GPA
CREATE FUNCTION assessment.gpa_snapshot(p_student uuid)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    WITH g AS MATERIALIZED (SELECT * FROM assessment.student_gpa(p_student)),
    last AS (SELECT * FROM g ORDER BY g.session DESC, g.semester DESC LIMIT 1)
    SELECT jsonb_build_object('tcr', coalesce((SELECT last.tcr FROM last), 0), 'twgp', coalesce((SELECT last.twgp FROM last), 0),
                              'cgpa', (SELECT last.cgpa FROM last),
                              'sem', coalesce((SELECT jsonb_object_agg(g.session || '|' || g.semester, g.gpa) FILTER (WHERE g.gpa IS NOT NULL) FROM g), '{}'::jsonb))
$$;
COMMENT ON FUNCTION assessment.gpa_snapshot(uuid) IS
  'V771: tcr, twgp and CGPA to date (assessment.student_gpa''s last row) and every semester''s GPA keyed "session|semester" — taken before and after an upload changes the student.';

-- ── the loader ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION assessment.legacy_semester_load(text, integer, jsonb, boolean, boolean);
CREATE FUNCTION assessment.legacy_semester_load(p_session text, p_semester integer, p_rows jsonb, p_with_results boolean, p_preview boolean,
                                                 p_upload uuid DEFAULT NULL, p_as_taken boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    r jsonb; v_i bigint; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_line text; v_matric text; v_raw_code text; v_code text; v_units int; v_level int; v_reg_level int; v_ca int; v_exam int; v_total int; v_outcome text;
    v_student uuid; v_programme text; v_stream text; v_offering uuid; v_sheet uuid; v_reg uuid; v_reg_status text; v_entry uuid; v_entry_status text;
    v_entry_units int; v_have_mark boolean; v_status text; v_detail text; v_entry_state text;
    v_new_reg boolean; v_new_entry boolean; v_new_offering boolean; v_reapprove boolean; v_posted boolean; v_deferred boolean := false;
    n int := 0; n_off int := 0; n_reg int := 0; n_entry int := 0; n_res int := 0; n_already int := 0; n_units int := 0; n_dropped int := 0;
    n_open int := 0; n_reapproved int := 0; nns int := 0; n_held int := 0; nnc int := 0; nnm int := 0; n_refused int := 0; n_dup int := 0;
    -- V614: the mark read as the whole, and a result already on record (the same, an earlier upload's replaced, one entered on the portal)
    v_mark_note text; v_prev assessment.score; v_prev_found boolean;
    n_as_total int := 0; n_res_same int := 0; n_res_replaced int := 0; n_res_portal int := 0;
    -- V619: the old portal's ABS read as an absence
    v_abs_note text; n_absent int := 0;
    v_firsterr text := NULL; v_lines jsonb := '[]'::jsonb;
    seen_students uuid[] := '{}'; seen_codes text[] := '{}'; seen_keys text[] := '{}';
    v_siwes_override text := current_setting('moaum.siwes_override', true);   -- V752
    -- V771: the course as taken
    v_reconcile boolean := coalesce(current_setting('moaum.legacy_reconcile', true), '') = 'on';
    v_upload uuid := CASE WHEN p_preview THEN NULL ELSE p_upload END; v_up assessment.past_upload; v_may boolean;
    v_title text; v_cu_raw text; v_cu int; v_cat_raw text; v_cat text; v_et text; v_basis text; v_code_as text;
    v_ident jsonb; v_idcache jsonb := '{}'::jsonb; v_match text; v_cands text[]; v_cur_units int; v_cur_title text;
    v_at uuid; v_at_made boolean; v_at_existed boolean; v_entry_at uuid; v_entry_type text; v_entry_basis text; v_kind text;
    v_old catalogue.course_as_taken; v_printed_code text; v_printed_title text; v_cat_now text; v_cat_to text;
    v_same_units boolean; v_same_ident boolean; v_same_cat boolean; v_held text; v_elsewhere text; v_portal boolean; v_senate text;
    v_graduate boolean; v_kinds text[]; v_moved uuid[] := '{}'; v_classes uuid[] := '{}'; v_gpa_before jsonb := '{}'::jsonb;
    v_dupe jsonb := '{}'::jsonb; v_dkey text; v_fp text; v_courses jsonb := '{}'::jsonb; v_ckey text;
    v_gpa jsonb := '[]'::jsonb; v_graduates jsonb := '{}'::jsonb; v_affected jsonb := '{}'::jsonb; v_newregs jsonb := '{}'::jsonb;
    v_now_et text; v_now_basis text; v_score_v int; v_x record; v_after jsonb; v_before jsonb; v_entry_detail text;
    n_missing int := 0; n_invalid int := 0; n_ambiguous int := 0; n_conflict int := 0; n_elsewhere int := 0; n_removed int := 0; n_pending int := 0;
    n_units_corr int := 0; n_ident_corr int := 0; n_linked int := 0; n_cat_corr int := 0; n_on_portal int := 0; n_by_senate int := 0; n_differs int := 0;
    n_new_title int := 0; n_vmade int := 0; n_vreused int := 0; n_classes int := 0;
    v_made_ats uuid[] := '{}'; v_reused_ats uuid[] := '{}'; v_touched uuid[] := '{}'; v_senate_r text; v_line_obj jsonb;
    v_rolled boolean; v_rc int; v_reg_lvl int; v_differs boolean;
BEGIN
    IF p_with_results THEN PERFORM assessment.past_results_office(); END IF;  -- V627: past results are the Directorate of ICT's to load
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_semester NOT IN (1, 2, 3) THEN RAISE EXCEPTION 'a semester is 1, 2 or 3' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, course, units and the mark' USING ERRCODE = '23514';
    END IF;
    -- V771: a confirmed upload names its record, which is the uploader's own and still running; a held row posted later joins its upload
    v_may := assessment.past_results_may();
    IF p_as_taken AND NOT p_preview THEN
        IF v_upload IS NULL AND NOT v_reconcile THEN
            RAISE EXCEPTION 'LEGACY_UPLOAD_REQUIRED: a file is loaded under its confirmed upload' USING ERRCODE = '23514';
        END IF;
        IF v_upload IS NOT NULL THEN
            SELECT * INTO v_up FROM assessment.past_upload WHERE id = v_upload FOR UPDATE;
            IF v_up.id IS NULL THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: no upload %', v_upload USING ERRCODE = 'P0002'; END IF;
            IF v_reconcile THEN
                IF v_up.state = 'REVERTED' THEN
                    RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is rolled back; its held rows are not posted', v_up.ref USING ERRCODE = '23514';
                END IF;
                v_may := v_up.created_office IN ('ict', 'super', 'dbops');
            ELSE
                IF v_up.created_by IS DISTINCT FROM v_actor THEN
                    RAISE EXCEPTION 'LEGACY_UPLOAD_OWN: upload % is another officer''s', v_up.ref USING ERRCODE = '42501';
                END IF;
                IF v_up.state <> 'RUNNING' OR v_up.kind <> (CASE WHEN p_with_results THEN 'RESULTS' ELSE 'REGISTRATION' END) THEN
                    RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is % (a % upload); start a new upload', v_up.ref, lower(v_up.state), lower(v_up.kind)
                        USING ERRCODE = '23514';
                END IF;
            END IF;
        ELSE
            v_may := false;   -- a held row with no upload of record: only what is not on record is added
        END IF;
    END IF;

    BEGIN   -- the whole load; a preview undoes it at the end, keeping what it learned
        PERFORM assessment.ensure_session(p_session);
        -- V752: history: the SIWES rule is set aside for a closed session's rows only (registration.entry_siwes_only)
        PERFORM set_config('moaum.siwes_override', 'on', true);
        v_deferred := people.defer_positions();

        -- V771: one student's course stated twice: the same words keep the first, different words refuse every copy
        IF p_as_taken THEN
            FOR r, v_i IN SELECT e.value, e.ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY e LOOP
                v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', r->>'reg_no', '')));
                v_raw_code := upper(btrim(coalesce(r->>'course', r->>'courseCode', r->>'course_code', r->>'code', '')));
                IF v_matric = '' OR v_raw_code = '' THEN CONTINUE; END IF;
                v_dkey := v_matric || '|' || coalesce(catalogue.shown_code(catalogue.resolve_course_code(catalogue.code_as_written(v_raw_code))),
                                                      catalogue.code_as_written(v_raw_code));
                v_fp := concat_ws('|', catalogue.title_as_written(coalesce(r->>'title', r->>'courseTitle')),
                                  regexp_replace(coalesce(r->>'creditUnits', ''), '\s', '', 'g'), upper(regexp_replace(coalesce(r->>'category', ''), '\s', '', 'g')),
                                  regexp_replace(coalesce(r->>'ca', r->>'CA', ''), '\s', '', 'g'), regexp_replace(coalesce(r->>'exam', r->>'EXAM', ''), '\s', '', 'g'),
                                  regexp_replace(coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark', ''), '\s', '', 'g'),
                                  upper(btrim(coalesce(r->>'outcome', ''))));
                IF v_dupe ? v_dkey THEN
                    IF v_dupe->v_dkey->>'fp' IS DISTINCT FROM v_fp THEN v_dupe := jsonb_set(v_dupe, ARRAY[v_dkey, 'conflict'], 'true'::jsonb); END IF;
                ELSE
                    v_dupe := v_dupe || jsonb_build_object(v_dkey, jsonb_build_object('fp', v_fp, 'first', v_i, 'conflict', false));
                END IF;
            END LOOP;
        END IF;

        FOR r, v_i IN SELECT e.value, e.ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY e LOOP
            v_line := nullif(btrim(coalesce(r->>'line', '')), '');
            v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', r->>'reg_no', '')));
            v_raw_code := upper(btrim(coalesce(r->>'course', r->>'courseCode', r->>'course_code', r->>'code', '')));
            IF v_matric = '' THEN CONTINUE; END IF;
            n := n + 1;
            v_status := NULL; v_detail := NULL; v_student := NULL; v_code := NULL; v_entry_state := NULL; v_mark_note := NULL; v_abs_note := NULL;
            v_new_reg := false; v_new_entry := false; v_new_offering := false; v_reapprove := false; v_posted := false;
            v_title := NULL; v_cu := NULL; v_cu_raw := NULL; v_cat := NULL; v_cat_raw := NULL; v_code_as := NULL; v_match := NULL; v_cands := '{}';
            v_cur_units := NULL; v_cur_title := NULL; v_at := NULL; v_at_made := false; v_at_existed := NULL; v_kinds := '{}'; v_held := NULL;
            v_elsewhere := NULL; v_graduate := false; v_et := 'CURRENT'; v_basis := NULL; v_offering := NULL; v_score_v := NULL;
            v_printed_code := NULL; v_printed_title := NULL; v_cat_now := NULL; v_now_et := NULL; v_now_basis := NULL; v_old := NULL;
            v_entry_at := NULL; v_entry_type := NULL; v_entry_basis := NULL; v_entry_units := NULL; v_entry_status := NULL; v_reg := NULL; v_reg_status := NULL;
            v_rolled := false; v_reg_lvl := NULL; v_senate_r := NULL;

            BEGIN   -- one savepoint per row: what the portal refuses sets the row aside, the batch goes on
                IF v_raw_code = '' THEN
                    v_status := 'NO_COURSE'; v_detail := 'The row has no course code';
                ELSE
                    IF p_as_taken THEN
                        -- V771 (D2, D5): the course as taken — title, credit units, category — on every row, read before anything else
                        v_title := catalogue.title_as_written(coalesce(r->>'title', r->>'courseTitle'));
                        v_cu_raw := btrim(coalesce(r->>'creditUnits', r->>'credit_units', ''));
                        v_cat_raw := upper(regexp_replace(coalesce(r->>'category', ''), '[^A-Za-z0-9]', '', 'g'));
                        v_cu := CASE WHEN v_cu_raw ~ '^[0-9]{1,2}(\.0+)?$' THEN split_part(v_cu_raw, '.', 1)::int END;
                        v_cat := CASE WHEN v_cat_raw IN ('CORE', '2') THEN 'CORE' WHEN v_cat_raw IN ('ELECTIVE', '3') THEN 'ELECTIVE'
                                      WHEN v_cat_raw IN ('GST', '1') THEN 'GST' WHEN v_cat_raw IN ('CARRYOVER', '0') THEN 'CARRY' END;
                        IF v_title IS NULL OR v_cu_raw = '' OR v_cat_raw = '' THEN
                            v_status := 'AS_TAKEN_MISSING';
                            v_detail := 'The row has no ' || array_to_string(array_remove(ARRAY[
                                CASE WHEN v_title IS NULL THEN 'course title' END, CASE WHEN v_cu_raw = '' THEN 'credit units' END,
                                CASE WHEN v_cat_raw = '' THEN 'category' END], NULL), ', ') || ' — nothing is taken from today''s catalogue in its place';
                        ELSIF length(v_title) > 200 OR v_cu IS NULL OR v_cu > 12 OR v_cat IS NULL THEN
                            v_status := 'AS_TAKEN_INVALID';
                            v_detail := array_to_string(array_remove(ARRAY[
                                CASE WHEN v_cu IS NULL OR v_cu > 12 THEN format('the credit units "%s" are not a whole number from 0 to 12', v_cu_raw) END,
                                CASE WHEN v_cat IS NULL THEN format('the category "%s" is not Core, Elective, GST or Carry-over (or the old portal''s 2, 3, 1, 0)', btrim(r->>'category')) END,
                                CASE WHEN length(v_title) > 200 THEN 'the title is longer than 200 characters' END], NULL), '; ');
                        ELSE
                            v_ident := v_idcache->(v_raw_code || '|' || v_title);
                            IF v_ident IS NULL THEN
                                v_ident := catalogue.course_for_as_taken(v_raw_code, v_title);
                                v_idcache := v_idcache || jsonb_build_object(v_raw_code || '|' || v_title, v_ident);
                            END IF;
                            IF v_ident->>'status' = 'NONE' THEN
                                v_status := 'NO_COURSE'; v_detail := format('No course %s in the catalogue, under this code or a code it had', v_raw_code);
                            ELSIF v_ident->>'status' = 'AMBIGUOUS' THEN
                                v_status := 'COURSE_AMBIGUOUS';
                                v_detail := format('%s is held by more than one course (%s) and the title "%s" names %s of them — write the course''s own code in the file',
                                                   v_raw_code, (SELECT string_agg(format('%s "%s"', x->>'code', x->>'title'), '; ') FROM jsonb_array_elements(v_ident->'candidates') x),
                                                   v_title, 'none or more than one');
                            ELSE
                                v_code := v_ident->>'code'; v_match := v_ident->>'match'; v_code_as := catalogue.code_as_written(v_raw_code);
                                SELECT coalesce(array_agg(x), '{}') INTO v_cands FROM jsonb_array_elements_text(v_ident->'candidates') x;
                                v_et := CASE v_cat WHEN 'CORE' THEN 'CURRENT' WHEN 'ELECTIVE' THEN 'ELECTIVE' WHEN 'GST' THEN 'GST' ELSE 'CARRYOVER' END;
                                v_basis := CASE v_cat WHEN 'CORE' THEN 'Core' WHEN 'ELECTIVE' THEN 'Elective' WHEN 'GST' THEN 'GST' END;
                                v_dkey := v_matric || '|' || coalesce(catalogue.shown_code(catalogue.resolve_course_code(catalogue.code_as_written(v_raw_code))),
                                                                      catalogue.code_as_written(v_raw_code));
                                IF (v_dupe->v_dkey->>'conflict')::boolean THEN
                                    v_status := 'DUPLICATE_CONFLICT';
                                    v_detail := 'The same student and course appear more than once in the file with different title, units, category or mark — none is loaded; keep one row';
                                ELSIF (v_dupe->v_dkey->>'first')::bigint IS DISTINCT FROM v_i THEN
                                    v_status := 'DUPLICATE_IN_FILE'; v_detail := 'The same student and course appear earlier in the file';
                                END IF;
                            END IF;
                        END IF;
                    ELSE
                        v_code := coalesce(catalogue.resolve_course_code(v_raw_code), regexp_replace(v_raw_code, '^([A-Z]{2,4})\s*([0-9]{3})$', '\1 \2'));
                    END IF;

                    IF v_status IS NULL THEN
                        SELECT s.id, s.programme_code INTO v_student, v_programme FROM people.student s WHERE upper(s.matric_no) = v_matric;
                        IF NOT p_as_taken AND (v_matric || '|' || v_code) = ANY (seen_keys) THEN
                            v_status := 'DUPLICATE_IN_FILE'; v_detail := 'The same student and course appear earlier in the file';
                        ELSIF v_student IS NULL THEN
                            IF p_with_results THEN
                                -- the student is not on the register yet: the result is HELD, to be posted on reconcile (V771: as it came)
                                -- a later upload carrying the row takes the hold over and remembers the one it replaced
                                INSERT INTO assessment.legacy_result_holding AS h (session, semester, matric, course_code, raw, as_taken, upload_id)
                                VALUES (p_session, p_semester, v_matric, v_code, r, p_as_taken, v_upload)
                                ON CONFLICT (session, semester, matric, course_code) DO UPDATE
                                   SET prior = CASE WHEN h.upload_id IS DISTINCT FROM EXCLUDED.upload_id
                                                    THEN jsonb_build_object('upload_id', h.upload_id, 'raw', h.raw, 'as_taken', h.as_taken,
                                                                            'loaded_at', h.loaded_at, 'prior', h.prior)
                                                    ELSE h.prior END,
                                       raw = EXCLUDED.raw, loaded_at = now(), as_taken = EXCLUDED.as_taken, upload_id = EXCLUDED.upload_id;
                                v_status := 'HELD'; v_detail := 'No student with this number yet; the result posts once the student is uploaded';
                            ELSE
                                v_status := 'NO_STUDENT'; v_detail := 'No student on the register has this matriculation number';
                            END IF;
                        ELSIF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_code) THEN
                            v_status := 'NO_COURSE'; v_detail := format('No course %s in the catalogue', v_raw_code);
                        END IF;
                    END IF;

                    IF v_status IS NULL THEN
                        v_stream := people.student_stream(v_student);
                        IF v_stream = 'PG' THEN
                            RAISE EXCEPTION 'POSTGRADUATE_STUDENT: % is a postgraduate student; their registration and results come over through the PG uploads', v_matric
                                USING ERRCODE = '23514';
                        END IF;
                        SELECT c.level, c.title INTO v_level, v_cur_title FROM catalogue.course c WHERE c.code = v_code;
                        v_level := coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int, v_level);
                        v_graduate := EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = v_student AND g.senate_state = 'APPROVED');
                        IF NOT (v_gpa_before ? v_student::text) THEN   -- V771: the GPA picture before this call writes anything of the student's
                            v_gpa_before := v_gpa_before || jsonb_build_object(v_student::text, assessment.gpa_snapshot(v_student));
                        END IF;

                        -- what is on record: the student's registration for the semester, and the course on it
                        SELECT cr.id, cr.status INTO v_reg, v_reg_status FROM registration.course_registration cr
                         WHERE cr.student_id = v_student AND cr.session = p_session AND cr.semester = p_semester;
                        v_entry := NULL; v_entry_status := NULL; v_entry_units := NULL; v_entry_at := NULL; v_entry_type := NULL; v_entry_basis := NULL;
                        IF v_reg IS NOT NULL THEN
                            SELECT e.offering_id, e.status, e.units, e.as_taken_id, e.entry_type, e.basis
                              INTO v_entry, v_entry_status, v_entry_units, v_entry_at, v_entry_type, v_entry_basis
                              FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                             WHERE e.registration_id = v_reg AND o.course_code = v_code
                             ORDER BY (e.status IN ('APPROVED', 'REGISTERED')) DESC LIMIT 1;
                            -- V771: a course taken off the registration is not put back by a file
                            IF v_entry IS NOT NULL THEN
                                v_held := registration.entry_held_out(v_reg, v_entry, v_student, p_session, p_semester);
                            END IF;
                            -- V771: the record holds the course under another of the code's courses (an earlier upload read the code alone),
                            -- whether the named course is missing or only on record uncounted — a file never counts it beside a counted sibling
                            IF (v_entry IS NULL OR (v_held IS NULL AND v_entry_status NOT IN ('APPROVED', 'REGISTERED')))
                               AND p_as_taken AND cardinality(v_cands) > 1 THEN
                                SELECT o.course_code || coalesce(' "' || coalesce(o.title, c.title) || '"', '') INTO v_elsewhere
                                  FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                                 WHERE e.registration_id = v_reg AND e.status IN ('APPROVED', 'REGISTERED') AND o.course_code = ANY (v_cands) AND o.course_code <> v_code
                                 LIMIT 1;
                            END IF;
                            -- V771: a course an upload added and its rollback withdrew is the file's to put back
                            v_rolled := v_entry IS NOT NULL AND v_entry_status = 'WITHDRAWN' AND v_held IS NULL
                                        AND EXISTS (SELECT 1 FROM assessment.past_upload_change u WHERE u.kind = 'ENTRY_ADDED' AND u.reverted_at IS NOT NULL
                                                       AND u.registration_id = v_reg AND u.offering_id = v_entry);
                        END IF;
                        v_units := catalogue.units_for(v_code, v_programme, v_level);
                        v_cur_units := v_units;

                        IF v_elsewhere IS NOT NULL THEN
                            v_status := 'COURSE_ON_RECORD_ELSEWHERE';
                            v_detail := format('On record as %s; the file''s title "%s" is %s''s — nothing added; take the other off through Course Registration Correction if it is wrong',
                                               v_elsewhere, v_title, v_code);
                        ELSIF v_held LIKE 'REMOVED:%' THEN
                            v_status := 'REMOVED_ON_RECORD';
                            v_detail := format('Taken off the student''s registration (%s); not brought back', substr(v_held, 9));
                        ELSIF v_held LIKE 'PENDING:%' THEN
                            v_status := 'REMOVAL_PENDING';
                            v_detail := format('%s awaits the Registry; nothing changed — upload this row again after the decision', substr(v_held, 9));
                        ELSIF v_entry IS NULL THEN
                            SELECT id INTO v_offering FROM catalogue.offering
                             WHERE course_code = v_code AND session = p_session AND semester = p_semester AND stream = v_stream;
                            IF v_offering IS NULL THEN
                                v_offering := gen_random_uuid();
                                -- V771: a class an upload opens takes the file's title and units, not today's catalogue
                                INSERT INTO catalogue.offering (id, course_code, session, semester, stream, title, units)
                                VALUES (v_offering, v_code, p_session, p_semester, v_stream, CASE WHEN p_as_taken THEN v_title END, CASE WHEN p_as_taken THEN v_cu END);
                                v_new_offering := true;
                            END IF;
                            -- V672: the enrolment and registration a load makes take the student's level in the session (a 300 Level
                            -- student's first row a 200 Level carry-over made the whole registration 200 Level): the level the file states,
                            -- else the session's enrolment, the course's level only where neither says — and never below the level the
                            -- record holds in the session the student is in now
                            v_reg_level := greatest(people.record_level_in(v_student, p_session),
                                                    coalesce(nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int,
                                                             (SELECT e.level FROM people.enrolment e WHERE e.student_id = v_student AND e.session = p_session),
                                                             v_level));
                            INSERT INTO people.enrolment (id, student_id, session, level)
                            VALUES (gen_random_uuid(), v_student, p_session, v_reg_level) ON CONFLICT (student_id, session) DO NOTHING;
                            GET DIAGNOSTICS v_rc = ROW_COUNT;
                            IF v_rc > 0 AND p_as_taken THEN v_kinds := v_kinds || 'ENROLMENT_ADDED'::text; END IF;   -- V771: undone with its upload
                            v_reg_lvl := v_reg_level;
                            IF v_reg IS NULL THEN
                                v_reg := gen_random_uuid();
                                INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at, approved_by)
                                VALUES (v_reg, v_student, p_session, p_semester, v_reg_level, 'APPROVED', now(), now(), v_actor);
                                v_new_reg := true;
                                IF p_as_taken THEN v_kinds := v_kinds || 'REGISTRATION_ADDED'::text; END IF;
                            END IF;
                            IF p_as_taken THEN
                                SELECT a.id INTO v_at FROM catalogue.course_as_taken a
                                 WHERE a.offering_id = v_offering AND a.code_as_taken = v_code_as AND a.title = v_title AND a.units = v_cu;
                                v_at_existed := v_at IS NOT NULL AND NOT (v_at = ANY (v_made_ats));
                                IF v_at IS NULL THEN v_at := catalogue.as_taken_for(v_offering, v_programme, v_code_as, v_title, v_cu, 'UPLOAD', v_upload, NULL); v_made_ats := v_made_ats || v_at; END IF;
                                INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, basis, as_taken_id)
                                VALUES (v_reg, v_offering, v_cu, v_et, 'APPROVED', v_basis, v_at);
                                v_kinds := v_kinds || 'ENTRY_ADDED'::text;
                            ELSE
                                INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                                VALUES (v_reg, v_offering, v_units, 'CURRENT', 'APPROVED');
                            END IF;
                            v_entry := v_offering;
                            v_new_entry := true;
                            IF NOT v_new_reg AND v_reg_status NOT IN ('APPROVED', 'LOCKED') THEN
                                v_status := 'ADDED_TO_OPEN_REGISTRATION';
                                v_detail := format('Added to the student''s %s registration for this semester on the portal', lower(v_reg_status));
                            ELSE
                                v_status := 'ADDED';
                                v_detail := format('%s units%s', coalesce(v_cu, v_units), CASE WHEN v_new_reg THEN '; a new approved registration for the semester' END);
                            END IF;
                        ELSIF v_entry_status NOT IN ('APPROVED', 'REGISTERED') THEN
                            IF p_with_results OR v_rolled THEN
                                -- a result is evidence the course was taken: the entry is approved, as before (V771: as the file states it,
                                -- where the office may correct the record)
                                -- never over a result entered on the portal, nor over the Senate's units (as on a counted course)
                                v_portal := p_as_taken AND v_may
                                            AND EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score s ON s.sheet_id = sh.id
                                                         WHERE sh.offering_id = v_entry AND s.student_id = v_student AND NOT s.imported);
                                SELECT c.kind INTO v_kind FROM catalogue.course c WHERE c.code = v_code;
                                v_cat_now := registration.entry_category(v_entry_type, v_kind, v_entry_basis);
                                v_differs := v_entry_units IS DISTINCT FROM v_cu
                                             OR NOT EXISTS (SELECT 1 FROM catalogue.course_as_taken a
                                                             WHERE a.id = v_entry_at AND a.code_as_taken = v_code_as AND a.title = v_title)
                                             OR v_cat_now IS DISTINCT FROM registration.entry_category(v_et, v_kind, v_basis);
                                v_senate_r := CASE WHEN p_as_taken AND v_may AND NOT v_portal AND v_entry_units IS DISTINCT FROM v_cu
                                                   THEN assessment.entry_units_by_senate(v_entry, v_programme, v_entry_units, v_entry_at, v_student) END;
                                IF p_as_taken AND v_may AND NOT v_portal AND v_senate_r IS NULL THEN
                                    SELECT a.id INTO v_at FROM catalogue.course_as_taken a
                                     WHERE a.offering_id = v_entry AND a.code_as_taken = v_code_as AND a.title = v_title AND a.units = v_cu;
                                    v_at_existed := v_at IS NOT NULL AND NOT (v_at = ANY (v_made_ats));
                                    IF v_at IS NULL THEN v_at := catalogue.as_taken_for(v_entry, v_programme, v_code_as, v_title, v_cu, 'UPLOAD', v_upload, NULL); v_made_ats := v_made_ats || v_at; END IF;
                                    UPDATE registration.entry SET status = 'APPROVED', units = v_cu, as_taken_id = v_at, entry_type = v_et,
                                                                  basis = coalesce(v_basis, basis)
                                     WHERE registration_id = v_reg AND offering_id = v_entry;
                                ELSE
                                    UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = v_reg AND offering_id = v_entry;
                                END IF;
                                v_reapprove := true;
                                v_kinds := v_kinds || 'ENTRY_REAPPROVED'::text;
                                v_status := CASE WHEN v_senate_r IS NOT NULL THEN 'UNITS_BY_AMENDMENT' WHEN v_portal AND v_differs THEN 'UNITS_ON_PORTAL' ELSE 'ADDED' END;
                                v_detail := CASE WHEN v_rolled THEN 'Withdrawn when an earlier upload was rolled back; approved again from this file'
                                                 ELSE format('%s on record; approved again because a result was posted', lower(v_entry_status)) END
                                            || CASE WHEN v_senate_r IS NOT NULL THEN format('; the Senate''s %s units kept (%s)', v_entry_units, v_senate_r) ELSE '' END
                                            || CASE WHEN v_portal AND v_differs
                                                    THEN format('; a result entered on the portal stands on it, so it is kept as on record (%s units, %s) — the file''s %s "%s", %s units, %s is not put over it; amend it through Result amendments',
                                                                v_entry_units, lower(replace(v_cat_now, '_', '-')), v_code_as, v_title, v_cu,
                                                                lower(replace(CASE v_cat WHEN 'CARRY' THEN 'CARRY_OVER' ELSE v_cat END, '_', '-'))) ELSE '' END;
                            ELSE
                                v_status := 'DROPPED_ON_RECORD';
                                v_detail := format('%s on the student''s registration; left as it is', initcap(lower(v_entry_status)));
                            END IF;
                        ELSIF NOT p_as_taken THEN
                            IF v_units IS NOT NULL AND v_entry_units IS DISTINCT FROM v_units THEN
                                v_status := 'UNITS_DIFFER';
                                v_detail := format('On record at %s units; the programme takes it at %s — left as it is', v_entry_units, v_units);
                            ELSE
                                v_status := 'ALREADY_ON_RECORD'; v_detail := format('On record at %s units', v_entry_units);
                            END IF;
                        ELSE
                            -- V771: a course on record, against the file's course as taken
                            v_old := NULL;
                            IF v_entry_at IS NOT NULL THEN SELECT * INTO v_old FROM catalogue.course_as_taken WHERE id = v_entry_at; END IF;
                            SELECT coalesce(v_old.code_as_taken, catalogue.code_as_written(o.course_code)),
                                   coalesce(v_old.title, catalogue.title_as_written(coalesce(o.title, c.title))),
                                   registration.entry_category(v_entry_type, c.kind, v_entry_basis), c.kind
                              INTO v_printed_code, v_printed_title, v_cat_now, v_kind
                              FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = v_entry;
                            v_cat_to := CASE v_cat WHEN 'CARRY' THEN 'CARRY_OVER' ELSE v_cat END;
                            v_same_units := v_entry_units = v_cu;
                            v_same_ident := v_printed_code = v_code_as AND v_printed_title = v_title;
                            -- the category the record would read with the file's applied: a GST course reads GST whatever the file calls it
                            v_same_cat := v_cat_now = registration.entry_category(v_et, v_kind, v_basis);
                            IF v_same_units AND v_same_ident AND v_same_cat AND (v_entry_at IS NOT NULL OR NOT v_may) THEN
                                v_status := 'ALREADY_ON_RECORD';
                                v_detail := format('On record as %s "%s", %s units, %s', v_printed_code, v_printed_title, v_entry_units, lower(replace(v_cat_now, '_', '-')))
                                            || CASE WHEN v_cat_to <> v_cat_now
                                                    THEN format('; the file''s %s is not taken — a GST course counts as GST', lower(replace(v_cat_to, '_', '-'))) ELSE '' END;
                            ELSIF NOT v_may THEN
                                v_status := 'AS_TAKEN_DIFFERS';
                                v_detail := format('On record as %s "%s", %s units, %s; the file says %s "%s", %s units, %s — left as it is (the Directorate of ICT corrects what is on record)',
                                                   v_printed_code, v_printed_title, v_entry_units, lower(replace(v_cat_now, '_', '-')),
                                                   v_code_as, v_title, v_cu, lower(replace(v_cat_to, '_', '-')));
                            ELSE
                                v_portal := EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score s ON s.sheet_id = sh.id
                                                     WHERE sh.offering_id = v_entry AND s.student_id = v_student AND NOT s.imported);
                                v_senate := assessment.entry_units_by_senate(v_entry, v_programme, v_entry_units, v_entry_at, v_student);
                                IF v_portal THEN
                                    v_status := 'UNITS_ON_PORTAL';
                                    v_detail := format('A result entered on the portal stands on this course (%s "%s", %s units, %s); the file''s %s "%s", %s units, %s is not put over it — amend it through Result amendments',
                                                       v_printed_code, v_printed_title, v_entry_units, lower(replace(v_cat_now, '_', '-')),
                                                       v_code_as, v_title, v_cu, lower(replace(v_cat_to, '_', '-')));
                                ELSIF v_senate IS NOT NULL AND NOT v_same_units THEN
                                    v_status := 'UNITS_BY_AMENDMENT';
                                    v_detail := format('The Senate set these units (%s units, %s); the file''s %s units are not put over them — amend them through Result amendments',
                                                       v_entry_units, v_senate, v_cu);
                                ELSE
                                    SELECT a.id INTO v_at FROM catalogue.course_as_taken a
                                     WHERE a.offering_id = v_entry AND a.code_as_taken = v_code_as AND a.title = v_title AND a.units = v_cu;
                                    v_at_existed := v_at IS NOT NULL AND NOT (v_at = ANY (v_made_ats));
                                    IF v_at IS NULL THEN v_at := catalogue.as_taken_for(v_entry, v_programme, v_code_as, v_title, v_cu, 'UPLOAD', v_upload, NULL); v_made_ats := v_made_ats || v_at; END IF;
                                    UPDATE registration.entry
                                       SET units = v_cu, as_taken_id = v_at,
                                           entry_type = CASE WHEN v_same_cat THEN entry_type ELSE v_et END,
                                           basis = CASE WHEN v_same_cat THEN basis ELSE coalesce(v_basis, basis) END
                                     WHERE registration_id = v_reg AND offering_id = v_entry
                                     RETURNING entry_type, basis INTO v_now_et, v_now_basis;
                                    IF NOT v_same_units THEN v_kinds := v_kinds || 'UNITS_CORRECTED'::text; END IF;
                                    IF NOT v_same_ident THEN v_kinds := v_kinds || 'AS_TAKEN_CORRECTED'::text; END IF;
                                    IF v_same_units AND v_same_ident AND v_entry_at IS NULL THEN v_kinds := v_kinds || 'AS_TAKEN_LINKED'::text; END IF;
                                    IF NOT v_same_cat AND (v_now_et IS DISTINCT FROM v_entry_type OR v_now_basis IS DISTINCT FROM v_entry_basis) THEN
                                        v_kinds := v_kinds || 'CATEGORY_CORRECTED'::text;
                                    END IF;
                                    v_status := CASE WHEN 'UNITS_CORRECTED' = ANY (v_kinds) THEN 'UNITS_CORRECTED'
                                                     WHEN 'AS_TAKEN_CORRECTED' = ANY (v_kinds) THEN 'AS_TAKEN_CORRECTED'
                                                     WHEN 'CATEGORY_CORRECTED' = ANY (v_kinds) THEN 'CATEGORY_CORRECTED'
                                                     WHEN 'AS_TAKEN_LINKED' = ANY (v_kinds) THEN 'AS_TAKEN_LINKED'
                                                     ELSE 'ALREADY_ON_RECORD' END;
                                    v_detail := format('Was %s "%s", %s units, %s; now %s "%s", %s units, %s',
                                                       v_printed_code, v_printed_title, v_entry_units, lower(replace(v_cat_now, '_', '-')),
                                                       v_code_as, v_title, v_cu, lower(replace(registration.entry_category(v_now_et, v_kind, v_now_basis), '_', '-')))
                                                || CASE WHEN v_cat_to <> v_cat_now AND v_same_cat
                                                        THEN format('; the file''s %s is not taken — a GST course counts as GST', lower(replace(v_cat_to, '_', '-'))) ELSE '' END;
                                END IF;
                            END IF;
                        END IF;
                        IF v_entry IS NOT NULL THEN v_offering := v_entry; END IF;   -- the entry is keyed by its registration and its class
                        v_entry_state := v_status;
                        v_entry_detail := v_detail;

                        IF p_with_results AND v_status NOT IN ('DROPPED_ON_RECORD', 'REMOVED_ON_RECORD', 'REMOVAL_PENDING', 'COURSE_ON_RECORD_ELSEWHERE') THEN
                            v_ca := nullif(regexp_replace(coalesce(r->>'ca', r->>'CA', ''), '[^0-9]', '', 'g'), '')::int;
                            v_exam := nullif(regexp_replace(coalesce(r->>'exam', r->>'EXAM', ''), '[^0-9]', '', 'g'), '')::int;
                            v_total := nullif(regexp_replace(coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark', ''), '[^0-9]', '', 'g'), '')::int;
                            v_outcome := upper(btrim(coalesce(r->>'outcome', 'GRADED')));
                            -- V619: the old portal marks a candidate who did not sit "ABS" (or "AB", "ABSENT", "ABS (F)") — in the Outcome,
                            -- Remark or Grade column, or in place of the mark itself. That is an absence (F, owed), never "No mark": a row
                            -- left unposted shows the candidate as NR on the broadsheet. A mark cell reads as the absence only when no
                            -- mark cell of the row carries a number (an "AB" beside an exam score is not an absence from the examination).
                            IF v_outcome <> 'ABSENT' AND regexp_replace(v_outcome, '[^A-Z]', '', 'g') IN ('ABS', 'AB', 'ABSENT', 'ABSF', 'ABSENTF') THEN
                                v_abs_note := format('"%s" on the old portal read as absent (F)', btrim(r->>'outcome'));
                                v_outcome := 'ABSENT';
                            END IF;
                            IF v_outcome NOT IN ('GRADED','ABSENT','WITHHELD','INCOMPLETE','MALPRACTICE','EXEMPTED') THEN v_outcome := 'GRADED'; END IF;
                            IF v_outcome = 'GRADED' AND v_ca IS NULL AND v_exam IS NULL AND v_total IS NULL THEN
                                SELECT format('"%s" in the %s column read as absent (F)', btrim(x.v), x.k) INTO v_abs_note
                                  FROM (VALUES (1, 'CA', coalesce(r->>'ca', r->>'CA')), (2, 'Exam', coalesce(r->>'exam', r->>'EXAM')),
                                               (3, 'Total', coalesce(r->>'total', r->>'TOTAL', r->>'score', r->>'SCORE', r->>'mark'))) x(o, k, v)
                                 WHERE regexp_replace(upper(coalesce(x.v, '')), '[^A-Z]', '', 'g') IN ('ABS', 'AB', 'ABSENT', 'ABSF', 'ABSENTF')
                                 ORDER BY x.o LIMIT 1;
                                IF v_abs_note IS NOT NULL THEN v_outcome := 'ABSENT'; END IF;
                            END IF;
                            -- V614: the old portal's mark as it stands, never refused for the 40/60 split. CA and exam as the record splits them
                            -- (CA 0–40, exam 0–60) stay so; otherwise the mark is the whole, out of 100: the Total column where the file has
                            -- one, else an exam column over 60 or with no CA beside it (the old portal had added the CA in), else a CA over 40
                            -- added to the exam
                            IF v_outcome = 'GRADED' THEN
                                IF v_ca IS NOT NULL AND v_exam IS NOT NULL AND v_ca <= 40 AND v_exam <= 60 AND (v_total IS NULL OR v_total = v_ca + v_exam) THEN
                                    v_total := NULL;
                                ELSIF v_total IS NOT NULL THEN
                                    IF v_ca IS NOT NULL OR v_exam IS NOT NULL THEN
                                        v_mark_note := format('the Total column taken as the mark: %s of 100', v_total);
                                    END IF;
                                    v_ca := NULL; v_exam := NULL;
                                ELSIF v_exam IS NOT NULL AND (v_ca IS NULL OR v_exam > 60) THEN
                                    v_mark_note := format('the exam column read as the whole mark: %s of 100%s', v_exam,
                                                          CASE WHEN v_ca IS NOT NULL THEN format(' (the CA of %s already in it)', v_ca) ELSE '' END);
                                    v_total := v_exam; v_ca := NULL; v_exam := NULL;
                                ELSIF v_exam IS NOT NULL THEN
                                    v_mark_note := format('CA %s and exam %s added as the whole mark: %s of 100', v_ca, v_exam, v_ca + v_exam);
                                    v_total := v_ca + v_exam; v_ca := NULL; v_exam := NULL;
                                ELSIF v_ca IS NOT NULL THEN
                                    v_total := v_ca; v_ca := NULL;   -- a lone mark is the whole, as before
                                END IF;
                            END IF;
                            IF v_outcome = 'GRADED' AND ((v_total IS NULL AND (v_ca IS NULL OR v_exam IS NULL)) OR coalesce(v_total, 0) > 100) THEN
                                v_status := 'NO_MARK';
                                v_detail := CASE WHEN coalesce(v_total, 0) > 100 THEN format('The mark is over 100 (%s)', v_total) ELSE 'No mark' END
                                            || CASE WHEN v_new_entry THEN '; the course was still registered' ELSE '' END;
                            ELSE
                                -- V614: a result already on record is not posted twice — the same one is left as it is, a different one an
                                -- earlier upload posted is replaced (and said so), one entered on the portal is never loaded over
                                -- V771: the main sitting's sheet (a re-sit or special sheet is never the one an old-portal mark goes on)
                                SELECT sh.id INTO v_sheet FROM assessment.score_sheet sh LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                                 WHERE sh.offering_id = v_offering ORDER BY (coalesce(es.kind, 'MAIN') = 'MAIN') DESC, sh.id LIMIT 1;
                                v_prev_found := false;
                                IF v_sheet IS NOT NULL THEN
                                    SELECT * INTO v_prev FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student ORDER BY version DESC LIMIT 1;
                                    v_prev_found := FOUND;
                                END IF;
                                IF v_prev_found AND v_prev.outcome = v_outcome
                                   AND (v_outcome <> 'GRADED' OR coalesce(v_prev.total, v_prev.ca + v_prev.exam) = coalesce(v_total, v_ca + v_exam)) THEN
                                    v_status := CASE WHEN v_status IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'CATEGORY_CORRECTED', 'AS_TAKEN_LINKED', 'UNITS_ON_PORTAL',
                                                                        'UNITS_BY_AMENDMENT', 'AS_TAKEN_DIFFERS') THEN v_status ELSE 'RESULT_ALREADY_ON_RECORD' END;
                                    v_detail := format('The same result is on record (%s); not posted again',
                                                       assessment.legacy_mark_words(v_prev.outcome, v_prev.ca, v_prev.exam, v_prev.total))
                                                || CASE WHEN v_status <> 'RESULT_ALREADY_ON_RECORD' THEN '; ' || coalesce(v_detail, '') ELSE '' END;
                                    DELETE FROM assessment.legacy_result_holding
                                     WHERE session = p_session AND semester = p_semester AND matric = v_matric AND course_code = v_code;
                                ELSIF v_prev_found AND NOT v_prev.imported THEN
                                    v_status := 'RESULT_ON_PORTAL';
                                    v_detail := format('A result entered on the portal is on record (%s); the old portal''s (%s) is not loaded over it — amend it through Result amendments',
                                                       assessment.legacy_mark_words(v_prev.outcome, v_prev.ca, v_prev.exam, v_prev.total),
                                                       assessment.legacy_mark_words(v_outcome, v_ca, v_exam, v_total))
                                                || CASE WHEN v_entry_state IN ('UNITS_ON_PORTAL', 'UNITS_BY_AMENDMENT', 'AS_TAKEN_DIFFERS', 'UNITS_CORRECTED',
                                                                               'AS_TAKEN_CORRECTED', 'CATEGORY_CORRECTED', 'AS_TAKEN_LINKED')
                                                        THEN '; ' || v_entry_detail ELSE '' END;
                                ELSE
                                    IF v_sheet IS NULL THEN
                                        v_sheet := gen_random_uuid();
                                        INSERT INTO assessment.score_sheet (id, offering_id, stage, senate_minute, published_at)
                                        VALUES (v_sheet, v_offering, 'PUBLISHED', 'Migrated from the legacy portal', now());
                                    ELSIF (SELECT stage FROM assessment.score_sheet WHERE id = v_sheet) <> 'PUBLISHED' THEN
                                        UPDATE assessment.score_sheet SET stage = 'PUBLISHED', senate_minute = coalesce(senate_minute, 'Migrated from the legacy portal'),
                                               published_at = coalesce(published_at, now()) WHERE id = v_sheet;
                                    END IF;
                                    v_score_v := coalesce((SELECT max(version) + 1 FROM assessment.score WHERE sheet_id = v_sheet AND student_id = v_student), 1);
                                    INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, total, outcome, imported, reason)
                                    VALUES (v_sheet, v_student, v_score_v,
                                            CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_ca END,
                                            CASE WHEN v_outcome = 'GRADED' AND v_exam IS NOT NULL THEN v_exam END,
                                            CASE WHEN v_outcome = 'GRADED' AND v_exam IS NULL THEN v_total END,
                                            v_outcome, true,
                                            CASE WHEN v_prev_found THEN 'Re-imported from the legacy portal' END);
                                    DELETE FROM assessment.legacy_result_holding
                                     WHERE session = p_session AND semester = p_semester AND matric = v_matric AND course_code = v_code;
                                    v_posted := true;
                                    v_kinds := v_kinds || CASE WHEN v_prev_found THEN 'RESULT_REPLACED' ELSE 'RESULT_POSTED' END;
                                    v_detail := 'Result posted' || coalesce('; ' || v_abs_note, '') || coalesce('; ' || v_mark_note, '')
                                                || CASE WHEN v_prev_found THEN format('; replaces %s an earlier upload posted',
                                                                                      assessment.legacy_mark_words(v_prev.outcome, v_prev.ca, v_prev.exam, v_prev.total)) ELSE '' END
                                                || coalesce('; ' || v_detail, '');
                                    v_status := CASE WHEN v_prev_found THEN 'RESULT_REPLACED' WHEN v_mark_note IS NOT NULL THEN 'RESULT_AS_TOTAL' ELSE 'RESULT_POSTED' END;
                                END IF;
                            END IF;
                        END IF;

                        -- V771: the ledger — every change, with what was there before; the student's CGPA before their first change
                        IF cardinality(v_kinds) > 0 THEN
                            IF v_kinds && ARRAY['ENTRY_ADDED', 'UNITS_CORRECTED', 'ENTRY_REAPPROVED', 'RESULT_POSTED', 'RESULT_REPLACED'] THEN
                                IF NOT (v_student = ANY (v_moved)) THEN v_moved := v_moved || v_student; END IF;
                            END IF;
                            IF p_as_taken AND NOT (v_offering = ANY (v_classes)) THEN v_classes := v_classes || v_offering; END IF;
                            IF v_upload IS NOT NULL THEN
                                INSERT INTO assessment.past_upload_change (upload_id, kind, student_id, registration_id, offering_id, course_code, session, semester, line,
                                                                           was_units, now_units, was_as_taken, now_as_taken, was_code, now_code, was_title, now_title,
                                                                           was_entry_type, now_entry_type, was_basis, now_basis, was_status, now_status,
                                                                           sheet_id, was_score_version, now_score_version, level, graduate, course_kind)
                                SELECT v_upload, k, v_student, v_reg, CASE WHEN k IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_offering END,
                                       v_code, p_session, p_semester, v_line,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_entry_units END,
                                       CASE WHEN k IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE e.units END,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_entry_at END,
                                       CASE WHEN k IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE e.as_taken_id END,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_printed_code END, v_code_as,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_printed_title END, v_title,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_entry_type END,
                                       CASE WHEN k IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE e.entry_type END,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_entry_basis END,
                                       CASE WHEN k IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE e.basis END,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_entry_status END,
                                       CASE WHEN k = 'REGISTRATION_ADDED' THEN 'APPROVED' WHEN k = 'ENROLMENT_ADDED' THEN NULL ELSE e.status END,
                                       CASE WHEN k IN ('RESULT_POSTED', 'RESULT_REPLACED') THEN v_sheet END,
                                       CASE WHEN k = 'RESULT_REPLACED' THEN v_prev.version
                                            -- an entry added or approved again: the newest mark on its class then (a later one is a change since)
                                            WHEN k IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') THEN
                                                coalesce((SELECT max(sc.version) FROM assessment.score_sheet sh JOIN assessment.score sc ON sc.sheet_id = sh.id
                                                           WHERE sh.offering_id = v_offering AND sc.student_id = v_student), 0) END,
                                       CASE WHEN k IN ('RESULT_POSTED', 'RESULT_REPLACED') THEN v_score_v END,
                                       CASE WHEN k IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN v_reg_lvl END,
                                       v_graduate,
                                       CASE WHEN k NOT IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN (SELECT ck.kind FROM catalogue.course ck WHERE ck.code = v_code) END
                                  FROM unnest(v_kinds) WITH ORDINALITY u(k, ord)
                                  LEFT JOIN registration.entry e ON e.registration_id = v_reg AND e.offering_id = v_offering
                                 ORDER BY u.ord;
                                v_before := v_gpa_before->(v_student::text);
                                INSERT INTO assessment.past_upload_student (upload_id, student_id, cgpa_before, tcr_before, cgpa_after, tcr_after, graduate, changes)
                                VALUES (v_upload, v_student, (v_before->>'cgpa')::numeric, (v_before->>'tcr')::int,
                                        (v_before->>'cgpa')::numeric, (v_before->>'tcr')::int, v_graduate, cardinality(v_kinds))
                                ON CONFLICT (upload_id, student_id) DO UPDATE SET changes = assessment.past_upload_student.changes + cardinality(v_kinds);
                                IF NOT (v_student = ANY (v_touched)) THEN v_touched := v_touched || v_student; END IF;
                            END IF;
                        END IF;
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_status := 'REFUSED';
                v_detail := left(SQLERRM, 300);
                v_new_reg := false; v_new_entry := false; v_new_offering := false; v_reapprove := false; v_posted := false; v_kinds := '{}';
                IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ' ' || coalesce(v_code, v_raw_code) || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
            END;

            -- the row's outcome, counted only once its writes stood
            IF NOT p_as_taken AND v_code IS NOT NULL AND v_status NOT IN ('DUPLICATE_IN_FILE') THEN seen_keys := seen_keys || (v_matric || '|' || v_code); END IF;
            CASE v_status
                WHEN 'ADDED' THEN NULL;
                WHEN 'ADDED_TO_OPEN_REGISTRATION' THEN n_open := n_open + 1;
                WHEN 'ALREADY_ON_RECORD' THEN n_already := n_already + 1;
                WHEN 'UNITS_DIFFER' THEN n_units := n_units + 1;
                WHEN 'DROPPED_ON_RECORD' THEN n_dropped := n_dropped + 1;
                WHEN 'NO_STUDENT' THEN nns := nns + 1;
                WHEN 'HELD' THEN n_held := n_held + 1;
                WHEN 'NO_COURSE' THEN nnc := nnc + 1;
                WHEN 'NO_MARK' THEN nnm := nnm + 1;
                WHEN 'DUPLICATE_IN_FILE' THEN n_dup := n_dup + 1;
                WHEN 'RESULT_ALREADY_ON_RECORD' THEN n_res_same := n_res_same + 1;
                WHEN 'RESULT_ON_PORTAL' THEN n_res_portal := n_res_portal + 1;
                WHEN 'RESULT_REPLACED' THEN n_res_replaced := n_res_replaced + 1;
                WHEN 'REFUSED' THEN n_refused := n_refused + 1;
                WHEN 'AS_TAKEN_MISSING' THEN n_missing := n_missing + 1;
                WHEN 'AS_TAKEN_INVALID' THEN n_invalid := n_invalid + 1;
                WHEN 'COURSE_AMBIGUOUS' THEN n_ambiguous := n_ambiguous + 1;
                WHEN 'DUPLICATE_CONFLICT' THEN n_conflict := n_conflict + 1;
                WHEN 'COURSE_ON_RECORD_ELSEWHERE' THEN n_elsewhere := n_elsewhere + 1;
                WHEN 'REMOVED_ON_RECORD' THEN n_removed := n_removed + 1;
                WHEN 'REMOVAL_PENDING' THEN n_pending := n_pending + 1;
                WHEN 'UNITS_ON_PORTAL' THEN n_on_portal := n_on_portal + 1;
                WHEN 'UNITS_BY_AMENDMENT' THEN n_by_senate := n_by_senate + 1;
                WHEN 'AS_TAKEN_DIFFERS' THEN n_differs := n_differs + 1;
                ELSE NULL;
            END CASE;
            -- a posted result's course was already on record, or on record at other units, or added
            IF v_posted AND v_entry_state = 'ALREADY_ON_RECORD' THEN n_already := n_already + 1; END IF;
            IF v_posted AND v_entry_state = 'UNITS_DIFFER' THEN n_units := n_units + 1; END IF;
            IF v_posted AND v_entry_state = 'ADDED_TO_OPEN_REGISTRATION' THEN n_open := n_open + 1; END IF;
            IF v_status IS DISTINCT FROM v_entry_state AND v_entry_state IN ('UNITS_ON_PORTAL', 'UNITS_BY_AMENDMENT', 'AS_TAKEN_DIFFERS') THEN
                CASE v_entry_state WHEN 'UNITS_ON_PORTAL' THEN n_on_portal := n_on_portal + 1; WHEN 'UNITS_BY_AMENDMENT' THEN n_by_senate := n_by_senate + 1;
                                   ELSE n_differs := n_differs + 1; END CASE;
            END IF;
            IF 'UNITS_CORRECTED' = ANY (v_kinds) THEN n_units_corr := n_units_corr + 1; END IF;
            IF 'AS_TAKEN_CORRECTED' = ANY (v_kinds) THEN n_ident_corr := n_ident_corr + 1; END IF;
            IF 'AS_TAKEN_LINKED' = ANY (v_kinds) THEN n_linked := n_linked + 1; END IF;
            IF 'CATEGORY_CORRECTED' = ANY (v_kinds) THEN n_cat_corr := n_cat_corr + 1; END IF;
            IF v_at IS NOT NULL AND v_at_existed AND NOT (v_at = ANY (v_reused_ats)) THEN v_reused_ats := v_reused_ats || v_at; END IF;
            IF v_match = 'CODE_ONLY_NEW_TITLE' AND v_status NOT IN ('REFUSED', 'NO_STUDENT', 'DUPLICATE_IN_FILE', 'DUPLICATE_CONFLICT') THEN n_new_title := n_new_title + 1; END IF;
            IF v_new_reg THEN n_reg := n_reg + 1; v_newregs := v_newregs || jsonb_build_object(v_matric || '|' || p_session || '|' || p_semester, true); END IF;
            IF v_new_entry THEN n_entry := n_entry + 1; END IF;
            IF v_reapprove THEN n_reapproved := n_reapproved + 1; END IF;
            IF v_posted THEN n_res := n_res + 1; END IF;
            IF v_posted AND v_mark_note IS NOT NULL THEN n_as_total := n_as_total + 1; END IF;
            IF v_posted AND v_abs_note IS NOT NULL THEN n_absent := n_absent + 1; END IF;
            IF v_status IN ('ADDED', 'ADDED_TO_OPEN_REGISTRATION', 'ALREADY_ON_RECORD', 'UNITS_DIFFER', 'DROPPED_ON_RECORD', 'RESULT_POSTED', 'NO_MARK',
                            'RESULT_AS_TOTAL', 'RESULT_REPLACED', 'RESULT_ALREADY_ON_RECORD', 'RESULT_ON_PORTAL',
                            'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED', 'UNITS_ON_PORTAL', 'UNITS_BY_AMENDMENT', 'AS_TAKEN_DIFFERS') THEN
                IF NOT (v_student = ANY (seen_students)) THEN seen_students := seen_students || v_student; END IF;
                IF NOT (v_code = ANY (seen_codes)) THEN seen_codes := seen_codes || v_code; n_off := n_off + 1; END IF;
                IF v_graduate AND (v_kinds && ARRAY['ENTRY_ADDED', 'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'CATEGORY_CORRECTED', 'ENTRY_REAPPROVED', 'RESULT_POSTED', 'RESULT_REPLACED']) THEN
                    v_graduates := v_graduates || jsonb_build_object(v_matric, true);
                END IF;
                -- V771: the course as taken, keyed so the check's batches add up (a class made in a batch that is undone has another id)
                IF p_as_taken AND v_code_as IS NOT NULL THEN
                    v_ckey := concat_ws('|', v_code, p_session, p_semester, v_stream, v_code_as, v_title, v_cu);
                    v_courses := jsonb_set(v_courses, ARRAY[v_ckey], jsonb_build_object(
                        'courseCode', v_code, 'codeAsTaken', v_code_as, 'title', v_title, 'units', v_cu, 'currentTitle', v_cur_title,
                        'currentUnits', v_cur_units, 'session', p_session, 'semester', p_semester, 'stream', v_stream, 'match', v_match,
                        'made', coalesce((v_courses->v_ckey->>'made')::boolean, false) OR (v_at IS NOT NULL AND NOT v_at_existed),
                        'existed', coalesce((v_courses->v_ckey->>'existed')::boolean, false) OR coalesce(v_at_existed, false),
                        'matrics', coalesce(v_courses->v_ckey->'matrics', '[]'::jsonb) || CASE WHEN coalesce(v_courses->v_ckey->'matrics', '[]'::jsonb) ? v_matric
                                                                                               THEN '[]'::jsonb ELSE to_jsonb(ARRAY[v_matric]) END));
                END IF;
            END IF;
            -- the rows the office reads: every row on a preview; on an import, every row not loaded or left as it was
            v_line_obj := (jsonb_build_object('line', v_line, 'matric', v_matric, 'course', coalesce(v_code, v_raw_code),
                                                          'session', p_session, 'semester', p_semester, 'status', v_status, 'detail', v_detail)
                                       || CASE WHEN p_as_taken THEN jsonb_build_object(
                                              'uploadedCode', v_raw_code, 'uploadedTitle', coalesce(v_title, r->>'title'), 'uploadedUnits', coalesce(v_cu_raw, ''),
                                              'category', coalesce(btrim(r->>'category'), ''), 'matchedCourse', v_code, 'currentTitle', v_cur_title,
                                              'entryStatus', v_entry_state,
                                              'currentUnits', v_cur_units, 'version', CASE WHEN v_at IS NULL THEN NULL WHEN v_at_existed THEN 'EXISTING' ELSE 'NEW' END,
                                              'match', coalesce(v_match, CASE WHEN v_status = 'COURSE_AMBIGUOUS' THEN 'AMBIGUOUS' END),
                                              'action', CASE CASE WHEN v_status IN ('RESULT_POSTED', 'RESULT_AS_TOTAL', 'RESULT_REPLACED', 'RESULT_ON_PORTAL', 'RESULT_ALREADY_ON_RECORD')
                                                                       AND v_entry_state IN ('UNITS_ON_PORTAL', 'UNITS_BY_AMENDMENT', 'AS_TAKEN_DIFFERS')
                                                                  THEN v_entry_state ELSE v_status END
                                                  WHEN 'AS_TAKEN_MISSING' THEN 'Fill the course title, credit units and category in the file, then upload the row again'
                                                  WHEN 'AS_TAKEN_INVALID' THEN 'Correct the cell named in the detail, then upload the row again'
                                                  WHEN 'COURSE_AMBIGUOUS' THEN 'Write the course''s own code (for example its BMAS or V2 code) in the file'
                                                  WHEN 'NO_COURSE' THEN 'Check the code; add the course to the catalogue if it is missing'
                                                  WHEN 'DUPLICATE_CONFLICT' THEN 'Keep one row for this student and course'
                                                  WHEN 'COURSE_ON_RECORD_ELSEWHERE' THEN 'Take the other course off through Course Registration Correction if it is wrong, then upload again'
                                                  WHEN 'REMOVAL_PENDING' THEN 'Upload the row again after the Registry decides the removal'
                                                  WHEN 'UNITS_ON_PORTAL' THEN 'Amend the units through Result amendments if the file is right'
                                                  WHEN 'UNITS_BY_AMENDMENT' THEN 'The Senate''s units stand; amend them through Result amendments if they are wrong'
                                                  WHEN 'AS_TAKEN_DIFFERS' THEN 'The Directorate of ICT uploads the correction'
                                                  ELSE CASE WHEN v_match = 'CODE_ONLY_NEW_TITLE' THEN 'Check that the code is right: the title differs from every title this course has had' END
                                              END) ELSE '{}'::jsonb END);
            IF p_preview OR v_status NOT IN ('ADDED', 'ADDED_TO_OPEN_REGISTRATION', 'ALREADY_ON_RECORD', 'RESULT_POSTED')
               OR coalesce(v_entry_state, v_status) NOT IN ('ADDED', 'ADDED_TO_OPEN_REGISTRATION', 'ALREADY_ON_RECORD', 'RESULT_POSTED') THEN
                v_lines := v_lines || v_line_obj;
            END IF;
            -- V771: the row's outcome under its upload, whatever it was (a batch sent again updates it)
            IF v_upload IS NOT NULL THEN
                INSERT INTO assessment.past_upload_row (upload_id, session, semester, line, matric, course, status, detail, facts)
                VALUES (v_upload, p_session, p_semester, v_line, v_matric, coalesce(v_code, v_raw_code), v_status, v_detail, v_line_obj)
                ON CONFLICT (upload_id, session, semester, (coalesce(line, '')), matric, course) DO UPDATE
                   SET status = EXCLUDED.status, detail = EXCLUDED.detail, facts = EXCLUDED.facts, loaded_at = clock_timestamp()
                 WHERE assessment.past_upload_row.status NOT IN ('ADDED', 'ADDED_TO_OPEN_REGISTRATION', 'RESULT_POSTED', 'RESULT_AS_TOTAL', 'RESULT_REPLACED',
                                                                'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
                    OR EXCLUDED.status IN ('ADDED', 'ADDED_TO_OPEN_REGISTRATION', 'RESULT_POSTED', 'RESULT_AS_TOTAL', 'RESULT_REPLACED',
                                           'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED');
            END IF;
        END LOOP;

        -- V771: a class all of whose students took one version reads as that version on its sheets (its header)
        IF p_as_taken AND v_may THEN
            FOR v_x IN
                SELECT o.id, o.title AS was_title, o.units AS was_units, min(a.title) AS title, min(a.units) AS units, min(a.code_as_taken) AS code
                  FROM catalogue.offering o
                  JOIN registration.entry e ON e.offering_id = o.id AND e.status IN ('APPROVED', 'REGISTERED')
                  LEFT JOIN catalogue.course_as_taken a ON a.id = e.as_taken_id
                 WHERE o.id = ANY (v_classes)
                 GROUP BY o.id, o.title, o.units
                HAVING bool_and(e.as_taken_id IS NOT NULL) AND count(DISTINCT (a.title, a.units)) = 1
                   AND (o.title IS DISTINCT FROM min(a.title) OR o.units IS DISTINCT FROM min(a.units))
            LOOP
                UPDATE catalogue.offering SET title = v_x.title, units = v_x.units WHERE id = v_x.id;
                n_classes := n_classes + 1;
                IF v_upload IS NOT NULL THEN
                    INSERT INTO assessment.past_upload_change (upload_id, kind, offering_id, course_code, session, semester, was_units, now_units, was_title, now_title, course_kind)
                    SELECT v_upload, 'CLASS_HEADER_CORRECTED', v_x.id, o.course_code, o.session, o.semester, v_x.was_units, v_x.units, v_x.was_title, v_x.title,
                           (SELECT ck.kind FROM catalogue.course ck WHERE ck.code = o.course_code)
                      FROM catalogue.offering o WHERE o.id = v_x.id;
                END IF;
            END LOOP;
        END IF;

        -- V771: each changed student's GPA and CGPA after the call, against before (the check adds the batches' differences up)
        FOR v_x IN SELECT s.id, upper(s.matric_no) AS matric, s.surname || ', ' || s.other_names AS name FROM people.student s WHERE s.id = ANY (v_moved || v_touched) LOOP
            v_before := v_gpa_before->(v_x.id::text);
            v_after := assessment.gpa_snapshot(v_x.id);
            IF v_after IS DISTINCT FROM v_before THEN
                v_gpa := v_gpa || jsonb_build_object('matric', v_x.matric, 'name', v_x.name, 'before', v_before, 'after', v_after);
                v_affected := v_affected || jsonb_build_object(v_x.matric, true);
            END IF;
            IF v_upload IS NOT NULL THEN
                UPDATE assessment.past_upload_student SET cgpa_after = (v_after->>'cgpa')::numeric, tcr_after = (v_after->>'tcr')::int
                 WHERE upload_id = v_upload AND student_id = v_x.id;
            END IF;
        END LOOP;

        IF v_deferred AND NOT p_preview THEN PERFORM people.refresh_deferred_positions(); END IF;
        IF p_preview THEN RAISE EXCEPTION 'LEGACY_PREVIEW_UNDONE' USING ERRCODE = 'P0001'; END IF;
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'LEGACY_PREVIEW_UNDONE' THEN RAISE; END IF;
    END;

    PERFORM set_config('moaum.siwes_override', coalesce(v_siwes_override, ''), true);   -- V752
    RETURN jsonb_build_object(
        'preview', p_preview, 'session', p_session, 'semester', p_semester,
        'rows', n, 'students', cardinality(seen_students), 'offerings', n_off, 'registrations', n_reg, 'entries', n_entry,
        'already', n_already, 'units_differ', n_units, 'dropped_kept', n_dropped, 'added_to_open', n_open, 'reapproved', n_reapproved,
        'results', n_res, 'no_student', nns, 'held', n_held, 'no_course', nnc, 'no_mark', nnm,
        'duplicate', n_dup, 'refused', n_refused, 'skipped', n_refused + n_dup, 'first_error', v_firsterr,
        'marks_as_total', n_as_total, 'results_same', n_res_same, 'results_replaced', n_res_replaced, 'results_on_portal', n_res_portal,
        'absent_from_abs', n_absent,
        'lines', v_lines)
        || CASE WHEN p_as_taken THEN jsonb_build_object(
            'as_taken', true, 'units_corrected', n_units_corr, 'as_taken_corrected', n_ident_corr, 'as_taken_linked', n_linked,
            'category_corrected', n_cat_corr, 'units_on_portal', n_on_portal, 'units_by_amendment', n_by_senate, 'as_taken_differs', n_differs,
            'as_taken_missing', n_missing, 'as_taken_invalid', n_invalid, 'ambiguous', n_ambiguous, 'duplicate_conflict', n_conflict,
            'on_record_elsewhere', n_elsewhere, 'removed_on_record', n_removed, 'removal_pending', n_pending, 'new_title', n_new_title,
            'versions_made', cardinality(v_made_ats), 'versions_reused', cardinality(v_reused_ats), 'classes_corrected', n_classes,
            'courses', coalesce((SELECT jsonb_agg(v ORDER BY v->>'courseCode', v->>'title') FROM jsonb_each(v_courses) AS j(k, v)), '[]'::jsonb),
            'gpa', v_gpa,
            'students_affected', coalesce((SELECT jsonb_agg(k ORDER BY k) FROM jsonb_object_keys(v_affected) k), '[]'::jsonb),
            'graduates', coalesce((SELECT jsonb_agg(k ORDER BY k) FROM jsonb_object_keys(v_graduates) k), '[]'::jsonb),
            'registrations_new', coalesce((SELECT jsonb_agg(k ORDER BY k) FROM jsonb_object_keys(v_newregs) k), '[]'::jsonb),
            'upload', v_up.ref) ELSE '{}'::jsonb END;
END $function$;
COMMENT ON FUNCTION assessment.legacy_semester_load(text, integer, jsonb, boolean, boolean, uuid, boolean) IS
  'V472, V614, V619, V627, V672, V752, V771: the one loader for the old portal''s course registration and past results of a semester. A preview runs it and undoes it. As taken (p_as_taken, the API always): each row''s Course Title, Credit Units and Category are required and recorded on the student''s registration (catalogue.course_as_taken); the course is identified by code and title; a course on record is corrected only by the Directorate of ICT''s offices, never over a portal result, a Senate units amendment or a removal; p_upload names the confirmed upload whose ledger records every change. Without it (fixtures, rows held before V771) the old rule: units from the programme''s structure, what is on record left as it is.';

-- held rows are posted as they came: as taken under their upload, or (held before V771) under the old rule. A row an earlier upload
-- still standing held before the present holder is posted first, under that upload, so the later one replaces it in its own ledger —
-- as for a student already on the register — and a rollback of the later one gives the earlier result back
CREATE OR REPLACE FUNCTION assessment.reconcile_legacy_holding()
 RETURNS TABLE(reconciled integer, still_held integer)
 LANGUAGE plpgsql
AS $function$
DECLARE grp record; v_before int; v_after int;
BEGIN
    PERFORM set_config('moaum.legacy_reconcile', 'on', true);  -- V627: posting held results is open to every migrating office
    SELECT count(*) INTO v_before FROM assessment.legacy_result_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric);
    FOR grp IN
        WITH RECURSIVE held AS (
            SELECT h.session, h.semester, h.matric, h.course_code, h.as_taken, h.upload_id, h.raw, h.loaded_at, h.prior, 0 AS depth
              FROM assessment.legacy_result_holding h
             WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric)
            UNION ALL
            SELECT c.session, c.semester, c.matric, c.course_code, coalesce((c.prior->>'as_taken')::boolean, false), (c.prior->>'upload_id')::uuid,
                   c.prior->'raw', (c.prior->>'loaded_at')::timestamptz, c.prior->'prior', c.depth + 1
              FROM held c WHERE jsonb_typeof(c.prior) = 'object')
        SELECT k.session, k.semester, k.as_taken, k.upload_id, jsonb_agg(k.raw ORDER BY k.loaded_at) AS rows
          FROM (SELECT DISTINCT ON (q.session, q.semester, q.matric, q.course_code, q.upload_id) q.*   -- an upload's newest hold of the row only
                  FROM held q ORDER BY q.session, q.semester, q.matric, q.course_code, q.upload_id, q.depth) k
          LEFT JOIN assessment.past_upload pu ON pu.id = k.upload_id
         WHERE k.depth = 0 OR pu.state IS DISTINCT FROM 'REVERTED'
         GROUP BY k.session, k.semester, k.as_taken, k.upload_id
         ORDER BY min(pu.created_at) NULLS FIRST, min(pu.ref) NULLS FIRST, max(k.depth) DESC
    LOOP
        PERFORM assessment.legacy_semester_load(grp.session, grp.semester, grp.rows, true, false, grp.upload_id, grp.as_taken);
    END LOOP;
    SELECT count(*) INTO v_after FROM assessment.legacy_result_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric);
    PERFORM set_config('moaum.legacy_reconcile', '', true);
    RETURN QUERY SELECT greatest(v_before - v_after, 0),
                        (SELECT count(*)::int FROM assessment.legacy_result_holding);
END $function$;

-- ── a confirmed upload: begun, finished ─────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION assessment.past_upload_begin(p_kind text, p_file text, p_rows int, p_reason text)
RETURNS assessment.past_upload
LANGUAGE plpgsql AS $$
DECLARE u assessment.past_upload; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL OR v_office IS NULL THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: an upload is confirmed by a person' USING ERRCODE = '42501'; END IF;
    IF p_kind NOT IN ('RESULTS', 'REGISTRATION') THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: an upload is RESULTS or REGISTRATION' USING ERRCODE = '23514'; END IF;
    IF p_kind = 'RESULTS' THEN PERFORM assessment.past_results_office(); END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_REASON: say why the file is loaded (ten characters or more); it goes on the record with your name' USING ERRCODE = '23514';
    END IF;
    INSERT INTO assessment.past_upload (ref, kind, file_name, rows, reason, created_by, created_office)
    VALUES ('PRU-' || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('PAST_UPLOAD', 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0'),
            p_kind, nullif(left(btrim(coalesce(p_file, '')), 200), ''), greatest(coalesce(p_rows, 0), 0), btrim(p_reason), v_actor, v_office)
    RETURNING * INTO u;
    RETURN u;
END $$;
COMMENT ON FUNCTION assessment.past_upload_begin(text, text, int, text) IS
  'V771: a confirmed old-portal upload is opened (RUNNING) with its reason; its batches then load under it. Refusals LEGACY_UPLOAD_STATE, LEGACY_UPLOAD_REASON, PAST_RESULTS_OFFICE.';

CREATE FUNCTION assessment.past_upload_finish(p_upload uuid, p_complete boolean)
RETURNS assessment.past_upload
LANGUAGE plpgsql AS $$
DECLARE u assessment.past_upload; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO u FROM assessment.past_upload WHERE id = p_upload FOR UPDATE;
    IF u.id IS NULL THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: no upload %', p_upload USING ERRCODE = 'P0002'; END IF;
    IF u.created_by IS DISTINCT FROM v_actor THEN RAISE EXCEPTION 'LEGACY_UPLOAD_OWN: upload % is another officer''s', u.ref USING ERRCODE = '42501'; END IF;
    IF u.state <> 'RUNNING' THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %', u.ref, lower(u.state) USING ERRCODE = '23514'; END IF;
    UPDATE assessment.past_upload
       SET state = CASE WHEN p_complete THEN 'COMPLETE' ELSE 'INCOMPLETE' END, finished_at = now(), finished_by = v_actor,
           counts = (SELECT jsonb_build_object('changes', count(*), 'students', count(DISTINCT c.student_id),
                                               'byKind', coalesce((SELECT jsonb_object_agg(k.kind, k.n) FROM (SELECT x.kind, count(*) AS n FROM assessment.past_upload_change x
                                                                                                            WHERE x.upload_id = p_upload GROUP BY x.kind) k), '{}'::jsonb),
                                               'graduates', (SELECT count(*) FROM assessment.past_upload_student s WHERE s.upload_id = p_upload AND s.graduate),
                                               'rows', (SELECT count(*) FROM assessment.past_upload_row w WHERE w.upload_id = p_upload),
                                               'byStatus', coalesce((SELECT jsonb_object_agg(k.status, k.n) FROM (SELECT w.status, count(*) AS n FROM assessment.past_upload_row w
                                                                                                                WHERE w.upload_id = p_upload GROUP BY w.status) k), '{}'::jsonb))
                       FROM assessment.past_upload_change c WHERE c.upload_id = p_upload)
     WHERE id = p_upload RETURNING * INTO u;
    RETURN u;
END $$;
-- ── an upload rolled back from its ledger ───────────────────────────────────────────────────────────────────────────────────────
-- each change undone in reverse, and only where the record still holds what the upload put (a later upload, an amendment, a removal
-- since stands, and is listed); an entry the upload added is withdrawn (its mark kept on the sheet as history); a result it replaced
-- gets the earlier marks back as a new version; a first result it posted on a course already on record is listed, never taken back
-- here (Result amendments)
-- a mark that is no change made since: one a rolled-back upload wrote, or one a rollback wrote to put the earlier marks back
CREATE FUNCTION assessment.score_undone(p_sheet uuid, p_student uuid, p_version int)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM assessment.past_upload_change p
                    WHERE p.student_id = p_student AND p.sheet_id = p_sheet AND p.kind IN ('RESULT_POSTED', 'RESULT_REPLACED')
                      AND ((p.reverted_at IS NOT NULL AND p.now_score_version = p_version) OR p.undo_score_version = p_version))
$$;
COMMENT ON FUNCTION assessment.score_undone(uuid, uuid, int) IS
  'V771: whether a mark is a rolled-back upload''s (its change undone) or the one a rollback wrote to put the earlier marks back — neither is a change made since an upload, so neither stops an earlier upload''s rollback.';

-- a student's mark on a sheet that is only history: the first result an upload posted there and its rollback took back, with no mark
-- made since (a later upload's that was rolled back too, or a rollback's restoration, is none) and the course not back on the
-- registration since (a corrected file with the same mark posts nothing new: the mark then counts again)
CREATE FUNCTION assessment.result_rolled_back(p_sheet uuid, p_student uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM assessment.past_upload_change u
                    WHERE u.kind = 'RESULT_POSTED' AND u.reverted_at IS NOT NULL AND u.student_id = p_student AND u.sheet_id = p_sheet
                      AND NOT EXISTS (SELECT 1 FROM assessment.score s
                                       WHERE s.sheet_id = p_sheet AND s.student_id = p_student AND s.version > u.now_score_version
                                         AND NOT assessment.score_undone(s.sheet_id, s.student_id, s.version))
                      -- back on the registration since (a corrected file with the same mark, a registration file, the portal)
                      AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh
                                        JOIN registration.course_registration r ON r.student_id = p_student
                                        JOIN registration.entry e ON e.registration_id = r.id AND e.offering_id = sh.offering_id
                                                                  AND e.status IN ('APPROVED', 'REGISTERED')
                                       WHERE sh.id = p_sheet)
                      -- put back by a later upload that still stands, whatever became of the course afterwards
                      AND NOT EXISTS (SELECT 1 FROM assessment.past_upload_change a
                                       WHERE a.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') AND a.reverted_at IS NULL
                                         AND a.student_id = p_student AND a.offering_id = u.offering_id AND a.changed_at > u.reverted_at))
$$;
COMMENT ON FUNCTION assessment.result_rolled_back(uuid, uuid) IS
  'V771: whether a student''s mark on a sheet is only the history of a rolled-back upload — the first result it posted there, taken back with its course, nothing marked since and the course not put back on the registration since. The result monitor, the duplicates desk and Course Registration Correction pass over it; a mark that was there before the upload, one made since, or one whose course is on the registration again is judged as any other.';

-- anything recorded on a registration besides its courses: a reset, a load decision, a review, a late registration, a SIWES registration,
-- a removal — every table that refers to it, read from the catalogue so a table added later is counted too
CREATE FUNCTION registration.registration_acted_on(p_registration uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
DECLARE k record; v_hit boolean;
BEGIN
    FOR k IN SELECT c.conrelid::regclass AS tbl, a.attname AS col
               FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
              WHERE c.contype = 'f' AND c.confrelid = 'registration.course_registration'::regclass
                AND c.conrelid <> 'registration.entry'::regclass AND cardinality(c.conkey) = 1 LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s WHERE %I = $1)', k.tbl, k.col) INTO v_hit USING p_registration;
        IF v_hit THEN RETURN true; END IF;
    END LOOP;
    RETURN false;
END $$;
COMMENT ON FUNCTION registration.registration_acted_on(uuid) IS
  'V771: whether anything but courses is recorded on a registration (a reset, a load decision, an approval review, a late or SIWES registration, a removal) — every table whose foreign key refers to it; a rollback never deletes such a registration.';

-- a Course Registration Correction recorded on a course since a moment (V772 gives it its reading; none exists before it)
CREATE FUNCTION registration.entry_corrected_since(p_registration uuid, p_offering uuid, p_since timestamptz)
RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT false $$;
COMMENT ON FUNCTION registration.entry_corrected_since(uuid, uuid, timestamptz) IS
  'V771: whether a Course Registration Correction (V772) was asked for, decided or undone on this course of this registration since the moment given — a person has acted on the course, so a rollback leaves it. False until V772.';

-- the registration an upload made is taken off only while it is still what the upload made: no course on it, its status and level as
-- made, nothing recorded on it. NULL when it is gone (now or before), else why it stays
CREATE FUNCTION assessment.revert_registration_added(c assessment.past_upload_change)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = c.registration_id FOR UPDATE;
    IF r.id IS NULL THEN RETURN NULL; END IF;
    IF EXISTS (SELECT 1 FROM registration.entry x WHERE x.registration_id = c.registration_id) THEN
        RETURN 'the registration holds courses kept or added since; left as it is';
    END IF;
    IF r.status IS DISTINCT FROM c.now_status OR r.level IS DISTINCT FROM c.level OR registration.registration_acted_on(r.id) THEN
        RETURN 'the registration has been reset, decided or otherwise acted on since; left as it is';
    END IF;
    DELETE FROM registration.course_registration WHERE id = c.registration_id;
    RETURN NULL;
END $$;

-- the session's enrolment an upload made goes when the student has no registration left in the session and its level stands
CREATE FUNCTION assessment.revert_enrolment_added(c assessment.past_upload_change)
RETURNS text
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM people.enrolment x WHERE x.student_id = c.student_id AND x.session = c.session) THEN RETURN NULL; END IF;
    IF EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = c.student_id AND r.session = c.session) THEN
        RETURN 'the student has a registration in the session; left as it is';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM people.enrolment x WHERE x.student_id = c.student_id AND x.session = c.session AND x.level IS NOT DISTINCT FROM c.level) THEN
        RETURN 'the session''s enrolment has changed since; left as it is';
    END IF;
    DELETE FROM people.enrolment WHERE student_id = c.student_id AND session = c.session;
    RETURN NULL;
END $$;

-- the hold a hold replaced, nearest first, whose upload still stands (a hold of an upload since rolled back is passed over)
CREATE FUNCTION assessment.held_prior_standing(p_prior jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE AS $$
BEGIN
    WHILE p_prior IS NOT NULL AND jsonb_typeof(p_prior) = 'object'
          AND EXISTS (SELECT 1 FROM assessment.past_upload pu WHERE pu.id = (p_prior->>'upload_id')::uuid AND pu.state = 'REVERTED') LOOP
        p_prior := p_prior->'prior';
    END LOOP;
    RETURN CASE WHEN jsonb_typeof(p_prior) = 'object' THEN p_prior END;
END $$;
COMMENT ON FUNCTION assessment.held_prior_standing(jsonb) IS
  'V771: of the holds a held result replaced (assessment.legacy_result_holding.prior, nearest first), the nearest whose upload has not been rolled back — the hold a rollback hands the row back to; NULL when there is none.';

-- one change of an upload's ledger undone, where it is still the last word on what it changed. The rule, for every kind:
--   · a later change in the ledger on the same thing that is not undone stands on it (whoever's upload, whatever the values) — left;
--   · the record no longer reads what the change left there — left;
--   · a person has acted on it since in a way that leaves no mark on it (the Senate's units at the same figure, a Course Registration
--     Correction asked for or undone, a registration reset or decided) — left;
--   · otherwise it is put back as it was.
-- A mark stands on a course unless a rollback undid it (assessment.score_undone) or it is the first result of an upload that is
-- itself rolled back: that result goes with the course. true when the change was undone
CREATE FUNCTION assessment.revert_change(p_change uuid, p_reason text, p_rolling uuid, p_by text)
RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE c assessment.past_upload_change; u assessment.past_upload; e registration.entry; o catalogue.offering;
        v_last assessment.score; v_was assessment.score; v_note text; v_done boolean := false; v_senate text; v_reason text;
        v_rolling text; v_later boolean := false; v_course text;
        v_when text := CASE WHEN p_by IS NOT NULL THEN 'undone when ' || p_by || ' was rolled back' END;
BEGIN
    IF coalesce(current_setting('moaum.upload_rollback', true), '') <> 'on' THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: an upload''s changes are undone by its rollback (assessment.revert_past_upload), never on their own'
              USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM assessment.past_upload_change WHERE id = p_change FOR UPDATE;
    IF c.id IS NULL OR c.reverted_at IS NOT NULL THEN RETURN false; END IF;   -- undone already (with its course, or with its row's other corrections)
    SELECT * INTO u FROM assessment.past_upload WHERE id = c.upload_id;
    SELECT pu.ref INTO v_rolling FROM assessment.past_upload pu WHERE pu.id = p_rolling;
    v_reason := 'Upload ' || u.ref || ' rolled back: ' || btrim(p_reason);
    IF c.registration_id IS NOT NULL AND c.offering_id IS NOT NULL THEN
        SELECT * INTO e FROM registration.entry WHERE registration_id = c.registration_id AND offering_id = c.offering_id FOR UPDATE;
        -- a later change to the course that is not undone stands on it; one row's corrections are one change (they share a snapshot)
        v_later := EXISTS (SELECT 1 FROM assessment.past_upload_change p
                            WHERE p.registration_id = c.registration_id AND p.offering_id = c.offering_id AND p.seq > c.seq AND p.reverted_at IS NULL
                              AND p.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED', 'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
                              AND NOT (p.upload_id = c.upload_id AND c.kind IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
                                       AND p.kind IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
                                       AND p.was_units IS NOT DISTINCT FROM c.was_units AND p.now_units IS NOT DISTINCT FROM c.now_units
                                       AND p.was_as_taken IS NOT DISTINCT FROM c.was_as_taken AND p.now_as_taken IS NOT DISTINCT FROM c.now_as_taken
                                       AND p.was_entry_type IS NOT DISTINCT FROM c.was_entry_type AND p.now_entry_type IS NOT DISTINCT FROM c.now_entry_type
                                       AND p.was_basis IS NOT DISTINCT FROM c.was_basis AND p.now_basis IS NOT DISTINCT FROM c.now_basis));
        -- the Senate's units stand on the course: an amendment applied at the units the upload had put moves nothing on the entry, so
        -- it is asked for as the loader asks (never written over, by a file or by a rollback)
        v_senate := CASE WHEN e.registration_id IS NOT NULL AND e.units = c.now_units AND c.was_units IS DISTINCT FROM c.now_units
                          AND c.kind IN ('ENTRY_REAPPROVED', 'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
                         THEN assessment.entry_units_by_senate(c.offering_id, (SELECT st.programme_code FROM people.student st WHERE st.id = c.student_id),
                                                               e.units, e.as_taken_id, c.student_id) END;
    END IF;

    IF c.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') THEN
        IF e.registration_id IS NULL THEN
            v_note := 'the course is no longer on the registration; left as it is';
        ELSIF v_later THEN
            v_note := 'a later upload has changed this course since and still stands; left as it is';
        ELSIF e.status IS DISTINCT FROM c.now_status OR e.units IS DISTINCT FROM c.now_units OR e.as_taken_id IS DISTINCT FROM c.now_as_taken
              OR e.entry_type IS DISTINCT FROM c.now_entry_type OR e.basis IS DISTINCT FROM c.now_basis THEN
            v_note := 'the course has changed on the registration since the upload; left as it is';
        ELSIF registration.entry_corrected_since(c.registration_id, c.offering_id, c.changed_at) THEN
            v_note := 'a Course Registration Correction has been recorded on this course since the upload; left as it is';
        ELSIF EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score s ON s.sheet_id = sh.id
                       WHERE sh.offering_id = c.offering_id AND s.student_id = c.student_id
                         AND s.version > coalesce(c.was_score_version, 0)   -- newer than the newest on the class when the course was added
                         AND NOT assessment.score_undone(s.sheet_id, s.student_id, s.version)
                         -- the first result of this upload, or of an upload that is rolled back, goes with the course
                         AND NOT EXISTS (SELECT 1 FROM assessment.past_upload_change p JOIN assessment.past_upload pu ON pu.id = p.upload_id
                                          WHERE p.kind = 'RESULT_POSTED' AND p.sheet_id = s.sheet_id AND p.student_id = s.student_id
                                            AND p.now_score_version = s.version AND p.registration_id = c.registration_id AND p.offering_id = c.offering_id
                                            AND (p.upload_id = c.upload_id OR pu.state = 'REVERTED' OR pu.id = p_rolling))) THEN
            v_note := 'a result has been entered or changed on this course since the upload; left as it is';
        ELSIF c.kind = 'ENTRY_ADDED' THEN
            -- as if it had never been added: a mark an upload posted on it stays on its sheet as history, the ledger says why it has no
            -- registration (the result monitor passes over it), and a corrected file adds the course afresh
            DELETE FROM registration.entry WHERE registration_id = c.registration_id AND offering_id = c.offering_id;
            v_done := true;
        ELSE
            -- dropped again as it was; the Senate's units, where they are the Senate's, stay with their version
            UPDATE registration.entry SET status = c.was_status,
                   units = CASE WHEN v_senate IS NOT NULL THEN units ELSE coalesce(c.was_units, units) END,
                   as_taken_id = CASE WHEN v_senate IS NOT NULL THEN as_taken_id ELSE c.was_as_taken END,
                   entry_type = coalesce(c.was_entry_type, entry_type), basis = c.was_basis
             WHERE registration_id = c.registration_id AND offering_id = c.offering_id;
            v_done := true;
        END IF;
        IF v_done THEN
            -- the first results on it go with it (each kept on its sheet as history): this upload's, and those of uploads rolled back
            -- (or being rolled back) that were posted after the course was put there
            UPDATE assessment.past_upload_change p
               SET reverted_at = clock_timestamp(),
                   revert_note = CASE WHEN p.upload_id = c.upload_id THEN v_when
                                      ELSE 'taken back with its course when ' || coalesce(v_rolling, u.ref) || ' was rolled back' END
              FROM assessment.past_upload pu
             WHERE pu.id = p.upload_id AND p.kind = 'RESULT_POSTED' AND p.reverted_at IS NULL
               AND p.registration_id = c.registration_id AND p.offering_id = c.offering_id
               AND (p.upload_id = c.upload_id
                    OR ((pu.state = 'REVERTED' OR pu.id = p_rolling) AND p.now_score_version > coalesce(c.was_score_version, 0)));
        ELSE
            -- the result this upload posted on it stays with it, for the same reason
            UPDATE assessment.past_upload_change p SET revert_note = v_note
             WHERE p.upload_id = c.upload_id AND p.kind = 'RESULT_POSTED' AND p.reverted_at IS NULL
               AND p.registration_id = c.registration_id AND p.offering_id = c.offering_id;
        END IF;
    ELSIF c.kind = 'RESULT_POSTED' THEN
        -- on a course this upload added or approved again it is decided with that course (the ledger is walked newest first)
        IF EXISTS (SELECT 1 FROM assessment.past_upload_change a
                    WHERE a.upload_id = c.upload_id AND a.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') AND a.reverted_at IS NULL
                      AND a.registration_id = c.registration_id AND a.offering_id = c.offering_id) THEN
            RETURN false;
        END IF;
        -- a first result on a course already on the registration cannot be taken off without the course
        SELECT pu.ref INTO v_course FROM assessment.past_upload_change a JOIN assessment.past_upload pu ON pu.id = a.upload_id
         WHERE a.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') AND a.reverted_at IS NULL AND a.upload_id <> c.upload_id
           AND a.registration_id = c.registration_id AND a.offering_id = c.offering_id AND a.seq < c.seq
         ORDER BY a.seq DESC LIMIT 1;
        v_note := CASE WHEN v_course IS NOT NULL
                       THEN 'a first result on a course ' || v_course || ' put on the registration: it goes with that course when ' || v_course
                            || ' is rolled back; until then amend it through Result amendments'
                       ELSE 'a first result on a course already on record is not taken back here; amend it through Result amendments' END;
    ELSIF c.kind = 'RESULT_REPLACED' THEN
        SELECT * INTO v_last FROM assessment.score WHERE sheet_id = c.sheet_id AND student_id = c.student_id ORDER BY version DESC LIMIT 1;
        SELECT * INTO v_was FROM assessment.score WHERE sheet_id = c.sheet_id AND student_id = c.student_id AND version = c.was_score_version;
        -- still this upload's result: its mark is the newest, or every later one is a rolled-back upload's or a rollback's restoration
        IF v_last.version IS NOT NULL AND v_was.version IS NOT NULL
           AND (v_last.version = c.now_score_version
                OR NOT EXISTS (SELECT 1 FROM assessment.score s WHERE s.sheet_id = c.sheet_id AND s.student_id = c.student_id
                                  AND s.version > c.now_score_version AND NOT assessment.score_undone(s.sheet_id, s.student_id, s.version))) THEN
            INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, total, outcome, imported, reason)
            VALUES (c.sheet_id, c.student_id, v_last.version + 1, v_was.ca, v_was.exam, v_was.total, v_was.outcome, v_was.imported, v_reason);
            UPDATE assessment.past_upload_change SET undo_score_version = v_last.version + 1 WHERE id = c.id;
            v_done := true;
        ELSE
            v_note := 'the result has changed since; left as it is';
        END IF;
    ELSIF c.kind IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED') THEN
        IF e.registration_id IS NULL THEN
            v_note := 'the course is no longer on the registration; left as it is';
        ELSIF v_later THEN
            v_note := 'a later upload has changed this course since and still stands; left as it is';
        ELSIF NOT (e.units = c.now_units AND e.as_taken_id IS NOT DISTINCT FROM c.now_as_taken
                   AND e.entry_type IS NOT DISTINCT FROM c.now_entry_type AND e.basis IS NOT DISTINCT FROM c.now_basis) THEN
            v_note := 'the course has changed on the registration since; left as it is';
        ELSIF v_senate IS NOT NULL THEN
            v_note := 'the Senate set these units (' || v_senate || '); left as it is';
        ELSE
            UPDATE registration.entry SET units = c.was_units, as_taken_id = c.was_as_taken, entry_type = c.was_entry_type, basis = c.was_basis
             WHERE registration_id = c.registration_id AND offering_id = c.offering_id;
            v_done := true;
            -- the row's other corrections were written from the same snapshot: undone with this one
            UPDATE assessment.past_upload_change p SET reverted_at = clock_timestamp(), revert_note = v_when
             WHERE p.upload_id = c.upload_id AND p.id <> c.id AND p.reverted_at IS NULL
               AND p.registration_id = c.registration_id AND p.offering_id = c.offering_id
               AND p.kind IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
               AND p.was_units IS NOT DISTINCT FROM c.was_units AND p.now_units IS NOT DISTINCT FROM c.now_units
               AND p.was_as_taken IS NOT DISTINCT FROM c.was_as_taken AND p.now_as_taken IS NOT DISTINCT FROM c.now_as_taken
               AND p.was_entry_type IS NOT DISTINCT FROM c.was_entry_type AND p.now_entry_type IS NOT DISTINCT FROM c.now_entry_type
               AND p.was_basis IS NOT DISTINCT FROM c.was_basis AND p.now_basis IS NOT DISTINCT FROM c.now_basis;
        END IF;
    ELSIF c.kind = 'CLASS_HEADER_CORRECTED' THEN
        SELECT * INTO o FROM catalogue.offering WHERE id = c.offering_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM assessment.past_upload_change p
                    WHERE p.kind = 'CLASS_HEADER_CORRECTED' AND p.offering_id = c.offering_id AND p.seq > c.seq AND p.reverted_at IS NULL) THEN
            v_note := 'a later upload has set this class''s heading since and still stands; left as it is';
        ELSIF o.id IS NULL OR o.title IS DISTINCT FROM c.now_title OR o.units IS DISTINCT FROM c.now_units THEN
            v_note := 'the class has changed since; left as it is';
        ELSIF (SELECT count(*) > 0 AND bool_and(a.id IS NOT NULL AND a.title IS NOT DISTINCT FROM c.now_title AND a.units IS NOT DISTINCT FROM c.now_units)
                 FROM registration.entry en LEFT JOIN catalogue.course_as_taken a ON a.id = en.as_taken_id
                WHERE en.offering_id = c.offering_id AND en.status IN ('APPROVED', 'REGISTERED')) THEN
            -- the heading reads what all its students took: their courses were left as the upload put them (the walk undoes the
            -- courses first), so the heading stays with them
            v_note := 'every student of the class still carries the course as this heading reads; left as it is';
        ELSE
            UPDATE catalogue.offering SET title = c.was_title, units = c.was_units WHERE id = c.offering_id;
            v_done := true;
        END IF;
    ELSIF c.kind = 'REGISTRATION_ADDED' THEN
        -- the registration the upload made goes when nothing is left on it and nothing has been done to it since
        v_note := assessment.revert_registration_added(c);
        v_done := v_note IS NULL;
    ELSIF c.kind = 'ENROLMENT_ADDED' THEN
        v_note := assessment.revert_enrolment_added(c);
        v_done := v_note IS NULL;
    END IF;
    UPDATE assessment.past_upload_change SET reverted_at = CASE WHEN v_done THEN clock_timestamp() END,
           revert_note = CASE WHEN v_done THEN v_when ELSE v_note END WHERE id = c.id;
    RETURN v_done;
END $$;
COMMENT ON FUNCTION assessment.revert_change(uuid, text, uuid, text) IS
  'V771: one change of an upload''s ledger undone where it is still the last word on what it changed — no later change in the ledger stands on it, the record still reads what it left, and no one has acted on it since (the Senate''s units, a Course Registration Correction, a registration reset or decided); a first result of a rolled-back upload goes with its course. Called by assessment.revert_past_upload, never on its own (LEGACY_UPLOAD_STATE without its moaum.upload_rollback handshake).';

CREATE FUNCTION assessment.revert_past_upload(p_upload uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        u assessment.past_upload; k record; n_held int := 0; n_round int; v_counts jsonb; v_left jsonb;
        v_started timestamptz;
BEGIN
    IF v_office IS NULL OR NOT assessment.past_results_may() THEN
        RAISE EXCEPTION 'LEGACY_REVERT_OFFICE: an upload is rolled back by the Directorate of ICT or a Database Operator granted over the University' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_REASON: say why the upload is rolled back (ten characters or more); it goes on the record with your name' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO u FROM assessment.past_upload WHERE id = p_upload FOR UPDATE;
    IF u.id IS NULL THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: no upload %', p_upload USING ERRCODE = 'P0002'; END IF;
    IF u.state NOT IN ('COMPLETE', 'INCOMPLETE') THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %; %', u.ref, lower(u.state),
              CASE WHEN u.state = 'RUNNING' THEN 'close it first' ELSE 'it is rolled back already' END USING ERRCODE = '23514';
    END IF;
    -- results it still holds for students not yet on the register never post under a rolled-back upload: each hold goes back to the
    -- nearest earlier upload still standing that held the row before it (the same file loaded twice), or is dropped. A row a later
    -- upload holds now, or has posted, is that upload's and stays as it is
    WITH mine AS MATERIALIZED (SELECT hx.session, hx.semester, hx.matric, hx.course_code, hx.raw->>'line' AS line,
                                      assessment.held_prior_standing(hx.prior) AS j
                                 FROM assessment.legacy_result_holding hx WHERE hx.upload_id = p_upload),
         back AS (UPDATE assessment.legacy_result_holding h
                     SET upload_id = (SELECT pu.id FROM assessment.past_upload pu WHERE pu.id = (m.j->>'upload_id')::uuid),
                         raw = m.j->'raw', as_taken = coalesce((m.j->>'as_taken')::boolean, false), loaded_at = (m.j->>'loaded_at')::timestamptz,
                         prior = CASE WHEN jsonb_typeof(m.j->'prior') = 'object' THEN m.j->'prior' END
                    FROM mine m
                   WHERE m.j IS NOT NULL AND h.session = m.session AND h.semester = m.semester AND h.matric = m.matric AND h.course_code = m.course_code
                  RETURNING 1),
         gone AS (DELETE FROM assessment.legacy_result_holding h USING mine m
                   WHERE m.j IS NULL AND h.session = m.session AND h.semester = m.semester AND h.matric = m.matric AND h.course_code = m.course_code
                  RETURNING 1),
         marked AS (UPDATE assessment.past_upload_row pr SET status = 'HELD_ROLLED_BACK',
                           detail = 'Held for a student not yet on the register; dropped when the upload was rolled back'
                                    || CASE WHEN m.j IS NOT NULL
                                            THEN '; the result ' || coalesce((SELECT pu.ref FROM assessment.past_upload pu WHERE pu.id = (m.j->>'upload_id')::uuid), 'an earlier upload')
                                                 || ' held before it is held again' ELSE '' END
                      FROM mine m
                     WHERE pr.upload_id = p_upload AND pr.status = 'HELD' AND pr.session = m.session AND pr.semester = m.semester AND pr.matric = m.matric
                       AND (pr.course = m.course_code OR (pr.line IS NOT NULL AND pr.line = m.line))
                    RETURNING 1),
         -- a hold really dropped also closes the rows of earlier holders already rolled back: none of them may still promise a posting
         others AS (UPDATE assessment.past_upload_row pr SET status = 'HELD_ROLLED_BACK',
                           detail = 'Held for a student not yet on the register; dropped when ' || u.ref || ' was rolled back'
                      FROM mine m, assessment.past_upload pu
                     WHERE pu.id = pr.upload_id AND pu.state = 'REVERTED' AND pu.id <> p_upload AND pr.status = 'HELD'
                       AND pr.session = m.session AND pr.semester = m.semester AND pr.matric = m.matric AND pr.course = m.course_code
                    RETURNING 1)
    SELECT count(*) INTO n_held FROM mine;

    v_started := clock_timestamp();
    PERFORM set_config('moaum.upload_rollback', 'on', true);   -- the changes are undone only from here
    -- its own ledger, newest change first; the class headings after the courses, since a heading follows what its students carry
    FOR k IN SELECT ch.id FROM assessment.past_upload_change ch WHERE ch.upload_id = p_upload AND ch.reverted_at IS NULL
              ORDER BY (ch.kind = 'CLASS_HEADER_CORRECTED'), ch.seq DESC LOOP
        PERFORM assessment.revert_change(k.id, p_reason, p_upload, NULL);
    END LOOP;
    -- then what this rollback has freed: a change a rollback had to leave (an earlier rolled-back upload's, or this one's) is tried
    -- again only when a LATER change on the very same thing was undone just now, or was this upload's first result on that course —
    -- never because the record happens to read the same again. Repeated until a round undoes nothing, so uploads rolled back in any
    -- order end the same
    LOOP
        n_round := 0;
        FOR k IN
            SELECT c.id, c.upload_id, pu.revert_reason
              FROM assessment.past_upload_change c JOIN assessment.past_upload pu ON pu.id = c.upload_id
             WHERE c.reverted_at IS NULL AND c.kind <> 'RESULT_POSTED' AND (pu.state = 'REVERTED' OR pu.id = p_upload)
               AND CASE c.kind
                     WHEN 'CLASS_HEADER_CORRECTED' THEN EXISTS (SELECT 1 FROM assessment.past_upload_change f
                                                                  WHERE f.offering_id = c.offering_id AND f.reverted_at >= v_started
                                                                    AND ((f.kind = 'CLASS_HEADER_CORRECTED' AND f.seq > c.seq)
                                                                         OR f.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED', 'UNITS_CORRECTED',
                                                                                       'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')))
                     WHEN 'REGISTRATION_ADDED' THEN EXISTS (SELECT 1 FROM assessment.past_upload_change f
                                                              WHERE f.kind = 'ENTRY_ADDED' AND f.registration_id = c.registration_id
                                                                AND f.reverted_at >= v_started)
                     WHEN 'ENROLMENT_ADDED' THEN EXISTS (SELECT 1 FROM assessment.past_upload_change f
                                                           WHERE f.kind = 'REGISTRATION_ADDED' AND f.student_id = c.student_id AND f.session = c.session
                                                             AND f.reverted_at >= v_started)
                     ELSE EXISTS (SELECT 1 FROM assessment.past_upload_change f
                                   WHERE f.registration_id = c.registration_id AND f.offering_id = c.offering_id AND f.seq > c.seq
                                     AND (f.reverted_at >= v_started OR (f.upload_id = p_upload AND f.kind = 'RESULT_POSTED')))
                   END
             ORDER BY (c.kind = 'CLASS_HEADER_CORRECTED'), c.seq DESC
        LOOP
            IF assessment.revert_change(k.id, CASE WHEN k.upload_id = p_upload THEN p_reason ELSE k.revert_reason END, p_upload,
                                        CASE WHEN k.upload_id = p_upload THEN NULL ELSE u.ref END) THEN
                n_round := n_round + 1;
            END IF;
        END LOOP;
        EXIT WHEN n_round = 0;
    END LOOP;
    PERFORM set_config('moaum.upload_rollback', '', true);

    -- an issued transcript that showed a course taken off (or dropped again) is flagged for review, once a student
    PERFORM credentials.flag_documents(z.student_id, ARRAY['TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT'],
                                       'A course an old-portal upload put on the record was taken off when ' || u.ref || ' was rolled back')
       FROM (SELECT DISTINCT ch.student_id FROM assessment.past_upload_change ch
              WHERE ch.reverted_at >= v_started AND ch.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') AND ch.student_id IS NOT NULL
                AND catalogue.class_examined(ch.offering_id)) z;
    -- the cached academic position: nothing refreshes it when a registration or an enrolment is deleted
    PERFORM people.refresh_academic_positions(ARRAY(SELECT DISTINCT ch.student_id FROM assessment.past_upload_change ch
                                                     WHERE ch.reverted_at >= v_started AND ch.kind IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED')
                                                       AND ch.student_id IS NOT NULL))
     WHERE EXISTS (SELECT 1 FROM assessment.past_upload_change ch
                    WHERE ch.reverted_at >= v_started AND ch.kind IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') AND ch.student_id IS NOT NULL);
    -- every answer is read from the ledger: this upload's, and each earlier rolled-back upload a change of which was undone just now
    UPDATE assessment.past_upload pu
       SET revert_counts = coalesce(pu.revert_counts, '{}'::jsonb)
                           || (SELECT jsonb_build_object('undone', count(*) FILTER (WHERE ch.reverted_at IS NOT NULL),
                                                         'left', count(*) FILTER (WHERE ch.reverted_at IS NULL))
                                 FROM assessment.past_upload_change ch WHERE ch.upload_id = pu.id)
     WHERE pu.id <> p_upload AND pu.state = 'REVERTED'
       AND EXISTS (SELECT 1 FROM assessment.past_upload_change ch WHERE ch.upload_id = pu.id AND ch.reverted_at >= v_started);
    SELECT jsonb_build_object('undone', count(*) FILTER (WHERE ch.upload_id = p_upload AND ch.reverted_at IS NOT NULL),
                              'left', count(*) FILTER (WHERE ch.upload_id = p_upload AND ch.reverted_at IS NULL),
                              'heldDropped', n_held,
                              'earlierUndone', count(*) FILTER (WHERE ch.upload_id <> p_upload AND ch.reverted_at >= v_started))
      INTO v_counts
      FROM assessment.past_upload_change ch
     WHERE ch.upload_id = p_upload OR ch.reverted_at >= v_started;
    SELECT coalesce(jsonb_agg(jsonb_build_object('kind', ch.kind, 'courseCode', ch.course_code, 'session', ch.session, 'semester', ch.semester,
                                                 'matric', (SELECT s.matric_no FROM people.student s WHERE s.id = ch.student_id), 'note', ch.revert_note)
                              ORDER BY ch.seq DESC), '[]'::jsonb)
      INTO v_left
      FROM assessment.past_upload_change ch WHERE ch.upload_id = p_upload AND ch.reverted_at IS NULL;
    UPDATE assessment.past_upload SET state = 'REVERTED', reverted_at = now(), reverted_by = v_actor, reverted_office = v_office,
           revert_reason = btrim(p_reason), revert_counts = v_counts
     WHERE id = p_upload;
    RETURN jsonb_build_object('ref', u.ref, 'state', 'REVERTED') || v_counts || jsonb_build_object('leftChanges', v_left);
END $$;
COMMENT ON FUNCTION assessment.revert_past_upload(uuid, text) IS
  'V771: a confirmed upload rolled back from its ledger, newest change first. Each change is undone only where it is still the last word on what it changed (assessment.revert_change): an entry it added is deleted (a mark posted on it stays on its sheet as history), one it approved again goes back as it was, a correction is put back, a replaced result is restored as a new version, a class header is put back, the registration and session enrolment it made go when nothing is left on them and nothing has been done to them, the cached academic position refreshed. A later change of another upload that still stands, a result amendment, a mark entered on the portal, the Senate''s units, a Course Registration Correction or a registration acted on leaves the change as it is, listed with why. A first result on a course already on record is listed for Result amendments — unless the course is itself an upload''s and that upload is rolled back too: then the result goes with the course. What an earlier rollback had to leave because of this upload is settled now (earlierUndone) — only what this rollback freed, never an unrelated change — so uploads rolled back in any order end the same. Held results go back to the nearest earlier upload still standing that held them, or are dropped (heldDropped). Issued transcripts are flagged. Refusals LEGACY_REVERT_OFFICE, LEGACY_UPLOAD_REASON, LEGACY_UPLOAD_STATE.';

COMMENT ON FUNCTION assessment.past_upload_finish(uuid, boolean) IS
  'V771: an upload is closed COMPLETE (every batch loaded) or INCOMPLETE (stopped part way; what loaded stands and is in its ledger), its counts taken from its ledger.';

-- ── the readers: the course as taken ────────────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION assessment.student_results(uuid);
CREATE FUNCTION assessment.student_results(p_student uuid)
 RETURNS TABLE(session text, semester integer, course_code text, title text, units integer, entry_type text, stage text, published boolean, published_at timestamp with time zone, senate_minute text, ca integer, exam integer, total integer, grade text, points numeric, outcome text, lecturer text, code_as_taken text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.session, r.semester, c.code, coalesce(at.title, o.title, c.title), e.units, e.entry_type,
           -- V421: a published sheet the student is not on (no outcome for them) is no result — never an absence
           CASE WHEN cf.stage = 'PUBLISHED' AND cf.outcome IS NULL THEN 'NO_RESULT' ELSE coalesce(cf.stage, 'NO_SHEET') END,
           coalesce(cf.stage = 'PUBLISHED' AND cf.outcome IS NOT NULL, false),
           CASE WHEN cf.outcome IS NOT NULL THEN cf.published_at END, CASE WHEN cf.outcome IS NOT NULL THEN cf.senate_minute END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.ca END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.exam END,
           CASE WHEN cf.stage = 'PUBLISHED' AND cf.outcome = 'GRADED' THEN cf.total END,
           -- a recorded absence is an F: the candidate did not sit
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome = 'GRADED' THEN cf.grade WHEN cf.outcome = 'ABSENT' THEN 'F' END END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN CASE WHEN cf.outcome = 'GRADED' THEN cf.points WHEN cf.outcome = 'ABSENT' THEN 0::numeric END END,
           CASE WHEN cf.stage = 'PUBLISHED' THEN cf.outcome END,
           CASE WHEN lp.id IS NULL THEN NULL ELSE lp.surname || ', ' || lp.given_names END,
           at.code_as_taken
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN catalogue.course_as_taken at ON at.id = e.as_taken_id
      LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
      LEFT JOIN LATERAL assessment.course_final(p_student, o.id) cf ON true
     WHERE r.student_id = p_student AND r.status IN ('APPROVED','LOCKED')
     ORDER BY r.session, r.semester, c.code;
$function$;
COMMENT ON FUNCTION assessment.student_results(uuid) IS
  'V243, V421, V771: the student''s courses and their final results — published only where the published sheet has an outcome for them; a recorded absence is F; no outcome on a published sheet is NO_RESULT (no grade, no points), never a failure. V771: the title as taken and code_as_taken (the code as the file wrote it; NULL where no file stated it) — course_code stays the catalogue key that carry-overs and electives join on.';

DROP FUNCTION assessment.result_records(text, integer, text, text, text, integer, text);
CREATE FUNCTION assessment.result_records(p_session text, p_sem integer, p_fac text, p_dept text, p_prog text, p_level integer, p_course text)
 RETURNS TABLE(registration_id uuid, student_id uuid, number text, jamb_reg_no text, surname text, other_names text, programme_code text, dept_code text, faculty_code text, level integer, offering_id uuid, course_code text, course_title text, units integer, course_level integer, course_semester integer, both_semesters boolean, entry_type text, basis text, stream text, sheet_id uuid, stage text, has_score boolean, lecturer_id uuid, code_as_taken text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.id, st.id, coalesce(st.matric_no, st.admission_no), st.jamb_reg_no, st.surname, st.other_names, st.programme_code, p.dept_code, p.faculty_code, r.level,
           o.id, o.course_code, coalesce(at.title, o.title, c.title), e.units, c.level, c.semester, c.both_semesters, e.entry_type, e.basis, o.stream,
           ms.id, coalesce(ms.stage, 'NO_SHEET'),
           ms.id IS NOT NULL AND EXISTS (SELECT 1 FROM assessment.score sc WHERE sc.sheet_id = ms.id AND sc.student_id = st.id),
           o.lecturer_id, at.code_as_taken
      FROM registration.course_registration r
      JOIN people.student st ON st.id = r.student_id
      JOIN ref.programme p ON p.code = st.programme_code
      JOIN registration.entry e ON e.registration_id = r.id AND e.status = 'APPROVED'
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code
      LEFT JOIN catalogue.course_as_taken at ON at.id = e.as_taken_id
      -- the main sitting's sheet (a special or re-sit is read by assessment.course_final when the result is shown)
      LEFT JOIN LATERAL (SELECT sh.id, sh.stage FROM assessment.score_sheet sh LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                          WHERE sh.offering_id = o.id ORDER BY (coalesce(es.kind, 'MAIN') = 'MAIN') DESC, sh.id LIMIT 1) ms ON true
     WHERE r.session = p_session AND r.semester = p_sem AND r.status IN ('APPROVED', 'LOCKED')
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR st.programme_code = p_prog)
       AND (p_level IS NULL OR r.level = p_level) AND (p_course IS NULL OR o.course_code = p_course)
$function$;
COMMENT ON FUNCTION assessment.result_records(text, integer, text, text, text, integer, text) IS
  'V700, V771: every course on an approved registration of a session''s semester in scope — the rows the broadsheet is made of — with the main sitting''s sheet, its stage (NO_SHEET when there is none) and whether the student has a mark on it. V771: the title as taken and code_as_taken.';

-- the transcript prints the code as taken
DO $$
DECLARE d text; f text := 'credentials.build_statement(uuid,text,text,integer)'; n int;
    a text := 'jsonb_build_object(''code'', x.course_code, ''title'', x.title,';
    b text := 'jsonb_build_object(''code'', coalesce(x.code_as_taken, x.course_code), ''title'', x.title,';
BEGIN
    d := pg_get_functiondef(f::regprocedure);
    n := (length(d) - length(replace(d, a, ''))) / length(a);
    IF n <> 1 THEN RAISE EXCEPTION 'V771: % is not as it was left (the course line found % times)', f, n; END IF;
    EXECUTE replace(d, a, b);
END $$;

-- a Senate units amendment marks the versions it moves entries to
DO $$
DECLARE d text; f text := 'assessment.advance_amendment(uuid,text,text)'; n int; i int;
    edits text[][] := ARRAY[
        ARRAY['        IF m.kind = ''UNITS'' THEN
            UPDATE registration.entry e SET units = m.units',
              '        IF m.kind = ''UNITS'' THEN
            PERFORM set_config(''moaum.units_source'', ''AMENDMENT:'' || m.ref, true);   -- V771: a course as taken follows, marked the Senate''s
            UPDATE registration.entry e SET units = m.units'],
        ARRAY['            GET DIAGNOSTICS v_count = ROW_COUNT;',
              '            GET DIAGNOSTICS v_count = ROW_COUNT;
            PERFORM set_config(''moaum.units_source'', '''', true);']];
BEGIN
    d := pg_get_functiondef(f::regprocedure);
    FOR i IN 1 .. array_length(edits, 1) LOOP
        n := (length(d) - length(replace(d, edits[i][1], ''))) / length(edits[i][1]);
        IF n <> 1 THEN RAISE EXCEPTION 'V771: % is not as it was left (% found % times)', f, left(edits[i][1], 50), n; END IF;
        d := replace(d, edits[i][1], edits[i][2]);
    END LOOP;
    EXECUTE d;
END $$;

-- the Course Registration Report (and its export) shows each past course as taken
DO $$
DECLARE d text; f text := 'reporting.course_registration_rows(text,integer,jsonb)'; n int; i int;
    edits text[][] := ARRAY[
        ARRAY['catalogue.shown_code(c.code) AS shown_code, c.title AS course_title',
              'catalogue.shown_code(coalesce(at.code_as_taken, c.code)) AS shown_code, coalesce(at.title, o.title, c.title) AS course_title'],
        ARRAY['JOIN catalogue.course c ON c.code = o.course_code',
              'JOIN catalogue.course c ON c.code = o.course_code
          LEFT JOIN catalogue.course_as_taken at ON at.id = e.as_taken_id   -- V771: the course as taken'],
        ARRAY['AND (f.course IS NULL OR c.code = upper(f.course) OR catalogue.shown_code(c.code) = upper(f.course))',
              'AND (f.course IS NULL OR c.code = upper(f.course) OR catalogue.shown_code(c.code) = upper(f.course)
                OR at.code_as_taken = upper(f.course) OR catalogue.shown_code(at.code_as_taken) = upper(f.course))   -- V771: the code as taken'],
        ARRAY['OR x.course_code ILIKE ''%'' || f.q || ''%'' OR x.course_title ILIKE',
              'OR x.course_code ILIKE ''%'' || f.q || ''%'' OR x.shown_code ILIKE ''%'' || f.q || ''%'' OR x.course_title ILIKE']];
BEGIN
    d := pg_get_functiondef(f::regprocedure);
    FOR i IN 1 .. array_length(edits, 1) LOOP
        n := (length(d) - length(replace(d, edits[i][1], ''))) / length(edits[i][1]);
        IF n <> 1 THEN RAISE EXCEPTION 'V771: % is not as it was left (% found % times)', f, left(edits[i][1], 50), n; END IF;
        d := replace(d, edits[i][1], edits[i][2]);
    END LOOP;
    EXECUTE d;
END $$;

-- a past attempt shows the code it was taken under; the course still owed reads as the catalogue offers it now
DO $$
DECLARE h text;
BEGIN
    SELECT md5(replace(p.prosrc, E'\r', '')) INTO h FROM pg_proc p WHERE p.oid = to_regprocedure('registration.carryover_history(uuid)');
    IF h IS DISTINCT FROM '34d38c4f17a4e834e497c16c2ef2831b' THEN RAISE EXCEPTION 'V771: registration.carryover_history(uuid) is not as it was left'; END IF;
    SELECT md5(replace(p.prosrc, E'\r', '')) INTO h FROM pg_proc p WHERE p.oid = to_regprocedure('registration.carryover_attempts(uuid)');
    IF h IS DISTINCT FROM '5425c15245fcd5bf9733c7265b78497f' THEN RAISE EXCEPTION 'V771: registration.carryover_attempts(uuid) is not as it was left'; END IF;
END $$;
DROP FUNCTION registration.carryover_history(uuid);
CREATE FUNCTION registration.carryover_history(p_student uuid)
 RETURNS TABLE(course_code text, title text, session text, semester integer, grade text, result text, owed boolean, code_as_taken text, course_title text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH r AS MATERIALIZED (SELECT * FROM assessment.student_results(p_student)),
    -- the courses failed on a published result at least once
    failed AS (SELECT DISTINCT x.course_code FROM r x WHERE x.published AND x.outcome IN ('GRADED', 'ABSENT') AND x.points = 0),
    owed AS (SELECT DISTINCT a.course_code FROM registration.carryover_attempts(p_student) a)
    SELECT x.course_code, x.title, x.session, x.semester, x.grade,
           CASE WHEN x.published AND x.outcome = 'GRADED' AND x.points > 0 THEN 'PASSED'
                WHEN x.published THEN 'FAILED'
                WHEN x.stage = 'NO_SHEET' THEN 'REGISTERED'
                WHEN x.stage = 'NO_RESULT' THEN 'NO_RESULT'
                ELSE 'AWAITED' END,
           x.course_code IN (SELECT o.course_code FROM owed o),
           x.code_as_taken,
           coalesce(cc.title, x.title)   -- the course as the catalogue holds it now: the heading its attempts sit under
      FROM r x
      LEFT JOIN catalogue.course cc ON cc.code = x.course_code
     WHERE x.course_code IN (SELECT f.course_code FROM failed f)
     ORDER BY x.course_code, x.session, x.semester;
$function$;
COMMENT ON FUNCTION registration.carryover_history(uuid) IS
  'V666: every attempt of each course a student has failed on a published result — PASSED, FAILED, AWAITED (a sheet on its way), NO_RESULT (a published sheet without them), REGISTERED (no sheet yet) — and whether the course is owed now. The history behind registration.carryovers; nothing is removed from it. V771: each attempt''s title as taken and code_as_taken (the code it was taken under); course_code stays the catalogue key and course_title is the course as the catalogue holds it now (the heading).';

CREATE OR REPLACE FUNCTION registration.carryover_attempts(p_student uuid)
 RETURNS TABLE(course_code text, title text, units integer, failed_in text, session text, semester integer)
 LANGUAGE sql
 STABLE
AS $function$
    -- the student's published results, read once
    WITH r AS MATERIALIZED (
        SELECT x.session, x.semester, x.course_code, x.title, x.units, x.outcome, x.points
          FROM assessment.student_results(p_student) x WHERE x.published)
    -- V771: the course owed reads as the catalogue offers it now (it is registered again as it is now); the attempt kept its own title
    SELECT f.course_code, coalesce(cc.title, f.title), f.units, f.session || ' semester ' || f.semester, f.session, f.semester
      FROM r f
      LEFT JOIN catalogue.course cc ON cc.code = f.course_code
     -- V422: a recorded absence is an F and owed, as a graded F is
     WHERE f.outcome IN ('GRADED', 'ABSENT') AND f.points = 0
       AND NOT registration.is_elective_for(p_student, f.course_code)
       AND NOT EXISTS (SELECT 1 FROM r g
                        WHERE g.course_code = f.course_code AND g.outcome = 'GRADED' AND g.points > 0
                          AND (g.session, g.semester) > (f.session, f.semester))
     ORDER BY f.course_code, f.session, f.semester;
$function$;

-- ── units that move with the catalogue leave history alone ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.reflect_units(p_course text, p_programme text, p_level integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
    UPDATE registration.entry e
       SET units = catalogue.units_for(o.course_code, s.programme_code, r.level)
      FROM registration.course_registration r, people.student s, catalogue.offering o
     WHERE e.registration_id = r.id AND r.student_id = s.id AND e.offering_id = o.id
       AND o.course_code = p_course
       AND (p_programme IS NULL OR s.programme_code = p_programme)
       AND (p_level IS NULL OR r.level = p_level)
       AND e.units IS DISTINCT FROM catalogue.units_for(o.course_code, s.programme_code, r.level)
       AND e.as_taken_id IS NULL   -- V771: a course as taken keeps its units
       AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state IN ('CLOSED', 'ARCHIVED', 'CANCELLED'))
       AND NOT catalogue.class_examined(o.id);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION catalogue.units_change_rows(p_course text, p_programme text, p_level integer, p_units integer)
 RETURNS TABLE(registration_id uuid, offering_id uuid, old_units integer, to_units integer, held boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH c AS (SELECT x.units FROM catalogue.course x WHERE x.code = p_course),
    b AS (SELECT co.level,
                 CASE WHEN co.level = p_level THEN nullif(p_units, (SELECT c.units FROM c)) ELSE co.units END AS units
            FROM catalogue.course_offer co WHERE co.course_code = p_course AND co.programme_code = p_programme),
    any_own AS (SELECT b.units FROM b WHERE b.units IS NOT NULL ORDER BY b.level LIMIT 1)
    SELECT e.registration_id, o.id, e.units,
           coalesce((SELECT b.units FROM b WHERE b.level = r.level),
                    CASE WHEN NOT EXISTS (SELECT 1 FROM b WHERE b.level = r.level) THEN (SELECT a.units FROM any_own a) END,
                    (SELECT c.units FROM c)),
           (e.as_taken_id IS NOT NULL   -- V771
            OR EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state IN ('CLOSED', 'ARCHIVED', 'CANCELLED'))
            OR catalogue.class_examined(o.id))
      FROM registration.entry e
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN people.student s ON s.id = r.student_id
      JOIN catalogue.offering o ON o.id = e.offering_id
     WHERE o.course_code = p_course AND s.programme_code = p_programme
$function$;

CREATE OR REPLACE FUNCTION catalogue.course_units_change_rows(p_course text, p_units integer)
 RETURNS TABLE(registration_id uuid, offering_id uuid, programme_code text, old_units integer, to_units integer, held boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH c AS (SELECT x.units FROM catalogue.course x WHERE x.code = p_course),
    pin AS (SELECT x.programme_code, x.level FROM catalogue.units_pinned_by_course(p_course) x WHERE p_units IS DISTINCT FROM (SELECT c.units FROM c)),
    b AS (SELECT co.programme_code, co.level,
                 CASE WHEN co.units IS NULL AND EXISTS (SELECT 1 FROM pin WHERE pin.programme_code = co.programme_code AND pin.level = co.level)
                      THEN (SELECT c.units FROM c) ELSE co.units END AS units
            FROM catalogue.course_offer co WHERE co.course_code = p_course)
    SELECT e.registration_id, o.id, s.programme_code, e.units,
           coalesce((SELECT b.units FROM b WHERE b.programme_code = s.programme_code AND b.level = r.level),
                    CASE WHEN NOT EXISTS (SELECT 1 FROM b WHERE b.programme_code = s.programme_code AND b.level = r.level)
                         THEN (SELECT b.units FROM b WHERE b.programme_code = s.programme_code AND b.units IS NOT NULL ORDER BY b.level LIMIT 1) END,
                    p_units),
           (e.as_taken_id IS NOT NULL   -- V771
            OR EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state IN ('CLOSED', 'ARCHIVED', 'CANCELLED'))
            OR catalogue.class_examined(o.id))
      FROM registration.entry e
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN people.student s ON s.id = r.student_id
      JOIN catalogue.offering o ON o.id = e.offering_id
     WHERE o.course_code = p_course
$function$;

-- ── an issued transcript is flagged when a course's printed code or title changes, as when its units do ─────────────────────────
CREATE OR REPLACE FUNCTION credentials.entry_units_changed()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE v_student uuid; v_old text; v_new text;
BEGIN
    IF OLD.units IS NOT DISTINCT FROM NEW.units THEN
        -- V771: only the course as taken changed: flag only when the printed code or title differs
        SELECT upper(coalesce(a.code_as_taken, o.course_code)) || '|' || coalesce(a.title, o.title, c.title) INTO v_old
          FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
          LEFT JOIN catalogue.course_as_taken a ON a.id = OLD.as_taken_id WHERE o.id = OLD.offering_id;
        SELECT upper(coalesce(a.code_as_taken, o.course_code)) || '|' || coalesce(a.title, o.title, c.title) INTO v_new
          FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code
          LEFT JOIN catalogue.course_as_taken a ON a.id = NEW.as_taken_id WHERE o.id = NEW.offering_id;
        IF v_old IS NOT DISTINCT FROM v_new THEN RETURN NEW; END IF;
    END IF;
    SELECT r.student_id INTO v_student FROM registration.course_registration r WHERE r.id = NEW.registration_id;
    IF EXISTS (SELECT 1 FROM credentials.issued i WHERE i.student_id = v_student
                  AND i.kind IN ('TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT') AND i.flagged_at IS NULL)
       AND catalogue.class_examined(NEW.offering_id) THEN
        PERFORM credentials.flag_documents(v_student, ARRAY['TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT'],
                                           CASE WHEN OLD.units IS DISTINCT FROM NEW.units
                                                THEN 'The units of a course on the student''s record changed after issue'
                                                ELSE 'The code or title of a course on the student''s record changed after issue' END);
    END IF;
    RETURN NEW;
END $function$;
DROP TRIGGER trg_entry_units_flag_documents ON registration.entry;
CREATE TRIGGER trg_entry_units_flag_documents AFTER UPDATE OF units, as_taken_id ON registration.entry
    FOR EACH ROW WHEN (OLD.units IS DISTINCT FROM NEW.units OR OLD.as_taken_id IS DISTINCT FROM NEW.as_taken_id)
    EXECUTE FUNCTION credentials.entry_units_changed();

-- ── who reads ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE rl text;
BEGIN
    FOREACH rl IN ARRAY ARRAY['app_auditor', 'app_acrecords', 'app_reporting', 'app_registration'] LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = rl) THEN
            EXECUTE format('GRANT SELECT ON catalogue.course_as_taken, assessment.past_upload, assessment.past_upload_change, assessment.past_upload_student, assessment.past_upload_row TO %I', rl);
        END IF;
    END LOOP;
END $$;

COMMIT;

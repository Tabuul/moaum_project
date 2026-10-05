-- V332 · One course, offered to many programmes across departments
--
-- The catalogue already holds the model the University needs: catalogue.course is the one record of a course (its
-- code is the key the whole portal references) owned by one department, and catalogue.course_offer is the
-- relationship that offers it to a programme at a level on a basis (Core, Elective, Borrowed, GST), for a track or
-- every track. Registration, results, allocation, GST/EPS and CBT all read that one course; a programme of another
-- department carries it as Borrowed. What was missing is the course-side workflow and its safeguards:
--
--     · a course has a stable identity beside its code (catalogue.course.id), and a code renamed follows into every
--       table that references it, so an edit never makes a second course;
--     · a binding records who made it and from where, and a binding that ends is kept on the record
--       (catalogue.course_offer_history) with how many registrations it carried — it is never silently lost;
--     · a course offered to a programme of another department waits for that department: an offer proposal
--       (PENDING → APPROVED / REJECTED / CANCELLED) decided by the programme's Head, its Dean or the Academic Office;
--       the course's owner is not changed by another department offering it;
--     · the course upload binds an existing code owned by another department without rewriting that course's title,
--       units or level — one CSC 201 across three structures stays one course;
--     · a co-lecturer of an offering may be posted to one programme's group of it.
--
-- Nothing here changes course_offer's key, so every reader of the structure is as it was.

-- ── 1 · a stable identity beside the code; a renamed code follows everywhere ─────────────────────────────────────
ALTER TABLE catalogue.course ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();
CREATE UNIQUE INDEX IF NOT EXISTS ux_course_id ON catalogue.course (id);
COMMENT ON COLUMN catalogue.course.id IS 'V332: the course''s identity, unchanged by an edit of its code, title or units; the code stays the key the portal references.';

ALTER TABLE catalogue.course_offer DROP CONSTRAINT IF EXISTS course_offer_course_code_fkey;
ALTER TABLE catalogue.course_offer ADD CONSTRAINT course_offer_course_code_fkey FOREIGN KEY (course_code) REFERENCES catalogue.course(code) ON UPDATE CASCADE;
ALTER TABLE catalogue.offering DROP CONSTRAINT IF EXISTS offering_course_code_fkey;
ALTER TABLE catalogue.offering ADD CONSTRAINT offering_course_code_fkey FOREIGN KEY (course_code) REFERENCES catalogue.course(code) ON UPDATE CASCADE;
ALTER TABLE assessment.question DROP CONSTRAINT IF EXISTS question_course_code_fkey;
ALTER TABLE assessment.question ADD CONSTRAINT question_course_code_fkey FOREIGN KEY (course_code) REFERENCES catalogue.course(code) ON UPDATE CASCADE;
ALTER TABLE extexam.project DROP CONSTRAINT IF EXISTS project_course_code_fkey;
ALTER TABLE extexam.project ADD CONSTRAINT project_course_code_fkey FOREIGN KEY (course_code) REFERENCES catalogue.course(code) ON UPDATE CASCADE;
ALTER TABLE people.deferred_course DROP CONSTRAINT IF EXISTS deferred_course_course_code_fkey;
ALTER TABLE people.deferred_course ADD CONSTRAINT deferred_course_course_code_fkey FOREIGN KEY (course_code) REFERENCES catalogue.course(code) ON UPDATE CASCADE;
ALTER TABLE assessment.cbt_exam DROP CONSTRAINT IF EXISTS cbt_exam_course_code_fkey;
ALTER TABLE assessment.cbt_exam ADD CONSTRAINT cbt_exam_course_code_fkey FOREIGN KEY (course_code) REFERENCES catalogue.course(code) ON UPDATE CASCADE;

-- ── 2 · a binding says who made it and from where; one that ends stays on the record ─────────────────────────────
ALTER TABLE catalogue.course_offer
    ADD COLUMN IF NOT EXISTS added_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS added_by uuid NULL,
    ADD COLUMN IF NOT EXISTS source   text NULL;
COMMENT ON COLUMN catalogue.course_offer.source IS 'V332: how the binding came to be — COURSE (the course''s desk), STRUCTURE (the programme''s desk), IMPORT (a structure upload), PROPOSAL (another department''s offer, approved), GST (the GST/EPS office).';

CREATE TABLE catalogue.course_offer_history (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_code            text NOT NULL REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    programme_code         text NOT NULL REFERENCES ref.programme(code) ON DELETE CASCADE,
    level                  int NOT NULL,
    basis                  text NULL,
    track                  text NULL,
    added_at               timestamptz NULL,
    added_by               uuid NULL,
    source                 text NULL,
    ended_at               timestamptz NOT NULL DEFAULT now(),
    ended_by               uuid NULL,
    ended_office           text NULL,
    reason                 text NULL,
    registrations_carried  bigint NOT NULL DEFAULT 0
);
CREATE INDEX ix_offer_history_course ON catalogue.course_offer_history (course_code, ended_at DESC);
COMMENT ON TABLE catalogue.course_offer_history IS 'V332: every binding of a course into a programme that was ended — when, by whom, why, and how many registrations it had carried. The registrations, results and transcripts themselves hang on the offerings and stay where they are.';
SELECT audit.attach('catalogue.course_offer_history');

-- ── 3 · a course offered to another department's programme waits for that department ────────────────────────────
CREATE TABLE catalogue.offer_proposal (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_code      text NOT NULL REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    programme_code   text NOT NULL REFERENCES ref.programme(code) ON DELETE CASCADE,
    level            int NOT NULL CHECK (level BETWEEN 100 AND 900),
    basis            text NOT NULL DEFAULT 'Borrowed' CHECK (basis IN ('Core','Elective','Borrowed','GST')),
    track            text NULL REFERENCES policy.curriculum_track(code),
    reason           text NULL,
    proposed_by      uuid NULL,
    proposed_office  text NULL,
    proposed_dept    text NULL,
    proposed_at      timestamptz NOT NULL DEFAULT now(),
    state            text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING','APPROVED','REJECTED','CANCELLED')),
    decided_by       uuid NULL,
    decided_office   text NULL,
    decided_at       timestamptz NULL,
    decision_note    text NULL
);
CREATE UNIQUE INDEX ux_offer_proposal_pending ON catalogue.offer_proposal (course_code, programme_code, level) WHERE state = 'PENDING';
CREATE INDEX ix_offer_proposal_programme ON catalogue.offer_proposal (programme_code, state);
CREATE INDEX ix_offer_proposal_course ON catalogue.offer_proposal (course_code, state);
COMMENT ON TABLE catalogue.offer_proposal IS 'V332: a proposal that a programme offer a course it does not yet — made from the course''s desk, decided by the programme''s department (its Head), its faculty (the Dean) or the Academic Office; approved, it becomes a catalogue.course_offer with source PROPOSAL.';
SELECT audit.attach('catalogue.offer_proposal');

-- ── 4 · a co-lecturer may teach one programme's group of the offering ───────────────────────────────────────────
ALTER TABLE catalogue.offering_teacher ADD COLUMN IF NOT EXISTS programme_code text NULL REFERENCES ref.programme(code);
COMMENT ON COLUMN catalogue.offering_teacher.programme_code IS 'V332: the programme whose students this co-lecturer teaches on the offering (CSC 201 to the Software Engineering group), or NULL for every programme. The score sheet is the offering''s; the group is who they teach.';

-- ── 5 · what carries a course: the counts an edit or a removal is warned with ────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.course_usage(p_code text)
RETURNS TABLE (registrations bigint, scores bigint, offerings bigint, cbt_exams bigint, questions bigint, deferred bigint, legacy bigint)
LANGUAGE sql STABLE AS $$
    SELECT (SELECT count(*) FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id WHERE o.course_code = p_code),
           (SELECT count(*) FROM assessment.score s JOIN assessment.score_sheet sh ON sh.id = s.sheet_id JOIN catalogue.offering o ON o.id = sh.offering_id WHERE o.course_code = p_code),
           (SELECT count(*) FROM catalogue.offering o WHERE o.course_code = p_code),
           (SELECT count(*) FROM assessment.cbt_exam x WHERE x.course_code = p_code),
           (SELECT count(*) FROM assessment.question q WHERE q.course_code = p_code),
           (SELECT count(*) FROM people.deferred_course d WHERE d.course_code = p_code),
           (SELECT count(*) FROM assessment.legacy_result_holding l WHERE l.course_code = p_code)
$$;
COMMENT ON FUNCTION catalogue.course_usage(text) IS 'V332: how much hangs on a course — registrations, scores, offerings, CBT examinations, questions, deferred courses, old-portal results — so an edit of its code, units, level or semester is made knowing it.';

-- ── 6 · binding a course into a programme, and ending the binding, as the one road every desk takes ────────────
CREATE OR REPLACE FUNCTION catalogue.assert_offerable(p_course text, p_programme text, p_level int, p_basis text, p_track text)
RETURNS void
LANGUAGE plpgsql STABLE AS $$
DECLARE c catalogue.course; p ref.programme;
BEGIN
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_course, '')));
    IF c.code IS NULL THEN RAISE EXCEPTION 'no course is coded %', p_course USING ERRCODE = '23503'; END IF;
    IF c.state = 'ENDED' THEN
        RAISE EXCEPTION 'CAT_ENDED: % has ended; an ended course is not offered to a programme', c.code USING ERRCODE = '23514',
            HINT = 'Restore the course on its department''s desk first.';
    END IF;
    SELECT * INTO p FROM ref.programme WHERE code = upper(btrim(coalesce(p_programme, '')));
    IF p.code IS NULL THEN RAISE EXCEPTION 'no programme is coded %', p_programme USING ERRCODE = '23503'; END IF;
    IF coalesce(p.archived, false) THEN
        RAISE EXCEPTION 'CAT_PROGRAMME_ARCHIVED: % is archived; a course is not offered to it', p.code USING ERRCODE = '23514';
    END IF;
    IF p.dept_code IS NULL OR NOT EXISTS (SELECT 1 FROM ref.department d WHERE d.code = p.dept_code AND d.ended_on IS NULL) THEN
        RAISE EXCEPTION 'CAT_DEPT_ENDED: the department of % is not live on the register', p.code USING ERRCODE = '23514';
    END IF;
    IF coalesce(nullif(btrim(p_basis), ''), 'Core') NOT IN ('Core', 'Elective', 'Borrowed', 'GST') THEN
        RAISE EXCEPTION 'CAT_BASIS: a course is offered to a programme as Core, Elective, Borrowed or GST' USING ERRCODE = '23514';
    END IF;
    IF p_level IS NULL OR p_level NOT BETWEEN 100 AND 900 OR p_level % 100 <> 0 THEN
        RAISE EXCEPTION 'CAT_LEVEL: a course is offered at a level from 100 to 900' USING ERRCODE = '23514';
    END IF;
    IF nullif(upper(btrim(coalesce(p_track, ''))), '') IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM policy.curriculum_track t WHERE t.code = upper(btrim(p_track))) THEN
        RAISE EXCEPTION 'CAT_TRACK: no curriculum track is coded %', p_track USING ERRCODE = '23514';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION catalogue.bind_offer(p_course text, p_programme text, p_level int, p_basis text, p_track text, p_source text DEFAULT 'COURSE')
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is bound into a programme by a person' USING ERRCODE = '23514'; END IF;
    PERFORM catalogue.assert_offerable(p_course, p_programme, p_level, p_basis, p_track);
    INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, track, added_by, source)
    VALUES (upper(btrim(p_course)), upper(btrim(p_programme)), p_level, coalesce(nullif(btrim(p_basis), ''), 'Core'),
            nullif(upper(btrim(coalesce(p_track, ''))), ''), who, coalesce(nullif(btrim(p_source), ''), 'COURSE'))
    ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis, track = EXCLUDED.track;
END $$;
COMMENT ON FUNCTION catalogue.bind_offer(text, text, int, text, text, text) IS 'V332: offer a course to a programme at a level — the one road from the course''s desk, the programme''s structure or an approved proposal; the course stays one record, its owner unchanged.';

CREATE OR REPLACE FUNCTION catalogue.unbind_offer(p_course text, p_programme text, p_level int, p_reason text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        o catalogue.course_offer; live bigint; carried bigint;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a binding is ended by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO o FROM catalogue.course_offer
     WHERE course_code = upper(btrim(coalesce(p_course, ''))) AND programme_code = upper(btrim(coalesce(p_programme, ''))) AND level = p_level;
    IF o.course_code IS NULL THEN
        RAISE EXCEPTION 'no binding of % into % at % level', p_course, p_programme, p_level USING ERRCODE = '23503';
    END IF;
    SELECT count(*) INTO live
      FROM registration.entry e
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN catalogue.offering f ON f.id = e.offering_id
      JOIN people.student st ON st.id = r.student_id
     WHERE f.course_code = o.course_code AND st.programme_code = o.programme_code AND r.level = o.level
       AND e.status IN ('REGISTERED', 'APPROVED') AND r.status <> 'RETURNED'
       AND r.session = (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1);
    IF live > 0 THEN
        RAISE EXCEPTION 'CAT_BOUND_IN_USE: % student% of % at % level % registered on % this session; the binding stays while they are',
            live, CASE WHEN live = 1 THEN '' ELSE 's' END, o.programme_code, o.level, CASE WHEN live = 1 THEN 'is' ELSE 'are' END, o.course_code
            USING ERRCODE = '23514', HINT = 'Unbind it after the session, or have the registrations amended first.';
    END IF;
    SELECT count(*) INTO carried
      FROM registration.entry e
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN catalogue.offering f ON f.id = e.offering_id
      JOIN people.student st ON st.id = r.student_id
     WHERE f.course_code = o.course_code AND st.programme_code = o.programme_code AND r.level = o.level;
    INSERT INTO catalogue.course_offer_history (course_code, programme_code, level, basis, track, added_at, added_by, source, ended_by, ended_office, reason, registrations_carried)
    VALUES (o.course_code, o.programme_code, o.level, o.basis, o.track, o.added_at, o.added_by, o.source, who, office, nullif(btrim(coalesce(p_reason, '')), ''), carried);
    DELETE FROM catalogue.course_offer WHERE course_code = o.course_code AND programme_code = o.programme_code AND level = o.level;
    RETURN CASE WHEN carried > 0 THEN 'ENDED' ELSE 'REMOVED' END;
END $$;
COMMENT ON FUNCTION catalogue.unbind_offer(text, text, int, text) IS 'V332: end a course''s binding into a programme — refused while a student of that programme and level is registered on it this session; otherwise kept on course_offer_history with the registrations it carried (ENDED) or none (REMOVED). The registrations and results themselves stay.';

-- ── 7 · a proposal to another department, and its decision ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.propose_offer(p_course text, p_programme text, p_level int, p_basis text, p_track text, p_reason text, p_proposed_dept text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); v uuid;
        v_course text := upper(btrim(coalesce(p_course, ''))); v_prog text := upper(btrim(coalesce(p_programme, '')));
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an offer is proposed by a person' USING ERRCODE = '23514'; END IF;
    PERFORM catalogue.assert_offerable(p_course, p_programme, p_level, p_basis, p_track);
    IF EXISTS (SELECT 1 FROM catalogue.course_offer WHERE course_code = v_course AND programme_code = v_prog AND level = p_level) THEN
        RAISE EXCEPTION 'CAT_OFFER_EXISTS: % is already offered to % at % level', v_course, v_prog, p_level USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM catalogue.offer_proposal WHERE course_code = v_course AND programme_code = v_prog AND level = p_level AND state = 'PENDING') THEN
        RAISE EXCEPTION 'CAT_PROPOSAL_PENDING: a proposal of % to % at % level already waits for the department', v_course, v_prog, p_level USING ERRCODE = '23514';
    END IF;
    INSERT INTO catalogue.offer_proposal (course_code, programme_code, level, basis, track, reason, proposed_by, proposed_office, proposed_dept)
    VALUES (v_course, v_prog, p_level, coalesce(nullif(btrim(p_basis), ''), 'Borrowed'), nullif(upper(btrim(coalesce(p_track, ''))), ''),
            nullif(btrim(coalesce(p_reason, '')), ''), who, office, nullif(upper(btrim(coalesce(p_proposed_dept, ''))), ''))
    RETURNING id INTO v;
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION catalogue.decide_offer_proposal(p_id uuid, p_approve boolean, p_note text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); pr catalogue.offer_proposal;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a proposal is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO pr FROM catalogue.offer_proposal WHERE id = p_id FOR UPDATE;
    IF pr.id IS NULL THEN RAISE EXCEPTION 'no proposal is identified %', p_id USING ERRCODE = '23503'; END IF;
    IF pr.state <> 'PENDING' THEN
        RAISE EXCEPTION 'CAT_PROPOSAL_DECIDED: this proposal was already % ', lower(pr.state) USING ERRCODE = '23514';
    END IF;
    IF p_approve THEN
        PERFORM catalogue.bind_offer(pr.course_code, pr.programme_code, pr.level, pr.basis, pr.track, 'PROPOSAL');
    END IF;
    UPDATE catalogue.offer_proposal
       SET state = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END, decided_by = who, decided_office = office, decided_at = now(),
           decision_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = p_id;
    RETURN CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END;
END $$;

CREATE OR REPLACE FUNCTION catalogue.cancel_offer_proposal(p_id uuid, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), ''); pr catalogue.offer_proposal;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a proposal is withdrawn by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO pr FROM catalogue.offer_proposal WHERE id = p_id FOR UPDATE;
    IF pr.id IS NULL THEN RAISE EXCEPTION 'no proposal is identified %', p_id USING ERRCODE = '23503'; END IF;
    IF pr.state <> 'PENDING' THEN RAISE EXCEPTION 'CAT_PROPOSAL_DECIDED: this proposal was already %', lower(pr.state) USING ERRCODE = '23514'; END IF;
    UPDATE catalogue.offer_proposal SET state = 'CANCELLED', decided_by = who, decided_office = office, decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = p_id;
END $$;

-- ── 8 · editing a course keeps it the same course ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION catalogue.update_course(p_code text, p_title text, p_units int, p_semester int, p_level int, p_kind text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_code text := upper(btrim(coalesce(p_code, '')));
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
    IF p_level IS NULL OR p_level NOT BETWEEN 100 AND 900 OR p_level % 100 <> 0 THEN RAISE EXCEPTION 'CAT_LEVEL: a course is at a level from 100 to 900' USING ERRCODE = '23514'; END IF;
    IF coalesce(nullif(btrim(p_kind), ''), 'Core') NOT IN ('Core', 'Required', 'Elective', 'GST') THEN
        RAISE EXCEPTION 'CAT_KIND: a course is Core, Required, Elective or GST' USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.course
       SET title = btrim(p_title), units = p_units, semester = p_semester, level = p_level, kind = coalesce(nullif(btrim(p_kind), ''), 'Core')
     WHERE code = v_code;
END $$;
COMMENT ON FUNCTION catalogue.update_course(text, text, int, int, int, text) IS 'V332: edit a course''s title, units, semester, level and kind in place — the same course (catalogue.course.id), every registration, result, offering and binding still on it.';

CREATE OR REPLACE FUNCTION catalogue.rename_course(p_old text, p_new text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_old text := upper(btrim(coalesce(p_old, ''))); m text[]; v_new text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is renamed by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_old) THEN RAISE EXCEPTION 'no course is coded %', p_old USING ERRCODE = '23503'; END IF;
    m := regexp_match(upper(btrim(coalesce(p_new, ''))), '^([A-Z]{3})\s*([0-9]{3})$');
    IF m IS NULL THEN
        RAISE EXCEPTION 'CAT_CODE: a course code is three letters, a space and three digits, like CSC 311 — % does not fit', coalesce(p_new, '')
            USING ERRCODE = '23514', HINT = 'Three letters for the subject and a three-digit number, e.g. MTH 212 or LAW 301.';
    END IF;
    v_new := m[1] || ' ' || m[2];
    IF v_new = v_old THEN RETURN v_new; END IF;
    IF EXISTS (SELECT 1 FROM catalogue.course WHERE code = v_new) THEN
        RAISE EXCEPTION 'a course with the code % already exists', v_new USING ERRCODE = '23505', HINT = 'A code is unique across the University; pick another.';
    END IF;
    -- the key follows into every table that references it by constraint (ON UPDATE CASCADE), and into the
    -- holdings and postings that carry the code without one
    UPDATE catalogue.course SET code = v_new WHERE code = v_old;
    UPDATE college.posting_course SET course_code = v_new WHERE course_code = v_old;
    UPDATE assessment.legacy_result_holding SET course_code = v_new WHERE course_code = v_old;
    UPDATE admissions.pg_legacy_holding SET course_code = v_new WHERE course_code = v_old;
    RETURN v_new;
END $$;
COMMENT ON FUNCTION catalogue.rename_course(text, text) IS 'V332: change a course''s code — the same course (its id unchanged); its bindings, offerings, registrations, results, questions, CBT examinations, deferred courses, postings and old-portal results follow the new code.';

-- ── 9 · the structure upload binds an existing course of another department; it does not re-own or rewrite it ──
DROP FUNCTION IF EXISTS catalogue.import_courses(text, jsonb, text);
DROP FUNCTION IF EXISTS catalogue.import_courses_rows(text, jsonb, text);

CREATE FUNCTION catalogue.import_courses_rows(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL::text)
RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_dept text; v_code text; v_title text; v_units int; v_level int; v_sem int; v_status text;
        v_kind text; v_basis text; v_lh int; v_ph int; v_curr text; v_owner text;
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
            v_status := upper(left(btrim(coalesce(r->>'status', 'C')), 1));
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
                INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, lecture_hours, practical_hours, curriculum, state)
                VALUES (v_code, v_title, v_units, v_sem, v_level, v_dept, v_kind, v_lh, v_ph, v_curr, 'LIVE')
                ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units, semester = EXCLUDED.semester,
                    level = EXCLUDED.level, kind = EXCLUDED.kind, lecture_hours = EXCLUDED.lecture_hours, practical_hours = EXCLUDED.practical_hours,
                    curriculum = coalesce(EXCLUDED.curriculum, catalogue.course.curriculum),
                    state = CASE WHEN catalogue.course.state IN ('BOARD', 'SENATE') THEN 'LIVE' ELSE catalogue.course.state END;
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

CREATE FUNCTION catalogue.import_courses(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL::text)
RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
LANGUAGE plpgsql AS $$
DECLARE r record; v_in text := upper(nullif(btrim(coalesce(p_curriculum, '')), '')); v_track text; v_framework text; v_prog text;
BEGIN
    IF v_in IN ('CCMAS_BSU', 'CCMAS_MOAU', 'BMAS') THEN
        v_track := v_in; v_framework := (SELECT framework FROM policy.curriculum_track WHERE code = v_in);
    ELSIF v_in = 'CCMAS' THEN
        v_track := NULL; v_framework := 'CCMAS';       -- CCMAS for any cohort
    ELSE
        v_track := NULL; v_framework := v_in;
    END IF;
    FOR r IN SELECT * FROM catalogue.import_courses_rows(p_programme, p_rows, v_framework) LOOP
        rows := r.rows; courses := r.courses; offers := r.offers; no_dept := r.no_dept; bad_code := r.bad_code;
        skipped := r.skipped; first_error := r.first_error; existing := r.existing;
        SELECT code INTO v_prog FROM ref.programme
         WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
        IF v_prog IS NOT NULL THEN
            UPDATE catalogue.course_offer co SET track = v_track
             WHERE co.programme_code = v_prog
               AND upper(co.course_code) IN (
                   SELECT regexp_replace(upper(btrim(coalesce(x->>'code', x->>'courseCode', x->>'course_code', ''))), '\s+', ' ', 'g')
                     FROM jsonb_array_elements(p_rows) x)
               AND co.track IS DISTINCT FROM v_track;
        END IF;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION catalogue.import_courses(text, jsonb, text) IS 'V084/V113/V332: load a programme''s structure — each row''s course is created under the programme''s department, or, where the code is another department''s course, bound to the programme as Borrowed without rewriting it (counted as existing).';

-- ── 10 · the module roles read the new tables as they read the structure ───────────────────────────────────────
GRANT SELECT ON catalogue.course_offer_history, catalogue.offer_proposal TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON catalogue.course_offer_history, catalogue.offer_proposal TO app_registration;

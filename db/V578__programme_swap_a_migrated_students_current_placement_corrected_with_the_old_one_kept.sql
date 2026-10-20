-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V578 — Programme swap: a migrated student's current programme, department, faculty and level corrected, the old placement kept
--
--   Students who changed programme before or during the migration from the old portal arrived under the programme they had
--   left: the register, the statistics, the fee lines and the class lists read them in the old department. The portal had two
--   ways to change a programme, neither for this: the inter-departmental transfer (V070) is the student's own application — a
--   processing fee, both departments, the Registry, the Senate — and the record move (V548) takes only a postgraduate record off
--   an undergraduate programme. Correcting the level alone (the Registry's Correct level, ICT Support's Student Level Management)
--   does not touch the programme.
--
--   The programme swap is an office's correction of the student's CURRENT placement, nothing else:
--     · people.programme_swap: one row a swap (PSW/YYYY/NNNNNN) — the student, the placement before (programme, department,
--       faculty, level) and after, the kind (a legacy migration correction, a programme correction, an academic transfer recorded),
--       the effective session, the reason, the review points the check raised, who prepared it and who decided it, the student row
--       before and after, the effect on the session's course registration. Prepared by the Academic Office, the Registry, the
--       Director of ICT or super; decided — approved and executed at once, or rejected — by ANOTHER officer of the Academic
--       Office or the Registry (super too); the Director of ICT decides a legacy migration correction, the technical case, and no
--       other. Nothing is written to the student until the decision.
--     · people.programme_swap_check says, before anything is written, what the swap would do and what stands in its way: the
--       student's state, the target programme (on the register, not archived, of the student's own category — a postgraduate
--       record onto a postgraduate programme is the V548 record move), the level among the programme's own, a transfer or a swap
--       already under way, the same placement; and what to look at: a level below one already registered at, a level the cohort
--       engine reads differently, the fee lines the new programme would carry for the session, the session's registered courses
--       the new programme does not offer and the new programme's core courses not registered.
--     · the swap changes people.student.programme_code and current_level and nothing else: the matriculation number (immutable
--       by trigger), the JAMB and admission numbers, the account, the registrations and their courses, the results, the
--       payments and receipts, the documents keep their rows; the cohort position refreshes by its own trigger; the statistics,
--       the register, the query engine and the fee lines read the new placement because they read people.student.
--     · people.programme_history reads every placement the record has had, from every source that holds one — the admission
--       (the candidate's programme, or the record's entry), transfers effected (V070), record moves (V548), swaps completed, and
--       any other change of programme the audit chain holds — so the full record shows where the student has been.
--     · people.programme_mismatches finds the migrated records whose placement looks wrong, from what the record itself says:
--       the department segment of the matriculation number against the programme's (ref.programme.matric_code, or the segment
--       most of the programme's own students carry), the department that owns most of the courses on the latest approved
--       registration against the programme's, and the programme the candidate was admitted to. Two signals agreeing on another
--       department: CONFIRMED; one: POSSIBLE; two disagreeing: REQUIRES_REVIEW; none: NO_MISMATCH. Nothing is changed by a
--       finding; an officer records what they made of it in people.programme_mismatch_review.
--     · evidence (a letter, an approval) is kept with the swap in people.programme_swap_evidence, in the file store where there
--       is one (V348), as the payment swap keeps its own.
--     · the student is told on completion (PROGRAMME_SWAP_COMPLETED), the new placement and whom to ask — no migration detail.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V578: programme swap', true);

-- ── 1 · the swap ────────────────────────────────────────────────────────────────────────────────────────────────────────

CREATE SEQUENCE people.programme_swap_seq;

CREATE TABLE people.programme_swap (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    swap_ref          text NOT NULL UNIQUE CHECK (swap_ref ~ '^PSW/[0-9]{4}/[0-9]{6}$'),
    student_id        uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,   -- the go-live reset clears a record's swaps with it
    kind              text NOT NULL CHECK (kind IN ('LEGACY_MIGRATION_CORRECTION', 'PROGRAMME_CORRECTION', 'ACADEMIC_TRANSFER')),
    change            text NOT NULL CHECK (change IN ('PROGRAMME', 'LEVEL', 'PROGRAMME_AND_LEVEL')),
    from_programme    text NOT NULL,
    from_dept         text,
    from_faculty      text,
    from_level        integer,
    to_programme      text NOT NULL REFERENCES ref.programme (code),
    to_dept           text,
    to_faculty        text,
    to_level          integer NOT NULL,
    effective_session text NOT NULL,
    reason            text NOT NULL CHECK (length(btrim(reason)) >= 10),
    review            jsonb NOT NULL DEFAULT '[]'::jsonb,   -- what the check asked the deciding officer to look at
    status            text NOT NULL DEFAULT 'PENDING_APPROVAL'
                      CHECK (status IN ('PENDING_APPROVAL', 'COMPLETED', 'REJECTED', 'CANCELLED', 'FAILED')),
    batch_id          uuid,
    prepared_by       uuid NOT NULL,
    prepared_office   text NOT NULL,
    prepared_at       timestamptz NOT NULL DEFAULT now(),
    decided_by        uuid,
    decided_office    text,
    decided_at        timestamptz,
    decision_note     text,
    executed_at       timestamptz,
    failure           text,
    before_state      jsonb,
    after_state       jsonb,
    impact            jsonb,
    CONSTRAINT ck_programme_swap_decided CHECK (status = 'PENDING_APPROVAL' OR decided_by IS NOT NULL),
    CONSTRAINT ck_programme_swap_other_officer CHECK (decided_by IS NULL OR decided_by <> prepared_by OR status = 'CANCELLED')
);
CREATE INDEX ix_programme_swap_student ON people.programme_swap (student_id, prepared_at DESC);
CREATE INDEX ix_programme_swap_status ON people.programme_swap (status, prepared_at DESC);
CREATE INDEX ix_programme_swap_batch ON people.programme_swap (batch_id) WHERE batch_id IS NOT NULL;
-- one swap under way for a student at a time
CREATE UNIQUE INDEX ux_programme_swap_pending ON people.programme_swap (student_id) WHERE status = 'PENDING_APPROVAL';
COMMENT ON TABLE people.programme_swap IS
  'V578: a student''s current programme, department, faculty and level corrected by an office (PSW/YYYY/NNNNNN) — the placement before and after, the kind, the reason, the review points, who prepared and who decided it (another officer), the student row before and after, the registration impact; the old placement stays here and in people.programme_history';
SELECT audit.attach('people.programme_swap');

CREATE TABLE people.programme_swap_evidence (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    swap_id      uuid NOT NULL REFERENCES people.programme_swap (id) ON DELETE CASCADE,
    filename     text NOT NULL,
    content_type text NOT NULL,
    size_bytes   bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
    content      bytea NULL,
    object_id    uuid NULL REFERENCES platform.file_object (id),
    added_by     uuid NOT NULL,
    added_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_programme_swap_evidence_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_programme_swap_evidence ON people.programme_swap_evidence (swap_id);
COMMENT ON TABLE people.programme_swap_evidence IS 'V578: a file supporting a programme swap (a letter, an approval) — in the file store where there is one, else here';
SELECT audit.exempt('people.programme_swap_evidence', 'The files supporting a programme swap; the swap itself is on the spine.');

-- what an officer made of a possible mismatch (the finding itself is computed, never stored)
CREATE TABLE people.programme_mismatch_review (
    student_id      uuid PRIMARY KEY REFERENCES people.student (id) ON DELETE CASCADE,
    status          text NOT NULL CHECK (status IN ('NOT_REVIEWED', 'UNDER_REVIEW', 'CONFIRMED', 'SWAP_REQUIRED', 'SWAPPED',
                                                    'NO_ACTION_REQUIRED', 'REQUIRES_DOCUMENTATION')),
    note            text,
    reviewed_by     uuid NOT NULL,
    reviewed_office text,
    reviewed_at     timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE people.programme_mismatch_review IS 'V578: what an officer made of a record whose programme looked wrong — under review, confirmed, a swap required, swapped, no action, documentation needed';
SELECT audit.attach('people.programme_mismatch_review');

-- ── 2 · the programme's own levels, and who may do what ─────────────────────────────────────────────────────────────────

-- the levels a programme has: 700, 800 and 900 for a postgraduate programme; 100 up to the final level for the rest
CREATE FUNCTION people.programme_levels(p_programme text) RETURNS integer[]
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p.category = 'POST GRADUATE' THEN ARRAY[700, 800, 900]
                ELSE (SELECT array_agg(l ORDER BY l) FROM generate_series(100, greatest(100, coalesce(p.final_level, p.duration_years * 100, 400)), 100) l) END
      FROM ref.programme p WHERE p.code = p_programme
$$;

CREATE FUNCTION people.programme_swap_office_prepares(p_office text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT p_office IN ('academic', 'registrar', 'dregistrar', 'ict', 'super') $$;

-- the Academic Office and the Registry decide any swap; the Director of ICT the technical case alone
CREATE FUNCTION people.programme_swap_office_decides(p_office text, p_kind text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT p_office IN ('academic', 'registrar', 'dregistrar', 'super') OR (p_office = 'ict' AND p_kind = 'LEGACY_MIGRATION_CORRECTION')
$$;

-- ── 3 · the check: what the swap would do, what stands in its way, what to look at ──────────────────────────────────────

CREATE FUNCTION people.programme_swap_check(p_student uuid, p_to_programme text, p_to_level integer, p_session text, p_ignore uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE
    s record; t record; pos record;
    refusals text[] := '{}'; warnings jsonb := '[]'::jsonb;
    v_to text := upper(btrim(coalesce(p_to_programme, '')));
    v_session text := coalesce(nullif(btrim(p_session), ''), policy.university_current_session());
    v_levels integer[]; v_highest integer; v_open text; v_fee_now numeric; v_fee_new numeric;
    v_regs jsonb; v_change text;
BEGIN
    SELECT st.id, st.surname, st.other_names, st.matric_no, st.jamb_reg_no, st.admission_no, st.status, st.entry_mode, st.study_mode, st.entry_session,
           st.current_level, st.programme_code, st.candidate_id, p.name AS programme, p.category, p.dept_code, d.name AS department,
           p.faculty_code, f.name AS faculty
      INTO s
      FROM people.student st
      LEFT JOIN ref.programme p ON p.code = st.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE st.id = p_student;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'refusals', jsonb_build_array('PSW_STUDENT: no such student'), 'warnings', '[]'::jsonb);
    END IF;
    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT') THEN
        refusals := array_append(refusals, ('PSW_STUDENT_STATE: the record is ' || lower(replace(s.status, '_', ' ')) || '; only a live record''s placement is corrected'));
    END IF;

    SELECT p.code, p.name, p.category, p.archived, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty
      INTO t
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE p.code = v_to;
    IF NOT FOUND THEN
        refusals := array_append(refusals, 'PSW_PROGRAMME: choose a programme on the register');
    ELSE
        IF t.archived THEN refusals := array_append(refusals, ('PSW_PROGRAMME_ARCHIVED: ' || t.name || ' is archived; a student is not placed on it')); END IF;
        IF t.dept_code IS NULL OR t.faculty_code IS NULL THEN
            refusals := array_append(refusals, ('PSW_PROGRAMME_STRUCTURE: ' || t.name || ' has no department or faculty on the structure'));
        END IF;
        IF s.category IS NOT NULL AND t.category IS DISTINCT FROM s.category THEN
            refusals := array_append(refusals, CASE WHEN t.category = 'POST GRADUATE'
                THEN 'PSW_CATEGORY: a record moved onto a postgraduate programme is the record move on Records Check, not a swap'
                ELSE 'PSW_CATEGORY: a postgraduate record is not placed on an undergraduate programme' END);
        END IF;
        v_levels := people.programme_levels(t.code);
        IF p_to_level IS NULL OR NOT (p_to_level = ANY (v_levels)) THEN
            refusals := array_append(refusals, ('PSW_LEVEL: ' || coalesce(t.name, 'the programme') || ' has the levels ' || array_to_string(v_levels, ', ') || '; ' || coalesce(p_to_level::text, 'none') || ' is not among them'));
        END IF;
        IF t.code = s.programme_code AND p_to_level = s.current_level THEN
            refusals := array_append(refusals, 'PSW_SAME: the student is on that programme at that level already; nothing would change');
        END IF;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_session AND a.state NOT IN ('DRAFT', 'CANCELLED')) THEN
        refusals := array_append(refusals, ('PSW_SESSION: ' || v_session || ' is not a session of the University'));
    END IF;

    -- a transfer under way, or a swap already pending
    SELECT ta.state INTO v_open FROM people.transfer_application ta
     WHERE ta.student_id = p_student AND ta.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED') ORDER BY ta.applied_at DESC LIMIT 1;
    IF v_open IS NOT NULL THEN
        refusals := array_append(refusals, ('PSW_TRANSFER_OPEN: an inter-departmental transfer is under way (' || lower(replace(v_open, '_', ' ')) || '); it is effected or withdrawn there first'));
    END IF;
    IF EXISTS (SELECT 1 FROM people.programme_swap x WHERE x.student_id = p_student AND x.status = 'PENDING_APPROVAL' AND x.id IS DISTINCT FROM p_ignore) THEN
        refusals := array_append(refusals, 'PSW_PENDING: a programme swap for this student is awaiting a decision already');
    END IF;
    IF s.candidate_id IS NOT NULL AND EXISTS (SELECT 1 FROM admissions.programme_change_request r WHERE r.candidate_id = s.candidate_id AND r.state = 'REQUESTED') THEN
        refusals := array_append(refusals, 'PSW_CHANGE_REQUESTED: a change of programme is requested at the admission desk; it is decided there first');
    END IF;

    -- what to look at: the level against the record's own history and the cohort engine's reading
    SELECT max(r.level) INTO v_highest FROM registration.course_registration r WHERE r.student_id = p_student AND r.status IN ('APPROVED', 'LOCKED');
    IF p_to_level IS NOT NULL AND v_highest IS NOT NULL AND p_to_level < v_highest THEN
        warnings := warnings || jsonb_build_object('code', 'LEVEL_BELOW_REGISTERED',
            'text', format('The student has an approved registration at %s Level; %s is below it. Approve only where the change of programme means repeating the level.', v_highest, p_to_level));
    END IF;
    SELECT ap.computed_level, ap.spillover_state, ap.final_level INTO pos FROM people.academic_position ap WHERE ap.student_id = p_student;
    IF pos.computed_level IS NOT NULL AND p_to_level IS NOT NULL AND pos.computed_level <> p_to_level AND t.code IS NOT NULL AND t.category <> 'POST GRADUATE' THEN
        warnings := warnings || jsonb_build_object('code', 'LEVEL_DIFFERS_FROM_COHORT',
            'text', format('By the cohort engine the student is at %s Level (entry %s); %s differs. The cohort is corrected on Student Cohorts if the entry session is wrong.', pos.computed_level, s.entry_session, p_to_level));
    END IF;
    IF p_to_level IS NOT NULL AND s.current_level IS NOT NULL AND p_to_level > s.current_level + 100 THEN
        warnings := warnings || jsonb_build_object('code', 'LEVEL_JUMP', 'text', format('The level moves from %s to %s, more than one year at once.', s.current_level, p_to_level));
    END IF;
    IF t.code IS NOT NULL AND t.faculty_code IS DISTINCT FROM s.faculty_code THEN
        warnings := warnings || jsonb_build_object('code', 'FACULTY_CHANGE', 'text', format('The student moves to another faculty: %s to %s.', coalesce(s.faculty, s.faculty_code, '—'), coalesce(t.faculty, t.faculty_code, '—')));
    END IF;
    IF s.entry_mode = 'CCE' AND NOT EXISTS (SELECT 1 FROM ref.programme_route pr WHERE pr.programme_code = t.code AND pr.route = 'CCE' AND pr.active) THEN
        warnings := warnings || jsonb_build_object('code', 'ROUTE', 'text', 'The student is on the CCE route and the programme is not offered on it; the route stays as it is.');
    END IF;

    -- the fee lines the session carries under each programme (nothing is charged here)
    IF t.code IS NOT NULL THEN
        SELECT coalesce(sum(c.amount), 0) INTO v_fee_now FROM finance.charges_of_as(p_student, v_session, ARRAY['FEE'], NULL) c;
        SELECT coalesce(sum(c.amount), 0) INTO v_fee_new FROM finance.charges_of_as(p_student, v_session, ARRAY['FEE'], t.code) c;
    END IF;

    -- the session's registered courses the new programme offers or does not, and its core courses not registered
    IF t.code IS NOT NULL THEN
        WITH regs AS (
            SELECT r.id, r.semester, r.level, r.status FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = v_session),
        ent AS (
            SELECT regs.semester, o.course_code, c.title, e.units, c.dept_code,
                   EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = o.course_code AND co.programme_code = t.code) AS offered,
                   (c.dept_code = t.dept_code OR c.kind IN ('GST', 'EPS')) AS own
              FROM regs JOIN registration.entry e ON e.registration_id = regs.id AND e.status IN ('REGISTERED', 'APPROVED')
              JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code),
        core AS (
            SELECT co.course_code, c.title, c.semester FROM catalogue.course_offer co JOIN catalogue.course c ON c.code = co.course_code
             WHERE co.programme_code = t.code AND co.level = p_to_level AND co.basis = 'Core' AND c.state = 'LIVE'
               AND c.semester IN (SELECT semester FROM regs))
        SELECT jsonb_build_object(
                   'registrations', (SELECT count(*) FROM regs),
                   'registered', (SELECT count(*) FROM ent),
                   'applicable', (SELECT count(*) FROM ent WHERE offered OR own),
                   'extra', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', course_code, 'title', title, 'semester', semester) ORDER BY semester, course_code), '[]'::jsonb) FROM ent WHERE NOT (offered OR own)),
                   'missingCore', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', course_code, 'title', title, 'semester', semester) ORDER BY semester, course_code), '[]'::jsonb)
                                     FROM core WHERE course_code NOT IN (SELECT course_code FROM ent)))
          INTO v_regs;
        IF (v_regs->>'registered')::int > 0 AND jsonb_array_length(v_regs->'extra') > 0 THEN
            warnings := warnings || jsonb_build_object('code', 'REGISTRATION_REVIEW',
                'text', format('%s of the %s courses registered for %s are not offered to %s; the registration is kept as it is and reviewed by the Academic Office afterwards.',
                               jsonb_array_length(v_regs->'extra'), v_regs->>'registered', v_session, t.name));
        END IF;
    END IF;

    v_change := CASE WHEN t.code IS NULL OR t.code = s.programme_code THEN 'LEVEL'
                     WHEN p_to_level IS NULL OR p_to_level = s.current_level THEN 'PROGRAMME' ELSE 'PROGRAMME_AND_LEVEL' END;
    RETURN jsonb_build_object(
        'ok', cardinality(refusals) = 0,
        'refusals', to_jsonb(refusals),
        'warnings', warnings,
        'change', v_change,
        'session', v_session,
        'student', jsonb_build_object('id', s.id, 'name', s.surname || ', ' || s.other_names, 'matricNo', s.matric_no, 'jambRegNo', s.jamb_reg_no,
                                      'admissionNo', s.admission_no, 'status', s.status, 'entryMode', s.entry_mode, 'studyMode', s.study_mode,
                                      'entrySession', s.entry_session),
        'from', jsonb_build_object('programme', s.programme_code, 'programmeName', s.programme, 'dept', s.dept_code, 'department', s.department,
                                   'faculty', s.faculty_code, 'facultyName', s.faculty, 'level', s.current_level, 'category', s.category),
        'to', CASE WHEN t.code IS NULL THEN NULL ELSE jsonb_build_object('programme', t.code, 'programmeName', t.name, 'dept', t.dept_code, 'department', t.department,
                                   'faculty', t.faculty_code, 'facultyName', t.faculty, 'level', p_to_level, 'category', t.category, 'levels', to_jsonb(v_levels)) END,
        'fees', CASE WHEN t.code IS NULL THEN NULL ELSE jsonb_build_object('session', v_session, 'current', v_fee_now, 'new', v_fee_new) END,
        'registration', v_regs,
        'unchanged', jsonb_build_array('Matriculation number', 'JAMB number', 'Admission number', 'Student ID and account', 'Course registrations and their courses',
                                       'Results', 'Payments and receipts', 'Documents', 'Support history'));
END $fn$;
COMMENT ON FUNCTION people.programme_swap_check(uuid, text, integer, text, uuid) IS
  'V578: what a programme swap would do and what stands in its way — refusals (state, programme, category, level, session, a transfer or swap under way), review points (the level against registrations and the cohort engine, the faculty, the route), the fee lines under each programme, the session''s registered courses the new programme does not offer and its core courses not registered';

-- ── 4 · prepare, decide, cancel ─────────────────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION people.prepare_programme_swap(p_student uuid, p_to_programme text, p_to_level integer, p_session text, p_kind text, p_reason text,
                                              p_batch uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        chk jsonb; v_id uuid; v_ref text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a programme swap is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'PSW_OFFICE: a programme swap is prepared by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF p_kind IS NULL OR p_kind NOT IN ('LEGACY_MIGRATION_CORRECTION', 'PROGRAMME_CORRECTION', 'ACADEMIC_TRANSFER') THEN
        RAISE EXCEPTION 'PSW_KIND: say what the swap is — a legacy migration correction, a programme correction or an academic transfer recorded' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PSW_REASON: say why the placement is corrected, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    chk := people.programme_swap_check(p_student, p_to_programme, p_to_level, p_session, NULL);
    IF NOT (chk->>'ok')::boolean THEN
        RAISE EXCEPTION '%', chk->'refusals'->>0 USING ERRCODE = '23514';
    END IF;
    v_ref := 'PSW/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('people.programme_swap_seq')::text, 6, '0');
    INSERT INTO people.programme_swap (swap_ref, student_id, kind, change, from_programme, from_dept, from_faculty, from_level,
                                       to_programme, to_dept, to_faculty, to_level, effective_session, reason, review, batch_id, prepared_by, prepared_office)
    VALUES (v_ref, p_student, p_kind, chk->>'change', chk->'from'->>'programme', chk->'from'->>'dept', chk->'from'->>'faculty', (chk->'from'->>'level')::int,
            chk->'to'->>'programme', chk->'to'->>'dept', chk->'to'->>'faculty', (chk->'to'->>'level')::int, chk->>'session', btrim(p_reason),
            coalesce(chk->'warnings', '[]'::jsonb), p_batch, who, office)
    RETURNING id INTO v_id;
    -- the finding, where one was recorded, now says a swap is on its way
    INSERT INTO people.programme_mismatch_review (student_id, status, note, reviewed_by, reviewed_office)
    VALUES (p_student, 'SWAP_REQUIRED', 'Swap ' || v_ref || ' prepared', who, office)
    ON CONFLICT (student_id) DO UPDATE SET status = 'SWAP_REQUIRED', note = EXCLUDED.note, reviewed_by = EXCLUDED.reviewed_by,
        reviewed_office = EXCLUDED.reviewed_office, reviewed_at = now()
     WHERE people.programme_mismatch_review.status NOT IN ('SWAPPED');
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION people.prepare_programme_swap(uuid, text, integer, text, text, text, uuid) IS
  'V578: a programme swap prepared for another officer''s decision — the check must pass; the placement before and after and the review points are kept on the swap; nothing on the student changes yet';

CREATE FUNCTION people.decide_programme_swap(p_id uuid, p_approve boolean, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        x people.programme_swap; chk jsonb; v_before jsonb; v_after jsonb; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a programme swap is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO x FROM people.programme_swap WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PSW_NOT_FOUND: no such programme swap' USING ERRCODE = 'P0002'; END IF;
    IF x.status <> 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'PSW_DECIDED: this swap is already %', lower(x.status) USING ERRCODE = '23514';
    END IF;
    IF NOT people.programme_swap_office_decides(coalesce(office, ''), x.kind) THEN
        RAISE EXCEPTION 'PSW_OFFICE: a programme swap is decided by the Academic Office or the Registry; the Director of ICT decides a legacy migration correction'
            USING ERRCODE = '42501';
    END IF;
    IF x.prepared_by = who THEN
        RAISE EXCEPTION 'PSW_SAME_OFFICER: the officer who prepared a swap does not decide it; another officer does' USING ERRCODE = '42501';
    END IF;
    IF NOT p_approve THEN
        IF v_note IS NULL OR length(v_note) < 10 THEN RAISE EXCEPTION 'PSW_REASON: say why the swap is rejected' USING ERRCODE = '23514'; END IF;
        UPDATE people.programme_swap SET status = 'REJECTED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note WHERE id = x.id;
        UPDATE people.programme_mismatch_review SET status = 'UNDER_REVIEW', note = 'Swap ' || x.swap_ref || ' rejected: ' || v_note, reviewed_by = who,
               reviewed_office = office, reviewed_at = now() WHERE student_id = x.student_id AND status = 'SWAP_REQUIRED';
        RETURN jsonb_build_object('id', x.id, 'swapRef', x.swap_ref, 'status', 'REJECTED');
    END IF;

    -- the check again, on the record as it stands now: what has changed since the swap was prepared fails it, nothing written
    chk := people.programme_swap_check(x.student_id, x.to_programme, x.to_level, x.effective_session, x.id);
    IF NOT (chk->>'ok')::boolean OR chk->'from'->>'programme' IS DISTINCT FROM x.from_programme OR (chk->'from'->>'level')::int IS DISTINCT FROM x.from_level THEN
        UPDATE people.programme_swap SET status = 'FAILED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
               failure = coalesce(chk->'refusals'->>0, 'PSW_CHANGED: the record changed since the swap was prepared (' || (chk->'from'->>'programme') || ' at '
                                  || coalesce(chk->'from'->>'level', '—') || ' Level now); prepare it again')
         WHERE id = x.id;
        RETURN jsonb_build_object('id', x.id, 'swapRef', x.swap_ref, 'status', 'FAILED', 'failure', (SELECT failure FROM people.programme_swap WHERE id = x.id));
    END IF;

    SELECT to_jsonb(st) INTO v_before FROM people.student st WHERE st.id = x.student_id;
    UPDATE people.student SET programme_code = x.to_programme, current_level = x.to_level WHERE id = x.student_id;
    SELECT to_jsonb(st) INTO v_after FROM people.student st WHERE st.id = x.student_id;
    UPDATE people.programme_swap
       SET status = 'COMPLETED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note, executed_at = now(),
           before_state = v_before - 'curriculum_version', after_state = v_after - 'curriculum_version', impact = chk->'registration', review = chk->'warnings'
     WHERE id = x.id;
    INSERT INTO people.programme_mismatch_review (student_id, status, note, reviewed_by, reviewed_office)
    VALUES (x.student_id, 'SWAPPED', 'Swap ' || x.swap_ref || ' completed', who, office)
    ON CONFLICT (student_id) DO UPDATE SET status = 'SWAPPED', note = EXCLUDED.note, reviewed_by = EXCLUDED.reviewed_by,
        reviewed_office = EXCLUDED.reviewed_office, reviewed_at = now();
    -- the student is told the new placement and whom to ask; nothing of the migration
    BEGIN
        PERFORM platform.tell_student(x.student_id, 'PROGRAMME_SWAP_COMPLETED', NULL,
            jsonb_build_object('NEW_PROGRAMME', chk->'to'->>'programmeName', 'NEW_DEPARTMENT', coalesce(chk->'to'->>'department', ''),
                               'NEW_LEVEL', x.to_level::text, 'SESSION', x.effective_session),
            'PROGRAMME_SWAP_COMPLETED:' || x.id::text);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'programme swap %: the student could not be told (%)', x.swap_ref, SQLERRM;
    END;
    RETURN jsonb_build_object('id', x.id, 'swapRef', x.swap_ref, 'status', 'COMPLETED', 'impact', chk->'registration');
END $fn$;
COMMENT ON FUNCTION people.decide_programme_swap(uuid, boolean, text) IS
  'V578: a programme swap rejected, or approved and executed at once by another officer — the check run again on the record as it stands (a change since fails the swap, nothing written), then the student''s programme and level set, the row before and after and the registration impact kept, the student told';

CREATE FUNCTION people.cancel_programme_swap(p_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        x people.programme_swap;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a programme swap is cancelled by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO x FROM people.programme_swap WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PSW_NOT_FOUND: no such programme swap' USING ERRCODE = 'P0002'; END IF;
    IF x.status <> 'PENDING_APPROVAL' THEN RAISE EXCEPTION 'PSW_DECIDED: this swap is %; it is not cancelled', lower(x.status) USING ERRCODE = '23514'; END IF;
    IF x.prepared_by <> who AND coalesce(office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'PSW_OFFICE: a swap is cancelled by the officer who prepared it, the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'PSW_REASON: say why the swap is cancelled' USING ERRCODE = '23514'; END IF;
    UPDATE people.programme_swap SET status = 'CANCELLED', decided_by = who, decided_office = office, decided_at = now(), decision_note = btrim(p_reason) WHERE id = x.id;
    UPDATE people.programme_mismatch_review SET status = 'UNDER_REVIEW', note = 'Swap ' || x.swap_ref || ' cancelled: ' || btrim(p_reason), reviewed_by = who,
           reviewed_office = office, reviewed_at = now() WHERE student_id = x.student_id AND status = 'SWAP_REQUIRED';
END $fn$;

CREATE FUNCTION people.set_programme_mismatch_review(p_student uuid, p_status text, p_note text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a finding is reviewed by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'PSW_OFFICE: a finding is reviewed by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF p_status IS NULL OR p_status NOT IN ('NOT_REVIEWED', 'UNDER_REVIEW', 'CONFIRMED', 'NO_ACTION_REQUIRED', 'REQUIRES_DOCUMENTATION') THEN
        RAISE EXCEPTION 'PSW_REVIEW_STATUS: a finding is under review, confirmed, needs no action or needs documentation; a swap sets the rest' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN RAISE EXCEPTION 'PSW_STUDENT: no such student' USING ERRCODE = '23514'; END IF;
    INSERT INTO people.programme_mismatch_review (student_id, status, note, reviewed_by, reviewed_office)
    VALUES (p_student, p_status, nullif(btrim(coalesce(p_note, '')), ''), who, office)
    ON CONFLICT (student_id) DO UPDATE SET status = EXCLUDED.status, note = EXCLUDED.note, reviewed_by = EXCLUDED.reviewed_by,
        reviewed_office = EXCLUDED.reviewed_office, reviewed_at = now();
END $fn$;

-- ── 5 · the placements a record has had ─────────────────────────────────────────────────────────────────────────────────

CREATE FUNCTION people.programme_history(p_student uuid)
RETURNS TABLE (at timestamptz, session text, source text, kind text, programme_code text, programme text, dept_code text, department text,
               faculty_code text, faculty text, level integer, from_programme text, from_level integer, reference text, detail text, by_whom text, current boolean)
LANGUAGE sql STABLE AS $$
    WITH st AS (SELECT s.* FROM people.student s WHERE s.id = p_student),
    moves AS (
        SELECT t.effected_at, t.session, 'TRANSFER', 'TRANSFER_EFFECTED', t.to_programme_code, t.from_programme_code, t.from_level,
               NULL, 'Inter-departmental transfer effected', helpdesk.person_name(t.effected_by)
          FROM people.transfer_application t WHERE t.student_id = p_student AND t.state = 'EFFECTED' AND t.effected_at IS NOT NULL
        UNION ALL
        SELECT m.moved_at, NULL, 'RECORD_MOVE', 'RECORD_MOVED', m.to_programme, m.from_programme, m.from_level, NULL,
               'Record moved to a postgraduate programme: ' || m.reason, helpdesk.person_name(m.moved_by)
          FROM people.record_move m WHERE m.student_id = p_student
        UNION ALL
        SELECT x.executed_at, x.effective_session, 'SWAP', 'PROGRAMME_SWAP_' || x.kind, x.to_programme, x.from_programme, x.from_level, x.swap_ref,
               x.reason, helpdesk.person_name(x.decided_by)
          FROM people.programme_swap x WHERE x.student_id = p_student AND x.status = 'COMPLETED'
        UNION ALL
        -- any other change of programme the audit chain holds (an upload, a merge, a correction by hand)
        SELECT e.occurred_at, NULL, 'RECORD', 'PROGRAMME_CHANGED', e.after_state->>'programme_code', e.before_state->>'programme_code',
               nullif(e.before_state->>'current_level', '')::int, NULL, coalesce(e.reason, 'Programme changed on the record'),
               CASE WHEN e.actor_office = 'student' THEN 'The student' WHEN e.actor_id IS NULL THEN 'The system' ELSE helpdesk.person_name(e.actor_id) END
          FROM audit.entries e
         WHERE e.subject_type = 'people.student' AND e.subject_id = p_student AND e.action = 'UPDATE'
           AND e.before_state->>'programme_code' IS DISTINCT FROM e.after_state->>'programme_code'
           AND NOT EXISTS (SELECT 1 FROM people.programme_swap x WHERE x.student_id = p_student AND x.status = 'COMPLETED' AND x.executed_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')
           AND NOT EXISTS (SELECT 1 FROM people.transfer_application t WHERE t.student_id = p_student AND t.effected_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')
           AND NOT EXISTS (SELECT 1 FROM people.record_move m WHERE m.student_id = p_student AND m.moved_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')),
    rows AS (
        -- the admission: the candidate's programme where the record is linked to one; else the programme the record held before its
        -- first recorded move; else the programme it holds (a record never moved)
        SELECT coalesce(a.starts_on::timestamptz, st.matriculated_at, '1900-01-01'::timestamptz) AS at, st.entry_session, 'ADMISSION', 'ORIGINAL_ADMISSION',
               coalesce(c.programme, (SELECT m.from_programme FROM moves m(at, s, src, k, prog, from_programme, fl, rf, d, b) WHERE m.from_programme IS NOT NULL ORDER BY m.at NULLS LAST LIMIT 1),
                        st.programme_code),
               NULL::text, NULL::integer, NULL::text, 'Original admission programme', NULL::text
          FROM st LEFT JOIN admissions.candidate c ON c.id = st.candidate_id LEFT JOIN policy.academic_session a ON a.name = st.entry_session
        UNION ALL
        SELECT * FROM moves)
    SELECT r.at, r.entry_session, r.source, r.kind, r.programme_code, p.name, p.dept_code, d.name, p.faculty_code, f.name, r.from_level, r.from_programme, r.from_level,
           r.reference, r.detail, r.by_whom,
           -- the current placement: the latest move, or the admission where the record was never moved
           CASE WHEN r.kind = 'ORIGINAL_ADMISSION' THEN NOT EXISTS (SELECT 1 FROM moves)
                ELSE r.at = (SELECT max(m.at) FROM moves m(at)) AND r.programme_code = (SELECT programme_code FROM st) END
      FROM rows r(at, entry_session, source, kind, programme_code, from_programme, from_level, reference, detail, by_whom)
      LEFT JOIN ref.programme p ON p.code = r.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     ORDER BY (r.kind = 'ORIGINAL_ADMISSION') DESC, r.at NULLS FIRST
$$;
COMMENT ON FUNCTION people.programme_history(uuid) IS
  'V578: every placement a record has had — the admission, transfers effected, record moves, swaps completed, and any other change of programme on the audit chain — oldest first, the current one marked';

-- ── 6 · the records whose placement looks wrong ─────────────────────────────────────────────────────────────────────────

-- the signals, student by student: the matriculation number's department segment against the programme's, the department owning most
-- of the latest approved registration's courses against the programme's, the candidate's admitted programme against the current one
CREATE FUNCTION people.programme_mismatches(p_fac text, p_dept text, p_prog text)
RETURNS TABLE (student_id uuid, surname text, other_names text, matric_no text, jamb_reg_no text, status text, entry_mode text, entry_session text,
               current_level integer, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text,
               matric_segment text, programme_segment text, registration_dept text, registration_dept_name text, registration_share numeric,
               admitted_programme text, admitted_programme_name text, classification text, suggested_dept text, suggested_programme text,
               suggested_programme_name text, review_status text, review_note text, reviewed_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH st AS MATERIALIZED (
        SELECT s.id, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.status, s.entry_mode, s.entry_session, s.current_level, s.programme_code,
               s.candidate_id, p.name AS programme, p.dept_code, p.faculty_code, p.matric_code, p.category,
               CASE WHEN s.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/' THEN split_part(s.matric_no, '/', 3) END AS seg
          FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT')
           AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)),
    -- the segment most of a programme's students carry: read over the whole register, so a filtered view judges by the same measure
    observed AS MATERIALIZED (
        SELECT programme_code, seg FROM (
            SELECT s.programme_code, split_part(s.matric_no, '/', 3) AS seg, count(*) AS n,
                   row_number() OVER (PARTITION BY s.programme_code ORDER BY count(*) DESC, split_part(s.matric_no, '/', 3)) AS rn
              FROM people.student s WHERE s.status IN ('ACTIVE', 'PROBATION', 'ADMITTED') AND s.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/'
             GROUP BY 1, 2) o WHERE rn = 1 AND n >= 3),
    seg_dept AS MATERIALIZED (   -- which department a segment names: the programme carrying it, by its own code or by its students
        SELECT seg, dept_code FROM (
            SELECT coalesce(p.matric_code, o.seg) AS seg, p.dept_code, row_number() OVER (PARTITION BY coalesce(p.matric_code, o.seg) ORDER BY (p.matric_code IS NOT NULL) DESC, p.code) rn
              FROM ref.programme p LEFT JOIN observed o ON o.programme_code = p.code WHERE coalesce(p.matric_code, o.seg) IS NOT NULL AND p.dept_code IS NOT NULL) q WHERE rn = 1),
    latest AS MATERIALIZED (
        SELECT DISTINCT ON (r.student_id) r.student_id, r.id FROM registration.course_registration r JOIN st ON st.id = r.student_id
         WHERE r.status IN ('APPROVED', 'LOCKED') ORDER BY r.student_id, r.session DESC, r.semester DESC),
    regdept AS MATERIALIZED (
        SELECT student_id, dept_code, share FROM (
            SELECT l.student_id, c.dept_code, count(*)::numeric / sum(count(*)) OVER (PARTITION BY l.student_id) AS share,
                   row_number() OVER (PARTITION BY l.student_id ORDER BY count(*) DESC, c.dept_code) AS rn
              FROM latest l JOIN registration.entry e ON e.registration_id = l.id AND e.status IN ('REGISTERED', 'APPROVED')
              JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
             WHERE c.kind NOT IN ('GST', 'EPS') AND c.dept_code IS NOT NULL
             GROUP BY 1, 2) q WHERE rn = 1),
    judged AS (
        SELECT st.*, coalesce(st.matric_code, o.seg) AS programme_segment, sd.dept_code AS seg_dept, rd.dept_code AS reg_dept, rd.share,
               c.programme AS admitted_programme,
               (st.seg IS NOT NULL AND coalesce(st.matric_code, o.seg) IS NOT NULL AND st.seg <> coalesce(st.matric_code, o.seg) AND sd.dept_code IS NOT NULL AND sd.dept_code <> st.dept_code) AS by_matric,
               (rd.dept_code IS NOT NULL AND rd.dept_code <> st.dept_code AND rd.share >= 0.5) AS by_registration,
               (c.programme IS NOT NULL AND c.programme <> st.programme_code) AS by_admission
          FROM st
          LEFT JOIN observed o ON o.programme_code = st.programme_code
          LEFT JOIN seg_dept sd ON sd.seg = st.seg
          LEFT JOIN regdept rd ON rd.student_id = st.id
          LEFT JOIN admissions.candidate c ON c.id = st.candidate_id),
    classed AS (
        SELECT j.*,
               CASE WHEN j.by_matric AND j.by_registration AND j.seg_dept = j.reg_dept THEN 'CONFIRMED'
                    WHEN j.by_matric AND j.by_registration THEN 'REQUIRES_REVIEW'
                    WHEN j.by_matric OR j.by_registration OR j.by_admission THEN 'POSSIBLE'
                    ELSE 'NO_MISMATCH' END AS classification,
               CASE WHEN j.by_matric AND j.by_registration AND j.seg_dept = j.reg_dept THEN j.seg_dept
                    WHEN j.by_registration THEN j.reg_dept WHEN j.by_matric THEN j.seg_dept END AS suggested_dept
          FROM judged j),
    -- the programme suggested for a department: the one of the student's own category most of its students sit on (read once)
    suggested AS MATERIALIZED (
        SELECT DISTINCT ON (p.dept_code, p.category) p.dept_code, p.category, p.code, p.name
          FROM ref.programme p
          LEFT JOIN (SELECT s2.programme_code, count(*) AS n FROM people.student s2 WHERE s2.status IN ('ACTIVE', 'PROBATION') GROUP BY 1) pop ON pop.programme_code = p.code
         WHERE NOT p.archived AND p.dept_code IS NOT NULL
         ORDER BY p.dept_code, p.category, coalesce(pop.n, 0) DESC, p.code)
    SELECT c.id, c.surname, c.other_names, c.matric_no, c.jamb_reg_no, c.status, c.entry_mode, c.entry_session, c.current_level, c.programme_code, c.programme,
           c.dept_code, d.name, c.faculty_code, f.name, c.seg, c.programme_segment, c.reg_dept, rdn.name, round(c.share, 2), c.admitted_programme, ap.name,
           c.classification, c.suggested_dept, sp.code, sp.name,
           coalesce(rv.status, 'NOT_REVIEWED'), rv.note, rv.reviewed_at
      FROM classed c
      LEFT JOIN ref.department d ON d.code = c.dept_code
      LEFT JOIN ref.faculty f ON f.code = c.faculty_code
      LEFT JOIN ref.department rdn ON rdn.code = c.reg_dept
      LEFT JOIN ref.programme ap ON ap.code = c.admitted_programme
      LEFT JOIN suggested sp ON sp.dept_code = c.suggested_dept AND sp.category = c.category
      LEFT JOIN people.programme_mismatch_review rv ON rv.student_id = c.id
     WHERE c.classification <> 'NO_MISMATCH' OR rv.student_id IS NOT NULL
$$;
COMMENT ON FUNCTION people.programme_mismatches(text, text, text) IS
  'V578: the live records whose placement looks wrong, by what the record says — the matriculation number''s department segment, the department owning most of the latest approved registration, the admitted programme — classed CONFIRMED (two signals agreeing), REQUIRES_REVIEW (two disagreeing), POSSIBLE (one), with the department and programme suggested and the officer''s review; nothing here changes a record';

-- the swaps, for the desk and the report (scope by the placement before OR after, so a faculty finds the students it lost and gained)
CREATE FUNCTION people.programme_swaps(p_status text, p_session text, p_fac text, p_dept text, p_from text, p_to text, p_level integer, p_kind text,
                                       p_from_date date, p_to_date date, p_q text, p_limit integer DEFAULT 500)
RETURNS TABLE (id uuid, swap_ref text, student_id uuid, student text, matric_no text, jamb_reg_no text, kind text, change text, status text,
               from_programme text, from_programme_name text, from_dept text, from_department text, from_faculty text, from_faculty_name text, from_level integer,
               to_programme text, to_programme_name text, to_dept text, to_department text, to_faculty text, to_faculty_name text, to_level integer,
               effective_session text, reason text, review jsonb, batch_id uuid, prepared_by text, prepared_office text, prepared_at timestamptz,
               decided_by text, decided_office text, decided_at timestamptz, decision_note text, executed_at timestamptz, failure text, impact jsonb,
               evidence integer)
LANGUAGE sql STABLE AS $$
    SELECT x.id, x.swap_ref, x.student_id, s.surname || ', ' || s.other_names, s.matric_no, s.jamb_reg_no, x.kind, x.change, x.status,
           x.from_programme, fp.name, x.from_dept, fd.name, x.from_faculty, ff.name, x.from_level,
           x.to_programme, tp.name, x.to_dept, td.name, x.to_faculty, tf.name, x.to_level,
           x.effective_session, x.reason, x.review, x.batch_id, helpdesk.person_name(x.prepared_by), x.prepared_office, x.prepared_at,
           helpdesk.person_name(x.decided_by), x.decided_office, x.decided_at, x.decision_note, x.executed_at, x.failure, x.impact,
           (SELECT count(*)::int FROM people.programme_swap_evidence ev WHERE ev.swap_id = x.id)
      FROM people.programme_swap x
      JOIN people.student s ON s.id = x.student_id
      LEFT JOIN ref.programme fp ON fp.code = x.from_programme LEFT JOIN ref.department fd ON fd.code = x.from_dept LEFT JOIN ref.faculty ff ON ff.code = x.from_faculty
      LEFT JOIN ref.programme tp ON tp.code = x.to_programme LEFT JOIN ref.department td ON td.code = x.to_dept LEFT JOIN ref.faculty tf ON tf.code = x.to_faculty
     WHERE (p_status IS NULL OR x.status = p_status)
       AND (p_session IS NULL OR x.effective_session = p_session)
       AND (p_fac IS NULL OR p_fac IN (x.from_faculty, x.to_faculty))
       AND (p_dept IS NULL OR p_dept IN (x.from_dept, x.to_dept))
       AND (p_from IS NULL OR x.from_programme = p_from)
       AND (p_to IS NULL OR x.to_programme = p_to)
       AND (p_level IS NULL OR p_level IN (x.from_level, x.to_level))
       AND (p_kind IS NULL OR x.kind = p_kind)
       AND (p_from_date IS NULL OR (x.prepared_at AT TIME ZONE 'Africa/Lagos')::date >= p_from_date)
       AND (p_to_date IS NULL OR (x.prepared_at AT TIME ZONE 'Africa/Lagos')::date <= p_to_date)
       AND (p_q IS NULL OR x.swap_ref ILIKE '%' || p_q || '%' OR s.matric_no ILIKE '%' || p_q || '%' OR s.jamb_reg_no ILIKE '%' || p_q || '%'
            OR (s.surname || ' ' || s.other_names) ILIKE '%' || p_q || '%')
     ORDER BY x.prepared_at DESC
     LIMIT greatest(1, least(coalesce(p_limit, 500), 5000))
$$;

-- ── 7 · the student told ────────────────────────────────────────────────────────────────────────────────────────────────

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PROGRAMME_SWAP_COMPLETED', 'Programme on the portal corrected',
 'To a student whose programme or level on the portal the Academic Office or the Registry has corrected',
 'Your programme on the portal: [NEW_PROGRAMME]',
 E'Dear [FIRST_NAME],\n\nYour record on the portal now reads [NEW_PROGRAMME], [NEW_DEPARTMENT], [NEW_LEVEL] Level, from the [SESSION] session. Your matriculation number, payments and results are unchanged.\n\nIf this is not right, tell the Academic Office.\n\nSign in: [PORTAL_URL]\n\n[UNIVERSITY_SHORT]',
 '[UNIVERSITY_SHORT]: your portal record now reads [NEW_PROGRAMME], [NEW_LEVEL] Level ([SESSION]). Not right? Tell the Academic Office.',
 'Your programme on the portal was corrected',
 'Your record now reads [NEW_PROGRAMME], [NEW_DEPARTMENT], [NEW_LEVEL] Level, from [SESSION]. Your matriculation number, payments and results are unchanged. If this is not right, tell the Academic Office.',
 ARRAY['FIRST_NAME','NEW_PROGRAMME','NEW_DEPARTMENT','NEW_LEVEL','SESSION','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- V574 classes every column naming a programme for a merge: a swap's target is history, kept as it was (a pending swap is checked
-- again at its decision, and an archived programme refuses it)
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('people.programme_swap', 'to_programme', 'KEEP', 'a programme swap''s target as it was; a pending swap is checked again when decided')
ON CONFLICT (tab, col) DO NOTHING;

GRANT SELECT ON people.programme_swap, people.programme_mismatch_review TO app_auditor, app_reporting;

COMMIT;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V588 — Inter-university transfer, incoming and outgoing
--
--   Students who come to the University from another, and students who leave for another, under the University's transfer policy
--   (approved by the Senate, recorded here many at a time from a spreadsheet):
--     · ref.university: the other universities, kept by the Academic Office and the Registry (ref.save_university) — a transfer
--       names one by its code, never in free text;
--     · people.university_transfer_check(rows, session): each row checked, its direction stated (INCOMING or OUTGOING):
--         OUTGOING — the student found by the matriculation number (a former one too, V579) or the JAMB number, never the name; a
--           record still live; the faculty, department, programme and level the row states as the student's own against the
--           record (SOURCE PROGRAMME MISMATCH, never put right silently); an inter-departmental transfer, a programme swap or
--           another university transfer of the student under way refused;
--         INCOMING — the identity searched first, so no one is placed twice: a student already on the register under the JAMB
--           number (directly or through the applicant it came from) or the matriculation number is that student — the transfer
--           is recorded on that record when it is live and already on the target placement, and refused otherwise (a placement is
--           changed by a programme swap, a closed record by the Registry); an applicant under the JAMB number not yet on the
--           register is linked to the new record, never duplicated; else a new record is made at the decision; the target an
--           undergraduate programme on the register in its department in its faculty, not archived, at a level of its own;
--         the other university on the list; the session one of the University's; the same student (or JAMB number) on two rows
--         refused on every row;
--     · people.prepare_university_transfers: a batch IUT/YYYY/NNNNNN, each valid row a transfer awaiting a decision
--       (people.university_transfer) and each invalid row kept with why — refused while a row is invalid unless the valid rows
--       alone are asked for; nothing on any record changes yet;
--     · people.decide_university_transfer (and the batch's, transfer by transfer): ANOTHER officer of the Academic Office or the
--       Registry; rejected with a note, or approved after the row is checked again on the records as they stand, and —
--         INCOMING: the record made as an admitted student would be (an admission number, ADMITTED, entry by TRANSFER at the
--           target level in the effective session, the applicant linked where there is one, the contact the row gives) or the
--           existing record named; the previous university, programme and level kept on the transfer; the matriculation number
--           follows by Matriculation Management as for any admitted student;
--         OUTGOING: the status TRANSFERRED_OUT by people.change_status on the batch's instrument (the student told), the
--           destination kept on the transfer, the record and every row of its history kept;
--     · people.university_transfer_batches / people.university_transfers: the batches and the transfers, by batch, student or
--       search, for the desk, the report and the student's record.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V588: inter-university transfer, incoming and outgoing', true);

-- ── 1 · the other universities ──────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE ref.university (
    code        text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9]{1,15}$'),
    name        text NOT NULL CHECK (length(btrim(name)) >= 3),
    country     text NOT NULL DEFAULT 'Nigeria' CHECK (length(btrim(country)) >= 2),
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_university_name ON ref.university (lower(btrim(name)));
SELECT audit.attach('ref.university');
COMMENT ON TABLE ref.university IS 'V588: the other universities a student transfers from or to — named by code on every transfer, never in free text; kept by the Academic Office and the Registry';

-- a starting list, kept and added to by the office (this University's own former name, Benue State University, is not another)
INSERT INTO ref.university (code, name) VALUES
    ('ABU', 'Ahmadu Bello University, Zaria'),
    ('FULAFIA', 'Federal University of Lafia'),
    ('FUWUKARI', 'Federal University Wukari'),
    ('JOSTUM', 'Joseph Sarwuan Tarka University, Makurdi'),
    ('NSUK', 'Nasarawa State University, Keffi'),
    ('OAU', 'Obafemi Awolowo University, Ile-Ife'),
    ('UI', 'University of Ibadan'),
    ('UNIABUJA', 'University of Abuja'),
    ('UNIBEN', 'University of Benin'),
    ('UNILAG', 'University of Lagos'),
    ('UNILORIN', 'University of Ilorin'),
    ('UNIJOS', 'University of Jos'),
    ('UNN', 'University of Nigeria, Nsukka')
ON CONFLICT DO NOTHING;

CREATE FUNCTION ref.save_university(p_code text, p_name text, p_country text, p_active boolean)
RETURNS ref.university LANGUAGE plpgsql AS $fn$
DECLARE office text := nullif(current_setting('moaum.actor_office', true), ''); v_code text := upper(btrim(coalesce(p_code, ''))); v ref.university;
BEGIN
    IF coalesce(office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'UNIVERSITY_OFFICE: the list of universities is kept by the Academic Office and the Registry' USING ERRCODE = '42501';
    END IF;
    IF v_code !~ '^[A-Z][A-Z0-9]{1,15}$' THEN
        RAISE EXCEPTION 'UNIVERSITY_CODE: a code is 2 to 16 capital letters and digits, beginning with a letter (UNIJOS, ABU)' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_name, ''))) < 3 THEN
        RAISE EXCEPTION 'UNIVERSITY_NAME: give the university''s full name' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM ref.university u WHERE lower(btrim(u.name)) = lower(btrim(p_name)) AND u.code <> v_code) THEN
        RAISE EXCEPTION 'UNIVERSITY_NAME_TAKEN: % is on the list already under another code', btrim(p_name) USING ERRCODE = '23514';
    END IF;
    INSERT INTO ref.university (code, name, country, active)
    VALUES (v_code, btrim(p_name), coalesce(nullif(btrim(coalesce(p_country, '')), ''), 'Nigeria'), coalesce(p_active, true))
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, country = EXCLUDED.country, active = EXCLUDED.active, updated_at = now()
    RETURNING * INTO v;
    RETURN v;
END $fn$;
COMMENT ON FUNCTION ref.save_university(text, text, text, boolean) IS 'V588: a university added to the list or its name, country or standing put right (a code is never renamed; one no longer used is made inactive)';

-- ── 2 · the batches, the transfers ──────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE people.university_transfer_batch (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref               text NOT NULL UNIQUE CHECK (ref ~ '^IUT/[0-9]{4}/[0-9]{6}$'),
    effective_session text NOT NULL,
    filename          text NULL,
    reason            text NOT NULL CHECK (length(btrim(reason)) >= 10),
    approval_ref      text NULL,
    partial           boolean NOT NULL DEFAULT false,
    total             int NOT NULL DEFAULT 0,
    prepared          int NOT NULL DEFAULT 0,
    left_out          int NOT NULL DEFAULT 0,
    prepared_by       uuid NOT NULL,
    prepared_office   text NOT NULL,
    prepared_at       timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('people.university_transfer_batch');
COMMENT ON TABLE people.university_transfer_batch IS 'V588: a bulk inter-university transfer (IUT/YYYY/NNNNNN): the file, the session, the reason and approval, how many rows prepared and left out';

CREATE TABLE people.university_transfer (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id          uuid NOT NULL REFERENCES people.university_transfer_batch (id) ON DELETE CASCADE,
    row_no            int NOT NULL,
    direction         text NOT NULL CHECK (direction IN ('INCOMING', 'OUTGOING')),
    uploaded          jsonb NOT NULL,
    student_id        uuid NULL REFERENCES people.student (id) ON DELETE CASCADE,   -- the go-live reset clears it with the student
    candidate_id      uuid NULL,
    jamb_reg_no       text NULL,
    matched_by        text NULL,
    university_code   text NOT NULL REFERENCES ref.university (code),
    other_programme   text NULL,
    other_level       int NULL,
    programme_code    text NULL REFERENCES ref.programme (code),
    level             int NULL,
    effective_session text NOT NULL,
    reason            text NULL,
    status            text NOT NULL DEFAULT 'PENDING_APPROVAL' CHECK (status IN ('PENDING_APPROVAL', 'COMPLETED', 'REJECTED')),
    created_student   boolean NOT NULL DEFAULT false,
    prepared_by       uuid NOT NULL,
    prepared_office   text NOT NULL,
    prepared_at       timestamptz NOT NULL DEFAULT now(),
    decided_by        uuid NULL,
    decided_office    text NULL,
    decided_at        timestamptz NULL,
    decision_note     text NULL,
    UNIQUE (batch_id, row_no),
    CONSTRAINT ck_university_transfer_other_officer CHECK (decided_by IS NULL OR decided_by <> prepared_by),
    CONSTRAINT ck_university_transfer_incoming_jamb CHECK (direction <> 'INCOMING' OR jamb_reg_no IS NOT NULL)
);
CREATE INDEX ix_university_transfer_batch ON people.university_transfer (batch_id);
CREATE INDEX ix_university_transfer_student ON people.university_transfer (student_id) WHERE student_id IS NOT NULL;
CREATE INDEX ix_university_transfer_status ON people.university_transfer (status, prepared_at DESC);
-- one transfer awaiting a decision for a record, or for a JAMB number not yet on the register, at a time
CREATE UNIQUE INDEX ux_university_transfer_pending ON people.university_transfer (student_id) WHERE status = 'PENDING_APPROVAL' AND student_id IS NOT NULL;
CREATE UNIQUE INDEX ux_university_transfer_pending_jamb ON people.university_transfer (upper(jamb_reg_no))
    WHERE status = 'PENDING_APPROVAL' AND student_id IS NULL AND jamb_reg_no IS NOT NULL;
SELECT audit.attach('people.university_transfer');
COMMENT ON TABLE people.university_transfer IS
  'V588: a student transferred from another university (INCOMING: the record made or found at the decision) or to one (OUTGOING: TRANSFERRED_OUT at the decision) — the row as uploaded, the other university and its programme and level, the placement here, who prepared it and who decided it (another officer).';

CREATE TABLE people.university_transfer_left_out (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id   uuid NOT NULL REFERENCES people.university_transfer_batch (id) ON DELETE CASCADE,
    row_no     int NOT NULL,
    uploaded   jsonb NOT NULL,
    messages   jsonb NOT NULL,
    UNIQUE (batch_id, row_no)
);
SELECT audit.attach('people.university_transfer_left_out');
COMMENT ON TABLE people.university_transfer_left_out IS 'V588: a row of a bulk inter-university transfer left out as invalid, kept with why';

-- ── 3 · the rows checked ────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.university_transfer_check(p_rows jsonb, p_session text, p_except uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE r record; v_out jsonb := '[]'; v_msgs jsonb; v_warn jsonb; v_dir text; v_no text; v_jamb text; s record; v_matched text; v_univ text;
        t record; v_cand uuid; v_cand_session text; v_cand_offer text; v_cand_prog text; v_prog text; v_dept text; v_fac text; v_level int; v_session text; v_name text; v_surname text; v_others text;
        v_action text; v_sex text; v_dob text; v_email text; v_phone text;
        v_live CONSTANT text[] := ARRAY['ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT'];
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RETURN '[]'; END IF;
    FOR r IN SELECT x.value AS row, x.ordinality::int AS n FROM jsonb_array_elements(p_rows) WITH ORDINALITY x LOOP
        v_msgs := '[]'; v_warn := '[]'; v_matched := NULL; v_action := NULL; v_cand := NULL; v_surname := NULL; v_others := NULL;
        v_sex := NULL; v_dob := NULL; v_email := NULL; v_phone := NULL;
        v_dir := upper(coalesce(people.transfer_cell(r.row, 'direction', 'Transfer Direction', 'Direction'), ''));
        v_dir := CASE WHEN v_dir IN ('IN', 'INCOMING') THEN 'INCOMING' WHEN v_dir IN ('OUT', 'OUTGOING') THEN 'OUTGOING' END;
        v_no := upper(regexp_replace(coalesce(people.transfer_cell(r.row, 'matric_no', 'Student Matriculation Number', 'Matriculation Number', 'Matric No'), ''), '\s+', '', 'g'));
        v_jamb := upper(regexp_replace(coalesce(people.transfer_cell(r.row, 'jamb_reg_no', 'JAMB Number', 'JAMB Registration Number'), ''), '\s+', '', 'g'));
        v_name := people.transfer_cell(r.row, 'student', 'Student Name', 'Name');
        v_session := coalesce(people.transfer_cell(r.row, 'effective_session', 'Effective Session'), nullif(btrim(coalesce(p_session, '')), ''), policy.university_current_session());
        v_univ := upper(btrim(coalesce(people.transfer_cell(r.row, 'university_code', 'University Code', 'Previous University Code', 'Destination University Code'), '')));
        v_prog := upper(coalesce(people.transfer_cell(r.row, 'programme', 'Programme Code', 'Current/Target Programme Code'), ''));
        v_dept := upper(coalesce(people.transfer_cell(r.row, 'dept', 'Department Code', 'Current/Target Department Code'), ''));
        v_fac := upper(coalesce(people.transfer_cell(r.row, 'faculty', 'Faculty Code', 'Current/Target Faculty Code'), ''));
        BEGIN
            v_level := nullif(regexp_replace(coalesce(people.transfer_cell(r.row, 'level', 'Level', 'Current/Target Level'), ''), '[^0-9]', '', 'g'), '')::int;
        EXCEPTION WHEN OTHERS THEN v_level := NULL; END;

        IF v_dir IS NULL THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'DIRECTION', 'text', 'Say the transfer direction: INCOMING or OUTGOING');
        END IF;
        IF v_univ = '' THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'UNIVERSITY_MISSING', 'text', 'Give the other university''s code from the list of universities');
        ELSIF NOT EXISTS (SELECT 1 FROM ref.university u WHERE u.code = v_univ AND u.active) THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'UNIVERSITY_UNKNOWN', 'text', v_univ || ' is not on the list of universities; add it under Universities first');
        END IF;
        IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_session AND a.state NOT IN ('DRAFT', 'CANCELLED')) THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'SESSION', 'text', coalesce(v_session, 'The session') || ' is not a session of the University');
        END IF;

        -- the student: the matriculation number, a former one kept by a correction, the JAMB number (directly or through the
        -- applicant the record came from) — never the name
        SELECT x.id, x.surname, x.other_names, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code, x.entry_mode, p.dept_code, p.faculty_code INTO s
          FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
         WHERE x.duplicate_of IS NULL AND v_no <> '' AND upper(x.matric_no) = v_no;
        IF s.id IS NOT NULL THEN v_matched := 'MATRIC'; END IF;
        IF s.id IS NULL AND v_no <> '' THEN
            SELECT x.id, x.surname, x.other_names, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code, x.entry_mode, p.dept_code, p.faculty_code INTO s
              FROM people.matric_alias a JOIN people.student x ON x.id = a.student_id LEFT JOIN ref.programme p ON p.code = x.programme_code
             WHERE upper(a.old_no) = v_no AND a.ended_at IS NULL;
            IF s.id IS NOT NULL THEN
                v_matched := 'FORMER_MATRIC';
                v_warn := v_warn || jsonb_build_object('code', 'FORMER_MATRIC', 'text', v_no || ' was corrected to ' || s.matric_no || '; the row is read as that student');
            END IF;
        END IF;
        IF s.id IS NULL AND v_jamb <> '' THEN
            SELECT x.id, x.surname, x.other_names, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code, x.entry_mode, p.dept_code, p.faculty_code INTO s
              FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
             WHERE x.duplicate_of IS NULL
               AND (upper(btrim(x.jamb_reg_no)) = v_jamb
                    OR x.candidate_id IN (SELECT k.id FROM admissions.candidate k WHERE upper(k.jamb_reg_no) = v_jamb))
             ORDER BY (x.status = ANY (v_live)) DESC, x.matriculated_at DESC NULLS LAST LIMIT 1;
            IF s.id IS NOT NULL THEN v_matched := 'JAMB'; END IF;
        END IF;
        IF s.id IS NOT NULL AND v_name IS NOT NULL AND position(upper(btrim(s.surname)) IN upper(v_name)) = 0 THEN
            v_warn := v_warn || jsonb_build_object('code', 'NAME_DIFFERS', 'text', 'The name given (' || v_name || ') does not carry the surname on the record (' || s.surname || ')');
        END IF;
        -- another inter-university transfer of the student (or of the JAMB number) awaiting a decision
        IF EXISTS (SELECT 1 FROM people.university_transfer u
                    WHERE u.status = 'PENDING_APPROVAL' AND u.id IS DISTINCT FROM p_except
                      AND ((s.id IS NOT NULL AND u.student_id = s.id) OR (v_jamb <> '' AND upper(u.jamb_reg_no) = v_jamb))) THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'TRANSFER_PENDING', 'text', 'An inter-university transfer of the student awaits a decision already');
        END IF;

        IF v_dir = 'OUTGOING' THEN
            IF s.id IS NULL THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'STUDENT_NOT_FOUND', 'text', 'No student holds the matriculation or JAMB number given');
            ELSE
                v_action := 'TRANSFER_OUT';
                IF NOT (s.status = ANY (v_live)) THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'STUDENT_STATE', 'text', 'The record is ' || lower(replace(s.status, '_', ' ')) || '; only a live record is transferred out');
                END IF;
                -- the placement the row states against the CURRENT record: never put right silently
                IF v_prog IS DISTINCT FROM upper(coalesce(s.programme_code, '')) OR v_dept IS DISTINCT FROM upper(coalesce(s.dept_code, ''))
                   OR v_fac IS DISTINCT FROM upper(coalesce(s.faculty_code, '')) THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'SOURCE_PROGRAMME_MISMATCH', 'text',
                        'SOURCE PROGRAMME MISMATCH: the file says ' || coalesce(nullif(v_fac, ''), '—') || ' / ' || coalesce(nullif(v_dept, ''), '—') || ' / '
                        || coalesce(nullif(v_prog, ''), '—') || '; the record says ' || coalesce(s.faculty_code, '—') || ' / ' || coalesce(s.dept_code, '—') || ' / ' || coalesce(s.programme_code, '—'));
                END IF;
                IF v_level IS DISTINCT FROM s.current_level THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'SOURCE_LEVEL_MISMATCH', 'text',
                        'The file says ' || coalesce(v_level::text, 'no level') || ' Level; the record says ' || coalesce(s.current_level::text, 'none'));
                END IF;
                IF EXISTS (SELECT 1 FROM people.transfer_application ta WHERE ta.student_id = s.id AND ta.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED'))
                   OR EXISTS (SELECT 1 FROM people.programme_swap w WHERE w.student_id = s.id AND w.status = 'PENDING_APPROVAL') THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'CHANGE_UNDER_WAY', 'text', 'An inter-departmental transfer or a programme swap of the student is under way; it is decided first');
                END IF;
                IF s.status = 'SUSPENDED' THEN
                    v_warn := v_warn || jsonb_build_object('code', 'SUSPENDED', 'text', 'The student is suspended; the transfer out closes the record as it stands');
                END IF;
            END IF;
        ELSIF v_dir = 'INCOMING' THEN
            IF v_jamb = '' THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'JAMB_MISSING', 'text', 'Give the student''s JAMB registration number: it is how the student is matched, so no one is placed twice');
            END IF;
            -- the target: an undergraduate programme on the register, in its department, in its faculty, at a level of its own
            SELECT p.code, p.name, p.dept_code, p.faculty_code, p.archived, p.category, d.faculty_code AS dept_faculty INTO t
              FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = v_prog;
            IF v_prog = '' THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_MISSING', 'text', 'Give the programme code the student comes into');
            ELSIF t.code IS NULL THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_UNKNOWN', 'text', v_prog || ' is not a programme on the register (no programme is created by an upload)');
            ELSE
                IF coalesce(t.archived, false) THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_ARCHIVED', 'text', t.name || ' is archived');
                END IF;
                IF t.category IS DISTINCT FROM 'UNDER GRADUATE' THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_CATEGORY', 'text', t.name || ' is not an undergraduate programme; a postgraduate student is admitted by the School of Postgraduate Studies');
                END IF;
                IF v_dept IS DISTINCT FROM upper(coalesce(t.dept_code, '')) THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_DEPARTMENT', 'text', t.name || ' belongs to department ' || coalesce(t.dept_code, '—') || ', not ' || coalesce(nullif(v_dept, ''), '—'));
                END IF;
                IF v_fac IS DISTINCT FROM upper(coalesce(t.faculty_code, '')) OR upper(coalesce(t.dept_faculty, t.faculty_code, '')) IS DISTINCT FROM upper(coalesce(t.faculty_code, '')) THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_FACULTY', 'text', 'Department ' || coalesce(t.dept_code, '—') || ' belongs to faculty ' || coalesce(t.faculty_code, '—') || ', not ' || coalesce(nullif(v_fac, ''), '—'));
                END IF;
                IF v_level IS NULL OR NOT (v_level = ANY (people.programme_levels(t.code))) THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'TARGET_LEVEL', 'text', t.name || ' has the levels ' || coalesce(array_to_string(people.programme_levels(t.code), ', '), 'none') || '; ' || coalesce(v_level::text, 'none given') || ' is not among them');
                END IF;
            END IF;
            -- the identity searched first: a record on the register is that student; an applicant is linked; else a new record
            IF s.id IS NOT NULL THEN
                IF NOT (s.status = ANY (v_live)) THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'STUDENT_EXISTS_CLOSED', 'text', s.surname || ', ' || s.other_names || ' is on the register already, '
                        || lower(replace(s.status, '_', ' ')) || '; a closed record is taken up again by the Registry, never made a second time');
                ELSIF s.programme_code IS DISTINCT FROM t.code OR s.current_level IS DISTINCT FROM v_level THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'STUDENT_EXISTS', 'text', s.surname || ', ' || s.other_names || ' is on the register already ('
                        || coalesce(s.programme_code, '—') || ', ' || coalesce(s.current_level::text, '—') || ' Level); no second record is made — a change of placement is a programme swap');
                ELSE
                    v_action := 'RECORD_ON_EXISTING';
                    v_warn := v_warn || jsonb_build_object('code', 'STUDENT_EXISTS', 'text', 'On the register already on that placement (entry ' || lower(replace(s.entry_mode, '_', ' '))
                        || '): the transfer is recorded on that record and no record is made');
                END IF;
            ELSE
                IF v_jamb <> '' THEN
                    SELECT k.id, k.session, k.offer_state, k.programme INTO v_cand, v_cand_session, v_cand_offer, v_cand_prog FROM admissions.candidate k
                     WHERE upper(k.jamb_reg_no) = v_jamb ORDER BY k.session DESC LIMIT 1;
                END IF;
                v_action := CASE WHEN v_cand IS NOT NULL THEN 'CREATE_FROM_APPLICANT' ELSE 'CREATE' END;
                IF v_cand IS NOT NULL THEN
                    v_warn := v_warn || jsonb_build_object('code', 'APPLICANT_LINKED', 'text', 'An applicant under the JAMB number (' || v_cand_session || ', ' || coalesce(v_cand_prog, '—')
                        || ', ' || lower(coalesce(v_cand_offer, 'no offer')) || ') is linked to the new record, never duplicated');
                END IF;
                v_surname := coalesce(people.transfer_cell(r.row, 'surname', 'Surname'), btrim(split_part(coalesce(v_name, ''), ',', 1)));
                v_others := coalesce(people.transfer_cell(r.row, 'other_names', 'Other Names'),
                                     btrim(substr(coalesce(v_name, ''), length(split_part(coalesce(v_name, ''), ',', 1)) + 2)));
                IF coalesce(v_surname, '') = '' OR coalesce(v_others, '') = '' THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'NAME', 'text', 'Give the student''s name as SURNAME, Other names');
                END IF;
                v_sex := upper(coalesce(people.transfer_cell(r.row, 'sex', 'Sex', 'Gender'), ''));
                IF v_sex <> '' AND v_sex NOT IN ('M', 'F', 'MALE', 'FEMALE') THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'SEX', 'text', 'Sex is M or F (' || v_sex || ' given)');
                END IF;
                v_dob := people.transfer_cell(r.row, 'date_of_birth', 'Date of Birth');
                IF v_dob IS NOT NULL AND (v_dob !~ '^\d{4}-\d{2}-\d{2}$' OR to_char(to_date(v_dob, 'YYYY-MM-DD'), 'YYYY-MM-DD') <> v_dob) THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'DATE_OF_BIRTH', 'text', 'The date of birth is written YYYY-MM-DD (' || v_dob || ' given)');
                END IF;
                v_email := lower(people.transfer_cell(r.row, 'email', 'Email', 'E-mail'));
                IF v_email IS NOT NULL AND v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'EMAIL', 'text', v_email || ' is not an e-mail address');
                END IF;
                v_phone := people.contact_phone(people.transfer_cell(r.row, 'phone', 'Phone', 'Phone Number'));
                IF v_phone IS NOT NULL AND v_phone !~ '^0[0-9]{10}$' THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'PHONE', 'text', people.transfer_cell(r.row, 'phone', 'Phone', 'Phone Number') || ' is not a Nigerian phone number (11 digits from 0)');
                END IF;
            END IF;
        END IF;
        v_out := v_out || jsonb_build_array(jsonb_build_object(
            'row', r.n, 'direction', v_dir, 'action', v_action,
            'status', CASE WHEN jsonb_array_length(v_msgs) > 0 THEN 'INVALID' WHEN jsonb_array_length(v_warn) > 0 THEN 'WARNING' ELSE 'VALID' END,
            'studentId', s.id, 'candidateId', v_cand, 'matchedBy', v_matched,
            'student', coalesce(CASE WHEN s.id IS NOT NULL THEN s.surname || ', ' || s.other_names END, v_name,
                                CASE WHEN v_surname IS NOT NULL THEN v_surname || ', ' || v_others END),
            'matricNo', s.matric_no, 'jambRegNo', coalesce(nullif(v_jamb, ''), s.jamb_reg_no),
            'surname', v_surname, 'otherNames', v_others,
            'sex', CASE WHEN v_sex IN ('M', 'MALE') THEN 'M' WHEN v_sex IN ('F', 'FEMALE') THEN 'F' END,
            'dateOfBirth', v_dob, 'email', v_email, 'phone', v_phone,
            'current', CASE WHEN s.id IS NOT NULL THEN jsonb_build_object('faculty', s.faculty_code, 'dept', s.dept_code, 'programme', s.programme_code, 'level', s.current_level, 'status', s.status) END,
            'university', nullif(v_univ, ''), 'universityName', (SELECT u.name FROM ref.university u WHERE u.code = v_univ),
            'otherProgramme', people.transfer_cell(r.row, 'other_programme', 'Other University Programme', 'Previous Programme', 'Destination Programme'),
            'otherLevel', nullif(left(regexp_replace(coalesce(people.transfer_cell(r.row, 'other_level', 'Other University Level', 'Previous Level'), ''), '[^0-9]', '', 'g'), 4), ''),
            'placement', jsonb_build_object('faculty', nullif(v_fac, ''), 'dept', nullif(v_dept, ''), 'programme', nullif(v_prog, ''), 'level', v_level,
                                            'programmeName', (SELECT p.name FROM ref.programme p WHERE p.code = v_prog)),
            'session', v_session, 'reason', people.transfer_cell(r.row, 'reason', 'Reason'),
            'problems', v_msgs, 'warnings', v_warn));
    END LOOP;
    -- the same student, or the same JAMB number, on two rows or more: every row of theirs refused, the rows named
    SELECT coalesce(jsonb_agg(CASE WHEN d.n > 1
                    THEN o.value || jsonb_build_object('status', 'INVALID', 'problems', (o.value->'problems') || jsonb_build_array(jsonb_build_object(
                         'code', 'DUPLICATE_ROW', 'text', 'The student is on rows ' || d.rows || ' of the file; keep one row')))
                    ELSE o.value END ORDER BY (o.value->>'row')::int), '[]')
      INTO v_out
      FROM jsonb_array_elements(v_out) o
      LEFT JOIN (SELECT coalesce(x->>'studentId', upper(x->>'jambRegNo')) AS k, count(*) AS n, string_agg(x->>'row', ', ' ORDER BY (x->>'row')::int) AS rows
                   FROM jsonb_array_elements(v_out) x WHERE coalesce(x->>'studentId', x->>'jambRegNo') IS NOT NULL GROUP BY 1) d
        ON d.k = coalesce(o.value->>'studentId', upper(o.value->>'jambRegNo'));
    RETURN v_out;
END $fn$;
COMMENT ON FUNCTION people.university_transfer_check(jsonb, text, uuid) IS
  'V588: each row of a bulk inter-university transfer checked — OUTGOING: the student found (matriculation, former, JAMB number; never the name), live, on the placement stated, nothing under way; INCOMING: the identity searched first (a live record on the target placement is that student, another is refused, an applicant is linked, else a new record at the decision), the target an undergraduate programme in its department and faculty at a level of its own; the other university on the list; the same student on two rows refused. p_except leaves one transfer out of the pending test (its own decision).';

-- ── 4 · prepared; decided ───────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.prepare_university_transfers(p_rows jsonb, p_session text, p_reason text, p_approval_ref text, p_filename text, p_partial boolean)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_checked jsonb; v_bad int; v_id uuid := gen_random_uuid(); v_ref text; x jsonb; v_n int := 0; v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
        v_session text := coalesce(nullif(btrim(coalesce(p_session, '')), ''), policy.university_current_session());
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'UNIVERSITY_TRANSFER_ACTOR: a transfer is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_OFFICE: an inter-university transfer is prepared by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_REASON: say why (the Senate''s approval, the University''s transfer policy), ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_EMPTY: the file has no rows' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_rows) > 1000 THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_TOO_MANY: up to 1,000 rows at a time (% given)', jsonb_array_length(p_rows) USING ERRCODE = '23514';
    END IF;
    v_checked := people.university_transfer_check(p_rows, v_session);
    v_bad := (SELECT count(*) FROM jsonb_array_elements(v_checked) c WHERE c->>'status' = 'INVALID');
    IF v_bad > 0 AND NOT coalesce(p_partial, false) THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_INVALID: % of the % rows are invalid; correct them and upload the file again, or prepare the valid rows alone', v_bad, jsonb_array_length(p_rows)
            USING ERRCODE = '23514';
    END IF;
    IF v_bad = jsonb_array_length(p_rows) THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_NONE_VALID: none of the % rows is valid', v_bad USING ERRCODE = '23514';
    END IF;
    v_ref := 'IUT/' || v_year || '/' || lpad(platform.next_number('INTER_UNIVERSITY_TRANSFER', 'UNIVERSITY', v_year)::text, 6, '0');
    INSERT INTO people.university_transfer_batch (id, ref, effective_session, filename, reason, approval_ref, partial, total, left_out, prepared_by, prepared_office)
    VALUES (v_id, v_ref, v_session, nullif(btrim(coalesce(p_filename, '')), ''), btrim(p_reason), nullif(btrim(coalesce(p_approval_ref, '')), ''),
            v_bad > 0, jsonb_array_length(p_rows), v_bad, who, office);
    FOR x IN SELECT c.value FROM jsonb_array_elements(v_checked) c ORDER BY (c.value->>'row')::int LOOP
        IF x->>'status' = 'INVALID' THEN
            INSERT INTO people.university_transfer_left_out (batch_id, row_no, uploaded, messages)
            VALUES (v_id, (x->>'row')::int, p_rows -> ((x->>'row')::int - 1), x->'problems');
            CONTINUE;
        END IF;
        INSERT INTO people.university_transfer (batch_id, row_no, direction, uploaded, student_id, candidate_id, jamb_reg_no, matched_by, university_code,
                                                other_programme, other_level, programme_code, level, effective_session, reason, prepared_by, prepared_office)
        VALUES (v_id, (x->>'row')::int, x->>'direction', p_rows -> ((x->>'row')::int - 1), (x->>'studentId')::uuid, (x->>'candidateId')::uuid,
                x->>'jambRegNo', x->>'matchedBy', x->>'university', x->>'otherProgramme', (x->>'otherLevel')::int,
                x->'placement'->>'programme', (x->'placement'->>'level')::int, x->>'session', x->>'reason', who, office);
        v_n := v_n + 1;
    END LOOP;
    UPDATE people.university_transfer_batch SET prepared = v_n WHERE id = v_id;
    RETURN jsonb_build_object('id', v_id, 'ref', v_ref, 'total', jsonb_array_length(p_rows), 'prepared', v_n, 'invalid', v_bad);
END $fn$;
COMMENT ON FUNCTION people.prepare_university_transfers(jsonb, text, text, text, text, boolean) IS
  'V588: a bulk inter-university transfer prepared (IUT/YYYY/NNNNNN) — the rows checked again, each valid row a transfer awaiting another officer''s decision, each invalid row kept with why; refused while a row is invalid unless the valid rows alone are asked for; nothing on any record changes yet.';

CREATE FUNCTION people.decide_university_transfer(p_id uuid, p_approve boolean, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        m people.university_transfer; b people.university_transfer_batch; chk jsonb; v_student uuid; v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_uname text; v_adm text; v_tries int := 0;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'UNIVERSITY_TRANSFER_ACTOR: a transfer is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO m FROM people.university_transfer WHERE id = p_id FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'UNIVERSITY_TRANSFER_UNKNOWN: no such transfer' USING ERRCODE = '23514'; END IF;
    IF m.status <> 'PENDING_APPROVAL' THEN RAISE EXCEPTION 'UNIVERSITY_TRANSFER_DECIDED: the transfer is % already', lower(m.status) USING ERRCODE = '23514'; END IF;
    IF coalesce(office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_DECIDER: an inter-university transfer is decided by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF m.prepared_by = who THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_SAME_OFFICER: the officer who prepared a transfer does not decide it' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO b FROM people.university_transfer_batch WHERE id = m.batch_id;
    IF NOT coalesce(p_approve, false) THEN
        IF length(coalesce(v_note, '')) < 10 THEN RAISE EXCEPTION 'UNIVERSITY_TRANSFER_NOTE: say why the transfer is rejected, ten characters or more' USING ERRCODE = '23514'; END IF;
        UPDATE people.university_transfer SET status = 'REJECTED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note WHERE id = m.id;
        RETURN jsonb_build_object('id', m.id, 'status', 'REJECTED', 'direction', m.direction);
    END IF;
    -- checked again on the records as they stand now (this transfer left out of its own pending test)
    chk := people.university_transfer_check(jsonb_build_array(m.uploaded), m.effective_session, m.id) -> 0;
    IF chk->>'status' = 'INVALID' THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_STALE: %', chk->'problems'->0->>'text' USING ERRCODE = '23514';
    END IF;
    IF chk->>'direction' IS DISTINCT FROM m.direction THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_STALE: the row reads % now', chk->>'direction' USING ERRCODE = '23514';
    END IF;
    v_uname := (SELECT u.name FROM ref.university u WHERE u.code = m.university_code);
    IF m.direction = 'OUTGOING' THEN
        v_student := (chk->>'studentId')::uuid;
        PERFORM people.change_status(v_student, 'TRANSFERRED_OUT', b.ref || coalesce(' (' || b.approval_ref || ')', ''), (now() AT TIME ZONE 'Africa/Lagos')::date,
            'Transferred to ' || v_uname || coalesce(' (' || m.other_programme || ')', '') || '. ' || b.reason);
    ELSIF chk->>'action' = 'RECORD_ON_EXISTING' THEN
        v_student := (chk->>'studentId')::uuid;
    ELSE
        -- a record made as an admitted student's is: an admission number (drawn until free: records imported with their numbers may
        -- hold some of the series), ADMITTED, entry by TRANSFER at the target level
        LOOP
            v_adm := 'MOAUM/ADM/' || substr(m.effective_session, 3, 2) || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', m.effective_session)::text, 6, '0');
            EXIT WHEN NOT EXISTS (SELECT 1 FROM people.student x WHERE x.admission_no = v_adm);
            v_tries := v_tries + 1;
            IF v_tries >= 500 THEN
                RAISE EXCEPTION 'UNIVERSITY_TRANSFER_ADMISSION_NUMBER: no free admission number in the % series after 500 draws', m.effective_session USING ERRCODE = '23514';
            END IF;
        END LOOP;
        INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names, sex, date_of_birth,
                                    programme_code, entry_mode, entry_session, entry_level, current_level, status, study_mode)
        VALUES (gen_random_uuid(), (chk->>'candidateId')::uuid,
                v_adm, chk->>'jambRegNo', upper(btrim(chk->>'surname')), btrim(chk->>'otherNames'), chk->>'sex', (chk->>'dateOfBirth')::date,
                m.programme_code, 'TRANSFER', m.effective_session, m.level, m.level, 'ADMITTED', 'FULL_TIME')
        RETURNING id INTO v_student;
        IF chk->>'email' IS NOT NULL OR chk->>'phone' IS NOT NULL THEN
            INSERT INTO people.student_contact (student_id, phone, email, updated_at)
            VALUES (v_student, chk->>'phone', chk->>'email', now())
            ON CONFLICT (student_id) DO NOTHING;
        END IF;
        PERFORM people.default_nationality(v_student);
    END IF;
    UPDATE people.university_transfer
       SET status = 'COMPLETED', student_id = v_student, candidate_id = coalesce((chk->>'candidateId')::uuid, candidate_id),
           created_student = (m.direction = 'INCOMING' AND chk->>'action' <> 'RECORD_ON_EXISTING'),
           decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note
     WHERE id = m.id;
    RETURN jsonb_build_object('id', m.id, 'status', 'COMPLETED', 'studentId', v_student, 'direction', m.direction, 'action', chk->>'action');
END $fn$;
COMMENT ON FUNCTION people.decide_university_transfer(uuid, boolean, text) IS
  'V588: a transfer decided by another officer of the Academic Office or the Registry — rejected with a note, or approved after a last check: INCOMING, the record made as an admitted student''s is (entry by TRANSFER, the applicant linked) or the existing one named; OUTGOING, TRANSFERRED_OUT on the batch''s instrument with the record kept.';

/* a batch decided transfer by transfer: one its record refuses is said with why and the others are decided */
CREATE FUNCTION people.decide_university_transfer_batch(p_batch uuid, p_approve boolean, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE x record; v_done jsonb := '[]'; v_skipped jsonb := '[]'; v_msg text; v_state text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM people.university_transfer_batch b WHERE b.id = p_batch) THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_UNKNOWN: no such batch' USING ERRCODE = '23514';
    END IF;
    FOR x IN SELECT t.id, t.row_no FROM people.university_transfer t WHERE t.batch_id = p_batch AND t.status = 'PENDING_APPROVAL' ORDER BY t.row_no LOOP
        BEGIN
            v_done := v_done || jsonb_build_array(people.decide_university_transfer(x.id, p_approve, p_note) || jsonb_build_object('row', x.row_no));
        EXCEPTION WHEN check_violation OR insufficient_privilege OR unique_violation OR foreign_key_violation THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
            -- the office or the officer is refused for the whole batch, not row by row
            IF v_state = '42501' THEN RAISE EXCEPTION '%', v_msg USING ERRCODE = '42501'; END IF;
            IF v_msg ~ '^UNIVERSITY_TRANSFER_NOTE' THEN RAISE EXCEPTION '%', v_msg USING ERRCODE = '23514'; END IF;
            v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('row', x.row_no, 'id', x.id, 'why', regexp_replace(v_msg, '^[A-Z_]+: ', '')));
        END;
    END LOOP;
    RETURN jsonb_build_object('decided', v_done, 'skipped', v_skipped);
END $fn$;
COMMENT ON FUNCTION people.decide_university_transfer_batch(uuid, boolean, text) IS
  'V588: every transfer of a batch awaiting a decision decided in one go, each on its own: one its record refuses now is said with why and left awaiting; the office, the officer and a rejection''s note are refused for the whole batch.';

-- ── 5 · reading ─────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.university_transfer_batches(p_limit int DEFAULT 200)
RETURNS TABLE (id uuid, ref text, effective_session text, filename text, reason text, approval_ref text, total int, prepared int, left_out int,
               incoming bigint, outgoing bigint, pending bigint, completed bigint, rejected bigint, prepared_by uuid, prepared_by_name text, prepared_office text,
               prepared_at timestamptz, status text)
LANGUAGE sql STABLE AS $fn$
    SELECT b.id, b.ref, b.effective_session, b.filename, b.reason, b.approval_ref, b.total, b.prepared, b.left_out,
           count(t.id) FILTER (WHERE t.direction = 'INCOMING'), count(t.id) FILTER (WHERE t.direction = 'OUTGOING'),
           count(t.id) FILTER (WHERE t.status = 'PENDING_APPROVAL'), count(t.id) FILTER (WHERE t.status = 'COMPLETED'), count(t.id) FILTER (WHERE t.status = 'REJECTED'),
           b.prepared_by, people.officer_name(b.prepared_by), b.prepared_office, b.prepared_at,
           CASE WHEN count(t.id) = 0 THEN 'NOTHING_PREPARED'
                WHEN count(t.id) FILTER (WHERE t.status = 'PENDING_APPROVAL') = count(t.id) THEN 'PENDING_APPROVAL'
                WHEN count(t.id) FILTER (WHERE t.status = 'PENDING_APPROVAL') > 0 THEN 'PARTLY_DECIDED'
                WHEN count(t.id) FILTER (WHERE t.status = 'COMPLETED') = count(t.id) AND b.left_out = 0 THEN 'COMPLETED'
                WHEN count(t.id) FILTER (WHERE t.status = 'COMPLETED') > 0 THEN 'COMPLETED_WITH_EXCEPTIONS'
                ELSE 'REJECTED' END
      FROM people.university_transfer_batch b LEFT JOIN people.university_transfer t ON t.batch_id = b.id
     GROUP BY b.id
     ORDER BY b.prepared_at DESC
     LIMIT greatest(1, least(coalesce(p_limit, 200), 2000))
$fn$;

/* the transfers of a batch, of a student, or matching a reference, number, name or university */
CREATE FUNCTION people.university_transfers(p_batch uuid DEFAULT NULL, p_student uuid DEFAULT NULL, p_q text DEFAULT NULL, p_direction text DEFAULT NULL, p_limit int DEFAULT 1000)
RETURNS TABLE (id uuid, batch_id uuid, batch_ref text, row_no int, direction text, status text, student_id uuid, student text, matric_no text, jamb_reg_no text,
               university_code text, university text, other_programme text, other_level int, programme_code text, programme text, level int,
               effective_session text, created_student boolean, matched_by text, prepared_by_name text, prepared_at timestamptz, decided_by_name text,
               decided_at timestamptz, decision_note text)
LANGUAGE sql STABLE AS $fn$
    SELECT t.id, t.batch_id, b.ref, t.row_no, t.direction, t.status, t.student_id,
           coalesce(s.surname || ', ' || s.other_names, people.transfer_cell(t.uploaded, 'student', 'Student Name', 'Name'),
                    people.transfer_cell(t.uploaded, 'surname', 'Surname') || ', ' || people.transfer_cell(t.uploaded, 'other_names', 'Other Names')),
           s.matric_no, coalesce(s.jamb_reg_no, t.jamb_reg_no), t.university_code, u.name, t.other_programme, t.other_level,
           t.programme_code, p.name, t.level, t.effective_session, t.created_student, t.matched_by,
           people.officer_name(t.prepared_by), t.prepared_at, people.officer_name(t.decided_by), t.decided_at, t.decision_note
      FROM people.university_transfer t
      JOIN people.university_transfer_batch b ON b.id = t.batch_id
      JOIN ref.university u ON u.code = t.university_code
      LEFT JOIN people.student s ON s.id = t.student_id
      LEFT JOIN ref.programme p ON p.code = t.programme_code
     WHERE (p_batch IS NULL OR t.batch_id = p_batch) AND (p_student IS NULL OR t.student_id = p_student)
       AND (p_direction IS NULL OR t.direction = p_direction)
       AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL OR b.ref ILIKE '%' || btrim(p_q) || '%' OR s.matric_no ILIKE '%' || btrim(p_q) || '%'
            OR t.jamb_reg_no ILIKE '%' || btrim(p_q) || '%' OR (s.surname || ' ' || s.other_names) ILIKE '%' || btrim(p_q) || '%' OR u.name ILIKE '%' || btrim(p_q) || '%')
     ORDER BY t.prepared_at DESC, t.row_no
     LIMIT greatest(1, least(coalesce(p_limit, 1000), 5000))
$fn$;

-- V574 classes every column naming a programme for a merge: a transfer's placement is history, kept as it was (a pending one is
-- checked again at its decision, and an archived programme refuses it)
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('people.university_transfer', 'programme_code', 'KEEP', 'an inter-university transfer''s placement as it was; a pending one is checked again when decided')
ON CONFLICT (tab, col) DO NOTHING;

GRANT SELECT ON ref.university, people.university_transfer, people.university_transfer_batch, people.university_transfer_left_out TO app_auditor, app_reporting;

COMMIT;

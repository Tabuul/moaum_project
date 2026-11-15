-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V763 — An inter-university transfer registered on a form, one student at a time
--
--   V588 records inter-university transfers many at a time from a spreadsheet. The Academic Office and the Registry now also
--   register one student on a form (Academic Office → Inter-University Transfer Form), under the same rules and the same
--   decision by another officer:
--     · the particulars a transfer form asks for, kept on the transfer (people.university_transfer) and read from a file too when
--       its columns carry them: the student's matriculation number at the other university, and for a student coming in the
--       session they entered it and their CGPA there with its scale (4 or 5 points); the documents the officer saw (a student
--       coming in: the transcript, the letter of release, the JAMB admission letter, the O'Level result; a student going out:
--       the student's written application, the receiving university's letter of acceptance); the remarks — each checked, never
--       put right silently: a CGPA above its scale, a session entered after the transfer's, a document of the other direction
--       refused; a CGPA with no scale read on the 5-point scale and said so; a form that names the documents seen and leaves out
--       the transcript or the letter of release (coming in) or the letter of acceptance (going out) is valid, with the point
--       to look at;
--     · people.university_transfer_form_check(row, session): the row checked as V588 checks a file's, and what a form must give
--       besides: coming in, the matriculation number, programme and level at the previous university, and for a new record the
--       sex and the date of birth; going out, the programme at the receiving university;
--     · people.register_university_transfer(row, session, reason, approval ref): the form registered as a batch of one
--       (IUT/YYYY/NNNNNN, source FORM) awaiting another officer's decision — refused while the form has a problem; nothing on a
--       record changes before the decision;
--     · people.university_transfer_lookup(number, direction): the student a number finds, as the check finds them for the
--       direction — going out, the matriculation number, a former one, then the JAMB number directly or through the
--       applicant; coming in, the JAMB number alone (the form's incoming row carries no other) — the applicant under a JAMB
--       number for a student coming in, and a transfer of theirs already awaiting a decision: the form shows who it is about
--       before it is filled, and is checked only once it has;
--     · the name a row gives (the student's name, or the surname and other names) is compared with the record a number finds
--       (NAME_DIFFERS, a point to look at), on a form as on a file;
--     · the batches say whether they came from a file or a form; the transfers carry the new particulars and are found by the
--       matriculation number at the other university too; the remarks of the transfers prepared before V763 (kept with the row
--       as uploaded) are carried into the new column.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V763: an inter-university transfer registered on a form', true);

-- ── 1 · the particulars a transfer form gives ───────────────────────────────────────────────────────────────────────────
ALTER TABLE people.university_transfer
    ADD COLUMN other_matric_no     text NULL,
    ADD COLUMN other_entry_session text NULL,
    ADD COLUMN other_cgpa          numeric(3, 2) NULL,
    ADD COLUMN other_cgpa_scale    smallint NULL,
    ADD COLUMN documents           text[] NOT NULL DEFAULT '{}',
    ADD COLUMN remarks             text NULL,
    ADD CONSTRAINT ck_university_transfer_cgpa CHECK (
        (other_cgpa IS NULL) = (other_cgpa_scale IS NULL)
        AND (other_cgpa_scale IS NULL OR other_cgpa_scale IN (4, 5))
        AND (other_cgpa IS NULL OR (other_cgpa >= 0 AND other_cgpa <= other_cgpa_scale))),
    ADD CONSTRAINT ck_university_transfer_entry_session CHECK (other_entry_session IS NULL OR other_entry_session ~ '^[0-9]{4}/[0-9]{4}$'),
    ADD CONSTRAINT ck_university_transfer_documents CHECK (
        documents <@ ARRAY['TRANSCRIPT', 'RELEASE_LETTER', 'JAMB_ADMISSION_LETTER', 'OLEVEL_RESULT', 'STUDENT_APPLICATION', 'ACCEPTANCE_LETTER']::text[]);
COMMENT ON COLUMN people.university_transfer.other_matric_no IS 'V763: the student''s matriculation number at the other university';
COMMENT ON COLUMN people.university_transfer.other_entry_session IS 'V763: a student coming in — the session they entered the previous university';
COMMENT ON COLUMN people.university_transfer.other_cgpa IS 'V763: a student coming in — their CGPA at the previous university, on other_cgpa_scale';
COMMENT ON COLUMN people.university_transfer.other_cgpa_scale IS 'V763: the scale of other_cgpa: 4 or 5 points';
COMMENT ON COLUMN people.university_transfer.documents IS 'V763: the documents the officer saw — coming in: TRANSCRIPT, RELEASE_LETTER, JAMB_ADMISSION_LETTER, OLEVEL_RESULT; going out: STUDENT_APPLICATION, ACCEPTANCE_LETTER';
COMMENT ON COLUMN people.university_transfer.remarks IS 'V763: the remarks the form or the file gave';

-- the remarks a file gave before V763 were kept only with the row as uploaded: carried into the column, so every transfer says them
UPDATE people.university_transfer
   SET remarks = people.transfer_cell(uploaded, 'remarks', 'Remarks')
 WHERE remarks IS NULL AND people.transfer_cell(uploaded, 'remarks', 'Remarks') IS NOT NULL;

ALTER TABLE people.university_transfer_batch
    ADD COLUMN source text NOT NULL DEFAULT 'FILE' CHECK (source IN ('FILE', 'FORM'));
COMMENT ON COLUMN people.university_transfer_batch.source IS 'V763: FILE — prepared from a spreadsheet; FORM — one student registered on the inter-university transfer form';

-- ── 2 · the rows checked: V588's check, with the new particulars ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.university_transfer_check(p_rows jsonb, p_session text, p_except uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE r record; v_out jsonb := '[]'; v_msgs jsonb; v_warn jsonb; v_dir text; v_no text; v_jamb text; s record; v_matched text; v_univ text;
        t record; v_cand uuid; v_cand_session text; v_cand_offer text; v_cand_prog text; v_prog text; v_dept text; v_fac text; v_level int; v_session text; v_name text; v_surname text; v_others text;
        v_action text; v_sex text; v_dob text; v_email text; v_phone text;
        -- V763: the particulars a form gives
        v_omatric text; v_entry text; v_cgpa_text text; v_scale_text text; v_cgpa numeric; v_scale int; v_docs text[]; v_docs_given boolean; v_bad_docs text[];
        v_given_name text;
        v_docs_in CONSTANT text[] := ARRAY['TRANSCRIPT', 'RELEASE_LETTER', 'JAMB_ADMISSION_LETTER', 'OLEVEL_RESULT'];
        v_docs_out CONSTANT text[] := ARRAY['STUDENT_APPLICATION', 'ACCEPTANCE_LETTER'];
        v_live CONSTANT text[] := ARRAY['ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT'];
BEGIN
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RETURN '[]'; END IF;
    FOR r IN SELECT x.value AS row, x.ordinality::int AS n FROM jsonb_array_elements(p_rows) WITH ORDINALITY x LOOP
        v_msgs := '[]'; v_warn := '[]'; v_matched := NULL; v_action := NULL; v_cand := NULL; v_surname := NULL; v_others := NULL;
        v_sex := NULL; v_dob := NULL; v_email := NULL; v_phone := NULL;
        v_cgpa := NULL; v_scale := NULL;
        v_dir := upper(coalesce(people.transfer_cell(r.row, 'direction', 'Transfer Direction', 'Direction'), ''));
        v_dir := CASE WHEN v_dir IN ('IN', 'INCOMING') THEN 'INCOMING' WHEN v_dir IN ('OUT', 'OUTGOING') THEN 'OUTGOING' END;
        v_no := upper(regexp_replace(coalesce(people.transfer_cell(r.row, 'matric_no', 'Student Matriculation Number', 'Matriculation Number', 'Matric No'), ''), '\s+', '', 'g'));
        v_jamb := upper(regexp_replace(coalesce(people.transfer_cell(r.row, 'jamb_reg_no', 'JAMB Number', 'JAMB Registration Number'), ''), '\s+', '', 'g'));
        v_name := people.transfer_cell(r.row, 'student', 'Student Name', 'Name');
        -- V763: the name compared with a record the number finds — the student's name, or (a form's) the surname and other names
        v_given_name := coalesce(v_name, nullif(btrim(coalesce(people.transfer_cell(r.row, 'surname', 'Surname'), '') || ' '
                                                      || coalesce(people.transfer_cell(r.row, 'other_names', 'Other Names'), '')), ''));
        v_session := coalesce(people.transfer_cell(r.row, 'effective_session', 'Effective Session'), nullif(btrim(coalesce(p_session, '')), ''), policy.university_current_session());
        v_univ := upper(btrim(coalesce(people.transfer_cell(r.row, 'university_code', 'University Code', 'Previous University Code', 'Destination University Code'), '')));
        v_prog := upper(coalesce(people.transfer_cell(r.row, 'programme', 'Programme Code', 'Current/Target Programme Code'), ''));
        v_dept := upper(coalesce(people.transfer_cell(r.row, 'dept', 'Department Code', 'Current/Target Department Code'), ''));
        v_fac := upper(coalesce(people.transfer_cell(r.row, 'faculty', 'Faculty Code', 'Current/Target Faculty Code'), ''));
        BEGIN
            v_level := nullif(regexp_replace(coalesce(people.transfer_cell(r.row, 'level', 'Level', 'Current/Target Level'), ''), '[^0-9]', '', 'g'), '')::int;
        EXCEPTION WHEN OTHERS THEN v_level := NULL; END;
        -- V763: the matriculation number there, the session entered there, the CGPA there and its scale, the documents seen
        v_omatric := nullif(upper(regexp_replace(coalesce(people.transfer_cell(r.row, 'other_matric_no', 'Other University Matriculation Number',
                                                                                'Previous Matriculation Number'), ''), '\s+', '', 'g')), '');
        v_entry := nullif(regexp_replace(coalesce(people.transfer_cell(r.row, 'other_entry_session', 'Other University Entry Session', 'Session Entered'), ''), '\s+', '', 'g'), '');
        v_cgpa_text := people.transfer_cell(r.row, 'other_cgpa', 'Other University CGPA', 'CGPA');
        v_scale_text := people.transfer_cell(r.row, 'other_cgpa_scale', 'CGPA Scale');
        IF jsonb_typeof(r.row -> 'documents') = 'array' THEN
            v_docs_given := true;
            v_docs := ARRAY(SELECT DISTINCT upper(btrim(d)) FROM jsonb_array_elements_text(r.row -> 'documents') d WHERE btrim(d) <> '');
        ELSE
            v_docs_given := people.transfer_cell(r.row, 'documents', 'Documents Seen') IS NOT NULL;
            v_docs := ARRAY(SELECT DISTINCT upper(btrim(d)) FROM regexp_split_to_table(coalesce(people.transfer_cell(r.row, 'documents', 'Documents Seen'), ''), '[,;]') d
                             WHERE btrim(d) <> '');
        END IF;

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
        IF s.id IS NOT NULL AND v_given_name IS NOT NULL AND position(upper(btrim(s.surname)) IN upper(v_given_name)) = 0 THEN
            v_warn := v_warn || jsonb_build_object('code', 'NAME_DIFFERS', 'text', 'The name given (' || v_given_name || ') does not carry the surname on the record (' || s.surname || ')');
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

        -- V763: the particulars a form gives, checked when given; never put right silently
        IF v_omatric IS NOT NULL AND (length(v_omatric) > 40 OR v_omatric !~ '^[A-Z0-9][A-Z0-9/._-]*$') THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'OTHER_MATRIC', 'text', v_omatric || ' is not a matriculation number (letters, digits and / . - _, up to 40)');
        END IF;
        IF v_dir = 'OUTGOING' AND (v_entry IS NOT NULL OR v_cgpa_text IS NOT NULL OR v_scale_text IS NOT NULL) THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'OUTGOING_PARTICULARS', 'text',
                'The session entered and the CGPA are a student''s coming in from the previous university; leave them blank for a student going out');
        END IF;
        IF v_dir IS DISTINCT FROM 'OUTGOING' AND v_entry IS NOT NULL THEN
            IF v_entry !~ '^[0-9]{4}/[0-9]{4}$' OR split_part(v_entry, '/', 2)::int <> split_part(v_entry, '/', 1)::int + 1 THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'ENTRY_SESSION', 'text', 'The session entered at the previous university is written 2022/2023 (' || v_entry || ' given)');
            ELSIF v_session ~ '^[0-9]{4}/' AND split_part(v_entry, '/', 1)::int > split_part(v_session, '/', 1)::int THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'ENTRY_SESSION', 'text', 'The session entered at the previous university (' || v_entry || ') is after the transfer''s (' || v_session || ')');
            END IF;
        END IF;
        IF v_dir IS DISTINCT FROM 'OUTGOING' AND (v_cgpa_text IS NOT NULL OR v_scale_text IS NOT NULL) THEN
            IF v_scale_text IS NOT NULL AND btrim(v_scale_text) !~ '^[45](\.0+)?$' THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'CGPA_SCALE', 'text', 'The CGPA scale is 4 or 5 points (' || v_scale_text || ' given)');
            ELSIF v_cgpa_text IS NULL THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'CGPA', 'text', 'A CGPA scale was given with no CGPA');
            ELSIF btrim(v_cgpa_text) !~ '^[0-9](\.[0-9]{1,2})?$' THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'CGPA', 'text', 'The CGPA is a number with up to two decimals, such as 3.45 (' || v_cgpa_text || ' given)');
            ELSE
                v_cgpa := btrim(v_cgpa_text)::numeric;
                v_scale := coalesce(left(btrim(v_scale_text), 1)::int, 5);
                IF v_scale_text IS NULL THEN
                    v_warn := v_warn || jsonb_build_object('code', 'CGPA_SCALE_ASSUMED', 'text', 'No CGPA scale was given; ' || v_cgpa_text || ' is read on the 5-point scale');
                END IF;
                IF v_cgpa > v_scale THEN
                    v_msgs := v_msgs || jsonb_build_object('code', 'CGPA', 'text', 'A CGPA of ' || v_cgpa_text || ' is above the ' || v_scale || '-point scale');
                    v_cgpa := NULL; v_scale := NULL;
                END IF;
            END IF;
        END IF;
        v_bad_docs := ARRAY(SELECT d FROM unnest(v_docs) d WHERE NOT (d = ANY (v_docs_in || v_docs_out)));
        IF cardinality(v_bad_docs) > 0 THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'DOCUMENTS', 'text', array_to_string(v_bad_docs, ', ') || ' is not a document of the form''s list');
        ELSIF v_dir = 'INCOMING' AND v_docs && v_docs_out THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'DOCUMENTS', 'text', array_to_string(ARRAY(SELECT d FROM unnest(v_docs) d WHERE d = ANY (v_docs_out)), ', ') || ' is a student going out''s document');
        ELSIF v_dir = 'OUTGOING' AND v_docs && v_docs_in THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'DOCUMENTS', 'text', array_to_string(ARRAY(SELECT d FROM unnest(v_docs) d WHERE d = ANY (v_docs_in)), ', ') || ' is a student coming in''s document');
        END IF;
        -- the documents named and one that matters left out: valid, with the point to look at
        IF v_docs_given AND v_dir = 'INCOMING' THEN
            IF NOT ('TRANSCRIPT' = ANY (v_docs)) THEN
                v_warn := v_warn || jsonb_build_object('code', 'TRANSCRIPT_NOT_SEEN', 'text', 'The transcript from the previous university was not seen');
            END IF;
            IF NOT ('RELEASE_LETTER' = ANY (v_docs)) THEN
                v_warn := v_warn || jsonb_build_object('code', 'RELEASE_LETTER_NOT_SEEN', 'text', 'The previous university''s letter of release was not seen');
            END IF;
        ELSIF v_docs_given AND v_dir = 'OUTGOING' AND NOT ('ACCEPTANCE_LETTER' = ANY (v_docs)) THEN
            v_warn := v_warn || jsonb_build_object('code', 'ACCEPTANCE_LETTER_NOT_SEEN', 'text', 'The receiving university''s letter of acceptance was not seen');
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
            'otherMatricNo', v_omatric,
            'otherEntrySession', CASE WHEN v_dir IS DISTINCT FROM 'OUTGOING' THEN v_entry END,
            'otherCgpa', v_cgpa, 'otherCgpaScale', CASE WHEN v_cgpa IS NOT NULL THEN v_scale END,
            'documents', to_jsonb(ARRAY(SELECT d FROM unnest(v_docs_in || v_docs_out) WITH ORDINALITY o(d, k) WHERE d = ANY (v_docs) ORDER BY k)),
            'remarks', people.transfer_cell(r.row, 'remarks', 'Remarks'),
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
  'V588, V763: each row of an inter-university transfer checked — OUTGOING: the student found (matriculation, former, JAMB number; never the name), live, on the placement stated, nothing under way; INCOMING: the identity searched first (a live record on the target placement is that student, another is refused, an applicant is linked, else a new record at the decision), the target an undergraduate programme in its department and faculty at a level of its own; the other university on the list; the same student on two rows refused; V763: the matriculation number at the other university, the session entered and the CGPA there (a student coming in), the documents seen (of the row''s direction) and the remarks, checked when given. p_except leaves one transfer out of the pending test (its own decision).';

-- ── 3 · prepared: V588's, the new particulars kept on the transfer ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.prepare_university_transfers(p_rows jsonb, p_session text, p_reason text, p_approval_ref text, p_filename text, p_partial boolean)
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
                                                other_programme, other_level, programme_code, level, effective_session, reason, prepared_by, prepared_office,
                                                other_matric_no, other_entry_session, other_cgpa, other_cgpa_scale, documents, remarks)
        VALUES (v_id, (x->>'row')::int, x->>'direction', p_rows -> ((x->>'row')::int - 1), (x->>'studentId')::uuid, (x->>'candidateId')::uuid,
                x->>'jambRegNo', x->>'matchedBy', x->>'university', x->>'otherProgramme', (x->>'otherLevel')::int,
                x->'placement'->>'programme', (x->'placement'->>'level')::int, x->>'session', x->>'reason', who, office,
                x->>'otherMatricNo', x->>'otherEntrySession', (x->>'otherCgpa')::numeric, (x->>'otherCgpaScale')::smallint,
                ARRAY(SELECT jsonb_array_elements_text(coalesce(x->'documents', '[]'))), x->>'remarks');
        v_n := v_n + 1;
    END LOOP;
    UPDATE people.university_transfer_batch SET prepared = v_n WHERE id = v_id;
    RETURN jsonb_build_object('id', v_id, 'ref', v_ref, 'total', jsonb_array_length(p_rows), 'prepared', v_n, 'invalid', v_bad);
END $fn$;
COMMENT ON FUNCTION people.prepare_university_transfers(jsonb, text, text, text, text, boolean) IS
  'V588, V763: an inter-university transfer batch prepared (IUT/YYYY/NNNNNN) — the rows checked again, each valid row a transfer awaiting another officer''s decision with the particulars it gives, each invalid row kept with why; refused while a row is invalid unless the valid rows alone are asked for; nothing on any record changes yet.';

-- ── 4 · the form: checked, registered ───────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.university_transfer_form_check(p_row jsonb, p_session text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE c jsonb; v_msgs jsonb;
BEGIN
    IF p_row IS NULL OR jsonb_typeof(p_row) <> 'object' THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_FORM_EMPTY: the form is empty' USING ERRCODE = '23514';
    END IF;
    c := people.university_transfer_check(jsonb_build_array(p_row), p_session) -> 0;
    v_msgs := c -> 'problems';
    -- what a form must give besides what a file's row must
    IF c->>'direction' = 'INCOMING' THEN
        IF c->>'otherMatricNo' IS NULL THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'OTHER_MATRIC_MISSING', 'text', 'Give the student''s matriculation number at the previous university');
        END IF;
        IF c->>'otherProgramme' IS NULL THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'OTHER_PROGRAMME_MISSING', 'text', 'Give the programme the student studied at the previous university');
        END IF;
        IF c->>'otherLevel' IS NULL THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'OTHER_LEVEL_MISSING', 'text', 'Give the level the student reached at the previous university');
        END IF;
        IF c->>'action' IN ('CREATE', 'CREATE_FROM_APPLICANT') THEN
            IF c->>'sex' IS NULL AND NOT (v_msgs @> '[{"code": "SEX"}]') THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'SEX_MISSING', 'text', 'Give the student''s sex: a record is made for them');
            END IF;
            IF c->>'dateOfBirth' IS NULL THEN
                v_msgs := v_msgs || jsonb_build_object('code', 'DATE_OF_BIRTH_MISSING', 'text', 'Give the student''s date of birth: a record is made for them');
            END IF;
        END IF;
    ELSIF c->>'direction' = 'OUTGOING' THEN
        IF c->>'otherProgramme' IS NULL THEN
            v_msgs := v_msgs || jsonb_build_object('code', 'OTHER_PROGRAMME_MISSING', 'text', 'Give the programme the student goes into at the receiving university');
        END IF;
    END IF;
    RETURN c || jsonb_build_object('problems', v_msgs,
        'status', CASE WHEN jsonb_array_length(v_msgs) > 0 THEN 'INVALID' WHEN jsonb_array_length(c -> 'warnings') > 0 THEN 'WARNING' ELSE 'VALID' END);
END $fn$;
COMMENT ON FUNCTION people.university_transfer_form_check(jsonb, text) IS
  'V763: the inter-university transfer form checked — the row as V588 checks a file''s, and what a form must give besides: coming in, the matriculation number, programme and level at the previous university, and the sex and date of birth for a new record; going out, the programme at the receiving university.';

CREATE FUNCTION people.register_university_transfer(p_row jsonb, p_session text, p_reason text, p_approval_ref text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        c jsonb; made jsonb;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'UNIVERSITY_TRANSFER_ACTOR: a transfer is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_OFFICE: an inter-university transfer is prepared by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    c := people.university_transfer_form_check(p_row, p_session);
    IF c->>'status' = 'INVALID' THEN
        RAISE EXCEPTION 'UNIVERSITY_TRANSFER_FORM_INVALID: %', (SELECT string_agg(m->>'text', '; ') FROM jsonb_array_elements(c -> 'problems') m)
            USING ERRCODE = '23514';
    END IF;
    made := people.prepare_university_transfers(jsonb_build_array(p_row), p_session, p_reason, p_approval_ref, NULL, false);
    UPDATE people.university_transfer_batch SET source = 'FORM' WHERE id = (made->>'id')::uuid;
    RETURN made || jsonb_build_object('transferId', (SELECT t.id FROM people.university_transfer t WHERE t.batch_id = (made->>'id')::uuid));
END $fn$;
COMMENT ON FUNCTION people.register_university_transfer(jsonb, text, text, text) IS
  'V763: one student''s inter-university transfer registered on the form — the Academic Office or the Registry; refused while the form has a problem; a batch of one (IUT/YYYY/NNNNNN, source FORM) awaiting another officer''s decision, nothing on a record changed before it.';

-- ── 5 · who a number finds, for the form ────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.university_transfer_lookup(p_number text, p_direction text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_no text := upper(regexp_replace(coalesce(p_number, ''), '\s+', '', 'g')); s record; k record; v_by text; v_pending text;
        v_dir text := upper(btrim(coalesce(p_direction, '')));
        v_live CONSTANT text[] := ARRAY['ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT'];
BEGIN
    -- as the check finds a student for the direction: going out (or unsaid), the matriculation number, a former one, then the JAMB
    -- number directly or through the applicant; coming in, the JAMB number alone — the form's incoming row carries no other, and a
    -- student found here by another number would be one the check never finds
    SELECT x.id, x.surname, x.other_names, x.sex, x.date_of_birth, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code,
           p.name AS programme_name, p.dept_code, p.faculty_code INTO s
      FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
     WHERE x.duplicate_of IS NULL AND length(v_no) >= 4 AND v_dir <> 'INCOMING' AND upper(x.matric_no) = v_no;
    IF s.id IS NOT NULL THEN v_by := 'MATRIC'; END IF;
    IF s.id IS NULL AND length(v_no) >= 4 AND v_dir <> 'INCOMING' THEN
        SELECT x.id, x.surname, x.other_names, x.sex, x.date_of_birth, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code,
               p.name AS programme_name, p.dept_code, p.faculty_code INTO s
          FROM people.matric_alias a JOIN people.student x ON x.id = a.student_id LEFT JOIN ref.programme p ON p.code = x.programme_code
         WHERE upper(a.old_no) = v_no AND a.ended_at IS NULL;
        IF s.id IS NOT NULL THEN v_by := 'FORMER_MATRIC'; END IF;
    END IF;
    IF s.id IS NULL AND length(v_no) >= 4 THEN
        SELECT x.id, x.surname, x.other_names, x.sex, x.date_of_birth, x.matric_no, x.jamb_reg_no, x.status, x.current_level, x.programme_code,
               p.name AS programme_name, p.dept_code, p.faculty_code INTO s
          FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
         WHERE x.duplicate_of IS NULL
           AND (upper(btrim(x.jamb_reg_no)) = v_no OR x.candidate_id IN (SELECT c.id FROM admissions.candidate c WHERE upper(c.jamb_reg_no) = v_no))
         ORDER BY (x.status = ANY (v_live)) DESC, x.matriculated_at DESC NULLS LAST LIMIT 1;
        IF s.id IS NOT NULL THEN v_by := 'JAMB'; END IF;
    END IF;
    -- the applicant under a JAMB number: a student coming in is linked to the application (going out, only a student is transferred)
    SELECT c.id, c.session, c.surname, c.other_names, c.sex, c.programme, c.offer_state, p.name AS programme_name INTO k
      FROM admissions.candidate c LEFT JOIN ref.programme p ON p.code = c.programme
     WHERE length(v_no) >= 4 AND v_dir <> 'OUTGOING' AND upper(c.jamb_reg_no) = v_no ORDER BY c.session DESC LIMIT 1;
    v_pending := (SELECT b.ref FROM people.university_transfer t JOIN people.university_transfer_batch b ON b.id = t.batch_id
                   WHERE t.status = 'PENDING_APPROVAL' AND ((s.id IS NOT NULL AND t.student_id = s.id) OR (length(v_no) >= 4 AND upper(t.jamb_reg_no) = v_no))
                   ORDER BY t.prepared_at DESC LIMIT 1);
    RETURN jsonb_build_object('number', v_no, 'direction', nullif(v_dir, ''), 'matchedBy', v_by,
        'student', CASE WHEN s.id IS NOT NULL THEN jsonb_build_object('id', s.id, 'name', s.surname || ', ' || s.other_names, 'surname', s.surname,
            'otherNames', s.other_names, 'sex', s.sex, 'dateOfBirth', s.date_of_birth, 'matricNo', s.matric_no, 'jambRegNo', s.jamb_reg_no, 'status', s.status,
            'live', s.status = ANY (v_live), 'faculty', s.faculty_code, 'dept', s.dept_code, 'programme', s.programme_code, 'programmeName', s.programme_name,
            'level', s.current_level) END,
        'applicant', CASE WHEN k.id IS NOT NULL THEN jsonb_build_object('id', k.id, 'session', k.session, 'surname', k.surname, 'otherNames', k.other_names,
            'sex', k.sex, 'programme', k.programme, 'programmeName', k.programme_name, 'offerState', k.offer_state) END,
        'pendingRef', v_pending);
END $fn$;
COMMENT ON FUNCTION people.university_transfer_lookup(text, text) IS
  'V763: who a number finds for the inter-university transfer form, as the check finds them for the direction — going out (or unsaid): the matriculation number, a former one, then the JAMB number directly or through the applicant; coming in: the JAMB number alone, and the applicant under it — and a transfer of theirs already awaiting a decision.';

-- ── 6 · reading: the source of a batch, the new particulars of a transfer ───────────────────────────────────────────────
DROP FUNCTION people.university_transfer_batches(int);
CREATE FUNCTION people.university_transfer_batches(p_limit int DEFAULT 200)
RETURNS TABLE (id uuid, ref text, effective_session text, filename text, reason text, approval_ref text, total int, prepared int, left_out int,
               incoming bigint, outgoing bigint, pending bigint, completed bigint, rejected bigint, prepared_by uuid, prepared_by_name text, prepared_office text,
               prepared_at timestamptz, status text, source text)
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
                ELSE 'REJECTED' END,
           b.source
      FROM people.university_transfer_batch b LEFT JOIN people.university_transfer t ON t.batch_id = b.id
     GROUP BY b.id
     ORDER BY b.prepared_at DESC
     LIMIT greatest(1, least(coalesce(p_limit, 200), 2000))
$fn$;
COMMENT ON FUNCTION people.university_transfer_batches(int) IS 'V588, V763: the inter-university transfer batches, the latest first, with how their transfers stand and whether a file or the form made them';

DROP FUNCTION people.university_transfers(uuid, uuid, text, text, int);
CREATE FUNCTION people.university_transfers(p_batch uuid DEFAULT NULL, p_student uuid DEFAULT NULL, p_q text DEFAULT NULL, p_direction text DEFAULT NULL, p_limit int DEFAULT 1000)
RETURNS TABLE (id uuid, batch_id uuid, batch_ref text, row_no int, direction text, status text, student_id uuid, student text, matric_no text, jamb_reg_no text,
               university_code text, university text, other_programme text, other_level int, programme_code text, programme text, level int,
               effective_session text, created_student boolean, matched_by text, prepared_by_name text, prepared_at timestamptz, decided_by_name text,
               decided_at timestamptz, decision_note text,
               other_matric_no text, other_entry_session text, other_cgpa numeric, other_cgpa_scale smallint, documents text[], remarks text, source text)
LANGUAGE sql STABLE AS $fn$
    SELECT t.id, t.batch_id, b.ref, t.row_no, t.direction, t.status, t.student_id,
           coalesce(s.surname || ', ' || s.other_names, people.transfer_cell(t.uploaded, 'student', 'Student Name', 'Name'),
                    people.transfer_cell(t.uploaded, 'surname', 'Surname') || ', ' || people.transfer_cell(t.uploaded, 'other_names', 'Other Names')),
           s.matric_no, coalesce(s.jamb_reg_no, t.jamb_reg_no), t.university_code, u.name, t.other_programme, t.other_level,
           t.programme_code, p.name, t.level, t.effective_session, t.created_student, t.matched_by,
           people.officer_name(t.prepared_by), t.prepared_at, people.officer_name(t.decided_by), t.decided_at, t.decision_note,
           t.other_matric_no, t.other_entry_session, t.other_cgpa, t.other_cgpa_scale, t.documents, t.remarks, b.source
      FROM people.university_transfer t
      JOIN people.university_transfer_batch b ON b.id = t.batch_id
      JOIN ref.university u ON u.code = t.university_code
      LEFT JOIN people.student s ON s.id = t.student_id
      LEFT JOIN ref.programme p ON p.code = t.programme_code
     WHERE (p_batch IS NULL OR t.batch_id = p_batch) AND (p_student IS NULL OR t.student_id = p_student)
       AND (p_direction IS NULL OR t.direction = p_direction)
       AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL OR b.ref ILIKE '%' || btrim(p_q) || '%' OR s.matric_no ILIKE '%' || btrim(p_q) || '%'
            OR t.jamb_reg_no ILIKE '%' || btrim(p_q) || '%' OR (s.surname || ' ' || s.other_names) ILIKE '%' || btrim(p_q) || '%' OR u.name ILIKE '%' || btrim(p_q) || '%'
            OR t.other_matric_no ILIKE '%' || btrim(p_q) || '%'
            OR people.transfer_cell(t.uploaded, 'student', 'Student Name', 'Name') ILIKE '%' || btrim(p_q) || '%'
            OR (people.transfer_cell(t.uploaded, 'surname', 'Surname') || ' ' || people.transfer_cell(t.uploaded, 'other_names', 'Other Names')) ILIKE '%' || btrim(p_q) || '%')
     ORDER BY t.prepared_at DESC, t.row_no
     LIMIT greatest(1, least(coalesce(p_limit, 1000), 5000))
$fn$;
COMMENT ON FUNCTION people.university_transfers(uuid, uuid, text, text, int) IS
  'V588, V763: the inter-university transfers of a batch, of a student, or matching a reference, a number (here or at the other university), a name or a university — with the particulars the form or the file gave';

COMMIT;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V579 — A matriculation number corrected, the old number kept
--
--   A matriculation number is permanent (V013, BR-007): no path on the portal changes one once issued. Some numbers are wrong —
--   brought over from the old portal under the wrong faculty or programme code, a wrong year or sequence, a data-entry slip — and
--   until now the Registry could only say so. The correction is one controlled act, never an edit:
--     · people.matric_correction: one row a correction (MCR/YYYY/NNNNNN) — the student, the number as it is and as it should be,
--       the kind of error, the reason and the approval reference, the review points the check raised, who prepared it and who
--       decided it. Prepared by the Academic Office, the Registry, the Director of ICT or super; decided — approved and made at
--       once, or rejected — by ANOTHER officer of the Academic Office or the Registry (super too); the Director of ICT decides a
--       legacy migration correction, the technical case, and no other. Nothing is written to the student until the decision.
--     · people.matric_correction_check says, before anything is written and again at the decision, what stands in the way —
--       the student has no number yet (that is issuance, not correction), the number is not in the University's form, it is
--       the number of another student, a former number of another student, issued to another in the history, reserved by a
--       batch, proposed for another student, or the sequence of the series was issued to another — and what to look at: the
--       codes the configuration gives the student's programme, the year of entry, the series moving on, the documents issued
--       under the old number, the sign-in changing. people.matric_correction_suggestions derives the number from the
--       configuration (the same year and sequence under the programme's codes; the next number of the series). The curriculum
--       track follows the number's prefix (V235), so a change of prefix that changes the framework is said before the decision.
--     · at the decision the student's number changes and nothing else: the record, the account, the registrations, the
--       results, the payments and receipts, the documents keep their rows and their student; the old number is kept as a
--       former number (people.matric_alias) that every search resolves to the student and that is never given again — not
--       by the generator (people.matric_number_taken), not by an upload (a guard on people.student refuses it by name); the
--       sign-in moves to the new number (people.student_username_change), and the student is told (MATRIC_NUMBER_CORRECTED);
--       a new number in the form of the student's series is written to the matriculation history like any number issued, so the
--       generator passes over its sequence while the series' counter runs on where it was.
--     · the V013 permanence trigger stands for every other path: it lets a number change only inside the decision of the
--       pending correction that names exactly that student, that old number and that new one.
--     · evidence (the Registrar's memo, the matriculation register, the legacy record) is kept with the correction in
--       people.matric_correction_evidence, in the file store where there is one (V348).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V579: a matriculation number corrected, the old number kept', true);

-- ── 1 · the correction, its evidence, the former numbers ────────────────────────────────────────────────────────────────
CREATE TABLE people.matric_correction (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref              text NOT NULL UNIQUE,
    student_id       uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,   -- the go-live reset clears it with the student
    old_no           text NOT NULL,
    new_no           text NOT NULL,
    kind             text NOT NULL CHECK (kind IN ('LEGACY_MIGRATION', 'FACULTY_CODE', 'PROGRAMME_CODE', 'YEAR', 'SERIES', 'SEQUENCE',
                                                   'DUPLICATE', 'DATA_ENTRY', 'PROGRAMME_CHANGE', 'OTHER')),
    reason           text NOT NULL CHECK (length(btrim(reason)) >= 10),
    approval_ref     text NULL,
    state            text NOT NULL DEFAULT 'PENDING_REVIEW' CHECK (state IN ('PENDING_REVIEW', 'COMPLETED', 'REJECTED', 'CANCELLED')),
    check_points     jsonb NOT NULL DEFAULT '[]',
    parts            jsonb NULL,
    prepared_by      uuid NOT NULL,
    prepared_office  text NULL,
    prepared_at      timestamptz NOT NULL DEFAULT now(),
    decided_by       uuid NULL,
    decided_office   text NULL,
    decided_at       timestamptz NULL,
    decision_note    text NULL,
    completed_at     timestamptz NULL,
    cancelled_by     uuid NULL,
    cancelled_at     timestamptz NULL,
    cancel_reason    text NULL,
    CHECK (upper(old_no) <> upper(new_no))
);
-- one correction at a time for a student, and one student at a time for a number
CREATE UNIQUE INDEX ux_matric_correction_open_student ON people.matric_correction (student_id) WHERE state = 'PENDING_REVIEW';
CREATE UNIQUE INDEX ux_matric_correction_open_number ON people.matric_correction (upper(new_no)) WHERE state = 'PENDING_REVIEW';
CREATE INDEX ix_matric_correction_student ON people.matric_correction (student_id);
CREATE INDEX ix_matric_correction_state ON people.matric_correction (state, prepared_at DESC);
SELECT audit.attach('people.matric_correction');
COMMENT ON TABLE people.matric_correction IS
  'V579: a matriculation number corrected — the student, the number as it was and as it is, the kind of error, reason, approval reference, review points, who prepared it and who decided it (another officer).';

CREATE TABLE people.matric_correction_evidence (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    correction_id  uuid NOT NULL REFERENCES people.matric_correction(id) ON DELETE CASCADE,
    filename       text NOT NULL,
    content_type   text NOT NULL,
    size_bytes     bigint NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 5242880),
    content        bytea NULL,
    object_id      uuid NULL REFERENCES platform.file_object(id),
    added_by       uuid NOT NULL,
    added_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_matric_correction_evidence_where CHECK (num_nonnulls(content, object_id) = 1)
);
CREATE INDEX ix_matric_correction_evidence ON people.matric_correction_evidence (correction_id);
COMMENT ON TABLE people.matric_correction_evidence IS 'V579: a file supporting a matriculation number correction — in the file store where there is one, else here';
SELECT audit.exempt('people.matric_correction_evidence',
    'The files supporting a matriculation number correction; the correction itself is on the spine, and each file names who added it and when.');

CREATE TABLE people.matric_alias (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    old_no               text NOT NULL,
    student_id           uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    correction_id        uuid NOT NULL REFERENCES people.matric_correction(id) ON DELETE CASCADE,
    created_at           timestamptz NOT NULL DEFAULT now(),
    ended_at             timestamptz NULL,
    ended_by_correction  uuid NULL REFERENCES people.matric_correction(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX ux_matric_alias_live ON people.matric_alias (upper(old_no)) WHERE ended_at IS NULL;
CREATE INDEX ix_matric_alias_student ON people.matric_alias (student_id);
SELECT audit.attach('people.matric_alias');
COMMENT ON TABLE people.matric_alias IS
  'V579: a former matriculation number of a student, kept when the number was corrected: searches resolve it to the student, and it is never given to anyone again. Ended only when a later correction gives it back to the same student.';

-- ── 2 · the permanence rule, with its one door; a former number never given again ───────────────────────────────────────
/* V013's rule, restated: a number once issued is never changed — except inside the decision of the pending correction that
   names exactly this student, this old number and this new one (people.decide_matric_correction sets moaum.matric_correction) */
CREATE OR REPLACE FUNCTION people.matric_is_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE v_c text := nullif(current_setting('moaum.matric_correction', true), '');
BEGIN
    IF OLD.matric_no IS NOT NULL AND NEW.matric_no IS DISTINCT FROM OLD.matric_no
       AND NOT (v_c IS NOT NULL AND EXISTS (SELECT 1 FROM people.matric_correction c
                                             WHERE c.id::text = v_c AND c.student_id = NEW.id AND c.state = 'PENDING_REVIEW'
                                               AND c.old_no = OLD.matric_no AND c.new_no = NEW.matric_no)) THEN
        RAISE EXCEPTION 'the matriculation number % is permanent and is not changed', OLD.matric_no
            USING ERRCODE = 'check_violation',
                  HINT = 'BR-007. A wrong number is corrected under Matriculation Correction: prepared by one officer, decided by another.';
    END IF;
    IF OLD.admission_no IS NOT NULL AND NEW.admission_no IS DISTINCT FROM OLD.admission_no THEN
        RAISE EXCEPTION 'the admission number % is retired, not changed', OLD.admission_no
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

/* a number corrected away from a student is never given again: not to a new record, not to another, not back by an upload */
CREATE FUNCTION people.matric_alias_guard()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE a record;
BEGIN
    IF NEW.matric_no IS NULL OR (TG_OP = 'UPDATE' AND NEW.matric_no IS NOT DISTINCT FROM OLD.matric_no) THEN RETURN NEW; END IF;
    SELECT al.student_id, s.matric_no AS now_no, c.ref INTO a
      FROM people.matric_alias al JOIN people.student s ON s.id = al.student_id JOIN people.matric_correction c ON c.id = al.correction_id
     WHERE upper(al.old_no) = upper(NEW.matric_no) AND al.ended_at IS NULL;
    IF a.student_id IS NOT NULL THEN
        RAISE EXCEPTION 'MATRIC_NUMBER_CORRECTED: % was corrected to % (%); a corrected number is never given again', NEW.matric_no, a.now_no, a.ref
            USING ERRCODE = '23514', HINT = 'Use the student''s current number.';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_student_matric_alias_guard BEFORE INSERT OR UPDATE OF matric_no ON people.student
    FOR EACH ROW EXECUTE FUNCTION people.matric_alias_guard();

/* V267's test of a free number, restated: a former number kept by a correction is taken too */
CREATE OR REPLACE FUNCTION people.matric_number_taken(p_no text, p_series text, p_seq bigint, p_row uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce(
        (SELECT 'Number already issued to ' || s.surname || ', ' || s.other_names FROM people.student s WHERE s.matric_no = p_no LIMIT 1),
        (SELECT 'Number was issued before (history of ' || h.issued_at::date || ')' FROM people.matric_history h WHERE h.matric_no = p_no OR (h.series_code = p_series AND h.sequence = p_seq) LIMIT 1),
        (SELECT 'Number is reserved by batch ' || b.ref FROM people.matric_reservation r JOIN people.matric_batch b ON b.id = r.batch_id
          WHERE r.released_at IS NULL AND (r.matric_no = p_no OR (r.series_code = p_series AND r.sequence = p_seq)) AND r.row_id IS DISTINCT FROM p_row LIMIT 1),
        (SELECT 'Number is a former number of ' || s.surname || ', ' || s.other_names || ', corrected by ' || c.ref
           FROM people.matric_alias a JOIN people.student s ON s.id = a.student_id JOIN people.matric_correction c ON c.id = a.correction_id
          WHERE upper(a.old_no) = upper(p_no) AND a.ended_at IS NULL LIMIT 1));
$function$;

-- ── 3 · a number's parts, the shapes, who else holds a number ───────────────────────────────────────────────────────────
/* a number's segments: MOAU/FAC/PROG/YY/SEQ, MOAU/FAC/YY/SEQ, or a legacy number (the last segment its sequence) */
CREATE FUNCTION people.matric_parts(p_no text)
RETURNS TABLE (university text, faculty text, programme text, yy text, sequence bigint, sequence_text text, segments int)
LANGUAGE sql IMMUTABLE AS $fn$
    WITH x AS (SELECT regexp_split_to_array(upper(btrim(coalesce(p_no, ''))), '[/-]') AS a)
    SELECT a[1], a[2],
           CASE WHEN cardinality(a) >= 5 THEN a[3] END,
           CASE WHEN cardinality(a) >= 4 AND a[cardinality(a) - 1] ~ '^[0-9]{2}$' THEN a[cardinality(a) - 1] END,
           CASE WHEN a[cardinality(a)] ~ '^[0-9]{1,8}$' THEN a[cardinality(a)]::bigint END,
           CASE WHEN a[cardinality(a)] ~ '^[0-9]{1,8}$' THEN a[cardinality(a)] END,
           cardinality(a)
      FROM x WHERE btrim(coalesce(p_no, '')) <> ''
$fn$;

/* a number the register accepts: the configured form, the V064 form, or a legacy old-portal number (people.student's own check) */
CREATE FUNCTION people.matric_shape_any(p_no text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
    SELECT coalesce(p_no ~ '^[A-Z]{2,6}[/-][A-Z0-9]{2,6}([/-][A-Z0-9]{2,6})?[/-][0-9]{2}[/-][0-9]{1,8}$'
                    OR p_no ~ '^[A-Z]{2,6}(/[A-Z0-9]{2,6}){1,4}/[0-9]{2,7}$', false)
$fn$;

/* who else holds a number: another student's number, another's former number, another's in the history, a batch's
   reservation for another, another student's pending correction (the correction given is left out) */
CREATE FUNCTION people.matric_taken_by_other(p_no text, p_student uuid, p_correction uuid DEFAULT NULL)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT p_no || ' is the matriculation number of ' || s.surname || ', ' || s.other_names
           FROM people.student s WHERE upper(s.matric_no) = upper(p_no) AND s.id <> p_student LIMIT 1),
        (SELECT p_no || ' is a former number of ' || s.surname || ', ' || s.other_names || ' (corrected by ' || c.ref || ') and is never given again'
           FROM people.matric_alias a JOIN people.student s ON s.id = a.student_id JOIN people.matric_correction c ON c.id = a.correction_id
          WHERE upper(a.old_no) = upper(p_no) AND a.ended_at IS NULL AND a.student_id <> p_student LIMIT 1),
        (SELECT p_no || ' was issued to ' || s.surname || ', ' || s.other_names || ' on ' || to_char(h.issued_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY')
           FROM people.matric_history h JOIN people.student s ON s.id = h.student_id WHERE upper(h.matric_no) = upper(p_no) AND h.student_id <> p_student LIMIT 1),
        (SELECT p_no || ' is reserved by matriculation batch ' || b.ref
           FROM people.matric_reservation r JOIN people.matric_batch b ON b.id = r.batch_id LEFT JOIN people.matric_batch_row br ON br.id = r.row_id
          WHERE r.released_at IS NULL AND upper(r.matric_no) = upper(p_no) AND br.student_id IS DISTINCT FROM p_student LIMIT 1),
        (SELECT p_no || ' is proposed for ' || s.surname || ', ' || s.other_names || ' by correction ' || c.ref || ', which waits for a decision'
           FROM people.matric_correction c JOIN people.student s ON s.id = c.student_id
          WHERE c.state = 'PENDING_REVIEW' AND upper(c.new_no) = upper(p_no) AND c.student_id <> p_student AND c.id IS DISTINCT FROM p_correction LIMIT 1))
$fn$;

-- ── 4 · the check, the numbers proposed ─────────────────────────────────────────────────────────────────────────────────
/* what a correction of this student's number to this one would do, and what stands in its way (problems) or is to be looked
   at (points); p_correction is the correction being decided, left out of the pending tests */
CREATE FUNCTION people.matric_correction_check(p_student uuid, p_new text, p_correction uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE s record; c record; ms people.matric_series; np record; v_new text := upper(regexp_replace(coalesce(p_new, ''), '\s+', '', 'g'));
        problems jsonb := '[]'; points jsonb := '[]'; v_taken text; v_docs int; v_reach record; v_in_series boolean := false;
        v_expected text; v_got text; v_pending text; v_own text; v_clash text;
BEGIN
    SELECT st.*, p.name AS programme, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty INTO s
      FROM people.student st LEFT JOIN ref.programme p ON p.code = st.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE st.id = p_student;
    IF s.id IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'problems', jsonb_build_array(jsonb_build_object('code', 'UNKNOWN', 'message', 'No such student on the register')), 'points', '[]'::jsonb);
    END IF;
    SELECT * INTO c FROM people.matric_components(p_student);
    SELECT * INTO np FROM people.matric_parts(v_new);

    IF s.matric_no IS NULL THEN
        problems := problems || jsonb_build_object('code', 'NO_NUMBER', 'message', 'The student has no matriculation number yet: one is issued under Matriculation Management, not corrected');
    END IF;
    IF s.duplicate_of IS NOT NULL THEN
        problems := problems || jsonb_build_object('code', 'DUPLICATE_RECORD', 'message', 'This record was ended as a duplicate of another; correct the record that was kept');
    END IF;
    IF v_new = '' THEN
        problems := problems || jsonb_build_object('code', 'EMPTY', 'message', 'Give the correct matriculation number');
    ELSIF upper(coalesce(s.matric_no, '')) = v_new THEN
        problems := problems || jsonb_build_object('code', 'SAME', 'message', v_new || ' is already the student''s number');
    ELSIF NOT people.matric_shape_any(v_new) THEN
        problems := problems || jsonb_build_object('code', 'SHAPE', 'message', v_new || ' is not a matriculation number: the University''s form is MOAU/FACULTY[/PROGRAMME]/YY/SEQUENCE');
    ELSE
        v_taken := people.matric_taken_by_other(v_new, p_student, p_correction);
        IF v_taken IS NOT NULL THEN
            problems := problems || jsonb_build_object('code', 'TAKEN', 'message', 'MATRICULATION NUMBER ALREADY ASSIGNED: ' || v_taken);
        END IF;
    END IF;
    SELECT c2.ref INTO v_pending FROM people.matric_correction c2
     WHERE c2.student_id = p_student AND c2.state = 'PENDING_REVIEW' AND c2.id IS DISTINCT FROM p_correction LIMIT 1;
    IF v_pending IS NOT NULL THEN
        problems := problems || jsonb_build_object('code', 'PENDING', 'message', 'A correction of this student''s number (' || v_pending || ') already waits for a decision');
    END IF;

    -- against the configuration: the codes the student's programme carries, the year of entry, the series
    IF c.problem IS NOT NULL THEN
        points := points || jsonb_build_object('code', 'CONFIG', 'message', 'The number cannot be compared with the configuration: ' || c.problem);
    ELSIF v_new <> '' AND np.university IS NOT NULL THEN
        v_expected := array_to_string(array_remove(ARRAY[c.university_code, c.faculty_segment, c.programme_segment], NULL), '/');
        v_got := array_to_string(array_remove(ARRAY[np.university, np.faculty, np.programme], NULL), '/');
        IF v_expected IS DISTINCT FROM v_got THEN
            points := points || jsonb_build_object('code', 'PREFIX', 'message',
                'The configuration gives ' || coalesce(s.programme, 'the programme') || ' the codes ' || v_expected || '; the number reads ' || coalesce(nullif(v_got, ''), '—'));
        ELSE
            v_in_series := np.sequence IS NOT NULL;
        END IF;
        IF np.yy IS DISTINCT FROM c.yy AND c.yy IS NOT NULL THEN
            points := points || jsonb_build_object('code', 'YEAR', 'message',
                'The year in the number is ' || coalesce(np.yy, 'missing') || '; the student entered in ' || coalesce(s.entry_session, '—') || ' (' || c.yy || ')');
        END IF;
        IF NOT people.matric_shape_ok(v_new) AND people.matric_shape_any(v_new) THEN
            points := points || jsonb_build_object('code', 'LEGACY_FORM', 'message', v_new || ' is in a legacy old-portal form, not the configured one');
        END IF;
        IF v_in_series THEN
            SELECT * INTO ms FROM people.matric_series WHERE code = c.series_code;
            SELECT h.matric_no || ' (' || s2.surname || ', ' || s2.other_names || ')' INTO v_clash
              FROM people.matric_history h JOIN people.student s2 ON s2.id = h.student_id
             WHERE h.series_code = c.series_code AND h.sequence = np.sequence AND h.student_id <> p_student LIMIT 1;
            IF v_clash IS NOT NULL THEN
                problems := problems || jsonb_build_object('code', 'SERIES_TAKEN', 'message',
                    'Sequence ' || np.sequence || ' of the ' || c.series_code || ' series was issued to another student: ' || v_clash);
            ELSIF ms.code IS NOT NULL THEN
                points := points || jsonb_build_object('code', 'SERIES', 'message',
                    'The number takes sequence ' || np.sequence || ' of the ' || ms.code || ' series (issued up to ' || ms.last_issued
                    || '); it is written to the matriculation history, so the generator passes over it and the series runs on as it is');
            END IF;
        END IF;
    END IF;

    -- what changes for the student, and what stays
    SELECT a.old_no INTO v_own FROM people.matric_alias a WHERE a.student_id = p_student AND upper(a.old_no) = v_new AND a.ended_at IS NULL;
    IF v_own IS NOT NULL THEN
        points := points || jsonb_build_object('code', 'FORMER', 'message', v_new || ' is the student''s own former number: the correction gives it back');
    END IF;
    v_docs := (SELECT count(*) FROM credentials.issued i WHERE i.student_id = p_student)
            + (SELECT count(*) FROM credentials.identity_card ic WHERE ic.student_id = p_student)
            + (SELECT count(*) FROM credentials.certificate ce WHERE ce.student_id = p_student);
    IF v_docs > 0 THEN
        points := points || jsonb_build_object('code', 'DOCUMENTS', 'message',
            v_docs || ' document' || CASE WHEN v_docs = 1 THEN ' was' ELSE 's were' END || ' issued under the old number; they stay as issued, and documents issued from now carry the new number');
    END IF;
    IF s.status = 'GRADUATED' THEN
        points := points || jsonb_build_object('code', 'GRADUATED', 'message', 'The student has graduated: the certificate and transcripts already issued carry the old number');
    END IF;
    -- the curriculum track follows the number's prefix (V235): a MOAU number and a BSU number may read different frameworks
    IF v_new <> '' AND people.track_for(v_new, s.entry_session, s.school_id) IS DISTINCT FROM s.curriculum_track THEN
        points := points || jsonb_build_object('code', 'CURRICULUM', 'message',
            'The curriculum track follows the number: it changes from ' || coalesce(s.curriculum_track, 'none') || ' to '
            || coalesce(people.track_for(v_new, s.entry_session, s.school_id), 'none') || ' (framework ' || coalesce(s.curriculum_version, '—') || ' to '
            || coalesce((SELECT t.framework FROM policy.curriculum_track t WHERE t.code = people.track_for(v_new, s.entry_session, s.school_id)), '—')
            || '), and the units and minimum load read the new framework');
    END IF;
    SELECT * INTO v_reach FROM people.student_reach(p_student);
    points := points || jsonb_build_object('code', 'SIGN_IN', 'message',
        'From the correction the student signs in with the new number; the old one no longer opens the portal. '
        || CASE WHEN v_reach.email IS NULL AND v_reach.phone IS NULL THEN 'No e-mail or phone is on record: tell the student in person.'
                ELSE 'The student is told by ' || array_to_string(array_remove(ARRAY[CASE WHEN v_reach.email IS NOT NULL THEN 'e-mail' END, CASE WHEN v_reach.phone IS NOT NULL THEN 'SMS' END], NULL), ' and ') || '.' END);

    RETURN jsonb_build_object(
        'ok', jsonb_array_length(problems) = 0,
        'student', jsonb_build_object('id', s.id, 'surname', s.surname, 'otherNames', s.other_names, 'matricNo', s.matric_no, 'admissionNo', s.admission_no,
                                      'jambRegNo', s.jamb_reg_no, 'programmeCode', s.programme_code, 'programme', s.programme, 'department', s.department,
                                      'faculty', s.faculty, 'level', s.current_level, 'status', s.status, 'entrySession', s.entry_session),
        'newNo', v_new,
        'parts', CASE WHEN np.university IS NOT NULL THEN jsonb_build_object('university', np.university, 'faculty', np.faculty, 'programme', np.programme,
                                                                            'year', np.yy, 'sequence', np.sequence) END,
        'configured', jsonb_build_object('university', c.university_code, 'faculty', c.faculty_segment, 'programme', c.programme_segment, 'year', c.yy,
                                         'series', c.series_code, 'problem', c.problem),
        'inSeries', v_in_series,
        'problems', problems,
        'points', points);
END $fn$;
COMMENT ON FUNCTION people.matric_correction_check(uuid, text, uuid) IS
  'V579: what correcting a student''s matriculation number to the one given would do — problems that stop it (no number yet, not a number, another student''s number or former number, issued, reserved or proposed for another, the series sequence issued to another, a correction already waiting) and points to look at (the configured codes, the year of entry, the series, documents issued, graduation, the sign-in).';

/* the numbers the configuration proposes: the same year and sequence under the codes the programme carries, and the next
   number of the series; each with who else holds it, if anyone */
CREATE FUNCTION people.matric_correction_suggestions(p_student uuid)
RETURNS TABLE (label text, matric_no text, taken text)
LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT st.id, st.matric_no FROM people.student st WHERE st.id = p_student),
         c AS (SELECT * FROM people.matric_components(p_student)),
         mf AS (SELECT * FROM people.matric_format WHERE id = 'UNIVERSITY'),
         o AS (SELECT * FROM people.matric_parts((SELECT matric_no FROM s))),
         cand AS (
             SELECT 1 AS n, 'The same year and sequence, under the codes the programme carries' AS label,
                    people.format_matric(c.university_code, c.faculty_segment, c.programme_segment, coalesce(o.yy, c.yy), NULL) || mf.separator || o.sequence_text AS no
               FROM c, o, mf WHERE c.problem IS NULL AND o.sequence_text IS NOT NULL
             UNION ALL
             SELECT 2, 'The next number of the ' || p.series_code || ' series', p.matric_no FROM people.matric_preview(p_student) p WHERE p.problem IS NULL)
    SELECT cand.label, cand.no, people.matric_taken_by_other(cand.no, p_student)
      FROM cand, s
     WHERE cand.no IS NOT NULL AND upper(cand.no) IS DISTINCT FROM upper(s.matric_no)
     ORDER BY cand.n
$fn$;

-- ── 5 · prepared, decided, cancelled ────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.prepare_matric_correction(p_student uuid, p_new text, p_kind text, p_reason text, p_approval_ref text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_new text := upper(regexp_replace(coalesce(p_new, ''), '\s+', '', 'g')); v_reason text := btrim(coalesce(p_reason, ''));
        s people.student; v_chk jsonb; v_id uuid := gen_random_uuid(); v_ref text; v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'MATRIC_CORRECTION_ACTOR: a correction is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF v_office IS NULL OR v_office NOT IN ('academic', 'records', 'registrar', 'dregistrar', 'ict', 'super') THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_OFFICE: a matriculation number correction is prepared by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF coalesce(p_kind, '') NOT IN ('LEGACY_MIGRATION', 'FACULTY_CODE', 'PROGRAMME_CODE', 'YEAR', 'SERIES', 'SEQUENCE', 'DUPLICATE', 'DATA_ENTRY', 'PROGRAMME_CHANGE', 'OTHER') THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_KIND: say what was wrong with the number' USING ERRCODE = '23514';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_REASON: say why the number is wrong and on whose authority, ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF s.id IS NULL THEN RAISE EXCEPTION 'MATRIC_CORRECTION_UNKNOWN: no such student on the register' USING ERRCODE = '23514'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('matric-no:' || v_new));
    v_chk := people.matric_correction_check(p_student, v_new, NULL);
    IF jsonb_array_length(v_chk->'problems') > 0 THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_%: %', v_chk->'problems'->0->>'code', v_chk->'problems'->0->>'message' USING ERRCODE = '23514';
    END IF;
    v_ref := 'MCR/' || v_year || '/' || lpad(platform.next_number('MATRIC_CORRECTION', 'UNIVERSITY', v_year)::text, 6, '0');
    INSERT INTO people.matric_correction (id, ref, student_id, old_no, new_no, kind, reason, approval_ref, check_points, parts, prepared_by, prepared_office)
    VALUES (v_id, v_ref, s.id, s.matric_no, v_new, p_kind, v_reason, nullif(btrim(coalesce(p_approval_ref, '')), ''), v_chk->'points', v_chk->'parts', v_actor, v_office);
    RETURN jsonb_build_object('id', v_id, 'ref', v_ref, 'state', 'PENDING_REVIEW', 'check', v_chk);
END $fn$;
COMMENT ON FUNCTION people.prepare_matric_correction(uuid, text, text, text, text) IS
  'V579: a matriculation number correction prepared (MCR/YYYY/NNNNNN) by the Academic Office, the Registry or the Director of ICT — checked first, refused on any problem; nothing is written to the student until another officer decides it.';

CREATE FUNCTION people.decide_matric_correction(p_id uuid, p_approve boolean, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        m people.matric_correction; s people.student; c record; v_chk jsonb; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'MATRIC_CORRECTION_ACTOR: a correction is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO m FROM people.matric_correction WHERE id = p_id FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'MATRIC_CORRECTION_UNKNOWN: no such correction' USING ERRCODE = '23514'; END IF;
    IF m.state <> 'PENDING_REVIEW' THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_DECIDED: % is % already', m.ref, lower(m.state) USING ERRCODE = '23514';
    END IF;
    IF NOT (coalesce(v_office, '') IN ('academic', 'records', 'registrar', 'dregistrar', 'super') OR (v_office = 'ict' AND m.kind = 'LEGACY_MIGRATION')) THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_DECIDER: a correction is decided by the Academic Office or the Registry; the Director of ICT decides a legacy migration correction only'
            USING ERRCODE = '42501';
    END IF;
    IF m.prepared_by = v_actor THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_SAME_OFFICER: the officer who prepared a correction does not decide it' USING ERRCODE = '42501';
    END IF;

    IF NOT coalesce(p_approve, false) THEN
        IF length(coalesce(v_note, '')) < 10 THEN
            RAISE EXCEPTION 'MATRIC_CORRECTION_NOTE: say why the correction is rejected, ten characters or more' USING ERRCODE = '23514';
        END IF;
        UPDATE people.matric_correction SET state = 'REJECTED', decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = v_note WHERE id = m.id;
        RETURN jsonb_build_object('id', m.id, 'ref', m.ref, 'state', 'REJECTED');
    END IF;

    -- checked again at the moment of the decision, the student, the number and the series held
    SELECT * INTO s FROM people.student WHERE id = m.student_id FOR UPDATE;
    IF upper(coalesce(s.matric_no, '')) <> upper(m.old_no) THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_STALE: the student''s number is now %, not the % this correction was prepared against; cancel it and prepare it again', coalesce(s.matric_no, 'none'), m.old_no
            USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('matric-no:' || upper(m.new_no)));
    SELECT * INTO c FROM people.matric_components(s.id);
    IF c.problem IS NULL THEN PERFORM 1 FROM people.matric_series WHERE code = c.series_code FOR UPDATE; END IF;
    v_chk := people.matric_correction_check(s.id, m.new_no, m.id);
    IF jsonb_array_length(v_chk->'problems') > 0 THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_%: %', v_chk->'problems'->0->>'code', v_chk->'problems'->0->>'message' USING ERRCODE = '23514';
    END IF;

    -- the student's own former number given back: that former number ends
    UPDATE people.matric_alias SET ended_at = now(), ended_by_correction = m.id WHERE student_id = s.id AND upper(old_no) = upper(m.new_no) AND ended_at IS NULL;
    PERFORM set_config('moaum.matric_correction', m.id::text, true);
    UPDATE people.student SET matric_no = m.new_no WHERE id = s.id;
    PERFORM set_config('moaum.matric_correction', '', true);
    INSERT INTO people.matric_alias (old_no, student_id, correction_id) VALUES (m.old_no, s.id, m.id);
    INSERT INTO people.student_username_change (student_id, previous_username, new_username, reason, changed_by, office)
    VALUES (s.id, m.old_no, m.new_no, 'Matriculation number corrected (' || m.ref || ')', v_actor, v_office);
    -- a corrected number in the form of the student's own series is on the history like any number issued, so the generator passes
    -- over its sequence; the series' counter is left where it is (a sequence the student already holds there is not written twice)
    IF c.problem IS NULL AND (v_chk->>'inSeries')::boolean THEN
        INSERT INTO people.matric_history (student_id, matric_no, series_code, sequence, components, issued_by, actor_office, reason)
        VALUES (s.id, m.new_no, c.series_code, (v_chk->'parts'->>'sequence')::bigint, coalesce(v_chk->'parts', '{}'::jsonb) || jsonb_build_object('correction', m.ref),
                v_actor, v_office, 'Matriculation number corrected (' || m.ref || ')')
        ON CONFLICT DO NOTHING;
    END IF;
    UPDATE people.matric_correction SET state = 'COMPLETED', decided_by = v_actor, decided_office = v_office, decided_at = now(), decision_note = v_note,
                                        completed_at = now(), check_points = v_chk->'points'
     WHERE id = m.id;
    BEGIN
        PERFORM platform.tell_student(s.id, 'MATRIC_NUMBER_CORRECTED', NULL, jsonb_build_object('OLD_MATRIC', m.old_no, 'NEW_MATRIC', m.new_no),
                                      'MATRIC_NUMBER_CORRECTED:' || m.id::text);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'matriculation correction %: the student could not be told (%)', m.ref, SQLERRM;
    END;
    RETURN jsonb_build_object('id', m.id, 'ref', m.ref, 'state', 'COMPLETED', 'oldNo', m.old_no, 'newNo', m.new_no);
END $fn$;
COMMENT ON FUNCTION people.decide_matric_correction(uuid, boolean, text) IS
  'V579: a correction decided by another officer — rejected with a note, or approved and made at once after a last check: the student''s number changed and nothing else, the old number kept as a former number, the sign-in moved, a number of the student''s series written to the matriculation history, the student told.';

CREATE FUNCTION people.cancel_matric_correction(p_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        m people.matric_correction; v_reason text := btrim(coalesce(p_reason, ''));
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'MATRIC_CORRECTION_ACTOR: a correction is cancelled by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO m FROM people.matric_correction WHERE id = p_id FOR UPDATE;
    IF m.id IS NULL THEN RAISE EXCEPTION 'MATRIC_CORRECTION_UNKNOWN: no such correction' USING ERRCODE = '23514'; END IF;
    IF m.state <> 'PENDING_REVIEW' THEN RAISE EXCEPTION 'MATRIC_CORRECTION_DECIDED: % is % already', m.ref, lower(m.state) USING ERRCODE = '23514'; END IF;
    IF NOT (m.prepared_by = v_actor OR coalesce(v_office, '') IN ('academic', 'records', 'registrar', 'dregistrar', 'super')) THEN
        RAISE EXCEPTION 'MATRIC_CORRECTION_OFFICE: a correction is cancelled by the officer who prepared it, the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF length(v_reason) < 10 THEN RAISE EXCEPTION 'MATRIC_CORRECTION_REASON: say why the correction is cancelled, ten characters or more' USING ERRCODE = '23514'; END IF;
    UPDATE people.matric_correction SET state = 'CANCELLED', cancelled_by = v_actor, cancelled_at = now(), cancel_reason = v_reason WHERE id = m.id;
    RETURN jsonb_build_object('id', m.id, 'ref', m.ref, 'state', 'CANCELLED');
END $fn$;

-- ── 6 · reading: a number resolved, the students found, the corrections, a student's numbers ────────────────────────────
/* an officer's name as the register of persons holds it, or nothing (the screen then names the office) */
CREATE FUNCTION people.officer_name(p_person uuid)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = p_person
$fn$;

/* the student a number names: the current matriculation number, a former one kept by a correction, the admission or JAMB number */
CREATE FUNCTION people.student_of_number(p_no text)
RETURNS TABLE (student_id uuid, matched text, matric_no text, correction_ref text, corrected_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    SELECT s.id, 'CURRENT', s.matric_no, NULL::text, NULL::timestamptz FROM people.student s WHERE upper(s.matric_no) = upper(btrim(p_no))
    UNION ALL
    SELECT s.id, 'CORRECTED', s.matric_no, c.ref, c.completed_at
      FROM people.matric_alias a JOIN people.student s ON s.id = a.student_id JOIN people.matric_correction c ON c.id = a.correction_id
     WHERE upper(a.old_no) = upper(btrim(p_no)) AND a.ended_at IS NULL
    UNION ALL
    SELECT s.id, 'ADMISSION', s.matric_no, NULL, NULL FROM people.student s WHERE upper(s.admission_no) = upper(btrim(p_no))
    UNION ALL
    SELECT s.id, 'JAMB', s.matric_no, NULL, NULL FROM people.student s WHERE upper(s.jamb_reg_no) = upper(btrim(p_no))
$fn$;

/* students found for a correction: by the current or a former matriculation number, the name, the JAMB, admission or application
   number, the record's id; within a faculty, department, programme or level */
CREATE FUNCTION people.matric_correction_search(p_q text, p_faculty text DEFAULT NULL, p_dept text DEFAULT NULL, p_programme text DEFAULT NULL,
                                                p_level int DEFAULT NULL, p_limit int DEFAULT 100)
RETURNS TABLE (student_id uuid, surname text, other_names text, matric_no text, former_no text, corrected_by text, admission_no text, jamb_reg_no text,
               programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, current_level int, status text,
               pending_ref text)
LANGUAGE sql STABLE AS $fn$
    WITH q AS (SELECT nullif(upper(btrim(coalesce(p_q, ''))), '') AS q),
    hits AS (
        SELECT s.id, NULL::text AS former_no, NULL::text AS cref
          FROM people.student s, q
         WHERE q.q IS NULL OR upper(s.matric_no) LIKE '%' || q.q || '%' OR upper(s.admission_no) = q.q OR upper(s.jamb_reg_no) = q.q
            OR s.id::text = lower(q.q) OR upper(s.surname || ' ' || s.other_names) LIKE '%' || q.q || '%' OR upper(s.other_names || ' ' || s.surname) LIKE '%' || q.q || '%'
            OR EXISTS (SELECT 1 FROM admissions.application ap WHERE ap.candidate_id = s.candidate_id AND upper(ap.application_no) = q.q)
        UNION ALL
        SELECT a.student_id, a.old_no, c.ref
          FROM people.matric_alias a JOIN people.matric_correction c ON c.id = a.correction_id, q
         WHERE q.q IS NOT NULL AND upper(a.old_no) LIKE '%' || q.q || '%'),
    one AS (SELECT DISTINCT ON (h.id) h.* FROM hits h ORDER BY h.id, h.former_no IS NULL)
    SELECT s.id, s.surname, s.other_names, s.matric_no, o.former_no, o.cref, s.admission_no, s.jamb_reg_no, p.code, p.name, d.code, d.name, f.code, f.name,
           s.current_level, s.status,
           (SELECT c.ref FROM people.matric_correction c WHERE c.student_id = s.id AND c.state = 'PENDING_REVIEW')
      FROM one o JOIN people.student s ON s.id = o.id
      LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE s.duplicate_of IS NULL
       AND (p_faculty IS NULL OR f.code = p_faculty) AND (p_dept IS NULL OR d.code = p_dept) AND (p_programme IS NULL OR p.code = p_programme)
       AND (p_level IS NULL OR s.current_level = p_level)
     ORDER BY o.former_no IS NULL, s.surname, s.other_names
     LIMIT greatest(1, least(coalesce(p_limit, 100), 1000))
$fn$;

/* the corrections, the latest first: by state, by a reference, number or name */
CREATE FUNCTION people.matric_corrections(p_state text DEFAULT NULL, p_q text DEFAULT NULL, p_student uuid DEFAULT NULL, p_limit int DEFAULT 500)
RETURNS TABLE (id uuid, ref text, student_id uuid, surname text, other_names text, programme text, current_level int, old_no text, new_no text, current_no text,
               kind text, reason text, approval_ref text, state text, check_points jsonb, prepared_by uuid, prepared_by_name text, prepared_office text, prepared_at timestamptz,
               decided_by_name text, decided_office text, decided_at timestamptz, decision_note text, cancelled_by_name text, cancelled_at timestamptz,
               cancel_reason text, evidence bigint)
LANGUAGE sql STABLE AS $fn$
    SELECT c.id, c.ref, c.student_id, s.surname, s.other_names, p.name, s.current_level, c.old_no, c.new_no, s.matric_no, c.kind, c.reason, c.approval_ref, c.state,
           c.check_points, c.prepared_by, people.officer_name(c.prepared_by), c.prepared_office, c.prepared_at,
           people.officer_name(c.decided_by), c.decided_office, c.decided_at, c.decision_note, people.officer_name(c.cancelled_by), c.cancelled_at, c.cancel_reason,
           (SELECT count(*) FROM people.matric_correction_evidence e WHERE e.correction_id = c.id)
      FROM people.matric_correction c JOIN people.student s ON s.id = c.student_id LEFT JOIN ref.programme p ON p.code = s.programme_code
     WHERE (p_state IS NULL OR c.state = p_state) AND (p_student IS NULL OR c.student_id = p_student)
       AND (p_q IS NULL OR c.ref ILIKE '%' || p_q || '%' OR c.old_no ILIKE '%' || p_q || '%' OR c.new_no ILIKE '%' || p_q || '%'
            OR (s.surname || ' ' || s.other_names) ILIKE '%' || p_q || '%')
     ORDER BY c.prepared_at DESC
     LIMIT greatest(1, least(coalesce(p_limit, 500), 5000))
$fn$;

/* a student's numbers through time: each issued (V263), each correction made, and the number brought from the old portal */
CREATE FUNCTION people.matric_number_history(p_student uuid)
RETURNS TABLE (at timestamptz, event text, matric_no text, previous_no text, ref text, reason text, by_name text, office text)
LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT * FROM people.student WHERE id = p_student),
    first_no AS (
        SELECT coalesce((SELECT c.old_no FROM people.matric_correction c WHERE c.student_id = p_student AND c.state = 'COMPLETED' ORDER BY c.completed_at LIMIT 1),
                        (SELECT matric_no FROM s)) AS no)
    SELECT h.issued_at, 'ISSUED', h.matric_no, NULL::text, coalesce(h.components->>'batch', NULL), h.reason, people.officer_name(h.issued_by), h.actor_office
      FROM people.matric_history h WHERE h.student_id = p_student AND NOT h.components ? 'correction'
    UNION ALL
    SELECT s.matriculated_at, 'ON_THE_REGISTER', f.no, NULL, NULL, 'On the register without a number issued by the portal (brought from the old portal)', NULL, NULL
      FROM s, first_no f
     WHERE f.no IS NOT NULL AND NOT EXISTS (SELECT 1 FROM people.matric_history h WHERE h.student_id = p_student AND NOT h.components ? 'correction')
    UNION ALL
    SELECT c.completed_at, 'CORRECTED', c.new_no, c.old_no, c.ref, c.reason, people.officer_name(c.decided_by), c.decided_office
      FROM people.matric_correction c WHERE c.student_id = p_student AND c.state = 'COMPLETED'
     ORDER BY 1 NULLS FIRST
$fn$;

-- ── 7 · the student told ────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('MATRIC_NUMBER_CORRECTED', 'Matriculation number corrected',
 'To a student whose matriculation number the Academic Office or the Registry has corrected',
 'Your matriculation number is now [NEW_MATRIC]',
 E'Dear [FIRST_NAME],\n\nYour matriculation number has been corrected from [OLD_MATRIC] to [NEW_MATRIC]. Use [NEW_MATRIC] from now on: it is your portal sign-in username, and every document the University issues to you from now carries it. Your password, payments, registrations and results are unchanged.\n\nIf this is not right, tell the Registry.',
 '[UNIVERSITY_SHORT]: your matriculation number is corrected from [OLD_MATRIC] to [NEW_MATRIC]. Sign in to the portal with [NEW_MATRIC]; your password is unchanged.',
 'Your matriculation number was corrected',
 'Your matriculation number is now [NEW_MATRIC] (it was [OLD_MATRIC]). It is your portal sign-in from now. Your password, payments, registrations and results are unchanged. If this is not right, tell the Registry.',
 ARRAY['FIRST_NAME','OLD_MATRIC','NEW_MATRIC','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

GRANT SELECT ON people.matric_correction, people.matric_alias TO app_auditor, app_reporting;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- V280 — the screening is the University's review of the record, not a form the applicant fills
--
--   After the acceptance fee the applicant was shown a seven-page screening
--   form to complete and submit. The University already holds what that form
--   asked for: what JAMB sent (the registration number, the UTME subjects and
--   score, the sex, the state and local government, the O'Level sittings, the
--   photograph), what the application gave (the next of kin, the contacts, the
--   date of birth) and the documents already uploaded. So the screening record
--   now opens by itself when the acceptance settles, in state PENDING; the
--   screening officers review the record assembled from those sources
--   (admissions.screening_facts) and decide — SUCCESSFUL, UNSUCCESSFUL with the
--   reason, or CORRECTION_REQUIRED naming the one thing to put right, which is
--   all the applicant is ever asked for. On success the official screening
--   forms are generated from the record as a numbered, versioned document in
--   the credential store (kind SCREENING_FORMS, number = the screening number):
--   the applicant views, downloads and prints them; fields the University does
--   not hold print as blanks to be filled by hand. Existing screening records,
--   answers and documents are kept; their states are carried over.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V280: the screening reviews the record; the forms are generated', true);

/* ── the states: awaiting the University, in review, one correction asked, decided ── */
ALTER TABLE admissions.screening_form DROP CONSTRAINT IF EXISTS ck_sf_state;
ALTER TABLE admissions.screening_form ADD CONSTRAINT ck_sf_state CHECK (state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'SUCCESSFUL', 'UNSUCCESSFUL', 'DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'RETURNED'));
ALTER TABLE admissions.screening_form ALTER COLUMN state SET DEFAULT 'PENDING';
UPDATE admissions.screening_form SET state = 'PENDING', updated_at = now() WHERE state IN ('DRAFT', 'SUBMITTED');
UPDATE admissions.screening_form SET state = 'IN_REVIEW', updated_at = now() WHERE state = 'UNDER_REVIEW';
UPDATE admissions.screening_form SET state = 'CORRECTION_REQUIRED', updated_at = now() WHERE state = 'RETURNED';
ALTER TABLE admissions.screening_form DROP CONSTRAINT IF EXISTS ck_sf_state;
ALTER TABLE admissions.screening_form ADD CONSTRAINT ck_sf_state CHECK (state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED', 'SUCCESSFUL', 'UNSUCCESSFUL'));
ALTER TABLE admissions.screening_form DROP CONSTRAINT IF EXISTS ck_sf_returned;
ALTER TABLE admissions.screening_form ADD CONSTRAINT ck_sf_returned CHECK (state <> 'CORRECTION_REQUIRED' OR nullif(btrim(coalesce(returned_note, '')), '') IS NOT NULL);
COMMENT ON COLUMN admissions.screening_form.state IS 'PENDING (awaiting the University''s screening) · IN_REVIEW · CORRECTION_REQUIRED (one thing asked of the applicant, in returned_note) · SUCCESSFUL · UNSUCCESSFUL (V280)';

/* the record opens by itself: awaiting the University, with JAMB's O'Level as its results, nothing to fill */
CREATE OR REPLACE FUNCTION admissions.screening_open(p_app uuid)
RETURNS admissions.screening_form LANGUAGE plpgsql AS $$
DECLARE a admissions.application; f admissions.screening_form; v_no text;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    IF f.application_id IS NOT NULL THEN RETURN f; END IF;
    IF a.accepted_at IS NULL THEN
        RAISE EXCEPTION 'SCREENING UNAVAILABLE: the screening opens once the offer is accepted and the acceptance fee confirmed' USING ERRCODE = '23514',
              HINT = 'Accept the offer and pay the acceptance fee first.';
    END IF;
    v_no := 'SCR/' || substr(a.session, 1, 4) || '/' || lpad(platform.next_number('SCREENING', 'UNIVERSITY', a.session)::text, 6, '0');
    INSERT INTO admissions.screening_form (application_id, screening_no, state) VALUES (p_app, v_no, 'PENDING') RETURNING * INTO f;
    INSERT INTO admissions.screening_olevel (application_id, ord, exam_body, exam_number, exam_year, subject, grade)
    SELECT p_app, row_number() OVER (ORDER BY st.ord, g.subject), st.exam_body, st.exam_number, nullif(regexp_replace(coalesce(st.exam_year, ''), '[^0-9]', '', 'g'), '')::int, g.subject, g.grade
      FROM admissions.candidate c JOIN admissions.olevel_sitting st ON st.session = c.session AND st.jamb_key = c.jamb_key JOIN admissions.olevel_grade g ON g.sitting_id = st.id
     WHERE c.id = a.candidate_id;
    PERFORM admissions.screening_log(p_app, 'OPENED', 'Screening ' || v_no || ' awaits the University on the record it holds');
    RETURN f;
END $$;

/* the applicant says the one correction is made: back to the University, a new version */
CREATE OR REPLACE FUNCTION admissions.screening_submit(p_app uuid, p_declaration boolean, p_ip text)
RETURNS admissions.screening_form LANGUAGE plpgsql AS $$
DECLARE f admissions.screening_form; c admissions.candidate; a admissions.application;
BEGIN
    f := admissions.screening_open(p_app);
    IF f.state <> 'CORRECTION_REQUIRED' THEN
        RAISE EXCEPTION 'SCREENING NOT FILLED: nothing is submitted by the applicant; the University screens on the record it holds' USING ERRCODE = '23514',
              HINT = 'Wait for the outcome of the screening; you are told here and by email.';
    END IF;
    UPDATE admissions.screening_form SET state = 'PENDING', version = version + 1, submitted_at = now(), submitted_ip = p_ip, declaration_at = now(), updated_at = now()
     WHERE application_id = p_app RETURNING * INTO f;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    PERFORM admissions.screening_log(p_app, 'CORRECTED', 'Correction provided (version ' || f.version || ') from ' || coalesce(p_ip, '?') || ': ' || coalesce(f.returned_note, ''));
    PERFORM admissions.notify_applicant(p_app, 'Your correction has been received',
        'The correction you provided on screening ' || f.screening_no || ' was received on ' || to_char(now(), 'DD Mon YYYY HH24:MI') || '. Your admission is back with the screening officers; you will be told the outcome here and by email.',
        'MOAUM: correction received on screening ' || f.screening_no || '. You will be told the outcome.');
    PERFORM admissions.tell_office('academic', 'A correction awaits the screening officers', c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || ') provided the correction asked for on screening ' || f.screening_no || ' for ' || c.programme || '.', p_app);
    RETURN f;
END $$;

CREATE OR REPLACE FUNCTION admissions.screening_start_review(p_app uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE admissions.screening_form SET state = 'IN_REVIEW', review_started_at = now(), review_started_by = p_actor, updated_at = now() WHERE application_id = p_app AND state = 'PENDING';
    IF FOUND THEN PERFORM admissions.screening_log(p_app, 'REVIEW_STARTED', NULL); END IF;
END $$;

CREATE OR REPLACE FUNCTION admissions.screening_refuse_student(p_student uuid, p_what text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.screening_override', true) = 'on' THEN RETURN; END IF;
    IF NOT admissions.screening_ok_student(p_student) THEN
        RAISE EXCEPTION '% UNAVAILABLE: the University''s screening must be successful first (or a change of programme approved)', p_what
            USING ERRCODE = '23514', HINT = 'The screening officers decide on the record the University holds; the door opens with their decision.';
    END IF;
END $$;

/* ── the record the officers screen and the forms are drawn from: every source the University already holds ── */
CREATE OR REPLACE FUNCTION admissions.screening_facts(p_app uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT ap.*, c.surname, c.other_names, c.jamb_reg_no, c.programme AS candidate_programme, c.entry_mode, c.entry_level, c.jamb_key, c.admitted_from, c.id AS cand_id
                 FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
         acc AS (SELECT acc.email, acc.phone FROM a JOIN admissions.applicant_account acc ON acc.id = a.account_id),
         cr AS (SELECT r.* FROM a LEFT JOIN admissions.caps_row r ON r.id = a.admitted_from),
         st AS (SELECT s.* FROM a LEFT JOIN people.student s ON s.candidate_id = a.cand_id),
         pr AS (SELECT p.code, p.name, p.category, f.name AS faculty, d.name AS department FROM a LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(a.candidate_programme)
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code),
         dob AS (SELECT x.payload ->> 'dob' AS dob FROM a JOIN admissions.attachment x ON x.candidate_id = a.cand_id AND x.kind = 'DATE_OF_BIRTH' ORDER BY x.arrived_at DESC LIMIT 1),
         photo AS (SELECT EXISTS (SELECT 1 FROM a JOIN admissions.attachment x ON x.session = a.session AND x.jamb_key = a.jamb_key AND x.kind = 'PASSPORT' AND jsonb_exists(x.payload, 'dataUrl')) AS yes),
         utme AS (SELECT (SELECT string_agg(e.value, ', ' ORDER BY e.key) FROM jsonb_each_text(cr.raw) e
                            WHERE regexp_replace(lower(e.key), '[^a-z0-9]', '', 'g') IN ('subject1','subject2','subject3','subject4') AND nullif(btrim(e.value), '') IS NOT NULL) AS subjects, cr.aggregate FROM cr),
         ol AS (SELECT coalesce(jsonb_agg(jsonb_build_object('exam_body', x.exam_body, 'exam_number', x.exam_number, 'exam_year', x.exam_year, 'subject', x.subject, 'grade', x.grade) ORDER BY x.ord), '[]'::jsonb) AS rows
                  FROM admissions.screening_olevel x WHERE x.application_id = p_app AND x.active),
         jol AS (SELECT coalesce(jsonb_agg(jsonb_build_object('exam_body', s.exam_body, 'exam_number', s.exam_number, 'exam_year', s.exam_year, 'subject', g.subject, 'grade', g.grade) ORDER BY s.ord, g.subject), '[]'::jsonb) AS rows
                   FROM a JOIN admissions.olevel_sitting s ON s.session = a.session AND s.jamb_key = a.jamb_key JOIN admissions.olevel_grade g ON g.sitting_id = s.id),
         docs AS (SELECT coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'filename', d.filename, 'uploaded_at', d.uploaded_at, 'status', d.status, 'review_note', d.review_note) ORDER BY d.kind, d.uploaded_at DESC), '[]'::jsonb) AS rows
                    FROM admissions.application_document d WHERE d.application_id = p_app),
         ans AS (SELECT coalesce(jsonb_object_agg(x.field, x.value) FILTER (WHERE btrim(x.value) <> ''), '{}'::jsonb) AS m FROM admissions.screening_answer x WHERE x.application_id = p_app),
         bio AS (SELECT coalesce(jsonb_object_agg(b.field, b.value) FILTER (WHERE btrim(b.value) <> ''), '{}'::jsonb) AS m FROM st JOIN people.biodata b ON b.student_id = st.id),
         inst AS (SELECT coalesce(jsonb_agg(jsonb_build_object('name', i.name, 'from_year', i.from_year, 'to_year', i.to_year, 'certificate', i.certificate, 'award_year', i.award_year) ORDER BY i.ord), '[]'::jsonb) AS rows
                    FROM admissions.screening_institution i WHERE i.application_id = p_app AND i.active),
         pay AS (SELECT coalesce(jsonb_object_agg(fr.kind, jsonb_build_object('reference', fr.reference, 'amount', fr.amount, 'confirmed_at', fr.confirmed_at, 'receipt_no', fr.receipt_no, 'channel', fr.channel)), '{}'::jsonb) AS m
                   FROM admissions.fee_reference fr WHERE fr.application_id = p_app AND fr.confirmed_at IS NOT NULL),
         ent AS (SELECT * FROM admissions.acceptance_entitlement(p_app)),
         scr AS (SELECT * FROM admissions.screening_form WHERE application_id = p_app)
    SELECT jsonb_build_object(
        'identity', jsonb_build_object('surname', a.surname, 'other_names', a.other_names, 'sex', coalesce(st.sex, cr.sex), 'date_of_birth', coalesce(st.date_of_birth::text, dob.dob),
                                       'state_of_origin', coalesce(st.state_of_origin, cr.state_of_origin), 'lga', cr.lga, 'email', acc.email, 'phone', acc.phone, 'next_of_kin', a.next_of_kin, 'passport', photo.yes),
        'jamb', jsonb_build_object('jamb_reg_no', a.jamb_reg_no, 'utme_aggregate', utme.aggregate, 'utme_subjects', utme.subjects, 'entry_mode', a.entry_mode, 'entry_level', a.entry_level,
                                   'programme', a.candidate_programme, 'session', a.session, 'list_source', (SELECT b.source FROM admissions.caps_row r JOIN admissions.caps_batch b ON b.id = r.batch_id WHERE r.id = a.admitted_from)),
        'admission', jsonb_build_object('application_no', a.application_no, 'programme', pr.name, 'programme_code', pr.code, 'degree_type', pr.category, 'faculty', pr.faculty, 'department', pr.department,
                                        'decision', a.decision, 'decision_basis', a.decision_basis, 'decision_released_at', a.decision_released_at, 'undertaking_at', a.undertaking_at, 'accepted_at', a.accepted_at,
                                        'acceptance_reference', ent.reference, 'acceptance_confirmed_at', ent.confirmed_at, 'admission_no', st.admission_no, 'matric_no', st.matric_no, 'student_status', st.status),
        'olevel', CASE WHEN jsonb_array_length(ol.rows) > 0 THEN ol.rows ELSE jol.rows END,
        'jamb_olevel', jol.rows,
        'institutions', inst.rows,
        'documents', docs.rows,
        'payments', pay.m,
        'answers', ans.m,
        'biodata', bio.m,
        'screening', CASE WHEN scr.application_id IS NULL THEN NULL ELSE jsonb_build_object('screening_no', scr.screening_no, 'state', scr.state, 'version', scr.version, 'decided_at', scr.decided_at, 'decided_office', scr.decided_office,
                                                                                            'decision_reason', scr.decision_reason, 'remarks', scr.remarks, 'returned_note', scr.returned_note, 'membership', scr.membership) END)
      FROM a, acc, cr, st, pr, photo, utme, ol, jol, docs, ans, bio, inst, pay, ent LEFT JOIN dob ON true LEFT JOIN scr ON true;
$$;
COMMENT ON FUNCTION admissions.screening_facts(uuid) IS 'The record the screening officers review and the screening forms are drawn from (V280): identity, JAMB, admission, O''Level, documents, payments, corrections and biodata — read from the authoritative tables, never copied.';

/* ── the screening forms as a document in the credential store ── */
ALTER TABLE credentials.document_policy DROP CONSTRAINT IF EXISTS ck_dp_kind;
ALTER TABLE credentials.document_policy ADD CONSTRAINT ck_dp_kind CHECK (kind IN ('DEGREE_CERTIFICATE', 'TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT', 'ADMISSION_LETTER', 'SCREENING_FORMS'));
INSERT INTO credentials.document_policy (kind, label, billable, fee, self_service, sla_days, number_prefix, graduates_only, public_fields)
VALUES ('SCREENING_FORMS', 'Screening forms', false, 0, true, 0, 'SCR', false, ARRAY['holder', 'programme', 'faculty', 'department', 'session', 'admissionType', 'screeningOutcome', 'decidedOn'])
ON CONFLICT (kind) DO NOTHING;
ALTER TABLE credentials.issued DROP CONSTRAINT IF EXISTS ck_issued_kind;
ALTER TABLE credentials.issued ADD CONSTRAINT ck_issued_kind CHECK (kind IN ('DEGREE_CERTIFICATE', 'TRANSCRIPT', 'STATEMENT_OF_RESULT', 'MATRICULATION', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT', 'ADMISSION_LETTER', 'SCREENING_FORMS'));

/* the forms of a successful screening: issued once under the screening number; a new version, the same number, when the record they were drawn from has changed */
CREATE OR REPLACE FUNCTION admissions.issue_screening_forms(p_app uuid)
RETURNS credentials.issued LANGUAGE plpgsql AS $$
DECLARE f admissions.screening_form; cur credentials.issued; facts jsonb; v_stmt jsonb; v_hash text; v_version int := 1; v_id uuid := gen_random_uuid();
        v_actor uuid; v_office text; v_student people.student; a admissions.application;
BEGIN
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    IF f.application_id IS NULL OR f.state <> 'SUCCESSFUL' THEN
        RAISE EXCEPTION 'the screening forms are generated once the screening is successful' USING ERRCODE = '23514', HINT = 'Wait for the University''s screening.';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO v_student FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    facts := admissions.screening_facts(p_app);
    SELECT * INTO cur FROM credentials.issued i WHERE i.application_id = p_app AND i.kind = 'SCREENING_FORMS' AND NOT EXISTS (SELECT 1 FROM credentials.issued x WHERE x.supersedes = i.id) ORDER BY i.version DESC LIMIT 1;
    -- the forms stand while the record they were drawn from stands
    IF cur.id IS NOT NULL AND (((cur.statement -> 'facts') - 'screening') - 'documents') - 'payments' = ((facts - 'screening') - 'documents') - 'payments' THEN RETURN cur; END IF;
    v_actor := coalesce(nullif(current_setting('moaum.actor_id', true), '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid);
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    IF v_office IS NULL OR NOT EXISTS (SELECT 1 FROM ref.office WHERE code = v_office) THEN v_office := 'academic'; END IF;
    IF cur.id IS NOT NULL THEN v_version := cur.version + 1; END IF;
    v_stmt := jsonb_build_object(
        'kind', 'SCREENING_FORMS', 'number', f.screening_no, 'version', v_version,
        'holder', (facts -> 'identity' ->> 'surname') || ', ' || (facts -> 'identity' ->> 'other_names'),
        'surname', facts -> 'identity' ->> 'surname', 'otherNames', facts -> 'identity' ->> 'other_names', 'jambRegNo', facts -> 'jamb' ->> 'jamb_reg_no', 'applicationNo', facts -> 'admission' ->> 'application_no',
        'session', a.session, 'programme', facts -> 'admission' ->> 'programme', 'faculty', facts -> 'admission' ->> 'faculty', 'department', facts -> 'admission' ->> 'department',
        'admissionType', (facts -> 'jamb' ->> 'entry_mode') || ' · ' || (facts -> 'jamb' ->> 'entry_level') || ' Level',
        'screeningOutcome', 'SUCCESSFUL', 'decidedOn', f.decided_at::date, 'decidedOffice', f.decided_office, 'remarks', f.remarks,
        'admissionNo', v_student.admission_no,
        'facts', facts, 'issuedOn', current_date, 'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi');
    v_hash := encode(sha256(convert_to(v_stmt::text, 'UTF8')), 'hex');
    INSERT INTO credentials.issued (id, kind, student_id, application_id, verification_code, statement, signature, signed_with, issuing_name, issued_on, issued_by, issued_office, supersedes, number, version, template_version, content_hash, note)
    VALUES (v_id, 'SCREENING_FORMS', v_student.id, p_app, credentials.new_code(), v_stmt, decode(v_hash, 'hex'), NULL, 'Rev. Fr. Moses Orshio Adasu University, Makurdi', current_date, v_actor, v_office, cur.id,
            f.screening_no, v_version, 280, v_hash, CASE WHEN cur.id IS NULL THEN 'Screening forms generated from the record' ELSE 'Regenerated: the record changed' END);
    PERFORM credentials.log(NULL, v_id, v_student.id, 'ISSUED', NULL, 'ACTIVE', 'SCREENING_FORMS ' || f.screening_no || ' v' || v_version);
    SELECT * INTO cur FROM credentials.issued WHERE id = v_id;
    RETURN cur;
END $$;

/* the document's own state, apart from the screening decision: not generated, generated, downloaded */
CREATE OR REPLACE FUNCTION admissions.screening_forms_state(p_app uuid)
RETURNS TABLE (state text, number text, version int, verification_code text, issued_on date, downloads bigint, last_downloaded_at timestamptz) LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN i.id IS NULL THEN 'NOT_GENERATED' WHEN d.n > 0 THEN 'DOWNLOADED' ELSE 'GENERATED' END, i.number, i.version, i.verification_code, i.issued_on, coalesce(d.n, 0), d.last_at
      FROM (SELECT 1) one
      LEFT JOIN LATERAL (SELECT * FROM credentials.issued x WHERE x.application_id = p_app AND x.kind = 'SCREENING_FORMS' AND NOT EXISTS (SELECT 1 FROM credentials.issued y WHERE y.supersedes = x.id) ORDER BY x.version DESC LIMIT 1) i ON true
      LEFT JOIN LATERAL (SELECT count(*) AS n, max(l.at) AS last_at FROM credentials.event l WHERE l.issued_id = i.id AND l.action = 'DOWNLOADED') d ON true;
$$;

CREATE OR REPLACE FUNCTION admissions.settle_acceptance(p_app uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$

DECLARE a admissions.application;

BEGIN

    SELECT * INTO a FROM admissions.application WHERE id = p_app;

    IF a.accepted_at IS NULL AND a.undertaking_at IS NOT NULL AND a.acceptance_confirmed_at IS NOT NULL AND a.declined_at IS NULL THEN

        UPDATE admissions.application SET accepted_at = now() WHERE id = p_app;

        UPDATE admissions.candidate SET offer_state = 'ACCEPTED' WHERE id = a.candidate_id AND offer_state = 'ADMITTED';

        -- where the session asks no screening, the register follows the acceptance (V278)

        PERFORM admissions.register_when_due(p_app);
        -- the University's screening opens on the record it already holds (V280): nothing is filled by the applicant
        IF admissions.screening_required(p_app) THEN PERFORM admissions.screening_open(p_app); END IF;

        PERFORM admissions.notify_applicant(p_app, 'Your place is held',

            'Your acceptance fee is confirmed and your undertaking is on record. Your place is held. Your admission now awaits the University''s screening, done on the information JAMB and your application already gave; the schools you attended are the only thing you enter. You will be told the outcome here and by email.',

            'MOAUM: your place is held. Your admission awaits the University''s screening.');

    END IF;

END $function$;

CREATE OR REPLACE FUNCTION admissions.screening_decide(p_app uuid, p_decision text, p_reason text, p_remarks text, p_actor uuid, p_office text)
 RETURNS admissions.screening_form
 LANGUAGE plpgsql
AS $function$



DECLARE f admissions.screening_form; a admissions.application; c admissions.candidate; v_alts int := 0; v_run uuid;



BEGIN



    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app FOR UPDATE;



    IF f.application_id IS NULL THEN RAISE EXCEPTION 'no screening form for this application' USING ERRCODE = '23503'; END IF;



    IF f.state NOT IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN RAISE EXCEPTION 'a decision is taken on a screening awaiting it; this one is %', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514'; END IF;



    SELECT * INTO a FROM admissions.application WHERE id = p_app;



    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;



    IF p_decision IN ('RETURNED', 'CORRECTION') THEN
        -- V280: one correction named; the applicant provides that and nothing else
        IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a correction names the one thing to be corrected' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.screening_form SET state = 'CORRECTION_REQUIRED', returned_note = btrim(p_reason), remarks = coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), remarks), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;
        PERFORM admissions.screening_log(p_app, 'CORRECTION_REQUIRED', btrim(p_reason));
        PERFORM admissions.notify_applicant(p_app, 'Your screening needs one correction',
            'The screening officers need one thing corrected on screening ' || f.screening_no || ': ' || btrim(p_reason) || ' Open Screening on your portal, provide it, and press "I have made the correction". Nothing else is asked of you.',
            'MOAUM: your screening needs one correction - see the portal.');
        RETURN f;
    ELSIF p_decision = 'SUCCESSFUL' THEN



        UPDATE admissions.screening_form SET state = 'SUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_reason = nullif(btrim(coalesce(p_reason, '')), ''),



               remarks = nullif(btrim(coalesce(p_remarks, '')), ''), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;



        -- the application is cleared (the stage the journey already knows), the answers go onto the record



        UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = p_app;



        PERFORM admissions.screening_apply_biodata(p_app);

        -- the register follows the screening (V278): the student record and the admission number, the moment the screening succeeds

        PERFORM admissions.register_when_due(p_app);
        -- the official screening forms are generated from the record (V280): the applicant prints them, never fills them
        PERFORM admissions.issue_screening_forms(p_app);



        PERFORM admissions.screening_log(p_app, 'SUCCESSFUL', coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), 'Successfully screened'));



        PERFORM admissions.notify_applicant(p_app, 'You have been successfully screened',



            'You have been successfully screened for ' || c.programme || '. Your screening forms have been generated from your record; view, download and print them on the portal. You can go ahead and pay school fees and commence registration using your admission number' || coalesce(' ' || (SELECT s.admission_no FROM people.student s WHERE s.candidate_id = c.id LIMIT 1), '') || '. Your matriculation number is issued afterwards over the list of students who registered.',



            'MOAUM: you have been successfully screened. You may now pay school fees and register.');



        RETURN f;



    ELSIF p_decision = 'UNSUCCESSFUL' THEN



        IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'an unsuccessful screening carries its reason' USING ERRCODE = '23514'; END IF;



        UPDATE admissions.screening_form SET state = 'UNSUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_reason = btrim(p_reason),



               remarks = nullif(btrim(coalesce(p_remarks, '')), ''), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;



        PERFORM admissions.screening_log(p_app, 'UNSUCCESSFUL', btrim(p_reason));



        -- the programmes the candidate does qualify for, read now by the engine



        v_run := admissions.evaluate_application(p_app, 'SYSTEM', p_actor);



        SELECT count(*) INTO v_alts FROM admissions.eligibility_result x WHERE x.run_id = v_run AND x.kind = 'ALTERNATIVE' AND x.result IN ('ELIGIBLE', 'ELIGIBLE_SCREENING');



        PERFORM admissions.notify_applicant(p_app, 'Your screening was not successful',



            'Your screening for ' || c.programme || ' was not successful. Reason: ' || btrim(p_reason) || ' '



            || CASE WHEN v_alts > 0 THEN 'Based on your results and the current admission policy, ' || v_alts || ' other programme(s) may be available to you; open Online Screening on your portal to apply for a change of programme. Your acceptance fee remains valid and is not paid again.'



                    ELSE 'No alternative programme was found on the current admission policy; contact the Admissions Office.' END,



            'MOAUM: your screening was not successful. ' || CASE WHEN v_alts > 0 THEN v_alts || ' other programme(s) may be open to you — see the portal.' ELSE 'See the portal for the reason.' END);



        RETURN f;



    END IF;



    RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';



END $function$;

CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
 RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean;

BEGIN

    SELECT * INTO a FROM admissions.application WHERE id = p_app;

    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;

    IF a.decision_released_at IS NULL OR a.decision IS NULL THEN RETURN QUERY SELECT 'PENDING', 'Admission pending', 'Wait for the Admissions Board', '/applicant/status', 'The decision is published here and by email.'; RETURN; END IF;

    -- the admission checking fee, its own payment, opens the released decision (V271); an acceptance already confirmed under the old rule counts as checked

    IF admissions.checking_due(p_app) THEN

        RETURN QUERY SELECT 'CHECKING_FEE_PENDING', 'Admission decision released', 'Pay the admission checking fee to view your admission status', '/applicant/admission',

            'The Admissions Board''s decision on your application has been released. It opens once the admission checking fee is confirmed; it is paid once, whatever follows.'; RETURN;

    END IF;

    IF a.decision <> 'OFFERED' THEN RETURN QUERY SELECT 'NOT_ADMITTED', CASE WHEN a.decision = 'WAITING' THEN 'Waiting list' ELSE 'Not admitted' END, NULL, '/applicant/status', a.decision_note; RETURN; END IF;

    IF a.declined_at IS NOT NULL THEN RETURN QUERY SELECT 'DECLINED', 'Offer declined', NULL, '/applicant/status', 'A declined offer is not reinstated.'; RETURN; END IF;

    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);

    -- the applicant reads the admission status — the offer, its programme, faculty and session — before anything is accepted (V271)

    IF a.accepted_at IS NULL AND a.status_checked_at IS NULL AND NOT ent.paid AND a.undertaking_at IS NULL THEN

        RETURN QUERY SELECT 'ADMITTED', 'Admitted — check your admission status', 'Check your admission status', '/applicant/admission', 'Congratulations: read the offer and its details, then accept it and pay the acceptance fee.'; RETURN;

    END IF;

    IF a.accepted_at IS NULL THEN

        IF ent.paid OR a.undertaking_at IS NOT NULL THEN RETURN QUERY SELECT 'ACCEPTANCE_PENDING', 'Acceptance in progress', CASE WHEN ent.paid THEN 'Sign the undertaking' ELSE 'Pay the acceptance fee' END, '/applicant/accept', 'The undertaking and the acceptance fee together accept the offer.'; RETURN; END IF;

        RETURN QUERY SELECT 'ADMITTED', 'Admitted — offer to accept', 'Pay the acceptance fee', '/applicant/accept', 'Accept the offer and pay the acceptance fee; the acceptance letter follows.'; RETURN;

    END IF;

    req := admissions.screening_required(p_app);

    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;

    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app ORDER BY x.requested_at DESC LIMIT 1;

    IF req AND NOT admissions.screening_ok(p_app) THEN

        -- the University screens on the record it holds (V280): the applicant waits (entering only the schools attended), or provides the one correction asked for
        IF f.application_id IS NULL OR f.state = 'PENDING' THEN RETURN QUERY SELECT 'SCREENING_PENDING', 'Accepted - awaiting screening', 'Wait for the University''s screening', '/applicant/clearance', 'Your information has been received. The University screens your admission on the information JAMB and your application already gave; the schools you attended are the only thing you enter. You will be told the outcome here and by email.'; RETURN; END IF;
        IF f.state = 'IN_REVIEW' THEN RETURN QUERY SELECT 'SCREENING_IN_REVIEW', 'Screening in progress', 'Wait for the screening officers', '/applicant/clearance', 'A screening officer opened your record' || coalesce(' on ' || to_char(f.review_started_at, 'DD Mon YYYY'), '') || '.'; RETURN; END IF;
        IF f.state = 'CORRECTION_REQUIRED' THEN RETURN QUERY SELECT 'SCREENING_CORRECTION', 'Screening: one correction required', 'Provide the correction', '/applicant/clearance', f.returned_note; RETURN; END IF;
        IF f.state = 'UNSUCCESSFUL' THEN

            IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND q.requested_at >= f.decided_at THEN RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Change of programme requested', 'Wait for the Admissions Office', '/applicant/clearance', 'Requested ' || q.to_programme || ' on ' || to_char(q.requested_at, 'DD Mon YYYY') || '.'; RETURN; END IF;

            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_REQUIRED', 'Screening unsuccessful', 'Apply for a change of programme', '/applicant/clearance', f.decision_reason; RETURN;

        END IF;

    END IF;

    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;

    IF s.id IS NULL THEN RETURN QUERY SELECT 'REGISTER_PENDING', CASE WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Wait for the Registry to bring you onto the register', '/applicant/matric', 'School fees open once you are on the register under your admission number.'; RETURN; END IF;

    IF s.matric_no IS NOT NULL THEN RETURN QUERY SELECT 'MATRICULATED', 'Matriculated', NULL, '/applicant/matric', 'Matriculation number ' || s.matric_no || ', issued ' || to_char(s.matriculated_at, 'DD Mon YYYY') || '. It is now your sign-in.'; RETURN; END IF;

    paid := coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);

    reg := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));

    IF NOT paid THEN RETURN QUERY SELECT 'SCHOOL_FEES_PENDING', CASE WHEN q.id IS NOT NULL AND q.state = 'APPROVED' THEN 'Change of programme approved' WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Pay school fees', '/student/fees', 'Sign in to the student portal with your admission number ' || coalesce(s.admission_no, '') || ' to pay.'; RETURN; END IF;

    IF NOT reg THEN RETURN QUERY SELECT 'COURSE_REGISTRATION_PENDING', 'School fees paid', 'Register your courses', '/student/registration', 'Registration is on the student portal.'; RETURN; END IF;

    RETURN QUERY SELECT 'MATRICULATION_PENDING', 'Ready for matriculation', 'Wait for the Academic Office to issue your number', '/applicant/matric', 'Your number is issued over the list of students who paid and registered.';

END $function$;

CREATE OR REPLACE FUNCTION admissions.admission_tracker(p_app uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; st record; req boolean; ent record; steps jsonb := '[]'::jsonb;

        paid boolean; reg boolean; offered boolean; accepted boolean; scr_done boolean; scr_failed boolean; chg_approved boolean;

BEGIN

    SELECT * INTO a FROM admissions.application WHERE id = p_app;

    SELECT * INTO st FROM admissions.admission_status(p_app);

    offered := a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL;

    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);

    accepted := a.accepted_at IS NOT NULL;

    req := admissions.screening_required(p_app);

    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;

    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app AND x.state IN ('REQUESTED', 'APPROVED') ORDER BY x.requested_at DESC LIMIT 1;

    scr_done := coalesce(f.state = 'SUCCESSFUL', false); scr_failed := coalesce(f.state = 'UNSUCCESSFUL', false);

    chg_approved := scr_failed AND coalesce(q.state = 'APPROVED' AND q.decided_at >= f.decided_at, false);

    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;

    paid := s.id IS NOT NULL AND coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);

    reg := s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));

    steps := steps || admissions.tracker_step('ADMISSION', 'JAMB admission', CASE WHEN offered THEN 'done' WHEN a.decision_released_at IS NULL THEN 'now' ELSE 'failed' END);

    steps := steps || admissions.tracker_step('ADMISSION_STATUS', 'Admission status checked', CASE WHEN ent.checking_paid OR a.status_checked_at IS NOT NULL OR accepted OR ent.paid OR a.undertaking_at IS NOT NULL THEN 'done' WHEN a.decision_released_at IS NOT NULL THEN 'now' ELSE 'todo' END);

    steps := steps || admissions.tracker_step('ACCEPTANCE_PAYMENT', 'Acceptance payment', CASE WHEN ent.paid THEN 'done' WHEN offered AND NOT admissions.checking_due(p_app) AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL) THEN 'now' ELSE 'todo' END);

    steps := steps || admissions.tracker_step('ACCEPTANCE_LETTER', 'Acceptance letter', CASE WHEN accepted THEN 'done' WHEN ent.paid THEN 'now' ELSE 'todo' END);

    IF req THEN

        steps := steps || admissions.tracker_step('SCREENING', 'University screening', CASE WHEN coalesce(f.state, '') IN ('SUCCESSFUL', 'UNSUCCESSFUL') THEN 'done' WHEN accepted THEN 'now' ELSE 'todo' END);

        IF scr_failed THEN

            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening unsuccessful', 'failed');

            steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme', CASE WHEN q.id IS NOT NULL AND q.requested_at >= f.decided_at THEN 'done' ELSE 'now' END);

            steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN chg_approved THEN 'done' WHEN q.id IS NOT NULL AND q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);

        ELSE

            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening successful', CASE WHEN scr_done THEN 'done' WHEN coalesce(f.state, '') IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN 'now' ELSE 'todo' END);
            steps := steps || admissions.tracker_step('SCREENING_FORMS', 'Screening forms generated', CASE WHEN scr_done THEN 'done' ELSE 'todo' END);

        END IF;

    END IF;

    steps := steps || admissions.tracker_step('SCHOOL_FEES', 'School fees', CASE WHEN paid THEN 'done' WHEN st.status = 'SCHOOL_FEES_PENDING' OR st.status = 'REGISTER_PENDING' THEN 'now' ELSE 'todo' END);

    steps := steps || admissions.tracker_step('COURSE_REGISTRATION', 'Course registration', CASE WHEN reg THEN 'done' WHEN st.status = 'COURSE_REGISTRATION_PENDING' THEN 'now' ELSE 'todo' END);

    steps := steps || admissions.tracker_step('MATRICULATION', 'Matriculation', CASE WHEN s.matric_no IS NOT NULL THEN 'done' WHEN st.status = 'MATRICULATION_PENDING' THEN 'now' ELSE 'todo' END);

    RETURN steps;

END $function$;

CREATE OR REPLACE FUNCTION admissions.pipeline_stats(p_session text)
 RETURNS TABLE(jamb_uploaded bigint, matched bigint, unmatched bigint, admitted bigint, acceptance_pending bigint, acceptance_paid bigint, screening_pending bigint, screening_submitted bigint, screening_successful bigint, screening_unsuccessful bigint, screening_returned bigint, change_requested bigint, change_approved bigint, fees_paid bigint, registered bigint, ready_for_matric bigint, matriculated bigint)
 LANGUAGE sql
 STABLE
AS $function$

    WITH apps AS (

        SELECT a.id, a.candidate_id, a.session, a.accepted_at, (SELECT e.paid FROM admissions.acceptance_entitlement(a.id) e) AS acc_paid, f.state AS scr,

               s.id AS student_id, s.matric_no,

               CASE WHEN s.id IS NULL THEN false ELSE coalesce((SELECT fp.paid_in_full FROM finance.position(s.id, a.session) fp), false) END AS paid,

               s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED')) AS reg

          FROM admissions.application a

          LEFT JOIN admissions.screening_form f ON f.application_id = a.id

          LEFT JOIN people.student s ON s.candidate_id = a.candidate_id

         WHERE a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL

    )

    SELECT (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session),

           (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session AND j.matched),

           (SELECT count(*) FROM admissions.jamb_admission j WHERE j.session = p_session AND NOT j.matched),

           count(*), count(*) FILTER (WHERE accepted_at IS NULL), count(*) FILTER (WHERE acc_paid),

           count(*) FILTER (WHERE accepted_at IS NOT NULL AND (scr IS NULL OR scr = 'PENDING') AND admissions.screening_required(id)),

           count(*) FILTER (WHERE scr = 'IN_REVIEW'), count(*) FILTER (WHERE scr = 'SUCCESSFUL'), count(*) FILTER (WHERE scr = 'UNSUCCESSFUL'), count(*) FILTER (WHERE scr = 'CORRECTION_REQUIRED'),

           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'REQUESTED'),

           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'APPROVED'),

           count(*) FILTER (WHERE paid), count(*) FILTER (WHERE reg),

           count(*) FILTER (WHERE paid AND reg AND matric_no IS NULL AND admissions.screening_ok(id)), count(*) FILTER (WHERE matric_no IS NOT NULL)

      FROM apps;

$function$;

CREATE OR REPLACE FUNCTION admissions.screening_save(p_app uuid, p_answers jsonb, p_institutions jsonb, p_olevel jsonb, p_membership text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$

DECLARE f admissions.screening_form; r record; n int := 0;

BEGIN

    f := admissions.screening_open(p_app);

    -- V280: the applicant enters only the schools attended with their dates (and a membership) while the screening is awaited;
    -- an answer or an O'Level change is taken only as the one correction an officer asked for; nothing after the decision
    IF (p_answers IS NOT NULL OR p_olevel IS NOT NULL) AND f.state <> 'CORRECTION_REQUIRED' THEN
        RAISE EXCEPTION 'SCREENING NOT FILLED: the University screens on the information it already holds; nothing is entered unless an officer asks for one correction' USING ERRCODE = '23514', HINT = 'Wait for the outcome of the screening.';
    END IF;
    IF f.state IN ('SUCCESSFUL', 'UNSUCCESSFUL') THEN

        RAISE EXCEPTION 'the screening is % and nothing more is entered', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514', HINT = 'An officer returns it for correction if something must change.';

    END IF;

    IF p_answers IS NOT NULL THEN

        FOR r IN SELECT key, value FROM jsonb_each_text(p_answers) LOOP

            IF NOT EXISTS (SELECT 1 FROM ref.biodata_field bf WHERE bf.field = r.key) THEN CONTINUE; END IF;

            INSERT INTO admissions.screening_answer (application_id, field, value) VALUES (p_app, r.key, left(btrim(coalesce(r.value, '')), 400))

            ON CONFLICT (application_id, field) DO UPDATE SET value = EXCLUDED.value;

        END LOOP;

    END IF;

    IF p_institutions IS NOT NULL THEN

        UPDATE admissions.screening_institution SET active = false WHERE application_id = p_app AND active;

        FOR r IN SELECT x.* FROM jsonb_to_recordset(p_institutions) AS x(name text, from_year int, to_year int, certificate text, award_year int) LOOP

            IF nullif(btrim(coalesce(r.name, '')), '') IS NULL THEN CONTINUE; END IF;

            n := n + 1;

            INSERT INTO admissions.screening_institution (application_id, ord, name, from_year, to_year, certificate, award_year, active)

            VALUES (p_app, n, left(btrim(r.name), 200), r.from_year, r.to_year, nullif(left(btrim(coalesce(r.certificate, '')), 100), ''), r.award_year, true)

            ON CONFLICT (application_id, ord) DO UPDATE SET name = EXCLUDED.name, from_year = EXCLUDED.from_year, to_year = EXCLUDED.to_year, certificate = EXCLUDED.certificate, award_year = EXCLUDED.award_year, active = true;

        END LOOP;

    END IF;

    IF p_olevel IS NOT NULL THEN

        UPDATE admissions.screening_olevel SET active = false WHERE application_id = p_app AND active;

        n := 0;

        FOR r IN SELECT x.* FROM jsonb_to_recordset(p_olevel) AS x(exam_body text, exam_number text, exam_year int, subject text, grade text) LOOP

            IF nullif(btrim(coalesce(r.subject, '')), '') IS NULL OR nullif(btrim(coalesce(r.grade, '')), '') IS NULL THEN CONTINUE; END IF;

            n := n + 1;

            INSERT INTO admissions.screening_olevel (application_id, ord, exam_body, exam_number, exam_year, subject, grade, active)

            VALUES (p_app, n, CASE WHEN upper(btrim(coalesce(r.exam_body, ''))) IN ('WAEC', 'NECO', 'NABTEB') THEN upper(btrim(r.exam_body)) ELSE 'OTHER' END,

                    nullif(left(btrim(coalesce(r.exam_number, '')), 40), ''), r.exam_year, left(btrim(r.subject), 80), upper(left(btrim(r.grade), 4)), true)

            ON CONFLICT (application_id, ord) DO UPDATE SET exam_body = EXCLUDED.exam_body, exam_number = EXCLUDED.exam_number, exam_year = EXCLUDED.exam_year, subject = EXCLUDED.subject, grade = EXCLUDED.grade, active = true;

        END LOOP;

    END IF;

    UPDATE admissions.screening_form SET membership = coalesce(nullif(btrim(coalesce(p_membership, '')), ''), membership), updated_at = now() WHERE application_id = p_app;

    PERFORM admissions.screening_log(p_app, 'SAVED', 'Draft saved');

END $function$;

-- the screenings already accepted and awaiting nothing but the office: opened now, so the queue holds them
DO $$
DECLARE r record; n int := 0;
BEGIN
    FOR r IN SELECT a.id FROM admissions.application a WHERE a.accepted_at IS NOT NULL AND a.declined_at IS NULL AND admissions.screening_required(a.id)
              AND NOT EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id)
    LOOP
        BEGIN PERFORM admissions.screening_open(r.id); n := n + 1; EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'V280: % not opened: %', r.id, SQLERRM; END;
    END LOOP;
    RAISE NOTICE 'V280: % screening(s) opened for the office', n;
END $$;

GRANT SELECT, INSERT ON credentials.event TO app_admissions, app_student;
GRANT SELECT, INSERT, UPDATE ON credentials.issued TO app_admissions, app_student;

COMMIT;

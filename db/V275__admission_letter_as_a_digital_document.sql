-- ═══════════════════════════════════════════════════════════════════════════
-- V275 — the admission letter is a digital document: numbered, hashed, verifiable
--
--   The letter of provisional admission was a PDF drawn on request with no
--   number and no way for a stranger to check it. It is now issued through
--   the credential store (V262) like a certificate or a transcript: a
--   document number ADM/YYYY/NNNNNN, a verification code, the statement it
--   stands on hashed, a QR code on the page that opens the public verifier,
--   and a new version — the same number — when an approved change of
--   programme alters what the letter says; the earlier version answers
--   REPLACED. The store is opened to an application, because the letter is
--   issued before the student is on the register.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V275: the admission letter as a digital document', true);

-- the kind, on the policy and on the store
ALTER TABLE credentials.document_policy DROP CONSTRAINT IF EXISTS ck_dp_kind;
ALTER TABLE credentials.document_policy ADD CONSTRAINT ck_dp_kind CHECK (kind IN ('DEGREE_CERTIFICATE', 'TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT', 'ADMISSION_LETTER'));
INSERT INTO credentials.document_policy (kind, label, billable, fee, self_service, sla_days, number_prefix, graduates_only, public_fields)
VALUES ('ADMISSION_LETTER', 'Letter of provisional admission', false, 0, true, 0, 'ADM', false, ARRAY['holder', 'programme', 'faculty', 'department', 'session', 'admissionType', 'acceptedOn'])
ON CONFLICT (kind) DO NOTHING;
ALTER TABLE credentials.issued DROP CONSTRAINT IF EXISTS ck_issued_kind;
ALTER TABLE credentials.issued ADD CONSTRAINT ck_issued_kind CHECK (kind IN ('DEGREE_CERTIFICATE', 'TRANSCRIPT', 'STATEMENT_OF_RESULT', 'MATRICULATION', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT', 'ADMISSION_LETTER'));

-- the store opened to an application: the letter comes before the register
ALTER TABLE credentials.issued ADD COLUMN IF NOT EXISTS application_id uuid NULL REFERENCES admissions.application(id);
ALTER TABLE credentials.issued ALTER COLUMN student_id DROP NOT NULL;
ALTER TABLE credentials.issued ADD CONSTRAINT ck_issued_subject CHECK (student_id IS NOT NULL OR application_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS ix_issued_application ON credentials.issued (application_id) WHERE application_id IS NOT NULL;

/* the letter of an accepted offer: issued once; a new version, the same number, when the programme it names has changed */
CREATE OR REPLACE FUNCTION admissions.issue_admission_letter(p_app uuid)
RETURNS credentials.issued LANGUAGE plpgsql AS $$
DECLARE a admissions.application; c admissions.candidate; cur credentials.issued; v_stmt jsonb; v_hash text; v_number text; v_version int := 1; v_id uuid := gen_random_uuid();
        v_actor uuid; v_office text; ent record; v_prog record; v_changed record; v_student people.student;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN RAISE EXCEPTION 'there is no offer to issue a letter for' USING ERRCODE = '23514'; END IF;
    IF a.accepted_at IS NULL THEN RAISE EXCEPTION 'the admission letter is issued once the offer is accepted and the acceptance fee confirmed' USING ERRCODE = '23514', HINT = 'Sign the undertaking and pay the acceptance fee, then print the letter.'; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT p.code, p.name, p.category, f.name AS faculty, d.name AS department INTO v_prog
      FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = admissions.programme_code_of(c.programme);
    SELECT * INTO cur FROM credentials.issued i WHERE i.application_id = p_app AND i.kind = 'ADMISSION_LETTER' AND NOT EXISTS (SELECT 1 FROM credentials.issued x WHERE x.supersedes = i.id) ORDER BY i.version DESC LIMIT 1;
    -- the letter stands while it names the programme the admission is for
    IF cur.id IS NOT NULL AND cur.statement->>'programme' = c.programme THEN RETURN cur; END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    SELECT * INTO v_student FROM people.student WHERE candidate_id = c.id LIMIT 1;
    SELECT q.from_programme, q.to_programme, q.decided_at INTO v_changed FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'APPROVED' ORDER BY q.decided_at DESC LIMIT 1;
    v_actor := coalesce(nullif(current_setting('moaum.actor_id', true), '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid);
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    IF v_office IS NULL OR NOT EXISTS (SELECT 1 FROM ref.office WHERE code = v_office) THEN v_office := 'registrar'; END IF;
    IF cur.id IS NOT NULL THEN v_version := cur.version + 1; v_number := cur.number; ELSE v_number := credentials.next_document_number('ADMISSION_LETTER'); END IF;
    v_stmt := jsonb_build_object(
        'kind', 'ADMISSION_LETTER', 'number', v_number, 'version', v_version,
        'holder', c.surname || ', ' || c.other_names, 'surname', c.surname, 'otherNames', c.other_names, 'jambRegNo', c.jamb_reg_no, 'applicationNo', a.application_no,
        'session', a.session, 'programme', c.programme, 'programmeCode', v_prog.code, 'degreeType', v_prog.category, 'faculty', v_prog.faculty, 'department', v_prog.department,
        'admissionType', c.entry_mode || ' · ' || c.entry_level || ' Level', 'entryMode', c.entry_mode, 'entryLevel', c.entry_level, 'basis', a.decision_basis,
        'decisionReleasedOn', a.decision_released_at::date, 'acceptedOn', a.accepted_at::date, 'acceptanceReference', ent.reference, 'acceptanceConfirmedOn', ent.confirmed_at::date,
        'admissionNo', v_student.admission_no,
        'changedFrom', v_changed.from_programme, 'changedTo', v_changed.to_programme, 'changedOn', v_changed.decided_at::date,
        'issuedOn', current_date, 'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi');
    v_hash := encode(sha256(convert_to(v_stmt::text, 'UTF8')), 'hex');
    INSERT INTO credentials.issued (id, kind, student_id, application_id, verification_code, statement, signature, signed_with, issuing_name, issued_on, issued_by, issued_office, supersedes, number, version, template_version, content_hash, note)
    VALUES (v_id, 'ADMISSION_LETTER', v_student.id, p_app, credentials.new_code(), v_stmt, decode(v_hash, 'hex'), NULL, 'Rev. Fr. Moses Orshio Adasu University, Makurdi', current_date, v_actor, v_office, cur.id,
            v_number, v_version, NULL, v_hash, CASE WHEN cur.id IS NULL THEN 'Letter of provisional admission' ELSE 'Reissued: the programme changed to ' || c.programme END);
    PERFORM credentials.log(NULL, v_id, v_student.id, 'ISSUED', NULL, 'ACTIVE', 'ADMISSION_LETTER ' || v_number || ' v' || v_version || ' · ' || c.programme);
    SELECT * INTO cur FROM credentials.issued WHERE id = v_id;
    RETURN cur;
END $$;

GRANT SELECT, INSERT, UPDATE ON credentials.issued TO app_admissions, app_student;
GRANT SELECT ON credentials.document_policy TO app_admissions, app_student;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- V269 — online screening and the admission lifecycle, JAMB list to matriculation
--
--   The portal already carries the journey: the JAMB list and its matching
--   (V081), the offer, the undertaking and the acceptance fee (V021/V025), the
--   acceptance letter, the register (intake), school fees, course registration,
--   the eligibility engine and its programme-change queue (V266) and
--   Matriculation Management (V267). What it lacked was the SCREENING of fresh
--   students the Registry does on paper (Form A, the Screening of Fresh
--   Undergraduate Students form, the Supplementary Biodata form and the
--   departmental data-capture form), the decision that ends it — "you have
--   been successfully screened; go ahead and pay school fees" — and the doors
--   that decision opens or keeps shut. This migration adds exactly that:
--     · a screening policy per session (on, from when, the documents and the
--       fields required), so nothing is hard-coded and existing students who
--       accepted before it are not held;
--     · the screening form on the application: answers keyed on the student
--       biodata catalogue (ref.biodata_field — the fields the forms ask for
--       that the catalogue lacked are added to it, never duplicated), the
--       institutions attended, the O'Level results as the candidate declares
--       them beside JAMB's, the documents (the existing application_document
--       with the kinds the forms name), the declaration, the trail;
--     · the officer's decision: SUCCESSFUL (the application is cleared, the
--       answers go onto the student record), UNSUCCESSFUL (with the reason;
--       the eligibility engine lists the programmes the candidate qualifies
--       for and the existing change-of-programme queue takes the request —
--       the acceptance fee is paid once, for the admission, never again),
--       RETURNED for correction;
--     · the lifecycle status and the tracker, one function each, read by the
--       applicant's page and the desks; the gates: school fees, course
--       registration and matriculation wait for a successful screening or an
--       approved change of programme where the policy requires one;
--     · the pipeline statistics and the matriculation broadcast.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V269: online screening and the admission lifecycle', true);

-- ── 1 · the fields the forms ask for that the catalogue lacked ───────────

ALTER TABLE ref.biodata_field DROP CONSTRAINT IF EXISTS ck_biodata_section;
ALTER TABLE ref.biodata_field ADD CONSTRAINT ck_biodata_section CHECK (section IN ('personal', 'contact', 'origin', 'family', 'kin', 'health', 'bank', 'education'));
INSERT INTO ref.biodata_field (field, section, label, tier, hint, wide, ord) VALUES
    ('maiden_name',              'personal',  'Maiden name',                                  'open', 'Where applicable', false, 41),
    ('children',                 'personal',  'Number of children',                           'open', NULL, false, 42),
    ('hobbies',                  'personal',  'Hobbies, skills, handwork',                    'open', NULL, false, 43),
    ('postal_address',           'contact',   'Postal address',                               'open', NULL, true, 44),
    ('parent_profession',        'family',    'Profession of parent or guardian',             'open', NULL, false, 45),
    ('parent_income',            'family',    'Estimated annual income of parent or guardian', 'open', 'In naira', false, 46),
    ('primary_school',           'education', 'Primary school attended',                      'open', NULL, true, 47),
    ('primary_fees_per_term',    'education', 'Primary school fees paid per term',            'open', 'In naira', false, 48),
    ('secondary_school',         'education', 'Secondary school attended',                    'open', NULL, true, 49),
    ('secondary_fees_per_term',  'education', 'Secondary school fees paid per term',          'open', 'In naira', false, 50),
    ('secondary_graduation_year','education', 'Year of graduation from secondary school',     'open', NULL, false, 51),
    ('alevel_institution',       'education', 'Institution of A-Level / NCE / OND (Direct Entry)', 'open', 'Direct Entry candidates only', true, 52),
    ('alevel_graduation_year',   'education', 'Year of graduation from A-Level / NCE / OND',  'open', 'Direct Entry candidates only', false, 53),
    ('working_experience',       'education', 'Working experience, if any',                   'open', 'Rank, place and duration', true, 54),
    ('memberships',              'education', 'Membership of any association, club, union or society', 'open', NULL, true, 55)
ON CONFLICT (field) DO NOTHING;

-- the documents the forms name, on the existing application document
ALTER TABLE admissions.application_document DROP CONSTRAINT IF EXISTS ck_doc_kind;
ALTER TABLE admissions.application_document ADD CONSTRAINT ck_doc_kind CHECK (kind IN (
    'OLEVEL_STATEMENT', 'BIRTH_CERT', 'LGA_ID', 'JAMB_SLIP', 'PASSPORT',
    'JAMB_ADMISSION_LETTER', 'STATE_OF_ORIGIN', 'MARRIAGE_CERT', 'CHANGE_OF_NAME', 'PREVIOUS_QUALIFICATION', 'OTHER'));

-- ── 2 · the policy, the form, its parts, the trail ───────────────────────

CREATE TABLE admissions.screening_policy (
    session            text PRIMARY KEY REFERENCES policy.academic_session(name),
    enabled            boolean NOT NULL DEFAULT true,
    enabled_from       timestamptz NOT NULL DEFAULT now(),     -- an applicant who accepted before this is not held to the screening
    required_documents text[] NOT NULL DEFAULT ARRAY['OLEVEL_STATEMENT', 'JAMB_SLIP', 'BIRTH_CERT', 'LGA_ID', 'PASSPORT'],
    required_fields    text[] NOT NULL DEFAULT ARRAY['nationality', 'state_of_origin', 'lga', 'religion', 'marital_status', 'home_address', 'mobile',
                                                      'sponsor_name', 'sponsor_address', 'kin_name', 'kin_mobile', 'kin_relationship', 'secondary_school', 'secondary_graduation_year'],
    instructions       text NULL,
    updated_at         timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('admissions.screening_policy');
COMMENT ON TABLE admissions.screening_policy IS
    'Whether and how a session screens its fresh students online (V269): on or off, from when, which documents and which fields the form requires. Nothing is hard-coded.';
-- every session that has admission settings screens from now on; earlier acceptances are not held
INSERT INTO admissions.screening_policy (session)
SELECT DISTINCT p.session FROM admissions.session_policy p JOIN policy.academic_session a ON a.name = p.session ON CONFLICT DO NOTHING;   -- only sessions the calendar knows

CREATE TABLE admissions.screening_form (
    application_id    uuid PRIMARY KEY REFERENCES admissions.application(id),
    screening_no      text NOT NULL UNIQUE,
    state             text NOT NULL DEFAULT 'DRAFT',
    version           int NOT NULL DEFAULT 0,
    opened_at         timestamptz NOT NULL DEFAULT now(),
    submitted_at      timestamptz NULL,
    submitted_ip      text NULL,
    declaration_at    timestamptz NULL,
    review_started_at timestamptz NULL,
    review_started_by uuid NULL,
    decided_at        timestamptz NULL,
    decided_by        uuid NULL,
    decided_office    text NULL,
    decision_reason   text NULL,
    remarks           text NULL,
    returned_note     text NULL,
    membership        text NULL,
    updated_at        timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_sf_state CHECK (state IN ('DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'RETURNED', 'SUCCESSFUL', 'UNSUCCESSFUL')),
    CONSTRAINT ck_sf_unsuccessful CHECK (state <> 'UNSUCCESSFUL' OR nullif(btrim(coalesce(decision_reason, '')), '') IS NOT NULL),
    CONSTRAINT ck_sf_returned CHECK (state <> 'RETURNED' OR nullif(btrim(coalesce(returned_note, '')), '') IS NOT NULL)
);
SELECT audit.attach('admissions.screening_form');

CREATE TABLE admissions.screening_answer (
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    field          text NOT NULL REFERENCES ref.biodata_field(field),
    value          text NOT NULL,
    PRIMARY KEY (application_id, field)
);
SELECT audit.exempt('admissions.screening_answer', 'The answers on a screening form; the act (save, submit, decide) is on the form and its trail.');

CREATE TABLE admissions.screening_institution (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    ord            int NOT NULL,
    name           text NOT NULL,
    from_year      int NULL,
    to_year        int NULL,
    certificate    text NULL,
    award_year     int NULL,
    active         boolean NOT NULL DEFAULT true,
    UNIQUE (application_id, ord)
);
SELECT audit.exempt('admissions.screening_institution', 'A row of the screening form (institutions attended); the act is on the form.');

CREATE TABLE admissions.screening_olevel (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    ord            int NOT NULL,
    exam_body      text NOT NULL,
    exam_number    text NULL,
    exam_year      int NULL,
    subject        text NOT NULL,
    grade          text NOT NULL,
    active         boolean NOT NULL DEFAULT true,
    UNIQUE (application_id, ord),
    CONSTRAINT ck_so_body CHECK (exam_body IN ('WAEC', 'NECO', 'NABTEB', 'OTHER'))
);
SELECT audit.exempt('admissions.screening_olevel', 'The O''Level results as the candidate declares them on the screening form, beside JAMB''s; the act is on the form.');

CREATE TABLE admissions.screening_event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    action         text NOT NULL,
    detail         text NULL,
    actor          uuid NULL,
    actor_office   text NULL,
    at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_screening_event_app ON admissions.screening_event (application_id, at);
SELECT audit.exempt('admissions.screening_event', 'Write-once trail of the screening: opened, saved, submitted, review started, returned, decided, programme changed.');
CREATE OR REPLACE FUNCTION admissions.screening_event_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'the screening trail is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_screening_event_once BEFORE UPDATE OR DELETE ON admissions.screening_event FOR EACH ROW EXECUTE FUNCTION admissions.screening_event_once();

CREATE OR REPLACE FUNCTION admissions.screening_log(p_app uuid, p_action text, p_detail text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO admissions.screening_event (application_id, action, detail, actor, actor_office)
    VALUES (p_app, p_action, p_detail, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
$$;

-- ── 3 · is a screening required, and is it satisfied ─────────────────────

CREATE OR REPLACE FUNCTION admissions.screening_required(p_app uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT sp.enabled AND (a.accepted_at IS NULL OR a.accepted_at >= sp.enabled_from)
                       FROM admissions.application a JOIN admissions.screening_policy sp ON sp.session = a.session WHERE a.id = p_app), false);
$$;

/* the screening is satisfied: not required; or SUCCESSFUL; or UNSUCCESSFUL and a change of programme approved since */
CREATE OR REPLACE FUNCTION admissions.screening_ok(p_app uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT NOT admissions.screening_required(p_app)
        OR EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = p_app AND f.state = 'SUCCESSFUL')
        OR EXISTS (SELECT 1 FROM admissions.screening_form f JOIN admissions.programme_change_request q ON q.application_id = f.application_id
                    WHERE f.application_id = p_app AND f.state = 'UNSUCCESSFUL' AND q.state = 'APPROVED' AND q.decided_at >= f.decided_at);
$$;

/* the same, from the student's side: a student who came through an application of this portal */
CREATE OR REPLACE FUNCTION admissions.screening_ok_student(p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT bool_and(admissions.screening_ok(a.id))
                       FROM people.student s JOIN admissions.application a ON a.candidate_id = s.candidate_id
                      WHERE s.id = p_student AND a.accepted_at IS NOT NULL), true);
$$;

/* the acceptance fee is paid once, for the admission — it belongs to the application, whatever the programme becomes */
CREATE OR REPLACE FUNCTION admissions.acceptance_entitlement(p_app uuid)
RETURNS TABLE (paid boolean, reference text, confirmed_at timestamptz, amount numeric)
LANGUAGE sql STABLE AS $$
    SELECT (a.acceptance_confirmed_at IS NOT NULL OR fr.confirmed_at IS NOT NULL), fr.reference, coalesce(a.acceptance_confirmed_at, fr.confirmed_at), fr.amount
      FROM admissions.application a
      LEFT JOIN LATERAL (SELECT r.reference, r.confirmed_at, r.amount FROM admissions.fee_reference r WHERE r.application_id = a.id AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NOT NULL ORDER BY r.confirmed_at LIMIT 1) fr ON true
     WHERE a.id = p_app;
$$;

-- ── 4 · the form: open, save, submit ─────────────────────────────────────

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
    INSERT INTO admissions.screening_form (application_id, screening_no) VALUES (p_app, v_no) RETURNING * INTO f;
    -- the O'Level results as JAMB sent them are offered as the first draft, for the candidate to confirm or correct
    INSERT INTO admissions.screening_olevel (application_id, ord, exam_body, exam_number, exam_year, subject, grade)
    SELECT p_app, row_number() OVER (ORDER BY st.ord, g.subject), st.exam_body, st.exam_number, nullif(regexp_replace(coalesce(st.exam_year, ''), '[^0-9]', '', 'g'), '')::int, g.subject, g.grade
      FROM admissions.candidate c JOIN admissions.olevel_sitting st ON st.session = c.session AND st.jamb_key = c.jamb_key JOIN admissions.olevel_grade g ON g.sitting_id = st.id
     WHERE c.id = a.candidate_id;
    PERFORM admissions.screening_log(p_app, 'OPENED', 'Screening form ' || v_no || ' opened');
    RETURN f;
END $$;

/* answers keyed on the biodata catalogue; the institutions and the O'Level rows replaced whole; only while the form is the candidate's */
CREATE OR REPLACE FUNCTION admissions.screening_save(p_app uuid, p_answers jsonb, p_institutions jsonb, p_olevel jsonb, p_membership text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE f admissions.screening_form; r record; n int := 0;
BEGIN
    f := admissions.screening_open(p_app);
    IF f.state NOT IN ('DRAFT', 'RETURNED') THEN
        RAISE EXCEPTION 'the screening form is % and no longer edited', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514', HINT = 'An officer returns it for correction if something must change.';
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
END $$;

/* what still stands in the way of a submission: the required fields and documents, at least one O'Level row */
CREATE OR REPLACE FUNCTION admissions.screening_missing(p_app uuid)
RETURNS TABLE (kind text, item text, label text)
LANGUAGE sql STABLE AS $$
    SELECT 'FIELD', f, bf.label
      FROM admissions.application a JOIN admissions.screening_policy sp ON sp.session = a.session CROSS JOIN unnest(sp.required_fields) AS f
      JOIN ref.biodata_field bf ON bf.field = f
     WHERE a.id = p_app AND NOT EXISTS (SELECT 1 FROM admissions.screening_answer x WHERE x.application_id = p_app AND x.field = f AND btrim(x.value) <> '')
    UNION ALL
    SELECT 'DOCUMENT', d, initcap(replace(lower(d), '_', ' '))
      FROM admissions.application a JOIN admissions.screening_policy sp ON sp.session = a.session CROSS JOIN unnest(sp.required_documents) AS d
     WHERE a.id = p_app AND NOT EXISTS (SELECT 1 FROM admissions.application_document x WHERE x.application_id = p_app AND x.kind = d AND x.status <> 'REJECTED')
    UNION ALL
    SELECT 'OLEVEL', 'OLEVEL', 'At least one O''Level result'
     WHERE NOT EXISTS (SELECT 1 FROM admissions.screening_olevel x WHERE x.application_id = p_app AND x.active);
$$;

CREATE OR REPLACE FUNCTION admissions.screening_submit(p_app uuid, p_declaration boolean, p_ip text)
RETURNS admissions.screening_form LANGUAGE plpgsql AS $$
DECLARE f admissions.screening_form; v_missing text; c admissions.candidate; a admissions.application;
BEGIN
    f := admissions.screening_open(p_app);
    IF f.state NOT IN ('DRAFT', 'RETURNED') THEN RAISE EXCEPTION 'the screening form is already %', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    IF NOT coalesce(p_declaration, false) THEN RAISE EXCEPTION 'the declaration was not accepted' USING ERRCODE = '23514', HINT = 'Read the declaration and tick that you accept it.'; END IF;
    SELECT string_agg(label, ', ' ORDER BY kind, label) INTO v_missing FROM admissions.screening_missing(p_app);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'the screening form is not complete: %', v_missing USING ERRCODE = '23514', HINT = 'Fill every required field, upload every required document and list your O''Level results.';
    END IF;
    UPDATE admissions.screening_form SET state = 'SUBMITTED', version = version + 1, submitted_at = now(), submitted_ip = p_ip, declaration_at = now(), returned_note = NULL, updated_at = now()
     WHERE application_id = p_app RETURNING * INTO f;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    PERFORM admissions.screening_log(p_app, CASE WHEN f.version > 1 THEN 'RESUBMITTED' ELSE 'SUBMITTED' END, 'Version ' || f.version || ' submitted from ' || coalesce(p_ip, '?'));
    PERFORM admissions.notify_applicant(p_app, 'Your screening form has been received',
        'Your screening form ' || f.screening_no || ' for ' || c.programme || ' was received on ' || to_char(now(), 'DD Mon YYYY HH24:MI') || '. It is now with the screening officers; you will be told the outcome here and by email.',
        'MOAUM: screening form ' || f.screening_no || ' received. You will be told the outcome.');
    PERFORM admissions.tell_office('academic', 'A screening form awaits review', c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || ') submitted screening form ' || f.screening_no || ' for ' || c.programme || '.', p_app);
    RETURN f;
END $$;

-- ── 5 · the officer: review, return, decide ──────────────────────────────

CREATE OR REPLACE FUNCTION admissions.screening_start_review(p_app uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE admissions.screening_form SET state = 'UNDER_REVIEW', review_started_at = now(), review_started_by = p_actor, updated_at = now() WHERE application_id = p_app AND state = 'SUBMITTED';
    IF FOUND THEN PERFORM admissions.screening_log(p_app, 'REVIEW_STARTED', NULL); END IF;
END $$;

/* the answers of a successful screening become the student's biodata, where the student is already on the register */
CREATE OR REPLACE FUNCTION admissions.screening_apply_biodata(p_app uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_student uuid; n int := 0;
BEGIN
    SELECT s.id INTO v_student FROM admissions.application a JOIN people.student s ON s.candidate_id = a.candidate_id WHERE a.id = p_app LIMIT 1;
    IF v_student IS NULL THEN RETURN 0; END IF;
    INSERT INTO people.biodata (student_id, field, value)
    SELECT v_student, x.field, x.value FROM admissions.screening_answer x JOIN admissions.screening_form f ON f.application_id = x.application_id
     WHERE x.application_id = p_app AND f.state = 'SUCCESSFUL'
    ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION admissions.screening_decide(p_app uuid, p_decision text, p_reason text, p_remarks text, p_actor uuid, p_office text)
RETURNS admissions.screening_form LANGUAGE plpgsql AS $$
DECLARE f admissions.screening_form; a admissions.application; c admissions.candidate; v_alts int := 0; v_run uuid;
BEGIN
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app FOR UPDATE;
    IF f.application_id IS NULL THEN RAISE EXCEPTION 'no screening form for this application' USING ERRCODE = '23503'; END IF;
    IF f.state NOT IN ('SUBMITTED', 'UNDER_REVIEW') THEN RAISE EXCEPTION 'a decision is taken on a submitted form; this one is %', lower(replace(f.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    IF p_decision = 'RETURNED' THEN
        IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'a form returned for correction says what must be corrected' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.screening_form SET state = 'RETURNED', returned_note = btrim(p_reason), remarks = coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), remarks), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;
        PERFORM admissions.screening_log(p_app, 'RETURNED', btrim(p_reason));
        PERFORM admissions.notify_applicant(p_app, 'Your screening form needs a correction',
            'The screening officers returned your form ' || f.screening_no || ' for correction: ' || btrim(p_reason) || ' Open Online Screening on your portal, make the correction and submit again.',
            'MOAUM: your screening form was returned for correction — see the portal.');
        RETURN f;
    ELSIF p_decision = 'SUCCESSFUL' THEN
        UPDATE admissions.screening_form SET state = 'SUCCESSFUL', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_reason = nullif(btrim(coalesce(p_reason, '')), ''),
               remarks = nullif(btrim(coalesce(p_remarks, '')), ''), updated_at = now() WHERE application_id = p_app RETURNING * INTO f;
        -- the application is cleared (the stage the journey already knows), the answers go onto the record
        UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = p_app;
        PERFORM admissions.screening_apply_biodata(p_app);
        PERFORM admissions.screening_log(p_app, 'SUCCESSFUL', coalesce(nullif(btrim(coalesce(p_remarks, '')), ''), 'Successfully screened'));
        PERFORM admissions.notify_applicant(p_app, 'You have been successfully screened',
            'You have been successfully screened for ' || c.programme || '. You can go ahead and pay school fees and commence registration using your admission number. Your matriculation number is issued afterwards over the list of students who registered.',
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
END $$;

-- a student brought onto the register after a successful screening takes the answers then
CREATE OR REPLACE FUNCTION admissions.screening_on_intake()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_app uuid;
BEGIN
    IF NEW.candidate_id IS NULL THEN RETURN NEW; END IF;
    FOR v_app IN SELECT a.id FROM admissions.application a JOIN admissions.screening_form f ON f.application_id = a.id WHERE a.candidate_id = NEW.candidate_id AND f.state = 'SUCCESSFUL' LOOP
        INSERT INTO people.biodata (student_id, field, value) SELECT NEW.id, x.field, x.value FROM admissions.screening_answer x WHERE x.application_id = v_app
        ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
    END LOOP;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_screening_on_intake AFTER INSERT ON people.student FOR EACH ROW EXECUTE FUNCTION admissions.screening_on_intake();

-- ── 6 · the gates: school fees, course registration ──────────────────────

CREATE OR REPLACE FUNCTION admissions.screening_refuse_student(p_student uuid, p_what text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.screening_override', true) = 'on' THEN RETURN; END IF;
    IF NOT admissions.screening_ok_student(p_student) THEN
        RAISE EXCEPTION '% UNAVAILABLE: the online screening must be successful first (or a change of programme approved)', p_what
            USING ERRCODE = '23514', HINT = 'Complete Online Screening on the applicant portal; the screening officers decide, and the door opens with their decision.';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION admissions.screening_gate_course_registration()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' OR (NEW.status = 'SUBMITTED' AND NEW.status IS DISTINCT FROM OLD.status) THEN
        PERFORM admissions.screening_refuse_student(NEW.student_id, 'COURSE REGISTRATION');
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_screening_gate_registration BEFORE INSERT OR UPDATE OF status ON registration.course_registration
FOR EACH ROW EXECUTE FUNCTION admissions.screening_gate_course_registration();

-- ── 7 · the lifecycle status and the tracker ─────────────────────────────

CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
RETURNS TABLE (status text, label text, next_action text, next_href text, detail text)
LANGUAGE plpgsql STABLE AS $$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;
    IF a.decision_released_at IS NULL OR a.decision IS NULL THEN RETURN QUERY SELECT 'PENDING', 'Admission pending', 'Wait for the Admissions Board', '/applicant/status', 'The decision is published here and by email.'; RETURN; END IF;
    IF a.decision <> 'OFFERED' THEN RETURN QUERY SELECT 'NOT_ADMITTED', CASE WHEN a.decision = 'WAITING' THEN 'Waiting list' ELSE 'Not admitted' END, NULL, '/applicant/status', a.decision_note; RETURN; END IF;
    IF a.declined_at IS NOT NULL THEN RETURN QUERY SELECT 'DECLINED', 'Offer declined', NULL, '/applicant/status', 'A declined offer is not reinstated.'; RETURN; END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    IF a.accepted_at IS NULL THEN
        IF ent.paid OR a.undertaking_at IS NOT NULL THEN RETURN QUERY SELECT 'ACCEPTANCE_PENDING', 'Acceptance in progress', CASE WHEN ent.paid THEN 'Sign the undertaking' ELSE 'Pay the acceptance fee' END, '/applicant/accept', 'The undertaking and the acceptance fee together accept the offer.'; RETURN; END IF;
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — offer to accept', 'Pay the acceptance fee', '/applicant/accept', 'Accept the offer and pay the acceptance fee; the acceptance letter follows.'; RETURN;
    END IF;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app ORDER BY x.requested_at DESC LIMIT 1;
    IF req AND NOT admissions.screening_ok(p_app) THEN
        IF f.application_id IS NULL THEN RETURN QUERY SELECT 'SCREENING_PENDING', 'Accepted — screening to complete', 'Complete the online screening', '/applicant/clearance', 'Your acceptance letter is ready; the online screening is the next step.'; RETURN; END IF;
        IF f.state = 'DRAFT' THEN RETURN QUERY SELECT 'SCREENING_IN_PROGRESS', 'Screening form in progress', 'Complete and submit the screening form', '/applicant/clearance', NULL; RETURN; END IF;
        IF f.state = 'RETURNED' THEN RETURN QUERY SELECT 'SCREENING_RETURNED', 'Screening form returned for correction', 'Correct and resubmit the screening form', '/applicant/clearance', f.returned_note; RETURN; END IF;
        IF f.state IN ('SUBMITTED', 'UNDER_REVIEW') THEN RETURN QUERY SELECT 'SCREENING_SUBMITTED', 'Screening under review', 'Wait for the screening officers', '/applicant/clearance', 'Submitted ' || to_char(f.submitted_at, 'DD Mon YYYY') || '.'; RETURN; END IF;
        IF f.state = 'UNSUCCESSFUL' THEN
            IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND q.requested_at >= f.decided_at THEN RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Change of programme requested', 'Wait for the Admissions Office', '/applicant/clearance', 'Requested ' || q.to_programme || ' on ' || to_char(q.requested_at, 'DD Mon YYYY') || '.'; RETURN; END IF;
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_REQUIRED', 'Screening unsuccessful', 'Apply for a change of programme', '/applicant/clearance', f.decision_reason; RETURN;
        END IF;
    END IF;
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    IF s.id IS NULL THEN RETURN QUERY SELECT 'REGISTER_PENDING', CASE WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Wait for the Registry to bring you onto the register', '/applicant/matric', 'School fees open once you are on the register under your admission number.'; RETURN; END IF;
    IF s.matric_no IS NOT NULL THEN RETURN QUERY SELECT 'MATRICULATED', 'Matriculated', NULL, '/applicant/matric', 'Matriculation number ' || s.matric_no || ', issued ' || to_char(s.matriculated_at, 'DD Mon YYYY') || '. It is now your sign-in.'; RETURN; END IF;
    paid := coalesce((SELECT fp.paid_in_full FROM finance.position(s.id, a.session) fp), false);
    reg := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    IF NOT paid THEN RETURN QUERY SELECT 'SCHOOL_FEES_PENDING', CASE WHEN q.id IS NOT NULL AND q.state = 'APPROVED' THEN 'Change of programme approved' WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Pay school fees', '/student/fees', 'Sign in to the student portal with your admission number ' || coalesce(s.admission_no, '') || ' to pay.'; RETURN; END IF;
    IF NOT reg THEN RETURN QUERY SELECT 'COURSE_REGISTRATION_PENDING', 'School fees paid', 'Register your courses', '/student/registration', 'Registration is on the student portal.'; RETURN; END IF;
    RETURN QUERY SELECT 'MATRICULATION_PENDING', 'Ready for matriculation', 'Wait for the Academic Office to issue your number', '/applicant/matric', 'Your number is issued over the list of students who paid and registered.';
END $$;

CREATE OR REPLACE FUNCTION admissions.tracker_step(k text, l text, st text)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT jsonb_build_object('key', k, 'label', l, 'state', st) $$;

/* the tracker: only the steps that concern this applicant, each done, now, todo or failed */
CREATE OR REPLACE FUNCTION admissions.admission_tracker(p_app uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
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
    paid := s.id IS NOT NULL AND coalesce((SELECT fp.paid_in_full FROM finance.position(s.id, a.session) fp), false);
    reg := s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    steps := steps || admissions.tracker_step('ADMISSION', 'JAMB admission', CASE WHEN offered THEN 'done' WHEN a.decision_released_at IS NULL THEN 'now' ELSE 'failed' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_PAYMENT', 'Acceptance payment', CASE WHEN ent.paid THEN 'done' WHEN offered THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_LETTER', 'Acceptance letter', CASE WHEN accepted THEN 'done' WHEN ent.paid THEN 'now' ELSE 'todo' END);
    IF req THEN
        steps := steps || admissions.tracker_step('SCREENING', 'Online screening', CASE WHEN coalesce(f.state, '') IN ('SUBMITTED', 'UNDER_REVIEW', 'SUCCESSFUL', 'UNSUCCESSFUL') THEN 'done' WHEN accepted THEN 'now' ELSE 'todo' END);
        IF scr_failed THEN
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening unsuccessful', 'failed');
            steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme', CASE WHEN q.id IS NOT NULL AND q.requested_at >= f.decided_at THEN 'done' ELSE 'now' END);
            steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN chg_approved THEN 'done' WHEN q.id IS NOT NULL AND q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
        ELSE
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening approval', CASE WHEN scr_done THEN 'done' WHEN coalesce(f.state, '') IN ('SUBMITTED', 'UNDER_REVIEW') THEN 'now' ELSE 'todo' END);
        END IF;
    END IF;
    steps := steps || admissions.tracker_step('SCHOOL_FEES', 'School fees', CASE WHEN paid THEN 'done' WHEN st.status = 'SCHOOL_FEES_PENDING' OR st.status = 'REGISTER_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('COURSE_REGISTRATION', 'Course registration', CASE WHEN reg THEN 'done' WHEN st.status = 'COURSE_REGISTRATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('MATRICULATION', 'Matriculation', CASE WHEN s.matric_no IS NOT NULL THEN 'done' WHEN st.status = 'MATRICULATION_PENDING' THEN 'now' ELSE 'todo' END);
    RETURN steps;
END $$;

-- ── 8 · the pipeline and the screening queue, counted ────────────────────

CREATE OR REPLACE FUNCTION admissions.pipeline_stats(p_session text)
RETURNS TABLE (jamb_uploaded bigint, matched bigint, unmatched bigint, admitted bigint, acceptance_pending bigint, acceptance_paid bigint, screening_pending bigint, screening_submitted bigint,
               screening_successful bigint, screening_unsuccessful bigint, screening_returned bigint, change_requested bigint, change_approved bigint, fees_paid bigint, registered bigint, ready_for_matric bigint, matriculated bigint)
LANGUAGE sql STABLE AS $$
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
           count(*) FILTER (WHERE accepted_at IS NOT NULL AND (scr IS NULL OR scr = 'DRAFT') AND admissions.screening_required(id)),
           count(*) FILTER (WHERE scr IN ('SUBMITTED', 'UNDER_REVIEW')), count(*) FILTER (WHERE scr = 'SUCCESSFUL'), count(*) FILTER (WHERE scr = 'UNSUCCESSFUL'), count(*) FILTER (WHERE scr = 'RETURNED'),
           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'REQUESTED'),
           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'APPROVED'),
           count(*) FILTER (WHERE paid), count(*) FILTER (WHERE reg),
           count(*) FILTER (WHERE paid AND reg AND matric_no IS NULL AND admissions.screening_ok(id)), count(*) FILTER (WHERE matric_no IS NOT NULL)
      FROM apps;
$$;

-- ── 9 · the matriculation broadcast ──────────────────────────────────────

CREATE TABLE people.matric_broadcast (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id   uuid NOT NULL REFERENCES people.matric_batch(id),
    sent_by    uuid NULL,
    office     text NULL,
    sent_at    timestamptz NOT NULL DEFAULT now(),
    recipients int NOT NULL DEFAULT 0,
    only_failed boolean NOT NULL DEFAULT false,
    note       text NULL
);
SELECT audit.attach('people.matric_broadcast');

/* the matriculation told to every student of an issued batch — faculty, department, programme, session, the sign-in — and recorded; the failed re-sent on request */
CREATE OR REPLACE FUNCTION people.matric_batch_broadcast(p_batch uuid, p_only_failed boolean, p_actor uuid, p_office text)
RETURNS TABLE (broadcast_id uuid, recipients int)
LANGUAGE plpgsql AS $$
DECLARE b people.matric_batch; r record; reach record; n int := 0; v_id uuid;
BEGIN
    SELECT * INTO b FROM people.matric_batch WHERE id = p_batch;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such batch' USING ERRCODE = '23503'; END IF;
    IF b.state <> 'ISSUED' THEN RAISE EXCEPTION 'only an issued batch is broadcast' USING ERRCODE = '23514'; END IF;
    INSERT INTO people.matric_broadcast (batch_id, sent_by, office, only_failed) VALUES (p_batch, p_actor, p_office, coalesce(p_only_failed, false)) RETURNING id INTO v_id;
    FOR r IN SELECT s.id, s.surname, s.other_names, s.matric_no, s.entry_session, p.name AS programme, d.name AS department, f.name AS faculty
               FROM people.matric_batch_row br JOIN people.student s ON s.id = br.student_id
               LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              WHERE br.batch_id = p_batch AND br.state = 'ISSUED'
                AND (NOT coalesce(p_only_failed, false) OR EXISTS (SELECT 1 FROM platform.notice nt WHERE nt.about_kind = 'student' AND nt.about_id = s.id AND nt.state = 'FAILED' AND nt.subject ILIKE 'Your matriculation%'))
              ORDER BY s.surname, s.other_names LOOP
        SELECT * INTO reach FROM people.student_reach(r.id);
        PERFORM platform.queue_notice('EMAIL', reach.email, 'Your matriculation — ' || r.matric_no,
            'Congratulations ' || r.other_names || ' ' || r.surname || '. Your matriculation has been successfully completed.'
            || E'\n\nMatriculation number: ' || r.matric_no
            || E'\nFaculty: ' || coalesce(r.faculty, '—') || E'\nDepartment: ' || coalesce(r.department, '—') || E'\nProgramme: ' || coalesce(r.programme, '—') || E'\nSession: ' || coalesce(r.entry_session, b.session)
            || E'\n\nYour matriculation number is now your student sign-in username. Sign in to the University Portal with it and the password you already use; it does not change.'
            || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'student', r.id);
        PERFORM platform.queue_notice('SMS', reach.phone, 'Your matriculation — ' || r.matric_no, 'MOAUM: you are matriculated. Your matriculation number ' || r.matric_no || ' is now your portal sign-in. Password unchanged.', 'student', r.id);
        n := n + 1;
    END LOOP;
    UPDATE people.matric_broadcast SET recipients = n WHERE id = v_id;
    RETURN QUERY SELECT v_id, n;
END $$;

-- ── 10 · grants ──────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON admissions.screening_policy, admissions.screening_form, admissions.screening_answer, admissions.screening_institution, admissions.screening_olevel, admissions.screening_event TO app_admissions, app_student;
GRANT SELECT ON admissions.screening_policy, admissions.screening_form, admissions.screening_answer, admissions.screening_institution, admissions.screening_olevel, admissions.screening_event TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON people.matric_broadcast TO app_student;
GRANT SELECT ON people.matric_broadcast TO app_auditor;

-- ── 11 · the existing functions made lifecycle-aware ─────────────────────

/* V267's candidates, with the screening as one more reason a student is pending */
CREATE OR REPLACE FUNCTION people.matric_candidates(p_session text, p_faculty text)
RETURNS TABLE (student_id uuid, admission_no text, surname text, other_names text, programme_code text, programme text, dept_code text, department text,
               faculty_code text, faculty text, entry_session text, status text, matric_no text, matriculated_at timestamptz,
               registered boolean, paid boolean, query_reason text, config_problem text, eligible boolean, reason text,
               batch_id uuid, batch_ref text, batch_state text, row_id uuid, proposed_no text, row_state text, problems text[], edited boolean, series_code text, sequence bigint)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT s.id, s.admission_no, s.surname, s.other_names, p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department,
               f.code AS faculty_code, f.name AS faculty, s.entry_session, s.status, s.matric_no, s.matriculated_at,
               EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = p_session AND r.status IN ('APPROVED', 'LOCKED')) AS registered,
               coalesce((SELECT fp.paid_in_full FROM finance.position(s.id, p_session) fp), false) AS paid,
               (SELECT q.reason FROM people.faculty_list l JOIN people.faculty_list_query q ON q.list_id = l.id AND q.student_id = s.id AND q.withdrawn_at IS NULL
                 WHERE l.session = p_session AND l.faculty_code = f.code LIMIT 1) AS query_reason,
               (SELECT c.problem FROM people.matric_components(s.id) c) AS config_problem
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN ref.department d ON d.code = p.dept_code
         WHERE f.code = p_faculty
           AND ((s.status = 'ADMITTED' AND s.matric_no IS NULL
                 AND (s.entry_session = p_session OR EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = p_session)))
                OR (s.matric_no IS NOT NULL AND (s.entry_session = p_session
                     OR EXISTS (SELECT 1 FROM people.matric_batch_row br JOIN people.matric_batch b ON b.id = br.batch_id WHERE br.student_id = s.id AND b.session = p_session AND br.state = 'ISSUED'))))
    ), judged AS (
        SELECT b.*,
               CASE WHEN b.matric_no IS NOT NULL THEN 'Already matriculated as ' || b.matric_no
                    WHEN b.status <> 'ADMITTED' THEN 'The student is ' || lower(b.status)
                    WHEN b.query_reason IS NOT NULL THEN 'Under query on the faculty list: ' || b.query_reason
                    WHEN NOT admissions.screening_ok_student(b.id) THEN 'Online screening not successful (or change of programme not yet approved)'
                    WHEN NOT b.registered THEN 'No approved course registration for ' || p_session
                    WHEN NOT b.paid THEN 'School fees for ' || p_session || ' not settled'
                    WHEN b.config_problem IS NOT NULL THEN b.config_problem
                    END AS reason
          FROM base b
    )
    SELECT j.id, j.admission_no, j.surname, j.other_names, j.programme_code, j.programme, j.dept_code, j.department, j.faculty_code, j.faculty, j.entry_session,
           j.status, j.matric_no, j.matriculated_at, j.registered, j.paid, j.query_reason, j.config_problem, j.reason IS NULL, j.reason,
           mb.id, mb.ref, mb.state, br.id, br.proposed_no, br.state, br.problems, br.edited, br.series_code, br.sequence
      FROM judged j
      LEFT JOIN people.matric_batch mb ON mb.session = p_session AND mb.faculty_code = j.faculty_code AND mb.state NOT IN ('ISSUED', 'CANCELLED')
      LEFT JOIN people.matric_batch_row br ON br.batch_id = mb.id AND br.student_id = j.id AND br.state <> 'DROPPED'
     ORDER BY j.surname, j.other_names;
$$;


/* V266's change of programme, open after an unsuccessful screening; the approval follows the student onto the register and carries the acceptance fee */
CREATE OR REPLACE FUNCTION admissions.request_programme_change(p_app uuid, p_to text, p_note text, p_by_kind text, p_by uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a admissions.application; c admissions.candidate; g ref.programme; r record; v_run uuid; v_id uuid; v_from text;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    -- after the Board's decision a change is possible only where the online screening was unsuccessful (V269): the screening committee's path, once
    IF a.decision_released_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = p_app AND f.state = 'UNSUCCESSFUL') THEN
        RAISE EXCEPTION 'the Board''s decision on this application has been released; a change of programme is a new decision of the Board' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.screening_form f JOIN admissions.programme_change_request q0 ON q0.application_id = f.application_id
                WHERE f.application_id = p_app AND f.state = 'UNSUCCESSFUL' AND q0.state = 'APPROVED' AND q0.decided_at >= f.decided_at) THEN
        RAISE EXCEPTION 'a change of programme has already been approved after the screening' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO g FROM ref.programme WHERE code = p_to;
    IF g.code IS NULL OR g.archived THEN RAISE EXCEPTION 'no such active programme %', p_to USING ERRCODE = '23514'; END IF;
    v_from := admissions.programme_code_of(c.programme);
    IF v_from = p_to THEN RAISE EXCEPTION 'that is the programme applied for' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a change of programme is already requested and awaits the Admissions Office' USING ERRCODE = '23514';
    END IF;
    -- read again now, never from a stale screen
    v_run := admissions.eligibility_current(p_app, p_by);
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, p_to, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        RAISE EXCEPTION 'the candidate is not eligible for %: %', g.name, array_to_string(r.reasons, '; ') USING ERRCODE = '23514',
              HINT = 'A programme is requested only when every mandatory requirement is met on the current admission policy.';
    END IF;
    INSERT INTO admissions.programme_change_request (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme, run_id, eligibility_at_request, requested_by_kind, requested_by, note)
    VALUES (p_app, c.id, a.session, v_from, c.programme, p_to, g.name, v_run, r.result, p_by_kind, p_by, nullif(btrim(coalesce(p_note, '')), ''))
    RETURNING id INTO v_id;
    PERFORM admissions.eligibility_log(p_app, v_run, 'PROGRAMME_CHANGE_REQUESTED', p_to, r.result, 'From ' || c.programme || ' to ' || g.name || coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    PERFORM admissions.notify_applicant(p_app, 'Your request to change programme has been received',
        'Your request to be considered for ' || g.name || ' in place of ' || c.programme || ' has been received and is with the Admissions Office. Your programme changes only when the Office approves; you will be told.',
        'MOAUM: your request to change to ' || g.name || ' is with the Admissions Office.');
    PERFORM admissions.tell_office('academic', 'A programme change request awaits the Admissions Office',
        'Applicant ' || c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || ') asks to move from ' || c.programme || ' to ' || g.name || '; the engine finds them ' || lower(replace(r.result, '_', ' ')) || '. Open Programme eligibility on the admissions desk to decide.', p_app);
    RETURN v_id;
END $$;


CREATE OR REPLACE FUNCTION admissions.decide_programme_change(p_req uuid, p_decision text, p_note text, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE q admissions.programme_change_request; a admissions.application; c admissions.candidate; r record; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    SELECT * INTO q FROM admissions.programme_change_request WHERE id = p_req FOR UPDATE;
    IF q.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF q.state <> 'REQUESTED' THEN RAISE EXCEPTION 'the request is already %', lower(q.state) USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = q.application_id;
    SELECT * INTO c FROM admissions.candidate WHERE id = q.candidate_id;
    IF p_decision = 'REJECT' THEN
        IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.programme_change_request SET state = 'REJECTED', decided_at = now(), decided_by = p_actor, decision_note = v_note WHERE id = q.id;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_REJECTED', q.to_programme_code, NULL, v_note);
        PERFORM admissions.notify_applicant(q.application_id, 'Your request to change programme was not approved', 'Your request to move to ' || q.to_programme || ' was not approved by the Admissions Office. Reason: ' || v_note || ' Your application for ' || q.from_programme || ' stands as it was.', NULL);
        RETURN 'REJECTED';
    ELSIF p_decision = 'APPROVE' THEN
        IF a.decision_released_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'UNSUCCESSFUL') THEN
            RAISE EXCEPTION 'the Board''s decision has been released; the programme is not changed under it' USING ERRCODE = '23514';
        END IF;
        -- eligibility read again at the moment of decision
        SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, q.to_programme_code, c.entry_mode);
        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
            RAISE EXCEPTION 'on the current settings the candidate is no longer eligible for %: %', q.to_programme, array_to_string(r.reasons, '; ') USING ERRCODE = '23514';
        END IF;
        UPDATE admissions.candidate SET programme = q.to_programme WHERE id = c.id;
        -- the student on the register, not yet matriculated, follows the programme (V269); the original stays on the request and the trail
        UPDATE people.student SET programme_code = q.to_programme_code WHERE candidate_id = c.id AND matric_no IS NULL;
        IF EXISTS (SELECT 1 FROM admissions.screening_form f WHERE f.application_id = a.id AND f.state = 'UNSUCCESSFUL') THEN
            -- the acceptance fee was paid for the admission, once: the approved change carries the entitlement and opens school fees
            UPDATE admissions.application SET cleared_at = coalesce(cleared_at, now()) WHERE id = a.id;
            PERFORM admissions.screening_log(a.id, 'PROGRAMME_CHANGED', 'From ' || q.from_programme || ' to ' || q.to_programme || ' after an unsuccessful screening; acceptance fee already paid, not charged again');
            PERFORM admissions.notify_applicant(a.id, 'Programme change approved — next step: school fees',
                'Your change of programme from ' || q.from_programme || ' to ' || q.to_programme || ' is approved. Your acceptance fee, already paid, remains valid and is not paid again. The next step is school fees, on the student portal under your admission number.',
                'MOAUM: your change to ' || q.to_programme || ' is approved. Acceptance fee not charged again; next, school fees.');
        END IF;
        UPDATE admissions.programme_change_request SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decision_note = v_note, eligibility_at_decision = r.result WHERE id = q.id;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_APPROVED', q.to_programme_code, r.result, 'From ' || q.from_programme || ' to ' || q.to_programme || coalesce(' · ' || v_note, ''));
        PERFORM admissions.evaluate_application(q.application_id, 'PROGRAMME_CHANGE', p_actor);
        PERFORM admissions.notify_applicant(q.application_id, 'Your programme has been changed to ' || q.to_programme,
            'The Admissions Office has approved your request: your application is now for ' || q.to_programme || ' (' || r.result || ' on the current admission policy). This is not an offer of admission; the Admissions Board decides in the normal way.' || coalesce(' Note: ' || v_note, ''),
            'MOAUM: your application is now for ' || q.to_programme || '. This is not yet an offer of admission.');
        RETURN 'APPROVED';
    ELSE
        RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';
    END IF;
END $$;

-- ── 9 · what the desk reads ───────────────────────────────────────────────


/* V026's school-fee reference, behind the screening */
CREATE OR REPLACE FUNCTION finance.new_reference(p_student uuid, p_session text, p_amount numeric, p_purpose text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE pos record; v_ref text; v_matric text;
BEGIN
    -- school fees wait for a successful online screening where the session requires one (V269)
    PERFORM admissions.screening_refuse_student(p_student, 'SCHOOL FEES');
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    IF pos.due = 0 THEN
        RAISE EXCEPTION 'no charge is stated for % yet', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the session''s fee schedule before anything is paid against it.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'a payment is for an amount' USING ERRCODE = '23514';
    END IF;
    IF p_amount > pos.balance THEN
        RAISE EXCEPTION 'the amount % is more than the balance of %', p_amount, pos.balance USING ERRCODE = '23514',
            HINT = 'Pay the balance, or part of it; nothing is taken beyond what is owed.';
    END IF;
    SELECT coalesce(matric_no, admission_no, 'X') INTO v_matric FROM people.student WHERE id = p_student;
    v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
    VALUES (p_student, p_session, v_ref, coalesce(p_purpose, 'School fees ' || p_session), p_amount, now() + interval '24 hours');
    RETURN v_ref;
END $$;


COMMIT;

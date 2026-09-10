-- ═══════════════════════════════════════════════════════════════════════════
-- V070 — inter-departmental transfer
--
--   A matriculated student asks to move from their department to another. The
--   application carries what the Special Admissions and Admission Irregularities
--   Committee (SAIC) needs to weigh it: the student's current department and
--   level, mode of entry, UTME score and CGPA (snapshotted from the results as
--   they stand), the course applied for and the reason. The committee either
--   RECOMMENDS the case for a named level, or does NOT recommend it. Recommended
--   cases go to Senate for approval. An approved candidate pays a non-refundable
--   processing fee, prints an approval letter, and the transfer is then effected
--   on the register — the programme and level change; the matriculation number,
--   which is the student's identity, does not. A case recommended in error is
--   withdrawn, which is the second memo the office issues.
--
--   Every step is one attributed act on the audit spine; nothing is deleted.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'V070: inter-departmental transfer', true);
END $seed$;

CREATE TABLE people.transfer_application (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id          uuid NOT NULL REFERENCES people.student(id),
    session             text NOT NULL,
    from_programme_code text NOT NULL REFERENCES ref.programme(code),
    from_level          int NOT NULL,
    to_programme_code   text NOT NULL REFERENCES ref.programme(code),
    reason              text NOT NULL,
    mode_of_entry       text NOT NULL,
    utme_score          int NULL,
    cgpa                numeric(3,2) NULL,
    state               text NOT NULL DEFAULT 'APPLIED',
    applied_at          timestamptz NOT NULL DEFAULT now(),
    applied_by          uuid NULL,
    recommended_level   int NULL,
    committee_note      text NULL,
    reviewed_at         timestamptz NULL,
    reviewed_by         uuid NULL,
    senate_at           timestamptz NULL,
    senate_by           uuid NULL,
    senate_note         text NULL,
    fee_reference       text NULL,
    effected_at         timestamptz NULL,
    effected_by         uuid NULL,
    withdrawn_why       text NULL,
    CONSTRAINT ck_ta_state CHECK (state IN ('APPLIED','RECOMMENDED','NOT_RECOMMENDED','APPROVED','DECLINED','EFFECTED','WITHDRAWN')),
    CONSTRAINT ck_ta_reason CHECK (btrim(reason) <> ''),
    CONSTRAINT ck_ta_different CHECK (from_programme_code <> to_programme_code),
    CONSTRAINT ck_ta_levels CHECK (from_level IN (100,200,300,400,500,600)
        AND (recommended_level IS NULL OR recommended_level IN (100,200,300,400,500,600)))
);
CREATE INDEX ix_ta_student ON people.transfer_application (student_id, applied_at DESC);
CREATE INDEX ix_ta_state ON people.transfer_application (session, state);
-- a student may carry only one live application at a time
CREATE UNIQUE INDEX uq_ta_live ON people.transfer_application (student_id)
    WHERE state IN ('APPLIED','RECOMMENDED','APPROVED');
SELECT audit.attach('people.transfer_application');

-- the processing fee (non-refundable), in naira
CREATE OR REPLACE FUNCTION people.transfer_fee()
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$ SELECT 10000::numeric $$;

-- a student applies to move to another programme
CREATE OR REPLACE FUNCTION people.apply_transfer(p_student uuid, p_to_programme text, p_reason text, p_utme int DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; s people.student; v_cgpa numeric; v_session text; v_id uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a transfer is applied for by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    IF s.matric_no IS NULL OR s.status NOT IN ('ACTIVE','PROBATION') THEN
        RAISE EXCEPTION 'only a matriculated, active student may apply to transfer' USING ERRCODE = '23514',
            HINT = 'Complete matriculation and be in good standing first.';
    END IF;
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'a transfer carries the reason it is sought' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM ref.programme WHERE code = p_to_programme AND NOT archived) THEN
        RAISE EXCEPTION 'the course applied for is not an offered programme' USING ERRCODE = '23503';
    END IF;
    IF p_to_programme = s.programme_code THEN
        RAISE EXCEPTION 'the course applied for is the student''s own department' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM people.transfer_application WHERE student_id = p_student AND state IN ('APPLIED','RECOMMENDED','APPROVED')) THEN
        RAISE EXCEPTION 'a transfer application is already in progress for this student' USING ERRCODE = '23505',
            HINT = 'One application runs at a time; wait for it to conclude.';
    END IF;
    SELECT name INTO v_session FROM policy.academic_session WHERE state = 'CURRENT';
    v_session := coalesce(v_session, s.entry_session);
    SELECT g.cgpa INTO v_cgpa FROM assessment.student_gpa(p_student) g WHERE g.cgpa IS NOT NULL ORDER BY g.session DESC, g.semester DESC LIMIT 1;
    INSERT INTO people.transfer_application (student_id, session, from_programme_code, from_level, to_programme_code, reason, mode_of_entry, utme_score, cgpa, applied_by)
    VALUES (p_student, v_session, s.programme_code, s.current_level, p_to_programme, btrim(p_reason), s.entry_mode, p_utme, v_cgpa, who)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- the committee's decision: recommend for a level, or do not recommend
CREATE OR REPLACE FUNCTION people.review_transfer(p_id uuid, p_recommend boolean, p_level int, p_note text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a case is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state <> 'APPLIED' THEN RAISE EXCEPTION 'application % has no case to consider', p_id USING ERRCODE = '23514'; END IF;
    IF p_recommend THEN
        IF p_level IS NULL OR p_level NOT IN (100,200,300,400,500,600) THEN
            RAISE EXCEPTION 'a recommendation names the level to admit into' USING ERRCODE = '23514';
        END IF;
        UPDATE people.transfer_application SET state = 'RECOMMENDED', recommended_level = p_level,
            committee_note = nullif(btrim(coalesce(p_note, '')), ''), reviewed_at = now(), reviewed_by = who WHERE id = p_id;
    ELSE
        IF p_note IS NULL OR btrim(p_note) = '' THEN RAISE EXCEPTION 'a case not recommended says why' USING ERRCODE = '23514'; END IF;
        UPDATE people.transfer_application SET state = 'NOT_RECOMMENDED', committee_note = btrim(p_note), reviewed_at = now(), reviewed_by = who WHERE id = p_id;
    END IF;
END $$;

-- Senate approves (or declines) a recommended case
CREATE OR REPLACE FUNCTION people.senate_transfer(p_id uuid, p_approve boolean, p_note text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a Senate decision is recorded by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state <> 'RECOMMENDED' THEN RAISE EXCEPTION 'application % is not before Senate', p_id USING ERRCODE = '23514'; END IF;
    UPDATE people.transfer_application SET state = CASE WHEN p_approve THEN 'APPROVED' ELSE 'DECLINED' END,
        senate_at = now(), senate_by = who, senate_note = nullif(btrim(coalesce(p_note, '')), '') WHERE id = p_id;
END $$;

-- a case recommended or approved in error is withdrawn (the second memo)
CREATE OR REPLACE FUNCTION people.withdraw_transfer(p_id uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a withdrawal is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a withdrawal says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state NOT IN ('RECOMMENDED','APPROVED') THEN RAISE EXCEPTION 'application % cannot be withdrawn', p_id USING ERRCODE = '23514'; END IF;
    UPDATE people.transfer_application SET state = 'WITHDRAWN', withdrawn_why = btrim(p_why) WHERE id = p_id;
END $$;

-- the approved candidate's processing-fee reference (non-refundable)
CREATE OR REPLACE FUNCTION people.transfer_fee_reference(p_id uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE t people.transfer_application; v_name text; v_ref text;
BEGIN
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state <> 'APPROVED' THEN RAISE EXCEPTION 'application % is not approved for payment', p_id USING ERRCODE = '23514'; END IF;
    IF t.fee_reference IS NOT NULL THEN RETURN t.fee_reference; END IF;
    SELECT name INTO v_name FROM ref.programme WHERE code = t.to_programme_code;
    v_ref := finance.new_purpose_reference(t.student_id, t.session, people.transfer_fee(), 'Inter-departmental transfer to ' || coalesce(v_name, t.to_programme_code));
    UPDATE people.transfer_application SET fee_reference = v_ref WHERE id = p_id;
    RETURN v_ref;
END $$;

-- once approved and the fee is confirmed, the transfer is effected on the register
CREATE OR REPLACE FUNCTION people.effect_transfer(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application; st record;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'the register is changed by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state <> 'APPROVED' THEN RAISE EXCEPTION 'application % is not approved', p_id USING ERRCODE = '23514'; END IF;
    IF t.fee_reference IS NULL THEN RAISE EXCEPTION 'the processing fee has not been generated' USING ERRCODE = '23514'; END IF;
    SELECT * INTO st FROM finance.reference_state(t.fee_reference);
    IF st.confirmed_at IS NULL THEN
        RAISE EXCEPTION 'the non-refundable processing fee is not yet confirmed' USING ERRCODE = '23514',
            HINT = 'The student pays the reference; effect the transfer once it clears.';
    END IF;
    UPDATE people.student SET programme_code = t.to_programme_code, current_level = coalesce(t.recommended_level, current_level)
     WHERE id = t.student_id;
    UPDATE people.transfer_application SET state = 'EFFECTED', effected_at = now(), effected_by = who WHERE id = p_id;
END $$;

-- the queue and the memos: an application with the student and the programmes named
CREATE OR REPLACE FUNCTION people.transfer_list(p_session text, p_state text)
RETURNS TABLE (id uuid, student_id uuid, name text, matric_no text, from_programme text, from_level int,
               to_programme text, mode_of_entry text, utme_score int, cgpa numeric, reason text, state text,
               recommended_level int, committee_note text, senate_note text, withdrawn_why text,
               applied_at timestamptz, reviewed_at timestamptz, senate_at timestamptz, effected_at timestamptz,
               fee_reference text, fee_confirmed_at timestamptz, session text)
LANGUAGE sql STABLE AS $$
    SELECT t.id, t.student_id, s.surname || ', ' || s.other_names, s.matric_no,
           fp.name, t.from_level, tp.name, t.mode_of_entry, t.utme_score, t.cgpa, t.reason, t.state,
           t.recommended_level, t.committee_note, t.senate_note, t.withdrawn_why,
           t.applied_at, t.reviewed_at, t.senate_at, t.effected_at,
           t.fee_reference, fs.confirmed_at, t.session
      FROM people.transfer_application t
      JOIN people.student s ON s.id = t.student_id
      LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code
      LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
      LEFT JOIN LATERAL finance.reference_state(t.fee_reference) fs ON t.fee_reference IS NOT NULL
     WHERE (p_session IS NULL OR t.session = p_session)
       AND (p_state IS NULL OR t.state = p_state)
     ORDER BY t.applied_at
$$;

COMMIT;

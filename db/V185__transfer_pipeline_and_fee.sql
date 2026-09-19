-- ═══════════════════════════════════════════════════════════════════════════
-- V185 — inter-departmental transfer: a four-office approval pipeline, and the
--        processing fee set by the Bursary (not hard-coded)
--
--   The transfer now moves through four desks, each a single Approve:
--     Student applies        → the application sits with the CURRENT department
--     Current dept approves  → it sits with the NEW department
--     New dept accepts       → it sits with the REGISTRAR
--     Registrar approves     → it sits with the ACADEMIC office
--     Academic approves      → APPROVED; the student pays the fee; it is effected
--   Any desk may decline (with a reason). The processing fee now reads from
--   finance.fee_setting.transfer_fee, which the Bursary sets, defaulting to the
--   old ₦10,000 when unset.
--
--   Every step stays one attributed act on the audit spine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'academic', true);
    PERFORM set_config('moaum.reason', 'V185: transfer pipeline and Bursary-set fee', true);
END $seed$;

-- ── #2 the fee is a Bursary-set item ───────────────────────────────────────
ALTER TABLE finance.fee_setting ADD COLUMN IF NOT EXISTS transfer_fee numeric(12,2) NULL;

CREATE OR REPLACE FUNCTION people.transfer_fee()
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT transfer_fee FROM finance.fee_setting WHERE id = 1), 10000::numeric)
$$;

-- ── #3 the pipeline: new stages and per-desk audit columns ─────────────────
ALTER TABLE people.transfer_application
    ADD COLUMN IF NOT EXISTS from_dept_at timestamptz NULL,
    ADD COLUMN IF NOT EXISTS from_dept_by uuid NULL,
    ADD COLUMN IF NOT EXISTS to_dept_at   timestamptz NULL,
    ADD COLUMN IF NOT EXISTS to_dept_by   uuid NULL,
    ADD COLUMN IF NOT EXISTS reg_at       timestamptz NULL,
    ADD COLUMN IF NOT EXISTS reg_by       uuid NULL,
    ADD COLUMN IF NOT EXISTS acad_at      timestamptz NULL,
    ADD COLUMN IF NOT EXISTS acad_by      uuid NULL,
    ADD COLUMN IF NOT EXISTS decline_note text NULL;

-- extend the state set to the new chain (a superset — existing rows still satisfy it)
ALTER TABLE people.transfer_application DROP CONSTRAINT ck_ta_state;
ALTER TABLE people.transfer_application ADD CONSTRAINT ck_ta_state
    CHECK (state IN ('APPLIED','FROM_OK','TO_OK','REG_OK','APPROVED','EFFECTED','DECLINED','WITHDRAWN',
                     'RECOMMENDED','NOT_RECOMMENDED'));

-- one live application at a time, across the new live states
DROP INDEX IF EXISTS people.uq_ta_live;
CREATE UNIQUE INDEX uq_ta_live ON people.transfer_application (student_id)
    WHERE state IN ('APPLIED','FROM_OK','TO_OK','REG_OK','APPROVED','RECOMMENDED');

-- the department that owns a programme (for routing an application to the right HOD)
CREATE OR REPLACE FUNCTION people.programme_dept(p_code text)
RETURNS text LANGUAGE sql STABLE AS $$ SELECT dept_code FROM ref.programme WHERE code = p_code $$;

-- a student applies to move — now the "in progress" test covers the new live states
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
    IF EXISTS (SELECT 1 FROM people.transfer_application WHERE student_id = p_student
                AND state IN ('APPLIED','FROM_OK','TO_OK','REG_OK','APPROVED','RECOMMENDED')) THEN
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

-- one desk's Approve: advance the application one stage. The caller (the API) has
-- already checked that the acting office is the right one for the current stage;
-- here we advance the state and record who and when on the matching desk columns.
CREATE OR REPLACE FUNCTION people.approve_transfer(p_id uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application; v_next text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a transfer is approved by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such transfer application' USING ERRCODE = '23503'; END IF;
    IF t.state = 'APPLIED' THEN
        UPDATE people.transfer_application SET state = 'FROM_OK', from_dept_at = now(), from_dept_by = who WHERE id = p_id;
        v_next := 'FROM_OK';
    ELSIF t.state = 'FROM_OK' THEN
        UPDATE people.transfer_application SET state = 'TO_OK', to_dept_at = now(), to_dept_by = who WHERE id = p_id;
        v_next := 'TO_OK';
    ELSIF t.state = 'TO_OK' THEN
        UPDATE people.transfer_application SET state = 'REG_OK', reg_at = now(), reg_by = who WHERE id = p_id;
        v_next := 'REG_OK';
    ELSIF t.state = 'REG_OK' THEN
        UPDATE people.transfer_application SET state = 'APPROVED', acad_at = now(), acad_by = who WHERE id = p_id;
        v_next := 'APPROVED';
    ELSE
        RAISE EXCEPTION 'application % has no approval pending at this stage (%).', p_id, t.state USING ERRCODE = '23514';
    END IF;
    RETURN v_next;
END $$;

-- any live desk may decline, with a reason on the record
CREATE OR REPLACE FUNCTION people.decline_transfer(p_id uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; t people.transfer_application;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a decision is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a declined case says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM people.transfer_application WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR t.state NOT IN ('APPLIED','FROM_OK','TO_OK','REG_OK','APPROVED') THEN
        RAISE EXCEPTION 'application % has no live case to decline', p_id USING ERRCODE = '23514';
    END IF;
    UPDATE people.transfer_application SET state = 'DECLINED', decline_note = btrim(p_why) WHERE id = p_id;
END $$;

-- the queue/pipeline: every application with the student, both programmes, the owning
-- departments (for routing), the stage and the fee state.
-- The return columns change (owning departments and per-desk timestamps added), so the old
-- definition is dropped and recreated rather than replaced.
DROP FUNCTION IF EXISTS people.transfer_list(text, text);
CREATE FUNCTION people.transfer_list(p_session text, p_state text)
RETURNS TABLE (id uuid, student_id uuid, name text, matric_no text,
               from_programme text, from_dept text, from_level int,
               to_programme text, to_dept text,
               mode_of_entry text, utme_score int, cgpa numeric, reason text, state text,
               recommended_level int, committee_note text, senate_note text, decline_note text, withdrawn_why text,
               applied_at timestamptz, from_dept_at timestamptz, to_dept_at timestamptz, reg_at timestamptz,
               acad_at timestamptz, effected_at timestamptz,
               fee_reference text, fee_confirmed_at timestamptz, session text)
LANGUAGE sql STABLE AS $$
    SELECT t.id, t.student_id, s.surname || ', ' || s.other_names, s.matric_no,
           fp.name, fp.dept_code, t.from_level, tp.name, tp.dept_code,
           t.mode_of_entry, t.utme_score, t.cgpa, t.reason, t.state,
           t.recommended_level, t.committee_note, t.senate_note, t.decline_note, t.withdrawn_why,
           t.applied_at, t.from_dept_at, t.to_dept_at, t.reg_at, t.acad_at, t.effected_at,
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

-- ═══════════════════════════════════════════════════════════════════════════
-- V072 — staff movements
--
--   The seventeen HR processes that change a staff record share one shape: a
--   movement is requested, approved by the authority the type names, and then —
--   and only then — an instrument (a letter) is issued. Approved is not real:
--   until the instrument exists the grade does not change, the payroll does not
--   move, and no office may be created citing it. Issuing the instrument is the
--   act that changes the record from the effective date. Requester and approver
--   are always different people.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    PERFORM set_config('moaum.reason', 'V072: staff movements', true);
END $seed$;

CREATE TABLE hrm.movement (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    employment_id  uuid NOT NULL REFERENCES hrm.employment(id),
    person_id      uuid NOT NULL REFERENCES iam.person(id),
    kind           text NOT NULL,
    effective_date date NOT NULL,
    what_changes   text NOT NULL,
    reason         text NULL,
    new_grade      text NULL,
    new_step       int NULL,
    state          text NOT NULL DEFAULT 'REQUESTED',
    requested_at   timestamptz NOT NULL DEFAULT now(),
    requested_by   uuid NULL,
    approved_at    timestamptz NULL,
    approved_by    uuid NULL,
    decision_note  text NULL,
    instrument     text NULL,
    instrument_at  timestamptz NULL,
    implemented_at timestamptz NULL,
    FOREIGN KEY (new_grade, new_step) REFERENCES hrm.grade(grade, step),
    CONSTRAINT ck_mv_kind CHECK (kind IN ('APPOINTMENT','CONFIRMATION','PROMOTION','UPGRADING','CONVERSION',
        'TRANSFER','SECONDMENT','ACTING','REDESIGNATION','LEAVE_OF_ABSENCE','SABBATICAL','SUSPENSION',
        'REINSTATEMENT','RETIREMENT','RESIGNATION','DISENGAGEMENT','DISMISSAL')),
    CONSTRAINT ck_mv_state CHECK (state IN ('REQUESTED','APPROVED','IMPLEMENTED','DECLINED','RETURNED')),
    CONSTRAINT ck_mv_two_people CHECK (approved_by IS NULL OR approved_by <> requested_by),
    CONSTRAINT ck_mv_changes CHECK (btrim(what_changes) <> '')
);
CREATE INDEX ix_mv_person ON hrm.movement (person_id, requested_at DESC);
CREATE INDEX ix_mv_state ON hrm.movement (state, effective_date);
SELECT audit.attach('hrm.movement');

-- raise a movement against a person's live employment
CREATE OR REPLACE FUNCTION hrm.raise_movement(p_person uuid, p_kind text, p_effective date, p_what text, p_reason text,
                                              p_new_grade text DEFAULT NULL, p_new_step int DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_emp uuid; v_id uuid; v_what text := btrim(coalesce(p_what, ''));
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a movement is raised by a person' USING ERRCODE = '23514'; END IF;
    SELECT id INTO v_emp FROM hrm.employment WHERE person_id = p_person AND status <> 'ENDED' ORDER BY appointment_date DESC LIMIT 1;
    IF v_emp IS NULL THEN SELECT id INTO v_emp FROM hrm.employment WHERE person_id = p_person ORDER BY appointment_date DESC LIMIT 1; END IF;
    IF v_emp IS NULL THEN RAISE EXCEPTION 'no employment on record for this person' USING ERRCODE = '23503'; END IF;
    IF p_effective IS NULL THEN RAISE EXCEPTION 'a movement is effective from a date' USING ERRCODE = '23514'; END IF;
    IF p_kind IN ('PROMOTION','UPGRADING','CONVERSION') THEN
        IF p_new_grade IS NULL OR p_new_step IS NULL THEN RAISE EXCEPTION 'a promotion names the grade and step it moves to' USING ERRCODE = '23514'; END IF;
        IF NOT EXISTS (SELECT 1 FROM hrm.grade WHERE grade = p_new_grade AND step = p_new_step) THEN RAISE EXCEPTION 'no such grade/step: % %', p_new_grade, p_new_step USING ERRCODE = '23503'; END IF;
        IF v_what = '' THEN v_what := 'Grade to ' || p_new_grade || ' step ' || p_new_step; END IF;
    END IF;
    IF v_what = '' THEN RAISE EXCEPTION 'a movement says what it changes' USING ERRCODE = '23514'; END IF;
    INSERT INTO hrm.movement (employment_id, person_id, kind, effective_date, what_changes, reason, new_grade, new_step, requested_by)
    VALUES (v_emp, p_person, p_kind, p_effective, v_what, nullif(btrim(coalesce(p_reason, '')), ''), p_new_grade, p_new_step, who)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION hrm.approve_movement(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; m hrm.movement;
BEGIN
    SELECT * INTO m FROM hrm.movement WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR m.state <> 'REQUESTED' THEN RAISE EXCEPTION 'movement % has no request to approve', p_id USING ERRCODE = '23514'; END IF;
    IF who IS NULL OR who = m.requested_by THEN
        RAISE EXCEPTION 'the officer who raised a movement does not approve it' USING ERRCODE = '23514',
            HINT = 'A movement is approved by a second officer.';
    END IF;
    UPDATE hrm.movement SET state = 'APPROVED', approved_by = who, approved_at = now() WHERE id = p_id;
END $$;

CREATE OR REPLACE FUNCTION hrm.decline_movement(p_id uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; m hrm.movement;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a decision is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_why IS NULL OR btrim(p_why) = '' THEN RAISE EXCEPTION 'a declined movement says why' USING ERRCODE = '23514'; END IF;
    SELECT * INTO m FROM hrm.movement WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR m.state <> 'REQUESTED' THEN RAISE EXCEPTION 'movement % has no request to decline', p_id USING ERRCODE = '23514'; END IF;
    UPDATE hrm.movement SET state = 'DECLINED', decision_note = btrim(p_why) WHERE id = p_id;
END $$;

-- issue the instrument: this is the act that makes an approved movement real
CREATE OR REPLACE FUNCTION hrm.issue_movement_instrument(p_id uuid)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; m hrm.movement; v_ref text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an instrument is issued by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO m FROM hrm.movement WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR m.state <> 'APPROVED' THEN RAISE EXCEPTION 'movement % is not approved for an instrument', p_id USING ERRCODE = '23514'; END IF;
    v_ref := 'MOAUM/R/ACA/' || to_char(current_date, 'YYYY') || '/' ||
             lpad(platform.next_number('MOVEMENT', 'UNIVERSITY', to_char(current_date, 'YYYY'))::text, 4, '0');
    -- the record changes from the effective date, by kind
    IF m.kind IN ('PROMOTION','UPGRADING','CONVERSION') THEN
        UPDATE hrm.employment SET grade = m.new_grade, step = m.new_step WHERE id = m.employment_id;
    ELSIF m.kind IN ('RETIREMENT','RESIGNATION','DISENGAGEMENT','DISMISSAL') THEN
        UPDATE hrm.employment SET status = 'ENDED', ended_on = m.effective_date, ended_reason = initcap(replace(m.kind, '_', ' ')) WHERE id = m.employment_id;
    ELSIF m.kind = 'SUSPENSION' THEN
        UPDATE hrm.employment SET status = 'SUSPENDED' WHERE id = m.employment_id;
    ELSIF m.kind = 'REINSTATEMENT' THEN
        UPDATE hrm.employment SET status = 'ACTIVE', ended_on = NULL, ended_reason = NULL WHERE id = m.employment_id;
    END IF;
    UPDATE hrm.movement SET state = 'IMPLEMENTED', instrument = v_ref, instrument_at = now(), implemented_at = now() WHERE id = p_id;
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION hrm.movement_list(p_state text)
RETURNS TABLE (id uuid, person_id uuid, name text, staff_no text, grade text, kind text, effective_date date,
               what_changes text, reason text, new_grade text, new_step int, state text,
               requested_at timestamptz, approved_at timestamptz, instrument text, decision_note text)
LANGUAGE sql STABLE AS $$
    SELECT m.id, m.person_id, p.surname || ', ' || p.given_names, em.staff_no, em.grade, m.kind, m.effective_date,
           m.what_changes, m.reason, m.new_grade, m.new_step, m.state, m.requested_at, m.approved_at, m.instrument, m.decision_note
      FROM hrm.movement m
      JOIN iam.person p ON p.id = m.person_id
      JOIN hrm.employment em ON em.id = m.employment_id
     WHERE (p_state IS NULL OR m.state = p_state)
     ORDER BY (m.state = 'REQUESTED') DESC, (m.state = 'APPROVED') DESC, m.effective_date DESC
$$;

COMMIT;

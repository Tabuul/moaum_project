-- ═══════════════════════════════════════════════════════════════════════════
-- V071 — staff leave
--
--   A member of staff requests leave of a kind, for a period; their office
--   approves or declines it. Annual leave draws down a yearly entitlement; the
--   balance is derived from what has been approved, never stored. Every request
--   and decision is one attributed act. A request is the person's own; the
--   decision is a second person's.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $seed$
BEGIN
    PERFORM set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
    PERFORM set_config('moaum.actor_office', 'hrm', true);
    PERFORM set_config('moaum.reason', 'V071: staff leave', true);
END $seed$;

CREATE TABLE hrm.leave_type (
    code       text PRIMARY KEY,
    name       text NOT NULL,
    max_days   int NOT NULL,
    paid       boolean NOT NULL DEFAULT true,
    annual     boolean NOT NULL DEFAULT false,
    CONSTRAINT ck_lt_days CHECK (max_days > 0)
);
SELECT audit.attach('hrm.leave_type');

CREATE TABLE hrm.leave_request (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    employment_id uuid NOT NULL REFERENCES hrm.employment(id),
    person_id     uuid NOT NULL REFERENCES iam.person(id),
    leave_type    text NOT NULL REFERENCES hrm.leave_type(code),
    from_date     date NOT NULL,
    to_date       date NOT NULL,
    days          int NOT NULL,
    cover         text NULL,
    note          text NULL,
    state         text NOT NULL DEFAULT 'REQUESTED',
    requested_at  timestamptz NOT NULL DEFAULT now(),
    requested_by  uuid NULL,
    decided_at    timestamptz NULL,
    decided_by    uuid NULL,
    decision_note text NULL,
    CONSTRAINT ck_lr_state CHECK (state IN ('REQUESTED','APPROVED','DECLINED','CANCELLED')),
    CONSTRAINT ck_lr_dates CHECK (to_date >= from_date),
    CONSTRAINT ck_lr_days CHECK (days > 0)
);
CREATE INDEX ix_lr_person ON hrm.leave_request (person_id, requested_at DESC);
CREATE INDEX ix_lr_state ON hrm.leave_request (state, from_date);
SELECT audit.attach('hrm.leave_request');

INSERT INTO hrm.leave_type (code, name, max_days, paid, annual) VALUES
 ('ANNUAL',        'Annual leave',              30,  true,  true),
 ('CASUAL',        'Casual leave',              7,   true,  false),
 ('SICK',          'Sick leave',                14,  true,  false),
 ('MATERNITY',     'Maternity leave',           112, true,  false),
 ('PATERNITY',     'Paternity leave',           14,  true,  false),
 ('COMPASSIONATE', 'Compassionate leave',       7,   true,  false),
 ('EXAMINATION',   'Examination leave',         14,  true,  false),
 ('STUDY_PAID',    'Study leave (with pay)',    1095, true, false),
 ('LEAVE_ABSENCE', 'Leave of absence (no pay)', 365, false, false);

-- the days a request covers, counted inclusive of both ends
CREATE OR REPLACE FUNCTION hrm.leave_days(p_from date, p_to date)
RETURNS int LANGUAGE sql IMMUTABLE AS $$ SELECT (p_to - p_from + 1)::int $$;

-- annual-leave entitlement remaining for a person in a calendar year
CREATE OR REPLACE FUNCTION hrm.leave_balance(p_person uuid, p_year int DEFAULT extract(year FROM current_date)::int)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT (SELECT max_days FROM hrm.leave_type WHERE code = 'ANNUAL')
         - coalesce((SELECT sum(r.days)::int FROM hrm.leave_request r
                      WHERE r.person_id = p_person AND r.leave_type = 'ANNUAL' AND r.state = 'APPROVED'
                        AND extract(year FROM r.from_date)::int = p_year), 0)
$$;

CREATE OR REPLACE FUNCTION hrm.request_leave(p_person uuid, p_type text, p_from date, p_to date, p_cover text, p_note text)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_emp uuid; v_days int; v_max int; v_id uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'leave is requested by a person' USING ERRCODE = '23514'; END IF;
    SELECT id INTO v_emp FROM hrm.employment WHERE person_id = p_person AND status = 'ACTIVE';
    IF v_emp IS NULL THEN RAISE EXCEPTION 'only a serving member of staff may request leave' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM hrm.leave_type WHERE code = p_type) THEN RAISE EXCEPTION 'no such leave type: %', p_type USING ERRCODE = '23503'; END IF;
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN RAISE EXCEPTION 'a leave period runs from a day to a later day' USING ERRCODE = '23514'; END IF;
    v_days := hrm.leave_days(p_from, p_to);
    SELECT max_days INTO v_max FROM hrm.leave_type WHERE code = p_type;
    IF v_days > v_max THEN RAISE EXCEPTION '% allows at most % day(s); this request is % day(s)', p_type, v_max, v_days USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM hrm.leave_request WHERE person_id = p_person AND state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a leave request is already awaiting a decision' USING ERRCODE = '23505';
    END IF;
    INSERT INTO hrm.leave_request (employment_id, person_id, leave_type, from_date, to_date, days, cover, note, requested_by)
    VALUES (v_emp, p_person, p_type, p_from, p_to, v_days, nullif(btrim(coalesce(p_cover, '')), ''), nullif(btrim(coalesce(p_note, '')), ''), who)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION hrm.decide_leave(p_id uuid, p_approve boolean, p_note text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; r hrm.leave_request;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a leave decision is recorded by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM hrm.leave_request WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state <> 'REQUESTED' THEN RAISE EXCEPTION 'request % has no decision to make', p_id USING ERRCODE = '23514'; END IF;
    IF NOT p_approve AND (p_note IS NULL OR btrim(p_note) = '') THEN RAISE EXCEPTION 'a declined request says why' USING ERRCODE = '23514'; END IF;
    IF p_approve AND r.leave_type = 'ANNUAL' AND r.days > hrm.leave_balance(r.person_id, extract(year FROM r.from_date)::int) THEN
        RAISE EXCEPTION 'the annual-leave balance does not cover % days' , r.days USING ERRCODE = '23514';
    END IF;
    UPDATE hrm.leave_request SET state = CASE WHEN p_approve THEN 'APPROVED' ELSE 'DECLINED' END,
        decided_at = now(), decided_by = who, decision_note = nullif(btrim(coalesce(p_note, '')), '') WHERE id = p_id;
END $$;

CREATE OR REPLACE FUNCTION hrm.cancel_leave(p_id uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; r hrm.leave_request;
BEGIN
    SELECT * INTO r FROM hrm.leave_request WHERE id = p_id FOR UPDATE;
    IF NOT FOUND OR r.state NOT IN ('REQUESTED','APPROVED') THEN RAISE EXCEPTION 'request % cannot be cancelled', p_id USING ERRCODE = '23514'; END IF;
    IF who IS NULL OR who <> r.person_id THEN RAISE EXCEPTION 'a request is cancelled by the person who made it' USING ERRCODE = '23514'; END IF;
    UPDATE hrm.leave_request SET state = 'CANCELLED' WHERE id = p_id;
END $$;

-- the office queue and a person's own history, with names resolved
CREATE OR REPLACE FUNCTION hrm.leave_list(p_state text)
RETURNS TABLE (id uuid, person_id uuid, name text, staff_no text, grade text, leave_type text, type_name text,
               from_date date, to_date date, days int, cover text, note text, state text,
               requested_at timestamptz, decided_at timestamptz, decision_note text)
LANGUAGE sql STABLE AS $$
    SELECT r.id, r.person_id, p.surname || ', ' || p.given_names, em.staff_no, em.grade, r.leave_type, lt.name,
           r.from_date, r.to_date, r.days, r.cover, r.note, r.state, r.requested_at, r.decided_at, r.decision_note
      FROM hrm.leave_request r
      JOIN iam.person p ON p.id = r.person_id
      JOIN hrm.employment em ON em.id = r.employment_id
      JOIN hrm.leave_type lt ON lt.code = r.leave_type
     WHERE (p_state IS NULL OR r.state = p_state)
     ORDER BY (r.state = 'REQUESTED') DESC, r.from_date
$$;

COMMIT;

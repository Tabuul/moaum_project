-- ═══════════════════════════════════════════════════════════════════════════
-- V036 — help and requests
--
--   A student asks an office for help in one line; the request carries a
--   reference, the office it is with, and its state; the office answers on
--   the record and the student is told. A request that sits unanswered is
--   the failure this exists to prevent, so the oldest open one is what an
--   office sees first.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE platform.service_request (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    ref         text NOT NULL UNIQUE,
    student_id  uuid NOT NULL REFERENCES people.student(id),
    office_code text NOT NULL REFERENCES ref.office(code),
    subject     text NOT NULL,
    detail      text NULL,
    raised_at   timestamptz NOT NULL DEFAULT now(),
    state       text NOT NULL DEFAULT 'OPEN',
    answer      text NULL,
    answered_at timestamptz NULL,
    answered_by uuid NULL,
    CONSTRAINT ck_sr_state CHECK (state IN ('OPEN','WITH_OFFICE','RESOLVED','CLOSED')),
    CONSTRAINT ck_sr_subject CHECK (btrim(subject) <> ''),
    CONSTRAINT ck_sr_answered CHECK (state NOT IN ('RESOLVED','CLOSED') OR (answer IS NOT NULL AND answered_at IS NOT NULL))
);
CREATE INDEX ix_sr_office ON platform.service_request (office_code, state, raised_at);
CREATE INDEX ix_sr_student ON platform.service_request (student_id, raised_at DESC);
SELECT audit.attach('platform.service_request');

-- the offices a student may ask, and the desk that answers for each
CREATE OR REPLACE FUNCTION platform.raise_request(p_student uuid, p_office text, p_subject text, p_detail text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v_ref text; v_yy text := to_char(current_date, 'YYYY');
BEGIN
    IF p_office NOT IN ('registrar','bursar','ict','library','services','academic','hod','housing') THEN
        RAISE EXCEPTION 'requests go to the Registry, the Bursary, ICT, the Library, Student Services, the Academic Office, the department or Housing' USING ERRCODE = '23514';
    END IF;
    IF p_subject IS NULL OR btrim(p_subject) = '' THEN RAISE EXCEPTION 'say what the problem is, in one line' USING ERRCODE = '23514'; END IF;
    IF (SELECT count(*) FROM platform.service_request WHERE student_id = p_student AND state IN ('OPEN','WITH_OFFICE')) >= 5 THEN
        RAISE EXCEPTION 'five requests are open already; wait for an answer before raising another' USING ERRCODE = '23514';
    END IF;
    v_ref := 'SR-' || v_yy || '-' || lpad(platform.next_number('SERVICE_REQUEST', 'UNIVERSITY', v_yy)::text, 5, '0');
    INSERT INTO platform.service_request (ref, student_id, office_code, subject, detail)
    VALUES (v_ref, p_student, p_office, btrim(p_subject), nullif(btrim(p_detail), ''));
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION platform.answer_request(p_request uuid, p_answer text, p_resolved boolean)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r platform.service_request; reach record;
BEGIN
    SELECT * INTO r FROM platform.service_request WHERE id = p_request FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no request %', p_request USING ERRCODE = 'no_data_found'; END IF;
    IF p_answer IS NULL OR btrim(p_answer) = '' THEN RAISE EXCEPTION 'an answer says something' USING ERRCODE = '23514'; END IF;
    UPDATE platform.service_request SET answer = btrim(p_answer), answered_at = now(),
           answered_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           state = CASE WHEN p_resolved THEN 'RESOLVED' ELSE 'WITH_OFFICE' END
     WHERE id = p_request;
    SELECT * INTO reach FROM people.student_reach(r.student_id);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your request ' || r.ref || (CASE WHEN p_resolved THEN ' is resolved' ELSE ' has an answer' END),
        r.subject || E'\n\n' || btrim(p_answer) || E'\n\nSign in to the portal to see the request.', 'student', r.student_id);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your request ' || r.ref,
        'MOAUM: your request ' || r.ref || (CASE WHEN p_resolved THEN ' is resolved.' ELSE ' has an answer.' END) || ' See the portal.', 'student', r.student_id);
END $$;

COMMIT;

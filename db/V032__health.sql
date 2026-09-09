-- ═══════════════════════════════════════════════════════════════════════════
-- V032 — University Health Services
--
--   Only the clinic sees the clinical notes. The Registry and the department
--   see a fitness status and nothing else; the student sees the outcome of
--   each visit and the consented facts on their own record. Every read of a
--   patient record by a clinician is logged against the clinician who opened
--   it, and the log can be shown to the patient on request.
--
--   What is on the spine: the appointment, the visit and its outcome, the
--   consented profile, the fitness status. What is exempt, with the reason:
--   the clinical note itself (a copy in a longer-lived trail is a second
--   place to read it from) and the access log (a log of the log).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE SCHEMA IF NOT EXISTS health;
GRANT USAGE ON SCHEMA health TO app_student, app_auditor;

CREATE TABLE health.profile (
    student_id     uuid PRIMARY KEY REFERENCES people.student(id),
    blood_group    text NULL,
    genotype       text NULL,
    allergies      text NULL,
    consented_at   timestamptz NULL,
    restricted_at  timestamptz NULL,
    fitness        text NOT NULL DEFAULT 'PENDING',
    fitness_on     date NULL,
    fitness_by     uuid NULL,
    CONSTRAINT ck_hp_blood CHECK (blood_group IS NULL OR blood_group IN ('O+','O-','A+','A-','B+','B-','AB+','AB-')),
    CONSTRAINT ck_hp_geno CHECK (genotype IS NULL OR genotype IN ('AA','AS','SS','AC','SC')),
    CONSTRAINT ck_hp_fit CHECK (fitness IN ('PENDING','FIT','UNFIT','FIT_WITH_CONDITIONS'))
);
SELECT audit.attach('health.profile');

CREATE TABLE health.appointment (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL REFERENCES people.student(id),
    reason        text NOT NULL,
    preferred_at  timestamptz NOT NULL,
    booked_at     timestamptz NOT NULL DEFAULT now(),
    state         text NOT NULL DEFAULT 'BOOKED',
    cancelled_why text NULL,
    CONSTRAINT ck_ha_state CHECK (state IN ('BOOKED','SEEN','CANCELLED','MISSED')),
    CONSTRAINT ck_ha_reason CHECK (btrim(reason) <> '')
);
CREATE INDEX ix_ha_student ON health.appointment (student_id, preferred_at DESC);
SELECT audit.attach('health.appointment');

CREATE TABLE health.visit (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id     uuid NOT NULL REFERENCES people.student(id),
    appointment_id uuid NULL REFERENCES health.appointment(id),
    arrived_at     timestamptz NOT NULL DEFAULT now(),
    presenting     text NOT NULL,
    triage         text NOT NULL DEFAULT 'STANDARD',
    state          text NOT NULL DEFAULT 'WAITING',
    seen_at        timestamptz NULL,
    clinician_id   uuid NULL REFERENCES iam.person(id),
    outcome        text NULL,
    referred_to    text NULL,
    concluded_at   timestamptz NULL,
    CONSTRAINT ck_hv_triage CHECK (triage IN ('URGENT','STANDARD','ROUTINE')),
    CONSTRAINT ck_hv_state CHECK (state IN ('WAITING','IN_CONSULTATION','DONE','LEFT')),
    CONSTRAINT ck_hv_done CHECK (state <> 'DONE' OR (outcome IS NOT NULL AND clinician_id IS NOT NULL AND concluded_at IS NOT NULL))
);
CREATE INDEX ix_hv_student ON health.visit (student_id, arrived_at DESC);
CREATE INDEX ix_hv_waiting ON health.visit (arrived_at) WHERE state IN ('WAITING','IN_CONSULTATION');
SELECT audit.attach('health.visit');

CREATE TABLE health.note (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    visit_id   uuid NOT NULL REFERENCES health.visit(id),
    written_by uuid NOT NULL,
    written_at timestamptz NOT NULL DEFAULT now(),
    note       text NOT NULL
);
SELECT audit.exempt('health.note',
    'The clinical note itself. The visit, its outcome and who concluded it are on the spine; a copy of the note in a '
    'longer-lived trail would be a second place to read it from, and clinical confidentiality forbids that.');

CREATE TABLE health.record_access (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL,
    person_id  uuid NOT NULL,
    office     text NOT NULL,
    what       text NOT NULL,
    at         timestamptz NOT NULL DEFAULT now()
);
SELECT audit.exempt('health.record_access', 'The log of who opened a patient record; auditing the audit doubles every row. It is shown to the patient on request.');

-- ── the acts ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION health.book(p_student uuid, p_reason text, p_preferred timestamptz)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'say why you want to be seen' USING ERRCODE = '23514'; END IF;
    IF p_preferred IS NULL OR p_preferred < now() - interval '1 hour' THEN RAISE EXCEPTION 'choose a time ahead' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM health.appointment WHERE student_id = p_student AND state = 'BOOKED' AND preferred_at > now()) THEN
        RAISE EXCEPTION 'an appointment already stands; cancel it before booking another' USING ERRCODE = '23505';
    END IF;
    INSERT INTO health.appointment (id, student_id, reason, preferred_at) VALUES (v, p_student, btrim(p_reason), p_preferred);
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION health.cancel(p_appointment uuid, p_student uuid, p_why text)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE health.appointment SET state = 'CANCELLED', cancelled_why = coalesce(nullif(btrim(p_why), ''), 'cancelled by the student')
     WHERE id = p_appointment AND student_id = p_student AND state = 'BOOKED';
    IF NOT FOUND THEN RAISE EXCEPTION 'no booked appointment %', p_appointment USING ERRCODE = 'no_data_found'; END IF;
END $$;

-- the patient arrives: a walk-in, or the appointment they booked
CREATE OR REPLACE FUNCTION health.arrive(p_student uuid, p_presenting text, p_triage text, p_appointment uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
    IF EXISTS (SELECT 1 FROM health.visit WHERE student_id = p_student AND state IN ('WAITING','IN_CONSULTATION')) THEN
        RAISE EXCEPTION 'the patient is already on the waiting list' USING ERRCODE = '23505';
    END IF;
    INSERT INTO health.visit (id, student_id, appointment_id, presenting, triage)
    VALUES (v, p_student, p_appointment, coalesce(nullif(btrim(p_presenting), ''), 'Not stated'), coalesce(upper(p_triage), 'STANDARD'));
    IF p_appointment IS NOT NULL THEN
        UPDATE health.appointment SET state = 'SEEN' WHERE id = p_appointment AND student_id = p_student AND state = 'BOOKED';
    END IF;
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION health.see(p_visit uuid, p_clinician uuid)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE health.visit SET state = 'IN_CONSULTATION', seen_at = coalesce(seen_at, now()), clinician_id = p_clinician
     WHERE id = p_visit AND state IN ('WAITING','IN_CONSULTATION');
    IF NOT FOUND THEN RAISE EXCEPTION 'visit % is not waiting', p_visit USING ERRCODE = '23514'; END IF;
    INSERT INTO health.record_access (student_id, person_id, office, what)
    SELECT student_id, p_clinician, coalesce(nullif(current_setting('moaum.actor_office', true), ''), 'services'), 'opened the visit' FROM health.visit WHERE id = p_visit;
END $$;

CREATE OR REPLACE FUNCTION health.conclude(p_visit uuid, p_clinician uuid, p_outcome text, p_referred text, p_note text, p_fitness text)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_student uuid;
BEGIN
    IF p_outcome IS NULL OR btrim(p_outcome) = '' THEN RAISE EXCEPTION 'a visit is concluded with its outcome' USING ERRCODE = '23514'; END IF;
    UPDATE health.visit SET state = 'DONE', seen_at = coalesce(seen_at, now()), clinician_id = p_clinician, outcome = btrim(p_outcome),
           referred_to = nullif(btrim(p_referred), ''), concluded_at = now()
     WHERE id = p_visit AND state IN ('WAITING','IN_CONSULTATION') RETURNING student_id INTO v_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'visit % is not open', p_visit USING ERRCODE = '23514'; END IF;
    IF p_note IS NOT NULL AND btrim(p_note) <> '' THEN
        INSERT INTO health.note (visit_id, written_by, note) VALUES (p_visit, p_clinician, btrim(p_note));
    END IF;
    IF p_fitness IS NOT NULL AND btrim(p_fitness) <> '' THEN
        INSERT INTO health.profile (student_id, fitness, fitness_on, fitness_by) VALUES (v_student, upper(p_fitness), current_date, p_clinician)
        ON CONFLICT (student_id) DO UPDATE SET fitness = EXCLUDED.fitness, fitness_on = EXCLUDED.fitness_on, fitness_by = EXCLUDED.fitness_by;
    END IF;
END $$;

-- the student consents to, or restricts, the facts on their own record
CREATE OR REPLACE FUNCTION health.consent(p_student uuid, p_blood text, p_genotype text, p_allergies text)
RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO health.profile (student_id, blood_group, genotype, allergies, consented_at, restricted_at)
    VALUES (p_student, nullif(upper(btrim(p_blood)), ''), nullif(upper(btrim(p_genotype)), ''), nullif(btrim(p_allergies), ''), now(), NULL)
    ON CONFLICT (student_id) DO UPDATE SET blood_group = EXCLUDED.blood_group, genotype = EXCLUDED.genotype, allergies = EXCLUDED.allergies,
        consented_at = now(), restricted_at = NULL;
END $$;

CREATE OR REPLACE FUNCTION health.restrict(p_student uuid)
RETURNS void
LANGUAGE sql AS $$
    UPDATE health.profile SET restricted_at = now() WHERE student_id = p_student;
$$;

-- what the student sees: their own visits' outcomes, never the note; their consented facts; their appointment
CREATE OR REPLACE FUNCTION health.student_visits(p_student uuid)
RETURNS TABLE (id uuid, arrived_at timestamptz, presenting text, triage text, state text, outcome text, referred_to text, concluded_at timestamptz, clinician text)
LANGUAGE sql STABLE AS $$
    SELECT v.id, v.arrived_at, v.presenting, v.triage, v.state, v.outcome, v.referred_to, v.concluded_at,
           CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
      FROM health.visit v LEFT JOIN iam.person p ON p.id = v.clinician_id
     WHERE v.student_id = p_student ORDER BY v.arrived_at DESC
$$;

-- what the Registry and the department may see: the fitness status, nothing else
CREATE OR REPLACE FUNCTION health.fitness_of(p_student uuid)
RETURNS TABLE (fitness text, fitness_on date)
LANGUAGE sql STABLE AS $$
    SELECT coalesce(p.fitness, 'PENDING'), p.fitness_on FROM (SELECT p_student AS sid) q LEFT JOIN health.profile p ON p.student_id = q.sid
$$;

COMMIT;

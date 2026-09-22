-- ═══════════════════════════════════════════════════════════════════════════
-- V224 — the postgraduate School's own session and semester calendar
--
--   The Postgraduate School keeps its own academic calendar, apart from the
--   undergraduate one: its own set of sessions (with the one it is currently
--   running), and its own semester windows for each. Until now the PG side
--   borrowed the University's single CURRENT session (policy.academic_session);
--   this gives the School its own store and a resolver that prefers it, falling
--   back to the University's current session, then a literal, so nothing that
--   already keys off a session string breaks. Like admissions.pg_fee, these are
--   plain tables the School owns — not on the audit spine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'PG calendar introduced (V224)', true);

-- ── 1 · the PG School's sessions (one CURRENT at a time) ─────────────────────
CREATE TABLE IF NOT EXISTS admissions.pg_academic_session (
    name        text PRIMARY KEY CHECK (name ~ '^[0-9]{4}/[0-9]{4}$'),
    starts_on   date,
    ends_on     date,
    semesters   int  NOT NULL DEFAULT 2 CHECK (semesters BETWEEN 1 AND 3),
    state       text NOT NULL DEFAULT 'PLANNED' CHECK (state IN ('PLANNED', 'CURRENT', 'CLOSED')),
    note        text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

-- exactly one session may be CURRENT for the School at a time
CREATE UNIQUE INDEX IF NOT EXISTS uq_pg_session_one_current
    ON admissions.pg_academic_session (state) WHERE state = 'CURRENT';

-- ── 2 · the semester windows of each PG session ─────────────────────────────
CREATE TABLE IF NOT EXISTS admissions.pg_semester (
    session             text NOT NULL REFERENCES admissions.pg_academic_session(name) ON DELETE CASCADE,
    number              int  NOT NULL CHECK (number BETWEEN 1 AND 3),
    registration_opens  date,
    registration_closes date,
    lectures_from       date,
    lectures_to         date,
    exams_from          date,
    exams_to            date,
    results_due         date,
    state               text NOT NULL DEFAULT 'NOT_YET_OPEN' CHECK (state IN ('NOT_YET_OPEN', 'OPEN', 'CLOSED')),
    PRIMARY KEY (session, number)
);

-- ── 3 · the current PG session: the School's own, else the University's, else a literal ──
CREATE OR REPLACE FUNCTION admissions.pg_current_session()
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT name FROM admissions.pg_academic_session WHERE state = 'CURRENT' LIMIT 1),
        (SELECT name FROM policy.academic_session         WHERE state = 'CURRENT' LIMIT 1),
        '2025/2026');
$$;

-- ── 4 · seed the PG calendar from the University's, so the School starts populated ──
INSERT INTO admissions.pg_academic_session (name, starts_on, ends_on, semesters, state)
SELECT name, starts_on, ends_on, semesters, state
  FROM policy.academic_session
 WHERE name ~ '^[0-9]{4}/[0-9]{4}$'
ON CONFLICT (name) DO NOTHING;

-- any session PG applications already carry, but the University's calendar does not list, as CLOSED
INSERT INTO admissions.pg_academic_session (name, state)
SELECT DISTINCT session, 'CLOSED'
  FROM admissions.pg_application
 WHERE session ~ '^[0-9]{4}/[0-9]{4}$'
ON CONFLICT (name) DO NOTHING;

-- mirror the University's semester windows for the sessions just copied in
INSERT INTO admissions.pg_semester (session, number, registration_opens, registration_closes,
                                    lectures_from, lectures_to, exams_from, exams_to, results_due, state)
SELECT s.session, s.number, s.registration_opens, s.registration_closes,
       s.lectures_from, s.lectures_to, s.exams_from, s.exams_to, s.results_due, s.state
  FROM policy.semester s
  JOIN admissions.pg_academic_session p ON p.name = s.session
ON CONFLICT (session, number) DO NOTHING;

-- ── 5 · the public apply resolves the session from the PG calendar now ───────
CREATE OR REPLACE FUNCTION admissions.pg_apply(p_form jsonb)
RETURNS TABLE (application_id uuid, application_no text, reference text, amount numeric)
LANGUAGE plpgsql AS $$
DECLARE
    v_session text; v_prog text; v_cat text; v_award text; v_applicant uuid; v_app uuid;
    v_ref text; v_amt numeric; v_yy text; v_sex text; ref jsonb; d jsonb; v_kind text;
BEGIN
    v_session := coalesce(nullif(btrim(p_form->>'session'), ''), admissions.pg_current_session());
    v_prog := upper(btrim(coalesce(p_form->>'programme', '')));
    SELECT category, pg_award INTO v_cat, v_award FROM ref.programme WHERE upper(code) = v_prog AND NOT archived;
    IF v_cat IS NULL THEN
        RAISE EXCEPTION 'that programme is not one the University runs' USING ERRCODE = '23503';
    END IF;
    IF v_cat <> 'POST GRADUATE' THEN
        RAISE EXCEPTION 'that programme is not a postgraduate programme' USING ERRCODE = '23514';
    END IF;
    v_yy := substr(v_session, 3, 2);
    v_sex := nullif(upper(left(btrim(coalesce(p_form->>'sex', '')), 1)), '');
    IF v_sex IS NOT NULL AND v_sex NOT IN ('F', 'M') THEN v_sex := NULL; END IF;

    INSERT INTO admissions.pg_applicant (session, surname, other_names, sex, date_of_birth, state_of_origin, lga,
                                         email, phone, password_hash)
    VALUES (v_session, btrim(coalesce(p_form->>'surname', '')), btrim(coalesce(p_form->>'otherNames', '')),
            v_sex,
            CASE WHEN coalesce(p_form->>'dob', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (p_form->>'dob')::date END,
            nullif(btrim(coalesce(p_form->>'state', '')), ''), nullif(btrim(coalesce(p_form->>'lga', '')), ''),
            lower(btrim(coalesce(p_form->>'email', ''))), nullif(btrim(coalesce(p_form->>'phone', '')), ''),
            p_form->>'passwordHash')
    RETURNING id INTO v_applicant;

    -- the first degree, kept on the application (for the desks): from priorDegrees[0], else the flat fields
    INSERT INTO admissions.pg_application (applicant_id, session, application_no, programme_code, entry_level,
            prior_institution, prior_award, prior_class, prior_cgpa, prior_year, proposal_title, proposal_text,
            state, submitted_at)
    VALUES (v_applicant, v_session,
            'PG/' || v_yy || '/' || lpad(platform.next_number('PG_APPLICATION', 'UNIVERSITY', v_session)::text, 6, '0'),
            v_prog, admissions.pg_award_level(v_award),
            coalesce(nullif(btrim(p_form->'priorDegrees'->0->>'institution'), ''), nullif(btrim(coalesce(p_form->>'priorInstitution', '')), '')),
            coalesce(nullif(btrim(p_form->'priorDegrees'->0->>'award'), ''),       nullif(btrim(coalesce(p_form->>'priorAward', '')), '')),
            coalesce(nullif(btrim(p_form->'priorDegrees'->0->>'classOfDegree'), ''), nullif(btrim(coalesce(p_form->>'priorClass', '')), '')),
            nullif(regexp_replace(coalesce(p_form->'priorDegrees'->0->>'cgpa', p_form->>'priorCgpa', ''), '[^0-9.]', '', 'g'), '')::numeric,
            nullif(regexp_replace(coalesce(p_form->'priorDegrees'->0->>'year', p_form->>'priorYear', ''), '[^0-9]', '', 'g'), '')::int,
            nullif(btrim(coalesce(p_form->>'proposalTitle', '')), ''),
            nullif(btrim(coalesce(p_form->>'proposalText', '')), ''),
            'SUBMITTED', now())
    RETURNING id INTO v_app;

    -- every qualification given, into the child table (first degree, prior Master's, PGD, NCE, HND, …)
    IF jsonb_typeof(p_form->'priorDegrees') = 'array' THEN
        FOR d IN SELECT * FROM jsonb_array_elements(p_form->'priorDegrees') LOOP
            IF coalesce(btrim(d->>'institution'), '') <> '' OR coalesce(btrim(d->>'award'), '') <> ''
               OR coalesce(btrim(d->>'field'), '') <> '' THEN
                v_kind := upper(coalesce(nullif(btrim(d->>'kind'), ''), 'FIRST'));
                IF v_kind NOT IN ('NCE','ND','HND','FIRST','PGD','MASTERS','PHD','OTHER') THEN v_kind := 'OTHER'; END IF;
                INSERT INTO admissions.pg_prior_degree (application_id, kind, institution, award, field, class_of_degree, cgpa, year)
                VALUES (v_app, v_kind,
                        nullif(btrim(d->>'institution'), ''), nullif(btrim(d->>'award'), ''),
                        nullif(btrim(d->>'field'), ''),
                        nullif(btrim(d->>'classOfDegree'), ''),
                        nullif(regexp_replace(coalesce(d->>'cgpa', ''), '[^0-9.]', '', 'g'), '')::numeric,
                        nullif(regexp_replace(coalesce(d->>'year', ''), '[^0-9]', '', 'g'), '')::int);
            END IF;
        END LOOP;
    END IF;

    IF jsonb_typeof(p_form->'referees') = 'array' THEN
        FOR ref IN SELECT * FROM jsonb_array_elements(p_form->'referees') LOOP
            IF coalesce(btrim(ref->>'name'), '') <> '' THEN
                INSERT INTO admissions.pg_referee (application_id, name, email, institution, position)
                VALUES (v_app, btrim(ref->>'name'), nullif(btrim(coalesce(ref->>'email', '')), ''),
                        nullif(btrim(coalesce(ref->>'institution', '')), ''), nullif(btrim(coalesce(ref->>'position', '')), ''));
            END IF;
        END LOOP;
    END IF;

    v_ref := admissions.pg_new_fee_reference(v_app, 'APPLICATION');
    SELECT fr.amount INTO v_amt FROM admissions.pg_fee_reference fr WHERE fr.reference = v_ref;
    RETURN QUERY SELECT v_app,
                        (SELECT a.application_no FROM admissions.pg_application a WHERE a.id = v_app),
                        v_ref, v_amt;
END $$;

-- ── 6 · PG coursework registration may run a third (Summer) semester too ─────
ALTER TABLE admissions.pg_registration DROP CONSTRAINT IF EXISTS ck_pg_reg_sem;
ALTER TABLE admissions.pg_registration ADD  CONSTRAINT ck_pg_reg_sem CHECK (semester IN (1, 2, 3));

COMMIT;

-- V379: CCE — the Centre for Continuing Education as a regular part-time route: the route and its own session (one behind
--       undergraduate by default), the programmes it offers, JAMB's CCE list loaded by the Academic Office, the CCE
--       application, the Centre's review and the Academic Office's publication, and the register.
--
-- CCE is a regular, part-time, six-year undergraduate route. A CCE student is an ordinary people.student — the same
-- programmes, finance, registration, results and sign-in — carrying the admission route CCE, the study mode PART_TIME and
-- the Centre for Continuing Education, and studying in the CCE session. Nothing here is a second student, admission,
-- finance or session system (docs/cce.md):
--
--   policy.study_route            the route: its study mode, centre, entry level, default duration (6 years) and how its
--                                 session follows the undergraduate session (offset −1), or a session the Academic Office
--                                 names instead; policy.route_session(route) reads it, policy.resolve_session(route, mode,
--                                 programme) is the one resolver; policy.session_before is session_after's mirror
--   ref.programme_route           a programme offered on the route (programme × route): duration and final level when they
--                                 differ from the route's, and whether it admits — no programme is duplicated
--   people.student.study_mode     FULL_TIME (every existing student) or PART_TIME (every CCE student); the route CCE added to
--                                 entry_mode; moving a student onto or off CCE or changing the study mode needs the
--                                 Academic Office or the Registry and a reason
--   admissions.cce_batch / _row   an uploaded CCE list: read, every row classified (NEW, EXISTING, UPDATED, DUPLICATE,
--                                 REQUIRES_REVIEW, INVALID) in a preview, then committed whole or discarded; kept as history
--   admissions.cce_candidate      the CCE list as committed: who may apply, for which session and programme; withdrawn with a
--                                 reason, never deleted
--   admissions.candidate          a CCE applicant is an ordinary candidate with entry_mode CCE, linked to the list row
--   admissions.cce_review         the Centre's review of each CCE application (DRAFT … APPROVED, ADMITTED, NOT_ADMITTED,
--                                 REJECTED) and its history; approved by someone other than the officer who recommended it;
--                                 published by the Academic Office, which writes the ordinary decision and releases it
--   admissions.route_fee          the CCE applicant fees, stated by the Bursary per session (application, portal charge,
--                                 acceptance), read by the ordinary fee references
--
-- Changed: the intake keeps a CCE candidate CCE and PART_TIME in the session admitted for; status checking needs no window
-- or checking fee for a CCE applicant; the online screening is not asked of a CCE applicant (the Centre's review is it);
-- the admission letter names the route, the study mode and the Centre; a CCE student stands in the CCE session; course
-- registration refuses a CCE student until the CCE offerings exist (phase 2 of docs/cce.md); the CCE application window.
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V379: CCE — the Centre for Continuing Education as a regular part-time route', true);

-- ── 1 · the office ───────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO ref.office (code, label, scope_kind) VALUES ('cce', 'Centre for Continuing Education', 'unit') ON CONFLICT (code) DO NOTHING;

-- ── 2 · the route and its session ───────────────────────────────────────────────────────────────────────────────
CREATE TABLE policy.study_route (
    code                   text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z_]{1,19}$'),
    name                   text NOT NULL CHECK (btrim(name) <> ''),
    study_mode             text NOT NULL CHECK (study_mode IN ('FULL_TIME', 'PART_TIME')),
    centre_unit            text NULL REFERENCES ref.unit (code),
    entry_level            integer NOT NULL DEFAULT 100 CHECK (entry_level IN (100, 200, 300)),
    default_duration_years integer NOT NULL CHECK (default_duration_years BETWEEN 1 AND 10),
    session_offset         integer NOT NULL DEFAULT 0 CHECK (session_offset BETWEEN -3 AND 3),
    session_override       text NULL REFERENCES policy.academic_session (name),
    override_reason        text NULL,
    effective_from         date NOT NULL DEFAULT current_date,
    configured_by          uuid NULL,
    configured_office      text NULL REFERENCES ref.office (code),
    configured_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_route_override_reason CHECK (session_override IS NULL OR nullif(btrim(coalesce(override_reason, '')), '') IS NOT NULL)
);
COMMENT ON TABLE policy.study_route IS
  'V379: an admission route with a calendar of its own (CCE): its study mode, centre, entry level and default duration, and how its session follows the undergraduate session — the offset (−1: one session behind), or a session the Academic Office names in its place.';
INSERT INTO policy.study_route (code, name, study_mode, centre_unit, entry_level, default_duration_years, session_offset)
VALUES ('CCE', 'Centre for Continuing Education', 'PART_TIME', 'CCE', 100, 6, -1);
SELECT audit.attach('policy.study_route');

CREATE TABLE policy.study_route_event (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    route      text NOT NULL REFERENCES policy.study_route (code),
    at         timestamptz NOT NULL DEFAULT now(),
    actor      uuid NULL,
    office     text NULL,
    what       text NOT NULL,
    before     jsonb NULL,
    after      jsonb NULL,
    reason     text NULL
);
CREATE INDEX ix_study_route_event ON policy.study_route_event (route, at DESC);
COMMENT ON TABLE policy.study_route_event IS 'V379: every change to a route''s session mapping or terms — what it was, what it became, by whom and why. Written once.';
CREATE OR REPLACE FUNCTION policy.study_route_event_once() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    RAISE EXCEPTION 'a route''s history is written once and never changed' USING ERRCODE = '23514';
END $fn$;
CREATE TRIGGER trg_study_route_event_once BEFORE UPDATE OR DELETE ON policy.study_route_event FOR EACH ROW EXECUTE FUNCTION policy.study_route_event_once();
SELECT audit.attach('policy.study_route_event');

/* the session n sessions before this one (cancelled sessions are not counted) — the mirror of policy.session_after */
CREATE OR REPLACE FUNCTION policy.session_before(p_session text, p_n integer)
RETURNS text LANGUAGE plpgsql STABLE AS $fn$
DECLARE y int := policy.session_year(p_session); left_to_count int := coalesce(p_n, 0); guard int := 0;
BEGIN
    IF y IS NULL THEN RETURN NULL; END IF;
    WHILE left_to_count > 0 AND guard < 40 LOOP
        y := y - 1; guard := guard + 1;
        IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = y || '/' || (y + 1) AND a.state = 'CANCELLED') THEN
            left_to_count := left_to_count - 1;
        END IF;
    END LOOP;
    RETURN y || '/' || (y + 1);
END $fn$;

/* a session moved by an offset: forward with session_after, back with session_before */
CREATE OR REPLACE FUNCTION policy.session_shift(p_session text, p_offset integer)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN coalesce(p_offset, 0) >= 0 THEN policy.session_after(p_session, coalesce(p_offset, 0))
                ELSE policy.session_before(p_session, -p_offset) END
$fn$;

/* the route's current session: the session the Academic Office named, else the undergraduate session moved by the offset —
   so when undergraduate moves on, the route moves with it, and nothing is moved by hand */
CREATE OR REPLACE FUNCTION policy.route_session(p_route text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(r.session_override, policy.session_shift(policy.university_current_session(), r.session_offset))
      FROM policy.study_route r WHERE r.code = upper(btrim(p_route))
$fn$;
COMMENT ON FUNCTION policy.route_session(text) IS
  'V379: the current session of a route with a calendar of its own (CCE): the session the Academic Office named, else the University''s current (undergraduate) session moved by the route''s offset.';

/* the one resolver: the session a transaction of this route (and study mode, and programme) belongs to today */
CREATE OR REPLACE FUNCTION policy.resolve_session(p_route text, p_study_mode text DEFAULT NULL, p_programme text DEFAULT NULL)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT CASE
             WHEN EXISTS (SELECT 1 FROM policy.study_route r WHERE r.code = upper(btrim(coalesce(p_route, '')))) THEN policy.route_session(p_route)
             WHEN upper(btrim(coalesce(p_route, ''))) = 'POSTGRADUATE' THEN admissions.pg_current_session()
             WHEN upper(btrim(coalesce(p_route, ''))) = 'JUPEB'
                  THEN coalesce((SELECT current_session FROM jupeb.setting WHERE session = '*'), policy.university_current_session())
             ELSE policy.university_current_session() END
$fn$;
COMMENT ON FUNCTION policy.resolve_session(text, text, text) IS
  'V379: the session a transaction belongs to by its route — CCE (and any route in policy.study_route) its own session, POSTGRADUATE the School''s, JUPEB the JUPEB Office''s, every other route (UTME, DIRECT_ENTRY, …) the University''s undergraduate session. Never assume CURRENT for every student.';

/* the mapping as the Academic Office reads it */
CREATE OR REPLACE FUNCTION policy.route_session_mapping(p_route text)
RETURNS TABLE (route text, name text, study_mode text, centre text, entry_level integer, default_duration_years integer,
               undergraduate_session text, route_session text, route_session_state text, session_offset integer,
               overridden boolean, override_reason text, relationship text, effective_from date,
               configured_by uuid, configured_by_name text, configured_office text, configured_at timestamptz)
LANGUAGE sql STABLE AS $fn$
    WITH r AS (SELECT * FROM policy.study_route WHERE code = upper(btrim(p_route))),
         ug AS (SELECT policy.university_current_session() AS s),
         m AS (SELECT r.*, ug.s AS ug_s, policy.route_session(r.code) AS route_s FROM r, ug),
         gap AS (SELECT m.*, policy.sessions_elapsed(m.route_s, m.ug_s) AS behind FROM m)
    SELECT g.code, g.name, g.study_mode, u.name, g.entry_level, g.default_duration_years,
           g.ug_s, g.route_s, a.state, g.session_offset, g.session_override IS NOT NULL, g.override_reason,
           CASE WHEN g.behind IS NULL THEN NULL
                WHEN g.behind = 0 THEN 'The same session as undergraduate'
                WHEN g.behind = 1 THEN '1 session behind undergraduate'
                WHEN g.behind > 1 THEN g.behind || ' sessions behind undergraduate'
                WHEN g.behind = -1 THEN '1 session ahead of undergraduate'
                ELSE (-g.behind) || ' sessions ahead of undergraduate' END,
           g.effective_from, g.configured_by, nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ','),
           g.configured_office, g.configured_at
      FROM gap g
      LEFT JOIN ref.unit u ON u.code = g.centre_unit
      LEFT JOIN policy.academic_session a ON a.name = g.route_s
      LEFT JOIN iam.person p ON p.id = g.configured_by
$fn$;

/* the Academic Office sets how the route's session follows undergraduate: an offset, or a named session with its reason */
CREATE OR REPLACE FUNCTION policy.set_route_session(p_route text, p_offset integer, p_override text, p_reason text, p_effective date)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r policy.study_route; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_override text := nullif(btrim(coalesce(p_override, '')), '');
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); before_s text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a route''s session is set by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(v_office, '') NOT IN ('academic', 'super') THEN
        RAISE EXCEPTION 'CCE_SESSION_OFFICE: the CCE session mapping is the Academic Office''s' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO r FROM policy.study_route WHERE code = upper(btrim(p_route)) FOR UPDATE;
    IF r.code IS NULL THEN RAISE EXCEPTION 'no route %', p_route USING ERRCODE = '23503'; END IF;
    IF p_offset IS NULL OR p_offset NOT BETWEEN -3 AND 3 THEN
        RAISE EXCEPTION 'CCE_SESSION_OFFSET: the offset is between three sessions behind and three ahead; CCE is one behind (−1) by default' USING ERRCODE = '23514';
    END IF;
    IF v_override IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_override AND a.state <> 'CANCELLED') THEN
        RAISE EXCEPTION 'CCE_SESSION_UNKNOWN: % is not a session on the calendar (or it was cancelled); add it on the calendar first', v_override USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL THEN
        RAISE EXCEPTION 'CCE_SESSION_REASON: a change to the CCE session is recorded with its reason' USING ERRCODE = '23514';
    END IF;
    before_s := policy.route_session(r.code);
    UPDATE policy.study_route
       SET session_offset = p_offset, session_override = v_override, override_reason = CASE WHEN v_override IS NULL THEN NULL ELSE v_reason END,
           effective_from = coalesce(p_effective, current_date), configured_by = v_actor, configured_office = v_office, configured_at = now()
     WHERE code = r.code;
    INSERT INTO policy.study_route_event (route, actor, office, what, before, after, reason)
    VALUES (r.code, v_actor, v_office, 'SESSION_MAPPING',
            jsonb_build_object('offset', r.session_offset, 'override', r.session_override, 'session', before_s, 'effective_from', r.effective_from),
            jsonb_build_object('offset', p_offset, 'override', v_override, 'session', policy.route_session(r.code), 'effective_from', coalesce(p_effective, current_date)),
            v_reason);
    RETURN policy.route_session(r.code);
END $fn$;

-- ── 3 · the programmes on the route ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE ref.programme_route (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    programme_code text NOT NULL REFERENCES ref.programme (code),
    route          text NOT NULL REFERENCES policy.study_route (code),
    duration_years integer NULL CHECK (duration_years IS NULL OR duration_years BETWEEN 1 AND 10),
    final_level    integer NULL CHECK (final_level IS NULL OR final_level IN (100, 200, 300, 400, 500, 600, 700, 800, 900)),
    active         boolean NOT NULL DEFAULT true,
    note           text NULL,
    updated_by     uuid NULL,
    updated_office text NULL REFERENCES ref.office (code),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_programme_route UNIQUE (programme_code, route)
);
COMMENT ON TABLE ref.programme_route IS
  'V379: a programme offered on a route (programme × route) — CCE offers an existing programme part-time; nothing is duplicated. Duration and final level are the route''s unless stated here; active says whether it admits.';
SELECT audit.attach('ref.programme_route');

/* a programme's terms on a route: whether it admits, the study mode, the centre, the duration (the route's default unless
   stated), the final level (the entry level plus a level a year unless stated) */
CREATE OR REPLACE FUNCTION ref.programme_route_terms(p_programme text, p_route text)
RETURNS TABLE (programme_code text, route text, configured boolean, active boolean, study_mode text, centre_unit text,
               entry_level integer, duration_years integer, final_level integer)
LANGUAGE sql STABLE AS $fn$
    SELECT p.code, r.code, pr.id IS NOT NULL, coalesce(pr.active, false) AND NOT p.archived, r.study_mode, r.centre_unit, r.entry_level,
           coalesce(pr.duration_years, r.default_duration_years),
           coalesce(pr.final_level, least(900, r.entry_level + 100 * (coalesce(pr.duration_years, r.default_duration_years) - 1)))
      FROM ref.programme p
      JOIN policy.study_route r ON r.code = upper(btrim(p_route))
      LEFT JOIN ref.programme_route pr ON pr.programme_code = p.code AND pr.route = r.code
     WHERE p.code = p_programme
$fn$;

/* the Academic Office offers a programme on the route, or stops it admitting (a programme already admitted into is kept) */
CREATE OR REPLACE FUNCTION ref.set_programme_route(p_programme text, p_route text, p_active boolean, p_duration integer, p_final_level integer, p_note text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        p ref.programme; r policy.study_route; v_id uuid; old ref.programme_route; v_final int;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a programme''s route is set by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(v_office, '') NOT IN ('academic', 'super') THEN
        RAISE EXCEPTION 'CCE_PROGRAMME_OFFICE: the programmes the Centre admits into are set by the Academic Office' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO p FROM ref.programme WHERE code = p_programme;
    IF p.code IS NULL THEN RAISE EXCEPTION 'no programme %', p_programme USING ERRCODE = '23503'; END IF;
    SELECT * INTO r FROM policy.study_route WHERE code = upper(btrim(p_route));
    IF r.code IS NULL THEN RAISE EXCEPTION 'no route %', p_route USING ERRCODE = '23503'; END IF;
    IF coalesce(p_active, false) AND (p.archived OR p.category IS DISTINCT FROM 'UNDER GRADUATE') THEN
        RAISE EXCEPTION 'CCE_PROGRAMME_NOT_UNDERGRADUATE: % is % — the Centre admits into the University''s current undergraduate programmes',
            p.name, CASE WHEN p.archived THEN 'archived' ELSE lower(coalesce(p.category, 'not undergraduate')) END USING ERRCODE = '23514';
    END IF;
    v_final := coalesce(p_final_level, least(900, r.entry_level + 100 * (coalesce(p_duration, r.default_duration_years) - 1)));
    IF v_final < r.entry_level THEN
        RAISE EXCEPTION 'CCE_PROGRAMME_LEVELS: the final level % is below the entry level %', v_final, r.entry_level USING ERRCODE = '23514';
    END IF;
    SELECT * INTO old FROM ref.programme_route WHERE programme_code = p.code AND route = r.code;
    INSERT INTO ref.programme_route (programme_code, route, duration_years, final_level, active, note, updated_by, updated_office, updated_at)
    VALUES (p.code, r.code, p_duration, p_final_level, coalesce(p_active, false), nullif(btrim(coalesce(p_note, '')), ''), v_actor, v_office, now())
    ON CONFLICT (programme_code, route) DO UPDATE
       SET duration_years = EXCLUDED.duration_years, final_level = EXCLUDED.final_level, active = EXCLUDED.active, note = EXCLUDED.note,
           updated_by = EXCLUDED.updated_by, updated_office = EXCLUDED.updated_office, updated_at = now()
    RETURNING id INTO v_id;
    INSERT INTO policy.study_route_event (route, actor, office, what, before, after, reason)
    VALUES (r.code, v_actor, v_office, 'PROGRAMME ' || p.code,
            CASE WHEN old.id IS NULL THEN NULL ELSE jsonb_build_object('active', old.active, 'duration_years', old.duration_years, 'final_level', old.final_level) END,
            jsonb_build_object('active', coalesce(p_active, false), 'duration_years', p_duration, 'final_level', p_final_level),
            nullif(btrim(coalesce(p_note, '')), ''));
    RETURN v_id;
END $fn$;

-- ── 4 · the route and study mode on the student and the candidate ───────────────────────────────────────────────
ALTER TABLE people.student ADD COLUMN study_mode text NOT NULL DEFAULT 'FULL_TIME';
ALTER TABLE people.student ADD CONSTRAINT ck_student_study_mode CHECK (study_mode IN ('FULL_TIME', 'PART_TIME'));
ALTER TABLE people.student DROP CONSTRAINT ck_student_entry;
ALTER TABLE people.student ADD CONSTRAINT ck_student_entry
    CHECK (entry_mode IN ('UTME', 'DIRECT_ENTRY', 'TRANSFER', 'POSTGRADUATE', 'JUPEB', 'SANDWICH', 'CCE'));
ALTER TABLE people.student ADD CONSTRAINT ck_student_cce_part_time CHECK (entry_mode <> 'CCE' OR study_mode = 'PART_TIME');
CREATE INDEX ix_student_cce ON people.student (entry_session) WHERE entry_mode = 'CCE';
COMMENT ON COLUMN people.student.study_mode IS 'V379: FULL_TIME (every student before CCE) or PART_TIME (every CCE student). Changed onto or off CCE, or between modes, only by the Academic Office or the Registry with a reason.';

/* a student is not moved onto or off the CCE route, or between study modes, behind the Academic Office's back */
CREATE OR REPLACE FUNCTION people.student_route_guard() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF (NEW.entry_mode IS DISTINCT FROM OLD.entry_mode AND 'CCE' IN (NEW.entry_mode, OLD.entry_mode))
       OR NEW.study_mode IS DISTINCT FROM OLD.study_mode THEN
        IF coalesce(current_setting('moaum.maintenance', true), '') <> 'on'
           AND coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
            RAISE EXCEPTION 'STUDENT_ROUTE_LOCKED: a student is moved onto or off the CCE route, or between full-time and part-time, only by the Academic Office or the Registry' USING ERRCODE = '23514';
        END IF;
        IF nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), '') IS NULL THEN
            RAISE EXCEPTION 'STUDENT_ROUTE_REASON: a change of route or study mode is recorded with its reason' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_student_route_guard BEFORE UPDATE OF entry_mode, study_mode ON people.student
    FOR EACH ROW EXECUTE FUNCTION people.student_route_guard();

-- ── 5 · JAMB's CCE list ─────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE admissions.cce_batch (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session         text NOT NULL REFERENCES policy.academic_session (name),
    filename        text NOT NULL CHECK (btrim(filename) <> ''),
    file_sha256     text NOT NULL CHECK (file_sha256 ~ '^[0-9a-f]{64}$'),
    rows_read       integer NOT NULL CHECK (rows_read >= 0),
    counts          jsonb NOT NULL DEFAULT '{}'::jsonb,
    state           text NOT NULL DEFAULT 'PREVIEW' CHECK (state IN ('PREVIEW', 'COMMITTED', 'DISCARDED')),
    uploaded_by     uuid NOT NULL,
    uploaded_office text NOT NULL REFERENCES ref.office (code),
    uploaded_at     timestamptz NOT NULL DEFAULT now(),
    committed_by    uuid NULL,
    committed_at    timestamptz NULL,
    applied         jsonb NULL,
    discarded_by    uuid NULL,
    discarded_at    timestamptz NULL,
    discard_reason  text NULL,
    CONSTRAINT ck_cce_batch_committed CHECK ((state = 'COMMITTED') = (committed_at IS NOT NULL AND committed_by IS NOT NULL)),
    CONSTRAINT ck_cce_batch_discarded CHECK ((state = 'DISCARDED') = (discarded_at IS NOT NULL AND nullif(btrim(coalesce(discard_reason, '')), '') IS NOT NULL))
);
CREATE INDEX ix_cce_batch_session ON admissions.cce_batch (session, uploaded_at DESC);
COMMENT ON TABLE admissions.cce_batch IS 'V379: a CCE list uploaded by the Academic Office — read, previewed row by row, then committed whole or discarded with a reason. Kept as the history of every list loaded.';
SELECT audit.attach('admissions.cce_batch');

CREATE TABLE admissions.cce_candidate (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session         text NOT NULL REFERENCES policy.academic_session (name),
    jamb_reg_no     text NOT NULL,
    jamb_key        text NOT NULL CHECK (jamb_key ~ '^[A-Z0-9/-]{6,24}$'),
    surname         text NOT NULL CHECK (btrim(surname) <> ''),
    first_name      text NOT NULL CHECK (btrim(first_name) <> ''),
    middle_name     text NULL,
    date_of_birth   date NOT NULL,
    sex             text NULL CHECK (sex IS NULL OR sex IN ('M', 'F')),
    phone           text NULL CHECK (phone IS NULL OR phone ~ '^0[0-9]{10}$'),
    email           text NULL,
    state_of_origin text NULL,
    lga             text NULL,
    nationality     text NULL,
    programme_code  text NOT NULL REFERENCES ref.programme (code),
    olevel_note     text NULL,
    remarks         text NULL,
    extra           jsonb NOT NULL DEFAULT '{}'::jsonb,
    source          text NOT NULL DEFAULT 'JAMB_CCE_LIST' CHECK (source IN ('JAMB_CCE_LIST')),
    standing        text NOT NULL DEFAULT 'LISTED' CHECK (standing IN ('LISTED', 'WITHDRAWN')),
    standing_reason text NULL,
    standing_by     uuid NULL,
    standing_at     timestamptz NULL,
    first_batch_id  uuid NOT NULL REFERENCES admissions.cce_batch (id),
    last_batch_id   uuid NOT NULL REFERENCES admissions.cce_batch (id),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_cce_candidate UNIQUE (session, jamb_key),
    CONSTRAINT ck_cce_candidate_withdrawn CHECK (standing = 'LISTED' OR nullif(btrim(coalesce(standing_reason, '')), '') IS NOT NULL)
);
CREATE INDEX ix_cce_candidate_name ON admissions.cce_candidate (session, upper(surname), upper(first_name));
CREATE INDEX ix_cce_candidate_programme ON admissions.cce_candidate (session, programme_code);
CREATE INDEX ix_cce_candidate_key ON admissions.cce_candidate (jamb_key);
COMMENT ON TABLE admissions.cce_candidate IS
  'V379: the CCE list as committed — the people JAMB supplied for the Centre for Continuing Education, for one CCE session and programme. Only a listed person may open a CCE application, and proves who they are with the JAMB number and the date of birth here. Withdrawn with a reason, never deleted.';
SELECT audit.attach('admissions.cce_candidate');

CREATE TABLE admissions.cce_batch_row (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_id         uuid NOT NULL REFERENCES admissions.cce_batch (id) ON DELETE CASCADE,
    row_no           integer NOT NULL CHECK (row_no >= 1),
    raw              jsonb NOT NULL,
    jamb_reg_no      text NULL,
    jamb_key         text NULL,
    surname          text NULL,
    first_name       text NULL,
    middle_name      text NULL,
    date_of_birth    date NULL,
    sex              text NULL,
    phone            text NULL,
    email            text NULL,
    state_of_origin  text NULL,
    lga              text NULL,
    nationality      text NULL,
    programme_code   text NULL,
    olevel_note      text NULL,
    remarks          text NULL,
    extra            jsonb NULL,
    classification   text NOT NULL CHECK (classification IN ('NEW', 'EXISTING', 'UPDATED', 'DUPLICATE', 'REQUIRES_REVIEW', 'INVALID')),
    issues           text[] NOT NULL DEFAULT '{}',
    notes            text[] NOT NULL DEFAULT '{}',
    changes          jsonb NULL,
    cce_candidate_id uuid NULL REFERENCES admissions.cce_candidate (id),
    CONSTRAINT uq_cce_batch_row UNIQUE (batch_id, row_no)
);
CREATE INDEX ix_cce_batch_row_class ON admissions.cce_batch_row (batch_id, classification);
COMMENT ON TABLE admissions.cce_batch_row IS 'V379: each row of an uploaded CCE list as read, with what it would do (NEW, EXISTING, UPDATED) or why it would not (DUPLICATE, REQUIRES_REVIEW, INVALID).';
SELECT audit.exempt('admissions.cce_batch_row', 'V379: the staging copy of an uploaded CCE list, written once by the preview; the batch, its commit and every candidate it creates or changes are audited');

/* a date as a CCE list carries it: 2001-04-17, 17/04/2001, 17-04-2001, 17.04.2001, 17 Apr 2001, or the spreadsheet's day number */
CREATE OR REPLACE FUNCTION admissions.cce_date(p text)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE s text := btrim(coalesce(p, '')); d date; n numeric;
BEGIN
    IF s = '' THEN RETURN NULL; END IF;
    BEGIN
        IF s ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}' THEN d := to_date(left(s, 10), 'YYYY-MM-DD');
        ELSIF s ~ '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}$' THEN d := to_date(regexp_replace(s, '[/.-]', '/', 'g'), 'DD/MM/YYYY');
        ELSIF s ~* '^[0-9]{1,2}[ -][a-z]{3,9}[ -,]+[0-9]{4}$' THEN d := to_date(regexp_replace(s, '[ ,-]+', ' ', 'g'), 'DD Mon YYYY');
        ELSIF s ~ '^[0-9]{4,5}(\.0+)?$' THEN
            n := s::numeric;
            IF n BETWEEN 7000 AND 60000 THEN d := date '1899-12-30' + n::int; END IF;
        END IF;
    EXCEPTION WHEN others THEN RETURN NULL;
    END;
    IF d IS NULL OR d < date '1930-01-01' OR d > current_date THEN RETURN NULL; END IF;
    RETURN d;
END $fn$;

/* a Nigerian mobile number as written on a list: 0803…, +234 803…, 803… — or NULL when it cannot be read */
CREATE OR REPLACE FUNCTION admissions.cce_phone(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE WHEN d ~ '^0[0-9]{10}$' THEN d
                WHEN d ~ '^234[0-9]{10}$' THEN '0' || substr(d, 4)
                WHEN d ~ '^[1-9][0-9]{9}$' THEN '0' || d END
      FROM (SELECT regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g') AS d) x
$fn$;

/* a programme as a list names it — the University code (C#####), or the programme's name — resolved to the code */
CREATE OR REPLACE FUNCTION admissions.cce_programme(p_code text, p_name text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT p.code FROM ref.programme p WHERE p.code = upper(btrim(coalesce(p_code, '')))),
        (SELECT p.code FROM ref.programme p WHERE upper(btrim(p.name)) = upper(btrim(coalesce(p_code, ''))) AND btrim(coalesce(p_code, '')) <> '' ORDER BY p.archived, p.code LIMIT 1),
        (SELECT p.code FROM ref.programme p WHERE upper(btrim(p.name)) = upper(btrim(coalesce(p_name, ''))) AND btrim(coalesce(p_name, '')) <> '' ORDER BY p.archived, p.code LIMIT 1))
$fn$;

/* the Academic Office's office test for the list and the session */
CREATE OR REPLACE FUNCTION admissions.cce_require_office(p_offices text[], p_what text)
RETURNS void LANGUAGE plpgsql STABLE AS $fn$
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION '% is done by a person', p_what USING ERRCODE = '23514';
    END IF;
    IF coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') <> ALL (p_offices) THEN
        RAISE EXCEPTION 'CCE_OFFICE: % is for %', p_what, array_to_string(p_offices, ', ') USING ERRCODE = '23514';
    END IF;
END $fn$;

/* the preview: every row of the list read and classified against the committed list, the register and the rest of the file;
   nothing reaches the list until the batch is committed. p_rows is an array of objects keyed by the template's columns. */
CREATE OR REPLACE FUNCTION admissions.cce_preview(p_session text, p_filename text, p_sha256 text, p_rows jsonb)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_batch uuid := gen_random_uuid(); r record; v jsonb; n int := 0;
        k text; v_key text; v_sur text; v_first text; v_mid text; v_dob date; v_sex text; v_phone text; v_email text; v_prog text;
        v_class text; v_issues text[]; v_notes text[]; v_changes jsonb; ex admissions.cce_candidate; v_started boolean; v_terms record;
        v_seen text[] := '{}'; v_extra jsonb; v_raw_dob text; v_raw_sex text; v_raw_phone text; v_raw_email text; v_s text; v_mode text; v_route text; v_other text;
        known text[] := ARRAY['sn', 'jamb_reg_no', 'surname', 'first_name', 'middle_name', 'other_names', 'date_of_birth', 'sex', 'phone', 'email',
                              'state_of_origin', 'lga', 'nationality', 'programme', 'programme_code', 'department', 'faculty', 'olevel', 'olevel_sitting',
                              'passport', 'admission_session', 'study_mode', 'admission_route', 'source', 'remarks'];
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['academic', 'super'], 'loading a CCE list');
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session AND a.state <> 'CANCELLED') THEN
        RAISE EXCEPTION 'CCE_LIST_SESSION: % is not a session on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'CCE_LIST_EMPTY: the file has no rows under its headings' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_rows) > 20000 THEN
        RAISE EXCEPTION 'CCE_LIST_TOO_LONG: % rows; a list is loaded in parts of 20,000 rows at most', jsonb_array_length(p_rows) USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.cce_batch b WHERE b.session = p_session AND b.file_sha256 = lower(p_sha256) AND b.state = 'COMMITTED') THEN
        RAISE EXCEPTION 'CCE_LIST_ALREADY_LOADED: this very file was committed for % on %', p_session,
            (SELECT to_char(max(b.committed_at) AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') FROM admissions.cce_batch b WHERE b.session = p_session AND b.file_sha256 = lower(p_sha256) AND b.state = 'COMMITTED')
            USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.cce_batch (id, session, filename, file_sha256, rows_read, uploaded_by, uploaded_office)
    VALUES (v_batch, p_session, btrim(p_filename), lower(p_sha256), jsonb_array_length(p_rows), v_actor, v_office);

    FOR r IN SELECT x.value AS row, x.ordinality AS i FROM jsonb_array_elements(p_rows) WITH ORDINALITY x LOOP
        v := r.row; n := n + 1;
        v_issues := '{}'; v_notes := '{}'; v_changes := NULL; ex := NULL; v_class := NULL;
        IF jsonb_typeof(v) <> 'object' THEN
            INSERT INTO admissions.cce_batch_row (batch_id, row_no, raw, classification, issues)
            VALUES (v_batch, r.i, coalesce(v, 'null'::jsonb), 'INVALID', ARRAY['The row could not be read']);
            CONTINUE;
        END IF;
        v_key := upper(regexp_replace(coalesce(v->>'jamb_reg_no', ''), '\s', '', 'g'));
        v_sur := nullif(btrim(coalesce(v->>'surname', '')), '');
        v_first := nullif(btrim(coalesce(v->>'first_name', '')), '');
        v_mid := nullif(btrim(coalesce(v->>'middle_name', '')), '');
        -- a list giving "other names" only: the first is the first name, the rest the middle name
        v_other := nullif(btrim(coalesce(v->>'other_names', '')), '');
        IF v_first IS NULL AND v_other IS NOT NULL THEN
            v_first := split_part(v_other, ' ', 1);
            v_mid := coalesce(v_mid, nullif(btrim(substr(v_other, length(split_part(v_other, ' ', 1)) + 1)), ''));
        END IF;
        v_raw_dob := nullif(btrim(coalesce(v->>'date_of_birth', '')), '');
        v_dob := admissions.cce_date(v_raw_dob);
        v_raw_sex := upper(btrim(coalesce(v->>'sex', '')));
        v_sex := CASE WHEN v_raw_sex IN ('M', 'MALE') THEN 'M' WHEN v_raw_sex IN ('F', 'FEMALE') THEN 'F' END;
        v_raw_phone := nullif(btrim(coalesce(v->>'phone', '')), '');
        v_phone := admissions.cce_phone(v_raw_phone);
        v_raw_email := nullif(btrim(coalesce(v->>'email', '')), '');
        v_email := CASE WHEN v_raw_email ~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN lower(v_raw_email) END;
        v_prog := admissions.cce_programme(v->>'programme_code', v->>'programme');
        v_extra := '{}'::jsonb;
        FOR k IN SELECT jsonb_object_keys(v) LOOP
            IF k IN ('department', 'faculty', 'olevel_sitting', 'passport', 'source', 'sn') OR NOT (k = ANY (known)) THEN
                IF nullif(btrim(coalesce(v->>k, '')), '') IS NOT NULL THEN v_extra := v_extra || jsonb_build_object(k, v->>k); END IF;
            END IF;
        END LOOP;

        -- what makes a row unusable
        IF v_key = '' THEN v_issues := array_append(v_issues, ('No JAMB number')::text);
        ELSIF v_key !~ '^[A-Z0-9/-]{6,24}$' THEN v_issues := array_append(v_issues, (('The JAMB number "' || left(v->>'jamb_reg_no', 30) || '" cannot be read'))::text); END IF;
        IF v_sur IS NULL THEN v_issues := array_append(v_issues, ('No surname')::text); END IF;
        IF v_first IS NULL THEN v_issues := array_append(v_issues, ('No first name')::text); END IF;
        IF v_raw_dob IS NULL THEN v_issues := array_append(v_issues, ('No date of birth: the candidate proves who they are with the JAMB number and the date of birth')::text);
        ELSIF v_dob IS NULL THEN v_issues := array_append(v_issues, (('The date of birth "' || left(v_raw_dob, 20) || '" cannot be read'))::text); END IF;
        IF nullif(btrim(coalesce(v->>'programme_code', '')), '') IS NULL AND nullif(btrim(coalesce(v->>'programme', '')), '') IS NULL THEN
            v_issues := array_append(v_issues, ('No programme')::text);
        ELSIF v_prog IS NULL THEN
            v_issues := array_append(v_issues, (('The programme "' || left(coalesce(nullif(btrim(v->>'programme_code'), ''), v->>'programme'), 60) || '" is not one the University runs'))::text);
        END IF;
        v_s := nullif(btrim(coalesce(v->>'admission_session', '')), '');
        IF v_s IS NOT NULL AND v_s <> p_session THEN v_issues := array_append(v_issues, (('The row names the session ' || v_s || '; this list is for ' || p_session))::text); END IF;
        v_mode := upper(regexp_replace(coalesce(v->>'study_mode', ''), '[^A-Za-z]', '', 'g'));
        IF v_mode <> '' AND v_mode NOT IN ('PARTTIME', 'PT') THEN v_issues := array_append(v_issues, (('The study mode "' || left(v->>'study_mode', 20) || '" is not part-time; CCE is part-time'))::text); END IF;
        v_route := upper(btrim(coalesce(v->>'admission_route', '')));
        IF v_route <> '' AND v_route NOT IN ('CCE', 'CENTRE FOR CONTINUING EDUCATION') THEN v_issues := array_append(v_issues, (('The admission route "' || left(v->>'admission_route', 30) || '" is not CCE'))::text); END IF;
        IF v_raw_sex <> '' AND v_sex IS NULL THEN v_issues := array_append(v_issues, (('The sex "' || left(v->>'sex', 10) || '" cannot be read'))::text); END IF;
        -- what is noted but does not stop the row
        IF v_raw_phone IS NOT NULL AND v_phone IS NULL THEN v_notes := array_append(v_notes, (('The phone number "' || left(v_raw_phone, 20) || '" cannot be read; the candidate gives it when applying'))::text); END IF;
        IF v_raw_email IS NOT NULL AND v_email IS NULL THEN v_notes := array_append(v_notes, (('The email "' || left(v_raw_email, 60) || '" cannot be read; the candidate gives it when applying'))::text); END IF;

        IF array_length(v_issues, 1) IS NOT NULL THEN
            v_class := 'INVALID';
        ELSIF v_key = ANY (v_seen) THEN
            v_class := 'DUPLICATE';
            v_issues := array_append(v_issues, (('The JAMB number ' || v_key || ' is on an earlier row of this file'))::text);
        ELSE
            SELECT * INTO ex FROM admissions.cce_candidate c WHERE c.session = p_session AND c.jamb_key = v_key;
            SELECT * INTO v_terms FROM ref.programme_route_terms(v_prog, 'CCE');
            IF NOT coalesce(v_terms.active, false) THEN
                v_issues := array_append(v_issues, (('The programme ' || v_prog || ' is not offered by the Centre for Continuing Education: offer it under CCE Programmes first'))::text);
            END IF;
            IF EXISTS (SELECT 1 FROM admissions.cce_candidate c WHERE c.jamb_key = v_key AND c.session <> p_session) THEN
                v_issues := array_append(v_issues, (('The JAMB number is already on the CCE list for ' ||
                    (SELECT string_agg(c.session, ', ' ORDER BY c.session) FROM admissions.cce_candidate c WHERE c.jamb_key = v_key AND c.session <> p_session)))::text);
            END IF;
            IF EXISTS (SELECT 1 FROM people.student s WHERE upper(btrim(s.jamb_reg_no)) = v_key) THEN
                v_issues := array_append(v_issues, (('The JAMB number belongs to a student already on the register (' ||
                    (SELECT coalesce(s.matric_no, s.admission_no, 'no number yet') FROM people.student s WHERE upper(btrim(s.jamb_reg_no)) = v_key LIMIT 1) || ')'))::text);
            END IF;
            IF EXISTS (SELECT 1 FROM admissions.candidate c WHERE c.session = p_session AND c.jamb_key = v_key AND c.entry_mode <> 'CCE') THEN
                v_issues := array_append(v_issues, (('The JAMB number is a ' || p_session || ' UTME or Direct Entry candidate'))::text);
            END IF;
            IF EXISTS (SELECT 1 FROM admissions.cce_candidate c
                        WHERE c.session = p_session AND c.jamb_key <> v_key AND c.date_of_birth = v_dob
                          AND upper(btrim(c.surname)) = upper(v_sur) AND upper(btrim(c.first_name)) = upper(v_first)) THEN
                v_issues := array_append(v_issues, (('The same name and date of birth are listed under another JAMB number: ' ||
                    (SELECT string_agg(c.jamb_reg_no, ', ') FROM admissions.cce_candidate c
                      WHERE c.session = p_session AND c.jamb_key <> v_key AND c.date_of_birth = v_dob
                        AND upper(btrim(c.surname)) = upper(v_sur) AND upper(btrim(c.first_name)) = upper(v_first))))::text);
            END IF;
            IF ex.id IS NOT NULL THEN
                v_changes := (SELECT coalesce(jsonb_object_agg(f.k, jsonb_build_object('from', f.o, 'to', f.nw)), '{}'::jsonb)
                                FROM (VALUES ('surname', ex.surname, v_sur), ('first_name', ex.first_name, v_first), ('middle_name', ex.middle_name, v_mid),
                                             ('date_of_birth', ex.date_of_birth::text, v_dob::text), ('sex', ex.sex, v_sex), ('phone', ex.phone, v_phone),
                                             ('email', ex.email, v_email), ('state_of_origin', ex.state_of_origin, nullif(btrim(coalesce(v->>'state_of_origin', '')), '')),
                                             ('lga', ex.lga, nullif(btrim(coalesce(v->>'lga', '')), '')), ('nationality', ex.nationality, nullif(btrim(coalesce(v->>'nationality', '')), '')),
                                             ('programme_code', ex.programme_code, v_prog), ('olevel_note', ex.olevel_note, nullif(btrim(coalesce(v->>'olevel', '')), '')),
                                             ('remarks', ex.remarks, nullif(btrim(coalesce(v->>'remarks', '')), ''))) f(k, o, nw)
                               WHERE f.o IS DISTINCT FROM f.nw AND f.nw IS NOT NULL);
                v_started := EXISTS (SELECT 1 FROM admissions.candidate c WHERE c.cce_candidate_id = ex.id);
                IF v_changes <> '{}'::jsonb AND v_started THEN
                    v_issues := array_append(v_issues, ('The candidate has already started an application: correct the application, not the list')::text);
                END IF;
                IF ex.standing = 'WITHDRAWN' THEN
                    v_issues := array_append(v_issues, (('The candidate was withdrawn from the list: ' || coalesce(ex.standing_reason, 'no reason recorded') || '; reinstate them first'))::text);
                END IF;
            END IF;
            v_class := CASE WHEN array_length(v_issues, 1) IS NOT NULL THEN 'REQUIRES_REVIEW'
                            WHEN ex.id IS NULL THEN 'NEW'
                            WHEN v_changes = '{}'::jsonb THEN 'EXISTING'
                            ELSE 'UPDATED' END;
        END IF;
        IF v_key <> '' THEN v_seen := array_append(v_seen, v_key); END IF;
        INSERT INTO admissions.cce_batch_row (batch_id, row_no, raw, jamb_reg_no, jamb_key, surname, first_name, middle_name, date_of_birth, sex, phone, email,
                                              state_of_origin, lga, nationality, programme_code, olevel_note, remarks, extra, classification, issues, notes, changes, cce_candidate_id)
        VALUES (v_batch, r.i, v, nullif(btrim(coalesce(v->>'jamb_reg_no', '')), ''), nullif(v_key, ''), v_sur, v_first, v_mid, v_dob, v_sex, v_phone, v_email,
                nullif(btrim(coalesce(v->>'state_of_origin', '')), ''), nullif(btrim(coalesce(v->>'lga', '')), ''), nullif(btrim(coalesce(v->>'nationality', '')), ''),
                v_prog, nullif(btrim(coalesce(v->>'olevel', '')), ''), nullif(btrim(coalesce(v->>'remarks', '')), ''), v_extra,
                v_class, v_issues, v_notes, CASE WHEN v_class IN ('UPDATED', 'REQUIRES_REVIEW') THEN v_changes END, ex.id);
    END LOOP;
    UPDATE admissions.cce_batch b
       SET counts = (SELECT jsonb_object_agg(c.k, coalesce(x.n, 0))
                       FROM unnest(ARRAY['NEW', 'EXISTING', 'UPDATED', 'DUPLICATE', 'REQUIRES_REVIEW', 'INVALID']) c(k)
                       LEFT JOIN (SELECT classification, count(*) AS n FROM admissions.cce_batch_row WHERE batch_id = v_batch GROUP BY 1) x ON x.classification = c.k)
     WHERE b.id = v_batch;
    RETURN v_batch;
END $fn$;
COMMENT ON FUNCTION admissions.cce_preview(text, text, text, jsonb) IS
  'V379: reads an uploaded CCE list into a PREVIEW batch, every row classified — NEW, EXISTING (unchanged), UPDATED (what changes), DUPLICATE (the same JAMB number earlier in the file), REQUIRES_REVIEW (a programme the Centre does not offer, a number on another session''s list or already a student or a UTME candidate, the same name and date of birth under another number, a change to someone who has applied, a withdrawn candidate), INVALID (what cannot be read). Matching is by JAMB number within the session, never by name.';

/* the commit: NEW rows added, UPDATED rows applied (to candidates who have not applied), EXISTING rows marked as seen; the
   rest stay as they were. All or nothing. */
CREATE OR REPLACE FUNCTION admissions.cce_commit(p_batch uuid)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; b admissions.cce_batch; x record;
        added int := 0; updated int := 0; seen int := 0; skipped int := 0; v_id uuid; v_out jsonb;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['academic', 'super'], 'committing a CCE list');
    SELECT * INTO b FROM admissions.cce_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such CCE list' USING ERRCODE = '23503'; END IF;
    IF b.state <> 'PREVIEW' THEN
        RAISE EXCEPTION 'CCE_LIST_NOT_PREVIEW: the list was % on %', lower(b.state), to_char(coalesce(b.committed_at, b.discarded_at) AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI') USING ERRCODE = '23514';
    END IF;
    FOR x IN SELECT * FROM admissions.cce_batch_row WHERE batch_id = p_batch AND classification IN ('NEW', 'UPDATED', 'EXISTING') ORDER BY row_no LOOP
        v_id := NULL;
        IF x.classification = 'NEW' THEN
            INSERT INTO admissions.cce_candidate (session, jamb_reg_no, jamb_key, surname, first_name, middle_name, date_of_birth, sex, phone, email,
                                                  state_of_origin, lga, nationality, programme_code, olevel_note, remarks, extra, first_batch_id, last_batch_id)
            VALUES (b.session, x.jamb_reg_no, x.jamb_key, x.surname, x.first_name, x.middle_name, x.date_of_birth, x.sex, x.phone, x.email,
                    x.state_of_origin, x.lga, x.nationality, x.programme_code, x.olevel_note, x.remarks, coalesce(x.extra, '{}'::jsonb), b.id, b.id)
            ON CONFLICT (session, jamb_key) DO NOTHING
            RETURNING id INTO v_id;
            IF v_id IS NULL THEN skipped := skipped + 1; ELSE added := added + 1; UPDATE admissions.cce_batch_row SET cce_candidate_id = v_id WHERE id = x.id; END IF;
        ELSIF x.classification = 'UPDATED' THEN
            UPDATE admissions.cce_candidate c
               SET surname = coalesce(x.surname, c.surname), first_name = coalesce(x.first_name, c.first_name), middle_name = coalesce(x.middle_name, c.middle_name),
                   date_of_birth = coalesce(x.date_of_birth, c.date_of_birth), sex = coalesce(x.sex, c.sex), phone = coalesce(x.phone, c.phone),
                   email = coalesce(x.email, c.email), state_of_origin = coalesce(x.state_of_origin, c.state_of_origin), lga = coalesce(x.lga, c.lga),
                   nationality = coalesce(x.nationality, c.nationality), programme_code = coalesce(x.programme_code, c.programme_code),
                   olevel_note = coalesce(x.olevel_note, c.olevel_note), remarks = coalesce(x.remarks, c.remarks), extra = c.extra || coalesce(x.extra, '{}'::jsonb),
                   last_batch_id = b.id, updated_at = now()
             WHERE c.id = x.cce_candidate_id AND c.standing = 'LISTED'
               AND NOT EXISTS (SELECT 1 FROM admissions.candidate a WHERE a.cce_candidate_id = c.id);
            IF FOUND THEN updated := updated + 1; ELSE skipped := skipped + 1; END IF;
        ELSE
            UPDATE admissions.cce_candidate SET last_batch_id = b.id WHERE id = x.cce_candidate_id;
            seen := seen + 1;
        END IF;
    END LOOP;
    v_out := jsonb_build_object('added', added, 'updated', updated, 'unchanged', seen, 'skipped', skipped,
                                'not_loaded', (SELECT count(*) FROM admissions.cce_batch_row WHERE batch_id = p_batch AND classification IN ('DUPLICATE', 'REQUIRES_REVIEW', 'INVALID')));
    UPDATE admissions.cce_batch SET state = 'COMMITTED', committed_by = v_actor, committed_at = now(), applied = v_out WHERE id = p_batch;
    RETURN v_out;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.cce_discard(p_batch uuid, p_reason text)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE b admissions.cce_batch;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['academic', 'super'], 'discarding a CCE list');
    SELECT * INTO b FROM admissions.cce_batch WHERE id = p_batch FOR UPDATE;
    IF b.id IS NULL THEN RAISE EXCEPTION 'no such CCE list' USING ERRCODE = '23503'; END IF;
    IF b.state <> 'PREVIEW' THEN RAISE EXCEPTION 'CCE_LIST_NOT_PREVIEW: only a list still in preview is discarded; this one was %', lower(b.state) USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'CCE_LIST_REASON: a discarded list is kept with the reason it was not loaded' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.cce_batch SET state = 'DISCARDED', discarded_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, discarded_at = now(), discard_reason = btrim(p_reason)
     WHERE id = p_batch;
END $fn$;

/* a listed person withdrawn from the list (with the reason), or reinstated; one already admitted is not withdrawn here */
CREATE OR REPLACE FUNCTION admissions.cce_set_standing(p_candidate uuid, p_standing text, p_reason text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE c admissions.cce_candidate;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['academic', 'super'], 'withdrawing or reinstating a listed CCE candidate');
    SELECT * INTO c FROM admissions.cce_candidate WHERE id = p_candidate FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'no such listed candidate' USING ERRCODE = '23503'; END IF;
    IF p_standing NOT IN ('LISTED', 'WITHDRAWN') THEN RAISE EXCEPTION 'a listed candidate is LISTED or WITHDRAWN' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'CCE_LIST_REASON: the reason is recorded' USING ERRCODE = '23514'; END IF;
    IF p_standing = 'WITHDRAWN' AND EXISTS (SELECT 1 FROM admissions.candidate a WHERE a.cce_candidate_id = c.id AND a.offer_state IN ('ADMITTED', 'ACCEPTED')) THEN
        RAISE EXCEPTION 'CCE_LIST_ADMITTED: % % is already admitted; an admission is not undone by the list', c.surname, c.first_name USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.cce_candidate
       SET standing = p_standing, standing_reason = btrim(p_reason), standing_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, standing_at = now(), updated_at = now()
     WHERE id = p_candidate;
    RETURN p_standing;
END $fn$;

-- ── 6 · the CCE applicant: an ordinary candidate, linked to the list ────────────────────────────────────────────
ALTER TABLE admissions.candidate ADD COLUMN cce_candidate_id uuid NULL REFERENCES admissions.cce_candidate (id);
ALTER TABLE admissions.candidate DROP CONSTRAINT ck_candidate_level;
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_level
    CHECK ((entry_mode = 'UTME' AND entry_level = 100) OR (entry_mode IN ('DIRECT_ENTRY', 'TRANSFER') AND entry_level IN (200, 300))
           OR (entry_mode = 'CCE' AND entry_level IN (100, 200, 300)));
ALTER TABLE admissions.candidate DROP CONSTRAINT ck_candidate_needs_caps;
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_needs_caps
    CHECK (offer_state = 'PROPOSED' OR admitted_from IS NOT NULL OR cce_candidate_id IS NOT NULL);
ALTER TABLE admissions.candidate ADD CONSTRAINT ck_candidate_cce_listed CHECK ((entry_mode = 'CCE') = (cce_candidate_id IS NOT NULL));
CREATE UNIQUE INDEX uq_candidate_cce ON admissions.candidate (cce_candidate_id) WHERE cce_candidate_id IS NOT NULL;
COMMENT ON COLUMN admissions.candidate.cce_candidate_id IS 'V379: the CCE list row a CCE candidate applied from (entry_mode CCE); it stands where admitted_from (the CAPS row) stands for UTME and Direct Entry.';

ALTER TABLE admissions.screening_olevel ADD COLUMN sitting smallint NULL CHECK (sitting IS NULL OR sitting IN (1, 2));
COMMENT ON COLUMN admissions.screening_olevel.sitting IS 'V379: the sitting (1 or 2) a CCE applicant''s O''Level row belongs to.';
-- the result of a second sitting is a document of its own (one current document of each kind)
ALTER TABLE admissions.application_document DROP CONSTRAINT ck_doc_kind;
ALTER TABLE admissions.application_document ADD CONSTRAINT ck_doc_kind
    CHECK (kind IN ('OLEVEL_STATEMENT', 'OLEVEL_STATEMENT_2', 'BIRTH_CERT', 'LGA_ID', 'JAMB_SLIP', 'PASSPORT', 'JAMB_ADMISSION_LETTER', 'STATE_OF_ORIGIN', 'MARRIAGE_CERT',
                    'CHANGE_OF_NAME', 'PREVIOUS_QUALIFICATION', 'OTHER'));

-- ── 7 · the CCE applicant fees, stated by the Bursary ───────────────────────────────────────────────────────────
CREATE TABLE admissions.route_fee (
    session         text NOT NULL REFERENCES policy.academic_session (name),
    route           text NOT NULL REFERENCES policy.study_route (code),
    application_fee numeric(12, 2) NOT NULL CHECK (application_fee >= 0),
    portal_charge   numeric(12, 2) NOT NULL DEFAULT 0 CHECK (portal_charge >= 0),
    acceptance_fee  numeric(12, 2) NOT NULL CHECK (acceptance_fee >= 0),
    stated_by       uuid NOT NULL,
    stated_office   text NOT NULL REFERENCES ref.office (code),
    stated_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session, route)
);
COMMENT ON TABLE admissions.route_fee IS 'V379: the applicant fees of a route with its own admission (CCE) for a session — application fee, portal charge, acceptance fee — stated by the Bursary. The ordinary fee references read them; nothing is hard-coded.';
SELECT audit.attach('admissions.route_fee');

/* the fees for a session: its own, else the last stated (carried, and said so); nothing at all when none was ever stated */
CREATE OR REPLACE FUNCTION admissions.route_fee_rule(p_session text, p_route text)
RETURNS TABLE (stated boolean, application_fee numeric, portal_charge numeric, acceptance_fee numeric, carried_from text)
LANGUAGE sql STABLE AS $fn$
    WITH own AS (SELECT true, f.application_fee, f.portal_charge, f.acceptance_fee, NULL::text
                   FROM admissions.route_fee f WHERE f.session = p_session AND f.route = upper(btrim(p_route))),
         carried AS (SELECT false, f.application_fee, f.portal_charge, f.acceptance_fee, f.session
                       FROM admissions.route_fee f WHERE f.route = upper(btrim(p_route)) AND NOT EXISTS (SELECT 1 FROM own)
                      ORDER BY f.stated_at DESC, f.session DESC LIMIT 1)
    SELECT * FROM own UNION ALL SELECT * FROM carried
$fn$;

CREATE OR REPLACE FUNCTION admissions.set_route_fee(p_session text, p_route text, p_application numeric, p_portal numeric, p_acceptance numeric)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['bursar', 'super'], 'stating the CCE applicant fees');
    IF p_application IS NULL OR p_acceptance IS NULL OR p_application < 0 OR p_acceptance < 0 OR coalesce(p_portal, 0) < 0 THEN
        RAISE EXCEPTION 'CCE_FEE_AMOUNT: the application and acceptance fees are stated, and none is negative' USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.route_fee (session, route, application_fee, portal_charge, acceptance_fee, stated_by, stated_office)
    VALUES (p_session, upper(btrim(p_route)), p_application, coalesce(p_portal, 0), p_acceptance,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, current_setting('moaum.actor_office', true))
    ON CONFLICT (session, route) DO UPDATE SET application_fee = EXCLUDED.application_fee, portal_charge = EXCLUDED.portal_charge,
        acceptance_fee = EXCLUDED.acceptance_fee, stated_by = EXCLUDED.stated_by, stated_office = EXCLUDED.stated_office, stated_at = now();
END $fn$;

-- ── 8 · the Centre's review ─────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE admissions.cce_review (
    application_id         uuid PRIMARY KEY REFERENCES admissions.application (id) ON DELETE CASCADE,
    state                  text NOT NULL DEFAULT 'DRAFT'
                           CHECK (state IN ('DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED', 'RECOMMENDED',
                                            'APPROVED', 'ADMITTED', 'NOT_ADMITTED', 'REJECTED')),
    programme_confirmed_at timestamptz NULL,
    submitted_at           timestamptz NULL,
    review_started_at      timestamptz NULL,
    review_started_by      uuid NULL,
    request_note           text NULL,
    requested_at           timestamptz NULL,
    requested_by           uuid NULL,
    recommended_at         timestamptz NULL,
    recommended_by         uuid NULL,
    recommendation_note    text NULL,
    decided_at             timestamptz NULL,
    decided_by             uuid NULL,
    decided_office         text NULL,
    decision_note          text NULL,
    published_at           timestamptz NULL,
    published_by           uuid NULL,
    updated_at             timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_cce_review_request CHECK (state NOT IN ('DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED') OR nullif(btrim(coalesce(request_note, '')), '') IS NOT NULL),
    CONSTRAINT ck_cce_review_declined CHECK (state NOT IN ('NOT_ADMITTED', 'REJECTED') OR nullif(btrim(coalesce(decision_note, '')), '') IS NOT NULL),
    CONSTRAINT ck_cce_review_two_people CHECK (state NOT IN ('APPROVED', 'ADMITTED') OR (recommended_by IS NOT NULL AND decided_by IS NOT NULL AND decided_by <> recommended_by)),
    CONSTRAINT ck_cce_review_published CHECK (state <> 'ADMITTED' OR published_at IS NOT NULL)
);
CREATE INDEX ix_cce_review_state ON admissions.cce_review (state);
COMMENT ON TABLE admissions.cce_review IS
  'V379: the Centre for Continuing Education''s review of a CCE application — DRAFT (the applicant''s), SUBMITTED, UNDER_REVIEW, DOCUMENTS_PENDING and VERIFICATION_REQUIRED (back with the applicant, the request noted), RECOMMENDED, APPROVED (by someone other than the officer who recommended), then ADMITTED when the Academic Office publishes; NOT_ADMITTED or REJECTED with the reason. Publication writes the ordinary admissions decision and releases it.';
SELECT audit.attach('admissions.cce_review');

CREATE TABLE admissions.cce_review_event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application (id) ON DELETE CASCADE,
    at             timestamptz NOT NULL DEFAULT clock_timestamp(),
    actor          uuid NULL,
    office         text NULL,
    action         text NOT NULL,
    from_state     text NULL,
    to_state       text NULL,
    note           text NULL
);
CREATE INDEX ix_cce_review_event ON admissions.cce_review_event (application_id, at);
CREATE INDEX ix_cce_review_event_at ON admissions.cce_review_event (at DESC);
COMMENT ON TABLE admissions.cce_review_event IS 'V379: the history of a CCE application — every step, who took it, from which office, and the note. Written once.';
CREATE OR REPLACE FUNCTION admissions.cce_review_event_once() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM admissions.application a WHERE a.id = OLD.application_id) THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'a CCE application''s history is written once and never changed' USING ERRCODE = '23514';
END $fn$;
CREATE TRIGGER trg_cce_review_event_once BEFORE UPDATE OR DELETE ON admissions.cce_review_event FOR EACH ROW EXECUTE FUNCTION admissions.cce_review_event_once();
SELECT audit.attach('admissions.cce_review_event');

CREATE OR REPLACE FUNCTION admissions.cce_log(p_app uuid, p_action text, p_from text, p_to text, p_note text)
RETURNS void LANGUAGE sql AS $fn$
    INSERT INTO admissions.cce_review_event (application_id, actor, office, action, from_state, to_state, note)
    VALUES (p_app, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''), p_action, p_from, p_to,
            nullif(btrim(coalesce(p_note, '')), ''))
$fn$;

/* the application of a CCE applicant, or an error saying it is not one */
CREATE OR REPLACE FUNCTION admissions.cce_application(p_app uuid)
RETURNS TABLE (application_id uuid, session text, candidate_id uuid, cce_candidate_id uuid, programme_code text, state text)
LANGUAGE plpgsql STABLE AS $fn$
BEGIN
    RETURN QUERY
    SELECT a.id, a.session, c.id, c.cce_candidate_id, l.programme_code, r.state
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode = 'CCE'
      JOIN admissions.cce_candidate l ON l.id = c.cce_candidate_id
      JOIN admissions.cce_review r ON r.application_id = a.id
     WHERE a.id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'CCE_NOT_CCE: that is not a CCE application' USING ERRCODE = '23503'; END IF;
END $fn$;

-- ── 9 · the CCE applicant registers: the JAMB number and the date of birth on the list ─────────────────────────
/* who a JAMB number and date of birth are on the CCE list: 'nomatch' says nothing more (a number on the list with the wrong
   date reads the same as a number not on it), 'found', 'registered' (an account exists), 'closed' (the programme no longer
   admits). The session is the current CCE session's list when the number is on it, else the latest. */
CREATE OR REPLACE FUNCTION admissions.cce_lookup(p_jamb text, p_dob date)
RETURNS TABLE (state text, cce_candidate_id uuid, session text, surname text, first_name text, middle_name text, programme_code text, programme text,
               window_state text)
LANGUAGE sql STABLE AS $fn$
    WITH k AS (SELECT upper(regexp_replace(coalesce(p_jamb, ''), '\s', '', 'g')) AS key),
         l AS (SELECT c.* FROM admissions.cce_candidate c, k
                WHERE c.jamb_key = k.key AND c.date_of_birth = p_dob AND c.standing = 'LISTED'
                ORDER BY (c.session = policy.route_session('CCE')) DESC, c.session DESC LIMIT 1)
    SELECT CASE WHEN l.id IS NULL THEN 'nomatch'
                WHEN EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE a.session = l.session AND a.jamb_key = l.jamb_key) THEN 'registered'
                WHEN NOT coalesce((SELECT t.active FROM ref.programme_route_terms(l.programme_code, 'CCE') t), false) THEN 'closed'
                ELSE 'found' END,
           l.id, l.session, l.surname, l.first_name, l.middle_name, l.programme_code, p.name,
           (SELECT w.state FROM policy.window_state('CCE_APPLICATION', l.session, NULL) w)
      FROM (SELECT 1) one LEFT JOIN l ON true LEFT JOIN ref.programme p ON p.code = l.programme_code
$fn$;

/* the CCE applicant's account and application: only a listed number with its date of birth, while the CCE application
   window of the list's session is open, once. The candidate is an ordinary admissions candidate (entry_mode CCE) filed
   under the CCE session of the list; what the list gave is carried into the form. */
CREATE OR REPLACE FUNCTION admissions.cce_register(p_jamb text, p_dob date, p_email text, p_phone text, p_hash text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE f record; l admissions.cce_candidate; v_candidate uuid := gen_random_uuid(); v_account uuid := gen_random_uuid(); v_app uuid := gen_random_uuid();
        v_no text; v_terms record; fee record;
BEGIN
    SELECT * INTO f FROM admissions.cce_lookup(p_jamb, p_dob);
    IF f.state = 'nomatch' THEN
        RAISE EXCEPTION 'CCE_NOT_LISTED: that JAMB number and date of birth are not together on the CCE list' USING ERRCODE = '23514',
            HINT = 'Type the JAMB number exactly as JAMB gave it and your date of birth as on the list. If both are right, the Centre for Continuing Education can tell you whether your name has reached the University.';
    ELSIF f.state = 'registered' THEN
        RAISE EXCEPTION 'CCE_REGISTERED: an application account already exists for this JAMB number' USING ERRCODE = '23514',
            HINT = 'Sign in with the email and password you chose; a forgotten password is reset from the sign-in page.';
    ELSIF f.state = 'closed' THEN
        RAISE EXCEPTION 'CCE_PROGRAMME_CLOSED: the Centre is not admitting into % at present', f.programme USING ERRCODE = '23514';
    END IF;
    IF coalesce(f.window_state, 'CLOSED') <> 'OPEN' THEN
        RAISE EXCEPTION 'APPLICATION_CLOSED: the CCE application for % is %', f.session, lower(coalesce(f.window_state, 'closed')) USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.applicant_account a WHERE lower(a.email) = lower(btrim(p_email))) THEN
        RAISE EXCEPTION 'the address % already belongs to an application account', btrim(p_email) USING ERRCODE = '23505', HINT = 'Sign in with it, or use another address.';
    END IF;
    SELECT * INTO l FROM admissions.cce_candidate WHERE id = f.cce_candidate_id FOR UPDATE;
    SELECT * INTO v_terms FROM ref.programme_route_terms(l.programme_code, 'CCE');
    -- the candidate's JAMB number is the list's, as the list's key reads it (the candidate's own key is generated from it)
    INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, cce_candidate_id)
    VALUES (v_candidate, l.session, l.jamb_key, l.surname, btrim(l.first_name || coalesce(' ' || l.middle_name, '')),
            (SELECT p.name FROM ref.programme p WHERE p.code = l.programme_code), 'CCE', v_terms.entry_level, 'PROPOSED', l.id);
    INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
    VALUES (v_account, l.session, v_candidate, l.jamb_key, btrim(p_email), p_phone, p_hash);
    v_no := 'APP/' || substr(l.session, 3, 2) || '/' || lpad(platform.next_number('APPLICATION', 'UNIVERSITY', l.session)::text, 6, '0');
    INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no) VALUES (v_app, v_account, v_candidate, l.session, v_no);
    INSERT INTO admissions.cce_review (application_id, state) VALUES (v_app, 'DRAFT');
    -- what the list gave is carried into the form; the applicant confirms or completes it
    INSERT INTO admissions.screening_answer (application_id, field, value)
    SELECT v_app, x.field, x.value FROM (VALUES ('date_of_birth', l.date_of_birth::text), ('state_of_origin', l.state_of_origin), ('lga', l.lga),
                                                ('nationality', l.nationality), ('mobile', coalesce(p_phone, l.phone)), ('personal_email', btrim(p_email))) x(field, value)
     WHERE nullif(btrim(coalesce(x.value, '')), '') IS NOT NULL;
    -- an application fee stated as nothing is nothing to pay
    SELECT * INTO fee FROM admissions.route_fee_rule(l.session, 'CCE');
    IF coalesce(fee.application_fee, -1) + coalesce(fee.portal_charge, 0) = 0 THEN
        UPDATE admissions.application SET fee_confirmed_at = now() WHERE id = v_app;
    END IF;
    PERFORM admissions.cce_log(v_app, 'REGISTERED', NULL, 'DRAFT', 'The application account was opened from the CCE list');
    RETURN v_account;
END $fn$;

-- ── 10 · the CCE application form ───────────────────────────────────────────────────────────────────────────────
/* the biodata a CCE applicant gives, and which of it is required */
CREATE OR REPLACE FUNCTION admissions.cce_form_fields()
RETURNS TABLE (field text, required boolean)
LANGUAGE sql IMMUTABLE AS $fn$
    VALUES ('date_of_birth', true), ('place_of_birth', false), ('marital_status', false), ('religion', false), ('home_address', true),
           ('postal_address', false), ('state_of_origin', true), ('lga', true), ('nationality', true), ('mobile', true), ('alt_mobile', false),
           ('personal_email', false), ('employer', false), ('disability', false), ('kin_name', true), ('kin_relationship', true),
           ('kin_mobile', true), ('kin_address', false)
$fn$;

/* the applicant may change the form while it is theirs: a draft, or back with them for documents or verification */
CREATE OR REPLACE FUNCTION admissions.cce_require_editable(p_app uuid)
RETURNS admissions.cce_review LANGUAGE plpgsql AS $fn$
DECLARE r admissions.cce_review;
BEGIN
    PERFORM admissions.cce_application(p_app);
    SELECT * INTO r FROM admissions.cce_review WHERE application_id = p_app FOR UPDATE;
    IF r.state NOT IN ('DRAFT', 'DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED') THEN
        RAISE EXCEPTION 'CCE_NOT_EDITABLE: the application is % and is with the Centre; it is changed only when the Centre asks', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    RETURN r;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.cce_save_biodata(p_app uuid, p_fields jsonb)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE r admissions.cce_review; k text; v text; n int := 0; l admissions.cce_candidate; d date;
BEGIN
    r := admissions.cce_require_editable(p_app);
    SELECT x.* INTO l FROM admissions.cce_candidate x JOIN admissions.candidate c ON c.cce_candidate_id = x.id JOIN admissions.application a ON a.candidate_id = c.id WHERE a.id = p_app;
    IF p_fields IS NULL OR jsonb_typeof(p_fields) <> 'object' THEN RAISE EXCEPTION 'the form is a set of fields' USING ERRCODE = '23514'; END IF;
    FOR k IN SELECT jsonb_object_keys(p_fields) LOOP
        IF NOT EXISTS (SELECT 1 FROM admissions.cce_form_fields() f WHERE f.field = k) THEN
            RAISE EXCEPTION 'CCE_FIELD: % is not a field of the CCE form', k USING ERRCODE = '23514';
        END IF;
        v := nullif(btrim(coalesce(p_fields->>k, '')), '');
        IF v IS NOT NULL AND length(v) > 400 THEN RAISE EXCEPTION 'CCE_FIELD: % is too long', k USING ERRCODE = '23514'; END IF;
        IF k = 'date_of_birth' AND v IS NOT NULL THEN
            d := admissions.cce_date(v);
            IF d IS NULL THEN RAISE EXCEPTION 'CCE_FIELD: the date of birth cannot be read' USING ERRCODE = '23514'; END IF;
            IF d <> l.date_of_birth THEN
                RAISE EXCEPTION 'CCE_DATE_OF_BIRTH: the date of birth is the one on the CCE list (%); if the list is wrong, write to the Centre for Continuing Education', to_char(l.date_of_birth, 'DD Mon YYYY') USING ERRCODE = '23514';
            END IF;
            v := d::text;
        END IF;
        IF k IN ('mobile', 'alt_mobile', 'kin_mobile') AND v IS NOT NULL THEN
            IF admissions.cce_phone(v) IS NULL THEN RAISE EXCEPTION 'CCE_FIELD: % is not a Nigerian mobile number (eleven digits beginning with 0)', replace(k, '_', ' ') USING ERRCODE = '23514'; END IF;
            v := admissions.cce_phone(v);
        END IF;
        IF k = 'personal_email' AND v IS NOT NULL AND v !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN RAISE EXCEPTION 'CCE_FIELD: that is not a complete email address' USING ERRCODE = '23514'; END IF;
        IF v IS NULL THEN
            DELETE FROM admissions.screening_answer WHERE application_id = p_app AND field = k;
        ELSE
            INSERT INTO admissions.screening_answer (application_id, field, value) VALUES (p_app, k, v)
            ON CONFLICT (application_id, field) DO UPDATE SET value = EXCLUDED.value;
        END IF;
        n := n + 1;
    END LOOP;
    -- the next of kin as the ordinary application carries it
    UPDATE admissions.application a
       SET next_of_kin = nullif(btrim(concat_ws(', ', (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_name')
                                                    || coalesce(' (' || (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_relationship') || ')', ''),
                                                (SELECT value FROM admissions.screening_answer WHERE application_id = p_app AND field = 'kin_mobile'))), '')
     WHERE a.id = p_app;
    RETURN n;
END $fn$;

/* the O'Level: one sitting or two, each complete — the examination body, number and year, and its subjects and grades */
CREATE OR REPLACE FUNCTION admissions.cce_save_olevel(p_app uuid, p_sittings jsonb)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE r admissions.cce_review; s jsonb; g jsonb; v_sit int; v_body text; v_no text; v_year int; n int := 0; ord int := 0; v_subj text; v_grade text;
        seen text[];
BEGIN
    r := admissions.cce_require_editable(p_app);
    IF p_sittings IS NULL OR jsonb_typeof(p_sittings) <> 'array' OR jsonb_array_length(p_sittings) NOT BETWEEN 1 AND 2 THEN
        RAISE EXCEPTION 'CCE_OLEVEL_SITTINGS: one sitting or two' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.screening_olevel SET active = false WHERE application_id = p_app AND active;
    FOR s IN SELECT x FROM jsonb_array_elements(p_sittings) x LOOP
        v_sit := coalesce((s->>'sitting')::int, 0);
        IF v_sit NOT IN (1, 2) THEN RAISE EXCEPTION 'CCE_OLEVEL_SITTINGS: a sitting is the first or the second' USING ERRCODE = '23514'; END IF;
        v_body := upper(btrim(coalesce(s->>'exam_body', '')));
        IF v_body NOT IN ('WAEC', 'NECO', 'NABTEB', 'OTHER') THEN
            RAISE EXCEPTION 'CCE_OLEVEL_BODY: sitting %: the examination body is WAEC, NECO, NABTEB or another', v_sit USING ERRCODE = '23514';
        END IF;
        v_no := nullif(btrim(coalesce(s->>'exam_number', '')), '');
        IF v_no IS NULL OR length(v_no) > 30 THEN RAISE EXCEPTION 'CCE_OLEVEL_NUMBER: sitting %: the examination number is given', v_sit USING ERRCODE = '23514'; END IF;
        v_year := CASE WHEN coalesce(s->>'exam_year', '') ~ '^[0-9]{4}$' THEN (s->>'exam_year')::int END;
        IF v_year IS NULL OR v_year < 1970 OR v_year > extract(year FROM current_date)::int THEN
            RAISE EXCEPTION 'CCE_OLEVEL_YEAR: sitting %: the year of the examination is given', v_sit USING ERRCODE = '23514';
        END IF;
        IF jsonb_typeof(s->'subjects') <> 'array' OR jsonb_array_length(s->'subjects') = 0 THEN
            RAISE EXCEPTION 'CCE_OLEVEL_INCOMPLETE: sitting % has no subjects; a second sitting is complete or not given', v_sit USING ERRCODE = '23514';
        END IF;
        IF jsonb_array_length(s->'subjects') > 9 THEN RAISE EXCEPTION 'CCE_OLEVEL_SUBJECTS: sitting %: nine subjects at most', v_sit USING ERRCODE = '23514'; END IF;
        seen := '{}';
        FOR g IN SELECT x FROM jsonb_array_elements(s->'subjects') x LOOP
            v_subj := nullif(btrim(coalesce(g->>'subject', '')), '');
            v_grade := upper(btrim(coalesce(g->>'grade', '')));
            IF v_subj IS NULL OR length(v_subj) > 60 THEN RAISE EXCEPTION 'CCE_OLEVEL_INCOMPLETE: sitting %: a subject is named', v_sit USING ERRCODE = '23514'; END IF;
            IF v_grade NOT IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6', 'D7', 'E8', 'F9') THEN
                RAISE EXCEPTION 'CCE_OLEVEL_GRADE: sitting %, %: the grade is one of A1, B2, B3, C4, C5, C6, D7, E8, F9', v_sit, v_subj USING ERRCODE = '23514';
            END IF;
            IF upper(v_subj) = ANY (seen) THEN RAISE EXCEPTION 'CCE_OLEVEL_SUBJECTS: sitting %: % is given twice', v_sit, v_subj USING ERRCODE = '23514'; END IF;
            seen := array_append(seen, upper(v_subj));
            ord := ord + 1;
            INSERT INTO admissions.screening_olevel (application_id, ord, exam_body, exam_number, exam_year, subject, grade, active, sitting)
            VALUES (p_app, ord, v_body, v_no, v_year, v_subj, v_grade, true, v_sit);
            n := n + 1;
        END LOOP;
    END LOOP;
    IF (SELECT count(DISTINCT sitting) FROM admissions.screening_olevel WHERE application_id = p_app AND active) <> jsonb_array_length(p_sittings) THEN
        RAISE EXCEPTION 'CCE_OLEVEL_SITTINGS: the same sitting is given twice' USING ERRCODE = '23514';
    END IF;
    RETURN n;
END $fn$;

CREATE OR REPLACE FUNCTION admissions.cce_confirm_programme(p_app uuid)
RETURNS timestamptz LANGUAGE plpgsql AS $fn$
DECLARE r admissions.cce_review;
BEGIN
    r := admissions.cce_require_editable(p_app);
    UPDATE admissions.cce_review SET programme_confirmed_at = coalesce(programme_confirmed_at, now()), updated_at = now() WHERE application_id = p_app
    RETURNING programme_confirmed_at INTO r.programme_confirmed_at;
    RETURN r.programme_confirmed_at;
END $fn$;

/* a document's name as the applicant reads it */
CREATE OR REPLACE FUNCTION admissions.cce_document_word(p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE p_kind WHEN 'PASSPORT' THEN 'passport photograph' WHEN 'OLEVEL_STATEMENT' THEN 'first sitting''s O''Level result'
                       WHEN 'OLEVEL_STATEMENT_2' THEN 'second sitting''s O''Level result' WHEN 'BIRTH_CERT' THEN 'birth certificate'
                       ELSE lower(replace(coalesce(p_kind, 'document'), '_', ' ')) END
$fn$;

/* what still stands between the applicant and submitting, step by step */
CREATE OR REPLACE FUNCTION admissions.cce_application_problems(p_app uuid)
RETURNS TABLE (step text, field text, message text)
LANGUAGE sql STABLE AS $fn$
    WITH a AS (SELECT ap.*, c.cce_candidate_id FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id WHERE ap.id = p_app),
         l AS (SELECT x.* FROM admissions.cce_candidate x JOIN a ON a.cce_candidate_id = x.id),
         r AS (SELECT x.* FROM admissions.cce_review x WHERE x.application_id = p_app),
         fee AS (SELECT f.* FROM a CROSS JOIN LATERAL admissions.route_fee_rule(a.session, 'CCE') f),
         ans AS (SELECT x.field, x.value FROM admissions.screening_answer x WHERE x.application_id = p_app),
         ol AS (SELECT x.* FROM admissions.screening_olevel x WHERE x.application_id = p_app AND x.active),
         sittings AS (SELECT count(DISTINCT sitting) AS n FROM ol),
         docs AS (SELECT d.* FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL)
    SELECT 'PAYMENT', 'application_fee', CASE WHEN NOT EXISTS (SELECT 1 FROM fee) THEN 'The Bursary has not yet stated the CCE application fee for ' || (SELECT session FROM a) || '; the form is completed and submitted once it is paid'
                                              ELSE 'Pay the CCE application fee' END
     WHERE (SELECT fee_confirmed_at FROM a) IS NULL
    UNION ALL
    SELECT 'PERSONAL', f.field, 'Give your ' || replace(replace(replace(f.field, 'kin_', 'next of kin''s '), '_', ' '), 'lga', 'local government area')
      FROM admissions.cce_form_fields() f WHERE f.required AND NOT EXISTS (SELECT 1 FROM ans WHERE ans.field = f.field)
    UNION ALL
    SELECT 'OLEVEL', 'sittings', 'Give your O''Level results (one sitting or two)' WHERE (SELECT n FROM sittings) = 0
    UNION ALL
    SELECT 'OLEVEL', 'subjects', 'Give at least five subjects across your sittings' WHERE (SELECT n FROM sittings) > 0 AND (SELECT count(*) FROM ol) < 5
    UNION ALL
    SELECT 'OLEVEL', 'compulsory', cs.subject || ' is not among your O''Level subjects'
      FROM a CROSS JOIN LATERAL admissions.olevel_compulsory_subjects(a.session) cs
     WHERE (SELECT n FROM sittings) > 0 AND NOT EXISTS (SELECT 1 FROM ol WHERE ol.subject ~ cs.pattern)
    UNION ALL
    SELECT 'DOCUMENTS', 'PASSPORT', 'Upload your passport photograph' WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = 'PASSPORT')
    UNION ALL
    SELECT 'DOCUMENTS', 'OLEVEL_STATEMENT', CASE WHEN (SELECT n FROM sittings) = 2 THEN 'Upload the O''Level result of your first sitting' ELSE 'Upload your O''Level result' END
     WHERE NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = 'OLEVEL_STATEMENT')
    UNION ALL
    SELECT 'DOCUMENTS', 'OLEVEL_STATEMENT_2', 'Upload the O''Level result of your second sitting'
     WHERE (SELECT n FROM sittings) = 2 AND NOT EXISTS (SELECT 1 FROM docs WHERE docs.kind = 'OLEVEL_STATEMENT_2')
    UNION ALL
    SELECT 'DOCUMENTS', d.kind, 'Replace your ' || admissions.cce_document_word(d.kind) || ', which the Centre could not accept: '
                                 || rtrim(coalesce(d.review_note, ''), '. ')
      FROM docs d WHERE d.status = 'REJECTED'
    UNION ALL
    SELECT 'PROGRAMME', 'programme', 'Confirm the programme you are applying for' WHERE (SELECT programme_confirmed_at FROM r) IS NULL
    UNION ALL
    SELECT 'PROGRAMME', 'programme', 'The Centre is not admitting into ' || (SELECT p.name FROM ref.programme p JOIN l ON l.programme_code = p.code) || ' at present'
     WHERE NOT coalesce((SELECT t.active FROM l CROSS JOIN LATERAL ref.programme_route_terms(l.programme_code, 'CCE') t), false)
$fn$;

/* the applicant submits — or, when the Centre asked for documents or verification, sends the application back to it */
CREATE OR REPLACE FUNCTION admissions.cce_submit(p_app uuid, p_ip text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.cce_review; a admissions.application; fee record; v_missing text;
BEGIN
    PERFORM admissions.cce_application(p_app);
    SELECT * INTO r FROM admissions.cce_review WHERE application_id = p_app FOR UPDATE;
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    IF r.state NOT IN ('DRAFT', 'DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED') THEN RETURN 'already submitted'; END IF;
    IF a.fee_confirmed_at IS NULL THEN
        SELECT * INTO fee FROM admissions.route_fee_rule(a.session, 'CCE');
        IF fee.stated IS NOT NULL AND fee.application_fee + fee.portal_charge = 0 THEN
            UPDATE admissions.application SET fee_confirmed_at = now() WHERE id = p_app;
        END IF;
    END IF;
    SELECT string_agg(x.message, '; ') INTO v_missing FROM (SELECT p.message FROM admissions.cce_application_problems(p_app) p LIMIT 6) x;
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'CCE_INCOMPLETE: the application is not complete: %', v_missing USING ERRCODE = '23514';
    END IF;
    IF r.state = 'DRAFT' THEN
        UPDATE admissions.application SET submitted_at = now(), declaration_ip = p_ip WHERE id = p_app;
        UPDATE admissions.cce_review SET state = 'SUBMITTED', submitted_at = now(), updated_at = now() WHERE application_id = p_app;
        PERFORM admissions.cce_log(p_app, 'SUBMITTED', 'DRAFT', 'SUBMITTED', NULL);
        PERFORM admissions.notify_applicant(p_app, 'Your CCE application is submitted',
            'Your application to the Centre for Continuing Education (application number ' || a.application_no || ', ' || a.session || ' session) is submitted. '
            || 'The Centre reviews it; you will be told here and by email if anything more is needed, and when the admission list is published. Keep your acknowledgement.',
            'MOAUM: your CCE application ' || a.application_no || ' is submitted. The Centre will review it.');
        RETURN 'submitted';
    END IF;
    UPDATE admissions.cce_review SET state = 'UNDER_REVIEW', updated_at = now() WHERE application_id = p_app;
    PERFORM admissions.cce_log(p_app, 'PROVIDED', r.state, 'UNDER_REVIEW', 'The applicant sent the application back with what was asked');
    RETURN 'returned to the Centre';
END $fn$;

-- ── 11 · the Centre reviews, the Academic Office oversees and publishes ─────────────────────────────────────────
/* a document of a CCE application accepted or rejected (with the reason) by the Centre */
CREATE OR REPLACE FUNCTION admissions.cce_review_document(p_document uuid, p_status text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE d admissions.application_document; r admissions.cce_review;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['cce', 'super'], 'verifying a CCE applicant''s documents');
    SELECT * INTO d FROM admissions.application_document WHERE id = p_document FOR UPDATE;
    IF d.id IS NULL THEN RAISE EXCEPTION 'no such document' USING ERRCODE = '23503'; END IF;
    PERFORM admissions.cce_application(d.application_id);
    SELECT * INTO r FROM admissions.cce_review WHERE application_id = d.application_id;
    IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED', 'RECOMMENDED') THEN
        RAISE EXCEPTION 'CCE_REVIEW_STATE: the documents of a % application are not reviewed', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF p_status NOT IN ('ACCEPTED', 'REJECTED') THEN RAISE EXCEPTION 'a document is ACCEPTED or REJECTED' USING ERRCODE = '23514'; END IF;
    IF p_status = 'REJECTED' AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'CCE_DOCUMENT_REASON: a document is rejected with the reason the applicant reads' USING ERRCODE = '23514';
    END IF;
    IF d.superseded_at IS NOT NULL THEN RAISE EXCEPTION 'CCE_DOCUMENT_REPLACED: the applicant has replaced this document' USING ERRCODE = '23514'; END IF;
    UPDATE admissions.application_document SET status = p_status, reviewed_at = now(), reviewed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           review_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = p_document;
    PERFORM admissions.cce_log(d.application_id, 'DOCUMENT_' || p_status, r.state, r.state,
                               upper(left(admissions.cce_document_word(d.kind), 1)) || substr(admissions.cce_document_word(d.kind), 2)
                               || coalesce(': ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    RETURN p_status;
END $fn$;

/* one step of the review. START (submitted → under review), REQUEST_DOCUMENTS and REQUIRE_VERIFICATION (back to the applicant,
   with what is needed), RESUME (back under review), RECOMMEND, APPROVE (by someone other than the recommender), NOT_ADMIT,
   REJECT (with the reason), REOPEN (an unpublished decision back under review). */
CREATE OR REPLACE FUNCTION admissions.cce_act(p_app uuid, p_action text, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE r admissions.cce_review; a admissions.application; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_to text; v_missing text[]; v_pending int;
BEGIN
    PERFORM admissions.cce_application(p_app);
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a CCE application is reviewed by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM admissions.cce_review WHERE application_id = p_app FOR UPDATE;
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF r.published_at IS NOT NULL THEN
        RAISE EXCEPTION 'CCE_PUBLISHED: the outcome was published on % and stands', to_char(r.published_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') USING ERRCODE = '23514';
    END IF;
    CASE upper(p_action)
    WHEN 'START' THEN
        PERFORM admissions.cce_require_office(ARRAY['cce', 'super'], 'reviewing CCE applications');
        IF r.state <> 'SUBMITTED' THEN RAISE EXCEPTION 'CCE_REVIEW_STATE: only a submitted application is taken up; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514'; END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.cce_review SET state = v_to, review_started_at = now(), review_started_by = v_actor, updated_at = now() WHERE application_id = p_app;
    WHEN 'REQUEST_DOCUMENTS', 'REQUIRE_VERIFICATION' THEN
        PERFORM admissions.cce_require_office(ARRAY['cce', 'super'], 'asking a CCE applicant for documents or verification');
        IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'RECOMMENDED') THEN
            RAISE EXCEPTION 'CCE_REVIEW_STATE: a % application is not sent back to the applicant', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'CCE_REQUEST_NOTE: say what the applicant is to provide' USING ERRCODE = '23514'; END IF;
        v_to := CASE upper(p_action) WHEN 'REQUEST_DOCUMENTS' THEN 'DOCUMENTS_PENDING' ELSE 'VERIFICATION_REQUIRED' END;
        UPDATE admissions.cce_review SET state = v_to, request_note = v_note, requested_at = now(), requested_by = v_actor,
               recommended_at = NULL, recommended_by = NULL, recommendation_note = NULL, updated_at = now()
         WHERE application_id = p_app;
        PERFORM admissions.notify_applicant(p_app, 'The Centre for Continuing Education needs more from you',
            'The Centre has reviewed your CCE application (' || a.application_no || ') and needs something more from you before it can continue. '
            || 'Sign in to the applicant portal to read what is asked, provide it, and send the application back to the Centre.',
            'MOAUM: the Centre for Continuing Education needs more for your application ' || a.application_no || '. Sign in to see what.');
    WHEN 'RESUME' THEN
        PERFORM admissions.cce_require_office(ARRAY['cce', 'super'], 'reviewing CCE applications');
        IF r.state NOT IN ('DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED') THEN
            RAISE EXCEPTION 'CCE_REVIEW_STATE: only an application waiting on the applicant is taken back; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.cce_review SET state = v_to, updated_at = now() WHERE application_id = p_app;
    WHEN 'RECOMMEND' THEN
        PERFORM admissions.cce_require_office(ARRAY['cce', 'super'], 'recommending a CCE admission');
        IF r.state <> 'UNDER_REVIEW' THEN
            RAISE EXCEPTION 'CCE_REVIEW_STATE: an application is recommended from review; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        SELECT count(*) INTO v_pending FROM admissions.application_document d WHERE d.application_id = p_app AND d.superseded_at IS NULL AND d.status <> 'ACCEPTED';
        IF v_pending > 0 THEN
            RAISE EXCEPTION 'CCE_DOCUMENTS_UNVERIFIED: % document(s) not yet accepted; verify every document before recommending', v_pending USING ERRCODE = '23514';
        END IF;
        -- the compulsory credits on the O'Level the applicant gave (a pass is not a credit)
        SELECT array_agg(cs.subject ORDER BY cs.subject) INTO v_missing
          FROM admissions.olevel_compulsory_subjects(a.session) cs
         WHERE NOT EXISTS (SELECT 1 FROM admissions.screening_olevel o
                            WHERE o.application_id = p_app AND o.active AND o.subject ~ cs.pattern AND o.grade IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6'));
        IF v_missing IS NOT NULL THEN
            RAISE EXCEPTION 'CCE_OLEVEL_CREDIT: no credit in %; a pass does not count', array_to_string(v_missing, ', ') USING ERRCODE = '23514';
        END IF;
        v_to := 'RECOMMENDED';
        UPDATE admissions.cce_review SET state = v_to, recommended_at = now(), recommended_by = v_actor, recommendation_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'APPROVE' THEN
        PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'approving a CCE admission');
        IF r.state <> 'RECOMMENDED' THEN
            RAISE EXCEPTION 'CCE_REVIEW_STATE: an admission is approved once recommended; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF r.recommended_by = v_actor THEN
            RAISE EXCEPTION 'CCE_APPROVE_OWN: the officer who recommended an admission does not also approve it; the Director of the Centre or the Academic Office approves' USING ERRCODE = '23514';
        END IF;
        v_to := 'APPROVED';
        UPDATE admissions.cce_review SET state = v_to, decided_at = now(), decided_by = v_actor, decided_office = v_office, decision_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'NOT_ADMIT', 'REJECT' THEN
        PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'deciding a CCE application');
        IF r.state NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED', 'RECOMMENDED', 'APPROVED') THEN
            RAISE EXCEPTION 'CCE_REVIEW_STATE: a % application is not decided', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'CCE_DECISION_NOTE: the reason is recorded and is what the applicant reads' USING ERRCODE = '23514'; END IF;
        v_to := CASE upper(p_action) WHEN 'NOT_ADMIT' THEN 'NOT_ADMITTED' ELSE 'REJECTED' END;
        UPDATE admissions.cce_review SET state = v_to, decided_at = now(), decided_by = v_actor, decided_office = v_office, decision_note = v_note, updated_at = now() WHERE application_id = p_app;
    WHEN 'REOPEN' THEN
        PERFORM admissions.cce_require_office(ARRAY['cce', 'academic', 'super'], 'reopening a CCE application');
        IF r.state NOT IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED') THEN
            RAISE EXCEPTION 'CCE_REVIEW_STATE: only a decided, unpublished application is reopened; this one is %', lower(replace(r.state, '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF v_note IS NULL THEN RAISE EXCEPTION 'CCE_REOPEN_NOTE: say why the decision is reopened' USING ERRCODE = '23514'; END IF;
        v_to := 'UNDER_REVIEW';
        UPDATE admissions.cce_review SET state = v_to, decided_at = NULL, decided_by = NULL, decided_office = NULL, decision_note = NULL,
               recommended_at = NULL, recommended_by = NULL, recommendation_note = NULL, updated_at = now()
         WHERE application_id = p_app;
    ELSE
        RAISE EXCEPTION 'unknown review step %', p_action USING ERRCODE = '23514';
    END CASE;
    PERFORM admissions.cce_log(p_app, upper(p_action), r.state, v_to, v_note);
    RETURN v_to;
END $fn$;

/* the Academic Office publishes the outcome: an approved admission becomes the ordinary admissions offer (OFFERED, released,
   the candidate ADMITTED); a declined one the ordinary NOT_OFFERED with its reason. Once published it stands. */
CREATE OR REPLACE FUNCTION admissions.cce_publish(p_session text, p_apps uuid[])
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE x record; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; n_adm int := 0; n_not int := 0; n_rej int := 0;
BEGIN
    PERFORM admissions.cce_require_office(ARRAY['academic', 'super'], 'publishing the CCE admission list');
    FOR x IN SELECT r.*, a.application_no, a.candidate_id
               FROM admissions.cce_review r JOIN admissions.application a ON a.id = r.application_id
              WHERE a.session = p_session AND r.published_at IS NULL AND r.state IN ('APPROVED', 'NOT_ADMITTED', 'REJECTED')
                AND (p_apps IS NULL OR r.application_id = ANY (p_apps))
              ORDER BY a.application_no FOR UPDATE OF r LOOP
        IF x.state = 'APPROVED' THEN
            UPDATE admissions.application SET decision = 'OFFERED', decision_basis = 'OTHER', decision_note = x.decision_note, decided_at = x.decided_at,
                   decision_released_at = now() WHERE id = x.application_id;
            UPDATE admissions.candidate SET offer_state = 'ADMITTED' WHERE id = x.candidate_id AND offer_state = 'PROPOSED';
            UPDATE admissions.cce_review SET state = 'ADMITTED', published_at = now(), published_by = v_actor, updated_at = now() WHERE application_id = x.application_id;
            PERFORM admissions.cce_log(x.application_id, 'PUBLISHED', 'APPROVED', 'ADMITTED', NULL);
            n_adm := n_adm + 1;
        ELSE
            UPDATE admissions.application SET decision = 'NOT_OFFERED', decision_basis = NULL, decision_note = x.decision_note, decided_at = x.decided_at,
                   decision_released_at = now() WHERE id = x.application_id;
            UPDATE admissions.cce_review SET published_at = now(), published_by = v_actor, updated_at = now() WHERE application_id = x.application_id;
            PERFORM admissions.cce_log(x.application_id, 'PUBLISHED', x.state, x.state, NULL);
            IF x.state = 'NOT_ADMITTED' THEN n_not := n_not + 1; ELSE n_rej := n_rej + 1; END IF;
        END IF;
        PERFORM admissions.notify_applicant(x.application_id, 'The outcome of your CCE application',
            'The Centre for Continuing Education has published the outcome of applications for the ' || p_session || ' session. '
            || 'Sign in to the applicant portal and open Admission Status to read yours (application ' || x.application_no || ').',
            'MOAUM: the outcome of your CCE application ' || x.application_no || ' is published. Sign in to read it.');
    END LOOP;
    RETURN jsonb_build_object('admitted', n_adm, 'not_admitted', n_not, 'rejected', n_rej);
END $fn$;

-- ── 12 · where each listed person stands, and the counts ────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW admissions.cce_candidate_status AS
    SELECT l.id, l.session, l.jamb_reg_no, l.jamb_key, l.surname, l.first_name, l.middle_name, l.date_of_birth, l.sex, l.phone, l.email,
           l.state_of_origin, l.lga, l.nationality, l.programme_code, p.name AS programme, d.name AS department, f.name AS faculty,
           l.standing, l.standing_reason, l.created_at, l.updated_at, l.first_batch_id, l.last_batch_id,
           c.id AS candidate_id, a.id AS application_id, a.application_no, r.state AS review_state, r.submitted_at, r.published_at,
           a.fee_confirmed_at, a.accepted_at, s.id AS student_id, s.admission_no, s.matric_no,
           CASE WHEN l.standing = 'WITHDRAWN' THEN 'WITHDRAWN'
                WHEN a.id IS NULL THEN CASE WHEN coalesce(t.active, false) THEN 'ELIGIBLE_TO_APPLY' ELSE 'IMPORTED' END
                WHEN r.state = 'DRAFT' THEN 'APPLICATION_STARTED'
                WHEN r.state = 'SUBMITTED' THEN 'APPLICATION_SUBMITTED'
                WHEN r.state IN ('UNDER_REVIEW', 'DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED', 'RECOMMENDED', 'APPROVED') THEN 'UNDER_REVIEW'
                WHEN r.state = 'ADMITTED' THEN 'ADMITTED'
                WHEN r.state = 'NOT_ADMITTED' AND r.published_at IS NOT NULL THEN 'NOT_ADMITTED'
                WHEN r.state = 'REJECTED' AND r.published_at IS NOT NULL THEN 'REJECTED'
                ELSE 'UNDER_REVIEW' END AS status
      FROM admissions.cce_candidate l
      JOIN ref.programme p ON p.code = l.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN LATERAL ref.programme_route_terms(l.programme_code, 'CCE') t ON true
      LEFT JOIN admissions.candidate c ON c.cce_candidate_id = l.id
      LEFT JOIN admissions.application a ON a.candidate_id = c.id
      LEFT JOIN admissions.cce_review r ON r.application_id = a.id
      LEFT JOIN people.student s ON s.candidate_id = c.id;
COMMENT ON VIEW admissions.cce_candidate_status IS
  'V379: each listed CCE person and where they stand — IMPORTED (their programme not admitting), ELIGIBLE_TO_APPLY, APPLICATION_STARTED, APPLICATION_SUBMITTED, UNDER_REVIEW, ADMITTED, NOT_ADMITTED, REJECTED (once published), WITHDRAWN — with the application and, once on the register, the student.';

CREATE OR REPLACE FUNCTION admissions.cce_stats(p_session text)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT * FROM admissions.cce_candidate_status WHERE session = p_session),
         st AS (SELECT x.* FROM people.student x WHERE x.entry_mode = 'CCE' AND x.entry_session = p_session)
    SELECT jsonb_build_object(
        'imported', (SELECT count(*) FROM s),
        'eligible', (SELECT count(*) FROM s WHERE status = 'ELIGIBLE_TO_APPLY'),
        'not_admitting', (SELECT count(*) FROM s WHERE status = 'IMPORTED'),
        'withdrawn', (SELECT count(*) FROM s WHERE status = 'WITHDRAWN'),
        'started', (SELECT count(*) FROM s WHERE application_id IS NOT NULL),
        'submitted', (SELECT count(*) FROM s WHERE submitted_at IS NOT NULL),
        'pending', (SELECT count(*) FROM s WHERE review_state = 'SUBMITTED'),
        'under_review', (SELECT count(*) FROM s WHERE review_state IN ('UNDER_REVIEW', 'RECOMMENDED')),
        'with_applicant', (SELECT count(*) FROM s WHERE review_state IN ('DOCUMENTS_PENDING', 'VERIFICATION_REQUIRED')),
        'approved_unpublished', (SELECT count(*) FROM s WHERE review_state = 'APPROVED'),
        'declined_unpublished', (SELECT count(*) FROM s WHERE review_state IN ('NOT_ADMITTED', 'REJECTED') AND published_at IS NULL),
        'admitted', (SELECT count(*) FROM s WHERE status = 'ADMITTED'),
        'not_admitted', (SELECT count(*) FROM s WHERE status IN ('NOT_ADMITTED', 'REJECTED')),
        'acceptance_paid', (SELECT count(*) FROM s JOIN admissions.application a ON a.id = s.application_id WHERE a.acceptance_confirmed_at IS NOT NULL),
        'accepted', (SELECT count(*) FROM s WHERE accepted_at IS NOT NULL),
        'activated', (SELECT count(*) FROM st),
        'matriculated', (SELECT count(*) FROM st WHERE matric_no IS NOT NULL),
        'current_students', (SELECT count(*) FROM people.student x WHERE x.entry_mode = 'CCE' AND x.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')))
$fn$;


-- ── 13 · the functions CCE changes ──────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION people.intake_one(p_candidate uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE c admissions.candidate; v_id uuid; v_code text; v_yy text; l admissions.cce_candidate;
BEGIN
    SELECT * INTO c FROM admissions.candidate WHERE id = p_candidate;
    IF c.id IS NULL THEN RAISE EXCEPTION 'no such candidate' USING ERRCODE = '23503'; END IF;
    SELECT id INTO v_id FROM people.student WHERE candidate_id = c.id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    IF c.offer_state NOT IN ('ADMITTED', 'ACCEPTED') THEN
        RAISE EXCEPTION 'only an admitted candidate is brought onto the register; % is %', c.jamb_reg_no, lower(coalesce(c.offer_state, 'not admitted')) USING ERRCODE = '23514';
    END IF;
    -- candidate.programme is the programme NAME; resolve it to a code, accepting a value that is already a code
    v_code := (SELECT p.code FROM ref.programme p WHERE p.name = c.programme ORDER BY p.archived, p.code LIMIT 1);
    IF v_code IS NULL THEN
        IF EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = c.programme) THEN
            v_code := c.programme;
        ELSE
            RAISE EXCEPTION 'the programme "%" for candidate % is not one the University runs; it cannot be brought onto the register',
                c.programme, c.jamb_reg_no USING ERRCODE = '23503',
                HINT = 'Set the programme''s University name to match ref.programme, or correct the candidate''s programme.';
        END IF;
    END IF;
    v_yy := substr(c.session, 3, 2);
    -- V379: a CCE candidate comes onto the register CCE and part-time, in the CCE session admitted for, with what the list gave
    SELECT * INTO l FROM admissions.cce_candidate WHERE id = c.cce_candidate_id;
    INSERT INTO people.student (id, candidate_id, admission_no, jamb_reg_no, surname, other_names,
                                programme_code, entry_mode, entry_session, entry_level, current_level, study_mode, date_of_birth, sex, state_of_origin)
    VALUES (gen_random_uuid(), c.id,
            'MOAUM/ADM/' || v_yy || '/' || lpad(platform.next_number('ADMISSION', 'UNIVERSITY', c.session)::text, 6, '0'),
            c.jamb_reg_no, c.surname, c.other_names, v_code,
            CASE WHEN c.entry_mode IN ('UTME', 'DIRECT_ENTRY', 'CCE') THEN c.entry_mode ELSE 'UTME' END,
            c.session, c.entry_level, c.entry_level,
            CASE WHEN c.entry_mode = 'CCE' THEN coalesce((SELECT r.study_mode FROM policy.study_route r WHERE r.code = 'CCE'), 'PART_TIME') ELSE 'FULL_TIME' END,
            l.date_of_birth, l.sex, l.state_of_origin)
    RETURNING id INTO v_id;
    IF c.entry_mode = 'CCE' THEN
        INSERT INTO people.biodata (student_id, field, value)
        SELECT v_id, x.field, x.value FROM admissions.screening_answer x JOIN admissions.application a ON a.id = x.application_id
         WHERE a.candidate_id = c.id AND btrim(x.value) <> ''
        ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value;
    END IF;
    -- the nationality JAMB's state implies, on the record from the first day (V282)
    PERFORM people.default_nationality(v_id);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION admissions.status_checking(p_app uuid)
 RETURNS TABLE(application_id uuid, session text, application_valid boolean, window_state text, window_open boolean, opens_at timestamp with time zone, closes_at timestamp with time zone, fee numeric, fee_required boolean, paid boolean, paid_at timestamp with time zone, paid_reference text, open_reference text, open_reference_expires timestamp with time zone, past boolean, may_pay boolean, may_check boolean, decision_visible boolean, reason text, checks bigint, last_checked_at timestamp with time zone, last_result text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH a AS (SELECT * FROM admissions.application WHERE id = p_app),
    -- V379: a CCE applicant reads the Centre's published outcome with no window and no checking fee
    cce AS (SELECT EXISTS (SELECT 1 FROM a JOIN admissions.candidate c ON c.id = a.candidate_id WHERE c.entry_mode = 'CCE') AS yes),
    w AS (SELECT CASE WHEN cce.yes THEN 'OPEN' ELSE ws.state END AS state, CASE WHEN cce.yes THEN NULL ELSE ws.opens_at END AS opens_at,
                 CASE WHEN cce.yes THEN NULL ELSE ws.closes_at END AS closes_at
            FROM a CROSS JOIN cce CROSS JOIN LATERAL policy.window_state('ADMISSION_STATUS_CHECKING', a.session, NULL) ws),
    f AS (SELECT CASE WHEN (SELECT yes FROM cce) THEN 0
                      ELSE coalesce((SELECT r.checking_fee FROM a CROSS JOIN LATERAL admissions.applicant_fee_rule(a.session) r), 0) END::numeric AS fee),
    pay AS (SELECT min(r.confirmed_at) FILTER (WHERE r.kind = 'CHECKING') AS ck_at,
                   (array_agg(r.reference ORDER BY r.confirmed_at) FILTER (WHERE r.kind = 'CHECKING'))[1] AS ck_ref,
                   coalesce(bool_or(r.kind = 'ACCEPTANCE'), false) AS acc
              FROM admissions.fee_reference r WHERE r.application_id = p_app AND r.confirmed_at IS NOT NULL),
    o AS (SELECT r.reference, r.expires_at FROM admissions.fee_reference r
           WHERE r.application_id = p_app AND r.kind = 'CHECKING' AND r.confirmed_at IS NULL AND r.expires_at > now()
           ORDER BY r.generated_at DESC LIMIT 1),
    k AS (SELECT count(*) AS n, max(c.checked_at) AS last_at, (array_agg(c.result ORDER BY c.checked_at DESC))[1] AS last_result
            FROM admissions.status_check c WHERE c.application_id = p_app),
    x AS (
        SELECT a.id, a.session,
               (a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL) AS valid,
               w.state AS wstate, w.state = 'OPEN' AS wopen, w.opens_at, w.closes_at,
               f.fee, f.fee > 0 AS required,
               -- an acceptance confirmed under the old rule (V148) included the checking fee: it counts as paid
               (a.checking_confirmed_at IS NOT NULL OR pay.ck_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL OR pay.acc) AS paid,
               coalesce(a.checking_confirmed_at, pay.ck_at) AS paid_at, pay.ck_ref,
               -- the offer has been read and the admission is under way: the workflow continues whatever the window
               (a.decision_released_at IS NOT NULL AND a.decision = 'OFFERED'
                AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL
                     OR a.accepted_at IS NOT NULL OR a.declined_at IS NOT NULL OR pay.acc)) AS past
          FROM a, w, f, pay)
    SELECT x.id, x.session, x.valid, x.wstate, x.wopen, x.opens_at, x.closes_at, x.fee, x.required,
           x.paid, x.paid_at, x.ck_ref, (SELECT o.reference FROM o), (SELECT o.expires_at FROM o),
           x.past,
           x.valid AND x.wopen AND x.required AND NOT x.paid,
           x.valid AND x.wopen AND (x.paid OR NOT x.required),
           x.past OR (x.valid AND x.wopen AND (x.paid OR NOT x.required)),
           CASE WHEN x.past THEN NULL WHEN NOT x.valid THEN 'APPLICATION_INCOMPLETE' WHEN NOT x.wopen THEN 'CHECKING_CLOSED'
                WHEN x.required AND NOT x.paid THEN 'CHECKING_FEE_UNPAID' END,
           k.n, k.last_at, k.last_result
      FROM x, k
$function$;

CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric; c record; v_cce boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    IF v_cce AND p_kind = 'CHECKING' THEN
        RAISE EXCEPTION 'CCE_NO_CHECKING_FEE: a CCE applicant reads the published outcome without a checking fee' USING ERRCODE = '23514';
    END IF;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    IF p_kind = 'CHECKING' THEN
        -- V295: the checking fee is open to every applicant with a valid Post-UTME application while the Director of ICT has
        -- admission status checking open — admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already confirmed; it is paid once, and nothing more is owed to check your admission status' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_CLOSED: admission status checking is closed; the admission checking fee is paid while the University has it open' USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: an offer is paid for, accepted or declined only after you have checked your admission status and read it' USING ERRCODE = '23514';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        IF a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    IF v_cce THEN
        -- V379: the CCE fees, as the Bursary stated them for the session (or last stated); never the Post-UTME figures
        SELECT r.application_fee, r.portal_charge, r.acceptance_fee, 0::numeric AS checking_fee INTO fee FROM admissions.route_fee_rule(a.session, 'CCE') r;
        v_amount := CASE p_kind WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge ELSE fee.acceptance_fee END;
        IF v_amount IS NULL THEN
            RAISE EXCEPTION 'CCE_FEE_NOT_STATED: the Bursary has not stated the CCE % fee for %', lower(p_kind), a.session USING ERRCODE = '23514';
        END IF;
    ELSE
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    END IF;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
             || lpad((floor(random() * 10000))::int::text, 4, '0');
    INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
    VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours');
    RETURN v_ref;
END $function$;

CREATE OR REPLACE FUNCTION admissions.confirm_fee(p_reference text, p_channel text, p_note text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE r admissions.fee_reference; a admissions.application; v_no text; v_purpose text; v_action text; v_sms_action text;
BEGIN
    SELECT * INTO r FROM admissions.fee_reference WHERE reference = upper(btrim(p_reference));
    IF NOT FOUND THEN RAISE EXCEPTION 'no reference % was generated by this portal', p_reference USING ERRCODE = '23503',
        HINT = 'Only a reference this portal generated is confirmed; money sent anywhere else did not reach the University.'; END IF;
    IF r.confirmed_at IS NOT NULL THEN RETURN 'already confirmed'; END IF;
    IF admissions.acting_person() IS NULL THEN
        RAISE EXCEPTION 'a payment is confirmed by a person' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM admissions.application WHERE id = r.application_id;

    v_no := 'RCT-' || left(a.session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', a.session)::text, 5, '0');
    UPDATE admissions.fee_reference SET confirmed_at = now(), confirmed_by = admissions.acting_person(),
           channel = p_channel, note = p_note, receipt_no = v_no WHERE id = r.id;

    IF r.kind = 'APPLICATION' THEN
        UPDATE admissions.application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = a.id;
        v_purpose := CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN 'CCE application' ELSE 'Application & Post-UTME' END;
        v_action := 'Your application form is now open: sign in and complete it.';
        v_sms_action := 'Your application form is open.';
    ELSIF r.kind = 'CHECKING' THEN
        -- V295: the fee grants the checking service; the status is read, and recorded, when the applicant checks it
        UPDATE admissions.application SET checking_confirmed_at = coalesce(checking_confirmed_at, now()) WHERE id = a.id;
        v_purpose := 'Admission checking';
        v_action := 'Your Admission Checking Fee payment has been verified. You can now check your admission status: sign in and open Admission Status.';
        v_sms_action := 'Admission checking fee verified. You can now check your admission status.';
    ELSE
        UPDATE admissions.application SET acceptance_confirmed_at = coalesce(acceptance_confirmed_at, now()) WHERE id = a.id;
        v_purpose := CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN 'CCE acceptance' ELSE 'Acceptance' END;
        v_action := 'Your acceptance of the offer is settled. Sign in to continue to clearance.';
        v_sms_action := 'Acceptance settled.';
        PERFORM admissions.settle_acceptance(a.id);
    END IF;

    PERFORM admissions.notify_applicant(a.id, 'Your payment receipt · ' || v_no,
        'This is your official receipt from Rev. Fr. Moses Orshio Adasu University, Makurdi.' || chr(10) || chr(10)
        || 'Receipt no:  ' || v_no || chr(10)
        || 'Reference:   ' || r.reference || chr(10)
        || 'Purpose:     ' || v_purpose || ' fee' || chr(10)
        || 'Session:     ' || a.session || chr(10)
        || 'Amount:      NGN ' || to_char(r.amount, 'FM999,999,990.00') || chr(10)
        || 'Confirmed:   ' || to_char(now(), 'FMDD FMMonth YYYY') || chr(10)
        || 'Channel:     ' || coalesce(p_channel, 'Bank') || chr(10) || chr(10)
        || v_action || chr(10) || chr(10)
        || 'Keep this receipt. It is verified against the University''s record by its receipt number, not by its appearance.',
        'MOAUM receipt ' || v_no || ': NGN ' || to_char(r.amount, 'FM999,999,990.00') || ' for ' || v_purpose || ' confirmed. ' || v_sms_action);

    RETURN 'confirmed';
END $function$;

CREATE OR REPLACE FUNCTION admissions.issue_admission_letter(p_app uuid)
 RETURNS credentials.issued
 LANGUAGE plpgsql
AS $function$
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
    -- V379: a CCE admission names the route, the study mode, the Centre and the programme's duration on the route
    IF c.entry_mode = 'CCE' THEN
        v_stmt := v_stmt || jsonb_build_object('admissionRoute', 'CCE', 'studyMode', 'PART-TIME', 'centre', 'Centre for Continuing Education',
                    'admissionType', 'CCE · Part-time · ' || c.entry_level || ' Level',
                    'durationYears', (SELECT t.duration_years FROM ref.programme_route_terms(v_prog.code, 'CCE') t),
                    'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi, for the Centre for Continuing Education');
    END IF;
    v_hash := encode(sha256(convert_to(v_stmt::text, 'UTF8')), 'hex');
    INSERT INTO credentials.issued (id, kind, student_id, application_id, verification_code, statement, signature, signed_with, issuing_name, issued_on, issued_by, issued_office, supersedes, number, version, template_version, content_hash, note)
    VALUES (v_id, 'ADMISSION_LETTER', v_student.id, p_app, credentials.new_code(), v_stmt, decode(v_hash, 'hex'), NULL, 'Rev. Fr. Moses Orshio Adasu University, Makurdi', current_date, v_actor, v_office, cur.id,
            v_number, v_version, NULL, v_hash, CASE WHEN cur.id IS NULL THEN 'Letter of provisional admission' ELSE 'Reissued: the programme changed to ' || c.programme END);
    PERFORM credentials.log(NULL, v_id, v_student.id, 'ISSUED', NULL, 'ACTIVE', 'ADMISSION_LETTER ' || v_number || ' v' || v_version || ' · ' || c.programme);
    SELECT * INTO cur FROM credentials.issued WHERE id = v_id;
    RETURN cur;
END $function$;

CREATE OR REPLACE FUNCTION people.academic_context(p_student uuid)
 RETURNS TABLE(session text, context text, session_state text, current_session text, transitions_on date)
 LANGUAGE sql
 STABLE
AS $function$
    WITH st AS (SELECT s.entry_session, s.entry_mode FROM people.student s WHERE s.id = p_student),
         cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'),
         run AS (SELECT name FROM policy.academic_session WHERE state IN ('CURRENT', 'CLOSED', 'ARCHIVED') ORDER BY name DESC LIMIT 1),
         -- V379: a CCE student stands in the CCE session (the route's), never the undergraduate one
         base AS (SELECT CASE WHEN (SELECT entry_mode FROM st) = 'CCE' THEN policy.route_session('CCE')
                              ELSE coalesce((SELECT name FROM cur), (SELECT name FROM run)) END AS name),
         stands AS (SELECT CASE WHEN st.entry_session IS NOT NULL AND (base.name IS NULL OR st.entry_session > base.name) THEN st.entry_session ELSE base.name END AS name
                      FROM st CROSS JOIN base)
    SELECT stands.name,
           CASE WHEN a.state IN ('PLANNED', 'DRAFT') AND stands.name = st.entry_session THEN 'PREPARING'
                WHEN stands.name IS NULL THEN 'NONE' ELSE 'CURRENT' END,
           a.state, CASE WHEN st.entry_mode = 'CCE' THEN policy.route_session('CCE') ELSE (SELECT name FROM cur) END, a.transitions_on
      FROM stands CROSS JOIN st LEFT JOIN policy.academic_session a ON a.name = stands.name
$function$;

CREATE OR REPLACE FUNCTION policy.application_session(p_type text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN p_type = 'POSTGRADUATE_APPLICATION' THEN admissions.pg_current_session()
                WHEN p_type = 'CCE_APPLICATION' THEN policy.route_session('CCE')
                WHEN p_type LIKE 'JUPEB%'
                    THEN coalesce((SELECT current_session FROM jupeb.setting WHERE session = '*'), policy.university_current_session())
                ELSE policy.intake_session() END
$function$;

CREATE OR REPLACE FUNCTION policy.window_state(p_type text, p_session text, p_semester integer)
 RETURNS TABLE(configured boolean, state text, phase text, opens_at timestamp with time zone, closes_at timestamp with time zone, late_until timestamp with time zone, late_fee_enabled boolean, forced text, reason text, window_id uuid, semester integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS (
        SELECT * FROM policy.portal_window
         WHERE window_type = p_type AND session = p_session AND superseded_at IS NULL
           AND (semester = p_semester OR semester IS NULL)
         ORDER BY (semester IS NOT NULL) DESC LIMIT 1)
    SELECT w.id IS NOT NULL,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION') THEN 'CLOSED' ELSE 'OPEN' END
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION') THEN 'NONE' ELSE 'NORMAL' END
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$function$;

CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text, p_opens timestamp with time zone, p_closes timestamp with time zone, p_late_until timestamp with time zone, p_late_fee boolean, p_reason text, p_actor uuid, p_office text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                      'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_ADMISSION_STATUS_CHECKING') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: admission status checking opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_APPLICATION_SESSION: an application window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF p_action NOT IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT') THEN RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514'; END IF;
    IF p_action IN ('CLOSE', 'REOPEN', 'SHORTEN') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'the reason for % is recorded, and none was given', lower(p_action) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.portal_window WHERE window_type = p_type AND session = p_session AND coalesce(semester, 0) = coalesce(p_semester, 0) AND superseded_at IS NULL FOR UPDATE;
    SELECT * INTO prev FROM policy.window_state(p_type, p_session, p_semester);
    v_opens := coalesce(p_opens, cur.opens_at); v_closes := coalesce(p_closes, cur.closes_at); v_late := coalesce(p_late_until, cur.late_until);
    v_fee := coalesce(p_late_fee, cur.late_fee_enabled, false);
    CASE p_action
        WHEN 'OPEN', 'REOPEN' THEN v_forced := CASE WHEN p_opens IS NULL AND p_closes IS NULL THEN 'OPEN' ELSE NULL END;
                                   IF p_opens IS NULL AND p_closes IS NOT NULL THEN v_opens := now(); END IF;
        WHEN 'CLOSE' THEN v_forced := 'CLOSED';
        WHEN 'SCHEDULE' THEN IF p_opens IS NULL THEN RAISE EXCEPTION 'a schedule names when the window opens' USING ERRCODE = '23514'; END IF; v_forced := NULL;
        WHEN 'EXTEND' THEN IF p_closes IS NULL AND p_late_until IS NULL THEN RAISE EXCEPTION 'an extension names the new closing' USING ERRCODE = '23514'; END IF;
                           IF cur.id IS NOT NULL AND p_closes IS NOT NULL AND cur.closes_at IS NOT NULL AND p_closes < cur.closes_at THEN RAISE EXCEPTION 'that closing is earlier than before; shorten the window instead' USING ERRCODE = '23514'; END IF;
                           v_forced := CASE WHEN cur.forced = 'CLOSED' THEN NULL ELSE cur.forced END;
        WHEN 'SHORTEN' THEN IF p_closes IS NULL THEN RAISE EXCEPTION 'a shortening names the new closing' USING ERRCODE = '23514'; END IF; v_forced := cur.forced;
        WHEN 'EDIT' THEN v_forced := cur.forced;
    END CASE;
    IF v_closes IS NOT NULL AND v_opens IS NOT NULL AND v_closes < v_opens THEN RAISE EXCEPTION 'the window closes before it opens' USING ERRCODE = '23514'; END IF;
    IF v_late IS NOT NULL AND v_closes IS NOT NULL AND v_late < v_closes THEN RAISE EXCEPTION 'the late period ends before the window closes' USING ERRCODE = '23514'; END IF;
    IF cur.id IS NOT NULL THEN UPDATE policy.portal_window SET superseded_at = now() WHERE id = cur.id; END IF;
    INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, late_until, late_fee_enabled, forced, reason, created_by, created_office)
    VALUES (p_type, p_session, p_semester, v_opens, v_closes, v_late, v_fee, v_forced, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office)
    RETURNING id INTO v_id;
    SELECT * INTO nxt FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, previous_state, new_state, previous_opens_at, previous_closes_at, previous_late_until,
                                            new_opens_at, new_closes_at, new_late_until, late_fee_enabled, reason, actor, office)
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state ELSE prev.state || ' (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $function$;

ALTER TABLE policy.portal_window DROP CONSTRAINT portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check
    CHECK (window_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                           'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING', 'CCE_APPLICATION'));
ALTER TABLE policy.portal_window DROP CONSTRAINT ck_window_application_session;
ALTER TABLE policy.portal_window ADD CONSTRAINT ck_window_application_session
    CHECK (window_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION')
           OR (semester IS NULL AND late_until IS NULL AND NOT late_fee_enabled));

ALTER TABLE policy.portal_window_message DROP CONSTRAINT IF EXISTS portal_window_message_window_type_check;
ALTER TABLE policy.portal_window_message ADD CONSTRAINT portal_window_message_window_type_check
    CHECK (window_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION'));
INSERT INTO policy.portal_window_message (window_type, message) VALUES
  ('CCE_APPLICATION',
   E'THE CCE APPLICATION IS CURRENTLY CLOSED

Thank you for your interest in the University''s Centre for Continuing Education.

Only candidates whose names JAMB has sent to the University on the CCE list may apply. The application is not open at the moment. Please check the University''s official website and this portal for the next application window.')
ON CONFLICT (window_type) DO NOTHING;

CREATE OR REPLACE FUNCTION policy.window_message_set(p_type text, p_message text, p_actor uuid, p_office text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_old text; v_new text;
BEGIN
    IF p_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION') THEN RAISE EXCEPTION 'no closure message for %', p_type USING ERRCODE = '23514'; END IF;
    v_new := btrim(regexp_replace(regexp_replace(coalesce(p_message, ''), '<[^>]*>', '', 'g'), '[\u0001-\u0008\u000B-\u001F\u007F]', '', 'g'));
    IF length(v_new) = 0 THEN RAISE EXCEPTION 'the closure message cannot be blank' USING ERRCODE = '23514'; END IF;
    IF length(v_new) > 2000 THEN RAISE EXCEPTION 'the closure message is at most 2000 characters' USING ERRCODE = '23514'; END IF;
    SELECT message INTO v_old FROM policy.portal_window_message WHERE window_type = p_type;
    INSERT INTO policy.portal_window_message (window_type, message, updated_by, updated_office, updated_at)
    VALUES (p_type, v_new, p_actor, p_office, now())
    ON CONFLICT (window_type) DO UPDATE SET message = EXCLUDED.message, updated_by = EXCLUDED.updated_by, updated_office = EXCLUDED.updated_office, updated_at = now();
    INSERT INTO policy.portal_window_event (window_type, session, action, previous_state, new_state, reason, actor, office)
    SELECT p_type, coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1), (SELECT max(name) FROM policy.academic_session)),
           'MESSAGE', left(v_old, 120), left(v_new, 120), 'closure message updated', p_actor, p_office
     WHERE EXISTS (SELECT 1 FROM policy.academic_session);
END $function$;

CREATE OR REPLACE FUNCTION registration.registration_gate(p_student uuid, p_session text, p_semester integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    WITH sm AS (SELECT * FROM policy.semester WHERE session = p_session AND number = p_semester),
         st AS (SELECT * FROM people.student WHERE id = p_student),
         w AS (SELECT CASE p_semester WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'third' END AS ord)
    SELECT CASE
             -- V379: CCE courses are offered in the CCE session on offerings of their own (docs/cce.md, phase 2); until then none is shown
             WHEN st.entry_mode = 'CCE' THEN 'Course registration for students of the Centre for Continuing Education opens when the Centre''s courses for ' || p_session || ' are set up.'
             WHEN pw.configured AND pw.state = 'CLOSED' THEN 'Course registration is currently closed for ' || p_session || ' ' || w.ord || ' semester.' || coalesce(' ' || pw.reason, '')
             WHEN pw.configured AND pw.state = 'SCHEDULED' THEN 'Course registration for ' || p_session || ' ' || w.ord || ' semester opens on ' || to_char(pw.opens_at AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'EXPIRED' THEN 'Course registration for ' || p_session || ' ' || w.ord || ' semester closed on ' || to_char(coalesce(pw.late_until, pw.closes_at) AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.'
             WHEN pw.configured AND pw.state = 'OPEN' THEN NULL
             WHEN NOT EXISTS (SELECT 1 FROM sm) THEN NULL
             WHEN sm.state = 'OPEN' THEN NULL
             WHEN sm.state IN ('CLOSED', 'ARCHIVED') THEN 'The ' || w.ord || ' semester of ' || p_session || ' is closed for registration.'
             WHEN sm.fresh_registration_from IS NOT NULL AND sm.fresh_registration_from <= current_date AND st.entry_session = p_session THEN NULL
             WHEN sm.fresh_registration_from IS NOT NULL AND st.entry_session = p_session
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' opens to fresh students on ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             WHEN sm.fresh_registration_from IS NOT NULL
                  THEN 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open; only the session''s fresh students register from ' || to_char(sm.fresh_registration_from, 'DD Month YYYY') || '.'
             ELSE 'The ' || w.ord || ' semester of ' || p_session || ' is not yet open for registration.'
           END
      FROM w LEFT JOIN sm ON true LEFT JOIN st ON true LEFT JOIN LATERAL (SELECT * FROM policy.window_state('COURSE_REGISTRATION', p_session, p_semester)) pw ON true
$function$;

CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
 RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean; c record;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;
    -- V295: the status is read through Admission Status Checking — a valid Post-UTME application (paid for and submitted), checking
    -- open (the Director of ICT's window) and the checking fee paid; never through the decision, which is what the check reveals.
    -- An applicant who has read an offer and whose admission is under way continues whatever the window.
    SELECT * INTO c FROM admissions.status_checking(p_app);
    IF NOT c.decision_visible THEN
        IF NOT c.application_valid THEN
            RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
                CASE WHEN a.fee_confirmed_at IS NULL THEN 'Pay the application fee' ELSE 'Complete and submit your application' END,
                CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN '/applicant/cce'
                     WHEN a.fee_confirmed_at IS NULL THEN '/applicant/fee' ELSE '/applicant/apply' END,
                CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE')
                     THEN 'The Centre for Continuing Education reviews your application once it is complete and submitted.'
                     ELSE 'Admission status checking is open to every applicant whose Post-UTME application is paid for and submitted.' END; RETURN;
        END IF;
        IF NOT c.window_open THEN
            RETURN QUERY SELECT 'CHECKING_CLOSED', 'Admission status checking closed', NULL::text, '/applicant/admission',
                CASE WHEN c.window_state = 'SCHEDULED' AND c.opens_at IS NOT NULL
                     THEN 'Admission status checking opens on ' || to_char(c.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY "at" HH24:MI') || '.'
                     ELSE 'Admission status checking is currently unavailable. Please check back when the University opens the admission checking portal.' END; RETURN;
        END IF;
        RETURN QUERY SELECT 'CHECKING_FEE_PENDING', 'Admission checking fee not paid', 'Pay the admission checking fee', '/applicant/admission',
            'Admission status checking is open. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then check your admission status as often as you need while checking is open.'; RETURN;
    END IF;
    IF a.decision_released_at IS NULL OR a.decision IS NULL THEN
        RETURN QUERY SELECT 'PENDING', 'Admission pending', NULL::text, '/applicant/admission',
            'Your admission has not yet been finalised. Please check again when further admission processing has been completed; the checking fee is not charged again.'; RETURN;
    END IF;
    IF a.decision <> 'OFFERED' THEN
        RETURN QUERY SELECT 'NOT_ADMITTED', CASE WHEN a.decision = 'WAITING' THEN 'Waiting list' ELSE 'Not admitted' END, NULL::text, '/applicant/admission',
            coalesce(a.decision_note, CASE WHEN a.decision = 'WAITING'
                THEN 'You are above the cut-off, but the approved quota is full. You are offered a place only if an offered candidate fails to accept in time.'
                ELSE 'Your admission status for the ' || a.session || ' admission exercise is: not admitted. You may continue to monitor the University''s official admission updates.' END); RETURN;
    END IF;
    IF a.declined_at IS NOT NULL THEN RETURN QUERY SELECT 'DECLINED', 'Offer declined', NULL, '/applicant/status', 'A declined offer is not reinstated.'; RETURN; END IF;
    -- V358: an offer not accepted by its deadline, lapsed by the Admissions Office
    IF a.lapsed_at IS NOT NULL THEN
        RETURN QUERY SELECT 'LAPSED', 'Offer lapsed', NULL::text, '/applicant/admission',
            'Your offer was not accepted by ' || coalesce(to_char(admissions.offer_deadline_of(p_app), 'FMDD Month YYYY'), 'its deadline')
            || ' and has lapsed. A lapsed offer is not reinstated; write to the Admissions Office quoting your application number if you believe this is in error.'; RETURN;
    END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    -- the applicant reads the admission status — the offer, its programme, faculty and session — before anything is accepted (V271)
    IF a.accepted_at IS NULL AND a.status_checked_at IS NULL AND NOT ent.paid AND a.undertaking_at IS NULL THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — check your admission status', 'Check your admission status', '/applicant/admission', 'Congratulations: read the offer and its details, then accept it and pay the acceptance fee.'; RETURN;
    END IF;
    IF a.accepted_at IS NULL THEN
        IF ent.paid OR a.undertaking_at IS NOT NULL THEN RETURN QUERY SELECT 'ACCEPTANCE_PENDING', 'Acceptance in progress', CASE WHEN ent.paid THEN 'Sign the undertaking' ELSE 'Pay the acceptance fee' END, '/applicant/accept', 'The undertaking and the acceptance fee together accept the offer.'; RETURN; END IF;
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — offer to accept', 'Pay the acceptance fee', '/applicant/accept', 'Accept the offer and pay the acceptance fee; the acceptance letter follows.' || coalesce(' Accept it by ' || to_char(admissions.offer_deadline_of(p_app), 'FMDD Month YYYY') || '; an offer neither accepted nor paid for by then lapses.', ''); RETURN;
    END IF;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app ORDER BY x.requested_at DESC LIMIT 1;
    IF req AND NOT admissions.screening_ok(p_app) THEN
        -- the University screens on the record it holds (V280): the applicant waits (entering only the schools attended), or provides the one correction asked for
        -- V284: a change the Academic Office recommended during the screening awaits approval
        IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND f.application_id IS NOT NULL AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Programme change under review', 'Wait for the Academic Office', '/applicant/admission',
                'During the screening the Academic Office recommended ' || q.to_programme || ' in place of ' || q.from_programme || '; the change takes effect when it is approved, and you will be told. Your acceptance fee is not paid again.';
            RETURN;
        END IF;
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

CREATE OR REPLACE FUNCTION admissions.screening_required(p_app uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce((SELECT sp.enabled AND (a.accepted_at IS NULL OR a.accepted_at >= sp.enabled_from)
                       FROM admissions.application a JOIN admissions.screening_policy sp ON sp.session = a.session
                       JOIN admissions.candidate c ON c.id = a.candidate_id AND c.entry_mode <> 'CCE' WHERE a.id = p_app), false);
$function$;

CREATE OR REPLACE FUNCTION finance.charges_of_as(p_student uuid, p_session text, p_kinds text[], p_programme text)
 RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, coalesce(p_programme, s.programme_code) AS programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(coalesce(p_programme, s.programme_code)) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT f.id,
           replace(replace(replace(f.item,
               '(semester 1)', '(First Semester)'),
               '(semester 2)', '(Second Semester)'),
               '(semester 3)', '(Third Semester)') AS item,
           f.amount, f.ord
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.kind = ANY (p_kinds)
       AND f.spillover = me.is_spill
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester <= coalesce((SELECT max(sm.number) FROM policy.semester sm
                                        WHERE sm.session = p_session AND sm.state = 'OPEN'), 3))
     ORDER BY f.ord, f.item;
$function$;

CREATE OR REPLACE FUNCTION finance.session_fee_total(p_student uuid, p_session text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT coalesce(sum(f.amount), 0)
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND (f.level IS NULL OR f.level = me.current_level)
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)));
$function$;

CREATE OR REPLACE FUNCTION finance.due_for_semester(p_student uuid, p_session text, p_semester integer)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT coalesce(sum(f.amount), 0)
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.spillover = me.is_spill
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL OR f.semester <= p_semester);
$function$;

CREATE OR REPLACE FUNCTION finance.fee_stated(p_student uuid, p_session text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS (
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT (p_session < coalesce(finance.schedule_from(), p_session) AND (SELECT me.entry_mode FROM me) IS DISTINCT FROM 'CCE')
        OR EXISTS (
        SELECT 1
          FROM finance.fee_schedule f
          CROSS JOIN me
          JOIN ref.programme p ON p.code = me.programme_code
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
          LEFT JOIN home ON true
         WHERE f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
           AND f.spillover = me.is_spill
           AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
           AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
           AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
           AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state))))
$function$;

CREATE OR REPLACE FUNCTION finance.fee_sums(p_session text, p_semester integer)
 RETURNS TABLE(profile_key text, due_before numeric, due_upto numeric, fee numeric, late_payment numeric, late_registration numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_max AS (SELECT coalesce((SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 3) AS n),
    prof AS (SELECT DISTINCT pr.profile_key, pr.programme_code, pr.faculty_code, pr.category, pr.current_level, pr.entry_mode, pr.state, pr.is_spill
               FROM finance.fee_profiles() pr),
    matched AS (
        SELECT pr.profile_key, f.kind, f.semester, f.amount
          FROM prof pr
          CROSS JOIN home
          JOIN finance.fee_schedule f ON f.session = p_session AND f.ended_at IS NULL
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (pr.is_spill OR f.level IS NULL OR f.level = pr.current_level)
           AND ((f.entry_mode IS NULL AND pr.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = pr.entry_mode)   -- V379
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code)
           AND (f.programme_code IS NULL OR f.programme_code = pr.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = pr.category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (pr.state = home.home_state)))
    SELECT m.profile_key,
           CASE WHEN p_semester IS NULL OR p_semester <= 1 THEN 0
                ELSE coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= p_semester - 1), 0) END,
           CASE WHEN p_semester IS NULL THEN coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= 3), 0)
                ELSE coalesce(sum(m.amount) FILTER (WHERE m.semester IS NULL OR m.semester <= p_semester), 0) END,
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'FEE' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0),
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'LATE_PAYMENT' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0),
           coalesce(sum(m.amount) FILTER (WHERE m.kind = 'LATE_REGISTRATION' AND (m.semester IS NULL OR m.semester <= (SELECT n FROM open_max))), 0)
      FROM matched m
     GROUP BY m.profile_key
$function$;

CREATE OR REPLACE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb)
 RETURNS TABLE(rows integer, lines integer, faculties integer, no_faculty integer, no_programme integer, no_group integer, spillover integer, programmes integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_fac text; v_fac_code text; v_level int; v_mode text; v_sem int; v_ind text; v_amt numeric; v_item text; v_ord int;
        v_spill boolean; v_prog text; v_prog_code text; v_grp text; v_grp_code text; v_kind text;
        n int := 0; nl int := 0; nnf int := 0; nnp int := 0; nng int := 0; nsp int := 0; facs text[] := '{}'; progs text[] := '{}';
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a fees structure is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: faculty or programme, level, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    -- replace the session's approved structure: end what stands, then load the new
    UPDATE finance.fee_schedule SET ended_at = now() WHERE session = p_session AND ended_at IS NULL;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
        n := n + 1;

        -- the faculty, by code or name
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', ''));
        v_fac_code := NULL;
        IF v_fac <> '' THEN
            SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(code) = upper(v_fac);
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) = upper(v_fac) LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) LIKE '%' || upper(v_fac) || '%' LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN nnf := nnf + 1; END IF;
        END IF;

        -- the programme, by code or name: the line is that programme's alone
        v_prog := btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', r->>'program', ''));
        v_prog_code := NULL;
        IF v_prog <> '' THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
            IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived LIMIT 1; END IF;
            IF v_prog_code IS NULL THEN nnp := nnp + 1; END IF;
            -- a programme names its faculty; the faculty column is not needed beside it
            IF v_prog_code IS NOT NULL AND v_fac_code IS NULL THEN SELECT faculty_code INTO v_fac_code FROM ref.programme WHERE code = v_prog_code; END IF;
        END IF;

        -- the fee group, by code or name
        v_grp := btrim(coalesce(r->>'feeGroup', r->>'fee_group', r->>'group', ''));
        v_grp_code := NULL;
        IF v_grp <> '' THEN
            SELECT code INTO v_grp_code FROM ref.fee_group WHERE upper(code) = upper(v_grp);
            IF v_grp_code IS NULL THEN SELECT code INTO v_grp_code FROM ref.fee_group WHERE upper(name) = upper(v_grp) LIMIT 1; END IF;
            IF v_grp_code IS NULL THEN nng := nng + 1; END IF;
        END IF;

        v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_level IS NOT NULL AND v_level NOT IN (100,200,300,400,500,600,700,800,900) THEN v_level := NULL; END IF;
        v_mode := nullif(upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', ''))), '');
        IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH','CCE') THEN v_mode := NULL; END IF;
        v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1,2,3) THEN v_sem := NULL; END IF;
        v_ind := upper(btrim(coalesce(r->>'indigene', '')));
        v_ind := CASE WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' ELSE NULL END;
        v_spill := lower(btrim(coalesce(r->>'spillover', 'false'))) IN ('true', 't', '1', 'yes', 'y', 'spillover', 'spill');
        IF v_spill THEN v_level := NULL; nsp := nsp + 1; END IF;   -- a spillover line is level-agnostic (V088)
        v_kind := upper(regexp_replace(btrim(coalesce(r->>'kind', r->>'type', '')), '[^A-Za-z]', '', 'g'));
        v_kind := CASE WHEN v_kind LIKE 'LATEPAY%' THEN 'LATE_PAYMENT' WHEN v_kind LIKE 'LATEREG%' THEN 'LATE_REGISTRATION' ELSE 'FEE' END;
        v_item := nullif(btrim(coalesce(r->>'item', '')), '');
        IF v_item IS NULL THEN
            v_item := CASE v_kind WHEN 'LATE_PAYMENT' THEN 'Late payment fee' WHEN 'LATE_REGISTRATION' THEN 'Late registration fee'
                                  ELSE CASE WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END END
                      || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END;
        END IF;
        v_ord := coalesce(nullif(regexp_replace(coalesce(r->>'ord', r->>'order', ''), '[^0-9]', '', 'g'), '')::int,
                          coalesce(v_sem, 1) + CASE WHEN v_spill THEN 100 ELSE 0 END);

        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, indigene, ord, spillover, kind)
        VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac_code, v_prog_code, v_grp_code, v_sem, v_ind, v_ord, v_spill, v_kind);
        nl := nl + 1;
        IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY(facs)) THEN facs := facs || v_fac_code; END IF;
        IF v_prog_code IS NOT NULL AND NOT (v_prog_code = ANY(progs)) THEN progs := progs || v_prog_code; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nl, cardinality(facs), nnf, nnp, nng, nsp, cardinality(progs);
END $function$;


COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V423 — the student biodata completion gate
--
--   One switch, the ICT Director's: while it is ON, a student whose required biodata is incomplete reaches only the
--   biodata page (and what it needs) until it is complete; while it is OFF — the default, for testing and migration —
--   the portal works as before. Nobody is chosen or blocked by hand: the rule is read afresh for each student from the
--   record itself, the one record V013 holds (people.biodata on the field list ref.biodata_field), the contact the
--   portal keeps (people.student_contact), the register line (people.student) and the passport photograph wherever
--   the portal already finds one. Nothing here is a second biodata store.
--
--   1. people.biodata_gate — the switch (one row), OFF; every change on the audit spine, with who, the office and why.
--   2. people.biodata_requirement — what is required: the passport photograph and any field the student can enter
--      (an open field; never a JAMB field the student cannot change, never a health field, which is held under consent).
--   3. people.biodata.updated_at — when a field was last written, kept by a trigger (unknown for rows written before).
--   4. people.biodata_completion(students[]) — the one calculation: for each student the required items, how many are
--      complete, which are missing, and when the record last changed. Set-based, so a list of thousands reads at once.
--   5. people.biodata_gate_exception — a named student let through for a stated reason until a date (at most 30 days),
--      granted and revoked by the ICT Director or an administrator, both on the audit spine.
--   6. people.biodata_gate_state(student) — OFF · EXCEPTION · COMPLETE · REQUIRED: what the API asks on each request.
--   7. people.remind_biodata(limit) — while the gate is ON, a student still incomplete is told by e-mail and SMS on the
--      notice queue at most once a week (people.biodata_reminder keeps what was sent); never while it is OFF.
--
--   Completing the biodata clears the gate and nothing else: it is not admission, screening, a fee, registration,
--   matriculation or graduation. Staff and every non-student account are untouched — the gate reads only the student
--   office (BiodataGateInterceptor in the API).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1 · the switch ────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE people.biodata_gate (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    enabled        boolean NOT NULL DEFAULT false,
    changed_by     uuid NULL,
    changed_office text NULL,
    changed_at     timestamptz NULL,
    reason         text NULL
);
CREATE UNIQUE INDEX ux_biodata_gate_one ON people.biodata_gate ((true));
INSERT INTO people.biodata_gate (enabled) VALUES (false);
SELECT audit.attach('people.biodata_gate');
COMMENT ON TABLE people.biodata_gate IS
  'V423: the ICT Director''s switch for mandatory student biodata completion — one row, OFF by default; every change on the audit spine.';

-- ── 2 · what is required ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE people.biodata_requirement (
    item     text PRIMARY KEY,
    field    text NULL REFERENCES ref.biodata_field(field),
    required boolean NOT NULL DEFAULT true,
    set_by   uuid NULL,
    set_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_biodata_requirement_item CHECK ((item = 'PASSPORT' AND field IS NULL) OR (field IS NOT NULL AND item = field))
);
-- the default: what the University reaches a student by, where they are from, and whom it calls — ten items
INSERT INTO people.biodata_requirement (item, field, required)
SELECT x.item, CASE WHEN x.item = 'PASSPORT' THEN NULL ELSE x.item END, true
  FROM (VALUES ('PASSPORT'), ('mobile'), ('personal_email'), ('home_address'), ('nationality'), ('state_of_origin'), ('lga'),
               ('kin_name'), ('kin_relationship'), ('kin_mobile')) AS x(item)
 WHERE x.item = 'PASSPORT' OR EXISTS (SELECT 1 FROM ref.biodata_field f WHERE f.field = x.item);
SELECT audit.attach('people.biodata_requirement');
COMMENT ON TABLE people.biodata_requirement IS
  'V423: the items a student must complete while the biodata gate is ON — PASSPORT or an open ref.biodata_field; a row with required false is offered but not required.';

-- an item the student cannot complete themselves is never required of them: a JAMB field is corrected with JAMB, and a
-- health field is given under consent, never compelled
CREATE OR REPLACE FUNCTION people.biodata_requirement_guard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE f ref.biodata_field;
BEGIN
    IF NEW.item = 'PASSPORT' OR NOT NEW.required THEN RETURN NEW; END IF;
    SELECT * INTO f FROM ref.biodata_field WHERE field = NEW.field;
    IF f.field IS NULL THEN
        RAISE EXCEPTION 'BIO_REQ_UNKNOWN: % is not a biodata field', NEW.item USING ERRCODE = '23514';
    END IF;
    IF f.tier = 'locked' THEN
        RAISE EXCEPTION 'BIO_REQ_LOCKED: % is read from JAMB and the student cannot enter it, so it cannot be required', f.label USING ERRCODE = '23514';
    END IF;
    IF f.section = 'health' THEN
        RAISE EXCEPTION 'BIO_REQ_HEALTH: % is health information, given under consent; it cannot be made a condition of using the portal', f.label USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_biodata_requirement_guard BEFORE INSERT OR UPDATE ON people.biodata_requirement
    FOR EACH ROW EXECUTE FUNCTION people.biodata_requirement_guard();

-- ── 3 · when a field was last written ────────────────────────────────────────────────────────────────────────────────
ALTER TABLE people.biodata ADD COLUMN updated_at timestamptz NULL;
COMMENT ON COLUMN people.biodata.updated_at IS 'V423: when the value was last written (NULL for rows written before V423).';
CREATE OR REPLACE FUNCTION people.biodata_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.value IS DISTINCT FROM OLD.value THEN
        NEW.updated_at := now();
    ELSE
        NEW.updated_at := OLD.updated_at;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_biodata_touch BEFORE INSERT OR UPDATE ON people.biodata
    FOR EACH ROW EXECUTE FUNCTION people.biodata_touch();

-- ── 4 · the one calculation ──────────────────────────────────────────────────────────────────────────────────────────
-- A field counts as given when it holds something other than blanks — in the biodata, or where the portal keeps the
-- same thing elsewhere: the mobile number, the e-mail and the address the student gave as contact
-- (people.student_contact), and the state of origin on the register line. The passport photograph counts wherever the
-- portal finds one: replaced on the portal, the admission's document, or the attachment store by candidate or JAMB number
-- (the same places StudentPortalRepository.hasPassport looks). Nothing counts because a record merely exists.
CREATE OR REPLACE FUNCTION people.biodata_completion(p_students uuid[])
RETURNS TABLE (student_id uuid, required int, completed int, missing text[], missing_labels text[], complete boolean,
               last_updated timestamptz)
LANGUAGE sql STABLE AS $$
    WITH req AS (
        SELECT r.item, r.field, coalesce(f.label, 'Passport photograph') AS label, coalesce(f.ord, 0) AS ord
          FROM people.biodata_requirement r LEFT JOIN ref.biodata_field f ON f.field = r.field
         WHERE r.required
    ),
    st AS (
        -- a semi-join, not "= ANY": a list of thousands is hashed once rather than compared row by row
        SELECT s.id, s.candidate_id, s.jamb_reg_no, s.state_of_origin FROM people.student s WHERE s.id IN (SELECT unnest(p_students))
    ),
    -- the required fields each student has given in the biodata, read once a student rather than once a field
    given AS (
        SELECT b.student_id, array_agg(b.field) FILTER (WHERE btrim(b.value) <> '') AS fields, max(b.updated_at) AS at
          FROM people.biodata b
         WHERE b.field IN (SELECT req.field FROM req WHERE req.field IS NOT NULL)
           AND b.student_id IN (SELECT st.id FROM st)
         GROUP BY b.student_id
    ),
    pass AS (
        SELECT st.id FROM st
         WHERE EXISTS (SELECT 1 FROM req WHERE req.item = 'PASSPORT')
           AND (EXISTS (SELECT 1 FROM people.student_photo ph WHERE ph.student_id = st.id)
                OR EXISTS (SELECT 1 FROM admissions.application a
                             JOIN admissions.application_document d ON d.application_id = a.id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                            WHERE a.candidate_id = st.candidate_id)
                OR EXISTS (SELECT 1 FROM admissions.attachment at
                            WHERE at.kind = 'PASSPORT' AND at.candidate_id = st.candidate_id
                              AND (at.object_id IS NOT NULL OR jsonb_exists(at.payload, 'dataUrl')))
                OR EXISTS (SELECT 1 FROM admissions.attachment at
                            WHERE at.kind = 'PASSPORT' AND st.jamb_reg_no IS NOT NULL AND at.jamb_key = upper(btrim(st.jamb_reg_no))
                              AND (at.object_id IS NOT NULL OR jsonb_exists(at.payload, 'dataUrl'))))
    ),
    one AS (
        SELECT st.id, st.state_of_origin, coalesce(g.fields, '{}'::text[]) AS fields, g.at, p.id IS NOT NULL AS has_photo,
               nullif(btrim(c.phone), '') AS phone, nullif(btrim(c.email), '') AS email, nullif(btrim(c.address), '') AS address,
               greatest(g.at, c.updated_at, ph.replaced_at) AS touched
          FROM st
          LEFT JOIN given g ON g.student_id = st.id
          LEFT JOIN pass p ON p.id = st.id
          LEFT JOIN people.student_contact c ON c.student_id = st.id
          LEFT JOIN people.student_photo ph ON ph.student_id = st.id
    )
    SELECT o.id, x.required, x.completed, x.missing, x.labels, x.required = x.completed, o.touched
      FROM one o
     CROSS JOIN LATERAL (
        SELECT count(*)::int AS required,
               (count(*) FILTER (WHERE d.done))::int AS completed,
               coalesce(array_agg(req.item ORDER BY req.ord, req.item) FILTER (WHERE NOT d.done), '{}'::text[]) AS missing,
               coalesce(array_agg(req.label ORDER BY req.ord, req.item) FILTER (WHERE NOT d.done), '{}'::text[]) AS labels
          FROM req
         CROSS JOIN LATERAL (SELECT CASE
                 WHEN req.item = 'PASSPORT' THEN o.has_photo
                 WHEN req.field = ANY (o.fields) THEN true
                 -- where the portal keeps the same thing elsewhere: the contact the student gave, the register line
                 WHEN req.field = 'mobile' THEN o.phone IS NOT NULL
                 WHEN req.field = 'personal_email' THEN o.email IS NOT NULL
                 WHEN req.field IN ('home_address', 'term_address') THEN o.address IS NOT NULL
                 WHEN req.field = 'state_of_origin' THEN nullif(btrim(o.state_of_origin), '') IS NOT NULL
                 ELSE false END AS done) d
     ) x
$$;
COMMENT ON FUNCTION people.biodata_completion(uuid[]) IS
  'V423: for each student, the required biodata items (people.biodata_requirement), how many are complete, the missing ones (keys and labels, in the form''s order), whether all are, and when the record last changed — the one calculation the gate, the student''s page, the ICT dashboard and the reminders read.';

-- ── 5 · a named student let through for a while ──────────────────────────────────────────────────────────────────────
CREATE TABLE people.biodata_gate_exception (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id     uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    reason         text NOT NULL,
    granted_by     uuid NOT NULL,
    granted_office text NOT NULL,
    starts_at      timestamptz NOT NULL DEFAULT now(),
    expires_at     timestamptz NOT NULL,
    created_at     timestamptz NOT NULL DEFAULT now(),
    revoked_at     timestamptz NULL,
    revoked_by     uuid NULL,
    revoke_reason  text NULL,
    CONSTRAINT ck_bge_reason CHECK (length(btrim(reason)) >= 5),
    CONSTRAINT ck_bge_span CHECK (expires_at > starts_at AND expires_at <= starts_at + interval '30 days'),
    CONSTRAINT ck_bge_revoke CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);
CREATE INDEX ix_bge_student ON people.biodata_gate_exception (student_id, expires_at DESC);
SELECT audit.attach('people.biodata_gate_exception');
COMMENT ON TABLE people.biodata_gate_exception IS
  'V423: a student let past the biodata gate for a stated reason until a date (30 days at most) — granted and revoked by the ICT Director or an administrator; never deleted.';

CREATE OR REPLACE FUNCTION people.grant_biodata_exception(p_student uuid, p_reason text, p_starts timestamptz, p_expires timestamptz,
                                                          p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_start timestamptz := coalesce(p_starts, now());
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'BIO_GATE_OFFICE: only the ICT Director or an administrator grants a biodata gate exception' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN
        RAISE EXCEPTION 'BIO_GATE_STUDENT: no such student' USING ERRCODE = '23514';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
        RAISE EXCEPTION 'BIO_GATE_REASON: an exception states why it is granted' USING ERRCODE = '23514';
    END IF;
    IF p_expires IS NULL OR p_expires <= v_start OR p_expires > v_start + interval '30 days' THEN
        RAISE EXCEPTION 'BIO_GATE_EXPIRY: an exception ends after it starts and within 30 days' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM people.biodata_gate_exception e
                WHERE e.student_id = p_student AND e.revoked_at IS NULL AND e.expires_at > now()) THEN
        RAISE EXCEPTION 'BIO_GATE_EXCEPTION_ACTIVE: this student already has an exception that has not ended; revoke it first' USING ERRCODE = '23514';
    END IF;
    INSERT INTO people.biodata_gate_exception (student_id, reason, granted_by, granted_office, starts_at, expires_at)
    VALUES (p_student, btrim(p_reason), p_actor, p_office, v_start, p_expires)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION people.revoke_biodata_exception(p_id uuid, p_reason text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'BIO_GATE_OFFICE: only the ICT Director or an administrator revokes a biodata gate exception' USING ERRCODE = '23514';
    END IF;
    UPDATE people.biodata_gate_exception
       SET revoked_at = now(), revoked_by = p_actor, revoke_reason = nullif(btrim(coalesce(p_reason, '')), '')
     WHERE id = p_id AND revoked_at IS NULL AND expires_at > now();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'BIO_GATE_EXCEPTION_ENDED: that exception has already ended or been revoked' USING ERRCODE = '23514';
    END IF;
END $$;

-- ── 6 · what the API asks on each request ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.biodata_gate_state(p_student uuid)
RETURNS text LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF NOT coalesce((SELECT g.enabled FROM people.biodata_gate g LIMIT 1), false) THEN
        RETURN 'OFF';
    END IF;
    IF EXISTS (SELECT 1 FROM people.biodata_gate_exception e
                WHERE e.student_id = p_student AND e.revoked_at IS NULL AND now() >= e.starts_at AND now() < e.expires_at) THEN
        RETURN 'EXCEPTION';
    END IF;
    IF coalesce((SELECT c.complete FROM people.biodata_completion(ARRAY[p_student]) c), false) THEN
        RETURN 'COMPLETE';
    END IF;
    RETURN 'REQUIRED';
END $$;
COMMENT ON FUNCTION people.biodata_gate_state(uuid) IS
  'V423: OFF (the gate is off), EXCEPTION (a live exception lets the student through), COMPLETE, or REQUIRED (the student reaches only the biodata page) — read from the record on every request, never cached.';

-- the switch, turned by the ICT Director or an administrator; the audit spine keeps the row before and after
CREATE OR REPLACE FUNCTION people.set_biodata_gate(p_enabled boolean, p_reason text, p_actor uuid, p_office text)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE v_was boolean;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'BIO_GATE_OFFICE: only the ICT Director or an administrator turns mandatory biodata completion on or off' USING ERRCODE = '23514';
    END IF;
    SELECT enabled INTO v_was FROM people.biodata_gate FOR UPDATE;
    IF v_was = p_enabled THEN
        RAISE EXCEPTION 'BIO_GATE_UNCHANGED: mandatory biodata completion is already %', CASE WHEN p_enabled THEN 'ON' ELSE 'OFF' END USING ERRCODE = '23514';
    END IF;
    UPDATE people.biodata_gate
       SET enabled = p_enabled, changed_by = p_actor, changed_office = p_office, changed_at = now(),
           reason = coalesce(nullif(btrim(coalesce(p_reason, '')), ''), CASE WHEN p_enabled THEN 'Turned ON' ELSE 'Turned OFF' END);
    RETURN p_enabled;
END $$;

CREATE OR REPLACE FUNCTION people.set_biodata_requirement(p_item text, p_required boolean, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_item text := CASE WHEN upper(btrim(p_item)) = 'PASSPORT' THEN 'PASSPORT' ELSE lower(btrim(p_item)) END;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'BIO_GATE_OFFICE: only the ICT Director or an administrator states the required biodata' USING ERRCODE = '23514';
    END IF;
    IF v_item <> 'PASSPORT' AND NOT EXISTS (SELECT 1 FROM ref.biodata_field WHERE field = v_item) THEN
        RAISE EXCEPTION 'BIO_REQ_UNKNOWN: % is not a biodata field', p_item USING ERRCODE = '23514';
    END IF;
    INSERT INTO people.biodata_requirement (item, field, required, set_by, set_at)
    VALUES (v_item, CASE WHEN v_item = 'PASSPORT' THEN NULL ELSE v_item END, p_required, p_actor, now())
    ON CONFLICT (item) DO UPDATE SET required = EXCLUDED.required, set_by = EXCLUDED.set_by, set_at = now()
     WHERE people.biodata_requirement.required IS DISTINCT FROM EXCLUDED.required;
END $$;

-- ── 7 · the weekly reminder, only while the gate is ON ───────────────────────────────────────────────────────────────
CREATE TABLE people.biodata_reminder (
    student_id   uuid PRIMARY KEY REFERENCES people.student(id) ON DELETE CASCADE,
    last_sent_at timestamptz NOT NULL,
    sent         int NOT NULL DEFAULT 1,
    queued       int NOT NULL DEFAULT 0
);
SELECT audit.exempt('people.biodata_reminder', 'when a student was last reminded to complete their biodata; written by the weekly job, read to keep from reminding twice in a week');

-- the students the gate is meant for on a dashboard or a reminder: on the register and in the portal's use
CREATE OR REPLACE FUNCTION people.biodata_applicable(p_status text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED')
$$;

CREATE OR REPLACE FUNCTION people.remind_biodata(p_limit int DEFAULT 3000)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE r record; n int := 0; v_q int; v_inst text;
BEGIN
    IF NOT coalesce((SELECT enabled FROM people.biodata_gate LIMIT 1), false) THEN
        RETURN 0;
    END IF;
    v_inst := coalesce((SELECT name FROM platform.institution_profile ORDER BY updated_at DESC LIMIT 1), 'the University');
    FOR r IN
        WITH cand AS (
            SELECT s.id FROM people.student s
             WHERE people.biodata_applicable(s.status)
               AND EXISTS (SELECT 1 FROM iam.student_account a WHERE a.student_id = s.id)
               AND NOT EXISTS (SELECT 1 FROM people.biodata_reminder m WHERE m.student_id = s.id AND m.last_sent_at > now() - interval '7 days')
        )
        SELECT c.student_id, c.missing_labels, c.completed, c.required, s.surname, s.other_names
          FROM people.biodata_completion((SELECT coalesce(array_agg(id), '{}'::uuid[]) FROM cand)) c
          JOIN people.student s ON s.id = c.student_id
          LEFT JOIN people.biodata_reminder m ON m.student_id = c.student_id
         WHERE NOT c.complete
         ORDER BY m.last_sent_at NULLS FIRST, s.surname, s.other_names
         LIMIT greatest(1, p_limit)
    LOOP
        SELECT count(*)::int INTO v_q FROM (
            SELECT platform.queue_notice('EMAIL', x.email, 'Complete your biodata on the student portal',
                       'Dear ' || r.surname || ', ' || r.other_names || ',' || E'\n\n'
                       || 'Please complete your required biodata information before using the Student Portal. '
                       || r.completed || ' of ' || r.required || ' required items are complete; still missing: '
                       || array_to_string(r.missing_labels, ', ') || '.' || E'\n\n'
                       || 'Sign in to the portal and open Biodata to complete it.' || E'\n\n' || 'ICT Directorate, ' || v_inst,
                       'student', r.student_id) AS q
              FROM people.student_reach(r.student_id) x
            UNION ALL
            SELECT platform.queue_notice('SMS', x.phone, 'Complete your biodata',
                       'MOAUM: please complete your required biodata on the student portal before continuing.', 'student', r.student_id)
              FROM people.student_reach(r.student_id) x
        ) y WHERE y.q IS NOT NULL;
        INSERT INTO people.biodata_reminder (student_id, last_sent_at, sent, queued) VALUES (r.student_id, now(), 1, v_q)
        ON CONFLICT (student_id) DO UPDATE SET last_sent_at = now(), sent = people.biodata_reminder.sent + 1, queued = EXCLUDED.queued;
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION people.remind_biodata(int) IS
  'V423: while the biodata gate is ON, tells each student still incomplete (on the register, with a portal account) by e-mail and SMS on the notice queue — at most once in seven days, and never while the gate is OFF; returns how many were reminded.';

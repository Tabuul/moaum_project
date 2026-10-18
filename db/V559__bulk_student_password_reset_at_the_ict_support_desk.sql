-- V559: bulk student password reset at the ICT Support Desk, on the one reset service of V485.
--
-- The desk resets one student at a time to the default student credential (V485: the account put on its first password — a hash
-- of a secret nobody holds, must-change on — the state in which the sign-in accepts the matriculation number and forces the
-- change before anything else; the number itself is never hashed or stored). ICT Support now resets many students in one
-- operation the same way:
--   * helpdesk.support_capabilities gains BULK_RESET_PASSWORD — granted on a posting, with the posting's scope (a CPO over the
--     Faculty of Science bulk-resets Science students only); the Head of the Support Desk, the Director of ICT and the
--     administrators hold it for the University. Not in the support baseline: the single reset stays every agent's.
--   * helpdesk.bulk_reset_check(agent, head, students): for each student chosen, whether it may be reset — not found, outside the
--     agent's scope (the desk never says who such a student is), switched off, a merged record, no matriculation number, a
--     status the desk does not reset — read for all of them at once; the preview, and again for each student as it is reset.
--   * helpdesk.bulk_reset (BPR/2026/000001 …) and helpdesk.bulk_reset_item: the operation — who, why, how many, the state
--     (PENDING, PROCESSING, COMPLETED, COMPLETED_WITH_EXCEPTIONS, FAILED, CANCELLED) — and each student's result (RESET,
--     ALREADY_RESET, FAILED with why); a repeat of the same request (its key) is the same operation. Each student is reset in
--     its own transaction by the API's BulkPasswordResets, on the support ledger as a PASSWORD_RESET naming the operation.
--   * helpdesk.start_bulk_reset, bulk_reset_tally and reset_desk_summary (the desk's counts: open login issues, resets today,
--     bulk resets today, students reset and failed in them).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V559: bulk student password reset at the ICT Support Desk', true);

CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE',
                 'VIEW_PROGRAMME_STRUCTURE', 'EDIT_COURSES', 'BIND_COURSES', 'MANAGE_PREREQUISITES',
                 'PROGRESS_LEVEL', 'CORRECT_LEVEL', 'VIEW_LEVEL_HISTORY', 'VIEW_RESET_HISTORY',
                 'VIEW_STUDENT_PORTAL',
                 -- V559: many students reset to the default credential in one operation, within the posting's scope
                 'BULK_RESET_PASSWORD']
$function$;

CREATE TABLE helpdesk.bulk_reset (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference       text NOT NULL UNIQUE,
    initiated_by    uuid NOT NULL,
    office          text NOT NULL,
    head            boolean NOT NULL,
    reason          text NOT NULL CHECK (length(btrim(reason)) >= 10),
    unlock          boolean NOT NULL DEFAULT true,
    idempotency_key text,
    status          text NOT NULL DEFAULT 'PENDING'
                    CHECK (status IN ('PENDING', 'PROCESSING', 'COMPLETED', 'COMPLETED_WITH_EXCEPTIONS', 'FAILED', 'CANCELLED')),
    total           integer NOT NULL DEFAULT 0,
    succeeded       integer NOT NULL DEFAULT 0,
    failed          integer NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    started_at      timestamptz,
    completed_at    timestamptz,
    UNIQUE (initiated_by, idempotency_key)
);
CREATE INDEX ix_bulk_reset_open ON helpdesk.bulk_reset (created_at) WHERE status IN ('PENDING', 'PROCESSING');
CREATE INDEX ix_bulk_reset_created ON helpdesk.bulk_reset (created_at DESC);
COMMENT ON TABLE helpdesk.bulk_reset IS
  'V559: a bulk student password reset at the ICT Support Desk — who, why, how many, and how it ended; never a password';
SELECT audit.attach('helpdesk.bulk_reset');

CREATE TABLE helpdesk.bulk_reset_item (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bulk_id       uuid NOT NULL REFERENCES helpdesk.bulk_reset (id) ON DELETE CASCADE,
    student_id    uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    ticket_id     uuid REFERENCES helpdesk.ticket (id) ON DELETE SET NULL,
    ord           integer NOT NULL,
    status        text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'RESET', 'ALREADY_RESET', 'FAILED')),
    failure_code  text,
    failure_words text,
    action_id     uuid,
    processed_at  timestamptz,
    UNIQUE (bulk_id, student_id),
    CHECK ((status = 'FAILED') = (failure_code IS NOT NULL))
);
CREATE INDEX ix_bulk_reset_item_pending ON helpdesk.bulk_reset_item (bulk_id, ord) WHERE status = 'PENDING';
CREATE INDEX ix_bulk_reset_item_student ON helpdesk.bulk_reset_item (student_id);
CREATE INDEX ix_bulk_reset_item_ticket ON helpdesk.bulk_reset_item (ticket_id) WHERE ticket_id IS NOT NULL;
COMMENT ON TABLE helpdesk.bulk_reset_item IS 'V559: each student of a bulk password reset and its result (RESET, ALREADY_RESET, FAILED and why)';
SELECT audit.attach('helpdesk.bulk_reset_item');

-- whether each student chosen may be reset by this agent: read for all at once, as iam.student_reset_check reads one, with the scope first
CREATE FUNCTION helpdesk.bulk_reset_check(p_agent uuid, p_head boolean, p_students uuid[])
RETURNS TABLE(student_id uuid, full_name text, matric_no text, jamb_reg_no text, faculty text, department text, programme text,
              current_level integer, status text, has_account boolean, must_change boolean, locked boolean, last_signed_in_at timestamptz,
              eligible boolean, code text)
LANGUAGE sql STABLE AS $fn$
    WITH them AS (SELECT DISTINCT x AS id FROM unnest(p_students) x WHERE x IS NOT NULL),
    sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(p_agent, 'BULK_RESET_PASSWORD')),
    g AS (SELECT * FROM helpdesk.setting WHERE row_no),
    r AS (
        SELECT t.id, s.id AS sid, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.current_level, s.status, s.duplicate_of,
               f.name AS faculty, d.name AS department, p.name AS programme,
               a.id IS NOT NULL AS has_account, coalesce(a.must_change, false) AS must_change, coalesce(a.locked_until > now(), false) AS locked,
               a.last_signed_in_at,
               p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY (sc.faculties) OR p.dept_code = ANY (sc.departments)) AS reach,
               CASE WHEN s.id IS NULL THEN 'NOT_FOUND'
                    WHEN NOT (p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY (sc.faculties) OR p.dept_code = ANY (sc.departments))) THEN 'OUT_OF_SCOPE'
                    WHEN NOT coalesce((SELECT g.student_reset_enabled FROM g), true) THEN 'RESET_DISABLED'
                    WHEN s.duplicate_of IS NOT NULL THEN 'RESET_MERGED_RECORD'
                    WHEN nullif(btrim(s.matric_no), '') IS NULL THEN 'RESET_NO_MATRIC'
                    WHEN NOT s.status = ANY (coalesce((SELECT g.student_reset_statuses FROM g), ARRAY['ACTIVE', 'PROBATION', 'DEFERRED', 'DORMANT', 'GRADUATED'])) THEN 'RESET_STATUS'
               END AS code
          FROM them t
          LEFT JOIN people.student s ON s.id = t.id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN iam.student_account a ON a.student_id = s.id)
    -- a student outside the agent's reach is never described: only that the desk may not reset it
    SELECT r.id, CASE WHEN r.reach AND r.sid IS NOT NULL THEN upper(btrim(r.surname)) || coalesce(', ' || nullif(btrim(r.other_names), ''), '') END,
           CASE WHEN r.reach THEN nullif(btrim(r.matric_no), '') END, CASE WHEN r.reach THEN r.jamb_reg_no END,
           CASE WHEN r.reach THEN r.faculty END, CASE WHEN r.reach THEN r.department END, CASE WHEN r.reach THEN r.programme END,
           CASE WHEN r.reach THEN r.current_level END, CASE WHEN r.reach THEN r.status END,
           CASE WHEN r.reach THEN r.has_account END, CASE WHEN r.reach THEN r.must_change END, CASE WHEN r.reach THEN r.locked END,
           CASE WHEN r.reach THEN r.last_signed_in_at END,
           r.code IS NULL, coalesce(r.code, 'ELIGIBLE')
      FROM r
$fn$;
COMMENT ON FUNCTION helpdesk.bulk_reset_check(uuid, boolean, uuid[]) IS
  'V559: for each student chosen, whether this agent may reset it to the default credential (NOT_FOUND, OUT_OF_SCOPE, RESET_DISABLED, RESET_MERGED_RECORD, RESET_NO_MATRIC, RESET_STATUS or ELIGIBLE) — the scope of BULK_RESET_PASSWORD first; read for all at once';

-- a bulk reset opened: the same request again (its key) is the same operation
CREATE FUNCTION helpdesk.start_bulk_reset(p_agent uuid, p_office text, p_head boolean, p_students uuid[], p_tickets jsonb, p_reason text,
                                          p_unlock boolean, p_key text)
RETURNS uuid
LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid; v_n int; v_ref text; v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
BEGIN
    IF p_key IS NOT NULL THEN
        SELECT b.id INTO v_id FROM helpdesk.bulk_reset b WHERE b.initiated_by = p_agent AND b.idempotency_key = p_key;
        IF FOUND THEN RETURN v_id; END IF;
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SUPPORT_REASON_SHORT: say why the passwords are reset, in 10 characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT count(DISTINCT x) INTO v_n FROM unnest(p_students) x WHERE x IS NOT NULL;
    IF v_n = 0 THEN
        RAISE EXCEPTION 'BULK_RESET_EMPTY: choose the students to reset' USING ERRCODE = '23514';
    END IF;
    IF v_n > 1000 THEN
        RAISE EXCEPTION 'BULK_RESET_TOO_MANY: at most 1,000 students in one operation (% chosen); reset them in parts', v_n USING ERRCODE = '23514';
    END IF;
    v_ref := 'BPR/' || v_year || '/' || lpad(platform.next_number('BULK_PASSWORD_RESET', 'ICT_SUPPORT', v_year)::text, 6, '0');
    INSERT INTO helpdesk.bulk_reset (reference, initiated_by, office, head, reason, unlock, idempotency_key, total)
    VALUES (v_ref, p_agent, p_office, p_head, btrim(p_reason), coalesce(p_unlock, true), p_key, v_n)
    RETURNING id INTO v_id;
    -- one item a student, in the order chosen, with the login ticket named for it; an id that names no student is counted as
    -- failed by the tally (the total is of every id chosen), never skipped in silence
    INSERT INTO helpdesk.bulk_reset_item (bulk_id, student_id, ticket_id, ord)
    SELECT v_id, d.x, d.tid, row_number() OVER (ORDER BY d.o)
      FROM (SELECT DISTINCT ON (s.x) s.x, s.o, t.id AS tid
              FROM unnest(p_students) WITH ORDINALITY s(x, o)
              LEFT JOIN helpdesk.ticket t ON t.id = CASE WHEN (p_tickets ->> s.x::text) ~ '^[0-9a-fA-F-]{36}$' THEN (p_tickets ->> s.x::text)::uuid END
             WHERE s.x IS NOT NULL AND EXISTS (SELECT 1 FROM people.student st WHERE st.id = s.x)
             ORDER BY s.x, s.o) d;
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION helpdesk.start_bulk_reset(uuid, text, boolean, uuid[], jsonb, text, boolean, text) IS
  'V559: a bulk password reset opened for the students chosen (at most 1,000), each student''s login ticket kept where given; the same key again is the same operation';

-- the operation's counts and state from its students' results
CREATE FUNCTION helpdesk.bulk_reset_tally(p_bulk uuid)
RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE v_ok int; v_bad int; v_pending int; v_total int; v_status text;
BEGIN
    SELECT count(*) FILTER (WHERE i.status IN ('RESET', 'ALREADY_RESET')), count(*) FILTER (WHERE i.status = 'FAILED'),
           count(*) FILTER (WHERE i.status = 'PENDING')
      INTO v_ok, v_bad, v_pending FROM helpdesk.bulk_reset_item i WHERE i.bulk_id = p_bulk;
    SELECT b.total INTO v_total FROM helpdesk.bulk_reset b WHERE b.id = p_bulk;
    -- a chosen id that named no student: failed, counted
    v_bad := v_bad + greatest(v_total - (v_ok + v_bad + v_pending), 0);
    v_status := CASE WHEN v_pending > 0 THEN 'PROCESSING'
                     WHEN v_bad = 0 THEN 'COMPLETED'
                     WHEN v_ok = 0 THEN 'FAILED'
                     ELSE 'COMPLETED_WITH_EXCEPTIONS' END;
    -- a cancelled operation keeps its state; its counts still follow its students (one reset as the cancel came is counted)
    UPDATE helpdesk.bulk_reset
       SET succeeded = v_ok, failed = v_bad, status = CASE WHEN status = 'CANCELLED' THEN status ELSE v_status END,
           started_at = coalesce(started_at, now()),
           completed_at = CASE WHEN v_pending = 0 THEN coalesce(completed_at, now()) ELSE completed_at END
     WHERE id = p_bulk
    RETURNING status INTO v_status;
    RETURN v_status;
END $fn$;
COMMENT ON FUNCTION helpdesk.bulk_reset_tally(uuid) IS 'V559: a bulk password reset''s counts and state from its students'' results';

-- the desk's counts, within the reader's reach: open login issues, resets today, bulk resets today and their students
CREATE FUNCTION helpdesk.reset_desk_summary(p_agent uuid, p_head boolean)
RETURNS jsonb
LANGUAGE sql STABLE AS $fn$
    WITH today AS (SELECT (now() AT TIME ZONE 'Africa/Lagos')::date AS d),
    sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(p_agent, 'BULK_RESET_PASSWORD')),
    b AS (SELECT * FROM helpdesk.bulk_reset x WHERE (x.created_at AT TIME ZONE 'Africa/Lagos')::date = (SELECT d FROM today)
                                               AND (p_head OR x.initiated_by = p_agent))
    SELECT jsonb_build_object(
        -- the students the bulk list's "Login issues only" shows: within the bulk scope, with an open Login Issues ticket the reader works
        'loginIssues', (SELECT count(DISTINCT t.requester_id) FROM helpdesk.ticket t JOIN helpdesk.category c ON c.id = t.category_id AND c.code = 'LOGIN'
                         JOIN people.student s ON t.requester_kind = 'STUDENT' AND s.id = t.requester_id
                         JOIN ref.programme p ON p.code = s.programme_code
                        WHERE t.status NOT IN ('RESOLVED', 'CLOSED')
                          AND (p_head OR (EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY (sc.faculties) OR p.dept_code = ANY (sc.departments))
                                          AND helpdesk.can_view(p_agent, t.id)))),
        'resetsToday', (SELECT count(*) FROM helpdesk.support_action a
                         WHERE a.action = 'PASSWORD_RESET' AND (a.at AT TIME ZONE 'Africa/Lagos')::date = (SELECT d FROM today)
                           AND (p_head OR a.agent_id = p_agent)),
        'bulkToday', (SELECT count(*) FROM b),
        'studentsResetToday', (SELECT coalesce(sum(b.succeeded), 0) FROM b),
        'failedToday', (SELECT coalesce(sum(b.failed), 0) FROM b),
        'mayBulk', p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR cardinality(sc.faculties) > 0 OR cardinality(sc.departments) > 0),
        'scope', CASE WHEN p_head THEN 'The University' ELSE (SELECT sc.words FROM sc) END)
$fn$;
COMMENT ON FUNCTION helpdesk.reset_desk_summary(uuid, boolean) IS
  'V559: the reset desk''s counts within the reader''s reach — students with an open login issue the reader works, resets today, bulk resets today, students reset and failed in them — and whether the reader may bulk-reset, over what';

COMMIT;

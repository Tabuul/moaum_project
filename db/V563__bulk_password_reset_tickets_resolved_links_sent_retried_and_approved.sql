-- V563: the bulk password reset (V559) finished at the desk — the login tickets resolved with it, a reset link for the students it
-- could not reset for want of a matriculation number, its resets kept apart in the Head's oversight, the students it failed tried
-- again, and a large one approved before it runs.
--
--   * A bulk reset may resolve each student's login ticket once the student is reset (helpdesk.bulk_reset.resolve_tickets, with
--     the words the students read): the ticket is taken through opened and in progress to resolved, on its timeline in the
--     agent's name, by helpdesk.resolve_for_reset; a ticket already resolved or closed is left as it is.
--   * A student refused for want of a matriculation number (RESET_NO_MATRIC) may be sent the one-hour reset link of the single
--     reset (V485's LINK method) from the operation's record: bulk_reset_item.link_sent_at / link_to (masked) / link_failure.
--   * Every support act made inside a bulk reset names it (helpdesk.support_action.bulk_id, set from the transaction's
--     moaum.bulk_reset): the Head's daily alert (V528) counts single resets only — a bulk reset is one reasoned operation under its
--     reference, not an agent resetting student after student — and helpdesk.reset_counts gives the bulk resets beside them.
--   * The students an operation did not reset may be tried again as a new operation (bulk_reset.retry_of).
--   * An operation of more students than helpdesk.setting.bulk_reset_approval_over (200 unless the Director of ICT says
--     otherwise; empty, never) waits (AWAITING_APPROVAL) until the Head of the ICT Support Desk, the Director of ICT or an
--     administrator other than the one who asked approves it, or declines it on a reason (REJECTED); both are told
--     (BULK_RESET_APPROVAL, BULK_RESET_DECIDED). The students are checked again as each is reset, whenever it is approved.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V563: bulk password reset — tickets resolved, links sent, retries, approval of a large one', true);

-- ── the policy: a large bulk reset waits for approval ───────────────────────────────────────────────────────────────────────
ALTER TABLE helpdesk.setting
    ADD COLUMN bulk_reset_approval_over integer NULL DEFAULT 200,
    ADD CONSTRAINT ck_hd_setting_bulk_approval CHECK (bulk_reset_approval_over IS NULL OR bulk_reset_approval_over BETWEEN 1 AND 1000);
COMMENT ON COLUMN helpdesk.setting.bulk_reset_approval_over IS
  'V563: a bulk password reset of more students than this waits for the Head of the ICT Support Desk or the Director of ICT (another person than the one who asked); NULL, never';

-- ── the operation ───────────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE helpdesk.bulk_reset
    DROP CONSTRAINT bulk_reset_status_check,
    ADD CONSTRAINT bulk_reset_status_check
        CHECK (status IN ('AWAITING_APPROVAL', 'PENDING', 'PROCESSING', 'COMPLETED', 'COMPLETED_WITH_EXCEPTIONS', 'FAILED', 'CANCELLED', 'REJECTED')),
    ADD COLUMN resolve_tickets boolean NOT NULL DEFAULT false,
    ADD COLUMN resolution      text,
    ADD COLUMN retry_of        uuid REFERENCES helpdesk.bulk_reset (id) ON DELETE SET NULL,
    ADD COLUMN approval_over   integer,
    ADD COLUMN decided_by      uuid,
    ADD COLUMN decided_at      timestamptz,
    ADD COLUMN decision_note   text,
    ADD CONSTRAINT ck_bulk_reset_resolution CHECK (NOT resolve_tickets OR length(btrim(coalesce(resolution, ''))) >= 20);
CREATE INDEX ix_bulk_reset_retry ON helpdesk.bulk_reset (retry_of);
CREATE INDEX ix_bulk_reset_waiting ON helpdesk.bulk_reset (created_at) WHERE status = 'AWAITING_APPROVAL';
COMMENT ON COLUMN helpdesk.bulk_reset.resolve_tickets IS 'V563: each student''s login ticket resolved once the student is reset, with the words in resolution';
COMMENT ON COLUMN helpdesk.bulk_reset.retry_of IS 'V563: the operation whose students not reset this one tries again';
COMMENT ON COLUMN helpdesk.bulk_reset.approval_over IS 'V563: the number of students above which it waited for approval, when it did';

ALTER TABLE helpdesk.bulk_reset_item
    ADD COLUMN ticket_resolved_at timestamptz,
    ADD COLUMN link_sent_at       timestamptz,
    ADD COLUMN link_to            text,
    ADD COLUMN link_failure       text;
COMMENT ON COLUMN helpdesk.bulk_reset_item.link_to IS 'V563: where the reset link went, masked as the single reset shows it (j***@mail.com and 080****12)';

-- ── every support act inside a bulk reset names it ──────────────────────────────────────────────────────────────────────────
ALTER TABLE helpdesk.support_action ADD COLUMN bulk_id uuid;
CREATE INDEX ix_hd_sa_bulk ON helpdesk.support_action (bulk_id) WHERE bulk_id IS NOT NULL;
COMMENT ON COLUMN helpdesk.support_action.bulk_id IS
  'V563: the bulk password reset (helpdesk.bulk_reset) the act was made in — from the transaction''s moaum.bulk_reset, set by the API for each student of one';

CREATE FUNCTION helpdesk.trg_support_action_bulk()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF NEW.bulk_id IS NULL AND nullif(current_setting('moaum.bulk_reset', true), '') IS NOT NULL THEN
        NEW.bulk_id := current_setting('moaum.bulk_reset', true)::uuid;
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_support_action_bulk BEFORE INSERT ON helpdesk.support_action FOR EACH ROW EXECUTE FUNCTION helpdesk.trg_support_action_bulk();

-- the Head told of many single resets by one agent (V528), a bulk reset's not among them (restated from V528's text)
CREATE OR REPLACE FUNCTION helpdesk.trg_reset_alert()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_at int; v_day date := (now() AT TIME ZONE 'Africa/Lagos')::date; n int; v_agent text; p record; v_heads int := 0; v_key text;
BEGIN
    SELECT g.student_reset_alert_daily INTO v_at FROM helpdesk.setting g WHERE g.row_no;
    IF v_at IS NULL OR NEW.agent_id IS NULL OR NEW.bulk_id IS NOT NULL THEN RETURN NEW; END IF;
    -- the agent's single resets this Lagos day, read on ix_hd_sa_agent (agent_id, at)
    SELECT count(*) INTO n FROM helpdesk.support_action a
     WHERE a.agent_id = NEW.agent_id AND a.action = 'PASSWORD_RESET' AND a.bulk_id IS NULL
       AND a.at >= v_day::timestamp AT TIME ZONE 'Africa/Lagos' AND a.at < (v_day + 1)::timestamp AT TIME ZONE 'Africa/Lagos';
    IF n < v_at THEN RETURN NEW; END IF;
    -- once an agent a day (reached, or passed when the figure was lowered during the day)
    v_key := 'reset-alert:' || NEW.agent_id || ':' || v_day;
    IF EXISTS (SELECT 1 FROM platform.notice x WHERE x.event_key = v_key) THEN RETURN NEW; END IF;
    SELECT coalesce(pp.surname || ', ' || pp.given_names, 'An agent') INTO v_agent FROM iam.person pp WHERE pp.id = NEW.agent_id;
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code = 'helpdeskhead' AND oa.valid_from <= v_day AND (oa.valid_to IS NULL OR oa.valid_to >= v_day)
                AND oa.person_id <> NEW.agent_id LOOP
        v_heads := v_heads + platform.tell_person(p.person_id, 'SUPPORT_RESET_ALERT', NULL,
            jsonb_build_object('AGENT', coalesce(v_agent, 'An agent'), 'COUNT', n::text, 'DAY', to_char(v_day, 'FMDD FMMonth YYYY')),
            v_key);
    END LOOP;
    IF v_heads = 0 THEN
        FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
                  WHERE oa.office_code = 'ict' AND oa.valid_from <= v_day AND (oa.valid_to IS NULL OR oa.valid_to >= v_day)
                    AND oa.person_id <> NEW.agent_id LOOP
            PERFORM platform.tell_person(p.person_id, 'SUPPORT_RESET_ALERT', NULL,
                jsonb_build_object('AGENT', coalesce(v_agent, 'An agent'), 'COUNT', n::text, 'DAY', to_char(v_day, 'FMDD FMMonth YYYY')),
                v_key);
        END LOOP;
    END IF;
    RETURN NEW;
END $fn$;

-- each agent's resets today and in the last seven days (Lagos days): the single ones (what the alert counts) and the bulk ones apart
DROP FUNCTION helpdesk.reset_counts();
CREATE FUNCTION helpdesk.reset_counts()
RETURNS TABLE (agent_id uuid, name text, today int, week int, last_at timestamptz, alert_at int, bulk_today int, bulk_week int, bulk_ops_today int)
LANGUAGE sql STABLE AS $fn$
    WITH d AS (SELECT (now() AT TIME ZONE 'Africa/Lagos')::date AS today),
    r AS (
        SELECT a.agent_id, (a.at AT TIME ZONE 'Africa/Lagos')::date AS day, a.at, a.bulk_id
          FROM helpdesk.support_action a, d
         WHERE a.action = 'PASSWORD_RESET' AND a.agent_id IS NOT NULL AND a.at >= (d.today - 6)::timestamp AT TIME ZONE 'Africa/Lagos')
    SELECT r.agent_id, coalesce(pp.surname || ', ' || pp.given_names, r.agent_id::text),
           count(*) FILTER (WHERE r.day = d.today AND r.bulk_id IS NULL)::int, count(*) FILTER (WHERE r.bulk_id IS NULL)::int,
           max(r.at) FILTER (WHERE r.bulk_id IS NULL),
           (SELECT g.student_reset_alert_daily FROM helpdesk.setting g WHERE g.row_no),
           count(*) FILTER (WHERE r.day = d.today AND r.bulk_id IS NOT NULL)::int, count(*) FILTER (WHERE r.bulk_id IS NOT NULL)::int,
           count(DISTINCT r.bulk_id) FILTER (WHERE r.day = d.today)::int
      FROM r CROSS JOIN d
      LEFT JOIN iam.person pp ON pp.id = r.agent_id
     GROUP BY r.agent_id, pp.surname, pp.given_names
     ORDER BY 3 DESC, 7 DESC, 4 DESC, 2
$fn$;
COMMENT ON FUNCTION helpdesk.reset_counts() IS
  'V528, V563: each ICT Support agent''s single student password resets today and in the last seven days (Lagos days), the last one, the daily figure at which the Head is told, and the students reset in bulk resets (and those operations today) apart';

-- ── a login ticket resolved with the reset ──────────────────────────────────────────────────────────────────────────────────
-- the ticket taken through the desk's own steps (submitted → opened → in progress → resolved), each on its timeline in the agent's
-- name; false when it was already resolved or closed
CREATE FUNCTION helpdesk.resolve_for_reset(p_ticket uuid, p_agent uuid, p_summary text, p_details text)
RETURNS boolean LANGUAGE plpgsql AS $fn$
DECLARE v_status text; v_name text := helpdesk.person_name(p_agent);
BEGIN
    SELECT t.status INTO v_status FROM helpdesk.ticket t WHERE t.id = p_ticket FOR UPDATE;
    IF NOT FOUND OR v_status IN ('RESOLVED', 'CLOSED') THEN RETURN false; END IF;
    IF v_status = 'SUBMITTED' THEN
        PERFORM helpdesk.transition(p_ticket, 'OPENED', 'AGENT', p_agent, v_name, NULL);
        v_status := 'OPENED';
    END IF;
    IF v_status <> 'IN_PROGRESS' THEN
        PERFORM helpdesk.transition(p_ticket, 'IN_PROGRESS', 'AGENT', p_agent, v_name, NULL);
    END IF;
    PERFORM helpdesk.resolve(p_ticket, p_agent, p_summary, p_details);
    RETURN true;
END $fn$;
COMMENT ON FUNCTION helpdesk.resolve_for_reset(uuid, uuid, text, text) IS
  'V563: a student''s login ticket resolved once the student''s password is reset in a bulk reset, through opened and in progress as the desk takes it';

-- ── the notices of a large bulk reset ───────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('BULK_RESET_APPROVAL', 'A large bulk password reset waits for approval',
 'To the Head of the ICT Support Desk (the Director of ICT where no Head is in office) when a bulk password reset of more students than the figure in ICT Support Settings waits for approval',
 '[AGENT] asks to reset [COUNT] student passwords ([REFERENCE])',
 E'Dear [FIRST_NAME],\n\n[AGENT] has asked to reset the passwords of [COUNT] students to their matriculation numbers in one operation, [REFERENCE].\n\nReason given: [REASON]\n\nA bulk reset of more than [OVER] students waits until the Head of the ICT Support Desk or the Director of ICT approves it. Approve or decline it under ICT Support Desk, Bulk Password Reset: [PORTAL_URL]\n\nMOAUM Portal',
 NULL,
 '[COUNT] password resets wait for your approval',
 '[AGENT] asks to reset [COUNT] student passwords in [REFERENCE]. Reason: [REASON]. Approve or decline it under Bulk Password Reset.',
 ARRAY['FIRST_NAME','AGENT','COUNT','REFERENCE','REASON','OVER','PORTAL_URL','UNIVERSITY_SHORT'], false, 'HIGH'),
('BULK_RESET_DECIDED', 'A bulk password reset approved or declined',
 'To the ICT Support agent who asked for a large bulk password reset, when it is approved or declined',
 'Bulk password reset [REFERENCE] [DECISION]',
 E'Dear [FIRST_NAME],\n\nYour bulk password reset [REFERENCE] of [COUNT] students was [DECISION] by [DECIDER].[NOTE]\n\n[NEXT]\n\nMOAUM Portal',
 NULL,
 'Bulk password reset [REFERENCE] [DECISION]',
 'Your bulk password reset [REFERENCE] of [COUNT] students was [DECISION] by [DECIDER].[NOTE] [NEXT]',
 ARRAY['FIRST_NAME','REFERENCE','COUNT','DECISION','DECIDER','NOTE','NEXT','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL');

-- the Head of the ICT Support Desk told of a bulk reset waiting (the Director of ICT where no Head is in office), never the one who asked
CREATE FUNCTION helpdesk.tell_bulk_approvers(p_bulk uuid)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE b record; v_day date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_vars jsonb; p record; v_told int := 0;
BEGIN
    SELECT x.id, x.reference, x.total, x.reason, x.approval_over, x.initiated_by, helpdesk.person_name(x.initiated_by) AS who
      INTO b FROM helpdesk.bulk_reset x WHERE x.id = p_bulk;
    IF NOT FOUND THEN RETURN 0; END IF;
    v_vars := jsonb_build_object('AGENT', coalesce(b.who, 'An agent'), 'COUNT', b.total::text, 'REFERENCE', b.reference, 'REASON', b.reason,
                                 'OVER', coalesce(b.approval_over::text, ''));
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code = 'helpdeskhead' AND oa.valid_from <= v_day AND (oa.valid_to IS NULL OR oa.valid_to >= v_day)
                AND oa.person_id <> b.initiated_by LOOP
        v_told := v_told + platform.tell_person(p.person_id, 'BULK_RESET_APPROVAL', NULL, v_vars, 'bulk-reset-approval:' || p_bulk);
    END LOOP;
    IF v_told = 0 THEN
        FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
                  WHERE oa.office_code = 'ict' AND oa.valid_from <= v_day AND (oa.valid_to IS NULL OR oa.valid_to >= v_day)
                    AND oa.person_id <> b.initiated_by LOOP
            v_told := v_told + platform.tell_person(p.person_id, 'BULK_RESET_APPROVAL', NULL, v_vars, 'bulk-reset-approval:' || p_bulk);
        END LOOP;
    END IF;
    RETURN v_told;
END $fn$;
COMMENT ON FUNCTION helpdesk.tell_bulk_approvers(uuid) IS
  'V563: the Head of the ICT Support Desk (the Director of ICT where no Head is in office) told that a large bulk password reset waits for approval';

-- ── a bulk reset opened (restated from V559's text): ticket resolution, a retry, the wait for approval ─────────────────────
DROP FUNCTION helpdesk.start_bulk_reset(uuid, text, boolean, uuid[], jsonb, text, boolean, text);
CREATE FUNCTION helpdesk.start_bulk_reset(p_agent uuid, p_office text, p_head boolean, p_students uuid[], p_tickets jsonb, p_reason text,
                                          p_unlock boolean, p_key text, p_resolve boolean DEFAULT false, p_resolution text DEFAULT NULL,
                                          p_retry_of uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid; v_n int; v_ref text; v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'); v_over int; v_wait boolean;
BEGIN
    IF p_key IS NOT NULL THEN
        SELECT b.id INTO v_id FROM helpdesk.bulk_reset b WHERE b.initiated_by = p_agent AND b.idempotency_key = p_key;
        IF FOUND THEN RETURN v_id; END IF;
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SUPPORT_REASON_SHORT: say why the passwords are reset, in 10 characters or more' USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_resolve, false) AND length(btrim(coalesce(p_resolution, ''))) < 20 THEN
        RAISE EXCEPTION 'BULK_RESOLUTION_SHORT: say what the students read on their resolved tickets, in 20 characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_retry_of IS NOT NULL AND NOT EXISTS (SELECT 1 FROM helpdesk.bulk_reset b WHERE b.id = p_retry_of AND (p_head OR b.initiated_by = p_agent)) THEN
        RAISE EXCEPTION 'BULK_RETRY_NOT_YOURS: only the one who made a bulk reset, the Head of the Support Desk or the Director of ICT tries its students again'
            USING ERRCODE = '23514';
    END IF;
    SELECT count(DISTINCT x) INTO v_n FROM unnest(p_students) x WHERE x IS NOT NULL;
    IF v_n = 0 THEN
        RAISE EXCEPTION 'BULK_RESET_EMPTY: choose the students to reset' USING ERRCODE = '23514';
    END IF;
    IF v_n > 1000 THEN
        RAISE EXCEPTION 'BULK_RESET_TOO_MANY: at most 1,000 students in one operation (% chosen); reset them in parts', v_n USING ERRCODE = '23514';
    END IF;
    SELECT g.bulk_reset_approval_over INTO v_over FROM helpdesk.setting g WHERE g.row_no;
    v_wait := v_over IS NOT NULL AND v_n > v_over;
    v_ref := 'BPR/' || v_year || '/' || lpad(platform.next_number('BULK_PASSWORD_RESET', 'ICT_SUPPORT', v_year)::text, 6, '0');
    INSERT INTO helpdesk.bulk_reset (reference, initiated_by, office, head, reason, unlock, idempotency_key, total, status,
                                     resolve_tickets, resolution, retry_of, approval_over)
    VALUES (v_ref, p_agent, p_office, p_head, btrim(p_reason), coalesce(p_unlock, true), p_key, v_n,
            CASE WHEN v_wait THEN 'AWAITING_APPROVAL' ELSE 'PENDING' END,
            coalesce(p_resolve, false), CASE WHEN coalesce(p_resolve, false) THEN btrim(p_resolution) END, p_retry_of,
            CASE WHEN v_wait THEN v_over END)
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
    IF v_wait THEN
        PERFORM helpdesk.tell_bulk_approvers(v_id);
    END IF;
    RETURN v_id;
END $fn$;
COMMENT ON FUNCTION helpdesk.start_bulk_reset(uuid, text, boolean, uuid[], jsonb, text, boolean, text, boolean, text, uuid) IS
  'V559, V563: a bulk password reset opened for the students chosen (at most 1,000), each student''s login ticket kept where given, the tickets resolved with it when asked, a retry of another''s students, waiting for approval above the figure in ICT Support Settings; the same key again is the same operation';

-- a large bulk reset approved (it runs) or declined on a reason (no student is reset), by a Head other than the one who asked
CREATE FUNCTION helpdesk.decide_bulk_reset(p_bulk uuid, p_person uuid, p_head boolean, p_approve boolean, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE b helpdesk.bulk_reset; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_status text;
BEGIN
    SELECT * INTO b FROM helpdesk.bulk_reset WHERE id = p_bulk FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no bulk password reset %', p_bulk USING ERRCODE = 'no_data_found'; END IF;
    IF NOT coalesce(p_head, false) THEN
        RAISE EXCEPTION 'BULK_APPROVAL_HEAD: a large bulk reset is approved by the Head of the ICT Support Desk or the Director of ICT' USING ERRCODE = '23514';
    END IF;
    IF b.initiated_by = p_person THEN
        RAISE EXCEPTION 'BULK_APPROVAL_OWN: a bulk reset is approved by another person than the one who asked for it' USING ERRCODE = '23514';
    END IF;
    IF b.status <> 'AWAITING_APPROVAL' THEN
        RAISE EXCEPTION 'BULK_APPROVAL_DECIDED: this bulk reset is no longer waiting for approval (it is %)', lower(replace(b.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    IF NOT p_approve AND length(coalesce(v_note, '')) < 10 THEN
        RAISE EXCEPTION 'SUPPORT_REASON_SHORT: say why the bulk reset is declined, in 10 characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_approve THEN
        UPDATE helpdesk.bulk_reset SET status = 'PENDING', decided_by = p_person, decided_at = now(), decision_note = v_note WHERE id = p_bulk;
        v_status := 'PENDING';
    ELSE
        UPDATE helpdesk.bulk_reset_item SET status = 'FAILED', failure_code = 'REJECTED', failure_words = 'NOT APPROVED — ' || v_note, processed_at = now()
         WHERE bulk_id = p_bulk AND status = 'PENDING';
        UPDATE helpdesk.bulk_reset SET status = 'REJECTED', decided_by = p_person, decided_at = now(), decision_note = v_note,
               succeeded = 0, failed = total, completed_at = now()
         WHERE id = p_bulk;
        v_status := 'REJECTED';
    END IF;
    PERFORM platform.tell_person(b.initiated_by, 'BULK_RESET_DECIDED', NULL,
        jsonb_build_object('REFERENCE', b.reference, 'COUNT', b.total::text, 'DECISION', CASE WHEN p_approve THEN 'approved' ELSE 'declined' END,
                           'DECIDER', coalesce(helpdesk.person_name(p_person), 'the Head of the ICT Support Desk'),
                           'NOTE', CASE WHEN v_note IS NULL THEN '' ELSE ' ' || CASE WHEN p_approve THEN 'Note: ' ELSE 'Reason: ' END || v_note END,
                           'NEXT', CASE WHEN p_approve THEN 'The students are being reset now; the result is on the operation''s record under Bulk Password Reset.'
                                        ELSE 'No student was reset.' END),
        'bulk-reset-decided:' || p_bulk);
    RETURN v_status;
END $fn$;
COMMENT ON FUNCTION helpdesk.decide_bulk_reset(uuid, uuid, boolean, boolean, text) IS
  'V563: a bulk password reset waiting for approval approved (it runs) or declined on a reason (no student reset), by a Head other than the one who asked; the one who asked is told';

-- the counts and state of an operation (restated from V559's text): a cancelled or declined one keeps its state
CREATE OR REPLACE FUNCTION helpdesk.bulk_reset_tally(p_bulk uuid)
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
    -- a cancelled or declined operation keeps its state, and one waiting for approval waits; the counts follow the students
    UPDATE helpdesk.bulk_reset
       SET succeeded = v_ok, failed = v_bad,
           status = CASE WHEN status IN ('CANCELLED', 'REJECTED', 'AWAITING_APPROVAL') THEN status ELSE v_status END,
           started_at = CASE WHEN status = 'AWAITING_APPROVAL' THEN started_at ELSE coalesce(started_at, now()) END,
           completed_at = CASE WHEN v_pending = 0 AND status <> 'AWAITING_APPROVAL' THEN coalesce(completed_at, now()) ELSE completed_at END
     WHERE id = p_bulk
    RETURNING status INTO v_status;
    RETURN v_status;
END $fn$;

-- the reset desk's counts (restated from V559's text): bulk resets waiting for approval, and the figure above which one waits
CREATE OR REPLACE FUNCTION helpdesk.reset_desk_summary(p_agent uuid, p_head boolean)
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
        -- for a Head, those another asked for (theirs to decide); for an agent, their own
        'awaitingApproval', (SELECT count(*) FROM helpdesk.bulk_reset x WHERE x.status = 'AWAITING_APPROVAL'
                               AND CASE WHEN p_head THEN x.initiated_by <> p_agent ELSE x.initiated_by = p_agent END),
        'approvalOver', (SELECT g.bulk_reset_approval_over FROM helpdesk.setting g WHERE g.row_no),
        'mayBulk', p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR cardinality(sc.faculties) > 0 OR cardinality(sc.departments) > 0),
        'scope', CASE WHEN p_head THEN 'The University' ELSE (SELECT sc.words FROM sc) END)
$fn$;
COMMENT ON FUNCTION helpdesk.reset_desk_summary(uuid, boolean) IS
  'V559, V563: the reset desk''s counts within the reader''s reach — students with an open login issue the reader works, resets today, bulk resets today, students reset and failed in them, bulk resets waiting for approval — whether the reader may bulk-reset, over what, and the figure above which one waits';

COMMIT;

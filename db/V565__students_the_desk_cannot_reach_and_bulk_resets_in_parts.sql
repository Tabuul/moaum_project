-- V565: the students the ICT Support Desk cannot reach, and a bulk password reset of more than 1,000 students in parts.
--
--   * A student's ticket may carry a phone where the record holds no e-mail (helpdesk.submit, restated from its current text):
--     29% of the active students on the live-shaped copy have no e-mail on record, and the desk could not raise a ticket for any of
--     them ("The record holds no email address for the ticket's updates"). The updates of such a ticket go by SMS (the API's
--     TicketNotifier); a ticket raised from the sign-in page (PUBLIC) or by staff still needs an e-mail, which its tracking page reads.
--   * helpdesk.reach_gaps(agent, head): within the reader's reach, the current students (active, on probation, admitted, deferred)
--     the University has no e-mail for, no phone for, and neither — by faculty — for the desk's "Students we cannot reach" list.
--   * A bulk password reset of more students than one operation holds (1,000) is opened as consecutive parts, each with its own
--     reference, run one after another (helpdesk.bulk_reset.series_id, part, parts): up to 10,000 students in one request. A large
--     one waits for approval as a whole (the figure is read against every student chosen), is approved or declined as a whole, and
--     is told to the Head once (helpdesk.start_bulk_reset, decide_bulk_reset, tell_bulk_approvers and reset_desk_summary restated
--     from V563's text).

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V565: students the desk cannot reach; bulk resets in parts', true);

-- ── a student's ticket reached by phone where the record holds no e-mail ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.submit(p_kind text, p_requester uuid, p_name text, p_number text, p_email text, p_phone text, p_dept text, p_faculty text, p_category text, p_subject text, p_description text, p_details jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE c helpdesk.category; f jsonb; v uuid := gen_random_uuid(); v_number text; n_open int; tries int := 0;
        v_email text := nullif(lower(btrim(coalesce(p_email, ''))), ''); v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
BEGIN
    SELECT * INTO c FROM helpdesk.category WHERE code = upper(btrim(p_category));
    IF NOT FOUND OR NOT c.active THEN
        RAISE EXCEPTION 'that category is not open for new tickets' USING ERRCODE = '23514', HINT = 'Choose one of the categories offered.';
    END IF;
    IF p_subject IS NULL OR btrim(p_subject) = '' THEN RAISE EXCEPTION 'a ticket has a subject' USING ERRCODE = '23514', HINT = 'Say what the problem is, in one line.'; END IF;
    IF p_description IS NULL OR btrim(p_description) = '' THEN RAISE EXCEPTION 'a ticket describes the problem' USING ERRCODE = '23514', HINT = 'Describe what happened and what you expected.'; END IF;
    -- V565: a student's ticket may be reached by phone alone (its updates go by SMS; the student reads it signed in); any other
    -- ticket carries the e-mail its tracking page reads
    IF v_email IS NULL AND NOT (p_kind = 'STUDENT' AND v_phone IS NOT NULL) THEN
        RAISE EXCEPTION 'a ticket carries an email address the desk can reach' USING ERRCODE = '23514',
            HINT = CASE WHEN p_kind = 'STUDENT' THEN 'Give an email address or a phone number; the ticket''s updates go there.'
                        ELSE 'Give an email address; the ticket''s updates and the public tracking page use it.' END;
    END IF;
    FOR f IN SELECT * FROM jsonb_array_elements(c.fields) LOOP
        IF coalesce((f->>'required')::boolean, false) AND coalesce(f->>'type', 'text') <> 'file'
           AND btrim(coalesce(p_details->>(f->>'key'), '')) = '' THEN
            RAISE EXCEPTION '% is required for a % ticket', f->>'label', c.name USING ERRCODE = '23514', HINT = 'Fill it in and submit again.';
        END IF;
    END LOOP;
    SELECT count(*) INTO n_open FROM helpdesk.ticket WHERE requester_kind = p_kind AND requester_id = p_requester AND status <> 'CLOSED';
    IF n_open >= 10 THEN
        RAISE EXCEPTION 'ten tickets are open already' USING ERRCODE = '23514', HINT = 'Wait for an answer on one of them, or close one you no longer need, before raising another.';
    END IF;
    LOOP
        v_number := helpdesk.new_number();
        BEGIN
            INSERT INTO helpdesk.ticket (id, number, category_id, subject, description, priority, requester_kind, requester_id, requester_name, requester_number,
                                         requester_email, requester_phone, department_code, faculty_code, details)
            VALUES (v, v_number, c.id, btrim(p_subject), btrim(p_description), c.suggested_priority, p_kind, p_requester, p_name, nullif(btrim(coalesce(p_number, '')), ''),
                    v_email, v_phone, p_dept, p_faculty, coalesce(p_details, '{}'::jsonb));
            EXIT;
        EXCEPTION WHEN unique_violation THEN
            tries := tries + 1;
            IF tries >= 10 THEN RAISE; END IF;
        END;
    END LOOP;
    PERFORM helpdesk.record(v, 'REQUESTER', p_requester, p_name, 'SUBMITTED', NULL, 'SUBMITTED', c.name || ' · ' || btrim(p_subject));
    RETURN v;
END $function$;

-- ── the students the desk cannot reach ──────────────────────────────────────────────────────────────────────────────────────
-- where the University reaches a student, read as people.student_reach reads it (the contact the student gave, else the applicant
-- account's), for every current student within the reader's reach at once; counted by faculty
CREATE FUNCTION helpdesk.reach_gaps(p_agent uuid, p_head boolean)
RETURNS TABLE (faculty_code text, faculty text, students bigint, no_email bigint, no_phone bigint, neither bigint)
LANGUAGE sql STABLE AS $fn$
    WITH sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(p_agent, 'VIEW_STUDENT')),
    r AS (
        SELECT p.faculty_code, nullif(btrim(coalesce(c.email, a.email, '')), '') IS NULL AS no_email,
               nullif(btrim(coalesce(c.phone, a.phone, '')), '') IS NULL AS no_phone
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN people.student_contact c ON c.student_id = s.id
          LEFT JOIN admissions.applicant_account a ON a.candidate_id = s.candidate_id
         WHERE s.duplicate_of IS NULL AND s.status IN ('ACTIVE', 'PROBATION', 'ADMITTED', 'DEFERRED')
           AND (p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY (sc.faculties) OR p.dept_code = ANY (sc.departments))))
    SELECT r.faculty_code, f.name, count(*), count(*) FILTER (WHERE r.no_email), count(*) FILTER (WHERE r.no_phone),
           count(*) FILTER (WHERE r.no_email AND r.no_phone)
      FROM r LEFT JOIN ref.faculty f ON f.code = r.faculty_code
     GROUP BY r.faculty_code, f.name
     ORDER BY count(*) FILTER (WHERE r.no_email AND r.no_phone) DESC, f.name
$fn$;
COMMENT ON FUNCTION helpdesk.reach_gaps(uuid, boolean) IS
  'V565: within the reader''s reach, the current students the University holds no e-mail for, no phone for, and neither, by faculty (the contact the student gave, else the applicant account''s)';

-- ── a bulk reset of more than 1,000 students, in parts ──────────────────────────────────────────────────────────────────────
-- the figure for approval may be any up to the 10,000 one request now holds
ALTER TABLE helpdesk.setting
    DROP CONSTRAINT ck_hd_setting_bulk_approval,
    ADD CONSTRAINT ck_hd_setting_bulk_approval CHECK (bulk_reset_approval_over IS NULL OR bulk_reset_approval_over BETWEEN 1 AND 10000);

ALTER TABLE helpdesk.bulk_reset
    ADD COLUMN series_id uuid REFERENCES helpdesk.bulk_reset (id) ON DELETE CASCADE,
    ADD COLUMN part      integer,
    ADD COLUMN parts     integer,
    ADD CONSTRAINT ck_bulk_reset_part CHECK ((series_id IS NULL) = (part IS NULL) AND (part IS NULL) = (parts IS NULL) AND (part IS NULL OR part BETWEEN 1 AND parts));
CREATE INDEX ix_bulk_reset_series ON helpdesk.bulk_reset (series_id);
COMMENT ON COLUMN helpdesk.bulk_reset.series_id IS 'V565: the first part of a bulk reset opened in parts (its own id on the first part); NULL for one of 1,000 or fewer';

-- the operation opened (restated from V563's text): more than 1,000 students become parts of 1,000, in the order chosen
CREATE OR REPLACE FUNCTION helpdesk.start_bulk_reset(p_agent uuid, p_office text, p_head boolean, p_students uuid[], p_tickets jsonb, p_reason text,
                                                     p_unlock boolean, p_key text, p_resolve boolean DEFAULT false, p_resolution text DEFAULT NULL,
                                                     p_retry_of uuid DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql AS $fn$
DECLARE v_id uuid; v_first uuid; v_ids uuid[]; v_n int; v_parts int; v_part int; v_ref text; v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY');
        v_over int; v_wait boolean; c_part constant int := 1000;
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
    -- each student once, at the place first chosen
    v_ids := ARRAY(SELECT s.x FROM unnest(p_students) WITH ORDINALITY s(x, o) WHERE s.x IS NOT NULL GROUP BY s.x ORDER BY min(s.o));
    v_n := coalesce(cardinality(v_ids), 0);
    IF v_n = 0 THEN
        RAISE EXCEPTION 'BULK_RESET_EMPTY: choose the students to reset' USING ERRCODE = '23514';
    END IF;
    IF v_n > 10 * c_part THEN
        RAISE EXCEPTION 'BULK_RESET_TOO_MANY: at most 10,000 students in one request (% chosen); reset them in two', v_n USING ERRCODE = '23514';
    END IF;
    -- the figure for approval is read against every student chosen: a request in parts waits, and is decided, as a whole
    SELECT g.bulk_reset_approval_over INTO v_over FROM helpdesk.setting g WHERE g.row_no;
    v_wait := v_over IS NOT NULL AND v_n > v_over;
    v_parts := (v_n + c_part - 1) / c_part;
    FOR v_part IN 1 .. v_parts LOOP
        v_ref := 'BPR/' || v_year || '/' || lpad(platform.next_number('BULK_PASSWORD_RESET', 'ICT_SUPPORT', v_year)::text, 6, '0');
        v_id := gen_random_uuid();
        INSERT INTO helpdesk.bulk_reset (id, reference, initiated_by, office, head, reason, unlock, idempotency_key, total, status,
                                         resolve_tickets, resolution, retry_of, approval_over, series_id, part, parts)
        VALUES (v_id, v_ref, p_agent, p_office, p_head, btrim(p_reason), coalesce(p_unlock, true),
                CASE WHEN p_key IS NULL THEN NULL WHEN v_part = 1 THEN p_key ELSE p_key || ':' || v_part END, least(c_part, v_n - (v_part - 1) * c_part),
                CASE WHEN v_wait THEN 'AWAITING_APPROVAL' ELSE 'PENDING' END,
                coalesce(p_resolve, false), CASE WHEN coalesce(p_resolve, false) THEN btrim(p_resolution) END, p_retry_of,
                CASE WHEN v_wait THEN v_over END,
                CASE WHEN v_parts > 1 THEN coalesce(v_first, v_id) END, CASE WHEN v_parts > 1 THEN v_part END, CASE WHEN v_parts > 1 THEN v_parts END);
        v_first := coalesce(v_first, v_id);
        -- one item a student of this part, in the order chosen, with the login ticket named for it; an id that names no student is
        -- counted as failed by the tally (the total is of every id chosen), never skipped in silence
        INSERT INTO helpdesk.bulk_reset_item (bulk_id, student_id, ticket_id, ord)
        SELECT v_id, b.x, t.id, row_number() OVER (ORDER BY b.o)
          FROM unnest(v_ids[(v_part - 1) * c_part + 1 : v_part * c_part]) WITH ORDINALITY b(x, o)
          LEFT JOIN helpdesk.ticket t ON t.id = CASE WHEN (p_tickets ->> b.x::text) ~ '^[0-9a-fA-F-]{36}$' THEN (p_tickets ->> b.x::text)::uuid END
         WHERE EXISTS (SELECT 1 FROM people.student st WHERE st.id = b.x);
    END LOOP;
    IF v_wait THEN
        PERFORM helpdesk.tell_bulk_approvers(v_first);
    END IF;
    RETURN v_first;
END $fn$;
COMMENT ON FUNCTION helpdesk.start_bulk_reset(uuid, text, boolean, uuid[], jsonb, text, boolean, text, boolean, text, uuid) IS
  'V559, V563, V565: a bulk password reset opened for the students chosen (up to 10,000, in parts of 1,000 run one after another), each student''s login ticket kept where given, the tickets resolved with it when asked, a retry of another''s students, waiting for approval as a whole above the figure in ICT Support Settings; the same key again is the same request (its first part returned)';

-- the Head told once of a bulk reset waiting, a request in parts as a whole (restated from V563's text)
CREATE OR REPLACE FUNCTION helpdesk.tell_bulk_approvers(p_bulk uuid)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE b record; v_day date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_vars jsonb; p record; v_told int := 0;
BEGIN
    SELECT x.id, x.reference, x.reason, x.approval_over, x.initiated_by, x.parts, helpdesk.person_name(x.initiated_by) AS who,
           (SELECT sum(y.total) FROM helpdesk.bulk_reset y WHERE coalesce(y.series_id, y.id) = coalesce(x.series_id, x.id)) AS total
      INTO b FROM helpdesk.bulk_reset x WHERE x.id = p_bulk;
    IF NOT FOUND THEN RETURN 0; END IF;
    v_vars := jsonb_build_object('AGENT', coalesce(b.who, 'An agent'), 'COUNT', b.total::text,
                                 'REFERENCE', b.reference || CASE WHEN b.parts > 1 THEN ' (in ' || b.parts || ' parts)' ELSE '' END,
                                 'REASON', b.reason, 'OVER', coalesce(b.approval_over::text, ''));
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

-- approved or declined (restated from V563's text): every part of a request decided with it
CREATE OR REPLACE FUNCTION helpdesk.decide_bulk_reset(p_bulk uuid, p_person uuid, p_head boolean, p_approve boolean, p_note text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE b helpdesk.bulk_reset; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_status text; v_series uuid; v_total int; v_first text;
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
    v_series := coalesce(b.series_id, b.id);
    PERFORM 1 FROM helpdesk.bulk_reset x WHERE coalesce(x.series_id, x.id) = v_series FOR UPDATE;
    SELECT sum(x.total), min(x.reference) INTO v_total, v_first FROM helpdesk.bulk_reset x WHERE coalesce(x.series_id, x.id) = v_series;
    IF p_approve THEN
        UPDATE helpdesk.bulk_reset SET status = 'PENDING', decided_by = p_person, decided_at = now(), decision_note = v_note
         WHERE coalesce(series_id, id) = v_series AND status = 'AWAITING_APPROVAL';
        v_status := 'PENDING';
    ELSE
        UPDATE helpdesk.bulk_reset_item i SET status = 'FAILED', failure_code = 'REJECTED', failure_words = 'NOT APPROVED — ' || v_note, processed_at = now()
          FROM helpdesk.bulk_reset x
         WHERE x.id = i.bulk_id AND coalesce(x.series_id, x.id) = v_series AND x.status = 'AWAITING_APPROVAL' AND i.status = 'PENDING';
        UPDATE helpdesk.bulk_reset SET status = 'REJECTED', decided_by = p_person, decided_at = now(), decision_note = v_note,
               succeeded = 0, failed = total, completed_at = now()
         WHERE coalesce(series_id, id) = v_series AND status = 'AWAITING_APPROVAL';
        v_status := 'REJECTED';
    END IF;
    PERFORM platform.tell_person(b.initiated_by, 'BULK_RESET_DECIDED', NULL,
        jsonb_build_object('REFERENCE', v_first || CASE WHEN b.parts > 1 THEN ' (in ' || b.parts || ' parts)' ELSE '' END, 'COUNT', v_total::text,
                           'DECISION', CASE WHEN p_approve THEN 'approved' ELSE 'declined' END,
                           'DECIDER', coalesce(helpdesk.person_name(p_person), 'the Head of the ICT Support Desk'),
                           'NOTE', CASE WHEN v_note IS NULL THEN '' ELSE ' ' || CASE WHEN p_approve THEN 'Note: ' ELSE 'Reason: ' END || v_note END,
                           'NEXT', CASE WHEN p_approve THEN 'The students are being reset now; the result is on the operation''s record under Bulk Password Reset.'
                                        ELSE 'No student was reset.' END),
        'bulk-reset-decided:' || v_series);
    RETURN v_status;
END $fn$;
COMMENT ON FUNCTION helpdesk.decide_bulk_reset(uuid, uuid, boolean, boolean, text) IS
  'V563, V565: a bulk password reset waiting for approval — every part of the request — approved (it runs) or declined on a reason (no student reset), by a Head other than the one who asked; the one who asked is told once';

-- the reset desk's counts (restated from V563's text): a request in parts waits as one
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
        'bulkToday', (SELECT count(DISTINCT coalesce(b.series_id, b.id)) FROM b),
        'studentsResetToday', (SELECT coalesce(sum(b.succeeded), 0) FROM b),
        'failedToday', (SELECT coalesce(sum(b.failed), 0) FROM b),
        -- for a Head, those another asked for (theirs to decide); for an agent, their own — a request in parts as one
        'awaitingApproval', (SELECT count(DISTINCT coalesce(x.series_id, x.id)) FROM helpdesk.bulk_reset x WHERE x.status = 'AWAITING_APPROVAL'
                               AND CASE WHEN p_head THEN x.initiated_by <> p_agent ELSE x.initiated_by = p_agent END),
        'approvalOver', (SELECT g.bulk_reset_approval_over FROM helpdesk.setting g WHERE g.row_no),
        'mayBulk', p_head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR cardinality(sc.faculties) > 0 OR cardinality(sc.departments) > 0),
        'scope', CASE WHEN p_head THEN 'The University' ELSE (SELECT sc.words FROM sc) END)
$fn$;

COMMIT;

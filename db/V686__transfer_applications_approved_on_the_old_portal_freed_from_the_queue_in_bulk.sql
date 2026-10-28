-- ═══════════════════════════════════════
-- V686 — Transfer applications approved on the old portal freed from the queue in bulk, each student moved to the programme applied for
--
-- The University's word of 28 October 2026: "students that applied for departmental transfer and were confirmed on the old portal, are
-- still queue up for the process again, i want all this to be freed so they can be easily moved to their respective department without
-- passing through the process of approvals again, so display all the list of student that apply for inter departmental transfer and
-- remove them from the queue".
--
-- V669 restored a transfer the old portal approved — the student put on the programme they transferred to, the number unchanged, the
-- transfer recorded in the history, an application left in the queue for it withdrawn, no application, fee or approval made
-- (people.restore_approved_transfer) — but one student at a time from the programme swap, or from an upload file naming each student,
-- the programme and the level again. The students the Academic Office had sent back into the queue (V669: the desk's only tool was
-- "Record an application") sat there at the current department's desk, each to pass the four approvals again.
--
-- Now people.free_old_portal_transfers(applications, reason, reference, approved on): for each application chosen from the queue (one
-- not yet effected, declined or withdrawn), the student is restored onto the programme the application names, at the level they are
-- at, by people.restore_approved_transfer — the application withdrawn with the reason, the old portal's transfer recorded (its
-- session the application's, where it is on the calendar), no approval, fee or new application; a student already on that programme has the transfer recorded only.
-- Each application is its own step: one refused (the swap's checks, an application no longer in the queue, one not found) leaves the
-- others done, and is answered with its reason. The Academic Office, the Registry or the Director of ICT (as the restoration), up to
-- 2,000 at a time. The transfer desk lists every application, the ones in the queue together, with Free from the queue.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V686: transfer applications approved on the old portal freed from the queue in bulk (the University, 28 October 2026)', true);

CREATE FUNCTION people.free_old_portal_transfers(p_applications uuid[], p_reason text, p_reference text, p_approved_on date)
RETURNS TABLE(application_id uuid, student_id uuid, matric_no text, name text, from_programme text, to_programme text, to_level integer,
              outcome text, swap_ref text, detail text)
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        v_reason text := btrim(coalesce(p_reason, '')); v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
        a record; res jsonb; v_err text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PTR_ACTOR: an approved transfer is restored by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'PTR_OFFICE: an approved transfer is restored by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(v_reason) < 10 THEN
        RAISE EXCEPTION 'PTR_REASON: say why the applications leave the queue (the old portal''s approval, the memo), in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_applications IS NULL OR cardinality(p_applications) = 0 THEN
        RAISE EXCEPTION 'PTQ_NONE: choose the applications the old portal approved' USING ERRCODE = '23514';
    END IF;
    IF cardinality(p_applications) > 2000 THEN
        RAISE EXCEPTION 'PTQ_MANY: free up to 2,000 applications at a time' USING ERRCODE = '23514';
    END IF;
    IF p_approved_on IS NOT NULL AND p_approved_on > (now() AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'PTR_APPROVED_ON: the transfers cannot have been approved in the future' USING ERRCODE = '23514';
    END IF;
    -- each application once, in the order chosen
    FOR a IN
        SELECT x.* FROM (
            SELECT DISTINCT ON (u.id) u.id AS asked, u.n, t.id, t.student_id, t.state, t.session, t.from_programme_code, t.to_programme_code,
                   s.matric_no, s.surname || ', ' || s.other_names AS name, s.current_level, fp.name AS from_name, tp.name AS to_name
              FROM unnest(p_applications) WITH ORDINALITY u(id, n)
              LEFT JOIN people.transfer_application t ON t.id = u.id
              LEFT JOIN people.student s ON s.id = t.student_id
              LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code
              LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
             ORDER BY u.id, u.n) x
         ORDER BY x.n
    LOOP
        application_id := a.asked; student_id := a.student_id; matric_no := a.matric_no; name := a.name;
        from_programme := coalesce(a.from_name, a.from_programme_code); to_programme := coalesce(a.to_name, a.to_programme_code); to_level := a.current_level;
        swap_ref := NULL; detail := NULL;
        IF a.id IS NULL THEN
            outcome := 'REFUSED'; detail := 'PTQ_NOT_FOUND: no such transfer application';
        ELSIF a.state NOT IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED') THEN
            outcome := 'REFUSED'; detail := 'PTQ_NOT_QUEUED: the application is ' || lower(replace(a.state, '_', ' ')) || ', not in the queue';
        ELSE
            BEGIN
                -- the transfer's session the application's, where it is a session of the University (else the restoration's own)
                res := people.restore_approved_transfer(a.student_id, a.to_programme_code, a.current_level, NULL, v_reason, a.from_programme_code,
                                                        CASE WHEN EXISTS (SELECT 1 FROM policy.academic_session z WHERE z.name = a.session) THEN a.session END,
                                                        NULL, p_approved_on, v_ref, NULL);
                -- this application leaves the queue, whichever of the student's was the latest
                UPDATE people.transfer_application x SET state = 'WITHDRAWN',
                       withdrawn_why = 'Withdrawn by the ' || initcap(office) || ' office: the transfer was approved on the old portal'
                                       || coalesce(' (' || v_ref || ')', '') || ' and is restored without a new application'
                 WHERE x.id = a.id AND x.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED');
                outcome := CASE WHEN (res ->> 'recordOnly')::boolean THEN 'RECORDED' ELSE 'MOVED' END;
                swap_ref := res ->> 'swapRef';
            EXCEPTION WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
                outcome := 'REFUSED'; detail := v_err; swap_ref := NULL;
            END;
        END IF;
        RETURN NEXT;
    END LOOP;
END $fn$;
COMMENT ON FUNCTION people.free_old_portal_transfers(uuid[], text, text, date) IS
  'V686: transfer applications the old portal approved, freed from the queue together — each student restored onto the programme their application names, at the level they are at, by people.restore_approved_transfer (V669: the number unchanged, the transfer recorded with the application''s session, the application withdrawn with the reason; no approval, fee or new application; a student already on it recorded only). Each application its own step: MOVED, RECORDED or REFUSED with the reason (PTQ_NOT_FOUND, PTQ_NOT_QUEUED, the swap''s checks). The Academic Office, the Registry or the Director of ICT; up to 2,000 at a time.';

COMMIT;

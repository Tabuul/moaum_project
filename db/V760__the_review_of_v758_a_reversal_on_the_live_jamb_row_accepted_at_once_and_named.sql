-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V760 · The review of V758: a reversal on the live JAMB row, accepted at once, and named
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The second review of V758 (an applicant's accidental decline reversed by the Academic Office) confirmed:
--    · a candidate whose JAMB list was withdrawn and re-uploaded while the offer stood declined kept admitted_from on the withdrawn
--      row; the reversal now re-links the candidate to the live row of the re-uploaded list, so a later withdrawal of that list
--      still finds the candidate (and its guard on admission numbers holds);
--    · a reversal whose undertaking was signed and acceptance fee completed while the offer stood declined accepts it at once (V758):
--      it no longer asks for a new acceptance date, and the applicant is told once that the offer is restored and accepted — never
--      "accept by" a date;
--    · the programme the reversal restores (the Board's offer, where JAMB's course was followed meanwhile) is named on the screen
--      before the officer confirms (admissions.declines_reversible), in the answer, and to the applicant;
--    · admissions.sign_undertaking's hint, met on a page left open after a decline, says how a decline made by mistake is put right
--      instead of "never reinstated";
--    · admissions.follow_caps_course reads the offer again under its lock before moving a candidate to JAMB's course: a decline
--      reversed meanwhile makes the offer stand, and it is left as offered.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V760: the review of V758 applied', true);

DROP FUNCTION admissions.declines_reversible(text);
DROP FUNCTION admissions.decline_reversible(uuid);

-- whether a declined offer may be reversed now, why not, the programme it comes back on, and whether it is accepted at once
CREATE FUNCTION admissions.decline_reversible(p_app uuid)
RETURNS TABLE (reversible boolean, why text, deadline date, deadline_passed boolean, programme_restores text, completes boolean)
LANGUAGE sql STABLE AS $$
    SELECT w.why IS NULL, w.why,
           admissions.offer_deadline_of(a.id),
           coalesce(admissions.offer_deadline_of(a.id) < (now() AT TIME ZONE 'Africa/Lagos')::date, false),
           coalesce(f.from_programme, c.programme),
           coalesce(a.undertaking_at IS NOT NULL AND (SELECT e.settled FROM admissions.acceptance_entitlement(a.id) e), false)
      FROM (SELECT p_app AS id) k
      LEFT JOIN admissions.application a ON a.id = k.id
      LEFT JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN LATERAL (SELECT x.id, x.application_no, x.promoted_at FROM admissions.application x WHERE x.promoted_for = a.id
                          ORDER BY x.promoted_at LIMIT 1) p ON true
      -- JAMB's course followed while the offer stood declined: the offer comes back on the programme the Board offered
      LEFT JOIN LATERAL (SELECT q.from_programme FROM admissions.programme_change_request q
                          WHERE q.candidate_id = c.id AND q.reason_code = 'JAMB_CAPS' AND q.state = 'APPROVED' AND q.decided_at >= a.declined_at
                            AND q.from_programme IS NOT NULL
                          ORDER BY q.decided_at ASC LIMIT 1) f ON true
      CROSS JOIN LATERAL (SELECT CASE
                WHEN a.id IS NULL THEN 'DECLINE_REVERSAL_NO_APPLICATION: no such application'
                WHEN a.declined_at IS NULL THEN 'DECLINE_REVERSAL_NOT_DECLINED: the offer was not declined'
                WHEN a.decision IS DISTINCT FROM 'OFFERED' OR a.decision_released_at IS NULL THEN 'DECLINE_REVERSAL_NO_OFFER: there is no released offer to restore'
                WHEN a.accepted_at IS NOT NULL THEN 'DECLINE_REVERSAL_ACCEPTED: the offer was accepted'
                WHEN a.lapsed_at IS NOT NULL THEN 'DECLINE_REVERSAL_LAPSED: the offer lapsed'
                WHEN p.id IS NOT NULL THEN 'DECLINE_REVERSAL_PLACE_FILLED: the place was given to ' || p.application_no || ' from the waiting list on '
                                           || to_char(p.promoted_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY')
                -- the JAMB list that admitted the candidate was withdrawn while the offer stood declined, and no list carries the
                -- candidate now: there is no admission to restore
                WHEN c.admitted_from IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM admissions.caps_row_live r WHERE r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no)
                     THEN 'DECLINE_REVERSAL_LIST_WITHDRAWN: the JAMB list that admitted the candidate was withdrawn while the offer stood declined'
                END AS why) w;
$$;

CREATE FUNCTION admissions.declines_reversible(p_session text)
RETURNS TABLE (application_id uuid, application_no text, name text, programme text, declined_at timestamptz, deadline date, deadline_passed boolean,
               programme_restores text, completes boolean)
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.application_no, upper(c.surname) || ', ' || c.other_names, c.programme, a.declined_at, r.deadline, r.deadline_passed,
           r.programme_restores, r.completes
      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
      CROSS JOIN LATERAL admissions.decline_reversible(a.id) r
     WHERE a.session = p_session AND a.declined_at IS NOT NULL AND r.reversible
     ORDER BY a.declined_at DESC;
$$;

CREATE OR REPLACE FUNCTION admissions.reverse_decline(p_app uuid, p_reason text, p_accept_by date DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a admissions.application; c admissions.candidate; r record;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_was text; v_now text; v_prog_was text; v_prog_now text; v_from uuid; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
        v_deadline date; v_accept_by date := p_accept_by; v_accepted boolean;
BEGIN
    IF v_actor IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'DECLINE_REVERSAL_OFFICE: a decline is reversed by the Academic Office or the Registrar''s office' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL OR length(v_reason) < 20 THEN
        RAISE EXCEPTION 'DECLINE_REVERSAL_REASON: say why (the applicant''s request and how it was received), at least 20 characters' USING ERRCODE = '23514';
    END IF;
    -- the offer locked first: a waiting-list promotion of this place, or a JAMB-course follow, waits for the reversal and reads it
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    SELECT * INTO r FROM admissions.decline_reversible(p_app);
    IF NOT r.reversible THEN
        RAISE EXCEPTION '%', r.why USING ERRCODE = CASE WHEN a.id IS NULL THEN '23503' ELSE '23514' END;
    END IF;
    IF r.completes THEN
        -- the undertaking signed and the acceptance fee completed while it stood declined: accepted at once, no date asked
        v_accept_by := NULL;
    ELSE
        -- the acceptance date: the session's while it runs; once passed, the officer's new date (and only then)
        IF r.deadline_passed AND v_accept_by IS NULL THEN
            RAISE EXCEPTION 'DECLINE_REVERSAL_DEADLINE: the acceptance deadline (%) has passed; give a new acceptance date for this offer', to_char(r.deadline, 'FMDD Mon YYYY')
                  USING ERRCODE = '23514';
        END IF;
        IF v_accept_by IS NOT NULL AND NOT r.deadline_passed THEN
            RAISE EXCEPTION 'DECLINE_REVERSAL_DATE: a new acceptance date is given only once the acceptance deadline has passed' USING ERRCODE = '23514';
        END IF;
        IF v_accept_by IS NOT NULL AND v_accept_by < v_today THEN
            RAISE EXCEPTION 'DECLINE_REVERSAL_DATE: the new acceptance date is in the past' USING ERRCODE = '23514';
        END IF;
        IF v_accept_by IS NOT NULL AND v_accept_by > v_today + 120 THEN
            RAISE EXCEPTION 'DECLINE_REVERSAL_DATE: a new acceptance date is at most 120 days away' USING ERRCODE = '23514';
        END IF;
    END IF;
    -- the officer's reason on the audit trail of every row changed
    PERFORM set_config('moaum.reason', left('Decline reversed: ' || v_reason, 1000), true);
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id FOR UPDATE;
    v_was := c.offer_state;
    v_prog_was := c.programme;
    -- the state before the decline, from the audit trail (the decline set DECLINED from PROPOSED or ADMITTED)
    IF c.offer_state = 'DECLINED' THEN
        SELECT e.before_state ->> 'offer_state' INTO v_now
          FROM audit.entries e
         WHERE e.subject_type = 'admissions.candidate' AND e.subject_id = c.id
           AND e.after_state ->> 'offer_state' = 'DECLINED' AND e.before_state ->> 'offer_state' IN ('PROPOSED', 'ADMITTED')
         ORDER BY e.occurred_at DESC LIMIT 1;
        v_now := coalesce(v_now, CASE WHEN c.admitted_from IS NOT NULL THEN 'ADMITTED' ELSE 'PROPOSED' END);
    ELSE
        v_now := c.offer_state;
    END IF;
    -- the programme the Board offered, where JAMB's course was followed while the offer stood declined (V636; the difference from
    -- CAPS then corrected on Programme Changes, V757)
    v_prog_now := r.programme_restores;
    -- the JAMB row: a list withdrawn and re-uploaded while the offer stood declined — the candidate re-linked to the live row
    v_from := c.admitted_from;
    IF c.admitted_from IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admissions.caps_row_live x WHERE x.id = c.admitted_from) THEN
        SELECT x.id INTO v_from FROM admissions.caps_row_live x WHERE x.session = c.session AND x.jamb_reg_no = c.jamb_reg_no LIMIT 1;
    END IF;
    UPDATE admissions.candidate SET offer_state = v_now, programme = v_prog_now, admitted_from = v_from
     WHERE id = c.id
       AND (offer_state IS DISTINCT FROM v_now OR programme IS DISTINCT FROM v_prog_now OR admitted_from IS DISTINCT FROM v_from);
    UPDATE admissions.application SET declined_at = NULL, own_accept_by = coalesce(v_accept_by, own_accept_by) WHERE id = a.id;
    INSERT INTO admissions.decline_reversal (application_id, declined_at, offer_state_was, offer_state_now, programme_was, programme_now, own_accept_by,
                                             reason, reversed_by, reversed_office)
    VALUES (a.id, a.declined_at, v_was, v_now, v_prog_was, v_prog_now, v_accept_by, v_reason, v_actor, v_office);
    -- the undertaking signed and the acceptance fee confirmed while the offer stood declined: the offer is accepted now, as it would
    -- have been then (registered, screening opened, the applicant told by it)
    PERFORM admissions.settle_acceptance(a.id);
    v_accepted := (SELECT x.accepted_at IS NOT NULL FROM admissions.application x WHERE x.id = a.id);
    v_deadline := admissions.offer_deadline_of(a.id);
    IF v_accepted THEN
        PERFORM admissions.notify_applicant(a.id, 'Your admission offer for ' || a.session || ' is restored and accepted',
            'At your request the University has reversed the decline of your admission offer of ' || v_prog_now || ' for the ' || a.session
            || ' session. Your undertaking and acceptance fee were already complete, so the offer is accepted: read Admission Status on the applicant portal for what comes next.',
            'MOAUM: your admission offer (' || v_prog_now || ') for ' || a.session || ' is restored at your request and accepted. See Admission Status on the portal.');
    ELSE
        PERFORM admissions.notify_applicant(a.id, 'Your admission offer for ' || a.session || ' is restored',
            'At your request the University has reversed the decline of your admission offer of ' || v_prog_now || ' for the ' || a.session || ' session'
            || CASE WHEN v_prog_now IS DISTINCT FROM v_prog_was THEN ', the programme you were offered (JAMB''s change of course is reviewed separately)' ELSE '' END
            || '. The offer stands again: read it on the applicant portal under Admission Status, then accept it and pay the acceptance fee where you have not'
            || CASE WHEN v_deadline IS NOT NULL THEN ' by ' || to_char(v_deadline, 'FMDD FMMonth YYYY') ELSE '' END || '.',
            'MOAUM: your admission offer (' || v_prog_now || ') for ' || a.session || ' is restored at your request. See Admission Status on the portal'
            || CASE WHEN v_deadline IS NOT NULL THEN ' and accept by ' || to_char(v_deadline, 'FMDD Mon YYYY') ELSE '' END || '.');
    END IF;
    RETURN jsonb_build_object('outcome', 'REVERSED', 'applicationNo', a.application_no,
                              'offerState', (SELECT x.offer_state FROM admissions.candidate x WHERE x.id = c.id), 'accepted', v_accepted,
                              'programme', v_prog_now, 'programmeRestored', v_prog_now IS DISTINCT FROM v_prog_was,
                              'deadline', CASE WHEN v_accepted THEN NULL ELSE v_deadline END);
END $$;
COMMENT ON FUNCTION admissions.reverse_decline(uuid, text, date) IS
    'V758, V760: the Academic Office (or the Registrar''s office) reverses an applicant''s accidental decline while the place is free and a JAMB list carries the candidate (re-linked to the live row); a new acceptance date is required (and allowed) only once the session''s has passed, unless the undertaking and the fee are complete (then accepted at once); the candidate''s state and the programme offered restored, the reversal recorded with the reason, the applicant told once.';

-- the JAMB-course follow reads the offer again under its lock before it moves a candidate (a decline reversed meanwhile)
DO $$
DECLARE d text; anchor text := '        IF p_dry_run THEN CONTINUE; END IF;';
BEGIN
    d := pg_get_functiondef('admissions.follow_caps_course(text,boolean)'::regprocedure);
    IF (length(d) - length(replace(d, anchor, ''))) / length(anchor) <> 1 THEN RAISE EXCEPTION 'V760: admissions.follow_caps_course is not as V636 left it'; END IF;
    EXECUTE replace(d, anchor, anchor || '
        -- V760: the offer read again under its lock: a decline reversed meanwhile (V758) makes it stand, and it is left as offered
        IF r.application_id IS NOT NULL THEN
            PERFORM 1 FROM admissions.application x WHERE x.id = r.application_id FOR UPDATE;
            IF admissions.offer_stands(r.application_id) THEN
                n_follow := n_follow - 1;
                n_left := n_left + 1;
                CONTINUE;
            END IF;
        END IF;');
END $$;

-- a page left open after a decline meets the same words as the status page
DO $$
DECLARE d text; was text := 'HINT = ''A declined offer is not reinstated.''';
BEGIN
    d := pg_get_functiondef('admissions.sign_undertaking(uuid)'::regprocedure);
    IF (length(d) - length(replace(d, was, ''))) / length(was) <> 1 THEN RAISE EXCEPTION 'V760: admissions.sign_undertaking is not as it stood'; END IF;
    EXECUTE replace(d, was, 'HINT = ''If you declined by mistake, write to the Academic Office quoting your application number: a decline is reversed only while your place has not been given to someone else.''');
END $$;

COMMIT;

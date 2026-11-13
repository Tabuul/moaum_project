-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V758 · An applicant's accidental decline reversed by the Academic Office
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  An applicant who declines the offer by mistake asks for it back. The University's decisions of 13 November 2026:
--    · the Academic Office (or the Registrar's office) reverses the decline, with the reason (the applicant's request and how it was
--      received) on the record and the audit trail;
--    · only while the place is free: once the Admissions Office has given it to someone from the waiting list (V358, promoted_for),
--      the decline stands and the reversal is refused, naming who holds the place — the programme never goes over its quota and
--      nobody else's offer is touched;
--    · when the acceptance deadline has passed, the officer sets a new acceptance date for this offer as part of the reversal; the
--      offer does not lapse before it (application.own_accept_by, read by admissions.offer_deadline_of).
--  The reversal clears the decline, puts the candidate back in the state the decline left (from the audit trail: PROPOSED or
--  ADMITTED) and on the programme the Board offered (where JAMB's course was followed meanwhile, V636 — the difference then corrected
--  on Programme Changes, V757), accepts the offer at once where the undertaking was signed and the acceptance fee confirmed while it
--  stood declined, records it in admissions.decline_reversal with the reason (also on the audit trail), and tells the applicant. It
--  is refused when the JAMB list that admitted the candidate was withdrawn meanwhile. A waiting-list promotion now locks the place it
--  fills, so a promotion and a reversal of the same place never both stand. A declined offer is a freed place
--  (admissions.vacancies) until then; after it, it is an offer again, to accept and pay for as before.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V758: an applicant''s accidental decline reversed by the Academic Office', true);

ALTER TABLE admissions.application ADD COLUMN own_accept_by date;
COMMENT ON COLUMN admissions.application.own_accept_by IS
    'V758: an acceptance deadline of this offer''s own, set by the officer who reversed its decline after the session''s deadline had passed; the offer does not lapse before it.';

CREATE TABLE admissions.decline_reversal (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id    uuid NOT NULL REFERENCES admissions.application(id) ON DELETE CASCADE,
    declined_at       timestamptz NOT NULL,
    offer_state_was   text NULL,
    offer_state_now   text NULL,
    programme_was     text NULL,
    programme_now     text NULL,
    own_accept_by     date NULL,
    reason            text NOT NULL CHECK (length(btrim(reason)) >= 20),
    reversed_by       uuid NOT NULL,
    reversed_office   text NOT NULL,
    reversed_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_decline_reversal_application ON admissions.decline_reversal (application_id);
SELECT audit.attach('admissions.decline_reversal');
COMMENT ON TABLE admissions.decline_reversal IS
    'V758: each decline the Academic Office (or the Registrar''s office) reversed — the decline undone, the candidate''s state before and after, a new acceptance date where the session''s had passed, the reason and who.';

-- the deadline of an offer: the session's rule, or the offer's own date set at a reversal, whichever is later; with no session deadline
-- in force no offer lapses, whatever date a reversal gave
CREATE OR REPLACE FUNCTION admissions.offer_deadline_of(p_app uuid)
 RETURNS date
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN d.session IS NULL OR a.decision_released_at IS NULL THEN NULL
                ELSE greatest(
                    CASE WHEN d.accept_by IS NOT NULL AND d.days_after_release IS NOT NULL
                              THEN greatest(d.accept_by, (a.decision_released_at AT TIME ZONE 'Africa/Lagos')::date + d.days_after_release)
                         WHEN d.accept_by IS NOT NULL THEN d.accept_by
                         ELSE (a.decision_released_at AT TIME ZONE 'Africa/Lagos')::date + d.days_after_release END,
                    a.own_accept_by)   -- V758
           END
      FROM admissions.application a LEFT JOIN admissions.offer_deadline d ON d.session = a.session
     WHERE a.id = p_app
$function$;

-- whether a declined offer may be reversed now, and why not
CREATE FUNCTION admissions.decline_reversible(p_app uuid)
RETURNS TABLE (reversible boolean, why text, deadline date, deadline_passed boolean)
LANGUAGE sql STABLE AS $$
    SELECT w.why IS NULL, w.why,
           admissions.offer_deadline_of(a.id),
           coalesce(admissions.offer_deadline_of(a.id) < (now() AT TIME ZONE 'Africa/Lagos')::date, false)
      FROM (SELECT p_app AS id) k
      LEFT JOIN admissions.application a ON a.id = k.id
      LEFT JOIN admissions.candidate c ON c.id = a.candidate_id
      LEFT JOIN LATERAL (SELECT x.id, x.application_no, x.promoted_at FROM admissions.application x WHERE x.promoted_for = a.id
                          ORDER BY x.promoted_at LIMIT 1) p ON true
      CROSS JOIN LATERAL (SELECT CASE
                WHEN a.id IS NULL THEN 'DECLINE_REVERSAL_NO_APPLICATION: no such application'
                WHEN a.declined_at IS NULL THEN 'DECLINE_REVERSAL_NOT_DECLINED: the offer was not declined'
                WHEN a.decision IS DISTINCT FROM 'OFFERED' OR a.decision_released_at IS NULL THEN 'DECLINE_REVERSAL_NO_OFFER: there is no released offer to restore'
                WHEN a.accepted_at IS NOT NULL THEN 'DECLINE_REVERSAL_ACCEPTED: the offer was accepted'
                WHEN a.lapsed_at IS NOT NULL THEN 'DECLINE_REVERSAL_LAPSED: the offer lapsed'
                WHEN p.id IS NOT NULL THEN 'DECLINE_REVERSAL_PLACE_FILLED: the place was given to ' || p.application_no || ' from the waiting list on '
                                           || to_char(p.promoted_at AT TIME ZONE 'Africa/Lagos', 'FMDD Mon YYYY')
                -- the JAMB list that admitted the candidate was withdrawn while the offer stood declined: there is no admission to restore
                WHEN c.admitted_from IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM admissions.caps_row_live r WHERE r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no)
                     THEN 'DECLINE_REVERSAL_LIST_WITHDRAWN: the JAMB list that admitted the candidate was withdrawn while the offer stood declined'
                END AS why) w;
$$;

CREATE FUNCTION admissions.reverse_decline(p_app uuid, p_reason text, p_accept_by date DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a admissions.application; c admissions.candidate; r record; q admissions.programme_change_request;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_was text; v_now text; v_prog_was text; v_prog_now text; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_deadline date;
BEGIN
    IF v_actor IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'DECLINE_REVERSAL_OFFICE: a decline is reversed by the Academic Office or the Registrar''s office' USING ERRCODE = '23514';
    END IF;
    IF v_reason IS NULL OR length(v_reason) < 20 THEN
        RAISE EXCEPTION 'DECLINE_REVERSAL_REASON: say why (the applicant''s request and how it was received), at least 20 characters' USING ERRCODE = '23514';
    END IF;
    -- the offer locked first: a waiting-list promotion of this place waits for the reversal, then finds the place taken back
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    SELECT * INTO r FROM admissions.decline_reversible(p_app);
    IF NOT r.reversible THEN
        RAISE EXCEPTION '%', r.why USING ERRCODE = CASE WHEN a.id IS NULL THEN '23503' ELSE '23514' END;
    END IF;
    -- the acceptance date: the session's while it runs; once passed, the officer's new date (and only then)
    IF r.deadline_passed AND p_accept_by IS NULL THEN
        RAISE EXCEPTION 'DECLINE_REVERSAL_DEADLINE: the acceptance deadline (%) has passed; give a new acceptance date for this offer', to_char(r.deadline, 'FMDD Mon YYYY')
              USING ERRCODE = '23514';
    END IF;
    IF p_accept_by IS NOT NULL AND NOT r.deadline_passed THEN
        RAISE EXCEPTION 'DECLINE_REVERSAL_DATE: a new acceptance date is given only once the acceptance deadline has passed' USING ERRCODE = '23514';
    END IF;
    IF p_accept_by IS NOT NULL AND p_accept_by < v_today THEN
        RAISE EXCEPTION 'DECLINE_REVERSAL_DATE: the new acceptance date is in the past' USING ERRCODE = '23514';
    END IF;
    IF p_accept_by IS NOT NULL AND p_accept_by > v_today + 120 THEN
        RAISE EXCEPTION 'DECLINE_REVERSAL_DATE: a new acceptance date is at most 120 days away' USING ERRCODE = '23514';
    END IF;
    -- the officer's reason on the audit trail of every row changed
    PERFORM set_config('moaum.reason', left('Decline reversed: ' || v_reason, 1000), true);
    -- the candidate's state before the decline, from the audit trail (the decline set DECLINED from PROPOSED or ADMITTED)
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id FOR UPDATE;
    v_was := c.offer_state;
    v_prog_was := c.programme;
    v_prog_now := c.programme;
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
    -- JAMB's course followed while the offer stood declined (V636 moves only a candidate whose offer does not stand): the offer is
    -- restored on the programme the Board offered; the difference from CAPS is then corrected on Programme Changes (V757)
    SELECT * INTO q FROM admissions.programme_change_request x
     WHERE x.candidate_id = c.id AND x.reason_code = 'JAMB_CAPS' AND x.state = 'APPROVED' AND x.decided_at >= a.declined_at
     ORDER BY x.decided_at ASC LIMIT 1;
    IF q.id IS NOT NULL AND q.from_programme IS NOT NULL AND q.from_programme IS DISTINCT FROM c.programme THEN
        v_prog_now := q.from_programme;
    END IF;
    UPDATE admissions.candidate SET offer_state = v_now, programme = v_prog_now
     WHERE id = c.id AND (offer_state IS DISTINCT FROM v_now OR programme IS DISTINCT FROM v_prog_now);
    UPDATE admissions.application SET declined_at = NULL, own_accept_by = coalesce(p_accept_by, own_accept_by) WHERE id = a.id;
    INSERT INTO admissions.decline_reversal (application_id, declined_at, offer_state_was, offer_state_now, programme_was, programme_now, own_accept_by,
                                             reason, reversed_by, reversed_office)
    VALUES (a.id, a.declined_at, v_was, v_now, v_prog_was, v_prog_now, p_accept_by, v_reason, v_actor, v_office);
    -- the undertaking signed and the acceptance fee confirmed while the offer stood declined: the offer is accepted now, as it would
    -- have been then (registered, screening opened, the applicant told)
    PERFORM admissions.settle_acceptance(a.id);
    v_deadline := admissions.offer_deadline_of(a.id);
    PERFORM admissions.notify_applicant(a.id, 'Your admission offer for ' || a.session || ' is restored',
        'At your request the University has reversed the decline of your admission offer for the ' || a.session || ' session. The offer stands again: '
        || 'read it on the applicant portal under Admission Status, then accept it and pay the acceptance fee where you have not'
        || CASE WHEN v_deadline IS NOT NULL THEN ' by ' || to_char(v_deadline, 'FMDD FMMonth YYYY') ELSE '' END || '.',
        'MOAUM: your admission offer for ' || a.session || ' is restored at your request. See Admission Status on the portal'
        || CASE WHEN v_deadline IS NOT NULL THEN ' and accept by ' || to_char(v_deadline, 'FMDD Mon YYYY') ELSE '' END || '.');
    RETURN jsonb_build_object('outcome', 'REVERSED', 'applicationNo', a.application_no, 'offerState',
                              (SELECT x.offer_state FROM admissions.candidate x WHERE x.id = c.id), 'programme', v_prog_now,
                              'programmeRestored', v_prog_now IS DISTINCT FROM v_prog_was, 'deadline', v_deadline);
END $$;
COMMENT ON FUNCTION admissions.reverse_decline(uuid, text, date) IS
    'V758: the Academic Office (or the Registrar''s office) reverses an applicant''s accidental decline while the place is free and its JAMB list stands; a new acceptance date is required (and allowed) only once the session''s has passed; the candidate''s state (and the programme offered, where JAMB''s course was followed meanwhile) restored, an undertaking and fee completed meanwhile settled, the reversal recorded with the reason, the applicant told.';

-- a waiting-list promotion locks the place it fills and finds it still free (a decline reversed meanwhile takes the place back)
DO $$
DECLARE d text; anchor text := '        SELECT * INTO v FROM admissions.vacancies(p_session) x WHERE x.programme = p_programme ORDER BY x.freed_at, x.application_no LIMIT 1;';
BEGIN
    d := pg_get_functiondef('admissions.promote_waiting(text,text,uuid[],uuid)'::regprocedure);
    IF (length(d) - length(replace(d, anchor, ''))) / length(anchor) <> 1 THEN RAISE EXCEPTION 'V758: admissions.promote_waiting is not as V358 left it'; END IF;
    EXECUTE replace(d, anchor, anchor || '
        -- V758: the place locked and read again before it is filled: a decline reversed meanwhile has taken it back
        PERFORM 1 FROM admissions.application x
         WHERE x.id = v.vacated_id AND x.accepted_at IS NULL AND (x.declined_at IS NOT NULL OR x.lapsed_at IS NOT NULL) FOR UPDATE;
        IF v.vacated_id IS NULL OR NOT FOUND THEN
            RAISE EXCEPTION ''ADMISSION_NO_VACANCY: the place was taken back meanwhile; read the freed places again'' USING ERRCODE = ''23514'';
        END IF;');
END $$;

-- the applicant is no longer told a declined offer is never reinstated
DO $$
DECLARE d text; was text := '''A declined offer is not reinstated.''';
BEGIN
    d := pg_get_functiondef('admissions.admission_status(uuid)'::regprocedure);
    IF (length(d) - length(replace(d, was, ''))) / length(was) <> 1 THEN RAISE EXCEPTION 'V758: admissions.admission_status is not as it stood'; END IF;
    EXECUTE replace(d, was, '''If you declined by mistake, write to the Academic Office quoting your application number: a decline is reversed only while your place has not been given to someone else.''');
END $$;

-- the freed places say whether a declined one may still be reversed (the Offers screen)
CREATE FUNCTION admissions.declines_reversible(p_session text)
RETURNS TABLE (application_id uuid, application_no text, name text, programme text, declined_at timestamptz, deadline date, deadline_passed boolean)
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.application_no, upper(c.surname) || ', ' || c.other_names, c.programme, a.declined_at, r.deadline, r.deadline_passed
      FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
      CROSS JOIN LATERAL admissions.decline_reversible(a.id) r
     WHERE a.session = p_session AND a.declined_at IS NOT NULL AND r.reversible
     ORDER BY a.declined_at DESC;
$$;

COMMIT;

-- ═══════════════════════════════════════
-- V643 — A student who sees a GST/EPS course on the registration page can pay the GST fee for it, and is asked to before it is
-- registered
--
-- The University's report of 23 October 2026: "you are required to pay the GST fee of NGN 4000.00 for 2025/2026 before you can
-- register your courses" — and the student could not pay it; "student that can see their gst course on registration page should
-- be able to pay, for gst fee including the ones in 300 level ... correct for all students".
--
-- Since V590 the registration menu lists the programme's courses at the student's level whatever the binding's track and the
-- course's curriculum (registration.curriculum_open, on). What a student owes for GST/EPS (finance.gst_eps_rows) was left as
-- it was on purpose — the programme's courses of the student's own curriculum — because many programmes bind both curricula's
-- GST courses at one level and a student takes one set. So a student whose only GST/EPS course on the page is of the other
-- curriculum owed nothing: GST & EPS said no payment was required, and finance.new_gst_reference refused the fee
-- (GST_NOT_REQUIRED). Saving that course beside the others then failed with the message above: once on the registration
-- being saved it made the fee owed (a course being taken counts), the Bursary's "required for all registration"
-- (finance.gst_setting.required_for_all) refused the next course, the whole save was undone, and the student was back to
-- "no payment required" with nothing to pay. On the live-shaped copy 997 students saw a GST/EPS course and owed nothing:
-- 984 at 400 Level (BMAS: GST 312, GST 412, ENT 412), 11 at 300 Level (BMAS: EPS 301, GST 312), 2 at 100 Level.
--
-- Now (what is owed, course by course, is unchanged):
--   · finance.gst_payable_courses(student, session): the GST/EPS courses the registration page shows the student — the
--     programme's at their level, whatever the curriculum while the curricula are open, offered in the session in the
--     student's stream, not already passed — for an undergraduate in good standing, never CCE (as finance.gst_eps_rows);
--   · finance.new_gst_reference: the fee is paid by a student who owes it or who is shown such a course (GST_NOT_REQUIRED
--     only for one shown none);
--   · registration.gst_gate: such a course, not yet owed, is held until the fee is paid — the student is asked to pay before
--     it goes on the registration (the GST/EPS course itself, "before you can register GST courses"), never by the whole save
--     failing on the course after it; every other course registers as before.
--   · finance.renew_reference: an expired GST reference of such a student is made payable again on the same terms (V635).
-- A student who pays it and takes the course owes it as a course being taken, as every other student; one who pays and never
-- takes one stays on the Bursary's review of payments no course requires (V367).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V643: a student shown a GST/EPS course on the registration page pays the GST fee for it', true);

-- ── 1 · the GST/EPS courses the registration page shows ─────────────────────────────────────────────────────────────────
CREATE FUNCTION finance.gst_payable_courses(p_student uuid, p_session text)
RETURNS TABLE (course_code text, office text) LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT st.id, st.programme_code, st.current_level, st.curriculum_track, st.curriculum_version,
                      people.student_stream(st.id) AS stream, registration.curriculum_open() AS open_all
                 FROM people.student st
                 JOIN ref.programme p ON p.code = st.programme_code AND p.category = 'UNDER GRADUATE'
                WHERE st.id = p_student AND st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') AND st.entry_mode IS DISTINCT FROM 'CCE'),
         -- the menu leaves out the GST/EPS courses the engine reads as already passed (registration.student_menu, V366)
         passed AS (SELECT x.course_code FROM finance.gst_eps_rows(p_session, p_student) x WHERE x.status = 'ALREADY_PASSED')
    SELECT DISTINCT c.code, c.general_office
      FROM s
      JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                                    AND (s.open_all OR co.track IS NULL OR s.curriculum_track IS NULL OR co.track = s.curriculum_track)
      JOIN catalogue.course c ON c.code = co.course_code AND c.kind = 'GST' AND c.general_office IS NOT NULL AND c.state <> 'ENDED'
                             AND c.code NOT LIKE 'DMO %'
      JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.stream = s.stream
     WHERE (s.open_all OR c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version)
       AND c.code NOT IN (SELECT pc.course_code FROM passed pc)
$$;
COMMENT ON FUNCTION finance.gst_payable_courses(uuid, text) IS
  'V643: the GST/EPS courses the registration page shows a student in a session — the programme''s at their level (whatever the '
  'curriculum while the curricula are open, as registration.student_menu lists them), offered in the session in the student''s '
  'stream, not already passed; an undergraduate in good standing, never CCE. The GST fee is paid for them (finance.new_gst_reference) '
  'and they are held until it is (registration.gst_gate).';

-- ── 2 · the fee paid by a student shown such a course ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.new_gst_reference(p_student uuid, p_session text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE e record;
BEGIN
    SELECT * INTO e FROM finance.gst_entitlement(p_student, p_session);
    IF e.state = 'PAID' THEN
        RAISE EXCEPTION 'GST_ALREADY_PAID: the GST fee for % is paid in full (receipt %)', p_session, coalesce(e.receipt_no, e.reference) USING ERRCODE = '23514',
            HINT = 'It is paid once and covers both GST and EPS.';
    END IF;
    -- V643: owed, or shown a GST/EPS course on the registration page
    IF NOT e.required AND NOT EXISTS (SELECT 1 FROM finance.gst_payable_courses(p_student, p_session)) THEN
        RAISE EXCEPTION 'GST_NOT_REQUIRED: no GST or EPS course requires the GST fee of you in %', p_session USING ERRCODE = '23514',
            HINT = 'The fee is owed for a GST or EPS course offered to your programme at your level, or a GST/EPS carryover. If a course is missing, ask ICT Support.';
    END IF;
    IF e.stated AND e.fee = 0 THEN
        RAISE EXCEPTION 'GST_EXEMPT: the GST fee stated for you in % is nothing; there is nothing to pay', p_session USING ERRCODE = '23514';
    END IF;
    IF NOT e.stated THEN
        RAISE EXCEPTION 'GST_FEE_NOT_STATED: no GST fee is stated for %', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the GST fee for the session before it is paid.';
    END IF;
    IF e.open_reference IS NOT NULL THEN RETURN e.open_reference; END IF;
    RETURN finance.new_purpose_reference(p_student, p_session, e.fee - e.paid, 'GST fee ' || p_session);
END $function$;

-- ── 3 · such a course held until the fee is paid ────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.gst_gate(p_student uuid, p_session text, p_course text)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT kind, general_office FROM catalogue.course WHERE code = p_course),
         g AS (SELECT * FROM finance.gst_setting WHERE id = 1),
         e AS (SELECT * FROM finance.gst_entitlement(p_student, p_session))
    SELECT CASE WHEN e.required AND e.stated AND e.fee > 0 AND NOT e.entitled
                     AND ((g.required_for_gst_eps AND c.kind = 'GST' AND c.general_office IS NOT NULL AND (c.general_office = 'GST' OR g.covers_eps))
                          OR g.required_for_all)
                THEN 'GST_PAYMENT_REQUIRED: you are required to pay the GST fee of NGN ' || to_char(e.fee, 'FM999,999,999,990.00') || ' for ' || p_session
                     || ' before you can register ' || CASE WHEN c.general_office IS NOT NULL THEN c.general_office || ' courses' ELSE 'your courses' END
                     || '. GST payment covers both GST and EPS requirements.'
                -- V643: a GST/EPS course the registration page shows, not yet owed (taken, it would be): paid for first, so the save is
                -- never refused on the course after it
                WHEN NOT e.required AND e.stated AND e.fee > 0 AND NOT e.entitled
                     AND c.kind = 'GST' AND c.general_office IS NOT NULL
                     AND ((g.required_for_gst_eps AND (c.general_office = 'GST' OR g.covers_eps)) OR g.required_for_all)
                THEN CASE WHEN EXISTS (SELECT 1 FROM finance.gst_payable_courses(p_student, p_session) pc WHERE pc.course_code = p_course)
                          THEN 'GST_PAYMENT_REQUIRED: you are required to pay the GST fee of NGN ' || to_char(e.fee, 'FM999,999,999,990.00') || ' for ' || p_session
                               || ' before you can register ' || c.general_office || ' courses. GST payment covers both GST and EPS requirements.' END
                ELSE NULL END
      FROM g CROSS JOIN e LEFT JOIN c ON true
$$;
COMMENT ON FUNCTION registration.gst_gate(uuid, text, text) IS
  'V314/V366/V367/V643: why the GST fee holds a course from the student''s registration, or NULL — owed and not paid, a GST/EPS '
  'course (or every course under the Bursary''s required-for-all); (V643) a GST/EPS course the registration page shows the student, '
  'not yet owed, until the fee is paid.';

-- ── 4 · an expired GST reference renewed on the same terms ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.renew_reference(p_student uuid, p_reference text)
 RETURNS TABLE(reference_out text, amount_out numeric, until_out timestamp with time zone, purpose_out text, outcome text)
 LANGUAGE plpgsql
AS $function$
DECLARE r finance.payment_reference; o finance.payment_reference; v_until timestamptz := now() + interval '24 hours'; v_new text;
        pos record; win record; e record; t record; al hostel.allocation; v_ref text := upper(btrim(coalesce(p_reference, '')));
BEGIN
    SELECT * INTO r FROM finance.payment_reference x WHERE x.reference = v_ref FOR UPDATE;
    IF NOT FOUND OR r.student_id IS DISTINCT FROM p_student THEN
        RAISE EXCEPTION 'REFERENCE_NOT_FOUND: no payment reference % of yours', v_ref USING ERRCODE = 'P0002';
    END IF;
    IF r.confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'REFERENCE_PAID: reference % is paid (receipt %); there is nothing to pay again', r.reference, coalesce(r.receipt_no, '—') USING ERRCODE = '23514';
    END IF;
    -- still payable: nothing to renew
    IF r.expires_at > now() THEN
        RETURN QUERY SELECT r.reference, r.amount, r.expires_at, r.purpose, 'OPEN'::text;
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('renew-reference:' || p_student::text));

    IF r.purpose LIKE 'School fees%' THEN
        -- as for a new school-fees reference (finance.new_reference, V602, V269, V288)
        IF finance.closed_for_fees(p_student, r.session) THEN
            RAISE EXCEPTION 'SCHOOL_FEES_CLOSED_GRADUATED: This academic record has been marked as graduated. New school-fee payments are not available for this academic enrollment.'
                USING ERRCODE = '23514';
        END IF;
        PERFORM admissions.screening_refuse_student(p_student, 'SCHOOL FEES');
        SELECT * INTO win FROM policy.window_state('SCHOOL_FEES_PAYMENT', r.session, NULL);
        IF win.state <> 'OPEN' THEN
            RAISE EXCEPTION 'SCHOOL_FEES_PAYMENT_CLOSED: school fees payment is currently % for %', lower(win.state), r.session USING ERRCODE = '23514',
                HINT = CASE WHEN win.state = 'SCHEDULED' THEN 'It opens on ' || to_char(win.opens_at AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.' ELSE 'The Directorate of ICT opens the payment window.' END;
        END IF;
        SELECT * INTO o FROM finance.payment_reference x
         WHERE x.student_id = p_student AND x.session = r.session AND x.purpose LIKE 'School fees%' AND x.confirmed_at IS NULL AND x.expires_at > now()
         ORDER BY x.generated_at DESC LIMIT 1;
        IF FOUND THEN
            RETURN QUERY SELECT o.reference, o.amount, o.expires_at, o.purpose, 'OPEN'::text;
            RETURN;
        END IF;
        SELECT * INTO pos FROM finance.position(p_student, r.session);
        IF coalesce(pos.balance, 0) < 1 THEN
            RAISE EXCEPTION 'REFERENCE_NOTHING_OWED: the school fees for % are paid; reference % is not needed', r.session, r.reference USING ERRCODE = '23514';
        END IF;
        IF r.amount > pos.balance THEN
            v_new := finance.new_reference(p_student, r.session, pos.balance, r.purpose);
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'NEW'::text FROM finance.payment_reference x WHERE x.reference = v_new;
            RETURN;
        END IF;
    ELSIF r.purpose LIKE 'GST fee %' THEN
        SELECT * INTO e FROM finance.gst_entitlement(p_student, r.session);
        IF e.state = 'PAID' THEN
            RAISE EXCEPTION 'GST_ALREADY_PAID: the GST fee for % is paid in full (receipt %)', r.session, coalesce(e.receipt_no, e.reference) USING ERRCODE = '23514';
        END IF;
        -- V643: owed, or shown a GST/EPS course on the registration page (finance.gst_payable_courses)
        IF (NOT e.required AND NOT EXISTS (SELECT 1 FROM finance.gst_payable_courses(p_student, r.session)))
           OR NOT e.stated OR coalesce(e.fee, 0) - coalesce(e.paid, 0) < 1 THEN
            RAISE EXCEPTION 'REFERENCE_NOTHING_OWED: no GST fee is owed for %; reference % is not needed', r.session, r.reference USING ERRCODE = '23514';
        END IF;
        IF e.open_reference IS NOT NULL THEN
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'OPEN'::text FROM finance.payment_reference x WHERE x.reference = e.open_reference;
            RETURN;
        END IF;
        IF r.amount <> e.fee - e.paid THEN
            v_new := finance.new_gst_reference(p_student, r.session);
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'NEW'::text FROM finance.payment_reference x WHERE x.reference = v_new;
            RETURN;
        END IF;
    ELSIF r.purpose LIKE 'Wallet top-up%' THEN
        SELECT * INTO t FROM finance.topup_eligibility(p_student, r.session);
        IF t.open_reference IS NOT NULL THEN
            RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, 'OPEN'::text FROM finance.payment_reference x WHERE x.reference = t.open_reference;
            RETURN;
        END IF;
        IF NOT t.allowed THEN
            RAISE EXCEPTION 'REFERENCE_TOPUP_REFUSED: the wallet takes no top-up for % now (%)', r.session, lower(replace(coalesce(t.reason, 'not allowed'), '_', ' ')) USING ERRCODE = '23514';
        END IF;
        IF r.amount > t.max_topup THEN
            RAISE EXCEPTION 'REFERENCE_TOPUP_AMOUNT: the wallet takes at most NGN % for % now; start a top-up of that on the wallet page', to_char(t.max_topup, 'FM999,999,999,990.00'), r.session USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Transcript %' THEN
        IF NOT EXISTS (SELECT 1 FROM credentials.transcript_request q WHERE q.reference = r.reference AND q.paid_at IS NULL AND q.closed_at IS NULL) THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the request reference % pays for is paid, cancelled or closed', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Hostel accommodation fine %' THEN
        IF NOT EXISTS (SELECT 1 FROM hostel.sanction sn WHERE sn.id::text = split_part(r.purpose, ' ', 5) AND sn.settled_at IS NULL AND sn.waived_at IS NULL AND sn.state = 'IN_FORCE') THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the hostel fine reference % pays for is settled, waived or quashed', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Hostel accommodation damage%' THEN
        IF NOT EXISTS (SELECT 1 FROM hostel.damage_charge dc WHERE dc.reference = r.reference AND dc.settled_at IS NULL AND dc.waived_at IS NULL) THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the damage charge reference % pays for is settled or waived', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Hostel accommodation%' THEN
        SELECT * INTO al FROM hostel.allocation a WHERE a.reference = r.reference ORDER BY a.allocated_at DESC LIMIT 1;
        IF NOT FOUND OR coalesce(al.fee_status, 'PAYABLE') = 'PAID' OR al.ended_at IS NOT NULL OR al.lapsed_at IS NOT NULL
           OR al.state IN ('DECLINED', 'CANCELLED', 'TRANSFERRED', 'LAPSED', 'CHECKED_OUT') THEN
            RAISE EXCEPTION 'REFERENCE_HOSTEL_HOLD_ENDED: the bed reference % paid for is no longer held for you; reserve again on Hostel', r.reference USING ERRCODE = '23514';
        END IF;
        -- a held bed is paid for within its hold, never after it: the reference lasts no longer than the hold
        IF al.state = 'HELD' AND al.held_until IS NOT NULL THEN
            IF al.held_until <= now() THEN
                RAISE EXCEPTION 'REFERENCE_HOSTEL_HOLD_ENDED: the hold on the bed reference % paid for ended on %; reserve again on Hostel', r.reference,
                    to_char(al.held_until AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY HH24:MI') USING ERRCODE = '23514';
            END IF;
            v_until := least(v_until, al.held_until);
        END IF;
    ELSIF r.purpose LIKE 'Library fine%' THEN
        IF NOT EXISTS (SELECT 1 FROM library.loan l WHERE l.fine_reference = r.reference AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL) THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the library fine reference % pays for is settled or waived', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Deferment application fee%' THEN
        IF NOT EXISTS (SELECT 1 FROM people.deferment_fee f WHERE f.reference = r.reference AND f.state = 'PENDING') THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the deferment fee reference % pays for is no longer pending', r.reference USING ERRCODE = '23514';
        END IF;
    ELSIF r.purpose LIKE 'Inter-departmental transfer%' THEN
        IF NOT EXISTS (SELECT 1 FROM people.transfer_application ta WHERE ta.fee_reference = r.reference
                          AND ta.state NOT IN ('DECLINED', 'WITHDRAWN', 'EFFECTED', 'NOT_RECOMMENDED')) THEN
            RAISE EXCEPTION 'REFERENCE_ITEM_CLOSED: the transfer reference % pays for is withdrawn, declined or done', r.reference USING ERRCODE = '23514';
        END IF;
    ELSE
        RAISE EXCEPTION 'REFERENCE_NOT_RENEWABLE: reference % (%) is renewed by the office that raised it', r.reference, r.purpose USING ERRCODE = '23514',
            HINT = 'Ask the Bursary.';
    END IF;

    -- the same reference, payable again
    UPDATE finance.payment_reference x SET expires_at = v_until WHERE x.id = r.id;
    RETURN QUERY SELECT r.reference, r.amount, v_until, r.purpose, 'REOPENED'::text;
END $function$;

COMMIT;

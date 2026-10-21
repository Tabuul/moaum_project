-- V621: a course dropped from a registration stays on it as DROPPED through a save that leaves it out, and is restored in place
-- when it is chosen again. V620 made registration.student_choose keep an entry already on the registration and still chosen as it
-- was registered; a dropped entry chosen again — the support desk's restore (registration.support_add puts the dropped course back
-- through the student's own engine, V346) or the student ticking the course once more — was kept as it was too, DROPPED, and the
-- restore was refused ("the engine did not place the course on the draft"; CI on d527b055, SupportResolutionIT). Before V620 a save
-- deleted every dropped entry not chosen and re-made a chosen one afresh; now neither: a dropped or withdrawn entry stays on the
-- record as it is, and a dropped one chosen again goes back to REGISTERED with the units, the type and the basis it was registered
-- at. Nothing else in the function changes.
CREATE OR REPLACE FUNCTION registration.student_choose(p_registration uuid, p_offerings uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; n int := 0; v_gate text; v_unmet text[];
        v_added jsonb; v_menu uuid[]; v_code text; ctx record; v_ctx boolean := false; x record; v_units int;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE id = p_registration;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such registration' USING ERRCODE = '23503'; END IF;
    IF r.status NOT IN ('DRAFT','RETURNED') THEN
        RAISE EXCEPTION 'this registration is %; it is not edited', lower(r.status) USING ERRCODE = '23514',
            HINT = 'A submitted registration is changed by the level adviser returning it.';
    END IF;
    -- V518: only the registration's own session and semester are chosen from: a screen switched from another semester could send that
    -- semester's courses with this one's (a first-semester course then refused as "already on your registration for another
    -- semester"); an offering of another session or semester is never this registration's, so it is left out rather than refused
    p_offerings := ARRAY(SELECT DISTINCT o.id FROM catalogue.offering o
                          WHERE o.id = ANY (coalesce(p_offerings, '{}'::uuid[])) AND o.session = r.session AND o.semester = r.semester);
    -- V504: when each course the student added beside the menu was first added, kept across saves
    SELECT coalesce(jsonb_object_agg(e.offering_id::text, e.student_added_at), '{}'::jsonb) INTO v_added
      FROM registration.entry e WHERE e.registration_id = p_registration AND e.student_added_at IS NOT NULL;
    -- V611: a carry-over the student declared is the student's choice, kept only while chosen; one the results state stays
    -- V620: an entry already on the registration and still chosen is kept as it was registered — its units, its type and the
    -- programme's basis for the course at the time (registration.entry.basis) — whatever its binding has become since, or whether it
    -- is still bound at all; only an entry the student no longer chooses goes
    -- V621: a course dropped (or withdrawn) stays on the registration as it is through a save that leaves it out — never deleted —
    -- and a dropped one chosen again is restored in place, as it was registered (the support desk's restore and the student's own tick)
    DELETE FROM registration.entry WHERE registration_id = p_registration AND support_override_at IS NULL
       AND NOT offering_id = ANY (p_offerings)
       AND status NOT IN ('DROPPED', 'WITHDRAWN')
       AND (entry_type NOT IN ('CARRYOVER','DEFERRED') OR added_as = 'CARRY_OVER_DECLARED');
    UPDATE registration.entry SET status = 'REGISTERED'
     WHERE registration_id = p_registration AND offering_id = ANY (p_offerings) AND status = 'DROPPED';
    -- V512: a GST/EPS carry-over put on the draft before the GST fee was paid comes off it while the fee is owed (not one ICT Support
    -- put on the student's ticket)
    DELETE FROM registration.entry e USING catalogue.offering o
     WHERE e.registration_id = p_registration AND o.id = e.offering_id AND e.entry_type IN ('CARRYOVER', 'DEFERRED') AND e.support_override_at IS NULL
       AND registration.gst_course_hold(r.student_id, r.session, o.course_code) IS NOT NULL;
    -- a deferred course or a carry-over that has since become due is added to a draft that predates it — a GST/EPS one once the fee is paid
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE carryover LOOP
        IF registration.gst_course_hold(r.student_id, r.session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(p_registration, m.offering_id); END IF;
    END LOOP;
    SELECT coalesce(array_agg(mm.offering_id), '{}'::uuid[]) INTO v_menu FROM registration.student_menu(r.student_id, r.session, r.semester) mm;
    FOR m IN SELECT * FROM registration.student_menu(r.student_id, r.session, r.semester) WHERE NOT carryover AND offering_id = ANY(p_offerings) LOOP
        -- V314: a GST or EPS course is registered only by a student whose GST fee is paid
        v_gate := registration.gst_gate(r.student_id, r.session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        -- V482: where the Academic Office enforces prerequisites, a course whose prerequisite the student has not passed is refused
        IF registration.prerequisite_mode() = 'ENFORCED' THEN
            v_unmet := registration.prerequisites_unmet(r.student_id, m.course_code);
            IF cardinality(v_unmet) > 0 THEN
                RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first; no published pass is on your record', m.course_code, array_to_string(v_unmet, ', ')
                    USING ERRCODE = '23514', HINT = 'If you passed it and the result is not yet published, or were exempted, your department asks ICT Support to add the course on your ticket.';
            END IF;
        END IF;
        -- V504: the programme's own setup (course_offer.basis) types it, as registration.is_elective_for reads it — a course the
        -- programme takes as core is core here though its own department offers it as an elective
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (p_registration, m.offering_id, m.units,
                CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                     WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND AND m.kind = 'GST' THEN PERFORM registration.gst_course_registered(p_registration, m.offering_id); END IF;
        n := n + 1;
    END LOOP;
    -- V504: a course beside the menu is kept only when the engine still allows it (registration.course_check); the record is
    -- read once for all of them
    FOR v_code IN SELECT o.course_code FROM catalogue.offering o
                   WHERE o.id = ANY (p_offerings) AND NOT o.id = ANY (v_menu)
                     AND NOT EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = p_registration AND e.offering_id = o.id)
                   ORDER BY o.course_code LOOP
        IF NOT v_ctx THEN SELECT * INTO ctx FROM registration.course_context(r.student_id, r.session, r.semester); v_ctx := true; END IF;
        SELECT * INTO x FROM registration.course_check(r.student_id, r.session, r.semester, v_code, ctx.passed, ctx.awaited, ctx.carry, ctx.other_semester);
        IF x.refusal IS NOT NULL THEN
            RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514', HINT = 'Remove ' || v_code || ' from your selection and save again.';
        END IF;
        IF NOT x.offering_id = ANY (p_offerings) THEN CONTINUE; END IF;   -- another stream's class of the course: not the student's
        -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
        v_gate := registration.gst_gate(r.student_id, r.session, v_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; registration opens the moment the payment is confirmed.';
        END IF;
        SELECT catalogue.units_for(v_code, s.programme_code, NULL) INTO v_units FROM people.student s WHERE s.id = r.student_id;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, student_added_at, added_as)
        VALUES (p_registration, x.offering_id, v_units,
                CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END,
                coalesce((v_added ->> x.offering_id::text)::timestamptz, now()), x.added_as)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(p_registration, x.offering_id); END IF;
        n := n + 1;
    END LOOP;
    RETURN registration.units_of(p_registration);
END $function$;
COMMENT ON FUNCTION registration.student_choose(uuid, uuid[]) IS 'V504, V512, V518, V611, V620, V621: the student''s choice saved on a draft — the menu''s courses chosen, the carry-overs and deferred courses due kept or added, a course beside the menu kept while the engine allows it, a declared carry-over only while chosen; an entry already on the registration and still chosen is kept as it was registered, whatever its binding has become (V620); a dropped entry stays on the record and is restored in place when chosen again (V621).';

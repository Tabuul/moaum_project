-- ═══════════════════════════════════════
-- V518 — The course registration save keeps only the semester's own courses
--
-- A student who registered the first semester and switched the course registration screen to the second semester saved a
-- selection that still held the first semester's courses (the screen kept its choice across the switch, out of sight under the
-- second semester's list), and the save refused it: "BIO 101 is already on your registration for another semester of 2025/2026"
-- (REG_ALREADY_REGISTERED, V504) — for every programme and course alike. The screen now starts afresh on each session and
-- semester, and registration.student_choose (restated from V512's definition) chooses only among the offerings of the
-- registration's own session and semester: any other is left out, never refused and never added. Nothing is written by this
-- migration; on the live-shaped copy no registration held another semester's course.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V518: the course registration save keeps only the semester''s own courses', true);

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
    DELETE FROM registration.entry WHERE registration_id = p_registration AND entry_type NOT IN ('CARRYOVER','DEFERRED') AND support_override_at IS NULL;
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

COMMENT ON FUNCTION registration.student_choose(uuid, uuid[]) IS
  'The student''s choice of courses for a draft or returned registration, kept by the engine (the menu, the carry-overs, the GST fee, the prerequisites, a course beside the menu by registration.course_check); V518: only the offerings of the registration''s own session and semester are chosen from, any other left out';

COMMIT;

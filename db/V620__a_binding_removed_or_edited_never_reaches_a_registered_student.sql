-- V620: a binding (a course bound into a programme's structure at a level) removed or edited never reaches a registered student —
-- the University's word of 21 October 2026. Until now a registered entry's category (core, elective, GST) was read from the live
-- binding each time it was shown, so a binding's basis edited or the binding removed changed what the student had registered; a
-- binding's units edited rewrote the units of every registration not yet examined (V464); an unbinding was refused while students
-- were registered on it (CAT_BOUND_IN_USE), and once allowed left those students' entries off their register and lost on the next
-- save (registration.student_choose re-made the registration from today's menu). Now:
--   · registration.entry.basis holds the programme's basis for the course as the student registered it (the binding at the
--     registration's level at the time), filled by a trigger on every new entry and for every entry already made from the binding as
--     it stands today — exactly what the readers read until now, frozen; the readers read the entry;
--   · registration.student_choose keeps an entry already on the registration and still chosen as it was registered;
--   · registration.is_elective_for reads the student's own registration of the course first (a carry-over is owed or not as the
--     course was registered), the structure only for a course never registered here;
--   · catalogue.unbind_offer is never refused for registered students (the binding goes on course_offer_history with the
--     registrations it carried, as before);
--   · a binding's units edited reach no registration by themselves (the trigger that carried them into the registrations not yet
--     examined is dropped); the structure desk may still carry a change into those registrations as its own explicit act
--     (catalogue.reflect_units, as the API's door offers it); the course's own units corrected still reach them (V465).
-- Nothing registered, scored or issued is deleted or rewritten.

-- ── the entry carries the basis it was registered under ──
ALTER TABLE registration.entry ADD COLUMN basis text;
ALTER TABLE registration.entry ADD CONSTRAINT ck_entry_basis
    CHECK (basis IS NULL OR basis IN ('Core', 'Elective', 'Borrowed', 'GST', 'Deficiency', 'Research'));
COMMENT ON COLUMN registration.entry.basis IS 'V620: the programme''s basis for the course as the student registered it (catalogue.course_offer.basis of the binding at the registration''s level at the time; NULL where the programme had no binding at that level). Read by every screen and rule that classifies the entry; never changed by a later edit or removal of the binding.';

CREATE OR REPLACE FUNCTION registration.entry_basis_snapshot()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- the binding at the registration's level for the student's programme, as the registration screens read it until V620
    IF NEW.basis IS NULL THEN
        SELECT co.basis INTO NEW.basis
          FROM registration.course_registration r
          JOIN people.student s ON s.id = r.student_id
          JOIN catalogue.offering o ON o.id = NEW.offering_id
          JOIN catalogue.course_offer co ON co.course_code = o.course_code AND co.programme_code = s.programme_code AND co.level = r.level
         WHERE r.id = NEW.registration_id;
    END IF;
    RETURN NEW;
END $function$;
COMMENT ON FUNCTION registration.entry_basis_snapshot() IS 'V620: a new entry takes the programme''s basis for its course from the binding at the registration''s level, once, unless the writer gave one.';
CREATE TRIGGER trg_entry_basis_snapshot BEFORE INSERT ON registration.entry FOR EACH ROW EXECUTE FUNCTION registration.entry_basis_snapshot();

-- every entry already made: the binding as it stands today — what every reader read for it until now, so nothing changes for anyone,
-- and from now on the binding may change without reaching it. A derived column filled from data already on the record is a change
-- of schema, not a change of anyone's state: the audit spine (one row an entry — 538,000 on the live record) and the CGPA
-- staleness mark are not written for it; the column is new and nothing read it before.
ALTER TABLE registration.entry DISABLE TRIGGER trg_audit_registration_entry;
ALTER TABLE registration.entry DISABLE TRIGGER trg_cgpa_entry_upd;
UPDATE registration.entry e
   SET basis = co.basis
  FROM registration.course_registration r, people.student s, catalogue.offering o, catalogue.course_offer co
 WHERE r.id = e.registration_id AND s.id = r.student_id AND o.id = e.offering_id
   AND co.course_code = o.course_code AND co.programme_code = s.programme_code AND co.level = r.level
   AND e.basis IS NULL;
ALTER TABLE registration.entry ENABLE TRIGGER trg_audit_registration_entry;
ALTER TABLE registration.entry ENABLE TRIGGER trg_cgpa_entry_upd;

-- ── the student's choice keeps what is registered ──
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
    DELETE FROM registration.entry WHERE registration_id = p_registration AND support_override_at IS NULL
       AND NOT offering_id = ANY (p_offerings)
       AND (entry_type NOT IN ('CARRYOVER','DEFERRED') OR added_as = 'CARRY_OVER_DECLARED');
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
COMMENT ON FUNCTION registration.student_choose(uuid, uuid[]) IS 'V504, V512, V518, V611, V620: the student''s choice saved on a draft — the menu''s courses chosen, the carry-overs and deferred courses due kept or added, a course beside the menu kept while the engine allows it, a declared carry-over only while chosen; an entry already on the registration and still chosen is kept as it was registered, whatever its binding has become (V620).';

-- ── a carry-over is owed or not as the course was registered ──
CREATE OR REPLACE FUNCTION registration.is_elective_for(p_student uuid, p_course text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    -- V620: as the student registered it — the programme's basis for the course at the time (registration.entry.basis) and the entry's
    -- type, read as registration.entry_category reads them — whatever the binding has become since; a course the student never
    -- registered here (an old-portal result) by the programme's structure today, else by the course's own kind
    SELECT coalesce(
        (SELECT registration.entry_category(e.entry_type, c.kind, e.basis) = 'ELECTIVE'
           FROM registration.entry e
           JOIN registration.course_registration r ON r.id = e.registration_id
           JOIN catalogue.offering o ON o.id = e.offering_id
           JOIN catalogue.course c ON c.code = o.course_code
          WHERE r.student_id = p_student AND o.course_code = p_course
            AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND e.entry_type NOT IN ('CARRYOVER', 'DEFERRED', 'REPEAT')
          ORDER BY r.session DESC, r.semester DESC LIMIT 1),
        (SELECT bool_or(co.basis = 'Elective')
           FROM catalogue.course_offer co
           JOIN people.student s ON s.id = p_student
          WHERE co.course_code = p_course AND co.programme_code = s.programme_code),
        (SELECT c.kind = 'Elective' FROM catalogue.course c WHERE c.code = p_course),
        false)
$function$;
COMMENT ON FUNCTION registration.is_elective_for(uuid, text) IS 'V620: whether a course is an elective to this student — as the student registered it (the entry''s basis and type), else by the programme''s structure today where it places the course, else by the course''s own kind.';

-- ── unbinding never refused for the students registered on it ──
CREATE OR REPLACE FUNCTION catalogue.unbind_offer(p_course text, p_programme text, p_level integer, p_reason text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        o catalogue.course_offer; carried bigint;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a binding is ended by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO o FROM catalogue.course_offer
     WHERE course_code = upper(btrim(coalesce(p_course, ''))) AND programme_code = upper(btrim(coalesce(p_programme, ''))) AND level = p_level;
    IF o.course_code IS NULL THEN
        RAISE EXCEPTION 'no binding of % into % at % level', p_course, p_programme, p_level USING ERRCODE = '23503';
    END IF;
    -- V620: never refused for the students registered on it — each keeps the registration as it was made (its units, its type, the
    -- programme's basis for the course at the time); the binding goes on the record with the registrations it carried
    SELECT count(*) INTO carried
      FROM registration.entry e
      JOIN registration.course_registration r ON r.id = e.registration_id
      JOIN catalogue.offering f ON f.id = e.offering_id
      JOIN people.student st ON st.id = r.student_id
     WHERE f.course_code = o.course_code AND st.programme_code = o.programme_code AND r.level = o.level;
    INSERT INTO catalogue.course_offer_history (course_code, programme_code, level, basis, track, added_at, added_by, source, ended_by, ended_office, reason, registrations_carried)
    VALUES (o.course_code, o.programme_code, o.level, o.basis, o.track, o.added_at, o.added_by, o.source, who, office, nullif(btrim(coalesce(p_reason, '')), ''), carried);
    DELETE FROM catalogue.course_offer WHERE course_code = o.course_code AND programme_code = o.programme_code AND level = o.level;
    RETURN CASE WHEN carried > 0 THEN 'ENDED' ELSE 'REMOVED' END;
END $function$;
COMMENT ON FUNCTION catalogue.unbind_offer(text, text, integer, text) IS 'V332, V620: end a course''s binding into a programme — kept on course_offer_history with the registrations it carried (ENDED) or none (REMOVED). Never refused for the students registered on it: each keeps the registration as it was made (V620). The registrations and results themselves stay.';

-- ── a binding's units edited reach no registration by themselves ──
DROP TRIGGER IF EXISTS trg_offer_units_reflect ON catalogue.course_offer;
DROP FUNCTION IF EXISTS catalogue.offer_units_reflect();
COMMENT ON FUNCTION catalogue.reflect_units(text, text, integer) IS 'V460, V464, V620: the registrations of the course (for one programme, at one level, or all) not yet examined — a session not closed, a class without a score and whose sheet has not left entry — take the units the structure now states (catalogue.units_for). Called by the course''s own units correction (catalogue.course_units_reflect) and by the structure desk''s explicit choice to carry a binding''s new units into those registrations (the API''s door); a binding''s edit alone reaches none (V620).';

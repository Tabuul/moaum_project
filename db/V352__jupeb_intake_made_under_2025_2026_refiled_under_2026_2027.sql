-- ═══════════════════════════════════════════════════════════════════════════
-- V352 — The JUPEB intake made under 2025/2026 re-filed under 2026/2027, the session it belongs to
--
--   · Until V351 the JUPEB session followed the University's current session, 2025/2026, while the JUPEB programme running
--     is 2026/2027 (the JUPEB Office: "2025/2026 is passed already"). So the JUPEB windows the Director of ICT opened in
--     October 2026, and the applications made on the portal since, were filed under 2025/2026. Left there, V351 would have
--     closed the live intake (2026/2027 had no window) and left the students out of the 2026/2027 lists and timetable.
--   · Re-filed under 2026/2027, as the JUPEB Office asked ("move them to 2026/2027"):
--       - the JUPEB application and admission-status-checking windows of 2025/2026, with their history, exactly as the Director
--         of ICT set them (dates unchanged), where 2026/2027 has none of its own; the move is on the window's history;
--       - every application made on this portal under 2025/2026 (not an old-portal upload, which the office filed under the
--         session it chose; not a deferred admission, which its deferment moves) — with its subject registrations and its
--         payments. A payment keeps its reference, amount, channel and date; only the session it is counted in changes, so the
--         Bursary's 2026/2027 list holds it. The school fee already charged stays as charged (both sessions' fees are the same);
--       - the JUPEB attendance registers of 2025/2026 held since September 2026 for every class, unless someone still filed
--         under 2025/2026 is marked on one.
--   · Every paper issued for a moved application states 2025/2026, so each is revoked with the reason; the next print issues it
--     afresh with its own code (the student's identity card too, when they open it). The application keeps its number and its
--     admission reference. Each application's trail records the move, and the candidate is told, by email and text.
--   · Nothing is deleted.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'jupeb', true),
       set_config('moaum.reason', 'V352: the JUPEB intake made under 2025/2026 re-filed under 2026/2027', true);

DO $$
DECLARE v_from constant text := '2025/2026'; v_to constant text := '2026/2027';
        v_why constant text := 'the JUPEB session followed the University''s (2025/2026) when this was made, while the JUPEB programme running is 2026/2027';
        t text; w record; r record; n_win int := 0; n_app int := 0; n_pay int := 0; n_paper int := 0; n_reg int := 0; k int;
BEGIN
    IF jupeb.current_session() IS DISTINCT FROM v_to OR NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = v_to) THEN
        RAISE NOTICE 'V352: the JUPEB current session is not %, nothing re-filed', v_to;
        RETURN;
    END IF;

    -- ── 1 · the windows, as the Director of ICT set them ──
    FOREACH t IN ARRAY ARRAY['JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING'] LOOP
        CONTINUE WHEN NOT EXISTS (SELECT 1 FROM policy.portal_window WHERE window_type = t AND session = v_from)
                   OR EXISTS (SELECT 1 FROM policy.portal_window WHERE window_type = t AND session = v_to);
        UPDATE policy.portal_window SET session = v_to WHERE window_type = t AND session = v_from;
        UPDATE policy.portal_window_event SET session = v_to WHERE window_type = t AND session = v_from;
        FOR w IN SELECT * FROM policy.portal_window WHERE window_type = t AND session = v_to AND superseded_at IS NULL LOOP
            INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, new_opens_at, new_closes_at, new_late_until,
                                                    late_fee_enabled, reason, office, at)
            VALUES (w.id, t, v_to, w.semester, 'EDIT', w.opens_at, w.closes_at, w.late_until, w.late_fee_enabled,
                    'Re-filed from ' || v_from || ' to ' || v_to || ' with its dates unchanged (V352): ' || v_why, 'jupeb', now());
        END LOOP;
        n_win := n_win + 1;
    END LOOP;

    -- ── 2 · the applications made on this portal, with their subjects, payments and papers ──
    FOR r IN SELECT a.id FROM jupeb.application a
              WHERE a.session = v_from AND a.legacy_source IS NULL AND a.state <> 'DEFERRED'
              ORDER BY a.created_at FOR UPDATE LOOP
        UPDATE jupeb.application SET session = v_to WHERE id = r.id;
        UPDATE jupeb.subject_registration SET session = v_to WHERE application_id = r.id AND session = v_from;
        UPDATE jupeb.fee_reference SET session = v_to WHERE application_id = r.id AND session = v_from;
        GET DIAGNOSTICS k = ROW_COUNT; n_pay := n_pay + k;
        UPDATE jupeb.paper SET revoked_at = now(), revoked_reason = 'Re-filed from ' || v_from || ' to ' || v_to || ' (V352): this paper states ' || v_from
                                                                   || '; printed again, it is issued afresh with its own code'
         WHERE application_id = r.id AND revoked_at IS NULL AND facts->>'session' = v_from;
        GET DIAGNOSTICS k = ROW_COUNT; n_paper := n_paper + k;
        PERFORM jupeb.app_event(r.id, 'SESSION_REFILED', 'Re-filed from ' || v_from || ' to ' || v_to || ': ' || v_why
            || '. The subjects and the payments moved with it (references and amounts unchanged); ' || k || ' paper' || CASE WHEN k = 1 THEN '' ELSE 's' END
            || ' stating ' || v_from || ' revoked, to be printed again.');
        PERFORM jupeb.tell(r.id, 'Your JUPEB record is in the 2026/2027 session',
            'Your JUPEB application, your subjects and your payments are now filed under the 2026/2027 session, the session you are in. '
            || 'Nothing you paid changes. The letters and slips you printed (and your identity card, if you have one) show 2025/2026: '
            || 'print them again from the JUPEB portal, and each carries a new verification code.');
        n_app := n_app + 1;
    END LOOP;

    -- ── 3 · the attendance registers of this intake ──
    UPDATE attendance.register g SET session = v_to
     WHERE g.context = 'JUPEB' AND g.session = v_from AND g.class_ref IS NULL AND g.held_on >= DATE '2026-09-01'
       AND NOT EXISTS (SELECT 1 FROM attendance.mark m JOIN jupeb.application a ON a.id = m.member_ref
                        WHERE m.register_id = g.id AND a.session = v_from);
    GET DIAGNOSTICS n_reg = ROW_COUNT;

    RAISE NOTICE 'V352: re-filed under %: % window type(s), % application(s) with % payment(s), % attendance register(s); % paper(s) revoked to be printed again',
        v_to, n_win, n_app, n_pay, n_reg, n_paper;
END $$;

COMMIT;

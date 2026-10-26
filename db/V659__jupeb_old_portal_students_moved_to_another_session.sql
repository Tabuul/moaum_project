-- ═══════════════════════════════════════
-- V659 — JUPEB old-portal students moved to another session
--
-- The word of 26 October 2026 ("i uploaded list of jupeb that is supposed to be 2025/2026 session but its enters 2026/2027 can you
-- give me update page to move them to 2025/2026"). Until cf25cb7a the old-portal upload offered only the sessions holding JUPEB
-- records and JUPEB's current session (2026/2027), so students of 2025/2026 were filed under 2026/2027. A student's session is not
-- one column: the subjects registered and the payments carry it, a paper (ID card, statement) states it, a class belongs to one.
-- V352 re-filed a mislabelled intake once, by hand; this is the office's own tool for an old-portal upload, with the same shape:
--   · jupeb.old_portal_sessions(): the sessions an old-portal student may be filed under — every session of the University's
--     calendar up to JUPEB's current one, none cancelled or merged into another, with any session already holding JUPEB records
--     and the current one (the list the upload offers since cf25cb7a, now in one place);
--   · jupeb.move_old_portal_students(ids, to, reason, commit): each student judged — MOVE, or left as they are and why:
--     NOT_OLD_PORTAL (applied on this portal: their session follows their application), SAME_SESSION, WITHDRAWN, BOARD_REGISTERED
--     (sent to the Board for that session), RESULTS (results or CA scores recorded), ATTENDANCE (attendance marked in that
--     session's classes), ACCOUNT_IN_TARGET (the same account already has a record in the session asked); without commit nothing
--     is written; with it each student MOVE is filed under the session asked with the subjects registered and the payments of the
--     session it leaves (references and amounts unchanged), the class of that session left (to be placed in one of the new
--     session's), every paper stating that session revoked to be printed again, and the move with its reason on the student's
--     timeline (SESSION_MOVED). The session asked is one of jupeb.old_portal_sessions() (JUPEB_SESSION); a reason is required
--     (JUPEB_REASON); the JUPEB Office and the platform only (JUPEB_NOT_PERMITTED). Nothing is announced to the students.
-- ═══════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION jupeb.old_portal_sessions() RETURNS SETOF text LANGUAGE sql STABLE AS $$
    SELECT x.session
      FROM (SELECT s.name AS session FROM policy.academic_session s
             WHERE s.state <> 'CANCELLED' AND s.merged_into IS NULL AND s.name <= jupeb.current_session()
            UNION SELECT DISTINCT a.session FROM jupeb.application a
            UNION SELECT jupeb.current_session()) x
     WHERE x.session IS NOT NULL
     ORDER BY x.session DESC
$$;
COMMENT ON FUNCTION jupeb.old_portal_sessions() IS
  'V659: the sessions an old-portal student may be filed under — every session of the University''s calendar up to JUPEB''s current one, none cancelled or merged, with any session holding JUPEB records and the current one';

CREATE OR REPLACE FUNCTION jupeb.move_old_portal_students(p_ids uuid[], p_to text, p_reason text, p_commit boolean) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE a record; v_status text; v_msg text; v_rows jsonb := '[]'::jsonb; n_moved int := 0; n_left int := 0;
        n_subj int; n_pay int; n_paper int; v_class text; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := coalesce(current_setting('moaum.actor_office', true), ''); v_to text := btrim(coalesce(p_to, ''));
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
BEGIN
    IF v_office NOT IN ('jupeb', 'super') THEN
        RAISE EXCEPTION 'JUPEB_NOT_PERMITTED: the JUPEB Office moves old-portal students between sessions' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.old_portal_sessions() s WHERE s = v_to) THEN
        RAISE EXCEPTION 'JUPEB_SESSION: % is not a session old-portal students can be filed under (a session of the calendar up to JUPEB''s current one)',
            coalesce(nullif(v_to, ''), 'that') USING ERRCODE = '23514';
    END IF;
    IF p_commit AND (v_reason IS NULL OR length(v_reason) < 5) THEN
        RAISE EXCEPTION 'JUPEB_REASON: say why the students are moved' USING ERRCODE = '23514';
    END IF;

    FOR a IN SELECT x.*, c.name AS class_name
               FROM jupeb.application x LEFT JOIN jupeb.class c ON c.id = x.class_id
              WHERE x.id = ANY (coalesce(p_ids, '{}'::uuid[]))
              ORDER BY x.surname, x.first_name, x.application_no
              FOR UPDATE OF x LOOP
        n_subj := (SELECT count(*) FROM jupeb.subject_registration r WHERE r.application_id = a.id AND r.session = a.session);
        n_pay := (SELECT count(*) FROM jupeb.fee_reference f WHERE f.application_id = a.id AND f.session = a.session);
        n_paper := (SELECT count(*) FROM jupeb.paper p WHERE p.application_id = a.id AND p.revoked_at IS NULL AND p.facts ->> 'session' = a.session);
        v_class := a.class_name;
        v_status := 'MOVE'; v_msg := NULL;
        IF a.legacy_source IS NULL THEN
            v_status := 'NOT_OLD_PORTAL'; v_msg := 'Applied on this portal: the session follows the application';
        ELSIF a.session = v_to THEN
            v_status := 'SAME_SESSION'; v_msg := 'Already in ' || v_to;
        ELSIF a.state = 'WITHDRAWN' THEN
            v_status := 'WITHDRAWN'; v_msg := 'Withdrawn';
        ELSIF EXISTS (SELECT 1 FROM jupeb.board_registration b WHERE b.application_id = a.id AND b.stage <> 'WITHDRAWN') THEN
            v_status := 'BOARD_REGISTERED'; v_msg := 'Registered with the Board for ' || a.session;
        ELSIF EXISTS (SELECT 1 FROM jupeb.result r WHERE r.application_id = a.id) OR EXISTS (SELECT 1 FROM jupeb.ca_score s WHERE s.application_id = a.id) THEN
            v_status := 'RESULTS'; v_msg := 'Has results or CA scores recorded in ' || a.session;
        ELSIF EXISTS (SELECT 1 FROM attendance.mark m JOIN attendance.register g ON g.id = m.register_id
                       WHERE m.member_ref = a.id AND g.context = 'JUPEB' AND g.session = a.session) THEN
            v_status := 'ATTENDANCE'; v_msg := 'Has attendance marked in ' || a.session || '''s classes';
        ELSIF EXISTS (SELECT 1 FROM jupeb.application o WHERE o.account_id = a.account_id AND o.session = v_to AND o.id <> a.id) THEN
            v_status := 'ACCOUNT_IN_TARGET'; v_msg := 'The same login already has a record in ' || v_to;
        END IF;

        IF v_status = 'MOVE' THEN
            v_msg := concat_ws('; ', n_subj || ' subject' || CASE WHEN n_subj = 1 THEN '' ELSE 's' END || ' and ' || n_pay || ' payment'
                                     || CASE WHEN n_pay = 1 THEN '' ELSE 's' END || ' move with the student (references and amounts unchanged)',
                               CASE WHEN v_class IS NOT NULL THEN 'class ' || v_class || ' of ' || a.session || ' left: place them in a ' || v_to || ' class' END,
                               CASE WHEN n_paper > 0 THEN n_paper || ' paper' || CASE WHEN n_paper = 1 THEN '' ELSE 's' END || ' stating ' || a.session
                                                          || ' revoked, to be printed again' END);
            IF p_commit THEN
                UPDATE jupeb.application SET session = v_to, class_id = NULL, updated_at = now() WHERE id = a.id;
                UPDATE jupeb.subject_registration SET session = v_to WHERE application_id = a.id AND session = a.session;
                UPDATE jupeb.fee_reference SET session = v_to WHERE application_id = a.id AND session = a.session;
                UPDATE jupeb.paper SET revoked_at = now(), revoked_by = v_actor,
                       revoked_reason = 'Moved from ' || a.session || ' to ' || v_to || ': this paper states ' || a.session || '; printed again it states ' || v_to
                 WHERE application_id = a.id AND revoked_at IS NULL AND facts ->> 'session' = a.session;
                PERFORM jupeb.app_event(a.id, 'SESSION_MOVED', 'Moved from ' || a.session || ' to ' || v_to || ': ' || v_reason || '. ' || v_msg);
            END IF;
            n_moved := n_moved + 1;
        ELSE
            n_left := n_left + 1;
        END IF;
        v_rows := v_rows || jsonb_build_object('applicationId', a.id, 'applicationNo', a.application_no,
            'name', a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), 'session', a.session, 'state', a.state,
            'status', v_status, 'message', v_msg, 'subjects', n_subj, 'payments', n_pay, 'papers', n_paper, 'className', v_class, 'batch', a.legacy_batch);
    END LOOP;
    RETURN jsonb_build_object('to', v_to, 'committed', p_commit, 'moved', CASE WHEN p_commit THEN n_moved ELSE 0 END,
                              'movable', n_moved, 'left', n_left, 'rows', v_rows);
END $$;
COMMENT ON FUNCTION jupeb.move_old_portal_students(uuid[], text, text, boolean) IS
  'V659: old-portal students filed under another session — judged (MOVE, or NOT_OLD_PORTAL, SAME_SESSION, WITHDRAWN, BOARD_REGISTERED, RESULTS, ATTENDANCE, ACCOUNT_IN_TARGET); on commit the session, the subjects and payments of the session left (references and amounts unchanged), the class left, the papers stating it revoked, the move on the timeline';

COMMIT;

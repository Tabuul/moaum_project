-- ═══════════════════════════════════════
-- V671 — graduation notices: the student told when only the Bursary remains, the Bursar told of the students newly ready
--
-- The word of 27 October 2026 ("do 1": tell people when only the Bursary remains). Since V665 the Bursary's stage of a final
-- clearance is last and its clearance graduates the student; since V668 the Bursar has the queue (clearance.ready_to_graduate).
-- Nobody was told when a student reached it.
--
--   · clearance.tell_bursary_turn(limit): every student whose award is approved, not yet GRADUATED, and whose final clearance
--     waits only on the Bursary (the queue) is told once (event key bursary-turn:<process>): every other office has cleared you;
--     the Bursary clears you last and its clearance graduates you — with nothing owed, it will confirm; with school fees owed
--     (STUDENT_BURSARY_TURN:OWING), the amount and each session and semester owed, and where to pay; with a period still being
--     assessed and nothing owed (STUDENT_BURSARY_TURN:ASSESSING), that it is being assessed and nothing is owed for it yet.
--   · clearance.tell_bursar_ready(): the students newly ready (nothing owed, nothing being assessed) since the last digest
--     (clearance.ready_seen keeps who was announced) are told to every person holding the Bursar's office, in one message: how
--     many are newly ready, how many are ready in all, up to twenty names, and where to confirm (BURSAR_READY_TO_GRADUATE). Nothing
--     is sent when nobody is newly ready.
--   · Both run each morning with the clearance reminders (ClearanceReminders, 08:40 Lagos).
-- ═══════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V671: graduation notices — the Bursary''s turn told to the student, the newly ready told to the Bursar', true);

-- ── 1 · the texts ───────────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('STUDENT_BURSARY_TURN', 'Final clearance: only the Bursary remains',
 'To a student whose award is approved, once every office but the Bursary has cleared the final clearance and nothing is owed',
 'Your final clearance: only the Bursary remains ([REFERENCE])',
 E'Dear [FIRST_NAME],\n\nEvery office has cleared you for your final clearance ([REFERENCE]) except the Bursary, which clears you last. Nothing is owed on your school fees for any session, so the Bursary will confirm your final clearance; its confirmation graduates you, and your record then reads GRADUATED.\n\nFollow it on My Clearance: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Registry',
 '[UNIVERSITY_SHORT]: every office but the Bursary has cleared your final clearance ([REFERENCE]); nothing is owed. The Bursar''s confirmation graduates you. See My Clearance.',
 'Only the Bursary remains',
 'Every office but the Bursary has cleared your final clearance ([REFERENCE]). Nothing is owed; the Bursar''s confirmation graduates you.',
 ARRAY['FIRST_NAME','REFERENCE','PORTAL_URL','UNIVERSITY_SHORT'], true, 'HIGH'),
('STUDENT_BURSARY_TURN:ASSESSING', 'Final clearance: only the Bursary remains, a semester being assessed',
 'To a student whose award is approved, once every office but the Bursary has cleared the final clearance, while a past semester is still being assessed',
 'Your final clearance: only the Bursary remains ([REFERENCE])',
 E'Dear [FIRST_NAME],\n\nEvery office has cleared you for your final clearance ([REFERENCE]) except the Bursary, which clears you last and whose clearance graduates you. Nothing is owed on your school fees now, but [BEING_ASSESSED] still being assessed by the Bursary from the University''s fees of the period; nothing is owed for it until an amount is approved, and you will be told. Once it is settled the Bursar confirms your final clearance and your record reads GRADUATED.\n\nMy Clearance: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: only the Bursary remains on your final clearance ([REFERENCE]); a past semester is being assessed. Nothing is owed until an amount is approved. See My Clearance.',
 'Only the Bursary remains',
 'Every office but the Bursary has cleared your final clearance ([REFERENCE]). [BEING_ASSESSED] still being assessed by the Bursary; nothing is owed for it until an amount is approved.',
 ARRAY['FIRST_NAME','REFERENCE','BEING_ASSESSED','PORTAL_URL','UNIVERSITY_SHORT'], true, 'HIGH'),
('STUDENT_BURSARY_TURN:OWING', 'Final clearance: only the Bursary remains, school fees owed',
 'To a student whose award is approved, once every office but the Bursary has cleared the final clearance, while school fees are owed',
 'Your final clearance: school fees of [OUTSTANDING] stand between you and graduation ([REFERENCE])',
 E'Dear [FIRST_NAME],\n\nEvery office has cleared you for your final clearance ([REFERENCE]) except the Bursary, which clears you last and whose clearance graduates you. It cannot clear you while school fees are owed:\n\n[OWING]\n\nTotal outstanding: [OUTSTANDING][BEING_ASSESSED]. Pay it on your portal (Fees → Historical school fees) or ask the Bursary; once nothing is owed, the Bursar confirms your final clearance and your record reads GRADUATED.\n\nMy Clearance: [PORTAL_URL]\n\n[UNIVERSITY_SHORT] Bursary',
 '[UNIVERSITY_SHORT]: only the Bursary remains on your final clearance ([REFERENCE]); school fees of [OUTSTANDING] are owed. Pay on your portal; the Bursar''s clearance then graduates you.',
 'School fees stand between you and graduation',
 'Every office but the Bursary has cleared your final clearance ([REFERENCE]). [OUTSTANDING] is owed ([OWING_SHORT]); once paid, the Bursar''s confirmation graduates you.',
 ARRAY['FIRST_NAME','REFERENCE','OUTSTANDING','OWING','OWING_SHORT','BEING_ASSESSED','PORTAL_URL','UNIVERSITY_SHORT'], true, 'HIGH'),
('BURSAR_READY_TO_GRADUATE', 'Students ready to graduate',
 'To the Bursar''s office when students become ready to graduate: every other office has cleared their final clearance and nothing is owed',
 '[COUNT] student(s) ready to graduate — your confirmation awaited',
 E'Dear [FIRST_NAME],\n\n[COUNT] student(s) became ready to graduate since the last notice ([TOTAL] ready in all): every other office has cleared their final clearance and nothing is owed for any session.\n\n[NAMES]\n\nConfirm their final clearance on Ready to Graduate: [PORTAL_URL]/clearance/ready — each is checked again, and graduated or refused with the reason.\n\n[UNIVERSITY_SHORT] Registry',
 NULL,
 'Students ready to graduate',
 '[COUNT] student(s) became ready to graduate ([TOTAL] ready in all). Confirm them on Ready to Graduate.',
 ARRAY['FIRST_NAME','COUNT','TOTAL','NAMES','PORTAL_URL','UNIVERSITY_SHORT'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── 2 · who was announced to the Bursar as ready ────────────────────────────────────────────────────────────────────────────
CREATE TABLE clearance.ready_seen (
    process_id uuid PRIMARY KEY REFERENCES clearance.process (id) ON DELETE CASCADE,
    seen_at timestamptz NOT NULL DEFAULT now()
);
SELECT audit.exempt('clearance.ready_seen', 'V671: a record of which final clearances were announced to the Bursar as ready, so each is announced once; the notices themselves are on the notice queue');
COMMENT ON TABLE clearance.ready_seen IS 'V671: the final clearances announced to the Bursar as ready to graduate (clearance.tell_bursar_ready), each once';

-- ── 3 · the student told once that only the Bursary remains ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.tell_bursary_turn(p_limit integer DEFAULT 2000) RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE r record; n int := 0; v_lines text; v_short text; v_assessed text;
BEGIN
    FOR r IN SELECT * FROM clearance.ready_to_graduate(NULL, NULL, NULL, NULL, greatest(1, least(coalesce(p_limit, 2000), 5000))) x
              WHERE NOT EXISTS (SELECT 1 FROM platform.notice nn WHERE nn.event_key = 'bursary-turn:' || x.process_id) LOOP
        -- a period with no amount yet: "1 semester is" / "2 semesters are" (the ASSESSING text), a note in brackets beside what is owed
        v_assessed := CASE WHEN r.review_periods + r.pending_periods = 1 THEN '1 semester of your record is'
                           WHEN r.review_periods + r.pending_periods > 1 THEN (r.review_periods + r.pending_periods) || ' semesters of your record are'
                           ELSE '' END;
        IF r.outstanding >= 1 THEN
            SELECT string_agg('· ' || x.session || ', ' || lower(finance.semester_words(x.semester)) || ': ' || clearance.naira(x.outstanding), E'\n' ORDER BY x.session, x.semester),
                   string_agg(x.session || ' S' || x.semester, ', ' ORDER BY x.session, x.semester)
              INTO v_lines, v_short FROM finance.historical_rows(ARRAY[r.student_id]) x WHERE x.outstanding > 0;
            PERFORM platform.tell_student(r.student_id, 'STUDENT_BURSARY_TURN', 'OWING',
                jsonb_build_object('REFERENCE', r.reference, 'OUTSTANDING', clearance.naira(r.outstanding), 'OWING', coalesce(v_lines, ''),
                                   'OWING_SHORT', coalesce(v_short, ''),
                                   'BEING_ASSESSED', CASE WHEN v_assessed = '' THEN '' ELSE ' (besides, ' || v_assessed || ' still being assessed; nothing is owed for it until an amount is approved)' END),
                'bursary-turn:' || r.process_id);
        ELSIF v_assessed <> '' THEN
            PERFORM platform.tell_student(r.student_id, 'STUDENT_BURSARY_TURN', 'ASSESSING',
                jsonb_build_object('REFERENCE', r.reference, 'BEING_ASSESSED', v_assessed), 'bursary-turn:' || r.process_id);
        ELSE
            PERFORM platform.tell_student(r.student_id, 'STUDENT_BURSARY_TURN', NULL, jsonb_build_object('REFERENCE', r.reference), 'bursary-turn:' || r.process_id);
        END IF;
        n := n + 1;
    END LOOP;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION clearance.tell_bursary_turn(integer) IS
  'V671: every student in the Bursar''s queue (an approved award, every other office cleared) not yet told is told once — with nothing owed, that the Bursary will confirm and graduate them; with school fees owed, the amount, each session and semester owed and where to pay (STUDENT_BURSARY_TURN, :OWING); a semester being assessed said as such. Returns how many students were told.';

-- ── 4 · the Bursar told of the students newly ready ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.tell_bursar_ready() RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE v_new uuid[]; v_total int; v_names text; v_more int; v_key text; p record; n int := 0; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    WITH q AS (SELECT * FROM clearance.ready_to_graduate(NULL, NULL, NULL, NULL, 5000) x WHERE x.ready)
    SELECT (SELECT coalesce(array_agg(q.process_id ORDER BY q.surname, q.other_names), '{}'::uuid[]) FROM q WHERE NOT EXISTS (SELECT 1 FROM clearance.ready_seen s WHERE s.process_id = q.process_id)),
           (SELECT count(*)::int FROM q)
      INTO v_new, v_total;
    IF cardinality(v_new) = 0 THEN RETURN 0; END IF;
    INSERT INTO clearance.ready_seen (process_id) SELECT unnest(v_new) ON CONFLICT (process_id) DO NOTHING;
    SELECT string_agg('· ' || s.surname || ', ' || s.other_names || ' (' || coalesce(s.matric_no, q.reference) || ')', E'\n' ORDER BY s.surname, s.other_names)
      INTO v_names
      FROM (SELECT x.id AS process_id, x.reference, x.student_id FROM clearance.process x WHERE x.id = ANY (v_new)) q
      JOIN people.student s ON s.id = q.student_id
     WHERE q.process_id = ANY (v_new[1:20]);
    v_more := cardinality(v_new) - 20;
    IF v_more > 0 THEN v_names := v_names || E'\n· and ' || v_more || ' more'; END IF;
    -- one message per batch of newly ready students: the key names the batch, so a re-run never repeats it
    v_key := 'ready-digest:' || md5(array_to_string(v_new, ','));
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code = 'bursar' AND oa.valid_from <= v_today AND (oa.valid_to IS NULL OR oa.valid_to >= v_today) LOOP
        n := n + platform.tell_person(p.person_id, 'BURSAR_READY_TO_GRADUATE', NULL,
                 jsonb_build_object('COUNT', cardinality(v_new), 'TOTAL', v_total, 'NAMES', coalesce(v_names, '')), v_key || ':' || p.person_id);
    END LOOP;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION clearance.tell_bursar_ready() IS
  'V671: the students newly ready to graduate (in the queue with nothing owed or being assessed, not announced before — clearance.ready_seen) told to every person holding the Bursar''s office in one message (BURSAR_READY_TO_GRADUATE: how many newly, how many in all, up to twenty names); nothing sent when nobody is newly ready. Returns how many notices were queued.';

COMMIT;

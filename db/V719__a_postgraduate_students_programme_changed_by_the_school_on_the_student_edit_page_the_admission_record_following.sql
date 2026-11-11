-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V719 · A postgraduate student's programme changed by the School of Postgraduate Studies on the student edit page — by the
--  programme swap, the admission record following, the history kept
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's brief of 11 November 2026, "PG STUDENT EDIT – PROGRAMME CHANGE FUNCTIONALITY": an authorised PG School
--  administrator opens a postgraduate student's record, picks another approved postgraduate programme (searchable; faculty,
--  department and degree type shown), gives a reason, confirms current against proposed, saves; the change reaches the profile,
--  dashboards, admission and registration records and reports; the application number, admission history, payments, documents and
--  history are preserved; the audit log holds the previous and new programme, who, when and why; existing RBAC and approval
--  workflows apply; no duplicate record; no parallel module.
--
--  Inspect-first: nothing rebuilt. The student edit page (V642) changes a student's programme by the programme swap (V578, made at
--  once by the officer who initiates it since V633): a searchable faculty → department → programme → level picker, the change
--  checked first (refusals, registrations, fees), a reason of ten characters or more, the swap kept on people.programme_swap with
--  the placement before and after, who prepared and decided it and when, the student record's change on the audit spine, the
--  swap on the student's edit history and programme history (V669), the student told. V715 opened the page to the School
--  (pgschool, pgsecretary) and the Director of ICT for a postgraduate student and granted them EDIT_STUDENT_PROGRAMME. The check
--  already refuses a postgraduate record on an undergraduate programme and the reverse (PSW_CATEGORY), an archived programme, a
--  level the programme has not (700, 800, 900 for a postgraduate programme), a transfer or change request under way.
--
--  What was missing:
--   · people.programme_swap_office_prepares named the Academic Office, the Registry, the Director of ICT and super alone, so the
--     School's officer saw the control and was refused (PSW_OFFICE) — and the API's office lists (and the structure the picker is
--     filled from) refused them first. Now people.programme_swap_office_prepares_for(office, student): the offices above anywhere;
--     the School of Postgraduate Studies (pgschool, pgsecretary) for a postgraduate student (people.is_postgraduate), never for an
--     undergraduate. prepare_programme_swap and decide_programme_swap read it.
--   · The postgraduate profile, dashboards, fee references and reports read the programme on the admission record
--     (admissions.pg_application.programme_code), which a swap did not touch: the register said one programme and the portal
--     another. Now a completed swap of a postgraduate student carries the admission record with it — the application's programme
--     set to the new one, a specialisation of the old programme let go (catalogue.programme_specialisation belongs to a programme),
--     the application number, state, decision, dates, payments and documents untouched — and writes a PROGRAMME_CHANGED event on
--     the application's own history (admissions.pg_application_event) naming the swap, the programmes before and after and the
--     reason. The swap row keeps the placement before and after as it did.
--  The degree type (admissions.pg_award_of) is shown by the picker and the confirmation on the frontend from the structure the
--  API gives (ProgrammeSwapController /structure gains award); the confirmation of current against proposed and the notifications
--  are the page's. Nothing of the record is deleted or overwritten beyond the programme and level the swap has always changed.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1 · who prepares a swap for whom ──
CREATE OR REPLACE FUNCTION people.programme_swap_office_prepares_for(p_office text, p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT people.programme_swap_office_prepares(coalesce(p_office, ''))
        OR (coalesce(p_office, '') IN ('pgschool', 'pgsecretary')
            AND EXISTS (SELECT 1 FROM people.student s JOIN ref.programme g ON g.code = s.programme_code
                         WHERE s.id = p_student AND people.is_postgraduate(s.entry_mode, g.category)))
$$;
COMMENT ON FUNCTION people.programme_swap_office_prepares_for(text, uuid) IS
  'V719: who may make a programme swap for this student — the Academic Office, the Registry, the Director of ICT and super for anyone (V578); the School of Postgraduate Studies (pgschool, pgsecretary) for a postgraduate student alone.';

-- ── 2 · the swap prepared (V669 restated): the School for a postgraduate student ──
CREATE OR REPLACE FUNCTION people.prepare_programme_swap(p_student uuid, p_to_programme text, p_to_level integer, p_session text, p_kind text, p_reason text, p_batch uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        chk jsonb; v_id uuid; v_ref text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a programme swap is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares_for(coalesce(office, ''), p_student) THEN   -- V719: the School, for a postgraduate student
        RAISE EXCEPTION 'PSW_OFFICE: a programme swap is prepared by the Academic Office, the Registry or the Director of ICT — or, for a postgraduate student, the School of Postgraduate Studies' USING ERRCODE = '42501';
    END IF;
    IF p_kind IS NULL OR p_kind NOT IN ('LEGACY_MIGRATION_CORRECTION', 'PROGRAMME_CORRECTION', 'ACADEMIC_TRANSFER', 'APPROVED_TRANSFER_RESTORED') THEN
        RAISE EXCEPTION 'PSW_KIND: say what the swap is — a legacy migration correction, a programme correction, an academic transfer recorded or an approved transfer restored' USING ERRCODE = '23514';
    END IF;
    -- V669: a transfer approved on the old portal is restored with its record (people.restore_approved_transfer), never as a plain swap
    IF p_kind = 'APPROVED_TRANSFER_RESTORED' AND coalesce(current_setting('moaum.transfer_restore', true), '') <> 'on' THEN
        RAISE EXCEPTION 'PSW_KIND: a transfer approved on the old portal is restored by Restore an approved transfer, which records it; not as a plain swap' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PSW_REASON: say why the placement is corrected, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    chk := people.programme_swap_check(p_student, p_to_programme, p_to_level, p_session, NULL);
    IF NOT (chk->>'ok')::boolean THEN
        RAISE EXCEPTION '%', chk->'refusals'->>0 USING ERRCODE = '23514';
    END IF;
    v_ref := 'PSW/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('people.programme_swap_seq')::text, 6, '0');
    INSERT INTO people.programme_swap (swap_ref, student_id, kind, change, from_programme, from_dept, from_faculty, from_level,
                                       to_programme, to_dept, to_faculty, to_level, effective_session, reason, review, batch_id, prepared_by, prepared_office)
    VALUES (v_ref, p_student, p_kind, chk->>'change', chk->'from'->>'programme', chk->'from'->>'dept', chk->'from'->>'faculty', (chk->'from'->>'level')::int,
            chk->'to'->>'programme', chk->'to'->>'dept', chk->'to'->>'faculty', (chk->'to'->>'level')::int, chk->>'session', btrim(p_reason),
            coalesce(chk->'warnings', '[]'::jsonb), p_batch, who, office)
    RETURNING id INTO v_id;
    -- the finding, where one was recorded, now says a swap is on its way
    INSERT INTO people.programme_mismatch_review (student_id, status, note, reviewed_by, reviewed_office)
    VALUES (p_student, 'SWAP_REQUIRED', 'Swap ' || v_ref || ' prepared', who, office)
    ON CONFLICT (student_id) DO UPDATE SET status = 'SWAP_REQUIRED', note = EXCLUDED.note, reviewed_by = EXCLUDED.reviewed_by,
        reviewed_office = EXCLUDED.reviewed_office, reviewed_at = now()
     WHERE people.programme_mismatch_review.status NOT IN ('SWAPPED');
    -- V633: the officer who initiates the swap makes it — decided at once, by the same officer; the swap is COMPLETED on return
    PERFORM people.decide_programme_swap(v_id, true, NULL);
    RETURN v_id;
END $function$;
COMMENT ON FUNCTION people.prepare_programme_swap(uuid, text, integer, text, text, text, uuid) IS
  'V578, V633, V669, V719: a programme swap made by the officer who initiates it — the check must pass; the placement before and after and the review points are kept on the swap, and it is decided at once by the same officer. The Academic Office, the Registry, the Director of ICT, super; the School of Postgraduate Studies for a postgraduate student.';

-- ── 3 · the swap decided (V633 restated): the School for a postgraduate student; a postgraduate's admission record follows ──
CREATE OR REPLACE FUNCTION people.decide_programme_swap(p_id uuid, p_approve boolean, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        x people.programme_swap; chk jsonb; v_before jsonb; v_after jsonb; v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_pg boolean; a record; n_apps int := 0;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a programme swap is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO x FROM people.programme_swap WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PSW_NOT_FOUND: no such programme swap' USING ERRCODE = 'P0002'; END IF;
    IF x.status <> 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'PSW_DECIDED: this swap is already %', lower(x.status) USING ERRCODE = '23514';
    END IF;
    IF NOT (people.programme_swap_office_decides(coalesce(office, ''), x.kind) OR people.programme_swap_office_prepares_for(coalesce(office, ''), x.student_id)) THEN
        RAISE EXCEPTION 'PSW_OFFICE: a programme swap is decided by the Academic Office, the Registry or the Director of ICT — or, for a postgraduate student, the School of Postgraduate Studies' USING ERRCODE = '42501';
    END IF;
    IF NOT p_approve THEN
        IF v_note IS NULL OR length(v_note) < 10 THEN RAISE EXCEPTION 'PSW_REASON: say why the swap is rejected' USING ERRCODE = '23514'; END IF;
        UPDATE people.programme_swap SET status = 'REJECTED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note WHERE id = x.id;
        UPDATE people.programme_mismatch_review SET status = 'UNDER_REVIEW', note = 'Swap ' || x.swap_ref || ' rejected: ' || v_note, reviewed_by = who,
               reviewed_office = office, reviewed_at = now() WHERE student_id = x.student_id AND status = 'SWAP_REQUIRED';
        RETURN jsonb_build_object('id', x.id, 'swapRef', x.swap_ref, 'status', 'REJECTED');
    END IF;

    -- the check again, on the record as it stands now: what has changed since the swap was prepared fails it, nothing written
    chk := people.programme_swap_check(x.student_id, x.to_programme, x.to_level, x.effective_session, x.id);
    IF NOT (chk->>'ok')::boolean OR chk->'from'->>'programme' IS DISTINCT FROM x.from_programme OR (chk->'from'->>'level')::int IS DISTINCT FROM x.from_level THEN
        UPDATE people.programme_swap SET status = 'FAILED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note,
               failure = coalesce(chk->'refusals'->>0, 'PSW_CHANGED: the record changed since the swap was prepared (' || (chk->'from'->>'programme') || ' at '
                                  || coalesce(chk->'from'->>'level', '—') || ' Level now); prepare it again')
         WHERE id = x.id;
        RETURN jsonb_build_object('id', x.id, 'swapRef', x.swap_ref, 'status', 'FAILED', 'failure', (SELECT failure FROM people.programme_swap WHERE id = x.id));
    END IF;

    SELECT people.is_postgraduate(st.entry_mode, g.category) INTO v_pg FROM people.student st JOIN ref.programme g ON g.code = st.programme_code WHERE st.id = x.student_id;
    SELECT to_jsonb(st) INTO v_before FROM people.student st WHERE st.id = x.student_id;
    UPDATE people.student SET programme_code = x.to_programme, current_level = x.to_level WHERE id = x.student_id;
    SELECT to_jsonb(st) INTO v_after FROM people.student st WHERE st.id = x.student_id;
    -- V719: a postgraduate's admission record follows the register — the application's programme (what the postgraduate portal,
    -- the fee references and the School's desks read), a specialisation of the old programme let go; the number, the state, the
    -- decision, the payments and the documents untouched; the change on the application's own history
    IF coalesce(v_pg, false) THEN
        FOR a IN SELECT ap.id, ap.application_no, ap.programme_code, ap.specialisation_id
                   FROM admissions.pg_application ap WHERE ap.student_id = x.student_id AND ap.programme_code IS DISTINCT FROM x.to_programme
                   ORDER BY ap.created_at
        LOOP
            UPDATE admissions.pg_application ap
               SET programme_code = x.to_programme,
                   specialisation_id = CASE WHEN ap.specialisation_id IS NOT NULL
                                             AND EXISTS (SELECT 1 FROM catalogue.programme_specialisation ps WHERE ps.id = ap.specialisation_id AND ps.programme_code = x.to_programme)
                                            THEN ap.specialisation_id END
             WHERE ap.id = a.id;
            PERFORM admissions.pg_app_event(a.id, 'PROGRAMME_CHANGED',
                'Programme changed by programme swap ' || x.swap_ref || ': ' || a.programme_code || ' → ' || x.to_programme
                || CASE WHEN a.specialisation_id IS NOT NULL AND (SELECT ps.programme_code FROM catalogue.programme_specialisation ps WHERE ps.id = a.specialisation_id) <> x.to_programme
                        THEN ' (the specialisation of the old programme let go)' ELSE '' END
                || ' — ' || x.reason);
            n_apps := n_apps + 1;
        END LOOP;
    END IF;
    UPDATE people.programme_swap
       SET status = 'COMPLETED', decided_by = who, decided_office = office, decided_at = now(), decision_note = v_note, executed_at = now(),
           before_state = v_before - 'curriculum_version', after_state = v_after - 'curriculum_version', impact = chk->'registration', review = chk->'warnings'
     WHERE id = x.id;
    INSERT INTO people.programme_mismatch_review (student_id, status, note, reviewed_by, reviewed_office)
    VALUES (x.student_id, 'SWAPPED', 'Swap ' || x.swap_ref || ' completed', who, office)
    ON CONFLICT (student_id) DO UPDATE SET status = 'SWAPPED', note = EXCLUDED.note, reviewed_by = EXCLUDED.reviewed_by,
        reviewed_office = EXCLUDED.reviewed_office, reviewed_at = now();
    -- the student is told the new placement and whom to ask; nothing of the migration
    BEGIN
        PERFORM platform.tell_student(x.student_id, 'PROGRAMME_SWAP_COMPLETED', NULL,
            jsonb_build_object('NEW_PROGRAMME', chk->'to'->>'programmeName', 'NEW_DEPARTMENT', coalesce(chk->'to'->>'department', ''),
                               'NEW_LEVEL', x.to_level::text, 'SESSION', x.effective_session),
            'PROGRAMME_SWAP_COMPLETED:' || x.id::text);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'programme swap %: the student could not be told (%)', x.swap_ref, SQLERRM;
    END;
    RETURN jsonb_build_object('id', x.id, 'swapRef', x.swap_ref, 'status', 'COMPLETED', 'impact', chk->'registration', 'applications', n_apps);
END $fn$;
COMMENT ON FUNCTION people.decide_programme_swap(uuid, boolean, text) IS
  'V578, V633, V719: a pending programme swap rejected, or approved and executed at once, by any officer who may prepare one for the student (the one who prepared it included; the School for a postgraduate) — the check run again on the record as it stands (a change since fails the swap, nothing written); the student''s programme and level changed, the placement before and after kept on the swap; a postgraduate''s admission record (admissions.pg_application) following with a PROGRAMME_CHANGED event; the student told.';

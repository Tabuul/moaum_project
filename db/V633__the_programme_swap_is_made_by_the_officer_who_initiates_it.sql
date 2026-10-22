-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V633 — The programme swap is made by the officer who initiates it
--
--   The University's word of 22 October 2026: "programme swap should remove level of approval; the person that initiates the
--   swap should also be the one to approve it and move the student to the right programme".
--
--   V578 had a swap prepared by one officer and decided by another (PSW_SAME_OFFICER; the check constraint
--   ck_programme_swap_other_officer), the Director of ICT deciding a legacy migration correction and no other. Now:
--     · people.prepare_programme_swap — restated exactly as V578 wrote it, and then the swap is decided at once by the same
--       officer (people.decide_programme_swap with approve): the check having passed a moment before, the student's programme and
--       level are set, the row before and after and the registration impact are kept on the swap, the finding reads swapped and
--       the student is told. The swap is COMPLETED when the function returns; nothing waits for anyone. The desk's bulk swap and
--       the bulk inter-departmental transfer (V587) ride on this function, so their students move at once as well.
--     · people.decide_programme_swap — restated without the two-officer rule: who may prepare a swap decides one, the Director of
--       ICT any kind. It still decides a swap left pending from before V633 (the API's /{id}/decide and /batches/{id}/decide), and
--       still runs the check again on the record as it stands (a change since fails the swap, nothing written).
--     · people.programme_swap_office_decides(office, kind) is people.programme_swap_office_prepares(office).
--     · ck_programme_swap_other_officer is dropped: decided_by may equal prepared_by.
--   Nothing of the record is lost: every swap keeps who prepared and who decided it (the same person now), the placement before
--   and after, the reason, the review points and its audit entries; the old placement stays in people.programme_history.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE people.programme_swap DROP CONSTRAINT ck_programme_swap_other_officer;
COMMENT ON TABLE people.programme_swap IS
  'V578, V633: a student''s current programme, department, faculty and level corrected by an office (PSW/YYYY/NNNNNN) — the placement before and after, the kind, the reason, the review points, who prepared and who decided it (the same officer since V633), the student row before and after, the registration impact; the old placement stays here and in people.programme_history';

-- who may prepare a swap decides one
CREATE OR REPLACE FUNCTION people.programme_swap_office_decides(p_office text, p_kind text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT people.programme_swap_office_prepares(p_office) $$;
COMMENT ON FUNCTION people.programme_swap_office_decides(text, text) IS
  'V633: the offices that prepare a programme swap decide one — the Academic Office, the Registry, the Director of ICT, super — whatever its kind';

-- V578's decide, without the two-officer rule
CREATE OR REPLACE FUNCTION people.decide_programme_swap(p_id uuid, p_approve boolean, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        x people.programme_swap; chk jsonb; v_before jsonb; v_after jsonb; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a programme swap is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO x FROM people.programme_swap WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PSW_NOT_FOUND: no such programme swap' USING ERRCODE = 'P0002'; END IF;
    IF x.status <> 'PENDING_APPROVAL' THEN
        RAISE EXCEPTION 'PSW_DECIDED: this swap is already %', lower(x.status) USING ERRCODE = '23514';
    END IF;
    IF NOT people.programme_swap_office_decides(coalesce(office, ''), x.kind) THEN
        RAISE EXCEPTION 'PSW_OFFICE: a programme swap is decided by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
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

    SELECT to_jsonb(st) INTO v_before FROM people.student st WHERE st.id = x.student_id;
    UPDATE people.student SET programme_code = x.to_programme, current_level = x.to_level WHERE id = x.student_id;
    SELECT to_jsonb(st) INTO v_after FROM people.student st WHERE st.id = x.student_id;
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
    RETURN jsonb_build_object('id', x.id, 'swapRef', x.swap_ref, 'status', 'COMPLETED', 'impact', chk->'registration');
END $fn$;
COMMENT ON FUNCTION people.decide_programme_swap(uuid, boolean, text) IS
  'V578, V633: a pending programme swap rejected, or approved and executed at once, by any officer who may prepare one (the one who prepared it included) — the check run again on the record as it stands (a change since fails the swap, nothing written), then the student''s programme and level set, the row before and after and the registration impact kept, the student told';

-- V578's prepare, and then the swap made at once by the same officer
CREATE OR REPLACE FUNCTION people.prepare_programme_swap(p_student uuid, p_to_programme text, p_to_level integer, p_session text, p_kind text, p_reason text,
                                                         p_batch uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        chk jsonb; v_id uuid; v_ref text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a programme swap is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'PSW_OFFICE: a programme swap is prepared by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF p_kind IS NULL OR p_kind NOT IN ('LEGACY_MIGRATION_CORRECTION', 'PROGRAMME_CORRECTION', 'ACADEMIC_TRANSFER') THEN
        RAISE EXCEPTION 'PSW_KIND: say what the swap is — a legacy migration correction, a programme correction or an academic transfer recorded' USING ERRCODE = '23514';
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
END $fn$;
COMMENT ON FUNCTION people.prepare_programme_swap(uuid, text, integer, text, text, text, uuid) IS
  'V578, V633: a programme swap made by the officer who initiates it — the check must pass; the placement before and after and the review points are kept on the swap, and it is decided at once by the same officer: the student''s programme and level set, the student told, the swap COMPLETED on return';

COMMENT ON FUNCTION people.prepare_transfer_batch(jsonb, text, text, text, text, boolean) IS
  'V587, V633: a bulk inter-departmental transfer made (IDT/YYYY/NNNNNN) — the rows checked again, a programme swap (ACADEMIC_TRANSFER) made under the batch for each valid row by the officer who uploads it, the students moved at once, every row kept with its result; refused while a row is invalid unless the valid rows alone are asked for.';
COMMENT ON TABLE people.transfer_batch IS
  'V587, V633: a bulk inter-departmental transfer (IDT/YYYY/NNNNNN) — the file, the session, the reason, how many rows, made as programme swaps and skipped; the swaps carry its id as their batch and are made at once by the officer who uploads it.';

COMMIT;

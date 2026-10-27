-- V669. A transfer approved on the old portal restored without a new application; the matriculation number never places a student —
-- the University's master prompt of 27 October 2026 ("Inter-departmental transfer migration correction, Academic Office direct placement
-- & matriculation number preservation").
--
-- Students who had moved department on the old portal, with Senate's approval, keep the matriculation number of the department they
-- left. On this portal they were found in that department again: the programme-mismatch list (people.programme_mismatches, V578) read
-- the department the matriculation number names, and where the registrations migrated from before the transfer agreed, it called the
-- student a CONFIRMED mismatch and suggested the old department — or, the number alone differing, suggested it all the same; an old-portal
-- student file uploaded again (people.import_students_rows, people.import_biography_rows) wrote its programme over whatever the record held.
-- And the Academic Office, putting them right, had only the transfer desk's "Record an application", which starts the transfer again from
-- the first desk, the fee and Senate included.
--
-- What stands already: the matriculation number never changes (people.matric_is_immutable, V013/V579: only a matriculation correction
-- changes it; no transfer, swap or record move touches it), and the programme swap (V578, V633) moves a student's programme and level at
-- once, the history kept. V669:
--
--   people.prior_transfer — a transfer approved on the old portal: from, to, the levels, the session and semester it took effect, the date
--     approved and the old portal's reference. History, not an application: nothing of the transfer workflow reads it.
--   programme swap kind APPROVED_TRANSFER_RESTORED; people.restore_transfer_check and people.restore_approved_transfer — the student put
--     on the approved programme and level by the swap (made at once, by the officer, as every swap since V633), the old portal's transfer
--     recorded, an application left in the transfer queue to that same programme withdrawn with the reason; no application, no fee, no
--     approval, the matriculation number untouched. A student on that programme already: the transfer recorded, nothing moved.
--   The bulk transfer (V587) gains the restoration: a batch of kind APPROVED_TRANSFER_RESTORED (TRR/YYYY/NNNNNN), each row checked on its
--     own (people.restore_upload_check), the valid ones restored.
--   people.programme_mismatches — the matriculation number alone never suggests a department; a student whose programme a recorded move
--     set (an effected transfer, a programme swap, a transfer approved on the old portal) is not judged by the number, and only the
--     registrations since that move count.
--   people.placement_settled; the old-portal uploads keep a placement this portal recorded and put the file's to the Academic Office
--     (people.placement_conflict, people.placement_conflicts, people.decide_placement_conflict).
--   people.programme_history — the transfer approved on the old portal in the student's programme history.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V669: transfers approved on the old portal restored without a new application (the University, 27 October 2026)', true);

-- ── the transfers approved on the old portal ──
CREATE TABLE people.prior_transfer (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    from_programme text NOT NULL REFERENCES ref.programme(code),
    to_programme text NOT NULL REFERENCES ref.programme(code),
    from_level integer,
    to_level integer,
    effective_session text NOT NULL CHECK (effective_session ~ '^[0-9]{4}/[0-9]{4}$'),
    effective_semester integer CHECK (effective_semester IN (1, 2)),
    approved_on date,
    reference text,
    source text NOT NULL DEFAULT 'OLD_PORTAL' CHECK (source = 'OLD_PORTAL'),
    swap_id uuid REFERENCES people.programme_swap(id) ON DELETE SET NULL,
    batch_id uuid REFERENCES people.transfer_batch(id) ON DELETE SET NULL,
    note text NOT NULL CHECK (length(btrim(note)) >= 10),
    recorded_by uuid NOT NULL,
    recorded_office text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CHECK (from_programme <> to_programme));
CREATE UNIQUE INDEX ux_prior_transfer ON people.prior_transfer (student_id, from_programme, to_programme, effective_session);
CREATE INDEX ix_prior_transfer_to ON people.prior_transfer (to_programme);
SELECT audit.attach('people.prior_transfer');
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('people.prior_transfer', 'from_programme', 'KEEP', 'history: the programme a transfer approved on the old portal moved the student from'),
    ('people.prior_transfer', 'to_programme', 'KEEP', 'history: the programme a transfer approved on the old portal moved the student to');
COMMENT ON TABLE people.prior_transfer IS
  'V669: an inter-departmental transfer approved on the old portal, recorded when the Academic Office restored it here (people.restore_approved_transfer). History, never an application: no transfer desk, fee or approval reads it. The student''s matriculation number is never changed by it.';

-- ── what an upload names against a placement this portal recorded ──
CREATE TABLE people.placement_conflict (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    source text NOT NULL CHECK (source IN ('STUDENT_UPLOAD', 'BIOGRAPHY_UPLOAD')),
    file_programme text NOT NULL REFERENCES ref.programme(code),
    file_level integer,
    kept_programme text NOT NULL REFERENCES ref.programme(code),
    kept_level integer,
    settled_by text NOT NULL,
    status text NOT NULL DEFAULT 'REQUIRES_REVIEW' CHECK (status IN ('REQUIRES_REVIEW', 'KEPT', 'APPLIED')),
    seen integer NOT NULL DEFAULT 1,
    first_seen timestamptz NOT NULL DEFAULT now(),
    last_seen timestamptz NOT NULL DEFAULT now(),
    swap_id uuid REFERENCES people.programme_swap(id) ON DELETE SET NULL,
    decided_by uuid,
    decided_office text,
    decided_at timestamptz,
    note text,
    CHECK (status = 'REQUIRES_REVIEW' OR (decided_by IS NOT NULL AND length(btrim(coalesce(note, ''))) >= 10)));
CREATE INDEX ix_placement_conflict_status ON people.placement_conflict (status, last_seen DESC);
CREATE INDEX ix_placement_conflict_student ON people.placement_conflict (student_id);
SELECT audit.attach('people.placement_conflict');
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('people.placement_conflict', 'file_programme', 'KEEP', 'history: the programme an old-portal upload named'),
    ('people.placement_conflict', 'kept_programme', 'KEEP', 'history: the programme the record kept against the upload');
COMMENT ON TABLE people.placement_conflict IS
  'V669: an old-portal upload naming a programme or level other than one this portal recorded (a transfer, a programme swap, an approved transfer restored). The record keeps its placement; the Academic Office keeps it or applies the file''s by a programme swap (people.decide_placement_conflict).';

-- ── the programme swap's new kind, and the bulk transfer's ──
ALTER TABLE people.programme_swap DROP CONSTRAINT programme_swap_kind_check;
ALTER TABLE people.programme_swap ADD CONSTRAINT programme_swap_kind_check
    CHECK (kind IN ('LEGACY_MIGRATION_CORRECTION', 'PROGRAMME_CORRECTION', 'ACADEMIC_TRANSFER', 'APPROVED_TRANSFER_RESTORED'));
ALTER TABLE people.transfer_batch ADD COLUMN kind text NOT NULL DEFAULT 'ACADEMIC_TRANSFER'
    CHECK (kind IN ('ACADEMIC_TRANSFER', 'APPROVED_TRANSFER_RESTORED'));
ALTER TABLE people.transfer_batch DROP CONSTRAINT transfer_batch_ref_check;
ALTER TABLE people.transfer_batch ADD CONSTRAINT transfer_batch_ref_check CHECK (ref ~ '^(IDT|TRR)/[0-9]{4}/[0-9]{6}$');

-- ── whether this portal recorded the student's placement: the move that set the programme the record holds ──
CREATE OR REPLACE FUNCTION people.placement_settled(p_student uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH s AS (SELECT st.programme_code FROM people.student st WHERE st.id = p_student)
    SELECT m.ref FROM (
        SELECT x.swap_ref AS ref, x.executed_at AS at FROM people.programme_swap x, s
         WHERE x.student_id = p_student AND x.status = 'COMPLETED' AND x.to_programme = s.programme_code
        UNION ALL
        SELECT 'Inter-departmental transfer of ' || t.session, t.effected_at FROM people.transfer_application t, s
         WHERE t.student_id = p_student AND t.state = 'EFFECTED' AND t.to_programme_code = s.programme_code
        UNION ALL
        SELECT 'Transfer approved on the old portal' || coalesce(' (' || pt.reference || ')', ''), pt.recorded_at FROM people.prior_transfer pt, s
         WHERE pt.student_id = p_student AND pt.to_programme = s.programme_code
        UNION ALL
        SELECT 'Record moved', rm.moved_at FROM people.record_move rm, s
         WHERE rm.student_id = p_student AND rm.to_programme = s.programme_code) m
     ORDER BY m.at DESC NULLS LAST LIMIT 1
$$;
COMMENT ON FUNCTION people.placement_settled(uuid) IS
  'V669: the move this portal recorded that set the student''s current programme (a programme swap, an effected transfer, a transfer approved on the old portal, a record move), or NULL. An upload never overwrites such a placement.';

-- an upload's programme or level against a recorded placement: one open conflict a student, source and programme, seen again counted
CREATE OR REPLACE FUNCTION people.note_placement_conflict(p_student uuid, p_source text, p_file_programme text, p_file_level integer,
                                                          p_kept_programme text, p_kept_level integer, p_settled_by text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE people.placement_conflict SET seen = seen + 1, last_seen = now(), kept_programme = p_kept_programme, kept_level = p_kept_level,
           settled_by = p_settled_by
     WHERE student_id = p_student AND source = p_source AND file_programme = p_file_programme
       AND file_level IS NOT DISTINCT FROM p_file_level AND status = 'REQUIRES_REVIEW';
    IF NOT FOUND THEN
        INSERT INTO people.placement_conflict (student_id, source, file_programme, file_level, kept_programme, kept_level, settled_by)
        VALUES (p_student, p_source, p_file_programme, p_file_level, p_kept_programme, p_kept_level, p_settled_by);
    END IF;
END $$;

-- ── restoring a transfer approved on the old portal: what it would do ──
CREATE OR REPLACE FUNCTION people.restore_transfer_check(p_student uuid, p_to_programme text, p_to_level integer, p_session text,
                                                         p_from_programme text, p_transfer_session text, p_approved_on date)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE chk jsonb; v_open record; v_refusals jsonb; v_warnings jsonb; v_same boolean; v_from text; f record; v_tses text; v_done text;
BEGIN
    chk := people.programme_swap_check(p_student, p_to_programme, p_to_level, p_session, NULL);
    IF chk->'student' IS NULL THEN RETURN chk; END IF;
    SELECT ta.id, ta.state, ta.to_programme_code, ta.applied_at INTO v_open FROM people.transfer_application ta
     WHERE ta.student_id = p_student AND ta.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED')
     ORDER BY ta.applied_at DESC LIMIT 1;
    v_same := EXISTS (SELECT 1 FROM jsonb_array_elements_text(chk->'refusals') x WHERE x LIKE 'PSW_SAME:%');
    -- the application left in the queue to this very programme is withdrawn by the restoration; already on the programme, the transfer
    -- is recorded and nothing moves
    SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]') INTO v_refusals FROM jsonb_array_elements_text(chk->'refusals') x
     WHERE NOT (x LIKE 'PSW_TRANSFER_OPEN:%' AND v_open.to_programme_code = p_to_programme) AND x NOT LIKE 'PSW_SAME:%';
    v_warnings := coalesce(chk->'warnings', '[]');
    v_from := coalesce(nullif(btrim(coalesce(p_from_programme, '')), ''), CASE WHEN v_same THEN NULL ELSE chk->'from'->>'programme' END);
    SELECT p.code, p.name INTO f FROM ref.programme p WHERE upper(p.code) = upper(v_from) OR upper(p.name) = upper(v_from)
     ORDER BY (upper(p.code) = upper(v_from)) DESC, p.archived, p.code LIMIT 1;
    IF v_from IS NULL THEN
        v_refusals := v_refusals || to_jsonb('PTR_FROM: the student is on that programme already; name the programme they transferred from'::text);
    ELSIF f.code IS NULL THEN
        v_refusals := v_refusals || to_jsonb(('PTR_FROM: ' || v_from || ' is not a programme on the register')::text);
    ELSIF f.code = p_to_programme THEN
        v_refusals := v_refusals || to_jsonb('PTR_FROM_SAME: the programme transferred from and the programme transferred to are the same'::text);
    END IF;
    v_tses := coalesce(nullif(btrim(coalesce(p_transfer_session, '')), ''), chk->>'session');
    IF v_tses !~ '^[0-9]{4}/[0-9]{4}$' OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_tses) THEN
        v_refusals := v_refusals || to_jsonb(('PTR_TRANSFER_SESSION: ' || coalesce(v_tses, 'none') || ' is not a session of the University')::text);
    END IF;
    IF p_approved_on IS NOT NULL AND p_approved_on > (now() AT TIME ZONE 'Africa/Lagos')::date THEN
        v_refusals := v_refusals || to_jsonb('PTR_APPROVED_ON: the transfer cannot have been approved in the future'::text);
    END IF;
    SELECT coalesce(pt.reference, to_char(pt.recorded_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY')) INTO v_done FROM people.prior_transfer pt
     WHERE pt.student_id = p_student AND pt.from_programme = f.code AND pt.to_programme = p_to_programme AND pt.effective_session = v_tses;
    IF v_done IS NOT NULL AND v_same THEN
        v_refusals := v_refusals || to_jsonb(('PTR_RECORDED: this transfer is on the record already (' || v_done || '), and the student is on that programme')::text);
    END IF;
    IF v_open.id IS NOT NULL AND v_open.to_programme_code = p_to_programme THEN
        v_warnings := v_warnings || jsonb_build_object('code', 'APPLICATION_WITHDRAWN',
            'text', 'The transfer application in the queue (' || lower(replace(v_open.state, '_', ' ')) || ') is withdrawn: the transfer approved on the old portal is restored instead, and no new application is made');
    END IF;
    IF v_same THEN
        v_warnings := v_warnings || jsonb_build_object('code', 'RECORD_ONLY',
            'text', 'The student is on ' || coalesce(chk->'to'->>'programmeName', p_to_programme) || ' at ' || p_to_level || ' Level already: the approved transfer is recorded in the history, and nothing is moved');
    END IF;
    RETURN chk || jsonb_build_object(
        'ok', jsonb_array_length(v_refusals) = 0, 'refusals', v_refusals, 'warnings', v_warnings,
        'restore', jsonb_build_object('fromProgramme', f.code, 'fromProgrammeName', f.name, 'transferSession', v_tses, 'approvedOn', p_approved_on,
                                      'recordOnly', v_same, 'recordedAlready', v_done,
                                      'openApplication', CASE WHEN v_open.id IS NULL THEN NULL ELSE jsonb_build_object('id', v_open.id, 'state', v_open.state,
                                          'toProgramme', v_open.to_programme_code, 'appliedAt', v_open.applied_at, 'withdrawn', v_open.to_programme_code = p_to_programme) END),
        -- what a restoration never makes
        'creates', jsonb_build_object('transferApplications', 0, 'transferPayments', 0, 'transferApprovals', 0, 'matriculationNumbers', 0));
END $$;
COMMENT ON FUNCTION people.restore_transfer_check(uuid, text, integer, text, text, text, date) IS
  'V669: what restoring a transfer approved on the old portal would do — the programme swap''s check, an application in the queue to the same programme withdrawn rather than refused, the student already on the programme recorded rather than refused, and the old portal''s transfer checked (the programme left, the session, the date, not recorded twice).';

-- ── restoring it: the swap (made at once), the old portal's transfer recorded, the application in the queue withdrawn ──
CREATE OR REPLACE FUNCTION people.restore_approved_transfer(p_student uuid, p_to_programme text, p_to_level integer, p_session text, p_reason text,
                                                            p_from_programme text, p_transfer_session text, p_transfer_semester integer,
                                                            p_approved_on date, p_reference text, p_batch uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        chk jsonb; v_swap uuid; v_ref text; v_withdrawn uuid; v_prior uuid; v_ptref text := nullif(btrim(coalesce(p_reference, '')), ''); v_open uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PTR_ACTOR: an approved transfer is restored by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'PTR_OFFICE: an approved transfer is restored by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PTR_REASON: say why the placement is restored (the old portal''s approval, the memo), in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_transfer_semester IS NOT NULL AND p_transfer_semester NOT IN (1, 2) THEN
        RAISE EXCEPTION 'PTR_TRANSFER_SEMESTER: the transfer took effect in the first or the second semester' USING ERRCODE = '23514';
    END IF;
    chk := people.restore_transfer_check(p_student, p_to_programme, p_to_level, p_session, p_from_programme, p_transfer_session, p_approved_on);
    IF chk->'student' IS NULL OR NOT (chk->>'ok')::boolean THEN
        RAISE EXCEPTION '%', coalesce(chk->'refusals'->>0, 'PTR_STUDENT: no such student') USING ERRCODE = '23514';
    END IF;
    -- the application left in the queue to the same programme: withdrawn, the reason said
    v_open := CASE WHEN (chk->'restore'->'openApplication'->>'withdrawn')::boolean THEN (chk->'restore'->'openApplication'->>'id')::uuid END;
    IF v_open IS NOT NULL THEN
        UPDATE people.transfer_application SET state = 'WITHDRAWN',
               withdrawn_why = 'Withdrawn by the ' || initcap(office) || ' office: the transfer was approved on the old portal'
                               || coalesce(' (' || v_ptref || ')', '') || ' and is restored without a new application'
         WHERE id = v_open RETURNING id INTO v_withdrawn;
    END IF;
    IF NOT (chk->'restore'->>'recordOnly')::boolean THEN
        PERFORM set_config('moaum.transfer_restore', 'on', true);   -- the kind is made here alone (people.prepare_programme_swap)
        v_swap := people.prepare_programme_swap(p_student, p_to_programme, p_to_level, p_session, 'APPROVED_TRANSFER_RESTORED',
                     btrim(p_reason) || coalesce(' (old portal transfer ' || v_ptref || ')', ''), p_batch);
        PERFORM set_config('moaum.transfer_restore', '', true);
        SELECT x.swap_ref INTO v_ref FROM people.programme_swap x WHERE x.id = v_swap AND x.status = 'COMPLETED';
        IF v_ref IS NULL THEN RAISE EXCEPTION 'PTR_SWAP: the placement could not be restored; nothing is changed' USING ERRCODE = '23514'; END IF;
    END IF;
    INSERT INTO people.prior_transfer (student_id, from_programme, to_programme, from_level, to_level, effective_session, effective_semester, approved_on,
                                       reference, swap_id, batch_id, note, recorded_by, recorded_office)
    VALUES (p_student, chk->'restore'->>'fromProgramme', p_to_programme, (chk->'from'->>'level')::int, p_to_level, chk->'restore'->>'transferSession',
            p_transfer_semester, p_approved_on, v_ptref, v_swap, p_batch, btrim(p_reason), who, office)
    ON CONFLICT (student_id, from_programme, to_programme, effective_session) DO UPDATE SET swap_id = coalesce(EXCLUDED.swap_id, people.prior_transfer.swap_id),
        approved_on = coalesce(EXCLUDED.approved_on, people.prior_transfer.approved_on), reference = coalesce(EXCLUDED.reference, people.prior_transfer.reference)
    RETURNING id INTO v_prior;
    RETURN jsonb_build_object('priorTransferId', v_prior, 'swapId', v_swap, 'swapRef', v_ref, 'recordOnly', (chk->'restore'->>'recordOnly')::boolean,
                              'withdrawnApplication', v_withdrawn, 'transferApplicationsCreated', 0, 'transferPaymentsCreated', 0,
                              'matricNo', chk->'student'->>'matricNo');
END $$;
COMMENT ON FUNCTION people.restore_approved_transfer(uuid, text, integer, text, text, text, text, integer, date, text, uuid) IS
  'V669: a transfer approved on the old portal restored — the student put on the approved programme and level by a programme swap of kind APPROVED_TRANSFER_RESTORED (made at once), the transfer recorded in people.prior_transfer, an application left in the queue to the same programme withdrawn with the reason. No transfer application, fee or approval is made; the matriculation number is never changed.';

-- a date as the University's sheets write it: 2025-03-14, 14/03/2025, 14-03-2025, 14 Mar 2025
CREATE OR REPLACE FUNCTION people.restore_date(p text)
RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text := btrim(coalesce(p, ''));
BEGIN
    IF v = '' THEN RETURN NULL; END IF;
    IF v ~ '^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}' THEN RETURN to_date(left(v, 10), 'YYYY-MM-DD'); END IF;
    IF v ~ '^[0-9]{1,2}[/.-][0-9]{1,2}[/.-][0-9]{4}$' THEN RETURN to_date(regexp_replace(v, '[/.-]', '/', 'g'), 'DD/MM/YYYY'); END IF;
    IF v ~* '^[0-9]{1,2}[ -][a-z]{3,9}[ -,]+[0-9]{4}$' THEN RETURN to_date(regexp_replace(v, '[ ,-]+', ' ', 'g'), 'DD Mon YYYY'); END IF;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END $$;

-- ── the bulk restoration: each row of the file checked as the bulk transfer checks it, then as a restoration ──
CREATE OR REPLACE FUNCTION people.restore_upload_check(p_rows jsonb, p_session text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v_in jsonb; v_out jsonb := '[]'; o jsonb; src jsonb; v_probs jsonb; v_warn jsonb; v_open record; v_same boolean; v_tses text; v_appr text;
        v_from text; v_done boolean;
BEGIN
    v_in := people.transfer_upload_check(p_rows, p_session);
    FOR o IN SELECT x.value FROM jsonb_array_elements(v_in) x ORDER BY (x.value->>'row')::int LOOP
        src := p_rows -> ((o->>'row')::int - 1);
        v_probs := coalesce(o->'problems', '[]'); v_warn := coalesce(o->'warnings', '[]');
        v_from := NULL; v_tses := NULL; v_appr := NULL; v_same := false; v_done := false;   -- each row its own
        IF o->>'studentId' IS NOT NULL THEN
            SELECT ta.state, ta.to_programme_code INTO v_open FROM people.transfer_application ta
             WHERE ta.student_id = (o->>'studentId')::uuid AND ta.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED')
             ORDER BY ta.applied_at DESC LIMIT 1;
            v_same := EXISTS (SELECT 1 FROM jsonb_array_elements(v_probs) p WHERE p->>'code' = 'PSW_SAME');
            SELECT coalesce(jsonb_agg(p), '[]') INTO v_probs FROM jsonb_array_elements(v_probs) p
             WHERE NOT (p->>'code' = 'PSW_TRANSFER_OPEN' AND v_open.to_programme_code = o->'new'->>'programme') AND p->>'code' <> 'PSW_SAME';
            IF v_open.to_programme_code IS NOT NULL AND v_open.to_programme_code = o->'new'->>'programme' THEN
                v_warn := v_warn || jsonb_build_object('code', 'APPLICATION_WITHDRAWN', 'text', 'The transfer application in the queue (' || lower(replace(v_open.state, '_', ' '))
                                                       || ') is withdrawn: the approved transfer is restored instead');
            END IF;
            v_from := coalesce(people.transfer_cell(src, 'old_programme', 'Old Programme Code', 'Old Programme', 'From Programme Code', 'From Programme'),
                               CASE WHEN v_same THEN NULL ELSE o->'current'->>'programme' END);
            IF v_same THEN
                v_warn := v_warn || jsonb_build_object('code', 'RECORD_ONLY', 'text', 'On that programme and level already: the approved transfer is recorded, nothing moved');
                IF v_from IS NULL THEN
                    v_probs := v_probs || jsonb_build_object('code', 'PTR_FROM', 'text', 'The student is on that programme already; the row names the programme they transferred from');
                END IF;
            END IF;
            v_tses := coalesce(people.transfer_cell(src, 'transfer_session', 'Transfer Session', 'Transfer Effective Session', 'effective_session', 'Effective Session'), o->>'session');
            IF v_tses !~ '^[0-9]{4}/[0-9]{4}$' OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = v_tses) THEN
                v_probs := v_probs || jsonb_build_object('code', 'PTR_TRANSFER_SESSION', 'text', coalesce(v_tses, 'No session') || ' is not a session of the University');
            END IF;
            v_appr := people.transfer_cell(src, 'approved_on', 'Approved On', 'Approval Date', 'Date Approved');
            IF v_appr IS NOT NULL AND people.restore_date(v_appr) IS NULL THEN
                v_probs := v_probs || jsonb_build_object('code', 'PTR_APPROVED_ON', 'text', 'The approval date ' || v_appr || ' is not a date (day/month/year)');
            ELSIF people.restore_date(v_appr) > (now() AT TIME ZONE 'Africa/Lagos')::date THEN
                v_probs := v_probs || jsonb_build_object('code', 'PTR_APPROVED_ON', 'text', 'The approval date ' || v_appr || ' is in the future');
            END IF;
            v_done := v_same AND EXISTS (SELECT 1 FROM people.prior_transfer pt JOIN ref.programme fp ON (upper(fp.code) = upper(v_from) OR upper(fp.name) = upper(v_from))
                                          WHERE pt.student_id = (o->>'studentId')::uuid AND pt.from_programme = fp.code
                                            AND pt.to_programme = o->'new'->>'programme' AND pt.effective_session = v_tses);
            IF v_done THEN
                v_probs := v_probs || jsonb_build_object('code', 'PTR_RECORDED', 'text', 'This transfer is on the record already and the student is on that programme');
            END IF;
        END IF;
        v_out := v_out || jsonb_build_array(o || jsonb_build_object(
            'problems', v_probs, 'warnings', v_warn,
            'status', CASE WHEN jsonb_array_length(v_probs) > 0 THEN 'INVALID' WHEN jsonb_array_length(v_warn) > 0 THEN 'WARNING' ELSE 'VALID' END,
            'restore', jsonb_build_object('fromProgramme', v_from, 'transferSession', v_tses, 'approvedOn', people.restore_date(v_appr),
                                          'reference', people.transfer_cell(src, 'transfer_ref', 'Old Portal Transfer Reference', 'Transfer Reference', 'approval_ref', 'Approval Reference', 'Reference'),
                                          'transferSemester', CASE upper(coalesce(people.transfer_cell(src, 'effective_semester', 'Effective Semester', 'Semester'), ''))
                                                                  WHEN '1' THEN 1 WHEN 'FIRST' THEN 1 WHEN '2' THEN 2 WHEN 'SECOND' THEN 2 END,
                                          'recordOnly', coalesce(v_same, false))));
    END LOOP;
    RETURN v_out;
END $$;
COMMENT ON FUNCTION people.restore_upload_check(jsonb, text) IS
  'V669: a bulk restoration file checked — every check of the bulk transfer (people.transfer_upload_check), an application in the queue to the same programme withdrawn rather than refused, a student already on the programme recorded rather than refused, and the old portal''s cells read: the programme left (Old Programme Code), the transfer session, the date approved, the reference.';

-- ── the placement conflicts the uploads found, and the Academic Office's word on each ──
CREATE OR REPLACE FUNCTION people.placement_conflicts(p_status text)
RETURNS TABLE (id uuid, student_id uuid, name text, matric_no text, jamb_reg_no text, source text, file_programme text, file_programme_name text,
               file_level integer, kept_programme text, kept_programme_name text, kept_level integer, current_programme text, current_level integer,
               settled_by text, status text, seen integer, first_seen timestamptz, last_seen timestamptz, note text, decided_at timestamptz, swap_ref text)
LANGUAGE sql STABLE AS $$
    SELECT c.id, c.student_id, upper(s.surname) || ', ' || s.other_names, s.matric_no, s.jamb_reg_no, c.source, c.file_programme, fp.name, c.file_level,
           c.kept_programme, kp.name, c.kept_level, s.programme_code, s.current_level, c.settled_by, c.status, c.seen, c.first_seen, c.last_seen, c.note,
           c.decided_at, x.swap_ref
      FROM people.placement_conflict c
      JOIN people.student s ON s.id = c.student_id
      LEFT JOIN ref.programme fp ON fp.code = c.file_programme
      LEFT JOIN ref.programme kp ON kp.code = c.kept_programme
      LEFT JOIN people.programme_swap x ON x.id = c.swap_id
     WHERE p_status IS NULL OR c.status = p_status
     ORDER BY (c.status = 'REQUIRES_REVIEW') DESC, c.last_seen DESC
$$;

CREATE OR REPLACE FUNCTION people.decide_placement_conflict(p_id uuid, p_decision text, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        c people.placement_conflict; v_swap uuid;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PLC_ACTOR: a placement conflict is decided by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'PLC_OFFICE: a placement conflict is decided by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF p_decision NOT IN ('KEEP', 'APPLY') THEN RAISE EXCEPTION 'PLC_DECISION: keep the recorded placement or apply the file''s' USING ERRCODE = '23514'; END IF;
    IF length(btrim(coalesce(p_note, ''))) < 10 THEN RAISE EXCEPTION 'PLC_NOTE: say why, in ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM people.placement_conflict WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PLC_CONFLICT: no such placement conflict' USING ERRCODE = '23514'; END IF;
    IF c.status <> 'REQUIRES_REVIEW' THEN RAISE EXCEPTION 'PLC_DECIDED: this conflict is decided already' USING ERRCODE = '23514'; END IF;
    IF p_decision = 'APPLY' THEN
        -- the file's placement, by the programme swap: checked and made at once, the history kept
        v_swap := people.prepare_programme_swap(c.student_id, c.file_programme,
                      coalesce(c.file_level, (SELECT s.current_level FROM people.student s WHERE s.id = c.student_id)), NULL,
                      'LEGACY_MIGRATION_CORRECTION', btrim(p_note) || ' (the old-portal upload''s placement applied)', NULL);
    END IF;
    UPDATE people.placement_conflict SET status = CASE p_decision WHEN 'KEEP' THEN 'KEPT' ELSE 'APPLIED' END, note = btrim(p_note), swap_id = v_swap,
           decided_by = who, decided_office = office, decided_at = now()
     WHERE id = p_id;
    RETURN jsonb_build_object('id', p_id, 'status', CASE p_decision WHEN 'KEEP' THEN 'KEPT' ELSE 'APPLIED' END, 'swapId', v_swap);
END $$;

-- ── V578/V633's prepare, restated: the kind APPROVED_TRANSFER_RESTORED (people.restore_approved_transfer) ──
CREATE OR REPLACE FUNCTION people.prepare_programme_swap(p_student uuid, p_to_programme text, p_to_level integer, p_session text, p_kind text, p_reason text, p_batch uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        chk jsonb; v_id uuid; v_ref text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'PSW_ACTOR: a programme swap is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'PSW_OFFICE: a programme swap is prepared by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
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

-- ── V587's bulk transfer, restated with its kind: APPROVED_TRANSFER_RESTORED restores each valid row (TRR/YYYY/NNNNNN) ──
DROP FUNCTION people.prepare_transfer_batch(jsonb, text, text, text, text, boolean);
CREATE OR REPLACE FUNCTION people.prepare_transfer_batch(p_rows jsonb, p_session text, p_reason text, p_approval_ref text, p_filename text, p_partial boolean, p_kind text DEFAULT 'ACADEMIC_TRANSFER'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_checked jsonb; v_bad int; v_id uuid := gen_random_uuid(); v_ref text; x jsonb; v_swap uuid; v_prepared int := 0; v_skipped int := 0; v_msg text;
        v_year text := to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY'); v_rows jsonb;
        v_res jsonb; v_restore boolean := coalesce(p_kind, 'ACADEMIC_TRANSFER') = 'APPROVED_TRANSFER_RESTORED';
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'TRANSFER_BATCH_ACTOR: a bulk transfer is prepared by a person' USING ERRCODE = '23514'; END IF;
    IF NOT people.programme_swap_office_prepares(coalesce(office, '')) THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_OFFICE: a bulk transfer is prepared by the Academic Office, the Registry or the Director of ICT' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_REASON: say why these students are transferred (the Senate''s approval, the memo), ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_kind, 'ACADEMIC_TRANSFER') NOT IN ('ACADEMIC_TRANSFER', 'APPROVED_TRANSFER_RESTORED') THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_KIND: a bulk transfer, or the restoration of transfers approved on the old portal' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_EMPTY: the file has no rows' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_rows) > 1000 THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_TOO_MANY: up to 1,000 rows at a time (% given); split the file', jsonb_array_length(p_rows) USING ERRCODE = '23514';
    END IF;
    -- checked again now, the final word before anything is written
    -- V669: a restoration's rows are checked as restorations (people.restore_upload_check)
    v_checked := CASE WHEN v_restore THEN people.restore_upload_check(p_rows, p_session) ELSE people.transfer_upload_check(p_rows, p_session) END;
    v_bad := (SELECT count(*) FROM jsonb_array_elements(v_checked) c WHERE c->>'status' = 'INVALID');
    IF v_bad > 0 AND NOT coalesce(p_partial, false) THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_INVALID: % of the % rows are invalid; correct them and upload the file again, or prepare the valid rows alone', v_bad, jsonb_array_length(p_rows)
            USING ERRCODE = '23514';
    END IF;
    IF v_bad = jsonb_array_length(p_rows) THEN
        RAISE EXCEPTION 'TRANSFER_BATCH_NONE_VALID: none of the % rows is valid', v_bad USING ERRCODE = '23514';
    END IF;
    v_ref := CASE WHEN v_restore THEN 'TRR/' || v_year || '/' || lpad(platform.next_number('TRANSFER_RESTORATION', 'UNIVERSITY', v_year)::text, 6, '0')
                  ELSE 'IDT/' || v_year || '/' || lpad(platform.next_number('INTER_DEPARTMENTAL_TRANSFER', 'UNIVERSITY', v_year)::text, 6, '0') END;
    INSERT INTO people.transfer_batch (id, ref, effective_session, filename, reason, approval_ref, partial, total, prepared_by, prepared_office, kind)
    VALUES (v_id, v_ref, coalesce(nullif(btrim(p_session), ''), policy.university_current_session()), nullif(btrim(coalesce(p_filename, '')), ''), btrim(p_reason),
            nullif(btrim(coalesce(p_approval_ref, '')), ''), v_bad > 0, jsonb_array_length(p_rows), who, office, coalesce(p_kind, 'ACADEMIC_TRANSFER'));
    v_rows := p_rows;
    FOR x IN SELECT c.value FROM jsonb_array_elements(v_checked) c ORDER BY (c.value->>'row')::int LOOP
        IF x->>'status' = 'INVALID' THEN
            INSERT INTO people.transfer_batch_row (batch_id, row_no, student_id, uploaded, status, messages)
            VALUES (v_id, (x->>'row')::int, (x->>'studentId')::uuid, v_rows -> ((x->>'row')::int - 1), 'INVALID', x->'problems');
            CONTINUE;
        END IF;
        BEGIN
            IF v_restore THEN
                -- V669: the transfer approved on the old portal restored — no application, no fee, no approval
                v_res := people.restore_approved_transfer((x->>'studentId')::uuid, x->'new'->>'programme', (x->'new'->>'level')::int, x->>'session',
                    btrim(p_reason) || ' (' || v_ref || CASE WHEN x->>'reason' IS NOT NULL THEN ': ' || (x->>'reason') ELSE '' END || ')',
                    x->'restore'->>'fromProgramme', x->'restore'->>'transferSession', (x->'restore'->>'transferSemester')::int, (x->'restore'->>'approvedOn')::date, x->'restore'->>'reference', v_id);
                v_swap := (v_res->>'swapId')::uuid;
            ELSE
                v_swap := people.prepare_programme_swap((x->>'studentId')::uuid, x->'new'->>'programme', (x->'new'->>'level')::int, x->>'session', 'ACADEMIC_TRANSFER',
                    btrim(p_reason) || ' (' || v_ref || CASE WHEN x->>'reason' IS NOT NULL THEN ': ' || (x->>'reason') ELSE '' END || ')', v_id);
            END IF;
            INSERT INTO people.transfer_batch_row (batch_id, row_no, student_id, uploaded, status, messages, swap_id)
            VALUES (v_id, (x->>'row')::int, (x->>'studentId')::uuid, v_rows -> ((x->>'row')::int - 1), 'PREPARED', x->'warnings', v_swap);
            v_prepared := v_prepared + 1;
        EXCEPTION WHEN check_violation OR insufficient_privilege OR unique_violation THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            INSERT INTO people.transfer_batch_row (batch_id, row_no, student_id, uploaded, status, messages)
            VALUES (v_id, (x->>'row')::int, (x->>'studentId')::uuid, v_rows -> ((x->>'row')::int - 1), 'SKIPPED',
                    jsonb_build_array(jsonb_build_object('code', split_part(v_msg, ':', 1), 'text', btrim(substr(v_msg, position(':' IN v_msg) + 1)))));
            v_skipped := v_skipped + 1;
        END;
    END LOOP;
    UPDATE people.transfer_batch SET prepared = v_prepared, skipped = v_skipped + v_bad WHERE id = v_id;
    RETURN jsonb_build_object('id', v_id, 'ref', v_ref, 'total', jsonb_array_length(p_rows), 'prepared', v_prepared, 'skipped', v_skipped, 'invalid', v_bad,
                              'kind', coalesce(p_kind, 'ACADEMIC_TRANSFER'), 'transferApplicationsCreated', 0);
END $function$;

-- ── V578's programme history, restated: the transfer approved on the old portal ──
CREATE OR REPLACE FUNCTION people.programme_history(p_student uuid)
 RETURNS TABLE(at timestamp with time zone, session text, source text, kind text, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, level integer, from_programme text, from_level integer, reference text, detail text, by_whom text, current boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH st AS (SELECT s.* FROM people.student s WHERE s.id = p_student),
    moves AS (
        SELECT t.effected_at, t.session, 'TRANSFER', 'TRANSFER_EFFECTED', t.to_programme_code, t.from_programme_code, t.from_level,
               NULL, 'Inter-departmental transfer effected', helpdesk.person_name(t.effected_by)
          FROM people.transfer_application t WHERE t.student_id = p_student AND t.state = 'EFFECTED' AND t.effected_at IS NOT NULL
        UNION ALL
        SELECT m.moved_at, NULL, 'RECORD_MOVE', 'RECORD_MOVED', m.to_programme, m.from_programme, m.from_level, NULL,
               'Record moved to a postgraduate programme: ' || m.reason, helpdesk.person_name(m.moved_by)
          FROM people.record_move m WHERE m.student_id = p_student
        UNION ALL
        SELECT x.executed_at, x.effective_session, 'SWAP', 'PROGRAMME_SWAP_' || x.kind, x.to_programme, x.from_programme, x.from_level, x.swap_ref,
               x.reason, helpdesk.person_name(x.decided_by)
          FROM people.programme_swap x WHERE x.student_id = p_student AND x.status = 'COMPLETED'
        UNION ALL
        -- V669: a transfer approved on the old portal, dated when it was approved (else when its session began); its restoration here is
        -- the programme swap after it
        SELECT coalesce(pt.approved_on::timestamptz, (SELECT a.starts_on::timestamptz FROM policy.academic_session a WHERE a.name = pt.effective_session), pt.recorded_at),
               pt.effective_session, 'OLD_PORTAL', 'TRANSFER_APPROVED_OLD_PORTAL', pt.to_programme, pt.from_programme, pt.from_level, pt.reference,
               'Inter-departmental transfer approved on the old portal' || CASE WHEN pt.approved_on IS NOT NULL THEN ' on ' || to_char(pt.approved_on, 'DD Mon YYYY') ELSE '' END
               || CASE WHEN pt.effective_semester IS NOT NULL THEN ', effective ' || CASE pt.effective_semester WHEN 1 THEN 'first' ELSE 'second' END || ' semester' ELSE '' END,
               coalesce(people.officer_name(pt.recorded_by), 'The ' || initcap(pt.recorded_office) || ' office')
          FROM people.prior_transfer pt WHERE pt.student_id = p_student
        UNION ALL
        -- any other change of programme the audit chain holds (an upload, a merge, a correction by hand)
        SELECT e.occurred_at, NULL, 'RECORD', 'PROGRAMME_CHANGED', e.after_state->>'programme_code', e.before_state->>'programme_code',
               nullif(e.before_state->>'current_level', '')::int, NULL, coalesce(e.reason, 'Programme changed on the record'),
               CASE WHEN e.actor_office = 'student' THEN 'The student' WHEN e.actor_id IS NULL THEN 'The system' ELSE helpdesk.person_name(e.actor_id) END
          FROM audit.entries e
         WHERE e.subject_type = 'people.student' AND e.subject_id = p_student AND e.action = 'UPDATE'
           AND e.before_state->>'programme_code' IS DISTINCT FROM e.after_state->>'programme_code'
           AND NOT EXISTS (SELECT 1 FROM people.programme_swap x WHERE x.student_id = p_student AND x.status = 'COMPLETED' AND x.executed_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')
           AND NOT EXISTS (SELECT 1 FROM people.transfer_application t WHERE t.student_id = p_student AND t.effected_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')
           AND NOT EXISTS (SELECT 1 FROM people.record_move m WHERE m.student_id = p_student AND m.moved_at BETWEEN e.occurred_at - interval '5 seconds' AND e.occurred_at + interval '5 seconds')),
    rows AS (
        -- the admission: the candidate's programme where the record is linked to one; else the programme the record held before its
        -- first recorded move; else the programme it holds (a record never moved)
        SELECT coalesce(a.starts_on::timestamptz, st.matriculated_at, '1900-01-01'::timestamptz) AS at, st.entry_session, 'ADMISSION', 'ORIGINAL_ADMISSION',
               coalesce(c.programme, (SELECT m.from_programme FROM moves m(at, s, src, k, prog, from_programme, fl, rf, d, b) WHERE m.from_programme IS NOT NULL ORDER BY m.at NULLS LAST LIMIT 1),
                        st.programme_code),
               NULL::text, NULL::integer, NULL::text, 'Original admission programme', NULL::text
          FROM st LEFT JOIN admissions.candidate c ON c.id = st.candidate_id LEFT JOIN policy.academic_session a ON a.name = st.entry_session
        UNION ALL
        SELECT * FROM moves)
    SELECT r.at, r.entry_session, r.source, r.kind, r.programme_code, p.name, p.dept_code, d.name, p.faculty_code, f.name, r.from_level, r.from_programme, r.from_level,
           r.reference, r.detail, r.by_whom,
           -- the current placement: the latest move, or the admission where the record was never moved
           CASE WHEN r.kind = 'ORIGINAL_ADMISSION' THEN NOT EXISTS (SELECT 1 FROM moves)
                ELSE r.at = (SELECT max(m.at) FROM moves m(at)) AND r.programme_code = (SELECT programme_code FROM st) END
      FROM rows r(at, entry_session, source, kind, programme_code, from_programme, from_level, reference, detail, by_whom)
      LEFT JOIN ref.programme p ON p.code = r.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     ORDER BY (r.kind = 'ORIGINAL_ADMISSION') DESC, r.at NULLS FIRST
$function$;

-- ── V578's mismatch list, restated: the number alone never suggests a department; a recorded move is not judged by it ──
CREATE OR REPLACE FUNCTION people.programme_mismatches(p_fac text, p_dept text, p_prog text)
 RETURNS TABLE(student_id uuid, surname text, other_names text, matric_no text, jamb_reg_no text, status text, entry_mode text, entry_session text, current_level integer, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, matric_segment text, programme_segment text, registration_dept text, registration_dept_name text, registration_share numeric, admitted_programme text, admitted_programme_name text, classification text, suggested_dept text, suggested_programme text, suggested_programme_name text, review_status text, review_note text, reviewed_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    WITH st AS MATERIALIZED (
        SELECT s.id, s.surname, s.other_names, s.matric_no, s.jamb_reg_no, s.status, s.entry_mode, s.entry_session, s.current_level, s.programme_code,
               s.candidate_id, p.name AS programme, p.dept_code, p.faculty_code, p.matric_code, p.category,
               CASE WHEN s.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/' THEN split_part(s.matric_no, '/', 3) END AS seg
          FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED', 'DORMANT')
           AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)),
    -- V669: a placement this portal recorded — an effected transfer, a completed programme swap, a transfer approved on the old portal —
    -- to the programme the student holds: since when (the registrations before it are of the programme left)
    moved AS MATERIALIZED (
        SELECT m.student_id, max(m.since) AS since FROM (
            SELECT t.student_id, t.session AS since FROM people.transfer_application t JOIN st ON st.id = t.student_id AND t.to_programme_code = st.programme_code
             WHERE t.state = 'EFFECTED'
            UNION ALL
            SELECT x.student_id, x.effective_session FROM people.programme_swap x JOIN st ON st.id = x.student_id AND x.to_programme = st.programme_code
             WHERE x.status = 'COMPLETED'
            UNION ALL
            SELECT pt.student_id, pt.effective_session FROM people.prior_transfer pt JOIN st ON st.id = pt.student_id AND pt.to_programme = st.programme_code) m
         GROUP BY m.student_id),
    -- the segment most of a programme's students carry: read over the whole register, so a filtered view judges by the same measure
    observed AS MATERIALIZED (
        SELECT programme_code, seg FROM (
            SELECT s.programme_code, split_part(s.matric_no, '/', 3) AS seg, count(*) AS n,
                   row_number() OVER (PARTITION BY s.programme_code ORDER BY count(*) DESC, split_part(s.matric_no, '/', 3)) AS rn
              FROM people.student s WHERE s.status IN ('ACTIVE', 'PROBATION', 'ADMITTED') AND s.matric_no ~ '^[A-Z]+/[A-Z]+/[A-Z]+/'
             GROUP BY 1, 2) o WHERE rn = 1 AND n >= 3),
    seg_dept AS MATERIALIZED (   -- which department a segment names: the programme carrying it, by its own code or by its students
        SELECT seg, dept_code FROM (
            SELECT coalesce(p.matric_code, o.seg) AS seg, p.dept_code, row_number() OVER (PARTITION BY coalesce(p.matric_code, o.seg) ORDER BY (p.matric_code IS NOT NULL) DESC, p.code) rn
              FROM ref.programme p LEFT JOIN observed o ON o.programme_code = p.code WHERE coalesce(p.matric_code, o.seg) IS NOT NULL AND p.dept_code IS NOT NULL) q WHERE rn = 1),
    latest AS MATERIALIZED (
        SELECT DISTINCT ON (r.student_id) r.student_id, r.id FROM registration.course_registration r JOIN st ON st.id = r.student_id
          LEFT JOIN moved mv ON mv.student_id = r.student_id
         WHERE r.status IN ('APPROVED', 'LOCKED') AND (mv.since IS NULL OR r.session >= mv.since) ORDER BY r.student_id, r.session DESC, r.semester DESC),
    regdept AS MATERIALIZED (
        SELECT student_id, dept_code, share FROM (
            SELECT l.student_id, c.dept_code, count(*)::numeric / sum(count(*)) OVER (PARTITION BY l.student_id) AS share,
                   row_number() OVER (PARTITION BY l.student_id ORDER BY count(*) DESC, c.dept_code) AS rn
              FROM latest l JOIN registration.entry e ON e.registration_id = l.id AND e.status IN ('REGISTERED', 'APPROVED')
              JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
             WHERE c.kind NOT IN ('GST', 'EPS') AND c.dept_code IS NOT NULL
             GROUP BY 1, 2) q WHERE rn = 1),
    judged AS (
        SELECT st.*, coalesce(st.matric_code, o.seg) AS programme_segment, sd.dept_code AS seg_dept, rd.dept_code AS reg_dept, rd.share,
               c.programme AS admitted_programme,
               -- V669: the number names the department a student was admitted to; after a recorded move it is not a sign of anything
               (mv.student_id IS NULL AND st.seg IS NOT NULL AND coalesce(st.matric_code, o.seg) IS NOT NULL AND st.seg <> coalesce(st.matric_code, o.seg) AND sd.dept_code IS NOT NULL AND sd.dept_code <> st.dept_code) AS by_matric,
               (rd.dept_code IS NOT NULL AND rd.dept_code <> st.dept_code AND rd.share >= 0.5) AS by_registration,
               (mv.student_id IS NULL AND c.programme IS NOT NULL AND c.programme <> st.programme_code) AS by_admission
          FROM st
          LEFT JOIN observed o ON o.programme_code = st.programme_code
          LEFT JOIN seg_dept sd ON sd.seg = st.seg
          LEFT JOIN regdept rd ON rd.student_id = st.id
          LEFT JOIN admissions.candidate c ON c.id = st.candidate_id
          LEFT JOIN moved mv ON mv.student_id = st.id),
    classed AS (
        SELECT j.*,
               CASE WHEN j.by_matric AND j.by_registration AND j.seg_dept = j.reg_dept THEN 'CONFIRMED'
                    WHEN j.by_matric AND j.by_registration THEN 'REQUIRES_REVIEW'
                    WHEN j.by_matric OR j.by_registration OR j.by_admission THEN 'POSSIBLE'
                    ELSE 'NO_MISMATCH' END AS classification,
               CASE WHEN j.by_matric AND j.by_registration AND j.seg_dept = j.reg_dept THEN j.seg_dept
                    -- V669: the matriculation number alone never suggests a department (a student transferred keeps the number of the one left)
                    WHEN j.by_registration THEN j.reg_dept END AS suggested_dept
          FROM judged j),
    -- the programme suggested for a department: the one of the student's own category most of its students sit on (read once)
    suggested AS MATERIALIZED (
        SELECT DISTINCT ON (p.dept_code, p.category) p.dept_code, p.category, p.code, p.name
          FROM ref.programme p
          LEFT JOIN (SELECT s2.programme_code, count(*) AS n FROM people.student s2 WHERE s2.status IN ('ACTIVE', 'PROBATION') GROUP BY 1) pop ON pop.programme_code = p.code
         WHERE NOT p.archived AND p.dept_code IS NOT NULL
         ORDER BY p.dept_code, p.category, coalesce(pop.n, 0) DESC, p.code)
    SELECT c.id, c.surname, c.other_names, c.matric_no, c.jamb_reg_no, c.status, c.entry_mode, c.entry_session, c.current_level, c.programme_code, c.programme,
           c.dept_code, d.name, c.faculty_code, f.name, c.seg, c.programme_segment, c.reg_dept, rdn.name, round(c.share, 2), c.admitted_programme, ap.name,
           c.classification, c.suggested_dept, sp.code, sp.name,
           coalesce(rv.status, 'NOT_REVIEWED'), rv.note, rv.reviewed_at
      FROM classed c
      LEFT JOIN ref.department d ON d.code = c.dept_code
      LEFT JOIN ref.faculty f ON f.code = c.faculty_code
      LEFT JOIN ref.department rdn ON rdn.code = c.reg_dept
      LEFT JOIN ref.programme ap ON ap.code = c.admitted_programme
      LEFT JOIN suggested sp ON sp.dept_code = c.suggested_dept AND sp.category = c.category
      LEFT JOIN people.programme_mismatch_review rv ON rv.student_id = c.id
     WHERE c.classification <> 'NO_MISMATCH' OR rv.student_id IS NOT NULL
$function$;

-- ── the old-portal student upload, restated: a recorded placement kept, the file's a placement conflict ──
CREATE OR REPLACE FUNCTION people.import_students_rows(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE v_settled text; v_cur_prog text; v_cur_level integer; v_sid uuid;
        r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_mode text; v_es text; v_el int; v_cl int; v_stated boolean;
        v_surname text; v_others text; v_exists boolean; v_state text; v_school text;
        n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0; ns int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;
        IF v_matric !~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$'
           AND v_matric !~ '^[A-Z]{2,6}(/[A-Z0-9]{2,6}){1,4}/[0-9]{2,7}$' THEN nbn := nbn + 1; CONTINUE; END IF;

        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
        IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1; END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

        BEGIN
            v_surname := nullif(btrim(coalesce(r->>'surname', '')), '');
            v_others := nullif(btrim(coalesce(r->>'otherNames', r->>'other_names', r->>'othernames', '')), '');
            IF v_surname IS NULL THEN
                DECLARE nm text := btrim(coalesce(r->>'name', r->>'fullName', ''));
                BEGIN
                    IF position(',' IN nm) > 0 THEN v_surname := btrim(split_part(nm, ',', 1)); v_others := btrim(substr(nm, position(',' IN nm) + 1));
                    ELSE v_surname := split_part(nm, ' ', 1); v_others := nullif(btrim(substr(nm, length(split_part(nm, ' ', 1)) + 1)), ''); END IF;
                END;
            END IF;
            IF v_surname IS NULL OR v_surname = '' THEN v_surname := 'UNKNOWN'; END IF;
            v_others := coalesce(v_others, '');

            v_sex := upper(left(btrim(coalesce(r->>'sex', r->>'gender', '')), 1));
            IF v_sex NOT IN ('F','M') THEN v_sex := NULL; END IF;
            BEGIN v_dob := (r->>'dob')::date; EXCEPTION WHEN OTHERS THEN BEGIN v_dob := (r->>'dateOfBirth')::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END; END;
            v_state := nullif(btrim(coalesce(r->>'state', r->>'stateOfOrigin', r->>'state_of_origin', '')), '');
            v_school := upper(nullif(btrim(coalesce(r->>'schoolId', r->>'school_id', r->>'schoolid', '')), ''));
            v_mode := upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', 'UTME')));
            -- V381: a student of the Centre for Continuing Education (the route, the study mode or the entry mode says so) comes over as CCE
            IF v_mode IN ('CCE', 'PART TIME', 'PART-TIME', 'PART_TIME') OR v_mode LIKE '%CONTINUING%'
               OR upper(coalesce(r->>'route', r->>'admissionRoute', r->>'admission_route', '')) ~ '(CCE|CONTINUING)'
               OR upper(coalesce(r->>'studyMode', r->>'study_mode', '')) ~ 'PART' THEN
                v_mode := 'CCE';
            END IF;
            IF v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH','CCE') THEN v_mode := 'UTME'; END IF;

            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                IF v_matric ~ '^MOAUM/' THEN
                    v_es := '20' || split_part(v_matric, '/', 3) || '/20' || lpad(((split_part(v_matric, '/', 3))::int + 1)::text, 2, '0');
                ELSE
                    v_es := coalesce(v_es, '2000/2001');
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2000/2001'; END IF;

            -- V455: a postgraduate programme's row is filed POSTGRADUATE at 700/800/900 (people.upload_levels)
            SELECT u.mode, u.entry_level, u.current_level, u.level_stated INTO v_mode, v_el, v_cl, v_stated
              FROM people.upload_levels(v_prog_code, v_mode, coalesce(r->>'entryLevel', r->>'entry_level', ''),
                                        coalesce(r->>'level', r->>'currentLevel', r->>'current_level', '')) u;

            -- V669: a placement this portal recorded (a transfer, a programme swap, an approved transfer restored) is not undone by an
            -- upload: the record keeps its programme and level, and the file's are put to the Academic Office as a placement conflict
            v_sid := NULL; v_settled := NULL; v_cur_prog := NULL; v_cur_level := NULL;
            SELECT s.id, s.programme_code, s.current_level, people.placement_settled(s.id) INTO v_sid, v_cur_prog, v_cur_level, v_settled
              FROM people.student s WHERE upper(s.matric_no) = v_matric;
            SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
            INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, state_of_origin, programme_code, entry_mode,
                                        entry_session, entry_level, current_level, status, matriculated_at, school_id, study_mode)
            VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_state, v_prog_code, v_mode, v_es, v_el, v_cl, 'ACTIVE', now(), v_school,
                    CASE WHEN v_mode = 'CCE' THEN 'PART_TIME' ELSE 'FULL_TIME' END)
            ON CONFLICT (matric_no) DO UPDATE SET surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                sex = coalesce(EXCLUDED.sex, people.student.sex), date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
                state_of_origin = coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                programme_code = CASE WHEN v_settled IS NOT NULL THEN people.student.programme_code ELSE EXCLUDED.programme_code END,
                -- V459: the level changes only when the file states one (people.upload_kept_level: never a postgraduate
                -- below 700); a postgraduate programme's row re-files a student wrongly filed as undergraduate (people.upload_kept_mode)
                current_level = CASE WHEN v_settled IS NOT NULL THEN people.student.current_level
                                     ELSE people.upload_kept_level(people.student.entry_mode, people.student.current_level, EXCLUDED.entry_mode, EXCLUDED.current_level, v_stated) END,
                entry_mode = people.upload_kept_mode(people.student.entry_mode, EXCLUDED.entry_mode),
                entry_level = CASE WHEN EXCLUDED.entry_mode = 'POSTGRADUATE' AND people.student.entry_mode NOT IN ('POSTGRADUATE', 'CCE')
                                        AND coalesce(people.student.entry_level, 0) < 700
                                   THEN EXCLUDED.entry_level ELSE people.student.entry_level END,
                school_id = coalesce(EXCLUDED.school_id, people.student.school_id);
            IF v_settled IS NOT NULL AND (v_cur_prog IS DISTINCT FROM v_prog_code OR (v_stated AND v_cur_level IS DISTINCT FROM v_cl)) THEN
                PERFORM people.note_placement_conflict(v_sid, 'STUDENT_UPLOAD', v_prog_code, CASE WHEN v_stated THEN v_cl END, v_cur_prog, v_cur_level, v_settled);
            END IF;
            IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, nc, nu, nnp, nbn, ns, v_firsterr;
END $function$;

-- ── the old-portal biography upload, restated alike ──
CREATE OR REPLACE FUNCTION people.import_biography_rows(p_rows jsonb)
 RETURNS TABLE(rows integer, created integer, updated integer, no_programme integer, bad_number integer, contacts integer, biography integer, accounts integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE v_settled text; v_cur_prog text; v_cur_level integer; v_sid uuid;
       
    r jsonb;
    v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_matric text; v_prog text; v_prog_code text; v_sex text; v_dob date; v_jamb text;
    v_mode text; v_es text; v_el int; v_cl int; v_stated boolean; v_surname text; v_others text;
    v_state text; v_phone text; v_email text; v_addr text; v_student uuid; v_exists boolean;
    bf text; bv text; l_contact int; l_bio int; l_acct int;
    v_sealed text;   -- one hash per upload, made when the first account is opened (V294)
    n int := 0; nc int := 0; nu int := 0; nnp int := 0; nbn int := 0;
    ncontact int := 0; nbio int := 0; nacct int := 0; nerr int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, name, programme, level, and the biography'
            USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;

        IF v_matric !~ '^MOAUM/[A-Z]{2,4}/[0-9]{2}/[0-9]{4}$'
           AND v_matric !~ '^[A-Z]{2,6}(/[A-Z0-9]{2,6}){1,4}/[0-9]{2,7}$' THEN
            nbn := nbn + 1; CONTINUE;
        END IF;

        v_prog := btrim(coalesce(r->>'programme', r->>'programmeCode', r->>'programme_code', r->>'course', ''));
        SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
        IF v_prog_code IS NULL THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived, code LIMIT 1;
        END IF;
        IF v_prog_code IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;

        l_contact := 0; l_bio := 0; l_acct := 0;
        BEGIN
            v_surname := nullif(btrim(coalesce(r->>'surname', '')), '');
            v_others  := nullif(btrim(coalesce(r->>'otherNames', r->>'other_names', r->>'othernames', '')), '');
            IF v_surname IS NULL THEN
                DECLARE nm text := btrim(coalesce(r->>'name', r->>'fullName', ''));
                BEGIN
                    IF position(',' IN nm) > 0 THEN
                        v_surname := btrim(split_part(nm, ',', 1));
                        v_others  := btrim(substr(nm, position(',' IN nm) + 1));
                    ELSE
                        v_surname := split_part(nm, ' ', 1);
                        v_others  := nullif(btrim(substr(nm, length(split_part(nm, ' ', 1)) + 1)), '');
                    END IF;
                END;
            END IF;
            IF v_surname IS NULL OR v_surname = '' THEN v_surname := 'UNKNOWN'; END IF;
            v_others := coalesce(v_others, '');

            v_sex := upper(left(btrim(coalesce(r->>'sex', r->>'gender', '')), 1));
            IF v_sex NOT IN ('F', 'M') THEN v_sex := NULL; END IF;

            BEGIN v_dob := (r->>'dob')::date;
            EXCEPTION WHEN OTHERS THEN
                BEGIN v_dob := (r->>'dateOfBirth')::date; EXCEPTION WHEN OTHERS THEN v_dob := NULL; END;
            END;

            v_state := nullif(btrim(coalesce(r->>'state', r->>'stateOfOrigin', r->>'state_of_origin', '')), '');
            v_jamb := nullif(upper(btrim(coalesce(r->>'jamb', r->>'jambNo', r->>'jamb_no', r->>'jambRegNo', r->>'jamb_reg_no', ''))), '');

            v_mode := upper(btrim(coalesce(r->>'entryMode', r->>'entry_mode', r->>'mode_entry', 'UTME')));
            v_mode := CASE v_mode
                          WHEN 'DE' THEN 'DIRECT_ENTRY'
                          WHEN 'DIRECT ENTRY' THEN 'DIRECT_ENTRY'
                          WHEN 'PG' THEN 'POSTGRADUATE'
                          ELSE v_mode END;
            IF v_mode NOT IN ('UTME', 'DIRECT_ENTRY', 'TRANSFER', 'POSTGRADUATE', 'JUPEB', 'SANDWICH') THEN v_mode := 'UTME'; END IF;

            v_es := nullif(btrim(coalesce(r->>'entrySession', r->>'entry_session', r->>'yoe', '')), '');
            IF v_es IS NULL OR v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN
                IF v_matric ~ '^MOAUM/' THEN
                    v_es := '20' || split_part(v_matric, '/', 3) || '/20'
                            || lpad(((split_part(v_matric, '/', 3))::int + 1)::text, 2, '0');
                ELSE
                    v_es := coalesce(v_es, '2000/2001');
                END IF;
            END IF;
            IF v_es !~ '^[0-9]{4}/[0-9]{4}$' THEN v_es := '2000/2001'; END IF;

            -- V455: a postgraduate programme's row is filed POSTGRADUATE at 700/800/900 (people.upload_levels)
            SELECT u.mode, u.entry_level, u.current_level, u.level_stated INTO v_mode, v_el, v_cl, v_stated
              FROM people.upload_levels(v_prog_code, v_mode, coalesce(r->>'entryLevel', r->>'entry_level', ''),
                                        coalesce(r->>'level', r->>'currentLevel', r->>'current_level', '')) u;

            -- V669: a placement this portal recorded (a transfer, a programme swap, an approved transfer restored) is not undone by an
            -- upload: the record keeps its programme and level, and the file's are put to the Academic Office as a placement conflict
            v_sid := NULL; v_settled := NULL; v_cur_prog := NULL; v_cur_level := NULL;
            SELECT s.id, s.programme_code, s.current_level, people.placement_settled(s.id) INTO v_sid, v_cur_prog, v_cur_level, v_settled
              FROM people.student s WHERE upper(s.matric_no) = v_matric;
            SELECT true INTO v_exists FROM people.student WHERE upper(matric_no) = v_matric;
            INSERT INTO people.student (id, matric_no, surname, other_names, sex, date_of_birth, state_of_origin,
                                        jamb_reg_no, programme_code, entry_mode, entry_session, entry_level, current_level,
                                        status, matriculated_at)
            VALUES (gen_random_uuid(), v_matric, v_surname, v_others, v_sex, v_dob, v_state, v_jamb, v_prog_code, v_mode,
                    v_es, v_el, v_cl, 'ACTIVE', now())
            ON CONFLICT (matric_no) DO UPDATE SET
                surname = EXCLUDED.surname, other_names = EXCLUDED.other_names,
                sex = coalesce(EXCLUDED.sex, people.student.sex),
                date_of_birth = coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth),
                state_of_origin = coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                jamb_reg_no = coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no),
                programme_code = CASE WHEN v_settled IS NOT NULL THEN people.student.programme_code ELSE EXCLUDED.programme_code END,
                -- V459: the level changes only when the file states one (people.upload_kept_level: never a postgraduate
                -- below 700); a postgraduate programme's row re-files a student wrongly filed as undergraduate (people.upload_kept_mode)
                current_level = CASE WHEN v_settled IS NOT NULL THEN people.student.current_level
                                     ELSE people.upload_kept_level(people.student.entry_mode, people.student.current_level, EXCLUDED.entry_mode, EXCLUDED.current_level, v_stated) END,
                entry_mode = people.upload_kept_mode(people.student.entry_mode, EXCLUDED.entry_mode),
                entry_level = CASE WHEN EXCLUDED.entry_mode = 'POSTGRADUATE' AND people.student.entry_mode NOT IN ('POSTGRADUATE', 'CCE')
                                        AND coalesce(people.student.entry_level, 0) < 700
                                   THEN EXCLUDED.entry_level ELSE people.student.entry_level END
            WHERE (people.student.surname, people.student.other_names, people.student.sex, people.student.date_of_birth,
                   people.student.state_of_origin, people.student.jamb_reg_no, people.student.programme_code, people.student.current_level,
                   people.student.entry_mode)
                  IS DISTINCT FROM (EXCLUDED.surname, EXCLUDED.other_names, coalesce(EXCLUDED.sex, people.student.sex),
                   coalesce(EXCLUDED.date_of_birth, people.student.date_of_birth), coalesce(EXCLUDED.state_of_origin, people.student.state_of_origin),
                   coalesce(EXCLUDED.jamb_reg_no, people.student.jamb_reg_no),
                   CASE WHEN v_settled IS NOT NULL THEN people.student.programme_code ELSE EXCLUDED.programme_code END,
                   CASE WHEN v_settled IS NOT NULL THEN people.student.current_level
                        ELSE people.upload_kept_level(people.student.entry_mode, people.student.current_level, EXCLUDED.entry_mode, EXCLUDED.current_level, v_stated) END,
                   people.upload_kept_mode(people.student.entry_mode, EXCLUDED.entry_mode));
            IF v_settled IS NOT NULL AND (v_cur_prog IS DISTINCT FROM v_prog_code OR (v_stated AND v_cur_level IS DISTINCT FROM v_cl)) THEN
                PERFORM people.note_placement_conflict(v_sid, 'BIOGRAPHY_UPLOAD', v_prog_code, CASE WHEN v_stated THEN v_cl END, v_cur_prog, v_cur_level, v_settled);
            END IF;
            SELECT id INTO v_student FROM people.student WHERE upper(matric_no) = v_matric;

            v_phone := regexp_replace(coalesce(r->>'phone', r->>'mobile', ''), '[^0-9]', '', 'g');
            IF length(v_phone) = 10 THEN v_phone := '0' || v_phone;
            ELSIF length(v_phone) = 13 AND left(v_phone, 3) = '234' THEN v_phone := '0' || right(v_phone, 10);
            END IF;
            IF v_phone !~ '^0[0-9]{10}$' THEN v_phone := NULL; END IF;

            v_email := lower(nullif(btrim(coalesce(r->>'email', r->>'loginemail', '')), ''));
            IF v_email IS NOT NULL AND v_email !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN v_email := NULL; END IF;

            v_addr := nullif(btrim(coalesce(r->>'address', '')), '');

            IF v_phone IS NOT NULL OR v_email IS NOT NULL OR v_addr IS NOT NULL THEN
                INSERT INTO people.student_contact (student_id, phone, email, address)
                VALUES (v_student, v_phone, v_email, v_addr)
                ON CONFLICT (student_id) DO UPDATE SET
                    phone = coalesce(EXCLUDED.phone, people.student_contact.phone),
                    email = coalesce(EXCLUDED.email, people.student_contact.email),
                    address = coalesce(EXCLUDED.address, people.student_contact.address),
                    updated_at = now()
                WHERE (people.student_contact.phone, people.student_contact.email, people.student_contact.address)
                      IS DISTINCT FROM (coalesce(EXCLUDED.phone, people.student_contact.phone),
                                        coalesce(EXCLUDED.email, people.student_contact.email),
                                        coalesce(EXCLUDED.address, people.student_contact.address));
                l_contact := 1;
            END IF;

            FOR bf, bv IN
                SELECT key, value FROM jsonb_each_text(jsonb_strip_nulls(jsonb_build_object(
                    'nationality',      nullif(btrim(coalesce(r->>'nationality', '')), ''),
                    'state_of_origin',  v_state,
                    'lga',              nullif(btrim(coalesce(r->>'lga', '')), ''),
                    'guardian_name',    nullif(btrim(coalesce(r->>'guardianName', r->>'guardianname', '')), ''),
                    'guardian_address', nullif(btrim(coalesce(r->>'guardianAddress', r->>'guardianaddress', '')), ''),
                    'sponsor_name',     nullif(btrim(coalesce(r->>'sponsorName', r->>'sponsorname', '')), ''),
                    'sponsor_address',  nullif(btrim(coalesce(r->>'sponsorAddress', r->>'sponsoraddress', '')), ''),
                    'kin_name',         nullif(btrim(coalesce(r->>'nokName', r->>'nokname', r->>'kinName', '')), ''),
                    'kin_address',      nullif(btrim(coalesce(r->>'nokAddress', r->>'nokaddress', r->>'kinAddress', '')), ''),
                    'extracurricular',  nullif(btrim(coalesce(r->>'extracurricular', '')), ''),
                    'legacy_appno',     nullif(btrim(coalesce(r->>'appno', r->>'applicationNo', '')), '')
                )))
            LOOP
                INSERT INTO people.biodata (student_id, field, value) VALUES (v_student, bf, bv)
                ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value
                WHERE people.biodata.value IS DISTINCT FROM EXCLUDED.value;
                l_bio := l_bio + 1;
            END LOOP;

            IF NOT EXISTS (SELECT 1 FROM iam.student_account WHERE student_id = v_student) THEN
                -- sealed: a cost-12 hash of a random secret nobody holds, made once for the upload rather than once a
                -- row; the student's first sign-in is their own number (must_change), never this
                IF v_sealed IS NULL THEN v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12)); END IF;
                INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
                VALUES (gen_random_uuid(), v_student, v_sealed, true);
                l_acct := 1;
            END IF;

            IF coalesce(v_exists, false) THEN nu := nu + 1; ELSE nc := nc + 1; END IF;
            ncontact := ncontact + l_contact;
            nbio := nbio + l_bio;
            nacct := nacct + l_acct;
        EXCEPTION WHEN OTHERS THEN
            nerr := nerr + 1;
            IF v_firsterr IS NULL THEN
                v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300);
            END IF;
        END;
    END LOOP;

    RETURN QUERY SELECT n, nc, nu, nnp, nbn, ncontact, nbio, nacct, nerr, v_firsterr;
END $function$;

COMMIT;

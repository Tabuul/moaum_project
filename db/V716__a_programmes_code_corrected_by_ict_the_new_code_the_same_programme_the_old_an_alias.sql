-- ════════════════════════════════════════════════════════════════════════
--  V716 · A programme's code corrected by the Director of ICT and the ICT Support Desk — the same programme under the new code, the
--  old code an alias
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 31 October 2026 ("can i edit/update or change programme code?" — "do it"), built as the course correction
--  (V713) was: a reason from a list, the impact shown first, a version check, a trail, a ticket where there is one; and on the
--  programme merge's machinery (V574), which already moves every record naming a programme and keeps the old code landing.
--
--  A programme's code (ref.programme.code, C plus five digits — JAMB's code) is the key 42 tables point at. Nothing changed it;
--  the merge joined two programmes, which is not a correction. Now ref.correct_programme_code(code, newCode, reasonKind, remarks,
--  version, ticket):
--   · the new code is written as a copy of the programme (its name, department, faculty, category, award, matriculation code, final
--     level — every column), in use;
--   · the programme is merged into the copy (ref.merge_programme, V574): every record ref.programme_reference says moves — students
--     (each postgraduate move on people.record_move), applications, fee lines, course bindings, specialisations, the rest — moves to
--     the new code, recorded row by row (ref.programme_merge_row); the old code becomes an alias of the new (ref.programme_alias: a
--     record written later with the old code — an upload, a JAMB list, an old-portal file — lands on the new) and is archived;
--     history (KEEP) stays as written, under the old code, which keeps its name;
--   · what JAMB calls the programme follows: ref.jamb_alias copied to the new code, ref.jamb_alias_name moved;
--   · written to ref.programme_code_change (the reason, the remarks, the ticket, the merge, how many students, what moved), kept.
--  Refused: an office other than ict, ictagent, helpdeskhead or super (PROGRAMME_CODE_OFFICE; an agent within its posting's scope,
--  EDIT_PROGRAMME_CODE, the API's check); a newer version than the one read (PROGRAMME_CHANGED_SINCE); no reason, or Other without
--  remarks (PROGRAMME_CHANGE_REASON); a code of the wrong shape (PROGRAMME_CODE_SHAPE); the code as it stands (PROGRAMME_CODE_UNCHANGED);
--  a programme already merged away (PROGRAMME_MERGED); a code another programme holds, in use or archived (PROGRAMME_CODE_TAKEN: the
--  same programme twice is merged on Records › Programme Merge, never corrected into). ref.undo_programme_code_correction(id, reason)
--  undoes it from the record: the merge undone (every row back, the alias ended, the old code in use), the JAMB names back, the new
--  code archived (the merge's record names it, so it stays on the register) — and reused by a later correction while nothing names it.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V716: a programme''s code corrected by ICT', true);

-- ── 1 · the support desk's capability ──────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION helpdesk.support_capabilities()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT ARRAY['VIEW_STUDENT', 'EDIT_CONTACT', 'EDIT_PERSONAL', 'EDIT_FAMILY', 'EDIT_PHOTO', 'REQUEST_CHANGE',
                 'VIEW_PAYMENTS', 'VIEW_DOCUMENTS', 'MANAGE_REGISTRATION', 'EXPORT_STUDENTS',
                 'OVERRIDE_REGISTRATION', 'RESET_PASSWORD', 'INVESTIGATE_PAYMENT', 'VERIFY_PAYMENT', 'SYNC_ENTITLEMENT',
                 'REGENERATE_RECEIPT', 'CREATE_TICKET', 'VIEW_SUPPORT_AUDIT',
                 'VIEW_ALLOCATIONS', 'ALLOCATE_COURSES', 'REMOVE_ALLOCATIONS', 'BULK_ALLOCATE',
                 'VIEW_PROGRAMME_STRUCTURE', 'EDIT_COURSES', 'BIND_COURSES', 'MANAGE_PREREQUISITES',
                 'PROGRESS_LEVEL', 'CORRECT_LEVEL', 'VIEW_LEVEL_HISTORY', 'VIEW_RESET_HISTORY',
                 'VIEW_STUDENT_PORTAL',
                 -- V559: many students reset to the default credential in one operation, within the posting's scope
                 'BULK_RESET_PASSWORD',
                 -- V582: the students of the login and password tickets the agent ticks, reset from the desk's queue
                 'BULK_RESET_FROM_TICKETS',
                 -- V713: a course's code, a course's title — corrected with a reason (EDIT_COURSES carries both)
                 'EDIT_COURSE_CODE', 'EDIT_COURSE_TITLE',
                 -- V716: a programme's code corrected with a reason, within the posting's faculties and departments
                 'EDIT_PROGRAMME_CODE']
$function$;

-- ── 2 · the merge's office rule passes a code correction (the correction's own rule stands in front of it) ────────────────
CREATE OR REPLACE FUNCTION ref.programme_merge_office(p_category text)
RETURNS void LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF coalesce(current_setting('moaum.programme_merge_preview', true), '') = 'on' THEN RETURN; END IF;
    IF coalesce(current_setting('moaum.programme_correction', true), '') = 'on' THEN RETURN; END IF;   -- V716: ref.correct_programme_code
    IF v_office IN ('records', 'registrar', 'dregistrar', 'super') THEN RETURN; END IF;
    IF v_office IN ('pgschool', 'pgsecretary') AND p_category = 'POST GRADUATE' THEN RETURN; END IF;
    RAISE EXCEPTION 'PROGRAMME_MERGE_OFFICE: programmes are merged by the Registry, and postgraduate programmes by the School of Postgraduate Studies'
        USING ERRCODE = '42501';
END $fn$;

-- ── 3 · every correction of a programme's code, kept ───────────────────────────────────────────────────────────────────────
CREATE TABLE ref.programme_code_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    old_code       text NOT NULL,
    new_code       text NOT NULL,
    name           text NOT NULL,
    category       text NULL,
    reason_kind    text NOT NULL CHECK (reason_kind IN ('WRONG_CODE_ENTERED', 'JAMB_CODE_CHANGED', 'SENATE_RENUMBERING', 'MIGRATION_CORRECTION',
                                                        'LEGACY_DATA_CORRECTION', 'DUPLICATE_DATA_CORRECTION', 'ICT_SUPPORT_CORRECTION', 'OTHER')),
    remarks        text NULL CHECK (remarks IS NULL OR length(remarks) <= 2000),
    ticket_id      uuid NULL REFERENCES helpdesk.ticket (id),
    merge_id       uuid NOT NULL REFERENCES ref.programme_merge (id),
    students       integer NOT NULL DEFAULT 0,
    moved          jsonb NOT NULL DEFAULT '{}',
    changed_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
    changed_by     uuid NOT NULL,
    changed_office text NOT NULL,
    undone_at      timestamptz NULL,
    undone_by      uuid NULL,
    undone_office  text NULL,
    undo_reason    text NULL,
    new_code_kept  boolean NULL,                       -- undone: whether something still named the new code (else a later correction may take it again)
    CHECK (old_code <> new_code)
);
CREATE INDEX ix_programme_code_change_at ON ref.programme_code_change (changed_at DESC);
CREATE INDEX ix_programme_code_change_codes ON ref.programme_code_change (old_code, new_code);
COMMENT ON TABLE ref.programme_code_change IS
  'V716: every correction of a programme''s code by the Director of ICT or the ICT Support Desk — the reason and remarks, the ticket, the merge that '
  'carried the records (V574), how many students and what moved — and its undoing. Never removed; altered only by its undoing.';

CREATE OR REPLACE FUNCTION ref.programme_code_change_kept() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'PROGRAMME_CODE_CHANGE_KEPT: a programme code change is kept as it was written; it is never removed' USING ERRCODE = '23514';
    END IF;
    -- only its undoing is written on it afterwards
    IF OLD.undone_at IS NOT NULL
       OR row(NEW.id, NEW.old_code, NEW.new_code, NEW.name, NEW.category, NEW.reason_kind, NEW.remarks, NEW.ticket_id, NEW.merge_id, NEW.students, NEW.moved, NEW.changed_at, NEW.changed_by, NEW.changed_office)
          IS DISTINCT FROM row(OLD.id, OLD.old_code, OLD.new_code, OLD.name, OLD.category, OLD.reason_kind, OLD.remarks, OLD.ticket_id, OLD.merge_id, OLD.students, OLD.moved, OLD.changed_at, OLD.changed_by, OLD.changed_office)
       OR NEW.undone_at IS NULL THEN
        RAISE EXCEPTION 'PROGRAMME_CODE_CHANGE_KEPT: a programme code change is kept as it was written; only its undoing is written on it' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_programme_code_change_kept BEFORE UPDATE OR DELETE ON ref.programme_code_change
FOR EACH ROW EXECUTE FUNCTION ref.programme_code_change_kept();
SELECT audit.attach('ref.programme_code_change');
GRANT SELECT ON ref.programme_code_change TO app_auditor, app_acrecords, app_reporting;

-- the words of a reason
CREATE OR REPLACE FUNCTION ref.programme_change_reason_words(p_kind text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE p_kind
        WHEN 'WRONG_CODE_ENTERED' THEN 'Wrong code entered'
        WHEN 'JAMB_CODE_CHANGED' THEN 'JAMB code changed'
        WHEN 'SENATE_RENUMBERING' THEN 'Senate renumbering'
        WHEN 'MIGRATION_CORRECTION' THEN 'Migration correction'
        WHEN 'LEGACY_DATA_CORRECTION' THEN 'Legacy data correction'
        WHEN 'DUPLICATE_DATA_CORRECTION' THEN 'Duplicate data correction'
        WHEN 'ICT_SUPPORT_CORRECTION' THEN 'ICT Support correction'
        WHEN 'OTHER' THEN 'Other'
    END
$$;

-- who corrects: the Director of ICT, the ICT Support Desk (an agent within its posting's scope: the API's check), super
CREATE OR REPLACE FUNCTION ref.programme_code_officer() RETURNS uuid LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := coalesce(current_setting('moaum.actor_office', true), '');
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'PROGRAMME_CODE_ACTOR: a programme''s code is corrected by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('ict', 'ictagent', 'helpdeskhead', 'super') THEN
        RAISE EXCEPTION 'PROGRAMME_CODE_OFFICE: a programme''s code is corrected by the Director of ICT or the ICT Support Desk, not %', v_office USING ERRCODE = '42501';
    END IF;
    RETURN v_actor;
END $fn$;

-- ── 4 · the version a correction is made against ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ref.programme_version(p ref.programme) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT md5(p::text)
$$;
COMMENT ON FUNCTION ref.programme_version(ref.programme) IS
  'V716: the programme as the person read it — a correction made against an older version is refused (PROGRAMME_CHANGED_SINCE).';

-- whether anything names a programme by its code (every classed column; the aliases merged into it; a correction standing on it)
CREATE OR REPLACE FUNCTION ref.programme_code_named(p_code text) RETURNS boolean LANGUAGE plpgsql STABLE AS $fn$
DECLARE x record; v boolean;
BEGIN
    FOR x IN SELECT pr.tab, pr.col FROM ref.programme_reference pr
              WHERE EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = to_regclass(pr.tab) AND a.attname = pr.col AND NOT a.attisdropped) LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s WHERE %I = $1)', x.tab, x.col) INTO v USING p_code;
        IF v THEN RETURN true; END IF;
    END LOOP;
    RETURN EXISTS (SELECT 1 FROM ref.programme_alias a WHERE a.programme_code = p_code AND a.ended_at IS NULL)
        OR EXISTS (SELECT 1 FROM ref.programme_code_change k WHERE k.old_code = p_code AND k.undone_at IS NULL);
END $fn$;

-- a code left on the register by an undone correction, nothing naming it: a later correction may take it again
CREATE OR REPLACE FUNCTION ref.programme_code_reusable(p_code text) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM ref.programme_code_change k WHERE k.new_code = p_code AND k.undone_at IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM ref.programme_code_change k WHERE k.new_code = p_code AND k.undone_at IS NULL)
       AND EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = p_code AND p.archived)
       AND NOT ref.programme_code_named(p_code)
$fn$;

-- ── 5 · what hangs on a programme ──────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ref.programme_code_impact(p_code text) RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_code text := upper(btrim(coalesce(p_code, ''))); x record; v_n bigint; v_rows jsonb := '{}'; v_history jsonb := '{}';
BEGIN
    FOR x IN SELECT pr.tab, pr.col, pr.policy FROM ref.programme_reference pr
              WHERE pr.policy <> 'DERIVED'
                AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = to_regclass(pr.tab) AND a.attname = pr.col AND NOT a.attisdropped)
              ORDER BY pr.tab, pr.col LOOP
        EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', x.tab, x.col) INTO v_n USING v_code;
        IF v_n > 0 THEN
            IF x.policy = 'KEEP' THEN v_history := v_history || jsonb_build_object(x.tab || '.' || x.col, v_n);
            ELSE v_rows := v_rows || jsonb_build_object(x.tab || '.' || x.col, v_n); END IF;
        END IF;
    END LOOP;
    RETURN jsonb_build_object(
        'students', (SELECT count(*) FROM people.student s WHERE s.programme_code = v_code),
        'activeStudents', (SELECT count(*) FROM people.student s WHERE s.programme_code = v_code AND s.status = 'ACTIVE'),
        'pgApplications', (SELECT count(*) FROM admissions.pg_application a WHERE a.programme_code = v_code),
        'cceCandidates', (SELECT count(*) FROM admissions.cce_candidate c WHERE c.programme_code = v_code),
        'jupebApplications', (SELECT count(*) FROM jupeb.application j WHERE j.programme_code = v_code),
        'feeLines', (SELECT count(*) FROM finance.fee_schedule f WHERE f.programme_code = v_code AND f.ended_at IS NULL),
        'courseBindings', (SELECT count(*) FROM catalogue.course_offer o WHERE o.programme_code = v_code),
        'specialisations', (SELECT count(*) FROM catalogue.programme_specialisation sp WHERE sp.programme_code = v_code),
        'ownedCourses', (SELECT count(*) FROM catalogue.course c WHERE c.owner_programme = v_code),
        'transfersIn', (SELECT count(*) FROM people.transfer_application t WHERE t.to_programme_code = v_code),
        'aliases', (SELECT coalesce(jsonb_agg(a.alias_code ORDER BY a.alias_code), '[]'::jsonb) FROM ref.programme_alias a WHERE a.programme_code = v_code AND a.ended_at IS NULL),
        'jambNames', (SELECT count(*) FROM ref.jamb_alias_name n WHERE n.code = v_code) + (SELECT count(*) FROM ref.jamb_alias j WHERE j.code = v_code),
        'rows', v_rows, 'history', v_history);
END $fn$;
COMMENT ON FUNCTION ref.programme_code_impact(text) IS
  'V716: what hangs on a programme — its students, applications, fee lines, course bindings, specialisations, courses it owns, transfers into it, the codes merged into it, what JAMB calls it; every classed column counted (rows move with a correction, history stays).';

-- ── 6 · what a correction would be, and why it would be refused ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ref.programme_code_check(p_code text, p_new_code text) RETURNS jsonb LANGUAGE plpgsql STABLE AS $fn$
DECLARE p ref.programme; v_new text := upper(regexp_replace(coalesce(p_new_code, ''), '\s+', '', 'g')); r_code text; r_msg text; o ref.programme; v_alias text;
BEGIN
    SELECT * INTO p FROM ref.programme WHERE code = upper(btrim(coalesce(p_code, '')));
    IF p.code IS NULL THEN RAISE EXCEPTION 'no programme is coded %', p_code USING ERRCODE = '23503'; END IF;
    v_alias := nullif(ref.programme_now(p.code), p.code);
    IF v_alias IS NOT NULL THEN
        r_code := 'PROGRAMME_MERGED'; r_msg := format('%s was merged into %s; the code is an alias of that programme and is not corrected. Undo the merge first if it was wrong.', p.code, v_alias);
    ELSIF v_new = '' THEN
        r_code := 'PROGRAMME_CODE_SHAPE'; r_msg := 'Give the programme''s new code.';
    ELSIF v_new !~ '^C[0-9]{5}$' THEN
        r_code := 'PROGRAMME_CODE_SHAPE'; r_msg := format('A programme code is C and five digits (C00023), as JAMB writes it; %s is not.', v_new);
    ELSIF v_new = p.code THEN
        r_code := 'PROGRAMME_CODE_UNCHANGED'; r_msg := 'The code is as it stands; nothing would change.';
    ELSE
        SELECT * INTO o FROM ref.programme WHERE code = v_new;
        IF o.code IS NOT NULL AND NOT ref.programme_code_reusable(v_new) THEN
            r_code := 'PROGRAMME_CODE_TAKEN';
            r_msg := format('%s is already a programme on the register: %s%s. A correction never joins two programmes — if they are one, merge them on Records › Programme Merge.',
                            o.code, o.name,
                            CASE WHEN nullif(ref.programme_now(o.code), o.code) IS NOT NULL THEN ' (merged into ' || ref.programme_now(o.code) || ')'
                                 WHEN o.archived THEN ' (archived)' ELSE '' END);
        END IF;
    END IF;
    RETURN jsonb_build_object('code', p.code, 'name', p.name, 'category', p.category, 'deptCode', p.dept_code, 'facultyCode', p.faculty_code,
                              'archived', p.archived, 'version', ref.programme_version(p), 'newCode', nullif(v_new, ''),
                              'reused', o.code IS NOT NULL AND r_code IS NULL,
                              'refusal', CASE WHEN r_code IS NULL THEN NULL ELSE jsonb_build_object('code', r_code, 'message', r_msg) END,
                              'impact', ref.programme_code_impact(p.code));
END $fn$;
COMMENT ON FUNCTION ref.programme_code_check(text, text) IS
  'V716: what a correction of a programme''s code would be — the programme as it reads, its version, what hangs on it — and why it would be refused. Changes nothing.';

-- ── 7 · the correction ─────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ref.correct_programme_code(p_code text, p_new_code text, p_reason_kind text, p_remarks text, p_version text, p_ticket uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := ref.programme_code_officer(); v_office text := current_setting('moaum.actor_office', true); p ref.programme; chk jsonb; v_kind text; v_rem text;
        v_new text; v_merge jsonb; v_id uuid; v_names int := 0; v_jamb int := 0; n ref.programme; v_cols text;
BEGIN
    SELECT * INTO p FROM ref.programme WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF p.code IS NULL THEN RAISE EXCEPTION 'no programme is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF p_version IS NULL OR p_version <> ref.programme_version(p) THEN
        RAISE EXCEPTION 'PROGRAMME_CHANGED_SINCE: % has been updated by another user since you opened it. Reload the latest version before making your change.', p.code
            USING ERRCODE = '23514', HINT = 'Reload the programme; your change was not saved.';
    END IF;
    v_kind := upper(btrim(coalesce(p_reason_kind, '')));
    IF ref.programme_change_reason_words(v_kind) IS NULL THEN
        RAISE EXCEPTION 'PROGRAMME_CHANGE_REASON: a programme''s code is corrected for a reason — choose one from the list' USING ERRCODE = '23514';
    END IF;
    v_rem := nullif(regexp_replace(btrim(coalesce(p_remarks, '')), '\s+', ' ', 'g'), '');
    IF v_kind = 'OTHER' AND (v_rem IS NULL OR length(v_rem) < 5) THEN
        RAISE EXCEPTION 'PROGRAMME_CHANGE_REASON: "Other" is explained in the remarks' USING ERRCODE = '23514';
    END IF;
    IF v_rem IS NOT NULL AND length(v_rem) > 2000 THEN
        RAISE EXCEPTION 'PROGRAMME_CHANGE_REASON: the remarks are at most 2000 characters' USING ERRCODE = '23514';
    END IF;
    chk := ref.programme_code_check(p.code, p_new_code);
    IF chk->'refusal' IS NOT NULL AND jsonb_typeof(chk->'refusal') = 'object' THEN
        RAISE EXCEPTION '%: %', chk->'refusal'->>'code', chk->'refusal'->>'message' USING ERRCODE = '23514';
    END IF;
    v_new := chk->>'newCode';

    -- the new code: a copy of the programme, every column, in use (a code an undone correction left, nothing naming it, taken again)
    IF (chk->>'reused')::boolean THEN
        SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum) INTO v_cols
          FROM pg_attribute a WHERE a.attrelid = 'ref.programme'::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attname <> 'code';
        EXECUTE format('UPDATE ref.programme SET (%s) = (SELECT %s FROM ref.programme WHERE code = $1) WHERE code = $2', v_cols, v_cols) USING p.code, v_new;
        UPDATE ref.programme SET archived = false WHERE code = v_new;
    ELSE
        INSERT INTO ref.programme SELECT * FROM jsonb_populate_record(NULL::ref.programme, to_jsonb(p) || jsonb_build_object('code', v_new, 'archived', false));
    END IF;
    -- what JAMB calls it follows: the primary name copied, every further name moved
    INSERT INTO ref.jamb_alias (code, jamb_name) SELECT v_new, j.jamb_name FROM ref.jamb_alias j WHERE j.code = p.code ON CONFLICT (code) DO NOTHING;
    GET DIAGNOSTICS v_jamb = ROW_COUNT;
    UPDATE ref.jamb_alias_name SET code = v_new WHERE code = p.code;
    GET DIAGNOSTICS v_names = ROW_COUNT;

    -- the programme merged into its copy: every record moves, recorded; the old code an alias, archived (V574)
    PERFORM set_config('moaum.programme_correction', 'on', true);
    v_merge := ref.merge_programme(p.code, v_new, 'Programme code corrected (' || ref.programme_change_reason_words(v_kind) || ')' || coalesce(': ' || v_rem, ''));
    PERFORM set_config('moaum.programme_correction', '', true);

    INSERT INTO ref.programme_code_change (old_code, new_code, name, category, reason_kind, remarks, ticket_id, merge_id, students, moved, changed_by, changed_office)
    VALUES (p.code, v_new, p.name, p.category, v_kind, v_rem, p_ticket, (v_merge->>'id')::uuid, coalesce((v_merge->>'students')::int, 0),
            coalesce(v_merge->'moved', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object('ref.jamb_alias_name.code', nullif(v_names, 0), 'ref.jamb_alias.code', nullif(v_jamb, 0))),
            who, v_office)
    RETURNING id INTO v_id;
    SELECT * INTO n FROM ref.programme WHERE code = v_new;
    RETURN jsonb_build_object('id', v_id, 'code', v_new, 'was', p.code, 'name', p.name, 'category', p.category, 'students', coalesce((v_merge->>'students')::int, 0),
                              'reused', (chk->>'reused')::boolean,
                              'moved', v_merge->'moved', 'kept', v_merge->'kept', 'mergeId', v_merge->>'id', 'version', ref.programme_version(n),
                              'reason', ref.programme_change_reason_words(v_kind), 'remarks', v_rem);
END $fn$;
COMMENT ON FUNCTION ref.correct_programme_code(text, text, text, text, text, uuid) IS
  'V716: a programme''s code corrected — the new code a copy of the programme, the programme merged into it (V574: every record moves, recorded; the old code an alias, archived), what JAMB calls it following — against the version the person read, for a reason from the list (remarks for Other); written to ref.programme_code_change with the ticket.';

-- ── 8 · undone from the record ─────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ref.undo_programme_code_correction(p_change uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE who uuid := ref.programme_code_officer(); v_office text := current_setting('moaum.actor_office', true); c ref.programme_code_change; v_reason text := btrim(coalesce(p_reason, ''));
        u jsonb; v_named boolean := false;
BEGIN
    IF length(v_reason) < 10 THEN RAISE EXCEPTION 'PROGRAMME_CHANGE_REASON: say why the correction is undone, ten characters or more' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM ref.programme_code_change WHERE id = p_change FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'PROGRAMME_CODE_CHANGE_UNKNOWN: no such correction' USING ERRCODE = '23514'; END IF;
    IF c.undone_at IS NOT NULL THEN
        RAISE EXCEPTION 'PROGRAMME_CODE_CHANGE_UNDONE: this correction was undone on %', to_char(c.undone_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') USING ERRCODE = '23514';
    END IF;
    -- the merge undone: every row back on the old code, the alias ended, the old code in use again (refused when the new code was merged away since)
    PERFORM set_config('moaum.programme_correction', 'on', true);
    u := ref.undo_programme_merge(c.merge_id, 'Programme code correction undone: ' || v_reason);
    PERFORM set_config('moaum.programme_correction', '', true);
    -- what JAMB calls it, back
    UPDATE ref.jamb_alias_name SET code = c.old_code WHERE code = c.new_code;
    IF (c.moved ? 'ref.jamb_alias.code') THEN DELETE FROM ref.jamb_alias WHERE code = c.new_code; END IF;
    -- the new code stays on the register, archived (the merge's record names it): named by nothing, a later correction may take it again
    UPDATE ref.programme SET archived = true WHERE code = c.new_code;
    v_named := ref.programme_code_named(c.new_code);
    UPDATE ref.programme_code_change SET undone_at = now(), undone_by = who, undone_office = v_office, undo_reason = v_reason, new_code_kept = v_named WHERE id = c.id;
    RETURN jsonb_build_object('id', c.id, 'code', c.old_code, 'was', c.new_code, 'name', c.name, 'students', u->>'students', 'rows', u->>'rows', 'newCodeNamed', v_named);
END $fn$;
COMMENT ON FUNCTION ref.undo_programme_code_correction(uuid, text) IS
  'V716: a programme code correction undone from its record — the merge undone (V574: every row back, the alias ended, the old code in use), the JAMB names back, the new code archived (reused by a later correction while nothing names it); the undoing written on the record.';

COMMIT;

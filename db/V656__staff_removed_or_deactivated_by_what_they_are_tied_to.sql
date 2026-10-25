-- V656: staff removed or deactivated, the database deciding what each person is tied to. The University's word of 25 October 2026:
-- "add delete button to view all lecturers, we should be able to add and delete lecturers and non academic staff as well".
--
-- What there was. The teaching-staff desk (t/lecturers) could add, edit and tick lecturers for "Delete selected"; iam.delete_lecturers
-- (V138) deleted the person outright — the sign-in and its history, every office grant, the establishment record — unless the
-- lecturer taught a class, when it was skipped with no word of why. Anything else the person had touched (a score sheet, a
-- deferment decision, a ticket, a payslip) either blocked the delete or would have lost its link. The non-academic desk (t/staffupload)
-- could only load the roll: no single add, no delete.
--
-- What it does now. A person is part of the University's records once anything points at them. So:
--   · iam.staff_ties(person): what the person is tied to — every foreign key to iam.person outside the person's own rows (the sign-in,
--     its events, the office grants, the staff record, photo and profile, contact reminders), read from the catalogue so a table added
--     later is counted without a change here; a sign-in made or tried; a change made on the portal (the audit trail's actor).
--   · iam.remove_staff(ids, mode, reason code, reason, apply): AUTO — a person tied to nothing is deleted permanently, a person tied
--     to anything is deactivated (taken off every list, sign-in refused, every office grant ended yesterday, open sessions ended;
--     nothing they did is touched); REMOVE — deleted only where tied to nothing (CANNOT_REMOVE otherwise, unchanged); DEACTIVATE —
--     always deactivated. Refused, unchanged: the acting person themselves (SELF), a person holding a live office other than lecturer
--     (HOLDS_OFFICE — the Head of Department, the Dean, the Bursar… are ended on Users & roles first), a person who is also a student
--     on the register (IS_STUDENT), one already ended (ALREADY_ENDED), one not on the staff register (NOT_STAFF), and a person the
--     acting office may not change (NOT_PERMITTED): teaching staff by the Registry and the Directorate of ICT (as their sign-ins),
--     non-academic staff also by Human Resources. Without apply it is a preview and writes nothing. A reason is required: added in
--     error, a duplicate, left the University, deceased, or other (described).
--   · iam.staff_change: every removal, deactivation and restoration, written once — the person, staff record, grants and sign-in as
--     they were (never the password), what tied them, the reason, who and when; on the audit spine.
--   · iam.restore_staff(change, reason code, reason): a deactivation undone — the person back on the lists, the grants it ended
--     reopened to the end each had; once.
--   · iam.staff_changes(category): the removed and deactivated staff, newest first, each deactivation saying whether it can be restored.
BEGIN;

-- ── 1 · the record of every change ─────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE iam.staff_change (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id uuid NOT NULL,              -- no key: a person removed is gone from the register, and kept here
    staff_number text,
    name text NOT NULL,
    category text CHECK (category IN ('ACADEMIC', 'NON_ACADEMIC')),
    action text NOT NULL CHECK (action IN ('STAFF_REMOVED', 'STAFF_DEACTIVATED', 'STAFF_RESTORED')),
    reason_code text NOT NULL CHECK (reason_code IN ('ADDED_IN_ERROR', 'DUPLICATE', 'LEFT_SERVICE', 'DECEASED', 'OTHER',
                                                     'DEACTIVATED_IN_ERROR', 'RETURNED_TO_SERVICE')),
    reason text,
    ties jsonb NOT NULL DEFAULT '[]'::jsonb,          -- what tied the person to the records when it was done
    before_state jsonb NOT NULL,                      -- the person, staff record, grants and sign-in as they were (never the password)
    grants_ended jsonb NOT NULL DEFAULT '[]'::jsonb,  -- a deactivation: [{id, valid_to_before, valid_to_set}]
    restores uuid,                                    -- a restoration: the deactivation it undoes
    batch uuid NOT NULL,
    actor uuid NOT NULL,
    actor_office text,
    at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_staff_change_other CHECK (reason_code <> 'OTHER' OR length(btrim(coalesce(reason, ''))) >= 10),
    CONSTRAINT ck_staff_change_restores CHECK ((action = 'STAFF_RESTORED') = (restores IS NOT NULL))
);
CREATE INDEX ix_staff_change_person ON iam.staff_change (person_id, at DESC);
CREATE INDEX ix_staff_change_at ON iam.staff_change (at DESC);
CREATE UNIQUE INDEX ux_staff_change_restored ON iam.staff_change (restores) WHERE restores IS NOT NULL;   -- a deactivation is undone once
SELECT audit.attach('iam.staff_change');
COMMENT ON TABLE iam.staff_change IS
  'V656: every member of staff removed, deactivated or restored — the person, staff record, office grants and sign-in as they were (never the password), what tied them to the records, the reason, who and when. Kept: never changed, removed only by the go-live reset (moaum.maintenance).';

CREATE FUNCTION iam.staff_change_kept()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' AND coalesce(current_setting('moaum.maintenance', true), '') = 'on' THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'STAFF_CHANGE_KEPT: a change to the staff register is kept as it was made' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_staff_change_kept BEFORE UPDATE OR DELETE ON iam.staff_change
    FOR EACH ROW EXECUTE FUNCTION iam.staff_change_kept();

CREATE FUNCTION iam.staff_reason_words(p_code text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_code
        WHEN 'ADDED_IN_ERROR' THEN 'Added in error'
        WHEN 'DUPLICATE' THEN 'A duplicate record'
        WHEN 'LEFT_SERVICE' THEN 'Left the University'
        WHEN 'DECEASED' THEN 'Deceased'
        WHEN 'DEACTIVATED_IN_ERROR' THEN 'Deactivated in error'
        WHEN 'RETURNED_TO_SERVICE' THEN 'Returned to service'
        WHEN 'OTHER' THEN 'Other'
    END
$$;

-- ── 2 · who may change whom ─────────────────────────────────────────────────────────────────────────────────────────────────
-- teaching staff by the offices that issue their sign-ins (the teaching-staff desk); non-academic staff also by Human Resources
CREATE FUNCTION iam.staff_change_may(p_office text, p_category text)
RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_category = 'NON_ACADEMIC' THEN coalesce(p_office, '') IN ('registrar', 'dregistrar', 'hrm', 'ict', 'admin', 'super')
                WHEN p_category = 'ACADEMIC' THEN coalesce(p_office, '') IN ('registrar', 'dregistrar', 'ict', 'admin', 'super')
                ELSE false END
$$;

-- a person's staff category: teaching staff where they ever held the lecturer office, else as their staff record says
CREATE FUNCTION iam.staff_category(p_person uuid)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p_person AND a.office_code = 'lecturer') THEN 'ACADEMIC'
                ELSE (SELECT sr.category FROM hrm.staff_record sr WHERE sr.person_id = p_person) END
$$;

-- ── 3 · what a person is tied to ───────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION iam.staff_tie_label(p_schema text, p_table text, p_column text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_schema = 'catalogue' AND p_table = 'offering' AND p_column = 'lecturer_id' THEN 'Lecturer of a course class'
        WHEN p_schema = 'catalogue' AND p_table = 'offering' THEN 'Examiner of a course class'
        WHEN p_schema = 'catalogue' AND p_table = 'offering_teacher' THEN 'Co-lecturer of a course class'
        WHEN p_schema = 'catalogue' AND p_table = 'allocation_event' THEN 'Course allocation history'
        WHEN p_schema = 'hrm' AND p_table = 'payslip' THEN 'Payslips'
        WHEN p_schema = 'hrm' AND p_table = 'employment' THEN 'Employment record'
        WHEN p_schema = 'hrm' AND p_table = 'appraisal' THEN 'Appraisals'
        WHEN p_schema = 'hrm' AND p_table = 'leave_request' THEN 'Leave requests'
        WHEN p_schema = 'hrm' AND p_table = 'movement' THEN 'Staff movements'
        WHEN p_schema = 'hrm' THEN 'Human resources records'
        WHEN p_schema = 'people' AND p_table = 'student' THEN 'A student on the register'
        WHEN p_schema = 'people' THEN 'Student requests decided or checked'
        WHEN p_schema = 'helpdesk' THEN 'ICT Support work'
        WHEN p_schema = 'admissions' THEN 'Admissions decisions and scores'
        WHEN p_schema = 'assessment' THEN 'Examination or SIWES duties'
        WHEN p_schema = 'attendance' THEN 'Attendance records'
        WHEN p_schema = 'college' THEN 'College of Health Sciences records'
        WHEN p_schema = 'credentials' THEN 'Staff identity card'
        WHEN p_schema = 'extexam' THEN 'External examination records'
        WHEN p_schema = 'library' THEN 'Library loans'
        WHEN p_schema = 'health' THEN 'Health centre records'
        WHEN p_schema = 'hostel' THEN 'Hostel allocation'
        WHEN p_schema = 'reports' THEN 'Reports filed'
        ELSE initcap(replace(p_table, '_', ' ')) || ' records'
    END
$$;

-- read once for a set of people: one query per foreign key, never one per person
CREATE FUNCTION iam.staff_ties_of(p_ids uuid[])
RETURNS TABLE (person_id uuid, kind text, label text, n bigint)
LANGUAGE plpgsql STABLE AS $$
DECLARE r record;
BEGIN
    -- every foreign key to a person, read from the catalogue (a table added later is counted too), but the person's own rows
    FOR r IN
        SELECT c.conrelid::regclass::text AS tbl, ns.nspname AS sch, cl.relname AS rel, a.attname AS col
          FROM pg_constraint c
          JOIN pg_class cl ON cl.oid = c.conrelid
          JOIN pg_namespace ns ON ns.oid = cl.relnamespace
          JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
         WHERE c.contype = 'f' AND c.confrelid = 'iam.person'::regclass AND cardinality(c.conkey) = 1 AND c.conparentid = 0
           AND (ns.nspname || '.' || cl.relname) NOT IN ('iam.credential', 'iam.credential_event', 'iam.office_assignment', 'hrm.staff_record',
                                                         'hrm.staff_photo', 'hrm.staff_profile', 'iam.staff_contact_reminder')
         ORDER BY 1, 4
    LOOP
        RETURN QUERY EXECUTE format('SELECT %I, $2, $3, count(*) FROM %s WHERE %I = ANY ($1) GROUP BY %I', r.col, r.tbl, r.col, r.col)
            USING p_ids, r.sch || '.' || r.rel || '.' || r.col, iam.staff_tie_label(r.sch, r.rel, r.col);
    END LOOP;
    -- a sign-in made, or tried
    RETURN QUERY SELECT c.person_id, 'SIGNED_IN'::text, 'Has signed in to the portal'::text, 1::bigint
                   FROM iam.credential c WHERE c.person_id = ANY (p_ids) AND c.last_sign_in_at IS NOT NULL;
    RETURN QUERY SELECT e.person_id, 'SIGN_IN_ATTEMPTS'::text, 'Sign-in attempts on record'::text, count(*)
                   FROM iam.sign_in_event e
                  WHERE e.person_id = ANY (p_ids)
                    AND NOT EXISTS (SELECT 1 FROM iam.credential c WHERE c.person_id = e.person_id AND c.last_sign_in_at IS NOT NULL)
                  GROUP BY e.person_id;
    -- a change made on the portal, as the audit trail's actor (counted to a thousand)
    RETURN QUERY SELECT x.id, 'ACTED'::text, 'Changes made on the portal'::text, y.k
                   FROM unnest(p_ids) AS x(id),
                        LATERAL (SELECT count(*) AS k FROM (SELECT 1 FROM audit.entries e WHERE e.actor_id = x.id LIMIT 1000) z) y
                  WHERE y.k > 0;
END $$;
COMMENT ON FUNCTION iam.staff_ties_of(uuid[]) IS
  'V656: what each of a set of people is tied to — every foreign key to iam.person outside their own rows (read from the catalogue), a sign-in made or tried, a change made on the portal; one query per key for the whole set. Nothing tied: a person may be deleted; anything: only deactivated.';

CREATE FUNCTION iam.staff_ties(p_person uuid)
RETURNS TABLE (kind text, label text, n bigint)
LANGUAGE sql STABLE AS $$
    SELECT t.kind, t.label, t.n FROM iam.staff_ties_of(ARRAY[p_person]) t ORDER BY t.label
$$;
COMMENT ON FUNCTION iam.staff_ties(uuid) IS 'V656: what one person is tied to (iam.staff_ties_of).';

-- the person as they stand, for the record: never the password
CREATE FUNCTION iam.staff_snapshot(p_person uuid)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'person', (SELECT to_jsonb(p) FROM iam.person p WHERE p.id = p_person),
        'staff_record', (SELECT to_jsonb(sr) FROM hrm.staff_record sr WHERE sr.person_id = p_person),
        'grants', coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.valid_from, a.office_code) FROM iam.office_assignment a WHERE a.person_id = p_person), '[]'::jsonb),
        'sign_in', (SELECT jsonb_build_object('username', c.username, 'set_at', c.set_at, 'last_sign_in_at', c.last_sign_in_at, 'must_change', c.must_change)
                      FROM iam.credential c WHERE c.person_id = p_person))
$$;

-- ── 4 · remove or deactivate ────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION iam.remove_staff(p_ids uuid[], p_mode text, p_reason_code text, p_reason text, p_apply boolean)
RETURNS TABLE (person_id uuid, staff_number text, name text, category text, ties jsonb, outcome text, detail text, applied boolean, change_id uuid)
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_mode text := upper(coalesce(nullif(btrim(p_mode), ''), 'AUTO'));
        v_code text := upper(nullif(btrim(coalesce(p_reason_code, '')), ''));
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_batch uuid := gen_random_uuid();
        v_ids uuid[]; v_tiemap jsonb;
        v_id uuid; p record; v_cat text; v_ties jsonb; v_offices text; v_before jsonb; v_grants jsonb; v_change uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'STAFF_ACTOR: a change to the staff register is made by a person' USING ERRCODE = '23514'; END IF;
    IF v_mode NOT IN ('AUTO', 'REMOVE', 'DEACTIVATE') THEN
        RAISE EXCEPTION 'STAFF_MODE: delete where nothing is tied and deactivate the rest, delete only, or deactivate only' USING ERRCODE = '23514';
    END IF;
    IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN RAISE EXCEPTION 'STAFF_NONE: name the staff to remove' USING ERRCODE = '23514'; END IF;
    IF cardinality(p_ids) > 500 THEN RAISE EXCEPTION 'STAFF_TOO_MANY: at most 500 at once' USING ERRCODE = '23514'; END IF;
    IF p_apply THEN
        IF v_code IS NULL OR v_code NOT IN ('ADDED_IN_ERROR', 'DUPLICATE', 'LEFT_SERVICE', 'DECEASED', 'OTHER') THEN
            RAISE EXCEPTION 'STAFF_REASON: say why — added in error, a duplicate, left the University, deceased, or other' USING ERRCODE = '23514';
        END IF;
        IF v_code = 'OTHER' AND length(coalesce(v_reason, '')) < 10 THEN
            RAISE EXCEPTION 'STAFF_REASON_OTHER: describe the reason in a few words' USING ERRCODE = '23514';
        END IF;
    END IF;

    v_ids := (SELECT array_agg(DISTINCT x) FROM unnest(p_ids) x WHERE x IS NOT NULL);
    IF v_ids IS NULL THEN RAISE EXCEPTION 'STAFF_NONE: name the staff to remove' USING ERRCODE = '23514'; END IF;
    -- what each is tied to, read once for them all
    v_tiemap := coalesce((SELECT jsonb_object_agg(q.pid::text, q.arr)
                            FROM (SELECT t.person_id AS pid, jsonb_agg(jsonb_build_object('kind', t.kind, 'label', t.label, 'n', t.n) ORDER BY t.label) AS arr
                                    FROM iam.staff_ties_of(v_ids) t GROUP BY t.person_id) q), '{}'::jsonb);

    FOREACH v_id IN ARRAY v_ids LOOP
        person_id := v_id; staff_number := NULL; name := NULL; category := NULL; ties := '[]'::jsonb; detail := NULL; applied := false; change_id := NULL;
        SELECT pe.* INTO p FROM iam.person pe WHERE pe.id = v_id;
        IF NOT FOUND THEN outcome := 'NOT_FOUND'; detail := 'No such person on the register'; RETURN NEXT; CONTINUE; END IF;
        staff_number := p.staff_number;
        name := btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, ''), ', ');
        v_cat := iam.staff_category(v_id);
        category := v_cat;
        IF v_id = v_actor THEN outcome := 'SELF'; detail := 'You cannot remove yourself'; RETURN NEXT; CONTINUE; END IF;
        IF p.ended_on IS NOT NULL THEN outcome := 'ALREADY_ENDED'; detail := 'Already deactivated on ' || to_char(p.ended_on, 'DD Mon YYYY'); RETURN NEXT; CONTINUE; END IF;
        IF v_cat IS NULL THEN outcome := 'NOT_STAFF'; detail := 'Not on the staff register'; RETURN NEXT; CONTINUE; END IF;
        IF NOT iam.staff_change_may(v_office, v_cat) THEN
            outcome := 'NOT_PERMITTED';
            detail := CASE WHEN v_cat = 'ACADEMIC' THEN 'Teaching staff are changed by the Registry and the Directorate of ICT'
                           ELSE 'Non-academic staff are changed by the Registry, Human Resources and the Directorate of ICT' END;
            RETURN NEXT; CONTINUE;
        END IF;
        IF EXISTS (SELECT 1 FROM people.student s WHERE s.person_id = v_id) THEN
            outcome := 'IS_STUDENT'; detail := 'Also a student on the register; their student record is the Registry''s'; RETURN NEXT; CONTINUE;
        END IF;
        v_offices := (SELECT string_agg(DISTINCT o.label, ', ') FROM iam.live_offices(v_id) o WHERE o.office_code <> 'lecturer');
        IF v_offices IS NOT NULL THEN
            outcome := 'HOLDS_OFFICE'; detail := 'Holds the office of ' || v_offices || '; end it on Users & roles first'; RETURN NEXT; CONTINUE;
        END IF;

        v_ties := coalesce(v_tiemap -> v_id::text, '[]'::jsonb);
        ties := v_ties;
        outcome := CASE WHEN v_mode = 'DEACTIVATE' THEN 'DEACTIVATE'
                        WHEN jsonb_array_length(v_ties) = 0 THEN 'REMOVE'
                        WHEN v_mode = 'REMOVE' THEN 'CANNOT_REMOVE'
                        ELSE 'DEACTIVATE' END;
        detail := CASE outcome WHEN 'REMOVE' THEN 'Tied to no record: deleted permanently'
                               WHEN 'CANNOT_REMOVE' THEN 'Tied to records: it can only be deactivated'
                               ELSE CASE WHEN jsonb_array_length(v_ties) = 0 THEN 'Deactivated as asked: off the lists, sign-in closed, kept on record'
                                         ELSE 'Tied to records: deactivated — off the lists, sign-in closed, everything they did kept' END END;
        IF NOT p_apply OR outcome = 'CANNOT_REMOVE' THEN RETURN NEXT; CONTINUE; END IF;

        v_before := iam.staff_snapshot(v_id);
        IF outcome = 'REMOVE' THEN
            BEGIN
                DELETE FROM iam.staff_contact_reminder r WHERE r.person_id = v_id;
                DELETE FROM iam.credential_event e WHERE e.person_id = v_id;
                DELETE FROM iam.credential c WHERE c.person_id = v_id;
                DELETE FROM iam.office_assignment a WHERE a.person_id = v_id;
                DELETE FROM hrm.staff_photo x WHERE x.person_id = v_id;
                DELETE FROM hrm.staff_profile x WHERE x.person_id = v_id;
                DELETE FROM hrm.staff_record x WHERE x.person_id = v_id;
                DELETE FROM iam.person x WHERE x.id = v_id;
            EXCEPTION WHEN foreign_key_violation THEN
                -- tied after all (a row written since the read): deactivated instead where AUTO asked, else left as it was
                IF v_mode = 'REMOVE' THEN
                    outcome := 'CANNOT_REMOVE'; detail := 'Tied to records: it can only be deactivated'; RETURN NEXT; CONTINUE;
                END IF;
                outcome := 'DEACTIVATE'; detail := 'Tied to records: deactivated — off the lists, sign-in closed, everything they did kept';
            END;
        END IF;
        IF outcome = 'DEACTIVATE' THEN
            v_grants := coalesce((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'office', a.office_code, 'valid_to_before', a.valid_to,
                                                                      'valid_to_set', greatest(a.valid_from, current_date - 1)))
                                    FROM iam.office_assignment a
                                   WHERE a.person_id = v_id AND (a.valid_to IS NULL OR a.valid_to >= current_date)), '[]'::jsonb);
            UPDATE iam.office_assignment a SET valid_to = greatest(a.valid_from, current_date - 1)
             WHERE a.person_id = v_id AND (a.valid_to IS NULL OR a.valid_to >= current_date);
            UPDATE iam.person x SET ended_on = current_date,
                   ended_reason = left(iam.staff_reason_words(v_code) || coalesce(': ' || v_reason, ''), 300)
             WHERE x.id = v_id;
            UPDATE platform.session s SET ended_at = now(), ended_reason = 'Staff deactivated'
             WHERE s.person_id = v_id AND s.ended_at IS NULL;
        END IF;
        INSERT INTO iam.staff_change (person_id, staff_number, name, category, action, reason_code, reason, ties, before_state, grants_ended,
                                      batch, actor, actor_office)
        VALUES (v_id, p.staff_number, name, v_cat, CASE outcome WHEN 'REMOVE' THEN 'STAFF_REMOVED' ELSE 'STAFF_DEACTIVATED' END,
                v_code, v_reason, v_ties, v_before, CASE WHEN outcome = 'DEACTIVATE' THEN v_grants ELSE '[]'::jsonb END, v_batch, v_actor, v_office)
        RETURNING id INTO v_change;
        applied := true; change_id := v_change;
        RETURN NEXT;
    END LOOP;
END $$;
COMMENT ON FUNCTION iam.remove_staff(uuid[], text, text, text, boolean) IS
  'V656: staff removed or deactivated — AUTO (deleted where tied to nothing, deactivated otherwise), REMOVE (deleted only where tied to nothing), DEACTIVATE; refused for oneself, a holder of another live office, a student, one already ended, one not on the staff register, or by an office that may not; a preview without apply; a reason required; each kept on iam.staff_change.';

-- ── 5 · a deactivation undone ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION iam.restore_staff(p_change uuid, p_reason_code text, p_reason text)
RETURNS TABLE (person_id uuid, name text, grants_reopened integer, change_id uuid)
LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_code text := upper(nullif(btrim(coalesce(p_reason_code, '')), ''));
        v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        c record; g jsonb; v_n integer := 0; v_new uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'STAFF_ACTOR: a change to the staff register is made by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM iam.staff_change x WHERE x.id = p_change FOR UPDATE;
    IF NOT FOUND OR c.action <> 'STAFF_DEACTIVATED' THEN
        RAISE EXCEPTION 'STAFF_NOT_DEACTIVATED: only a deactivation can be undone; a deleted person is added again' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM iam.staff_change x WHERE x.restores = p_change) THEN
        RAISE EXCEPTION 'STAFF_RESTORED: that deactivation has already been undone' USING ERRCODE = '23514';
    END IF;
    IF NOT iam.staff_change_may(v_office, c.category) THEN
        RAISE EXCEPTION 'STAFF_NOT_PERMITTED: your office may not restore this member of staff' USING ERRCODE = '42501';
    END IF;
    IF v_code IS NULL OR v_code NOT IN ('DEACTIVATED_IN_ERROR', 'RETURNED_TO_SERVICE', 'OTHER') THEN
        RAISE EXCEPTION 'STAFF_REASON: say why — deactivated in error, returned to service, or other' USING ERRCODE = '23514';
    END IF;
    IF v_code = 'OTHER' AND length(coalesce(v_reason, '')) < 10 THEN
        RAISE EXCEPTION 'STAFF_REASON_OTHER: describe the reason in a few words' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.person pe WHERE pe.id = c.person_id AND pe.ended_on IS NOT NULL) THEN
        RAISE EXCEPTION 'STAFF_NOT_ENDED: that member of staff is not deactivated now' USING ERRCODE = '23514';
    END IF;
    UPDATE iam.person pe SET ended_on = NULL, ended_reason = NULL WHERE pe.id = c.person_id;
    -- the grants the deactivation ended, reopened to the end each had, where nobody has changed them since
    FOR g IN SELECT * FROM jsonb_array_elements(c.grants_ended) LOOP
        UPDATE iam.office_assignment a SET valid_to = nullif(g->>'valid_to_before', '')::date
         WHERE a.id = (g->>'id')::uuid AND a.valid_to IS NOT DISTINCT FROM nullif(g->>'valid_to_set', '')::date;
        IF FOUND THEN v_n := v_n + 1; END IF;
    END LOOP;
    INSERT INTO iam.staff_change (person_id, staff_number, name, category, action, reason_code, reason, ties, before_state, restores, batch, actor, actor_office)
    VALUES (c.person_id, c.staff_number, c.name, c.category, 'STAFF_RESTORED', v_code, v_reason, '[]'::jsonb, iam.staff_snapshot(c.person_id),
            p_change, gen_random_uuid(), v_actor, v_office)
    RETURNING id INTO v_new;
    person_id := c.person_id; name := c.name; grants_reopened := v_n; change_id := v_new;
    RETURN NEXT;
END $$;
COMMENT ON FUNCTION iam.restore_staff(uuid, text, text) IS
  'V656: a deactivation undone — the person back on the lists and able to sign in, the grants it ended reopened to the end each had (where unchanged since); once, with a reason; kept on iam.staff_change.';

-- ── 6 · the removed and deactivated staff ──────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION iam.staff_changes(p_category text)
RETURNS TABLE (id uuid, person_id uuid, staff_number text, name text, category text, action text, reason_code text, reason_words text,
               reason text, ties jsonb, actor_name text, actor_office text, at timestamptz, restorable boolean, restored_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT c.id, c.person_id, c.staff_number, c.name, c.category, c.action, c.reason_code, iam.staff_reason_words(c.reason_code),
           c.reason, c.ties, nullif(btrim(coalesce(a.surname, '') || ', ' || coalesce(a.given_names, ''), ', '), ''), c.actor_office, c.at,
           (c.action = 'STAFF_DEACTIVATED' AND r.id IS NULL AND EXISTS (SELECT 1 FROM iam.person pe WHERE pe.id = c.person_id AND pe.ended_on IS NOT NULL)),
           r.at
      FROM iam.staff_change c
      LEFT JOIN iam.person a ON a.id = c.actor
      LEFT JOIN iam.staff_change r ON r.restores = c.id
     WHERE (p_category IS NULL OR c.category = upper(p_category))
     ORDER BY c.at DESC
     LIMIT 2000
$$;
COMMENT ON FUNCTION iam.staff_changes(text) IS
  'V656: the staff removed, deactivated and restored, newest first, each deactivation saying whether it can be restored and when it was.';

COMMENT ON FUNCTION iam.delete_lecturers(uuid[]) IS
  'V138, superseded by V656 iam.remove_staff (a person tied to records is deactivated, never deleted; a reason kept). No longer called by the API.';

COMMIT;

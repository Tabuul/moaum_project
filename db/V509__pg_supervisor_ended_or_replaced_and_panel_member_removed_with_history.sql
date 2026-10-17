-- ═══════════════════════════════════════
-- V509 — A PG supervisor ended or replaced, and a panel member removed, with the date, the reason and the history kept
--
--   The School added a supervisor and a panel member but could neither end nor replace a supervisor, nor take a member off the
--   panel (PRD FR-PG-05). Now, by the School of Postgraduate Studies (pgschool, pgsecretary; super as break-glass):
--   · admissions.pg_end_supervisor — a supervisor's supervision ends on a date (not before it began, not in the future) with a
--     reason; never the candidate's last first supervisor (replace them instead).
--   · admissions.pg_replace_supervisor — the supervisor ends and another takes the same role from the same date; the ended row
--     names its successor (replaced_by).
--   · admissions.pg_remove_panel_member — a member leaves the panel on a date with a reason, with an optional replacement in the
--     same role; never once the viva has been held (the panel that examined is the record).
--   Every change is on the research log (pg_research_event) and the audit trail; the ended and removed rows stay, and the screens
--   read the live ones as before (ended_at / removed_at IS NULL). The candidate is told when a supervisor changes
--   (PG_SUPERVISOR_CHANGED).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V509: PG supervisor ended or replaced and panel member removed, with history', true);

ALTER TABLE admissions.pg_research_supervisor
    ADD COLUMN ended_on     date NULL,
    ADD COLUMN end_reason   text NULL,
    ADD COLUMN ended_by     uuid NULL,
    ADD COLUMN ended_office text NULL,
    ADD COLUMN replaced_by  uuid NULL REFERENCES admissions.pg_research_supervisor(id);
-- a supervision ended from now on says when and why (rows ended before V509 keep what they had)
ALTER TABLE admissions.pg_research_supervisor
    ADD CONSTRAINT ck_pg_sup_end_said CHECK (ended_at IS NULL OR ended_on IS NULL OR length(btrim(coalesce(end_reason, ''))) >= 10) NOT VALID;
COMMENT ON COLUMN admissions.pg_research_supervisor.ended_on IS 'V509: the day the supervision ended, as the School states it (ended_at is when it was recorded)';
COMMENT ON COLUMN admissions.pg_research_supervisor.replaced_by IS 'V509: the supervisor who took the role over from this one';

ALTER TABLE admissions.pg_research_panel
    ADD COLUMN removed_at     timestamptz NULL,
    ADD COLUMN removed_on     date NULL,
    ADD COLUMN removed_reason text NULL,
    ADD COLUMN removed_by     uuid NULL,
    ADD COLUMN removed_office text NULL,
    ADD COLUMN replaced_by    uuid NULL REFERENCES admissions.pg_research_panel(id),
    ADD CONSTRAINT ck_pg_panel_removed_said CHECK (removed_at IS NULL OR (removed_on IS NOT NULL AND length(btrim(coalesce(removed_reason, ''))) >= 10));
COMMENT ON COLUMN admissions.pg_research_panel.removed_at IS 'V509: when the member was taken off the panel (NULL while a member); removed_on, removed_reason say when and why';
CREATE INDEX ix_pg_panel_live ON admissions.pg_research_panel (research_id) WHERE removed_at IS NULL;

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PG_SUPERVISOR_CHANGED', 'Your supervisor changed',
 'To the postgraduate candidate whose supervisor the School of Postgraduate Studies ends or replaces (V509)',
 'Your [ROLE] supervisor has changed',
 E'Dear [FIRST_NAME],\n\n[OLD] is no longer your [ROLE] supervisor from [ON]. [NEW]\n\nThe School of Postgraduate Studies: [REASON]\n\nYour supervisors are on the portal: [PORTAL_URL]\n\nSchool of Postgraduate Studies, [UNIVERSITY_NAME]',
 'MOAUM: [OLD] is no longer your [ROLE] supervisor from [ON]. [NEW]',
 'Your supervisor changed',
 '[OLD] is no longer your [ROLE] supervisor from [ON]. [NEW] [REASON]',
 ARRAY['FIRST_NAME','ROLE','OLD','NEW','ON','REASON','PORTAL_URL','UNIVERSITY_NAME'], true, 'NORMAL');

-- the School's offices, and a date the School may state (not in the future, not before the start)
CREATE FUNCTION admissions.pg_school_check(p_on date, p_from timestamptz, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') NOT IN ('pgschool', 'pgsecretary', 'super') THEN
        RAISE EXCEPTION 'PG_RESEARCH_SCHOOL: supervisors and the panel are changed by the School of Postgraduate Studies' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PG_CHANGE_REASON: say why, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF p_on IS NULL OR p_on > current_date THEN
        RAISE EXCEPTION 'PG_CHANGE_DATE: the change takes effect today or on an earlier day, not a future one' USING ERRCODE = '23514';
    END IF;
    IF p_from IS NOT NULL AND p_on < (p_from AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'PG_CHANGE_DATE: the change cannot take effect before % (when the role began)', to_char(p_from AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') USING ERRCODE = '23514';
    END IF;
END $$;

CREATE FUNCTION admissions.pg_role_words(p_role text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_role WHEN 'FIRST' THEN 'first' WHEN 'SECOND' THEN 'second' WHEN 'CO' THEN 'co-' ELSE lower(p_role) END
$$;

CREATE FUNCTION admissions.pg_tell_supervisor_change(p_research uuid, p_role text, p_old text, p_new text, p_on date, p_reason text, p_key text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_student uuid;
BEGIN
    SELECT r.student_id INTO v_student FROM admissions.pg_research r WHERE r.id = p_research;
    IF v_student IS NULL THEN RETURN; END IF;
    PERFORM platform.tell_student(v_student, 'PG_SUPERVISOR_CHANGED', NULL,
        jsonb_build_object('ROLE', admissions.pg_role_words(p_role), 'OLD', p_old, 'ON', to_char(p_on, 'DD Mon YYYY'),
                           'NEW', CASE WHEN p_new IS NULL THEN 'The School will name who takes the role over.' ELSE p_new || ' takes the role over.' END,
                           'REASON', btrim(p_reason)),
        p_key);
END $$;

CREATE FUNCTION admissions.pg_end_supervisor(p_supervisor uuid, p_on date, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE s admissions.pg_research_supervisor; v_stage text;
BEGIN
    SELECT * INTO s FROM admissions.pg_research_supervisor WHERE id = p_supervisor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PG_SUP_NOT_FOUND: no such supervisor' USING ERRCODE = '23503'; END IF;
    PERFORM admissions.pg_school_check(p_on, s.assigned_at, p_reason);
    IF s.ended_at IS NOT NULL THEN
        RAISE EXCEPTION 'PG_SUP_ENDED: this supervision has already ended' USING ERRCODE = '23514';
    END IF;
    SELECT r.stage INTO v_stage FROM admissions.pg_research r WHERE r.id = s.research_id FOR UPDATE;
    IF v_stage IN ('AWARDED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'PG_SUP_CLOSED: the research record is %; its supervision is history', lower(v_stage) USING ERRCODE = '23514';
    END IF;
    IF s.role = 'FIRST' AND NOT EXISTS (SELECT 1 FROM admissions.pg_research_supervisor o
                                         WHERE o.research_id = s.research_id AND o.role = 'FIRST' AND o.ended_at IS NULL AND o.id <> s.id) THEN
        RAISE EXCEPTION 'PG_SUP_LAST_FIRST: a candidate always has a first supervisor; replace % instead of ending the supervision', s.name USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.pg_research_supervisor SET ended_at = now(), ended_on = p_on, end_reason = btrim(p_reason),
           ended_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, ended_office = current_setting('moaum.actor_office', true)
     WHERE id = s.id;
    INSERT INTO admissions.pg_research_event (research_id, stage, note)
    VALUES (s.research_id, 'SUPERVISOR_ENDED', s.name || ' no longer ' || admissions.pg_role_words(s.role) || ' supervisor from ' || to_char(p_on, 'DD Mon YYYY') || ' — ' || btrim(p_reason));
    PERFORM admissions.pg_tell_supervisor_change(s.research_id, s.role, s.name, NULL, p_on, p_reason, 'PG_SUPERVISOR_CHANGED:' || s.id);
    RETURN s.id;
END $$;
COMMENT ON FUNCTION admissions.pg_end_supervisor(uuid, date, text) IS
  'V509: the School ends a supervision on a date (not in the future, not before it began) with a reason; never the candidate''s last first supervisor, never on an awarded or withdrawn record; logged, the candidate told';

CREATE FUNCTION admissions.pg_replace_supervisor(p_supervisor uuid, p_name text, p_person uuid, p_external boolean, p_on date, p_reason text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE s admissions.pg_research_supervisor; v_stage text; v_new uuid; v_name text := btrim(coalesce(p_name, ''));
BEGIN
    SELECT * INTO s FROM admissions.pg_research_supervisor WHERE id = p_supervisor FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PG_SUP_NOT_FOUND: no such supervisor' USING ERRCODE = '23503'; END IF;
    PERFORM admissions.pg_school_check(p_on, s.assigned_at, p_reason);
    IF s.ended_at IS NOT NULL THEN
        RAISE EXCEPTION 'PG_SUP_ENDED: this supervision has already ended' USING ERRCODE = '23514';
    END IF;
    IF length(v_name) < 3 THEN
        RAISE EXCEPTION 'PG_SUP_NAME: name the supervisor who takes the role over' USING ERRCODE = '23514';
    END IF;
    IF upper(v_name) = upper(btrim(s.name)) AND p_person IS NOT DISTINCT FROM s.person_id THEN
        RAISE EXCEPTION 'PG_SUP_SAME: % is already the % supervisor', s.name, admissions.pg_role_words(s.role) USING ERRCODE = '23514';
    END IF;
    SELECT r.stage INTO v_stage FROM admissions.pg_research r WHERE r.id = s.research_id FOR UPDATE;
    IF v_stage IN ('AWARDED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'PG_SUP_CLOSED: the research record is %; its supervision is history', lower(v_stage) USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.pg_research_supervisor (research_id, person_id, name, role, is_external, assigned_at)
    VALUES (s.research_id, p_person, v_name, s.role, coalesce(p_external, false),
            CASE WHEN p_on = current_date THEN now() ELSE p_on::timestamp AT TIME ZONE 'Africa/Lagos' END)
    RETURNING id INTO v_new;
    UPDATE admissions.pg_research_supervisor SET ended_at = now(), ended_on = p_on, end_reason = btrim(p_reason), replaced_by = v_new,
           ended_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, ended_office = current_setting('moaum.actor_office', true)
     WHERE id = s.id;
    INSERT INTO admissions.pg_research_event (research_id, stage, note)
    VALUES (s.research_id, 'SUPERVISOR_REPLACED', v_name || ' replaces ' || s.name || ' as ' || admissions.pg_role_words(s.role) || ' supervisor from '
            || to_char(p_on, 'DD Mon YYYY') || ' — ' || btrim(p_reason));
    PERFORM admissions.pg_tell_supervisor_change(s.research_id, s.role, s.name, v_name, p_on, p_reason, 'PG_SUPERVISOR_CHANGED:' || s.id);
    RETURN v_new;
END $$;
COMMENT ON FUNCTION admissions.pg_replace_supervisor(uuid, text, uuid, boolean, date, text) IS
  'V509: the School replaces a supervisor — the supervision ends on the date and another takes the same role (the ended row names its successor); logged, the candidate told';

CREATE FUNCTION admissions.pg_remove_panel_member(p_member uuid, p_on date, p_reason text, p_replacement text, p_external boolean)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE m admissions.pg_research_panel; v_stage text; v_new uuid; v_rep text := nullif(btrim(coalesce(p_replacement, '')), '');
BEGIN
    SELECT * INTO m FROM admissions.pg_research_panel WHERE id = p_member FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'PG_PANEL_NOT_FOUND: no such panel member' USING ERRCODE = '23503'; END IF;
    PERFORM admissions.pg_school_check(p_on, m.added_at, p_reason);
    IF m.removed_at IS NOT NULL THEN
        RAISE EXCEPTION 'PG_PANEL_REMOVED: % is already off the panel', m.name USING ERRCODE = '23514';
    END IF;
    SELECT r.stage INTO v_stage FROM admissions.pg_research r WHERE r.id = m.research_id FOR UPDATE;
    IF v_stage IN ('VIVA_HELD', 'CORRECTIONS', 'FINAL_SUBMITTED', 'CLEARED', 'AWARD_RECOMMENDED', 'AWARDED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'PG_PANEL_EXAMINED: the viva has been held; the panel that examined is the record and is not changed' USING ERRCODE = '23514';
    END IF;
    IF v_rep IS NOT NULL THEN
        IF length(v_rep) < 3 OR upper(v_rep) = upper(btrim(m.name)) THEN
            RAISE EXCEPTION 'PG_PANEL_NAME: name another member for the role' USING ERRCODE = '23514';
        END IF;
        INSERT INTO admissions.pg_research_panel (research_id, name, role, is_external) VALUES (m.research_id, v_rep, m.role, coalesce(p_external, false))
        RETURNING id INTO v_new;
    END IF;
    UPDATE admissions.pg_research_panel SET removed_at = now(), removed_on = p_on, removed_reason = btrim(p_reason), replaced_by = v_new,
           removed_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, removed_office = current_setting('moaum.actor_office', true)
     WHERE id = m.id;
    INSERT INTO admissions.pg_research_event (research_id, stage, note)
    VALUES (m.research_id, 'PANEL_CHANGED', m.name || ' off the panel (' || lower(replace(m.role, '_', ' ')) || ') from ' || to_char(p_on, 'DD Mon YYYY')
            || coalesce('; ' || v_rep || ' in the role', '') || ' — ' || btrim(p_reason));
    RETURN coalesce(v_new, m.id);
END $$;
COMMENT ON FUNCTION admissions.pg_remove_panel_member(uuid, date, text, text, boolean) IS
  'V509: the School takes a member off the panel of examiners on a date with a reason, optionally naming another in the same role; never once the viva has been held; logged';

COMMIT;

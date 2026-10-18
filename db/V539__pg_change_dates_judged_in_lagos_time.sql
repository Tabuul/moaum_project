-- ═══════════════════════════════════════
-- V539 — A postgraduate supervisor or panel change dated today is today in Lagos, whatever the hour
--
--   V509's rule (admissions.pg_school_check) took "today" from the database's own clock (current_date, UTC on Railway, on AWS
--   and in CI) but the day a role began in Lagos time. From midnight to one o'clock in Lagos the two are a day apart: the
--   School of Postgraduate Studies could not record a change dated today ("not a future one"), a role that began that day
--   could not be changed at all, and any CI run in that hour failed V509's check and PrdGapsIT (18 Oct 2026, 23:20 UTC, on
--   53c47e75). Both sides are now Lagos dates — the change date against today in Lagos, the start in Lagos — and a successor
--   appointed today starts now (admissions.pg_replace_supervisor). The functions are restated from V509's definitions with
--   that one change each.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'super', true),
       set_config('moaum.reason', 'V539: PG change dates judged in Lagos time', true);

CREATE OR REPLACE FUNCTION admissions.pg_school_check(p_on date, p_from timestamptz, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') NOT IN ('pgschool', 'pgsecretary', 'super') THEN
        RAISE EXCEPTION 'PG_RESEARCH_SCHOOL: supervisors and the panel are changed by the School of Postgraduate Studies' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'PG_CHANGE_REASON: say why, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    -- today is today in Lagos, not the database's UTC date (V539)
    IF p_on IS NULL OR p_on > (now() AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'PG_CHANGE_DATE: the change takes effect today or on an earlier day, not a future one' USING ERRCODE = '23514';
    END IF;
    IF p_from IS NOT NULL AND p_on < (p_from AT TIME ZONE 'Africa/Lagos')::date THEN
        RAISE EXCEPTION 'PG_CHANGE_DATE: the change cannot take effect before % (when the role began)', to_char(p_from AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') USING ERRCODE = '23514';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION admissions.pg_replace_supervisor(p_supervisor uuid, p_name text, p_person uuid, p_external boolean, p_on date, p_reason text)
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
            CASE WHEN p_on = (now() AT TIME ZONE 'Africa/Lagos')::date THEN now() ELSE p_on::timestamp AT TIME ZONE 'Africa/Lagos' END)
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

COMMIT;
